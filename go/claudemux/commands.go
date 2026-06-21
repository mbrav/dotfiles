package main

// commands.go — the nine subcommand handlers plus their bounded-wait helpers.
// All cwd handling flows from a single os.Getwd()/sessionCWD capture per command
// into both the pane (-c) and the stored metadata.

import (
	"cmp"
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
	key := projectKey()
	st := loadState(key)
	st.Window = win
	st.AgentsWindowID = wt.WindowID
	st.Agents[task] = Agent{PaneID: paneID, SessionID: sessionID, CWD: cwd, AgentName: agentName}
	saveState(key, st)

	// Tiled grid keeps panes usable-width as the agent count grows (6 panes ->
	// ~3x2 instead of six ~30-col vertical strips). Then repaint every pane so
	// the just-narrowed neighbors don't keep stale, wrong-width Claude frames.
	mustTmux("select-layout", "-t", wt.Target, "tiled")
	redrawWindowPanes(wt.Target)

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

	var rows []StatusRow

	if all {
		// Every project's roster.
		for _, e := range iterStateFiles() {
			if e.State == nil {
				continue
			}

			rows = append(rows, statusRowsFromState(*e.State, statuses)...)
		}
	} else {
		// Just this project's roster (the chosen state file IS the scope), so
		// hired agents from other repos still show.
		st := loadState(projectKey())
		st.Window = cmp.Or(st.Window, getWin())
		rows = statusRowsFromState(st, statuses)
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
	resurrectInto(win, projectKey(), task, sessionID, "subagent-"+win+"-"+task)
}

// resurrectInto creates a pane that resumes sessionID and registers it under
// `task` (with stored agent_name `agentName`) in the project file identified by
// callerKey. The pane runs in the session's ORIGINAL cwd (recovered from the
// transcript) so `claude --resume` finds it and the transcript keeps landing
// under the right project slug — even when callerKey is a *different* project
// (the `hire` case). Shared by `resurrect` and `hire`.
func resurrectInto(win, callerKey, task, sessionID, agentName string) {
	logInfof("resurrect agent=%s session=%s win=%s key=%s", agentName, sessionID, win, callerKey)

	// claude --resume only finds a session when launched from the directory it
	// was created in. Recover that cwd from the transcript (survives cleanup);
	// fall back to the caller's cwd. Thread it into the pane (-c) AND a cd guard.
	cwd, ok := sessionCWD(sessionID)
	if !ok {
		cwd, _ = os.Getwd()
	}

	// The recorded cwd can be stale: the original dir may have been moved or
	// deleted since the session ran. If so, `cd <gone> && claude --resume`
	// short-circuits on the failed cd and the pane dies on arrival. Fall back
	// to the caller's cwd so the resume still launches.
	if fi, err := os.Stat(cwd); err != nil || !fi.IsDir() {
		logWarnf("resurrect: recorded cwd %q is gone; falling back to current dir", cwd)
		stderrlnf("warning: original session dir %q no longer exists; resuming from "+
			"current dir. `claude --resume` keys sessions by directory, so it may "+
			"report \"No conversation found\".", cwd)

		cwd, _ = os.Getwd()
	}

	wt := ensureAgentsWindow(win, cwd)
	paneID := makeAgentPane(wt, cwd)
	logDebugf("resurrect agent=%s pane=%s", agentName, paneID)
	mustTmux("select-layout", "-t", wt.Target, "tiled")
	redrawWindowPanes(wt.Target)

	logInfof("resurrect agent=%s session=%s cwd=%s", agentName, sessionID, cwd)
	// && keeps resume from running in the wrong dir if cd fails (bash + fish 3.0+).
	resumeCmd := "cd " + shellQuote(cwd) + " && " + shellJoin([]string{"claude", "--resume", sessionID})
	mustTmux("send-keys", "-t", paneID, resumeCmd, "Enter")

	st := loadState(callerKey)
	st.Window = win
	st.AgentsWindowID = wt.WindowID
	st.Agents[task] = Agent{PaneID: paneID, SessionID: sessionID, CWD: cwd, AgentName: agentName}
	saveState(callerKey, st)
	logInfof("resurrected agent=%s pane=%s session=%s", agentName, paneID, sessionID)
	fmt.Printf("Resurrected %s in pane %s (session: %s)\n", agentName, paneID, sessionID)
}

// ---------------------------------------------------------------------------
// init / hire / dismiss (master + roster management)
// ---------------------------------------------------------------------------

// cmdInit registers the project's `master`. With no sessionID it spawns a fresh
// master agent in the CURRENT window (a split pane alongside the human) running a
// brand-new claude session (generated UUID) named agent-<project>. With a
// sessionID it adopts that already-running session as the master instead — no new
// pane — recording the current pane/cwd (intended for a running session to
// register itself, e.g. `init $CLAUDE_CODE_SESSION_ID`). Either way the master
// lives in the current window, NOT the detached agents session. Not part of the
// subagent surface documented in SKILL.md.
func cmdInit(sessionID, model, tools, effort, permMode string) {
	win := getWin()
	cwd, _ := os.Getwd()
	agentName := "agent-" + filepath.Base(projectScope(cwd))

	if sessionID != "" {
		key := projectKey()
		st := loadState(key)
		st.Window = win
		st.Master = &Agent{PaneID: os.Getenv("TMUX_PANE"), SessionID: sessionID, CWD: cwd, AgentName: agentName}
		saveState(key, st)

		logInfof("init adopt master=%s session=%s pane=%s key=%s", agentName, sessionID, os.Getenv("TMUX_PANE"), key)
		fmt.Printf("Initialized master %s from existing session %s\n", agentName, sessionID)

		return
	}

	logInfof("init master=%s win=%s (fresh)", agentName, win)

	// Split the current window's pane (anchored to $TMUX_PANE when set), so the
	// master lives beside the human. The attached client drives SIGWINCH, so no
	// manual retile/redraw is needed (unlike the detached agents session).
	split := []string{"split-window"}
	if tp := os.Getenv("TMUX_PANE"); tp != "" {
		split = append(split, "-t", tp)
	}

	split = append(split, "-c", cwd, "-P", "-F", "#{pane_id}")
	paneID := mustTmuxOut(split...)
	sessionID := newUUID()

	key := projectKey()
	st := loadState(key)
	st.Window = win
	st.Master = &Agent{PaneID: paneID, SessionID: sessionID, CWD: cwd, AgentName: agentName}
	saveState(key, st)

	// Start claude idle (no prompt); --name sets the real session name.
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

	mustTmux("send-keys", "-t", paneID, shellJoin(parts), "Enter")

	logInfof("init master=%s pane=%s session=%s key=%s", agentName, paneID, sessionID, key)
	fmt.Printf("Initialized master %s in pane %s (current window) [session: %s]\n",
		agentName, paneID, sessionID)
}

// cmdHire adopts an existing session (by UUID) into the current project's
// roster: it resumes the session in a pane (in the session's ORIGINAL project,
// recovered from the transcript) and tracks it here, so `status` lists it even
// though its cwd points at another repo. The roster task (and stored agent_name)
// come from the session's own name — one argument is all it needs. `dismiss` is
// the teardown.
func cmdHire(sessionID string) {
	win := getWin()

	if _, ok := sessionCWD(sessionID); !ok {
		exitErrf(1, "hire: no transcript found for session %s (unknown session)", sessionID)
	}

	task, agentName := hireIdentity(sessionID)
	logInfof("hire session=%s task=%s name=%s win=%s", sessionID, task, agentName, win)
	resurrectInto(win, projectKey(), task, sessionID, agentName)
}

// hireIdentity derives the roster task key and stored agent_name for a hired
// session from its existing session name, falling back to hired-<sid[:8]> when
// the session is unnamed.
func hireIdentity(sessionID string) (task, agentName string) {
	name := sessionName(sessionID)
	if name == "" {
		fallback := "hired-" + shortSession(sessionID)

		return fallback, fallback
	}

	return sanitizeTask(name), name
}

// taskSanitizer maps a free-form session name to a single path/shell-friendly
// token usable as a roster task key.
var taskSanitizer = strings.NewReplacer("/", "-", " ", "-", "\t", "-")

func sanitizeTask(s string) string {
	return strings.Trim(taskSanitizer.Replace(s), "-")
}

// cmdDismiss stops managing the agent with the given session UUID: it kills its
// pane and removes it from state (the inverse of hire). It searches the current
// project first, then every project file, so a UUID can be dismissed from
// anywhere.
func cmdDismiss(sessionID string) {
	key, task, st, ok := findAgentBySession(sessionID)
	if !ok {
		logWarnf("dismiss: no managed agent with session %s", sessionID)
		exitErrf(1, "dismiss: no managed agent with session %s", sessionID)
	}

	meta := st.Agents[task]
	logInfof("dismiss session=%s task=%s key=%s pane=%s", sessionID, task, key, meta.PaneID)

	if !killPane(meta.PaneID) {
		logWarnf("dismiss: pane %s already dead for session %s", meta.PaneID, sessionID)
	}

	delete(st.Agents, task)

	if len(st.Agents) == 0 && st.Master == nil {
		removeStateFile(key)
		logDebugf("dismiss: state file removed (empty) key=%s", key)
	} else {
		saveState(key, st)
	}

	fmt.Printf("Dismissed '%s' (session %s); killed pane %s\n", task, sessionID, meta.PaneID)
}

// shortSession returns the first 8 chars of a session id (or the whole thing if
// shorter) for a default task name.
func shortSession(sessionID string) string {
	if len(sessionID) > 8 {
		return sessionID[:8]
	}

	return sessionID
}

// findAgentBySession locates the tracked agent with the given session id,
// checking the current project first, then all project files. Returns the
// project key, task name, that project's loaded state, and whether found.
func findAgentBySession(sessionID string) (string, string, WinState, bool) {
	cur := projectKey()
	if st := loadState(cur); st.Agents != nil {
		for task, m := range st.Agents {
			if m.SessionID == sessionID {
				return cur, task, st, true
			}
		}
	}

	for _, e := range iterStateFiles() {
		if e.State == nil {
			continue
		}

		key := strings.TrimSuffix(filepath.Base(e.Path), ".json")
		if key == cur {
			continue
		}

		for task, m := range e.State.Agents {
			if m.SessionID == sessionID {
				return key, task, *e.State, true
			}
		}
	}

	return "", "", WinState{}, false
}

// ---------------------------------------------------------------------------
// redraw
// ---------------------------------------------------------------------------

// cmdRedraw repaints every pane in the current project's agents window,
// recovering the stale frames Claude's TUI leaves after a tmux resize (a layout
// rebalance, or a client attaching/resizing). Purely cosmetic for the attached
// human view; orchestration reads per-pane grids and never depended on it.
func cmdRedraw() {
	win := getWin()

	winID, ok := agentsWindowID(win)
	if !ok {
		fmt.Println("no agents window for this project")

		return
	}

	target := "agents:" + winID
	logInfof("redraw win=%s target=%s", win, target)
	// Re-tile first so an older even-horizontal window (cramped strips) is
	// normalized to the grid, then repaint to clear any stale frames.
	mustTmux("select-layout", "-t", target, "tiled")
	redrawWindowPanes(target)
	fmt.Printf("Re-tiled and repainted panes in %s\n", target)
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

	key := projectKey()
	st := loadState(key)
	delete(st.Agents, task)

	if len(st.Agents) > 0 || st.Master != nil {
		saveState(key, st)
	} else {
		removeStateFile(key)
		logDebugf("cleanup: state file removed (no agents left) key=%s", key)
	}

	logInfof("cleanup done agent=%s pane=%s", ref.Name, ref.PaneID)
	fmt.Printf("Killed pane %s (%s)\n", ref.PaneID, ref.Name)
}

func cleanupAll(win string) {
	logInfof("cleanup --all win=%s", win)

	key := projectKey()
	st := loadState(key)

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

	// The master lives in the current window (not the agents session) and is never
	// in st.Agents, so the loop above leaves it running. Keep its record too —
	// only drop the file when there's no master to preserve.
	if st.Master != nil {
		st.Agents = map[string]Agent{}
		saveState(key, st)
		logDebugf("cleanup --all: kept master, cleared agents key=%s", key)
	} else {
		removeStateFile(key)
		logDebugf("cleanup --all: removed state file for key=%s", key)
	}
}

func cleanupPrune() {
	logInfof("cleanup --prune: cross-window sweep")

	panes := livePanes()
	removed := 0

	for _, e := range iterStateFiles() {
		removed += pruneEntry(e, panes)
	}

	plural := "ies"
	if removed == 1 {
		plural = "y"
	}

	logInfof("prune: %d dead entr%s removed", removed, plural)
	fmt.Printf("%d dead entr%s pruned\n", removed, plural)
}

// pruneEntry drops dead agents from one state file, rewriting it — or removing
// it when neither agents nor a master remain. An unreadable file is removed
// outright. The master record (and its pane) is never touched. Returns the count
// of removed entries (1 for an unreadable file, else the number of dead agents).
func pruneEntry(e stateFileEntry, panes map[string]bool) int {
	base := filepath.Base(e.Path)
	if e.State == nil {
		_ = os.Remove(e.Path)

		fmt.Printf("Removed unreadable: %s\n", base)
		logInfof("prune: removed unreadable %s", base)

		return 1
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
		name := cmp.Or(st.Agents[t].AgentName, t)
		logInfof("prune: dead agent '%s' in %s (pane %s)", name, base, st.Agents[t].PaneID)
		delete(st.Agents, t)
		fmt.Printf("Pruned dead agent '%s' from %s\n", name, base)
	}

	if len(st.Agents) > 0 || st.Master != nil {
		if b, err := json.MarshalIndent(st, "", "  "); err == nil {
			_ = os.WriteFile(e.Path, b, 0o644)
		}
	} else {
		_ = os.Remove(e.Path)

		logInfof("prune: removed empty %s", base)
		fmt.Printf("Removed empty: %s\n", base)
	}

	return len(dead)
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
