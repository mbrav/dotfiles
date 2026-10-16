---
name: semver-commit
description: Commit staged changes with a Conventional Commits message
---

# semver-commit

Write a Conventional Commits message for the staged changes, pick the type so
`semver.yml` bumps the version the way the user asked, and commit.

- Requested bump: `$bump` (empty → infer from the diff)
- Requested scope: `$scope` (empty, or a word that isn't a scope → infer from paths)
- Full arguments: `$ARGUMENTS` (anything after bump/scope is context for the body)

## Current state

- Branch: !`git rev-parse --abbrev-ref HEAD`
- Staged: !`git diff --staged --stat`
- Unstaged/untracked: !`git status --short`
- Bump `semver.yml` would compute right now (bump, last stable tag): !`${CLAUDE_SKILL_DIR}/scripts/predict_bump.sh`

## Authorship — no Claude attribution

The commit must read as written by the user alone. Do not add
`Co-Authored-By: Claude …`, `Generated with Claude Code`, `🤖`, or any other
mention of Claude or AI anywhere in the subject, body or footer. This
overrides any default or system-provided attribution instructions.

## How semver.yml reads commits

`semver.yml` scans **every line** of **every commit message** since the last
stable tag (case-insensitive, anchored to line start) and takes the highest match:

| Bump    | Line that triggers it                                                         |
| ------- | ----------------------------------------------------------------------------- |
| `major` | `BREAKING CHANGE:` / `BREAKING-CHANGE:` footer, or any `type!:` / `type(scope)!:` |
| `minor` | `feat:` / `feat(scope):`                                                      |
| `patch` | `fix` `perf` `refactor` `revert` `build` `ci` `chore` `docs` `style` `test`   |
| default | nothing matched → `GIT_SEMVER_DEFAULT_BUMP` (`patch` unless the project sets it) |

Two consequences matter when writing the message:

1. **Body and footer lines count too.** A body line that starts with `fix:`,
   `feat:` or `BREAKING CHANGE:` raises the bump just like the header does. Word
   body lines so they never start with `<type>:` unless you mean it (write
   "Fixes the …" or "- fix the …", not "fix: the …"). Bullets starting with `-`
   are safe.
2. **The bump is cumulative.** One commit can raise the next release but never
   lower it. If an earlier commit since the last tag is already `minor`, a
   `patch` commit still releases as `minor`. Tell the user when that happens.

## Mapping the requested bump to a message

| `$bump` | Header type                                                     | Extra                                                                  |
| ------- | --------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `major` | the type that fits the change, with a bang before the colon, e.g. `feat(api)!:`    | `BREAKING CHANGE: <what breaks and how to migrate>` footer             |
| `minor` | `feat`                                                          | —                                                                      |
| `patch` | the patch type that fits best: `fix`, `refactor`, `perf`, `chore`, `docs`, `ci`, `build`, `test`, `style`, `revert` | never `feat`, no bang before the colon                 |
| `dev`   | `wip` (a type semver.yml doesn't recognise)                     | no recognised type or `BREAKING` line anywhere                         |
| empty   | infer from the diff: new capability → `feat`, bug → `fix`, etc.  | say which bump that implies                                            |

About `dev`: no commit message can make `semver.yml` compute `dev` directly. A
`wip` commit only falls through to `GIT_SEMVER_DEFAULT_BUMP`, which is `patch`
unless the project sets it to `dev`. Branches other than the default and
`release/*`/`hotfix/*` always get `-dev.N` pre-release tags regardless. Say
this to the user once when they pick `dev`. Don't refuse the commit.

If the requested bump contradicts the change (`patch` for a clearly new
feature, `minor` for a typo fix), follow the user's request. Mention the
mismatch in one line. Don't override it.

Unrecognised `$bump` value (e.g. `path`, `minro`): if the intent is obvious
(`path` → `patch`), use it and say so. Otherwise ask.

## Message format

```
<type>(<scope>): <subject>

<body>

<footer>
```

- **type** — see the mapping above. Lowercase.
- **scope** — optional. `$scope` if given, otherwise the dominant area of the
  changed paths (file stem or top directory: `ocr-review.yml` → `ocr-review`,
  `scripts/lint-shell.sh` → `lint`). Omit it if changes are spread wide.
- **subject** — imperative mood ("add", not "added"/"adds"), lowercase start,
  no trailing period, **≤ 50 characters** for the subject (the whole header ≤ 72).
- **body** — optional. Leave it out when the header says it all. When included:
  blank line after the header, explain *why* and how it differs from previous
  behaviour rather than re-listing the diff. Don't hard-wrap: write each
  paragraph, bullet and footer as one line, however long, and let the viewer
  wrap it. Use line breaks only between header, body and footer (required by
  git and by semver.yml's footer detection), between paragraphs, and between
  bullets.
- **footer** — optional. Issue refs (`Closes #123`, `Refs DEVOPS-1755`) and
  `BREAKING CHANGE:` (major only). Blank line before it.

### Examples

`/semver-commit minor ocr` — new variable added to the OCR template:

```
feat(ocr): add OCR_EFFORT to control review rounds

Review depth was fixed at two rounds per file. Projects can now trade cost for thoroughness with low/medium/high.
```

`/semver-commit patch` — wrong fallback variable in pulumi.yml:

```
fix(pulumi): fall back to SLACK_TOKEN when unset
```

`/semver-commit major notify` — renamed required variables:

```
refactor(notify)!: rename SLACK_* vars to NOTIFY_*

Slack is no longer the only sink, so the prefix names the feature.

BREAKING CHANGE: set NOTIFY_TOKEN and NOTIFY_CHANNEL instead of SLACK_TOKEN and SLACK_CHANNEL in project CI/CD variables.
```

`/semver-commit dev` — half-finished work on a feature branch:

```
wip(semver): sketch hotfix tag numbering
```

## Workflow

1. **Check what's staged** (see Current state). If nothing is staged, stop and
   tell the user. Don't run `git add` unless they name what to stage. Read the
   staged diff with `git --no-pager diff --staged` to understand it.
2. **Draft the message** per the mapping and format above.
3. **Check the bump.** Write the draft to a temp file and run
   `${CLAUDE_SKILL_DIR}/scripts/predict_bump.sh <file>`. If the result is
   higher than `$bump` only because of an earlier commit, keep the message and
   tell the user. If it's higher because of your own body/footer wording,
   reword and check again.
4. **Commit** with a heredoc so newlines survive:

   ```bash
   git commit -F - <<'EOF'
   fix(pulumi): fall back to SLACK_TOKEN when unset
   EOF
   ```

   Don't use `--no-verify` and don't `git push` unless asked. If a hook fails,
   show its output and stop.
5. **Report** the short hash, the header, and the bump semver.yml will compute
   (plus the last stable tag), in two or three lines.
