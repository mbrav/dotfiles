package main

// tui.go — the fragile part: driving Claude's interactive TUI through tmux.
// Ported faithfully from the Python helpers; the hard-won behaviors are:
//   - height-only redraw nudge to deliver SIGWINCH and bottom-anchor the input
//   - bracketed paste (load-buffer + paste-buffer -p) to preserve newlines
//   - C-u only to clear the line — NEVER Escape (Esc-Esc opens the rewind modal)
//   - post-Enter verification with a one-shot retry

import (
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// capturePane snapshots a pane's visible content (last screenful); "" on error.
func capturePane(pane string) string {
	out, err := tmuxOutput("capture-pane", "-t", pane, "-p")
	if err != nil {
		return ""
	}

	return out
}

// contextRe matches the context-window usage in Claude's footer, e.g.
// "... 90.0k/1000.0k (9.0%)" -> "90.0k/1000.0k (9.0%)".
var contextRe = regexp.MustCompile(`\d+(?:\.\d+)?k/\d+(?:\.\d+)?k\s*\(\d+(?:\.\d+)?%\)`)

// paneContext extracts the last context-window usage match from a pane footer,
// or "-" if none (pane starting/dead or footer not rendered).
func paneContext(pane string) string {
	match := ""

	for line := range strings.SplitSeq(capturePane(pane), "\n") {
		if m := contextRe.FindString(line); m != "" {
			match = strings.Join(strings.Fields(m), " ")
		}
	}

	if match == "" {
		return "-"
	}

	return match
}

func dur(seconds float64) time.Duration {
	return time.Duration(seconds * float64(time.Second))
}

// forceRedraw nudges the window height by one row and back, delivering SIGWINCH
// so Claude repaints full-height with its input box pinned to the bottom. Width
// is left unchanged so text never rewraps. Without this, a pane that grew after
// a layout rebalance leaves Claude's input box stranded mid-pane, which both
// eats pastes and defeats submit-verification.
func forceRedraw(pane string) {
	hs, err := tmuxOutput("display-message", "-p", "-t", pane, "#{window_height}")
	if err != nil {
		logWarnf("forceRedraw: failed to read height for pane %s: %v", pane, err)

		return
	}

	h, err := strconv.Atoi(hs)
	if err != nil {
		logWarnf("forceRedraw: bad height %q for pane %s", hs, pane)

		return
	}

	if err := tmuxRun("resize-window", "-t", pane, "-y", strconv.Itoa(h-1)); err != nil {
		logWarnf("forceRedraw: resize failed for pane %s: %v", pane, err)

		return
	}

	sleep(cfg.RedrawSettle)

	_ = tmuxRun("resize-window", "-t", pane, "-y", strconv.Itoa(h))

	sleep(cfg.RedrawAfter)
}

// pasteText pastes text via tmux load-buffer + paste-buffer -p (bracketed
// paste), so multiline prompts arrive as one block instead of being split into
// separate submissions by embedded newlines.
func pasteText(pane, text string) {
	buf := "sp_" + strconv.FormatInt(time.Now().UnixMilli(), 10)
	load := exec.Command("tmux", "load-buffer", "-b", buf, "-")

	load.Stdin = strings.NewReader(text)
	if err := load.Run(); err != nil {
		logErrorf("pasteText: load-buffer failed: %v", err)
		exitErrf(1, "tmux load-buffer failed: %v", err)
	}

	mustTmux("paste-buffer", "-p", "-t", pane, "-b", buf)
	_ = tmuxRun("delete-buffer", "-b", buf)
}

// resetInputLine clears Claude's input line with a single C-u. It deliberately
// does NOT send Escape: in current Claude (v2.1.x) Esc-Esc opens the
// rewind/checkpoint modal, so a paste would land in that menu and never submit.
func resetInputLine(pane string) {
	mustTmux("send-keys", "-t", pane, "C-u")
	sleep(cfg.ResetSettle)
}

// verifySubmittedFrom is the pure verifier: given a captured snapshot and the
// submitted text, it reports whether the text is no longer sitting on the input
// line (i.e. submission succeeded). Trailing blank lines are dropped first so a
// box with dead space below the footer doesn't mask an unsubmitted prompt.
func verifySubmittedFrom(snapshot, text string, tailLines, needleLen int) bool {
	ts := strings.TrimSpace(text)
	if ts == "" {
		return true
	}

	lines := strings.Split(ts, "\n")
	lastLine := lines[len(lines)-1]

	runes := []rune(lastLine)
	if len(runes) > needleLen {
		runes = runes[len(runes)-needleLen:]
	}

	needle := string(runes)
	if needle == "" {
		return true
	}

	snap := strings.Split(snapshot, "\n")
	for len(snap) > 0 && strings.TrimSpace(snap[len(snap)-1]) == "" {
		snap = snap[:len(snap)-1]
	}

	start := max(len(snap)-tailLines, 0)

	tail := strings.Join(snap[start:], "\n")

	return !strings.Contains(tail, needle)
}

// verifySubmitted captures the pane and runs the pure verifier.
func verifySubmitted(pane, text string) bool {
	sleep(cfg.VerifySettle)

	return verifySubmittedFrom(capturePane(pane), text, cfg.VerifyTailLines, cfg.VerifyNeedleLen)
}

// sendPrompt resets, pastes, submits, and (optionally) verifies with one retry.
// Returns true on success.
func sendPrompt(pane, text string, verify bool) bool {
	// Repaint first so the input box is bottom-anchored: a mid-pane box silently
	// eats pastes and defeats verification.
	forceRedraw(pane)
	resetInputLine(pane)
	pasteText(pane, text)
	sleep(cfg.PasteSettle)
	mustTmux("send-keys", "-t", pane, "Enter")

	if !verify {
		return true
	}

	if verifySubmitted(pane, text) {
		return true
	}

	logWarnf("prompt verify failed once, retrying")
	resetInputLine(pane)
	pasteText(pane, text)
	sleep(cfg.PasteSettle)
	mustTmux("send-keys", "-t", pane, "Enter")

	return verifySubmitted(pane, text)
}

// waitForPromptReady polls a freshly launched pane for Claude's ❯ prompt, up to
// SpawnReadyTimeout. Returns false on timeout or if the pane vanishes.
func waitForPromptReady(pane string) bool {
	deadline := time.Now().Add(dur(cfg.SpawnReadyTimeout))
	for time.Now().Before(deadline) {
		sleep(cfg.SpawnPoll)

		out, err := tmuxOutput("capture-pane", "-t", pane, "-p")
		if err != nil {
			logWarnf("waitForPromptReady: pane %s vanished", pane)

			return false
		}

		if strings.Contains(out, "❯") {
			return true
		}
	}

	return false
}
