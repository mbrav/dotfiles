---
name: tmux-agents-claude
description: Top-level "manager of managers" layer over tmux-subagents-claude (the `claudemux` CLI). Use whenever YOU manage agents that each manage their own subagents — a tree of Claude Code sessions in tmux panes. Triggers: "check on your agents and their subagents", "ask your agents how their subagents are doing", "ask your agents what their agents have been doing", "list your agents and their subagents", build a roster/status TREE of the whole fleet, route a task down through one of your agents, or recursively tear the tree down. TWO INVARIANTS this skill enforces: (1) the `master` row in `claudemux status` is YOU — never prompt/result/capture/despawn it; (2) you drive only your DIRECT children — anything below them you reach by DELEGATING to the child, never by addressing a grandchild yourself.
---
# Tmux Agents — Claude (manager of managers)

You sit at top of agent tree. Direct children are themselves managers — each runs `claudemux` to
spawn and drive *its own* subagents. Brief children, route work, aggregate reports, tear down cleanly.

```
master (YOU)
├── agent-dotfiles          ← direct child (manager)
│   ├── implementer         ← grandchild (DON'T address directly)
│   └── reviewer
└── agent-obsidian          ← direct child (manager)
    ├── editor
    └── organizer
```

Built on [tmux-subagents-claude](../tmux-subagents-claude/SKILL.md) (`claudemux` CLI) — inherit all
its rules. This skill adds only the tree layer.

## Two iron rules

**1. `master` is you.** `claudemux status` always shows a `master` row — that's *this session*.
Roster commands (`prompt`/`result`/`capture`/`despawn`) act on the `agents` list; master isn't in it.
Never target master. Skip it when reading `status`.

**2. Drive only direct children.** `claudemux status` (no `--all`) loads *your* roster only.
Grandchildren live in a different state file. To act on one, **delegate** to the owning child — never
address a grandchild yourself.

## Fleet check → build the tree

1. `claudemux status` — your roster. Skip `master` row.
2. For each child, `prompt --wait` it to run its own `claudemux status` and report subagents (use
   freshness token per child).
3. Assemble tree + tables; flag deltas.

```
master (me)
├── agent-dotfiles   🟢 idle
│   ├── implementer   🟢 idle  (Opus)
│   └── reviewer      🟢 idle  (Sonnet)
└── agent-obsidian   🟢 idle
    └── editor        🟢 idle  (Opus)
```

## Freshness

Every child prompt can collide with stale reply or wedged input line. Guard every status/report prompt:

- Prefix: `Ignore any leftover input text.`
- Require: `Reply starting with token <UNIQUE>` — verify token before trusting body. Missing → resend.
- Run **foreground** (`--wait`, never `&`).

Wedged child: `capture` to inspect → have it `despawn`+`resurrect`, or do so yourself.

## Delegate downward

To act on grandchild, prompt the child that owns it:

- *"Ask your `editor` to report what it's done, then summarize."*
- *"Run `claudemux despawn ingester` then `despawn --prune`."*
- *"Run `claudemux status` and list every subagent you manage."*

## Recursive teardown (leaves-first)

1. `claudemux compact <heavy-child>` — free context before more work.
2. Prompt **each** child: *"`claudemux despawn --all` then `despawn --prune`."* (delegated)
3. `claudemux despawn <child>` for each child from **your** roster.
4. `claudemux status` — confirm only `master` remains.

**Enlisted caveat:** `despawn`/`dismiss` on an enlisted child only untracks — pane keeps running.
Surface to user; they must kill it from inside or via tmux directly.

## More

[references/orchestration-patterns.md](references/orchestration-patterns.md) — copy-paste freshness
prompts, teardown checklist, enlisted-vs-owned table, context-watch note, FAQ.
