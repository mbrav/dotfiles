#!/usr/bin/env python3
"""PreToolUse hook: enforce ~/.claude/policy.sh.json, an IAM-style policy.

It covers rules Claude's permission settings can't express: who the agent is,
which branch it's on, what the command contains.

Evaluation: an explicit Deny wins, then Ask, then Allow. No matching statement
means no opinion, and Claude's own settings and auto mode decide. Never make
this fail closed: a broken policy file reports an error and leaves the
decision to Claude.

The policy file is a JSON array of statement objects.

Statement fields (all optional except Effect):
  Sid          name, shown in the decision reason
  Effect       Allow | Deny | Ask
  Action       tool names or globs (Bash, Edit, mcp__*), default every tool;
               a plain name that isn't a known Tool is reported as a typo
  NotAction    tool names or globs the statement skips
  Resource     globs on the tool's resource: Bash command, file path, URL,
               search query, skill or subagent name
  NotResource  resource globs the statement skips
  Condition    {Operator: {variable: value | [values]}}; operators AND, keys
               within one AND, values within a key OR (a Not* operator needs
               every value to miss). Operators: StringEquals, StringNotEquals,
               StringLike, StringNotLike, StringRegex, StringNotRegex, Null
               (true = variable is empty).
  Reason       text appended to the decision reason

Values may use ${variable}, as in IAM policy variables. Variables:
  tool, resource, command, file_path, url, cwd, permission_mode, agent_type,
  session_id, project (git repo or folder), git_repo, git_branch,
  herdr_agent (anselm-dev), herdr_project (anselm), herdr_role (dev),
  herdr_session (Claude session id Herdr tracks), herdr_pane, herdr_tab,
  herdr_workspace. Herdr ones are empty outside Herdr.

CLAUDE_POLICY_FILE overrides the policy path. The herdr lookup is cached per
pane for HERDR_CACHE_TTL seconds under $TMPDIR.
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
from enum import StrEnum
from fnmatch import fnmatchcase
from functools import cached_property

# The hook lives in <claude dir>/hooks/; the policy sits in <claude dir>
DEFAULT_POLICY = os.path.join(
    os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "policy.sh.json"
)
VAR = re.compile(r"\$\{([a-z_]+)\}")
GLOB_CHARS = frozenset("*?[")
UNNAMED = "unnamed statement"
# Agent names change only on rename or restart, and a stale name for a few
# seconds is harmless, while each `herdr agent list` costs ~45 ms
HERDR_CACHE_TTL = 10


def warn(message: str) -> None:
    print(f"policy.py: {message}", file=sys.stderr)


def run(*cmd: str) -> str:
    import subprocess  # ~4 ms, and most calls never need it

    try:
        # check=False: a failing git or herdr just leaves the variable empty
        return subprocess.run(
            cmd, capture_output=True, text=True, timeout=2, check=False
        ).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def as_tuple(value) -> tuple[str, ...]:
    return tuple(map(str, value)) if isinstance(value, list) else (str(value),)


class Tool(StrEnum):
    """Claude Code tools a policy can name in Action, with the input field that is their resource"""

    BASH = "Bash"
    READ = "Read"
    EDIT = "Edit"
    MULTI_EDIT = "MultiEdit"
    WRITE = "Write"
    NOTEBOOK_EDIT = "NotebookEdit"
    GLOB = "Glob"
    GREP = "Grep"
    WEB_FETCH = "WebFetch"
    WEB_SEARCH = "WebSearch"
    AGENT = "Agent"
    TASK = "Task"
    SKILL = "Skill"
    TODO_WRITE = "TodoWrite"
    ASK_USER_QUESTION = "AskUserQuestion"
    EXIT_PLAN_MODE = "ExitPlanMode"

    @property
    def resource_field(self) -> str | None:
        return _RESOURCE_FIELD.get(self)

    @classmethod
    def known(cls, name: str) -> bool:
        return name in cls._value2member_map_


_RESOURCE_FIELD = {
    Tool.BASH: "command",
    Tool.READ: "file_path",
    Tool.EDIT: "file_path",
    Tool.MULTI_EDIT: "file_path",
    Tool.WRITE: "file_path",
    Tool.NOTEBOOK_EDIT: "notebook_path",
    Tool.GLOB: "pattern",
    Tool.GREP: "pattern",
    Tool.WEB_FETCH: "url",
    Tool.WEB_SEARCH: "query",
    Tool.AGENT: "subagent_type",
    Tool.TASK: "subagent_type",
    Tool.SKILL: "skill",
}
# Tools without a mapping (MCP, new ones) use the first of these that is set
FALLBACK_FIELDS = ("command", "file_path", "notebook_path", "url", "query", "path")


class Effect(StrEnum):
    """Declared strongest first: that order is the precedence"""

    DENY = "Deny"
    ASK = "Ask"
    ALLOW = "Allow"


class Operator(StrEnum):
    STRING_EQUALS = "StringEquals"
    STRING_NOT_EQUALS = "StringNotEquals"
    STRING_LIKE = "StringLike"
    STRING_NOT_LIKE = "StringNotLike"
    STRING_REGEX = "StringRegex"
    STRING_NOT_REGEX = "StringNotRegex"
    NULL = "Null"

    @property
    def negated(self) -> bool:
        return "Not" in self.value

    def test(self, value: str, pattern: str) -> bool:
        match self:
            case Operator.STRING_EQUALS | Operator.STRING_NOT_EQUALS:
                return value == pattern
            case Operator.STRING_LIKE | Operator.STRING_NOT_LIKE:
                return fnmatchcase(value, pattern)
            case Operator.STRING_REGEX | Operator.STRING_NOT_REGEX:
                return re.search(pattern, value) is not None
            case Operator.NULL:
                return (value == "") == (pattern.lower() == "true")


class Context:
    """Policy variables. Git and herdr only run when a rule reads their values."""

    VARIABLES = frozenset(
        {
            "tool", "resource", "command", "file_path", "url", "cwd",
            "permission_mode", "agent_type", "session_id",
            "project", "git_repo", "git_branch",
            "herdr_agent", "herdr_project", "herdr_role", "herdr_session",
            "herdr_pane", "herdr_tab", "herdr_workspace",
        }
    )  # fmt: skip

    def __init__(self, event: dict):
        self.input: dict = event.get("tool_input") or {}
        self.tool: str = event.get("tool_name") or ""
        self.cwd: str = event.get("cwd") or os.getcwd()
        self.permission_mode: str = event.get("permission_mode") or ""
        self.agent_type: str = event.get("agent_type") or ""
        self.session_id: str = event.get("session_id") or ""
        self.command: str = self.input.get("command") or ""
        self.file_path: str = (
            self.input.get("file_path") or self.input.get("notebook_path") or ""
        )
        self.url: str = self.input.get("url") or ""
        self.herdr_pane = os.environ.get("HERDR_PANE_ID", "")
        self.herdr_tab = os.environ.get("HERDR_TAB_ID", "")
        self.herdr_workspace = os.environ.get("HERDR_WORKSPACE_ID", "")

    def __getitem__(self, name: str) -> str:
        if name not in self.VARIABLES:
            warn(f"unknown variable {name}")
            return ""
        return getattr(self, name)

    def substitute(self, text: str) -> str:
        return VAR.sub(lambda m: self[m.group(1)], text) if "${" in text else text

    @cached_property
    def resource(self) -> str:
        key = Tool(self.tool).resource_field if Tool.known(self.tool) else None
        keys = (key,) if key else FALLBACK_FIELDS
        return next(
            (v for k in keys if isinstance(v := self.input.get(k), str) and v), ""
        )

    # git

    @cached_property
    def _git_root(self) -> str:
        return run("git", "-C", self.cwd, "rev-parse", "--show-toplevel")

    @cached_property
    def git_repo(self) -> str:
        return os.path.basename(self._git_root)

    @cached_property
    def git_branch(self) -> str:
        return run("git", "-C", self.cwd, "branch", "--show-current")

    @cached_property
    def project(self) -> str:
        return os.path.basename(self._git_root or self.cwd.rstrip("/"))

    # herdr: names are <project>-<role>, the overseer is cto

    @cached_property
    def _herdr(self) -> dict:
        """This pane's entry from `herdr agent list`, cached for HERDR_CACHE_TTL seconds"""
        if os.environ.get("HERDR_ENV") != "1" or not self.herdr_pane:
            return {}
        socket = os.environ.get("HERDR_SOCKET_PATH", "")
        key = f"{socket}:{self.herdr_pane}".encode().hex()[-48:]
        cache = os.path.join(
            os.environ.get("TMPDIR", "/tmp"),
            f"claude-policy-herdr-{os.getuid()}-{key}.json",
        )
        try:
            if time.time() - os.path.getmtime(cache) < HERDR_CACHE_TTL:
                with open(cache, encoding="utf-8") as f:
                    return json.load(f)
        except (OSError, ValueError):
            pass
        try:
            agents = (
                json.loads(run("herdr", "agent", "list") or "{}")
                .get("result", {})
                .get("agents", [])
            )
        except ValueError:
            return {}
        agent = next((a for a in agents if a.get("pane_id") == self.herdr_pane), {})
        if (
            agent
        ):  # never cache a miss: a just-started agent must show up on the next call
            try:
                tmp = f"{cache}.{os.getpid()}"
                with open(tmp, "w", encoding="utf-8") as f:
                    json.dump(agent, f)
                os.replace(tmp, cache)
            except OSError:
                pass
        return agent

    @cached_property
    def herdr_agent(self) -> str:
        return self._herdr.get("name") or ""

    @cached_property
    def herdr_session(self) -> str:
        return (self._herdr.get("agent_session") or {}).get("value") or ""

    @cached_property
    def _herdr_parts(self) -> tuple[str, str]:
        if self.herdr_agent == "cto":
            return "management", "cto"
        project, _, role = self.herdr_agent.rpartition("-")
        return project, role

    @property
    def herdr_project(self) -> str:
        return self._herdr_parts[0]

    @property
    def herdr_role(self) -> str:
        return self._herdr_parts[1]


