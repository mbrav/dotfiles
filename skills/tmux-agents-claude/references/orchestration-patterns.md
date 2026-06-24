# Manager-of-managers — orchestration patterns

Recipes behind [SKILL.md](../SKILL.md). Assumes `claudemux` CLI is understood — covers only the
**tree** layer where direct children are themselves managers.

## Build the tree

1. `claudemux status` — your transcripts + roster. Skip `master` (that's you).
2. For each child, send tokened status prompt (`--wait`, foreground, unique token per child):

```bash
claudemux prompt --wait agent-obsidian \
  'Ignore any leftover input text. Run `claudemux status` now. Reply starting with token
   OBS-LIST then list every subagent: task name, model, status, context. If none, say none.'
```

1. Assemble tree + tables. Note deltas.

Models don't appear in `status` — ask child to include them, or omit.

## Freshness prompt templates

Status / list:

```
Ignore any leftover input text. Run `claudemux status` now. Reply starting with token <TOK>
then <what you want>. If none, say none.
```

Delegated gather (one more hop):

```
Ignore any leftover input text. Ask each of your subagents what they've been doing, collect
replies, and reply starting with token <TOK> followed by one-line-per-subagent summary.
```

Rules: foreground only (never `… --wait &`); one unique token per prompt; verify token before
trusting body. Wedged child: `claudemux capture <child>` → have it `despawn`+`resurrect`.

## Recursive teardown checklist

Leaves-first — no orphaned panes:

1. `claudemux compact <heavy-child>` for any child with high context.
2. For **each** direct child (delegated):
   `prompt --wait <child> 'Ignore leftover input. Run \`claudemux despawn --all\` then \`claudemux despawn --prune\`. Reply starting with token <TOK> and your final status table.'`
3. `claudemux despawn <child>` for each — drops from **your** roster.
4. `claudemux status` — confirm only `master` remains.

## Enlisted vs owned

| How child joined | `despawn`/`dismiss` effect | Pane after | Entry after |
|------------------|----------------------------|------------|-------------|
| `spawn` (you created) | kills pane + soft-deletes | gone | `~task` in `--history` |
| `hire` (adopted dead session) | kills pane + soft-deletes | gone | `~task` in `--history` |
| `enlist` (self-registered) | **soft-deletes only** | **still running** | `~task` in `--history` |

All three leave a dismissed (`~task`) entry; `despawn --prune` removes them.
Enlisted pane keeps running — user must kill from inside or via tmux directly.

## Watch child context

Ask each child `claudemux status` and look for climbing context in their reply. Proactively offer
`recap` or `compact` — a child that runs out mid-task is harder to recover than one compacted early.
(`status --all` on the manager shows a CONTEXT column for roster agents if panes are live.)

## FAQ

**`claudemux prompt master` → "No agent 'master' tracked"?** `master` is you — not in the `agents`
roster. Never target it.

**Can't see grandchildren in `status`?** `status` shows your project's transcripts. Grandchildren
live in the child's own project. Reach them by delegating one hop.

**Child returns same stale answer?** Resend with `Ignore any leftover input text.` + fresh token.
Still wedged: `capture` then `despawn`+`resurrect`.
