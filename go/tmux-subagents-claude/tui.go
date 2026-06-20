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

// classifyWait refines a bare `waiting` status by inspecting a pane snapshot for
// the signature of Claude's interactive permission dialog ("Do you want to
// proceed?" with numbered options and an "Esc to cancel" footer). Returns
// "permission" on a match, else "". A detached pane has no one to answer such a
// dialog, so surfacing `waiting:permission` tells the operator a keystroke is
// needed — something the JSONL transcript cannot reveal (the gated tool_use is
// not flushed while pending). Pure (snapshot in, no IO) so it is unit-testable.
func classifyWait(snapshot string) string {
	if strings.Contains(snapshot, "Do you want to proceed?") &&
		strings.Contains(snapshot, "Esc to cancel") {
		return "permission"
	}

	return ""
}

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

// redrawWindowPanes forces every pane in a window to repaint after a layout
// change. select-layout rebalances pane *widths*, but Claude's TUI (v2.1.x)
// only reliably reflows on a width SIGWINCH, so the panes must be jolted.
//
// The window can also be stuck at a phantom size — e.g. left over from a
// transient display-popup client that has since detached — that automatic
// resizing won't correct on its own. A manual `-x <width>` nudge can't escape
// that: under window-size=latest + aggressive-resize tmux clamps a manual width
// back, and the old nudge read the *stuck* width and resized around it, never
// reaching the size the viewing client actually wants.
//
// `resize-window -A` instead snaps the window to its *automatic* size — the
// largest client for which it is the current window — which both escapes a stuck
// size and is the size tmux genuinely wants. We then nudge one column narrower
// and snap back with `-A`, guaranteeing a width SIGWINCH cycle to every pane even
// when the window was already correctly sized. Cosmetic only — orchestration
// reads per-pane grids and is unaffected.
func redrawWindowPanes(target string) {
	if err := tmuxRun("resize-window", "-t", target, "-A"); err != nil {
		logWarnf("redrawWindowPanes: auto-resize failed for %s: %v", target, err)

		return
	}

	sleep(cfg.RedrawSettle)

	ws, err := tmuxOutput("display-message", "-p", "-t", target, "#{window_width}")
	if err != nil {
		logWarnf("redrawWindowPanes: failed to read width for %s: %v", target, err)

		return
	}

	w, err := strconv.Atoi(ws)
	if err != nil {
		logWarnf("redrawWindowPanes: bad width %q for %s", ws, target)

		return
	}

	// Nudge one column narrower, then snap back to automatic, forcing a width
	// SIGWINCH even when the window was already at its automatic size.
	if err := tmuxRun("resize-window", "-t", target, "-x", strconv.Itoa(w-1)); err != nil {
		logWarnf("redrawWindowPanes: nudge failed for %s: %v", target, err)

		return
	}

	sleep(cfg.RedrawSettle)

	_ = tmuxRun("resize-window", "-t", target, "-A")

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
