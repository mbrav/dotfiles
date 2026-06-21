# Manager-of-managers — orchestration patterns

Recipes behind [SKILL.md](../SKILL.md). Assumes `claudemux` CLI is understood — covers only the
**tree** layer where direct children are themselves managers.

## Build the tree

1. `claudemux status` — your roster. Skip `master` (that's you).
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

| How child joined | `despawn`/`dismiss` effect | Pane after |
|------------------|----------------------------|------------|
| `spawn` (you created) | kills pane | gone |
| `hire` (adopted dead session) | kills pane | gone |
| `enlist` (self-registered) | **untracks only** | **still running** |

Enlisted teardown only removes from roster. User must kill from inside session or via tmux directly.

## Watch child context

Note any child with climbing `CONTEXT` and offer `recap` or `compact` proactively. Child that runs
out mid-task is harder to recover than one compacted early.

## FAQ

**`claudemux prompt master` → "No agent 'master' tracked"?** `master` is you — not in the `agents`
roster. Never target it.

**Can't see grandchildren in `status`?** `status` loads only your project's state file. Grandchildren
live in the child's own file. Reach them by delegating one hop.

**Child returns same stale answer?** Resend with `Ignore any leftover input text.` + fresh token.
Still wedged: `capture` then `despawn`+`resurrect`.
