package main

// tmux.go — thin wrappers over the tmux CLI.
//
//	tmuxOutput / tmuxRun        return errors (caller decides)
//	mustTmuxOut / mustTmux      exit(1) on error, mirroring the Python helpers
//	                            whose CalledProcessError propagated uncaught
//	livePanes                   set of all live pane ids server-wide

import (
	"bytes"
	"errors"
	"fmt"
	"os/exec"
	"strings"
)

// tmuxOutput runs a tmux command and returns its trimmed stdout (and any error).
func tmuxOutput(args ...string) (string, error) {
	out, err := exec.Command("tmux", args...).Output()
	if err != nil {
		return strings.TrimSpace(string(out)), fmt.Errorf("tmux %v: %w", args, err)
	}

	return strings.TrimSpace(string(out)), nil
}

// tmuxRun runs a tmux command for its side effects, returning any error.
func tmuxRun(args ...string) error {
	if err := exec.Command("tmux", args...).Run(); err != nil {
		return fmt.Errorf("tmux %v: %w", args, err)
	}

	return nil
}

// tmuxResult runs a tmux command and reports its stderr and exit code. Used
// where we need to branch on a specific failure (e.g. "duplicate session").
func tmuxResult(args ...string) (stderr string, code int) {
	cmd := exec.Command("tmux", args...)

	var e bytes.Buffer

	cmd.Stderr = &e
	code = 0

	if err := cmd.Run(); err != nil {
		if ee, ok := errors.AsType[*exec.ExitError](err); ok {
			code = ee.ExitCode()
		} else {
			code = -1
		}
	}

	return strings.TrimSpace(e.String()), code
}

// mustTmux runs a tmux command and exits(1) on failure. Use for the call sites
// that in the Python original let CalledProcessError propagate (spawn/resurrect
// layout and send-keys, etc.).
func mustTmux(args ...string) {
	err := tmuxRun(args...)
	if err != nil {
		logErrorf("tmux %v failed: %v", args, err)
		exitErrf(1, "tmux error (%v): %v", args, err)
	}
}

// mustTmuxOut is mustTmux returning trimmed stdout.
func mustTmuxOut(args ...string) string {
	out, err := tmuxOutput(args...)
	if err != nil {
		logErrorf("tmux %v failed: %v", args, err)
		exitErrf(1, "tmux error (%v): %v", args, err)
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

	for line := range strings.SplitSeq(out, "\n") {
		if line != "" {
			panes[line] = true
		}
	}

	logDebugf("livePanes: %d pane(s)", len(panes))

	return panes
}
