---
name: herdr-teams
description: "Run per-project teams of Claude Code agents in Herdr under a CTO overseer: spawn a Tier 1/2/3 team for a project, brief and supervise it, resume it from the roster, track its work in todo.txt, and keep ~/dev/.roster.md current. Use when the user says spawn/start/resume a team, staff a project, talk to the CTO, check on the teams, or mentions the roster, a team lead, the team backlog, or agent tiers."
compatibility: "Runs inside a Herdr pane (HERDR_ENV=1) on rag as deploy. Projects live in ~/dev/<project>; the roster is ~/dev/.roster.md."
---

# Herdr teams

One overseer and one team per project, each agent a Claude Code session in its own Herdr pane. The **CTO** plans across projects and talks only to team leads. Each **team** is sized by tier and staffed with fixed roles. The roster records who exists and the session to resume them from; todo.txt records what they owe.

```
CEO (you)
  └─ cto                       ~/dev                    (workspace "management")
       ├─ <proj1>-lead         ~/dev/<proj1>            (workspace "<proj1>", Tier 1)
       │    ├─ <proj1>-dev
       │    ├─ <proj1>-rev
       │    ├─ <proj1>-test
       │    └─ <proj1>-ops
       ├─ <proj2>-lead         ~/dev/<proj2>            (Tier 2)
       │    ├─ <proj2>-dev
       │    └─ <proj2>-rev
       └─ <proj3>-dev          ~/dev/<proj3>            (Tier 3, reports to cto)
```

Tier sizes, role duties and the persona prompts are in [references/roles.md](references/roles.md).

## Builds on

This skill is team policy only. The mechanics live in three other skills; use them as they are:

- **herdr**: pane layout, `agent start/prompt/wait/read/send-keys`, what `idle`/`done`/`blocked` and timeouts mean, reading past the alternate screen, `/compact` past 280k, resuming by session id.
- **todo**: the backlog, through `T=~/.claude/skills/todo/scripts/todo.sh`.
- **semver-commit**: every commit a team makes.

Where this skill says something different, it wins for team agents.

## Before anything

```bash
test "${HERDR_ENV:-}" = 1 || echo "not inside Herdr — stop"
herdr agent list
cat ~/dev/.roster.md
```

## The roster

`~/dev/.roster.md` is the single source of truth. Keep the format exactly:

```markdown
# Roster
One line per agent: name | role | project | persona | last session id

Projects: <project> = Tier 1 (lead, dev, rev, test, ops)

- cto | CTO | management | plans and orchestrates the startup | <session-id>
- <project>-lead | lead | <project> | calm, decisive coordinator; crisp task briefs, says no to scope creep | <session-id>
```

- One `Projects:` entry per project with its tier and roles, comma-separated after the first: `Projects: <proj1> = Tier 1 (lead, dev, rev, test, ops), <proj3> = Tier 3 (dev)`.
- Agent names are `<project>-<role>`; the overseer is `cto`. This replaces herdr's numbered agent families for team agents. The same string is the Herdr agent name, so `herdr agent prompt <project>-dev …` and the roster line always agree.
- Persona is one line, a short character sketch. The full role brief comes from roles.md, not the roster.
- Record the session id right after an agent starts and again before it exits:

  ```bash
  herdr agent get <project>-dev | jq -r .result.agent.agent_session.value
  ```

Only the CTO edits the roster (or the CEO). Leads ask the CTO.

## The CTO's workspace

The CTO runs in a workspace of its own, labelled `management` to match its roster line, with cwd `~/dev` and one tab named `cto`. Never put a team agent in it, and never start the CTO in a project workspace. If it doesn't exist yet (first start, or after Herdr restarts), create it before starting or resuming the CTO:

```bash
herdr workspace create --cwd ~/dev --label management --no-focus   # root tab → cto
herdr tab rename <root-tab-id> cto
```

## Spawn a team

