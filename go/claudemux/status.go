package main

// status.go — project scoping and status-row construction.
//
// State is keyed by project (one file per project; see state.go), so the "one
// project" confinement is simply *which file is loaded*: `status` reads the
// current project's file and shows every agent in it (including agents hired
// from other projects, whose cwd points elsewhere). `projectScope` is still
// used to derive that project key. buildRows is kept pure (deps injected) so it
// is unit-testable without tmux.

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

// buildRows is the pure core of status: given a project's agents and injected
// world-views, it derives the display rows, sorted by task for deterministic
// output. No cwd filter — the caller already chose which project's roster to
// show by selecting the state file.
func buildRows(win string, agents map[string]Agent, deps rowDeps) []StatusRow {
	rows := make([]StatusRow, 0, len(agents))

	for _, task := range slices.Sorted(maps.Keys(agents)) {
		meta := agents[task]
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

// liveRowDeps is the production rowDeps wired to tmux + Claude's on-disk state.
func liveRowDeps(statuses map[string]string) rowDeps {
	return rowDeps{
		panes:    livePanes(),
		statuses: statuses,
		hasResponse: func(m Agent) bool {
			_, ok := lastResponse(jsonlPath(m))
			return ok
		},
		paneCtx:  paneContext,
		waitKind: func(pane string) string { return classifyWait(capturePane(pane)) },
	}
}

// statusRowsFromState is the IO wrapper around buildRows for one project's
// state. When a master is recorded (via `init`), it is prepended as a row
// labelled `master` so the roster's head is visible alongside its agents.
func statusRowsFromState(st WinState, statuses map[string]string) []StatusRow {
	deps := liveRowDeps(statuses)

	rows := make([]StatusRow, 0, len(st.Agents)+1)

	if st.Master != nil {
		m := *st.Master
		pane := cmp.Or(m.PaneID, "?")
		live := deps.panes[pane]

		context := "-"
		if live {
			context = deps.paneCtx(pane)
		}

		rows = append(rows, StatusRow{
			Project: st.Window,
			Pane:    pane,
			Task:    "master",
			Session: cmp.Or(m.SessionID, "?"),
			Status:  deriveStatus(m, live, deps),
			Context: context,
		})
	}

	return append(rows, buildRows(st.Window, st.Agents, deps)...)
}
