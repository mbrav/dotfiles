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
// is set, it also exits 1 with "pane not found: <task>" if the pane is dead —
// mirroring the two distinct Python error paths (get_agent vs resolve_pane_id).
func resolveAgent(win, task string, requireLive bool) AgentRef {
	st := loadWin(win)
	meta, ok := st.Agents[task]
	if !ok {
		logWarnf("resolveAgent: task '%s' not found in window '%s'", task, win)
		exitErr(1, "No agent '%s' tracked for window '%s'", task, win)
	}
	live := meta.PaneID != "" && livePanes()[meta.PaneID]
	name := agentNameFor(win, task, &meta)
	if requireLive && !live {
		logWarnf("resolveAgent: task=%s pane=%s not found or dead (win=%s)", task, meta.PaneID, win)
		exitErr(1, "pane not found: %s", task)
	}
	return AgentRef{Win: win, Task: task, Meta: meta, PaneID: meta.PaneID, Live: live, Name: name}
}
