package main

// state.go — window resolution + the consolidated per-project JSON state store.
//
// State is keyed by PROJECT, one file per project under STATE_DIR named with
// Claude's own ~/.claude/projects/ slug convention (every non-alphanumeric char
// -> "-", via cwdToProjectDir applied to the git-root/cwd). The window name is
// recorded inside for display; pane IDs are in-memory only (not persisted):
//
//	~/.local/share/claudemux/<project-slug>.json
//	{ "window": "obsidian",
//	  "master": {session_id, cwd, agent_name},   // optional, set by `promote`/`init`
//	  "agents": { "<task>": {session_id, cwd, agent_name, dismissed_at?} } }
//
// Per-project files each carrying a Master + Agents form a forest. PaneID is
// not persisted (tmux panes are ephemeral; they are re-discovered at runtime via
// findPaneForSession when needed).

import (
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"
)

// Agent is one tracked subagent (also reused for the master).
type Agent struct {
	// PaneID is in-process only: set at spawn/resurrect/enlist time, not
	// persisted. Stale pane IDs (tmux panes die on reboot) caused false "dead"
	// status; discovery via findPaneForSession is the recovery path.
	PaneID    string `json:"-"`
	SessionID string `json:"session_id"`
	CWD       string `json:"cwd"`
	AgentName string `json:"agent_name"`
	// Enlisted marks an agent adopted in place by `enlist`: the manager only
	// REFERENCES this pane (an independent session in its own window) and must
	// never kill it on despawn/dismiss.
	Enlisted bool `json:"enlisted,omitempty"`
	// DismissedAt is set (not nil) when the agent is soft-deleted via despawn or
	// dismiss. The entry stays in the roster so the session history is preserved;
	// `status` hides it by default and `despawn --prune` cleans it up.
	DismissedAt *time.Time `json:"dismissed_at,omitempty"`
}

// WinState is the full state for one project.
type WinState struct {
	Window string           `json:"window"`
	Master *Agent           `json:"master,omitempty"` // set by `promote`/`init`; absent otherwise
	Agents map[string]Agent `json:"agents"`
}

// getWin returns the calling tmux window's NAME, anchored to $TMUX_PANE so the
// result is independent of which window currently has focus. Requires
// `automatic-rename off` (tmux.conf) so names stay stable. Exits 1 if tmux
// can't be reached (mirrors the Python uncaught CalledProcessError).
func getWin() string {
	args := []string{"display-message", "-p"}
	if pane := os.Getenv("TMUX_PANE"); pane != "" {
		args = append(args, "-t", pane)
	}

	args = append(args, "#{window_name}")
	win := mustTmuxOut(args...)
	logDebugf("getWin -> %s (TMUX_PANE=%s)", win, envOr("TMUX_PANE", "<unset>"))

	return win
}

// projectKey is the state key for the current working directory's project: the
// git repo root (or cwd) encoded with Claude's projects/ slug convention. All
// commands from anywhere inside a repo resolve to the same key, so one project
// has exactly one roster file.
func projectKey() string {
	cwd, _ := os.Getwd()

	return projectKeyForDir(cwd)
}

// projectKeyForDir is projectKey for an arbitrary directory: the git repo root
// containing dir (or dir itself) encoded with Claude's projects/ slug
// convention. Used by `enlist`, where a worker names the manager's directory and
// must resolve it to the same key the manager's own commands produce.
func projectKeyForDir(dir string) string {
	key := cwdToProjectDir(realpath(projectScope(dir)))
	logDebugf("projectKeyForDir dir=%s -> %s", dir, key)

	return key
}

// stateFile is the state file path for a project key (creating STATE_DIR on
// demand).
func stateFile(key string) string {
	_ = os.MkdirAll(stateDir(), 0o755)

	return filepath.Join(stateDir(), key+".json")
}

// loadState loads a project's state, or an empty skeleton if absent/unreadable.
// Window is left as stored (callers stamp the current window name before save).
func loadState(key string) WinState {
	sf := stateFile(key)

	data, err := os.ReadFile(sf)
	if err != nil {
		logDebugf("loadState %s: no state file, returning empty", key)

		return WinState{Agents: map[string]Agent{}}
	}

	var st WinState
	if err := json.Unmarshal(data, &st); err != nil {
		logWarnf("loadState %s: parse error (%v), returning empty state", key, err)

		return WinState{Agents: map[string]Agent{}}
	}

	if st.Agents == nil {
		st.Agents = map[string]Agent{}
	}

	logDebugf("loadState %s: %d agent(s) from %s", key, len(st.Agents), sf)

	return st
}

// saveState persists a project's state (2-space indent, matching the prior format).
func saveState(key string, st WinState) {
	b, err := json.MarshalIndent(st, "", "  ")
	if err != nil {
		logErrorf("saveState %s: marshal error: %v", key, err)
		exitErrf(1, "failed to encode state for project %q: %v", key, err)
	}

	if err := os.WriteFile(stateFile(key), b, 0o644); err != nil {
		logErrorf("saveState %s: write error: %v", key, err)
		exitErrf(1, "failed to write state for project %q: %v", key, err)
	}

	logDebugf("saveState %s: %d agent(s) -> %s", key, len(st.Agents), stateFile(key))
}

// removeStateFile deletes a project's state file (ignoring "not found").
func removeStateFile(key string) {
	_ = os.Remove(stateFile(key))
}

// stateFileEntry is one window state file from iterStateFiles. State is nil if
// the file could not be read/parsed (callers decide: skip vs delete).
type stateFileEntry struct {
	Path  string
	State *WinState
}

// iterStateFiles returns every window state file under STATE_DIR, sorted by
// path. The single source of the per-window scan used by status and despawn
// --prune (previously duplicated).
func iterStateFiles() []stateFileEntry {
	dir := stateDir()

	matches, err := filepath.Glob(filepath.Join(dir, "*.json"))
	if err != nil {
		return nil
	}

	slices.Sort(matches)

	entries := make([]stateFileEntry, 0, len(matches))
	for _, p := range matches {
		data, err := os.ReadFile(p)
		if err != nil {
			entries = append(entries, stateFileEntry{Path: p})

			continue
		}

		var st WinState
		if err := json.Unmarshal(data, &st); err != nil {
			entries = append(entries, stateFileEntry{Path: p})

			continue
		}

		// Derive display name from the project slug when window is not stored.
		if st.Window == "" {
			st.Window = strings.TrimSuffix(filepath.Base(p), ".json")
		}

		if st.Agents == nil {
			st.Agents = map[string]Agent{}
		}

		entries = append(entries, stateFileEntry{Path: p, State: &st})
	}

	return entries
}
