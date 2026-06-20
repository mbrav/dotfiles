package main

// tmux.go — thin wrappers over the tmux CLI.
//
//	tmuxOutput / tmuxRun        return errors (caller decides)
//	mustTmuxOut / mustTmux      exit(1) on error, mirroring the Python helpers
//	                            whose CalledProcessError propagated uncaught
//	livePanes                   set of all live pane ids server-wide

import (
	"bytes"
	"os/exec"
	"strings"
)

// tmuxOutput runs a tmux command and returns its trimmed stdout (and any error).
func tmuxOutput(args ...string) (string, error) {
	out, err := exec.Command("tmux", args...).Output()
	return strings.TrimSpace(string(out)), err
}

// tmuxRun runs a tmux command for its side effects, returning any error.
func tmuxRun(args ...string) error {
	return exec.Command("tmux", args...).Run()
}

// tmuxResult runs a tmux command and reports stdout, stderr, and exit code.
// Used where we need to branch on a specific failure (e.g. "duplicate session").
func tmuxResult(args ...string) (stdout, stderr string, code int) {
	cmd := exec.Command("tmux", args...)
	var o, e bytes.Buffer
	cmd.Stdout = &o
	cmd.Stderr = &e
	err := cmd.Run()
	code = 0
	if err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			code = ee.ExitCode()
		} else {
			code = -1
		}
	}
	return strings.TrimSpace(o.String()), strings.TrimSpace(e.String()), code
}

// mustTmux runs a tmux command and exits(1) on failure. Use for the call sites
// that in the Python original let CalledProcessError propagate (spawn/resurrect
// layout and send-keys, etc.).
func mustTmux(args ...string) {
	if err := tmuxRun(args...); err != nil {
		logErrorf("tmux %v failed: %v", args, err)
		exitErr(1, "tmux error (%v): %v", args, err)
	}
}

// mustTmuxOut is mustTmux returning trimmed stdout.
func mustTmuxOut(args ...string) string {
	out, err := tmuxOutput(args...)
	if err != nil {
		logErrorf("tmux %v failed: %v", args, err)
		exitErr(1, "tmux error (%v): %v", args, err)
	}
	return out
}

// livePanes returns the set of all live pane ids across the tmux server.
func livePanes() map[string]bool {
	panes := map[string]bool{}
	out, err := tmuxOutput("list-panes", "-a", "-F", "#{pane_id}")
	if err != nil {
		logDebugf("livePanes: tmux error, returning empty set")
		return panes
	}
	for _, line := range strings.Split(out, "\n") {
		if line != "" {
			panes[line] = true
		}
	}
	logDebugf("livePanes: %d pane(s)", len(panes))
	return panes
}
