---
name: tmux-agents-claude
description: Top-level "manager of managers" layer over tmux-subagents-claude (the `claudemux` CLI). Use whenever YOU manage agents that each manage their own subagents — a tree of Claude Code sessions in tmux panes. Triggers: "check on your agents and their subagents", "ask your agents how their subagents are doing", "ask your agents what their agents have been doing", "list your agents and their subagents", build a roster/status TREE of the whole fleet, route a task down through one of your agents, or recursively tear the tree down. TWO INVARIANTS this skill enforces: (1) the `master` row in `claudemux status` is YOU — never prompt/result/capture/despawn it; (2) you drive only your DIRECT children — anything below them you reach by DELEGATING to the child, never by addressing a grandchild yourself.
---
# Tmux Agents — Claude (manager of managers)

You sit at the **top of an agent tree**. Your direct children are themselves managers: each runs the
[tmux-subagents-claude](../tmux-subagents-claude/SKILL.md) skill (the `claudemux` CLI) to spawn and
drive *its own* subagents. Your job is to brief your children, route work down to them, aggregate
their reports, and tear the tree down cleanly — not to micromanage the leaves.

```
master (YOU)
├── agent-dotfiles          ← your direct child (a manager)
│   ├── implementer         ← its subagent (your grandchild)
│   └── reviewer
└── agent-obsidian          ← your direct child (a manager)
    ├── editor
    └── organizer
```

This is `claudemux`'s **forest** state model: every project has one state file holding a `master`
(set by `init`/`enlist` — the orchestrator in that window) plus an `agents` roster. A child that
`init`s or `enlist`s in its own project becomes the master of its own sub-roster. See
[technicalities.md](../tmux-subagents-claude/references/technicalities.md#state-model--one-json-per-project)
for the full model.

## Two iron rules

**1. `master` is you.** Every `claudemux status` lists a `master` row — that is *this session*, the
orchestrator, not a managed agent. The roster commands (`prompt`/`result`/`capture`/`despawn`/
`dismiss`) act on the `agents` roster, and master isn't in it, so targeting it fails with
`No agent 'master' tracked`. Don't prompt master, don't try its session UUID, don't capture it —
when you read `status`, mentally skip the master row and operate only on the agents below it. (A
session that wastes turns trying to "ping master" is talking to itself.)

**2. Drive only your direct children.** Your `claudemux status` (no `--all`) shows *your* roster
only — your direct children, never their subagents. Grandchildren live in a different project's
state file that your commands don't load. So you **cannot** address a grandchild directly; to do
anything to one, you **delegate**: prompt the owning child to act on its own roster. Think one hop
at a time.

## Built on tmux-subagents-claude

This skill adds only the tree layer. For the actual CLI surface — `spawn`, `prompt`, `result`,
`status`, `recap`, `compact`, `despawn`, `hire`, `enlist`, `dismiss`, `resurrect` — use
[tmux-subagents-claude](../tmux-subagents-claude/SKILL.md), and inherit its rules verbatim:

- `prompt … --wait` baselines the prior reply so you get a *fresh* one; run it **foreground** (never
  background `--wait` with `&` — the reply is lost).
- `idle`/`empty` don't prove your latest prompt landed — confirm via the reply body.
- Status values and the `CONTEXT` column mean the same here as there.

## Check on the fleet → build the tree

The most common request ("check on the agents", "how are your agents' subagents doing", "list every
agent and its subagents") is a **two-level gather**:

1. `claudemux status` — your direct roster. Skip the `master` row (rule 1).
2. For **each** direct child, `prompt --wait` it to run its own `status` and report its subagents —
   with a freshness token (see below).
3. Assemble a tree + per-child table and report up.

Output template (mirror this):

```
master (me)
├── agent-dotfiles   🟢 idle
│   ├── implementer   🟢 idle  (Opus)
│   └── reviewer      🟢 idle  (Sonnet)
└── agent-obsidian   🟢 idle
    └── editor        🟢 idle  (Opus)
```

Flag changes between checks (an agent that vanished, context climbing, a subagent stuck `starting`).

## Talk to a child reliably (freshness)

Every interaction with a child is a *remote prompt into another Claude's pane*, so a prior reply can
linger or stray keystrokes can wedge the input line — you then read a **stale** answer and don't
notice. Guard every status/report prompt:

- Prefix it with `Ignore any leftover input text.`
- Require `Reply starting with token <UNIQUE>` (e.g. `OBS-LIST`, `DOT-DOWN`) and **verify the token
  appears** before trusting the body. No token → the prompt didn't land fresh; resend.
- Run **foreground** so the reply isn't lost to backgrounding.

If a child won't take a fresh prompt, it's wedged: `capture` it to see the pane, then recover per the
parent skill's [Stuck agent](../tmux-subagents-claude/SKILL.md#stuck-agent) guidance (have it
`despawn`+`resurrect`, or do so yourself if it's your direct child).

## Delegate downward

To act on a **grandchild**, prompt the child that owns it — phrase it as an instruction for the child
to run against its own roster:

- *"Ask your `editor` to report what it's done, then summarize."*
- *"Despawn your subagent `ingester` for good: `claudemux despawn ingester` then `despawn --prune`."*
- *"Run `claudemux status` and list every subagent you manage."*

You orchestrate one hop down; the child orchestrates the hop below it.

## Recursive teardown (order matters)

Tear the tree down **leaves-first**, so nothing is orphaned:

1. `compact` any heavy child first (frees its context before it does work) — e.g.
   `claudemux compact agent-dotfiles`.
2. Tell **each** child to clear its own roster: *"`claudemux despawn --all` then `despawn --prune`."*
   (delegated — you can't reach the grandchildren yourself).
3. Then `despawn` the children from **your** roster.

**Enlisted caveat:** if a child was `enlist`ed (it registered itself; you only *reference* its pane),
`despawn`/`dismiss` will only **untrack** it — its pane keeps running as a live session. Surface this
to the user (`Untracked enlisted <name> (pane … left running)`); if they want it actually killed, say
so — it must be terminated from inside that session or by killing the pane directly.

## More

[references/orchestration-patterns.md](references/orchestration-patterns.md) — copy-paste freshness
prompts, the full tree-build walkthrough, the teardown checklist, the enlisted-vs-owned table, a
context-watch note, and a short FAQ.
