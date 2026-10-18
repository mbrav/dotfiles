---
name: herdr-teams
description: "Run per-project teams of Claude Code agents in Herdr under a CTO overseer: spawn a Tier 1/2/3 team for a project, brief and supervise it, resume it from the roster, track its work in todo.txt, and keep ~/dev/.roster.md current. Use when the user says spawn/start/resume a team, staff a project, talk to the CTO, check on the teams, or mentions the roster, a team lead, the team backlog, or agent tiers."
compatibility: "Runs inside a Herdr pane (HERDR_ENV=1) on rag as deploy. Projects live in ~/dev/<project>; the roster is ~/dev/.roster.md."
---

# Herdr teams

One overseer and one team per project, each agent a Claude Code session in its own Herdr pane. The **CTO** plans across projects and talks only to team leads. Each **team** is sized by tier and staffed with fixed roles. The roster records who exists and the session to resume them from; todo.txt records what they owe.

```
CEO (you)
  └─ cto                       ~/dev                    (workspace "cto")
       ├─ anselm-lead          ~/dev/anselm             (workspace "anselm", Tier 1)
       │    ├─ anselm-dev
       │    ├─ anselm-rev
       │    ├─ anselm-test
       │    └─ anselm-ops
       ├─ <proj>-lead          ~/dev/<proj>             (Tier 2)
       │    ├─ <proj>-dev
       │    └─ <proj>-rev
       └─ <proj>-dev           ~/dev/<proj>             (Tier 3, reports to cto)
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

Projects: anselm = Tier 1 (lead, dev, rev, test, ops)

- cto | CTO | management | plans and orchestrates the startup | <session-id>
- anselm-lead | lead | anselm | calm, decisive coordinator; crisp task briefs, says no to scope creep | <session-id>
```

- One `Projects:` entry per project with its tier and roles, comma-separated after the first: `Projects: anselm = Tier 1 (lead, dev, rev, test, ops), foo = Tier 3 (dev)`.
- Agent names are `<project>-<role>`; the overseer is `cto`. This replaces herdr's numbered agent families for team agents. The same string is the Herdr agent name, so `herdr agent prompt anselm-dev …` and the roster line always agree.
- Persona is one line, a short character sketch. The full role brief comes from roles.md, not the roster.
- Record the session id right after an agent starts and again before it exits:

  ```bash
  herdr agent get anselm-dev | jq -r .result.agent.agent_session.value
  ```

Only the CTO edits the roster (or the CEO). Leads ask the CTO.

## Spawn a team

1. **Pick the tier** with the CEO if not stated. Add the `Projects:` entry and one roster line per role (session id blank for now).
2. **Check the repo.** Tier 1 and 2 work on branches, so `git -C ~/dev/<project> rev-parse --git-dir` must succeed. If it doesn't, ask the CEO before running `git init`, and whether there is a remote. Tier 3 may work without git. Then `mkdir -p ~/dev/.team/<project>` for reports.
3. **Lay out panes.** One workspace per project, cwd `~/dev/<project>`. Its root pane is the lead's (or the Tier 3 dev's); split the rest off it with `--cwd ~/dev/<project> --no-focus`. Five panes don't fit one tab legibly: lead+dev in the first tab, rev/test/ops in a second (`herdr tab create`).
4. **Start each agent** in its pane with its role brief appended to the system prompt:

   ```bash
   herdr agent start anselm-dev --kind claude --pane <pane-id> -- \
     --append-system-prompt "$(cat <<'EOF'
   <role brief from roles.md, placeholders filled>
   EOF
   )"
   ```

   `agent_not_ready` means it is blocked at startup (trust dialog, login): read it and ask the CEO before answering.
5. **Record session ids** in the roster.
6. **Brief the lead** (see below) and add the brief to the backlog. The lead briefs its own team; the CTO does not reach past it.

## Resume a team

For each roster line of the project: find a free shell pane (or lay one out as above), then start the agent on its recorded session with the same brief — `--resume` restores the conversation, not the appended system prompt:

```bash
herdr agent start anselm-dev --kind claude --pane <pane-id> -- \
  --resume <session-id> --append-system-prompt "<role brief>"
```

No session id, or the transcript is gone (`~/.claude/projects/-home-deploy-dev-<project>/<id>.jsonl` missing): start fresh and give it a catch-up brief instead. Before stopping an agent, record its session id.

## Chain of command

- **CEO ↔ cto.** The CEO can talk to anyone, but work enters through the CTO.
- **cto ↔ leads.** The CTO sets goals, priorities and cross-project calls. It never prompts a team member directly, except a Tier 3 dev, which has no lead.
- **lead ↔ its team.** The lead splits work, briefs members, gates on review and test, and reports up.
- **Members never prompt upward.** They finish the turn with their report; the superior collects it. A member that needs a decision ends its turn with the question, and its lead sees it on the next read.

Prompting is pull-based so no agent is ever interrupted mid-turn:

```bash
herdr agent prompt anselm-lead "<brief>" --wait --timeout 1800000   # short task: block until settled
herdr agent prompt anselm-dev  "<brief>"                             # long task: fire, then later…
herdr agent wait   anselm-dev --timeout 3600000
herdr agent read   anselm-dev --source recent-unwrapped --lines 200
```

A `blocked` agent you can't decide for goes up the chain to the CEO.

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

The CTO owns todo.txt for team work, as it owns the roster. Leads may read their project's tasks (`$T ls --json +<project>`) but never write. Commands and the usual rules (list before acting on a number, match by text) come from the todo skill. On top of that:

- Tag every task explicitly `+<project> @team`; the CTO works from `~/dev`, where derived tags would be wrong.
- One task per CTO→lead brief, its text the brief's Goal.
- Out-of-scope proposals and items a report leaves open become their own tasks, unprioritized.
- Anything waiting on the CEO (base-branch merge, shared infra, deletes, money) is `(A) … needs CEO`; clear the priority once the CEO decides.
- Complete a task when the lead's report meets the brief's Done line. A merge that needs the CEO stays its own `(A)` task.

## Supervision (CTO)

On each check-in:

```bash
herdr agent list
$T ls --json @team
```

- `blocked` anywhere → read it, unblock or escalate.
- A team idle with open tasks → ask its lead for status. Idle with nothing open → let it rest.
- Roster names, Herdr names and status-line names must match; fix with `herdr agent rename`.

## Never

- `herdr server stop`, killing the Herdr process, or closing workspaces/panes another agent or the CEO created.
- Pushing or merging to a project's base branch, deleting data, or changing shared infra (anything on another host, any shared database, NetBird, DNS) without the CEO's go-ahead. ops prepares the change and the exact commands; the CEO approves.
- Committing outside `/semver-commit`; it is what keeps AI attribution out of the history.
- Putting secrets in briefs, reports, the roster or todo.txt. Agents read them from the project's own `.env`.
