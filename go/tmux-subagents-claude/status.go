package main

// status.go — project scoping and status-row construction.
//
// Status is keyed by window NAME (which can repeat across projects), so the
// real "one project" confinement is path-based: an agent belongs to the current
// view if its recorded cwd is inside the current git repo root (projectScope).
// buildRows is kept pure (deps injected) so it is unit-testable without tmux.

import (
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

// runGitToplevel returns `git -C cwd rev-parse --show-toplevel`. A package var
// so tests can stub it.
var runGitToplevel = func(cwd string) (string, bool) {
	out, err := exec.Command("git", "-C", cwd, "rev-parse", "--show-toplevel").Output()
	if err != nil {
		return "", false
	}
	return strings.TrimSpace(string(out)), true
}

// projectScope returns the git repo root containing cwd, or cwd if not in a
// repo (exact-cwd fallback).
func projectScope(cwd string) string {
	if root, ok := runGitToplevel(cwd); ok && root != "" {
		return root
	}
	return cwd
}

// realpath resolves a path to an absolute, symlink-free form (best effort). A
// package var so tests can replace it with identity.
var realpath = func(p string) string {
	if p == "" {
		return p
	}
	if abs, err := filepath.Abs(p); err == nil {
		p = abs
	}
	if resolved, err := filepath.EvalSymlinks(p); err == nil {
		return resolved
	}
	return p
}

// inScope reports whether agentCWD is scopeRoot or a subdirectory of it. The
// trailing separator guards the boundary so "/repo" excludes "/repo-other".
// An empty scopeRoot includes everything (used by `status --all`).
func inScope(agentCWD, scopeRoot string) bool {
	if scopeRoot == "" {
		return true
	}
	return agentCWD == scopeRoot ||
		strings.HasPrefix(agentCWD, scopeRoot+string(filepath.Separator))
}

// StatusRow is one row of the status table.
type StatusRow struct {
	Project string
	Pane    string
	Task    string
	Session string
	Status  string
	Context string
}

// buildRows is the pure core of status: given a window's agents and injected
// views of the world (live panes, session statuses, a hasResponse probe, a
// pane-context probe), it derives the display rows. scopeRoot "" = no filter.
// Rows are sorted by task for deterministic output.
func buildRows(
	win string,
	agents map[string]Agent,
	scopeRoot string,
	panes map[string]bool,
	statuses map[string]string,
	hasResponse func(Agent) bool,
	paneCtx func(string) string,
) []StatusRow {
	tasks := make([]string, 0, len(agents))
	for t := range agents {
		tasks = append(tasks, t)
	}
	sort.Strings(tasks)

	var rows []StatusRow
	for _, task := range tasks {
		meta := agents[task]
		if scopeRoot != "" && !inScope(realpath(meta.CWD), scopeRoot) {
			continue
		}
		sid := meta.SessionID
		if sid == "" {
			sid = "?"
		}
		pane := meta.PaneID
		if pane == "" {
			pane = "?"
		}
		live := panes[pane]
		// A live pane is never "dead"; a missing status just means it is still
		// starting (the claude session-status file lags briefly).
		status := "dead"
		if live {
			if s, ok := statuses[meta.SessionID]; ok {
				status = s
			} else {
				status = "starting"
			}
		}
		// Disambiguate the idle trap: idle with no completed reply yet = "empty"
		// (fresh / awaiting first prompt) vs "idle" (finished, output ready).
		if status == "idle" && !hasResponse(meta) {
			status = "empty"
		}
		context := "-"
		if live {
			context = paneCtx(pane)
		}
		logDebugf("status agent=%s pane=%s status=%s context=%s",
			agentNameFor(win, task, &meta), pane, status, context)
		rows = append(rows, StatusRow{win, pane, task, sid, status, context})
	}
	return rows
}

// statusRows is the IO wrapper around buildRows for one window.
func statusRows(win string, statuses map[string]string, scopeRoot string) []StatusRow {
	st := loadWin(win)
	panes := livePanes()
	return buildRows(win, st.Agents, scopeRoot, panes, statuses,
		func(m Agent) bool { _, ok := lastResponse(jsonlPath(m)); return ok },
		paneContext)
}
