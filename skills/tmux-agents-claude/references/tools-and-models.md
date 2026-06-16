# Spawning Guide — Models, Tools, Permissions

How to choose `--model`, `--tools`, `--dangerously-skip-permissions`. Command syntax in [SKILL.md](../SKILL.md).

No `--model`/`--tools` = account default model + full tool access. Narrow deliberately per task.

## Model selection

| Task | Model | Why |
|------|-------|-----|
| Deep reasoning, architecture, hard debugging, multi-step refactors | `claude-opus-4-7` | Strongest reasoning; worth cost on genuinely hard work |
| General coding, edits, reviews, most subtasks | `claude-sonnet-4-6` | Best capability/cost balance — default choice |
| Bulk/parallel: file scans, grep-summarize, simple edits, log triage | `claude-haiku-4-5-20251001` | Fast + cheap; ideal for many concurrent agents |

- Default Sonnet unless task clearly needs more/less.
- Opus: wrong answer is expensive OR problem genuinely complex — not routine edits.
- Haiku: fanning out many agents over straightforward work.
- Match model to *hardest* step, not average.

Older fallbacks (`claude-opus-4-5`, `claude-sonnet-4-5`) exist; prefer newest per tier.

## Tool selection

Pass **minimum** set via `--tools` (comma-separated). Fewer tools = less risk, less distraction, faster. Omit `--tools` only for open-ended work.

| Task | `--tools` |
|------|-----------|
| Read-only analysis, code review | `Read,Grep,Glob` |
| Research with web access | `Read,Grep,Glob,WebFetch,WebSearch` |
| Editing existing code | `Read,Edit,Grep,Glob` |
| Creating new files / scaffolding | `Read,Write,Edit,Grep,Glob` |
| Build/test/run commands | add `Bash` |
| Jupyter notebooks | add `NotebookEdit` |
| Spawn own subagents | add `Agent` |
| Task tracking | add `TaskCreate,TaskUpdate,TaskList` |

Full vocabulary: `Read`, `Write`, `Edit`, `Bash`, `Grep`, `Glob`, `Agent`, `WebFetch`, `WebSearch`, `LSP`, `NotebookEdit`, `Skill`, `TaskCreate`, `TaskUpdate`, `TaskList`.

- Read-only tasks: no `Write`/`Edit`/`Bash`.
- `Bash` = highest blast radius — add only when agent must run commands.
- Start narrow; can always `prompt` agent or respawn with more.

## `--dangerously-skip-permissions`

Bypasses all permission prompts — agent edits files and runs commands without confirmation.

> [!danger] Only on explicit user request
> Do **not** pass `--dangerously-skip-permissions` unless user explicitly asked (e.g. "skip permissions", "run unattended", "auto-approve"). Removes human-in-the-loop safety for destructive actions.

Without explicit ask: omit. Agent pauses on sensitive actions — safe default for `Bash`/`Write`/`Edit` agents.

With explicit ask: still scope `--tools` tightly so unattended agent can't exceed task scope.

## Examples

```bash
# Routine edit — Sonnet, scoped tools, prompts on
./scripts/agent.py spawn fix-bug 'Fix the off-by-one in pagination' \
  --model claude-sonnet-4-6 --tools 'Read,Edit,Grep,Glob'

# Cheap parallel scan — Haiku, read-only
./scripts/agent.py spawn audit-imports 'List unused imports across src/' \
  --model claude-haiku-4-5-20251001 --tools 'Read,Grep,Glob'

# Hard architecture task — Opus, broad tools
./scripts/agent.py spawn redesign 'Propose a new caching layer; write an ADR' \
  --model claude-opus-4-7 --tools 'Read,Write,Edit,Grep,Glob,WebSearch'

# Unattended — ONLY because user explicitly asked to skip permissions
./scripts/agent.py spawn migrate 'Run the DB migration and verify' \
  --model claude-sonnet-4-6 --tools 'Read,Edit,Bash' \
  --dangerously-skip-permissions
```
