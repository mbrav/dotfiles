# Spawning Guide — Models, Tools, Permissions

Choose `--model`, `--tools`, `--dangerously-skip-permissions`. Syntax in [SKILL.md](../SKILL.md).

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

## `--dangerously-skip-permissions`

Bypass all permission prompts — no confirmation on edits/commands.

**Only on explicit user request** (e.g., "skip", "unattended", "auto-approve"). Removes human-in-loop safety.

Without ask: omit. Default safe. With ask: still scope `--tools` tightly.

## Examples

```bash
# Routine edit — Sonnet, scoped tools, prompts on
~/.config/scripts/tmux-subagents-claude spawn fix-bug 'Fix the off-by-one in pagination' \
  --model claude-sonnet-4-6 --tools 'Read,Edit,Grep,Glob'

# Cheap parallel scan — Haiku, read-only
~/.config/scripts/tmux-subagents-claude spawn audit-imports 'List unused imports across src/' \
  --model claude-haiku-4-5-20251001 --tools 'Read,Grep,Glob'

# Hard architecture task — Opus, broad tools
~/.config/scripts/tmux-subagents-claude spawn redesign 'Propose a new caching layer; write an ADR' \
  --model claude-opus-4-7 --tools 'Read,Write,Edit,Grep,Glob,WebSearch'

# Unattended — ONLY because user explicitly asked to skip permissions
~/.config/scripts/tmux-subagents-claude spawn migrate 'Run the DB migration and verify' \
  --model claude-sonnet-4-6 --tools 'Read,Edit,Bash' \
  --dangerously-skip-permissions
```