1. **Pick the tier** with the CEO if not stated. Add the `Projects:` entry and one roster line per role (session id blank for now).
2. **Check the repo.** Tier 1 and 2 work on branches, so `git -C ~/dev/<project> rev-parse --git-dir` must succeed. If it doesn't, ask the CEO before running `git init`, and whether there is a remote. Tier 3 may work without git. Then `mkdir -p ~/dev/.team/<project>` for reports.
3. **Lay out tabs.** Use one workspace per project, labelled `<project>`, with cwd `~/dev/<project>`. Each agent gets a tab of its own; don't split panes. Name each tab by its bare role (`lead`, `dev`, `rev`, `test`, `ops`), with no project prefix, since the workspace already names the project. The workspace's root tab is the lead's (or the Tier 3 dev's), so rename it. Create the rest in role order, because Herdr can't reorder tabs:

   ```bash
   herdr workspace create --cwd ~/dev/<project> --label <project> --no-focus   # root tab → lead
   herdr tab rename <root-tab-id> lead
   herdr tab create --workspace <ws-id> --cwd ~/dev/<project> --label dev --no-focus   # then rev, test, ops
   ```

   Each tab's pane id is `.result.root_pane.pane_id`. To fix a layout without stopping agents, run `herdr pane move <pane-id> --new-tab --workspace <ws-id> --label <role> --no-focus`. It appends the tab at the end, so move them in role order.
4. **Start each agent** in its pane with its role brief appended to the system prompt. Write the brief from roles.md, placeholders filled, to `~/dev/.team/briefs/<name>.md` and pass the file; Herdr rejects agent arguments with newlines or quotes, so an inline `--append-system-prompt "$(cat …)"` fails:

   ```bash
   herdr agent start <project>-dev --kind claude --pane <pane-id> -- \
     --append-system-prompt-file ~/dev/.team/briefs/<project>-dev.md
   ```

   `agent_not_ready` means it is blocked at startup (trust dialog, login): read it and ask the CEO before answering.
5. **Record session ids** in the roster.
6. **Brief the lead** (see below) and add the brief to the backlog. The lead briefs its own team; the CTO does not reach past it.

## Resume a team

For each roster line of the project: find the free shell pane in its role's tab (or lay the tabs out as above), then start the agent on its recorded session with the same brief — `--resume` restores the conversation, not the appended system prompt:

```bash
herdr agent start <project>-dev --kind claude --pane <pane-id> -- \
  --resume <session-id> --append-system-prompt-file ~/dev/.team/briefs/<project>-dev.md
```

No session id, or the transcript is gone (`~/.claude/projects/-home-deploy-dev-<project>/<id>.jsonl` missing): start fresh and give it a catch-up brief instead. Before stopping an agent, record its session id.

### Restart to load new config

Settings, hooks and MCP servers load only when an agent starts, and environment variables only when its shell does. To pick up a change, restart the agent in a fresh login shell, only while it is `idle` or `done`, and always with its brief file; a bare `--resume` drops the role brief:

```bash
herdr agent send-keys <project>-dev ctrl+c ctrl+c        # back to the shell prompt
herdr pane run <pane-id> "exec bash -l"                # reload the login environment
herdr agent start <project>-dev --kind claude --pane <pane-id> -- \
  --resume <session-id> --append-system-prompt-file ~/dev/.team/briefs/<project>-dev.md
```

Check it took: the process's environment and command line (`/proc/<pid>/environ`, `/proc/<pid>/cmdline`) show the new variables and the brief file. The CTO can't restart itself; ask the CEO to resume it in a new terminal.

Don't change an agent's effort with `/effort <level>`; it also rewrites the shared default in `~/.claude/settings.json`. Effort comes from that default.

## Chain of command

