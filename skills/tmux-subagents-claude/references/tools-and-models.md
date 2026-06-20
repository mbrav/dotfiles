# Spawning Guide — Models, Tools, Permissions

Choose `--model`, `--tools`, `--permission-mode`. Syntax in [SKILL.md](../SKILL.md).

Default: account model + full tools. Narrow per task.

## Model selection

- **Deep reasoning / architecture / hard debugging**: `claude-opus-4-7` (strongest; worth cost)
- **General coding / edits / reviews / most subtasks**: `claude-sonnet-4-6` (best balance, default)
- **Bulk/parallel scans / simple edits / log triage**: `claude-haiku-4-5-20251001` (fast + cheap)

Rules: Default Sonnet. Opus for complex/expensive-wrong-answer. Haiku for many concurrent agents. Match hardest step.

### Polling cadence by model

- **Haiku**: seconds. Use `result --wait` or `prompt --wait`
- **Sonnet**: tens of seconds to minutes. Use `result --wait`
- **Opus**: minutes. Use `result --wait`; take `status --all` for progress

`status` on-demand snapshot. Block with `result --wait` / `prompt --wait` to wait, don't re-run `status`.

Fallbacks: `claude-opus-4-5`, `claude-sonnet-4-5`. Prefer newest.

## Tool selection

Pass **minimum** set via `--tools` (comma-separated). Fewer = less risk, faster. Omit for open-ended work.

- **Read-only / review**: `Read,Grep,Glob`
- **Research + web**: `Read,Grep,Glob,WebFetch,WebSearch`
- **Edit code**: `Read,Edit,Grep,Glob`
- **New files**: `Read,Write,Edit,Grep,Glob`
- **Build/test/run**: add `Bash`
- **Jupyter**: add `NotebookEdit`
- **Subagents**: add `Agent`
- **Task tracking**: add `TaskCreate,TaskUpdate,TaskList`

Full: `Read`, `Write`, `Edit`, `Bash`, `Grep`, `Glob`, `Agent`, `WebFetch`, `WebSearch`, `LSP`, `NotebookEdit`, `Skill`, `TaskCreate`, `TaskUpdate`, `TaskList`.

Read-only: no `Write`/`Edit`/`Bash`. `Bash` = blast radius (add only when needed). Start narrow.

## `--permission-mode`

Spawned agents run in a detached pane with **no human at the keyboard**, so any
interactive permission prompt wedges them. The mode controls how the agent
handles permissions without a human in the loop.

Default: **`auto`** — proceeds without prompting and without the one-time "Bypass
Permissions mode" warning screen (which would otherwise stall a fresh pane). This
is the right default for unattended panes.

Choices (passed straight to `claude --permission-mode`):

- **`auto`** (default) — auto-proceed, no scary warning. Use for almost everything.
- **`acceptEdits`** — auto-accept file edits; still prompts for other actions (will wedge if a non-edit prompt fires).
- **`dontAsk`** — never ask.
- **`default`** / **`plan`** — standard / plan-only; will wedge on the first prompt since no one can answer.

Always scope `--tools` tightly regardless of mode — `Bash` is the blast radius.

## Examples

Flags precede the `<task> <prompt>` positionals (strict `flag` ordering).

```bash
# Routine edit — Sonnet, scoped tools, prompts on
tmux-subagents-claude spawn --model claude-sonnet-4-6 --tools 'Read,Edit,Grep,Glob' \
  fix-bug 'Fix the off-by-one in pagination'

# Cheap parallel scan — Haiku, read-only
tmux-subagents-claude spawn --model claude-haiku-4-5-20251001 --tools 'Read,Grep,Glob' \
  audit-imports 'List unused imports across src/'

# Hard architecture task — Opus, broad tools
tmux-subagents-claude spawn --model claude-opus-4-7 --tools 'Read,Write,Edit,Grep,Glob,WebSearch' \
  redesign 'Propose a new caching layer; write an ADR'

# Unattended with Bash — auto mode (default) keeps the pane from wedging
tmux-subagents-claude spawn --model claude-sonnet-4-6 --tools 'Read,Edit,Bash' \
  migrate 'Run the DB migration and verify'
```
