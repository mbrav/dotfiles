# Manager-of-managers — orchestration patterns

Detailed recipes behind [SKILL.md](../SKILL.md). Assumes the [tmux-subagents-claude](../../tmux-subagents-claude/SKILL.md)
CLI (`claudemux`) is already understood — this only covers the **tree** layer where your direct
children are themselves managers.

## Contents

- [Build the tree (two-level gather)](#build-the-tree-two-level-gather)
- [Freshness prompt templates](#freshness-prompt-templates)
- [Recursive teardown checklist](#recursive-teardown-checklist)
- [Enlisted vs owned](#enlisted-vs-owned)
- [Watch child context](#watch-child-context)
- [FAQ](#faq)

## Build the tree (two-level gather)

1. **Your roster:** `claudemux status`. Read the `project:` header and the rows; **skip `master`**
   (that row is you). What remains are your direct children.
2. **Each child's roster:** for every direct child, send a tokened status prompt (foreground,
   `--wait`) so the child runs *its own* `claudemux status` and reports back. Different token per
   child so you can tell replies apart.
3. **Assemble:** combine into a tree + tables. Note deltas from the last check.

Example child prompt:

```bash
claudemux prompt --wait agent-obsidian \
  'Ignore any leftover input text. Run `claudemux status` now. Reply starting with token
   OBS-LIST then list every subagent you manage: task name, model, status, context. If none, say none.'
```

Example assembled output:

```
My roster
┌────────────────┬─────────┬──────────────────┐
│     Agent      │ Status  │     Context      │
├────────────────┼─────────┼──────────────────┤
│ agent-dotfiles │ 🟢 idle │ 340k/1000k (34%) │
│ agent-obsidian │ 🟢 idle │ 50k/1000k (5%)   │
└────────────────┴─────────┴──────────────────┘

master (me)
├── agent-dotfiles   🟢 idle
│   ├── implementer   🟢 idle  (Opus)
│   └── reviewer      🟢 idle  (Sonnet)
└── agent-obsidian   🟢 idle
    └── editor        🟢 idle  (Opus)
```

Models don't appear in the `status` table — ask the child to include them (it knows from its own
spawn output), or omit.

## Freshness prompt templates

Every remote prompt can collide with a lingering reply or stray input in the child's pane. Use these
shapes and **verify the token** before trusting the reply; if the token is missing, the prompt didn't
land fresh — resend (don't accept the stale body).

Status / list:

```
Ignore any leftover input text. Run `claudemux status` now. Reply starting with token <TOK>
then <what you want>. If none, say none.
```

Report-gathering (delegated one more hop down):

```
Ignore any leftover input text. Ask each of your subagents what they've been doing, collect the
replies, and reply starting with token <TOK> followed by a one-line-per-subagent summary.
```

Rules: foreground only (never `… --wait &` — the reply is lost to backgrounding); one unique token
per prompt; if a child stays wedged, `claudemux capture <child>` to inspect, then have it
`despawn`+`resurrect` the stuck pane (or do it yourself for a direct child).

## Recursive teardown checklist

Leaves-first, so no pane is orphaned:

1. `claudemux compact <heavy-child>` — for any child with high context, before it does more work.
2. For **each** direct child (delegated — you can't see grandchildren):
   `prompt --wait <child> 'Ignore leftover input. Run \`claudemux despawn --all\` then \`claudemux despawn --prune\`. Reply starting with token <TOK> and your final status table.'`
3. `claudemux despawn <child>` for each child to drop it from **your** roster.
4. `claudemux status` to confirm only `master` (you) remains.

## Enlisted vs owned

How a child entered your roster decides what teardown does:

| How the child joined | `despawn`/`dismiss` effect | Pane after |
|----------------------|----------------------------|------------|
| `spawn` (you created it)        | kills the pane           | gone |
| `hire` (adopted a dead session) | kills the pane           | gone |
| `enlist` (it registered itself) | **untracks only**        | **still running** |

So tearing down an enlisted child only removes it from your roster — you'll see
`Untracked enlisted <name> (pane … left running)`. That's by design: `despawn`/`dismiss` never kill a
pane they don't own. If the user wants an enlisted session actually terminated, tell them it must be
killed from inside that session (or by killing its tmux pane) — you can't do it from here.

## Watch child context

Children accrue context as they work (the transcripts saw 27–34%). On a fleet check, note any child
whose `CONTEXT` is climbing and offer to `recap` (summarize progress) or `compact` (compress context)
it before it fills. Do this proactively — a child that runs out of context mid-task is harder to
recover than one compacted early.

## FAQ

**Why did `claudemux prompt master` fail with "No agent 'master' tracked"?** Because `master` is
*you* — the orchestrator row, not an entry in the `agents` roster the roster commands act on. Never
target master; skip it when reading `status`.

**Why can't I see my grandchildren in `status`?** `status` (no `--all`) loads only *your* project's
state file — your direct roster. Each child's subagents live in that child's own project file, which
your commands don't load. Reach them by delegating to the child, not directly. (`status --all` would
list every project's agents, but you still operate per-hop.)

**A child keeps returning the same old answer.** Its pane has a stale reply or stray unsubmitted
input. Resend with `Ignore any leftover input text.` + a fresh unique token and verify the token in
the reply. If it still won't take a fresh prompt, `capture` then `despawn`+`resurrect` it.