- **CEO ↔ cto.** The CEO can talk to anyone, but work enters through the CTO.
- **cto ↔ leads.** The CTO sets goals, priorities and cross-project calls. It never prompts a team member directly, except a Tier 3 dev, which has no lead.
- **lead ↔ its team.** The lead splits work, briefs members, gates on review and test, and reports up.
- **Members never prompt upward.** They finish the turn with their report; the superior collects it. A member that needs a decision ends its turn with the question, and its lead sees it on the next read.

Prompting is pull-based so no agent is ever interrupted mid-turn:

```bash
herdr agent prompt <project>-lead "<brief>" --wait --timeout 1800000   # short task: block until settled
herdr agent prompt <project>-dev  "<brief>"                             # long task: fire, then later…
herdr agent wait   <project>-dev --timeout 3600000
herdr agent read   <project>-dev --source recent-unwrapped --lines 200
```

A `blocked` agent you can't decide for goes up the chain to the CEO.

If Claude Code's auto-mode classifier denies an action that is in the brief, the agent doesn't route around it. It does every step it can without that action, then ends its turn with the exact command that was denied. The superior answers a permission dialog only for actions its own brief covers; anything else goes up. Plain `git push` of dev, main, `feat/*`, `fix/*` and `vX.Y.Z` tags from `cto` and the leads is allowed by statement `LeadsRelease` in `~/.claude/policy.sh.json`, the IAM-style policy the `~/.claude/hooks/policy.py` hook enforces. It is bound to their session ids, not their Herdr names; force pushes are denied by settings, deletes by `DenyRemoteDeletes`. Rules that hang on who an agent is go there, not into `settings.json`.

### Working inside auto mode

These keep agents inside the permission rules in `~/.claude/settings.json`, so the auto-mode classifier has nothing to block:

- Push as its own Bash call, plain `git push origin <ref>`: no `cd`, `&&` or variables. The push hook only recognises a lone push.
- Release and review worktrees go in `~/dev/.worktrees/<project>/<name>`, never `/tmp`, with the default `~/.cargo` (no `CARGO_HOME` under `/tmp`).
- Restart agents one `herdr` command per Bash call: no shell functions or loops. Wait with `herdr agent wait`, never `sleep` loops.
- Change files with the Edit tool, not `cp` to `/tmp` plus `sed -i`.
- A change to `~/.claude` settings, hooks or skills is a proposal: write it to `~/dev/.team/proposals/<date>-<slug>.md` and ask the CEO. Those edits always prompt (`ask` rules), and only the CEO approves them.

Have agents write anything longer than a screen to `~/dev/.team/<project>/<name>-<YYYY-MM-DD>-<slug>.md` and reply with only the path.

## Briefs

Every brief, CTO→lead or lead→member, has the same four parts. Lead→member briefs add a fifth:

```
Goal:     one sentence, the outcome not the steps
Scope:    files/areas in bounds, and what is explicitly out
Done:     how we'll know — tests, a command's output, a reviewer's sign-off
Report:   what to send back, and where (path under ~/dev/.team/<project>/)
Commit:   <type>(<scope>), bump <major|minor|patch|dev>
```

The member commits with `/semver-commit <bump> <scope>` from the Commit line, and rev checks the header against it. If semver-commit would stop to ask, the member ends its turn with the question like any other decision.

Leads reject scope creep from either direction: work outside the brief goes back up as a proposal, not into the diff.

## Backlog

The CTO owns todo.txt for team work, as it owns the roster. Leads may read their project's tasks (`$T ls --json +<project>`) but never write. Commands and the usual rules (always through the wrapper, ids for reference, `$T line ID` before acting on a line) come from the todo skill. On top of that:

- Tag every task explicitly `+<project>`; the CTO works from `~/dev`, where a derived project would be wrong. Give it exactly one kanban category as its context (`@triage`, `@backlog`, `@ready`, `@doing`, `@review`, `@blocked`, `@done`), and `$T move` it when its state changes: `@doing` when a lead briefs it, `@review` while rev or test has it, `@blocked` while it waits on someone, with who in the text. Refer to tasks by their `id:N` (`#42`) and resolve the line number with `$T line ID` right before acting.
- One task per CTO→lead brief, its text the brief's Goal.
- Out-of-scope proposals and items a report leaves open become their own tasks.
- Anything waiting on the CEO (base-branch merge, shared infra, deletes, money, a product decision) also gets `+ceo`, so `$T ls --json +ceo` is the CEO's queue. Drop the tag once the CEO decides. A merge that needs the CEO stays its own task.
- Complete a task when the lead's report meets the brief's Done line.

Priority says how much the work matters, not who it waits on:

| Priority | Meaning |
| --- | --- |
| `(A)` | Urgent: production or users affected, or a team is stopped until it's done |
| `(B)` | Next up: the work that moves the project now |
| `(C)` | Planned: queued behind `(B)`, nobody blocked |
| `(D)` | Worth doing, nobody waiting: proposals, follow-ups, small fixes |
| `(E)` | Someday: ideas and nice-to-haves, only when nothing else is open |
| none | Not triaged yet |

Set a priority on every task you add, using the todo skill's `(X)` prefix. The CEO reprioritizes in the TUI and that wins: never undo a priority you didn't just set. Re-triage when a task's situation changes (an incident makes it urgent, a merged fix makes a follow-up optional).

### Handing a project off

Once a project runs steadily, the CTO hands it to its lead so the CTO can take on other projects. Write a handoff to `~/dev/.team/<project>/cto-<date>-handoff.md` covering everything the CTO was doing for that project: picking the next work, the project's backlog tasks, releases and deploys under the standing delegations, team upkeep (restarts, `/compact`, names), what to escalate, and the facts the lead needs but only the CTO knew. Update the lead's brief file to point at it, and brief the lead with it once it's `idle` or `done`.

After a handoff the lead picks its own next work by priority, the same way the CTO does, and owns its project's `+<project>` tasks, and only those. The lead keeps `~/dev/.team/<project>/status.md` current (now, last done, needs cto, next). The CTO keeps the roster, priorities between projects and everything for the CEO. On check-ins it reads `status.md` instead of prompting the lead, and prompts only when it has something for the lead or the file shows a problem.

## Supervision (CTO)

On each check-in:

```bash
herdr agent list
$T ls --json +<project>   # once per project on the roster
$T ls --json +ceo
```

- `blocked` anywhere → read it, unblock or escalate.
- A team idle with open tasks → ask its lead for status.
- A handed-off team → read its `status.md`; act only on "Needs cto" or a stale or wrong file.
- A team not yet handed off, idle with nothing in flight → brief its lead on the project's highest-priority open task without `+ceo`: `(A)` through `(E)` in order, oldest first within a priority, one brief at a time. Untriaged tasks get a priority first. Leave `+ceo` tasks until the CEO decides. Nothing left → let it rest.
- Open `(A)` tasks anywhere → the CEO hears about them in the next summary, `+ceo` ones first.
- An agent idle past 280k context → `/compact` it (herdr skill).
- Roster names, Herdr names and status-line names must match; fix with `herdr agent rename`.

## Never

- `herdr server stop`, killing the Herdr process, or closing workspaces/panes another agent or the CEO created.
- Pushing or merging to a project's base branch, deleting data, or changing shared infra (anything on another host, any shared database, NetBird, DNS) without the CEO's go-ahead. ops prepares the change and the exact commands; the CEO approves. A standing delegation written into an agent's brief file (releases for a lead, deploys of the project's own services for ops) counts as that go-ahead, within exactly what it names.
- Committing outside `/semver-commit`; it is what keeps AI attribution out of the history.
- Putting secrets in briefs, reports, the roster or todo.txt, or printing them into a session at all. Agents read them from the project's own `.env`. Commands that render config inline (`docker compose config`, `env`, `printenv`) leak them; use `docker compose config --quiet`/`--hash`, or grep for names only.