class Condition:
    __slots__ = ("operator", "values", "variable")

    def __init__(self, operator: Operator, variable: str, values: tuple[str, ...]):
        self.operator = operator
        self.variable = variable
        self.values = values

    def holds(self, ctx: Context) -> bool:
        value = ctx[self.variable]
        hit = any(self.operator.test(value, ctx.substitute(p)) for p in self.values)
        return hit != self.operator.negated


class Statement:
    __slots__ = (
        "action",
        "conditions",
        "effect",
        "not_action",
        "not_resource",
        "reason",
        "resource",
        "sid",
    )

    def __init__(
        self,
        effect: Effect,
        sid: str = UNNAMED,
        action: tuple[str, ...] | None = None,
        not_action: tuple[str, ...] | None = None,
        resource: tuple[str, ...] | None = None,
        not_resource: tuple[str, ...] | None = None,
        conditions: tuple[Condition, ...] = (),
        reason: str = "",
    ):
        self.effect = effect
        self.sid = sid
        self.action = action
        self.not_action = not_action
        self.resource = resource
        self.not_resource = not_resource
        self.conditions = conditions
        self.reason = reason

    @classmethod
    def parse(cls, raw: dict) -> Statement | None:
        """None, with a warning, for a statement that can't be evaluated"""
        sid = raw.get("Sid") or UNNAMED
        try:
            effect = Effect(str(raw.get("Effect", "")).capitalize())
            conditions = tuple(
                Condition(Operator(op), variable, as_tuple(values))
                for op, pairs in (raw.get("Condition") or {}).items()
                for variable, values in pairs.items()
            )
        except ValueError as e:
            warn(f"skipping {sid}: {e}")
            return None

        def opt(key: str) -> tuple[str, ...] | None:
            return as_tuple(raw[key]) if key in raw else None

        statement = cls(
            effect=effect,
            sid=sid,
            action=opt("Action"),
            not_action=opt("NotAction"),
            resource=opt("Resource"),
            not_resource=opt("NotResource"),
            conditions=conditions,
            reason=raw.get("Reason") or "",
        )
        for name in (statement.action or ()) + (statement.not_action or ()):
            if (
                not GLOB_CHARS & set(name)
                and not name.startswith("mcp__")
                and not Tool.known(name)
            ):
                warn(f"{sid}: unknown tool {name!r} in Action")
        return statement

    def matches(self, ctx: Context) -> bool:
        def any_glob(value: str, patterns: tuple[str, ...]) -> bool:
            return any(fnmatchcase(value, ctx.substitute(p)) for p in patterns)

        # Cheapest checks first; conditions may shell out to git or herdr
        return (
            (self.action is None or any_glob(ctx.tool, self.action))
            and not (self.not_action and any_glob(ctx.tool, self.not_action))
            and (self.resource is None or any_glob(ctx.resource, self.resource))
            and not (self.not_resource and any_glob(ctx.resource, self.not_resource))
            and all(c.holds(ctx) for c in self.conditions)
        )

    def decision(self, ctx: Context) -> dict:
        reason = f"policy {self.effect.lower()}: {self.sid}"
        if self.reason:
            reason += f" ({ctx.substitute(self.reason)})"
        return {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": self.effect.lower(),
                "permissionDecisionReason": reason,
            }
        }


def decide(statements: list[Statement], ctx: Context) -> dict | None:
    """The first matching statement of the strongest effect, or None"""
    for effect in Effect:
        for statement in statements:
            if statement.effect is effect and statement.matches(ctx):
                return statement.decision(ctx)
    return None


def main() -> int:
    path = os.environ.get("CLAUDE_POLICY_FILE") or DEFAULT_POLICY
    if not os.path.isfile(path):
        return 0
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return 0
    try:
        with open(path, encoding="utf-8") as f:
            raw = json.load(f)
        if not isinstance(raw, list) or not all(isinstance(r, dict) for r in raw):
            raise ValueError("expected a JSON array of statement objects")
    except (OSError, ValueError) as e:
        warn(f"cannot read {path}: {e}")
        return 1
    statements = [s for r in raw if (s := Statement.parse(r))]
    if decision := decide(statements, Context(event)):
        print(json.dumps(decision))
    return 0


if __name__ == "__main__":
    sys.exit(main())
