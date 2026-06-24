package main

// agent.go — unified agent lookup. resolveAgent replaces the Python pair
// get_agent (metadata, no liveness) and resolve_pane_id (must be live), plus
// the repeated inline `agent_name` fallback.

// agentNameFor returns the stored agent_name, or the conventional
// subagent-<win>-<task> fallback when absent.
func agentNameFor(win, task string, meta *Agent) string {
	if meta != nil && meta.AgentName != "" {
		return meta.AgentName
	}

	return "subagent-" + win + "-" + task
}

// AgentRef is a resolved agent: its metadata plus derived pane liveness/name.
type AgentRef struct {
	Win    string
	Task   string
	Meta   Agent
	PaneID string
	Live   bool
	Name   string
}

// resolveAgent looks up a task in a window's state. It exits 1 with
// "No agent '<task>' tracked for window '<win>'" if untracked. When requireLive
// is set, it also exits 1 with "pane not found: <task>" if the pane is dead.
// PaneID is discovered at runtime (not read from state) so it works after reboot.
func resolveAgent(win, task string, requireLive bool) AgentRef {
	st := loadState(projectKey())

	meta, ok := st.Agents[task]
	if !ok {
		logWarnf("resolveAgent: task '%s' not found in window '%s'", task, win)
		exitErrf(1, "No agent '%s' tracked for window '%s'", task, win)
	}

	// PaneID may be in-memory from spawn (not loaded from state). Discover it via
	// session lookup when absent, so commands work after a process restart.
	paneID := meta.PaneID
	if paneID == "" && meta.SessionID != "" {
		if found, err := findPaneForSession(meta.SessionID); err == nil {
			paneID = found
		}
	}

	live := paneID != "" && livePanes()[paneID]

	name := agentNameFor(win, task, &meta)
	if requireLive && !live {
		logWarnf("resolveAgent: task=%s pane=%s not found or dead (win=%s)", task, paneID, win)
		exitErrf(1, "pane not found: %s (use `resurrect` to re-attach session)", task)
	}

	return AgentRef{Win: win, Task: task, Meta: meta, PaneID: paneID, Live: live, Name: name}
}
