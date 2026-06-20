package main

// session.go — lifecycle of the detached `agents` session, its keeper anchor,
// and the per-source-window agent windows/panes.

import "strings"

// WindowTarget is the result of ensureAgentsWindow. InitialPane is only
// meaningful when Fresh is true (the pane created with the window).
type WindowTarget struct {
	Target      string // "agents:<window_id>"
	Fresh       bool   // true if the window was just created
	InitialPane string // pane id created with a fresh window
	WindowID    string // tmux window id (@N)
}

// ensureAgentsSession ensures the detached `agents` session exists, anchored by
// the persistent keeper window so it survives all agent panes exiting.
func ensureAgentsSession() {
	_, stderr, code := tmuxResult(
		"new-session", "-d", "-s", "agents", "-n", keeperWindow, keeperCmd(),
	)
	if code == 0 {
		logInfof("agents session created (keeper window: %s)", keeperWindow)
		// Detached new-session defaults to window-size manual; switch to latest
		// so panes resize to the attaching client instead of the creation size.
		_ = tmuxRun("set-option", "-t", "agents", "window-size", "latest")
		return
	}
	if strings.Contains(stderr, "duplicate session") {
		names := map[string]bool{}
		if out, err := tmuxOutput("list-windows", "-t", "agents", "-F", "#{window_name}"); err == nil {
			for _, n := range strings.Split(out, "\n") {
				if n != "" {
					names[n] = true
				}
			}
		}
		if !names[keeperWindow] {
			_, _, _ = tmuxResult("new-window", "-d", "-t", "agents", "-n", keeperWindow, keeperCmd())
			logInfof("keeper window added to existing agents session")
		} else {
			logDebugf("ensureAgentsSession: session exists, keeper present")
		}
		return
	}
	logErrorf("ensureAgentsSession: unexpected tmux error (rc=%d): %s", code, stderr)
	exitErr(1, "tmux new-session failed (rc=%d): %s", code, stderr)
}

// agentsWindowID returns the window id (@N) of the exact-named window in the
// agents session, and whether it was found.
func agentsWindowID(win string) (string, bool) {
	out, err := tmuxOutput("list-windows", "-t", "agents", "-F", "#{window_id} #{window_name}")
	if err != nil {
		logDebugf("agentsWindowID %s: agents session not found", win)
		return "", false
	}
	for _, line := range strings.Split(out, "\n") {
		wid, name, _ := strings.Cut(line, " ")
		if name == win {
			logDebugf("agentsWindowID %s -> %s", win, wid)
			return wid, true
		}
	}
	logDebugf("agentsWindowID %s -> not found", win)
	return "", false
}

// ensureAgentsWindow ensures the agents session and the window mirroring *win*
// exist. A freshly created window's first pane is opened in *cwd* (the cwd
// single-source-of-truth fix), matching the cwd stored in metadata so the
// transcript lands under the expected project-dir slug.
func ensureAgentsWindow(win, cwd string) WindowTarget {
	ensureAgentsSession()
	if winID, ok := agentsWindowID(win); ok {
		logDebugf("ensureAgentsWindow: window exists win=%s id=%s", win, winID)
		return WindowTarget{Target: "agents:" + winID, Fresh: false, WindowID: winID}
	}
	out := mustTmuxOut("new-window", "-t", "agents", "-n", win, "-c", cwd,
		"-P", "-F", "#{window_id} #{pane_id}")
	winID, paneID, _ := strings.Cut(out, " ")
	logInfof("agents window created: win=%s id=%s pane=%s", win, winID, paneID)
	return WindowTarget{Target: "agents:" + winID, Fresh: true, InitialPane: paneID, WindowID: winID}
}

// makeAgentPane returns the pane id to use for a new agent: the fresh window's
// initial pane, or a new split-window pane opened in *cwd* (cwd fix).
func makeAgentPane(wt WindowTarget, cwd string) string {
	if wt.Fresh {
		return wt.InitialPane
	}
	return mustTmuxOut("split-window", "-t", wt.Target, "-c", cwd, "-d", "-P", "-F", "#{pane_id}")
}
