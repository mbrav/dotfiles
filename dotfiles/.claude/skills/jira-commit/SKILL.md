---
name: jira-commit
description: Writes Conventional-Commits messages (feat/fix/feature(scope): summary) and commits staged changes. Mirrors the commit description to any Jira key auto-detected in the summary or branch. Use for commit requests or /jira-commit.
---

# jira-commit

Create a Conventional-Commits message, commit the staged changes, and — if the summary names a Jira issue — mirror the commit body to that issue as a comment.

## Hard rules

- **NEVER add a `Co-Authored-By: Claude` trailer or any Claude/AI authorship line.** Do not add `Generated with Claude`, `🤖`, or similar. The commit must look authored by the user only.
- **Do not `git push`** unless the user explicitly asks. Commit only.
- Only commit what is already staged unless the user says to stage more. Never `git add -A` blindly.

## Commit message format

```
type(scope): short imperative summary   ≤ ~72 chars

Optional body: what changed and why, wrapped ~72 cols.
Bullet points are fine.
```

- **type**: one of `feat`, `fix`, `feature`, `chore`, `docs`, `refactor`, `test`, `perf`, `build`, `ci`, `style`. (`feature` is accepted as an alias of `feat`.)
- **scope** (the "context"): the area touched, e.g. `feat(auth):`, `fix(payreq-bot):`. Infer it from the changed paths; omit only if genuinely unclear.
- **summary**: imperative mood ("add", "fix", not "added"/"fixes").
- A **Jira key** may appear in the summary or a trailing `Refs:`. Key regex: `[A-Z][A-Z0-9]+-[0-9]+` (e.g. `DEVOPS-1755`, `HRM-42`).

### Examples

Input: staged JWT login endpoint + middleware, ticket DEVOPS-1755

```
feat(auth): add JWT login endpoint and validation middleware DEVOPS-1755

Add POST /login issuing signed tokens and middleware that validates the
Authorization header on protected routes.
```

Input: fixed timezone bug in reports (no ticket)

```
fix(reports): correct date formatting in timezone conversion

Use UTC timestamps consistently across report generation.
```

Input: dependency bumps + error-handling refactor, ticket PLAT-88

```
chore(deps): update dependencies and standardize error handling PLAT-88

- Upgrade lodash to 4.17.21
- Uniform error-response shape across endpoints
```

## Workflow

Copy this checklist and check items off:

```
- [ ] 1. Inspect staged changes
- [ ] 2. Compose type(scope): summary + body
- [ ] 3. Detect Jira key
- [ ] 4. Commit (no Claude author trailer)
- [ ] 5. If Jira key: comment the description on the issue
- [ ] 6. Report commit hash + Jira link
```

**Step 1 — Inspect.** `git status --short` and `git --no-pager diff --staged`. If nothing is staged, tell the user and stop (or stage exactly what they name). Pick `scope` from the dominant changed path.

**Step 2 — Compose.** Build the message per the format above. Keep the header ≤ ~72 chars. Write a body only if the change needs explanation.

**Step 3 — Detect Jira key (optional).** The user does not need to supply a key. Best-effort auto-detect `[A-Z][A-Z0-9]+-[0-9]+` from the drafted summary, and if none is there, from the current branch name (`git rev-parse --abbrev-ref HEAD`). If none is found anywhere, skip the Jira step silently — the commit still happens. If several appear, comment on each unique key.

**Step 4 — Commit.** Prefer a HEREDOC so the body/newlines survive:

```bash
git commit -F - <<'EOF'
type(scope): summary KEY-123

body line 1
body line 2
EOF
```

Do **not** pass `--author` for Claude and do **not** append any Co-Authored-By/Generated-by trailer. If the repo or a wrapper auto-adds such a trailer, strip it (e.g. `git commit --amend` with a clean message).

**Step 5 — Mirror to Jira.** Only if a key was found. Use Claude's built-in Atlassian MCP directly — `mcp__plugin_atlassian_atlassian__addCommentToJiraIssue`. The `cloudId` comes from the connected MCP; if it isn't already known this session, get it once from `mcp__plugin_atlassian_atlassian__getAccessibleAtlassianResources` (single site → its id). Then for each key:

```
mcp__plugin_atlassian_atlassian__addCommentToJiraIssue(
  cloudId=<from connected MCP>,
  issueIdOrKey="KEY-123",
  contentFormat="markdown",
  commentBody="**Commit `<short-hash>`** on `<branch>`\n\n`type(scope): summary`\n\n<body>"
)
```

If the comment call fails (issue not found, no access), report it but keep the commit — never roll back a good commit because Jira was unreachable.

**Step 6 — Report.** Print the short hash, the final header line, and a browse URL for each commented issue (`https://<site>.atlassian.net/browse/KEY-123`).

## Edge cases

- **No Jira key:** commit normally, skip steps 5. Mention that no ticket was linked.
- **Detached HEAD / on default branch:** if the user's workflow forbids committing to the default branch, branch first — otherwise proceed.
- **Amending:** if the user asks to amend, reuse this format and re-detect the key; re-comment only if the key changed or they ask.
- **Multiple keys:** comment each unique key once.

## Evaluation

Baseline scenarios live in [evaluations.json](evaluations.json). A commit passes when: the header matches `type(scope): summary`, no Claude/AI authorship trailer is present (`git show -s --format=%B HEAD | grep -i claude` returns nothing), and — if a key was in the summary — the issue received a comment containing the commit hash.
