package main

// commands.go — the nine subcommand handlers plus their bounded-wait helpers.
// All cwd handling flows from a single os.Getwd()/sessionCWD capture per command
// into both the pane (-c) and the stored metadata.

import (
	"crypto/rand"
	"encoding/json"
	"fmt"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"text/tabwriter"
	"time"
)

// newUUID returns a random RFC-4122 v4 UUID (stdlib only).
// TODO: Replace with uuid package once 1.27 comes out https://go.dev/doc/go1.27#uuid
func newUUID() string {
	var b [16]byte

	_, _ = rand.Read(b[:])
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80

	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

// ---------------------------------------------------------------------------
// spawn
// ---------------------------------------------------------------------------

func cmdSpawn(task, prompt, model, tools, effort, permMode string) {
	win := getWin()
	agentName := "subagent-" + win + "-" + task
	logInfof("spawn agent=%s", agentName)

	// cwd captured ONCE: it drives both the pane's working dir (-c) and the
	// stored metadata, so the transcript lands under the expected project slug.
	cwd, _ := os.Getwd()
	wt := ensureAgentsWindow(win, cwd)
	paneID := makeAgentPane(wt, cwd)
	logDebugf("spawn agent=%s pane=%s fresh_window=%v", agentName, paneID, wt.Fresh)

	sessionID := newUUID()
	st := loadWin(win)
	st.AgentsWindowID = wt.WindowID
	st.Agents[task] = Agent{PaneID: paneID, SessionID: sessionID, CWD: cwd, AgentName: agentName}
	saveWin(win, st)

	// Side-by-side horizontal layout: | Agent 1 | Agent 2 | Agent 3 |
	mustTmux("select-layout", "-t", wt.Target, "even-horizontal")

	// Start claude interactively; the prompt is pasted after startup (passing it
	// as a CLI arg makes claude treat it as a system prompt and stay idle).
	parts := []string{"claude", "--session-id", sessionID, "--name", agentName, "--permission-mode", permMode}
	if model != "" {
		parts = append(parts, "--model", model)
	}

	if tools != "" {
		parts = append(parts, "--allowedTools", tools)
	}

	if effort != "" {
		parts = append(parts, "--effort", effort)
	}

	cmdline := shellJoin(parts)
	logDebugf("spawn name=%s cmd: %s", agentName, cmdline)
	mustTmux("send-keys", "-t", paneID, cmdline, "Enter")

	if !waitForPromptReady(paneID) {
		logWarnf("spawn agent=%s ❯ never appeared within %.0fs (pane=%s)",
			agentName, cfg.SpawnReadyTimeout, paneID)
	}

	// Repaint so Claude bottom-anchors its input box before we paste.
	forceRedraw(paneID)
	pasteText(paneID, prompt)
	mustTmux("send-keys", "-t", paneID, "Enter")

	var extras []string
	if model != "" {
		extras = append(extras, "model="+model)
	}

	if tools != "" {
		extras = append(extras, "tools="+tools)
	}

	if effort != "" {
		extras = append(extras, "effort="+effort)
	}

	extras = append(extras, "perm="+permMode)
	extraStr := " [" + strings.Join(extras, ", ") + "]"
	logInfof("spawned agent=%s pane=%s session=%s%s", agentName, paneID, sessionID, extraStr)
	fmt.Printf("Spawned %s in pane %s (%s) [session: %s]%s\n",
		agentName, paneID, wt.Target, sessionID, extraStr)
}

// ---------------------------------------------------------------------------
// prompt
// ---------------------------------------------------------------------------

func cmdPrompt(task, text string, wait, verify bool) {
	win := getWin()
	ref := resolveAgent(win, task, true)
	logInfof("prompt agent=%s pane=%s verify=%v wait=%v", ref.Name, ref.PaneID, verify, wait)

	if !sendPrompt(ref.PaneID, text, verify) {
		logErrorf("prompt agent=%s NOT submitted — pane likely modal/stuck", ref.Name)
		exitErrf(2, "prompt-not-submitted: agent '%s' pane %s. "+
			"Pane may be in INSERT/modal state. Try `capture` to inspect, "+
			"or `cleanup <task>` + `resurrect <task> <session-id>` to reset.",
			ref.Name, ref.PaneID)
	}

	if wait {
		jsonl := jsonlPath(ref.Meta)
		baseline, _ := lastResponse(jsonl) // baseline so we wait for a NEW reply

		logInfof("prompt --wait agent=%s polling for new response", ref.Name)
		waitForNewResponse(ref.Name, jsonl, baseline)
	}
}

// ---------------------------------------------------------------------------
// result
// ---------------------------------------------------------------------------

func cmdResult(task string, wait bool) {
	win := getWin()
	ref := resolveAgent(win, task, false)
	sessionID := ref.Meta.SessionID
	jsonl := jsonlPath(ref.Meta)
	logDebugf("result agent=%s session=%s jsonl=%s wait=%v", ref.Name, sessionID, jsonl, wait)

	if wait {
		logInfof("result agent=%s waiting for response", ref.Name)
		stderrlnf("Waiting for response from '%s' (session: %s)...", ref.Name, sessionID)
		waitWhileBusy(ref.Name, sessionID, jsonl)

		return
	}

	res, ok := lastResponse(jsonl)
	if !ok {
		logInfof("result agent=%s no complete response yet", ref.Name)
		exitErrf(1, "No complete response yet for agent '%s' (session: %s)", ref.Name, sessionID)
	}

	logInfof("result agent=%s response found", ref.Name)
	fmt.Println(res)
}

// ---------------------------------------------------------------------------
// bounded --wait helpers (replace the old infinite while-True loops)
// ---------------------------------------------------------------------------

// waitDeadline returns the zero Time when WaitTimeout<=0 (infinite).
func waitDeadline() time.Time {
	if cfg.WaitTimeout <= 0 {
		return time.Time{}
	}

	return time.Now().Add(dur(cfg.WaitTimeout))
}

func timedOut(deadline time.Time) bool {
	return !deadline.IsZero() && !time.Now().Before(deadline)
}

// waitForNewResponse blocks until a NEW end_turn reply (differing from baseline)
// appears, then prints it. Exits 2 on timeout.
func waitForNewResponse(name, jsonl, baseline string) {
	deadline := waitDeadline()

	for {
		sleep(cfg.WaitPoll)

		cur, ok := lastResponse(jsonl)
		if ok && cur != baseline {
			fmt.Println(cur)

			return
		}

		if timedOut(deadline) {
			exitErrf(2, "wait-timeout: no new response from '%s' after %.0fs", name, cfg.WaitTimeout)
		}
	}
}

// waitWhileBusy blocks while the session is busy, then prints the latest reply.
// Exits 2 on timeout.
func waitWhileBusy(name, sessionID, jsonl string) {
	deadline := waitDeadline()

	for {
		status := "starting"
		if s, ok := sessionStatuses()[sessionID]; ok {
			status = s
		}

		res, ok := lastResponse(jsonl)
		if status != "busy" && ok {
			fmt.Println(res)

			return
		}

		if timedOut(deadline) {
			exitErrf(2, "wait-timeout: no response from '%s' after %.0fs (session: %s)",
				name, cfg.WaitTimeout, sessionID)
		}

		sleep(cfg.WaitPoll)
	}
}

// ---------------------------------------------------------------------------
// status
// ---------------------------------------------------------------------------

func cmdStatus(taskFilter string, all bool) {
	statuses := sessionStatuses()

	scopeRoot := ""

	if !all {
		// Scope to the current project's git repo root, across every window file,
		// so agents spawned from any subdir of this repo show up while other
		// repos stay out.
		cwd, _ := os.Getwd()
		scopeRoot = realpath(projectScope(cwd))
	}

	var rows []StatusRow

	for _, e := range iterStateFiles() {
		if e.State == nil {
			continue
		}

		rows = append(rows, statusRows(e.State.Window, statuses, scopeRoot)...)
	}

	if taskFilter != "" {
		var filtered []StatusRow

		for _, r := range rows {
			if r.Task == taskFilter {
				filtered = append(filtered, r)
			}
		}

		if len(filtered) == 0 {
			logErrorf("status: task '%s' not found", taskFilter)
			exitErrf(2, "unknown-task: %s", taskFilter)
		}
		// Single-agent query: bare status word for scripting.
		fmt.Println(filtered[0].Status)

		return
	}

	if len(rows) == 0 {
		fmt.Println("no sessions")

		return
	}

	printStatusTable(rows)
}

func printStatusTable(rows []StatusRow) {
	tw := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	emit := func(cells ...string) {
		_, _ = fmt.Fprintln(tw, strings.Join(cells, "\t"))
	}

	headers := []string{"PROJECT", "PANE", "TASK", "SESSION-ID", "STATUS", "CONTEXT"}

	dashes := make([]string, len(headers))
	for i, h := range headers {
		dashes[i] = strings.Repeat("-", len(h))
	}

	emit(headers...)
	emit(dashes...)

	for _, r := range rows {
		emit(r.Project, r.Pane, r.Task, r.Session, r.Status, r.Context)
	}

	_ = tw.Flush()
}

// ---------------------------------------------------------------------------
// resurrect
// ---------------------------------------------------------------------------

func cmdResurrect(task, sessionID string) {
	win := getWin()
	agentName := "subagent-" + win + "-" + task
	logInfof("resurrect agent=%s session=%s win=%s", agentName, sessionID, win)

	// claude --resume only finds a session when launched from the directory it
	// was created in. Recover that cwd from the transcript (survives cleanup);
	// fall back to the caller's cwd. Thread it into the pane (-c) AND a cd guard.
	cwd, ok := sessionCWD(sessionID)
	if !ok {
		cwd, _ = os.Getwd()
	}

	wt := ensureAgentsWindow(win, cwd)
	paneID := makeAgentPane(wt, cwd)
	logDebugf("resurrect agent=%s pane=%s", agentName, paneID)
	mustTmux("select-layout", "-t", wt.Target, "even-horizontal")

	logInfof("resurrect agent=%s session=%s cwd=%s", agentName, sessionID, cwd)
	// && keeps resume from running in the wrong dir if cd fails (bash + fish 3.0+).
	resumeCmd := "cd " + shellQuote(cwd) + " && " + shellJoin([]string{"claude", "--resume", sessionID})
	mustTmux("send-keys", "-t", paneID, resumeCmd, "Enter")

	st := loadWin(win)
	st.AgentsWindowID = wt.WindowID
	st.Agents[task] = Agent{PaneID: paneID, SessionID: sessionID, CWD: cwd, AgentName: agentName}
	saveWin(win, st)
	logInfof("resurrected agent=%s pane=%s session=%s", agentName, paneID, sessionID)
	fmt.Printf("Resurrected %s in pane %s (session: %s)\n", agentName, paneID, sessionID)
}

// ---------------------------------------------------------------------------
// capture
// ---------------------------------------------------------------------------

func cmdCapture(task, mode string) {
	win := getWin()
	ref := resolveAgent(win, task, true)

	// Cheapness hint: an idle agent is better read via `result` (JSONL) than by
	// scraping terminal scrollback.
	if (mode == "" || mode == "full") && ref.Meta.SessionID != "" {
		if sessionStatuses()[ref.Meta.SessionID] == "idle" {
			stderrlnf("hint: '%s' is idle — `result %s` is cheaper "+
				"(reads JSONL log, not terminal scrollback).", ref.Name, task)
		}
	}

	displayMode := mode
	if displayMode == "" {
		displayMode = "screenful"
	}

	logDebugf("capture agent=%s pane=%s mode=%s", ref.Name, ref.PaneID, displayMode)

	switch mode {
	case "full":
		fmt.Println(mustTmuxOut("capture-pane", "-t", ref.PaneID, "-p", "-S",
			"-"+strconv.Itoa(cfg.CaptureScrollback)))
	case "log":
		logfile := "/tmp/" + task + ".log"
		mustTmux("pipe-pane", "-t", ref.PaneID, "-o", "cat >> "+logfile)
		logInfof("capture agent=%s streaming to %s", ref.Name, logfile)
		fmt.Printf("Streaming to %s\n", logfile)
	case "stop":
		mustTmux("pipe-pane", "-t", ref.PaneID)
		logInfof("capture agent=%s streaming stopped", ref.Name)
		fmt.Println("Stopped streaming")
	default:
		fmt.Println(mustTmuxOut("capture-pane", "-t", ref.PaneID, "-p"))
	}
}

// ---------------------------------------------------------------------------
// cleanup
// ---------------------------------------------------------------------------

func killPane(pane string) bool {
	_, code := tmuxResult("kill-pane", "-t", pane)

	return code == 0
}

func cmdCleanup(task string, all, prune bool) {
	if prune {
		cleanupPrune()

		return
	}

	win := getWin()
	if all {
		cleanupAll(win)

		return
	}

	// Single task: get_agent semantics (no liveness requirement), exits 1 if untracked.
	ref := resolveAgent(win, task, false)
	logInfof("cleanup agent=%s win=%s pane=%s", ref.Name, win, ref.PaneID)

	if !killPane(ref.PaneID) {
		logWarnf("cleanup: pane %s already dead for agent '%s'", ref.PaneID, ref.Name)
	}

	st := loadWin(win)
	delete(st.Agents, task)

	if len(st.Agents) > 0 {
		saveWin(win, st)
	} else {
		removeWinFile(win)
		logDebugf("cleanup: state file removed (no agents left) win=%s", win)
	}

	logInfof("cleanup done agent=%s pane=%s", ref.Name, ref.PaneID)
	fmt.Printf("Killed pane %s (%s)\n", ref.PaneID, ref.Name)
}

func cleanupAll(win string) {
	logInfof("cleanup --all win=%s", win)

	st := loadWin(win)
	for _, task := range slices.Sorted(maps.Keys(st.Agents)) {
		meta := st.Agents[task]

		name := agentNameFor(win, task, &meta)
		if killPane(meta.PaneID) {
			logInfof("cleanup: killed pane=%s agent=%s", meta.PaneID, name)
			fmt.Printf("Killed pane %s (%s)\n", meta.PaneID, name)
		} else {
			logInfof("cleanup: pane=%s already gone agent=%s", meta.PaneID, name)
			fmt.Printf("Pane %s already gone (%s)\n", meta.PaneID, name)
		}
	}

	removeWinFile(win)
	logDebugf("cleanup --all: removed state file for win=%s", win)
}

func cleanupPrune() {
	logInfof("cleanup --prune: cross-window sweep")

	panes := livePanes()
	removed := 0

	for _, e := range iterStateFiles() {
		base := filepath.Base(e.Path)
		if e.State == nil {
			_ = os.Remove(e.Path)

			fmt.Printf("Removed unreadable: %s\n", base)
			logInfof("prune: removed unreadable %s", base)

			removed++

			continue
		}

		st := e.State
		dead := make([]string, 0)

		for t, m := range st.Agents {
			if !panes[m.PaneID] {
				dead = append(dead, t)
			}
		}

		slices.Sort(dead)

		for _, t := range dead {
			// Prune's name fallback is the TASK name (not subagent-win-task).
			name := st.Agents[t].AgentName
			if name == "" {
				name = t
			}

			logInfof("prune: dead agent '%s' in %s (pane %s)", name, base, st.Agents[t].PaneID)
			delete(st.Agents, t)
			fmt.Printf("Pruned dead agent '%s' from %s\n", name, base)

			removed++
		}

		if len(st.Agents) > 0 {
			if b, err := json.MarshalIndent(st, "", "  "); err == nil {
				_ = os.WriteFile(e.Path, b, 0o644)
			}
		} else {
			_ = os.Remove(e.Path)

			logInfof("prune: removed empty %s", base)
			fmt.Printf("Removed empty: %s\n", base)
		}
	}

	plural := "ies"
	if removed == 1 {
		plural = "y"
	}

	logInfof("prune: %d dead entr%s removed", removed, plural)
	fmt.Printf("%d dead entr%s pruned\n", removed, plural)
}

// ---------------------------------------------------------------------------
// recap / compact (slash-command shortcuts)
// ---------------------------------------------------------------------------

func cmdRecap(task string) {
	win := getWin()
	ref := resolveAgent(win, task, true)
	logInfof("recap agent=%s pane=%s", ref.Name, ref.PaneID)

	if !sendPrompt(ref.PaneID, "/recap", true) {
		logErrorf("recap agent=%s NOT submitted", ref.Name)
		exitErrf(2, "prompt-not-submitted: agent '%s' pane %s", ref.Name, ref.PaneID)
	}

	fmt.Printf("Sent /recap to %s (%s)\n", ref.Name, ref.PaneID)
}

func cmdCompact(task, description string) {
	win := getWin()
	ref := resolveAgent(win, task, true)

	text := "/compact"
	if description != "" {
		text = "/compact " + description
	}

	logInfof("compact agent=%s pane=%s text=%q", ref.Name, ref.PaneID, text)

	if !sendPrompt(ref.PaneID, text, true) {
		logErrorf("compact agent=%s NOT submitted", ref.Name)
		exitErrf(2, "prompt-not-submitted: agent '%s' pane %s", ref.Name, ref.PaneID)
	}

	fmt.Printf("Sent '%s' to %s (%s)\n", text, ref.Name, ref.PaneID)
}
