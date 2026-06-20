package main

// state.go — window resolution + the consolidated per-window JSON state store.
//
// State is keyed by the source window's (stable, deduped) NAME, one file per
// window under STATE_DIR. The schema is frozen for compatibility with existing
// files and the agents.sh / Prefix+a tmux integration:
//
//	~/.local/share/tmux-subagents-claude/<winkey>.json
//	{ "window": "...", "agents_window_id": "@65",
//	  "agents": { "<task>": {pane_id, session_id, cwd, agent_name} } }

import (
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"strings"
)

// winNameReplacer makes a window name filesystem-safe: "/"->"-", " "->"_".
var winNameReplacer = strings.NewReplacer("/", "-", " ", "_")

// Agent is one tracked subagent. JSON tags are frozen (existing on-disk files).
type Agent struct {
	PaneID    string `json:"pane_id"`
	SessionID string `json:"session_id"`
	CWD       string `json:"cwd"`
	AgentName string `json:"agent_name"`
}

// WinState is the full state for one source window.
type WinState struct {
	Window         string           `json:"window"`
	AgentsWindowID string           `json:"agents_window_id"`
	Agents         map[string]Agent `json:"agents"`
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

// winKey is a filesystem-safe key for a window name.
func winKey(win string) string {
	return winNameReplacer.Replace(win)
}

// winFile is the state file path for a window (creating STATE_DIR on demand).
func winFile(win string) string {
	_ = os.MkdirAll(stateDir(), 0o755)

	return filepath.Join(stateDir(), winKey(win)+".json")
}

// loadWin loads a window's state, or an empty skeleton if absent/unreadable.
func loadWin(win string) WinState {
	sf := winFile(win)

	data, err := os.ReadFile(sf)
	if err != nil {
		logDebugf("loadWin %s: no state file, returning empty", win)

		return WinState{Window: win, Agents: map[string]Agent{}}
	}

	var st WinState
	if err := json.Unmarshal(data, &st); err != nil {
		logWarnf("loadWin %s: parse error (%v), returning empty state", win, err)

		return WinState{Window: win, Agents: map[string]Agent{}}
	}

	if st.Window == "" {
		st.Window = win
	}

	if st.Agents == nil {
		st.Agents = map[string]Agent{}
	}

	logDebugf("loadWin %s: %d agent(s) from %s", win, len(st.Agents), sf)

	return st
}

// saveWin persists a window's state (2-space indent, matching the prior format).
func saveWin(win string, st WinState) {
	b, err := json.MarshalIndent(st, "", "  ")
	if err != nil {
		logErrorf("saveWin %s: marshal error: %v", win, err)
		exitErrf(1, "failed to encode state for window %q: %v", win, err)
	}

	if err := os.WriteFile(winFile(win), b, 0o644); err != nil {
		logErrorf("saveWin %s: write error: %v", win, err)
		exitErrf(1, "failed to write state for window %q: %v", win, err)
	}

	logDebugf("saveWin %s: %d agent(s) -> %s", win, len(st.Agents), winFile(win))
}

// removeWinFile deletes a window's state file (ignoring "not found").
func removeWinFile(win string) {
	_ = os.Remove(winFile(win))
}

// stateFileEntry is one window state file from iterStateFiles. State is nil if
// the file could not be read/parsed (callers decide: skip vs delete).
type stateFileEntry struct {
	Path  string
	State *WinState
}

// iterStateFiles returns every window state file under STATE_DIR, sorted by
// path. The single source of the per-window scan used by status and cleanup
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
