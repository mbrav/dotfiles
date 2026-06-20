package main

// status.go — project scoping and status-row construction.
//
// Status is keyed by window NAME (which can repeat across projects), so the
// real "one project" confinement is path-based: an agent belongs to the current
// view if its recorded cwd is inside the current git repo root (projectScope).
// buildRows is kept pure (deps injected) so it is unit-testable without tmux.

import (
	"cmp"
	"maps"
	"os/exec"
	"path/filepath"
	"slices"
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

// rowDeps are the injected views of the world buildRows needs. Bundling them
// keeps buildRows pure (testable without tmux/filesystem) and within the
// ≤4-parameter guideline.
type rowDeps struct {
	panes       map[string]bool     // live pane ids
	statuses    map[string]string   // sessionID -> status
	hasResponse func(Agent) bool    // does the transcript hold a completed reply?
	paneCtx     func(string) string // pane id -> context-window usage string
	waitKind    func(string) string // pane id -> waiting sub-kind (e.g. "permission"), "" if none
}

// deriveStatus maps a pane's liveness and session status into a display status.
// A dead pane is "dead"; a live pane with no session-status file yet is
// "starting" (the file lags briefly); idle-with-no-completed-reply is "empty"
// (fresh / awaiting first prompt) to disambiguate the idle trap.
func deriveStatus(meta Agent, live bool, deps rowDeps) string {
	if !live {
		return "dead"
	}

	status, ok := deps.statuses[meta.SessionID]
	if !ok {
		return "starting"
	}

	if status == "idle" && !deps.hasResponse(meta) {
		return "empty"
	}

	return status
}

// buildRows is the pure core of status: given a window's agents and injected
// world-views, it derives the display rows. scopeRoot "" = no filter. Rows are
// sorted by task for deterministic output.
func buildRows(win string, agents map[string]Agent, scopeRoot string, deps rowDeps) []StatusRow {
	var rows []StatusRow

	for _, task := range slices.Sorted(maps.Keys(agents)) {
		meta := agents[task]
		if scopeRoot != "" && !inScope(realpath(meta.CWD), scopeRoot) {
			continue
		}

		pane := cmp.Or(meta.PaneID, "?")
		live := deps.panes[pane]

		context := "-"
		if live {
			context = deps.paneCtx(pane)
		}

		status := deriveStatus(meta, live, deps)
		// Refine a bare `waiting` into e.g. `waiting:permission` when the pane is
		// sitting on an interactive dialog only a human can answer. Only the few
		// waiting panes pay the extra capture.
		if status == "waiting" && live && deps.waitKind != nil {
			if kind := deps.waitKind(pane); kind != "" {
				status += ":" + kind
			}
		}

		logDebugf("status agent=%s pane=%s status=%s context=%s",
			agentNameFor(win, task, &meta), pane, status, context)
		rows = append(rows, StatusRow{
			Project: win,
			Pane:    pane,
			Task:    task,
			Session: cmp.Or(meta.SessionID, "?"),
			Status:  status,
			Context: context,
		})
	}

	return rows
}

// statusRows is the IO wrapper around buildRows for one window.
func statusRows(win string, statuses map[string]string, scopeRoot string) []StatusRow {
	st := loadWin(win)

	return buildRows(win, st.Agents, scopeRoot, rowDeps{
		panes:    livePanes(),
		statuses: statuses,
		hasResponse: func(m Agent) bool {
			_, ok := lastResponse(jsonlPath(m))
			return ok
		},
		paneCtx:  paneContext,
		waitKind: func(pane string) string { return classifyWait(capturePane(pane)) },
	})
}
