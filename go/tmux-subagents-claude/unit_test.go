package main

// unit_test.go — pure-logic tests (no tmux / no filesystem) for the bits that
// have historically caused bugs: cwd encoding, repo scoping, the status
// task-filter column, config parsing, and submit verification.

import (
	"encoding/json"
	"testing"
)

func TestCwdToProjectDir(t *testing.T) {
	cases := map[string]string{
		"/home/x/dev/p":       "-home-x-dev-p",
		"/a/transcribe_audio": "-a-transcribe-audio", // underscore -> -
		"/a/b.c":              "-a-b-c",              // dot -> -
		"/a/b c":              "-a-b-c",              // space -> -
		"abc123":              "abc123",              // alphanumerics preserved
	}
	for in, want := range cases {
		if got := cwdToProjectDir(in); got != want {
			t.Errorf("cwdToProjectDir(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestWinKey(t *testing.T) {
	cases := map[string]string{
		"obsidian":  "obsidian",
		"a/b":       "a-b",
		"my window": "my_window",
		"a/b c":     "a-b_c",
	}
	for in, want := range cases {
		if got := winKey(in); got != want {
			t.Errorf("winKey(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestInScope(t *testing.T) {
	cases := []struct {
		agentCWD, scopeRoot string
		want                bool
	}{
		{"/repo", "/repo", true},         // exact root
		{"/repo/sub/dir", "/repo", true}, // subdir
		{"/repo-other", "/repo", false},  // sibling sharing a prefix — boundary
		{"/other", "/repo", false},       // unrelated
		{"/anything", "", true},          // empty scope = include all
		{"/repo", "/repo/sub", false},    // parent is not in child scope
	}
	for _, c := range cases {
		if got := inScope(c.agentCWD, c.scopeRoot); got != c.want {
			t.Errorf("inScope(%q, %q) = %v, want %v", c.agentCWD, c.scopeRoot, got, c.want)
		}
	}
}

func TestProjectScope(t *testing.T) {
	orig := runGitToplevel
	defer func() { runGitToplevel = orig }()

	runGitToplevel = func(string) (string, bool) { return "/repo/root", true }

	if got := projectScope("/repo/root/sub"); got != "/repo/root" {
		t.Errorf("projectScope in-repo = %q, want /repo/root", got)
	}

	runGitToplevel = func(string) (string, bool) { return "", false }

	if got := projectScope("/tmp/x"); got != "/tmp/x" {
		t.Errorf("projectScope outside-repo = %q, want /tmp/x (cwd fallback)", got)
	}
}

func TestAgentNameFor(t *testing.T) {
	if got := agentNameFor("win", "task", nil); got != "subagent-win-task" {
		t.Errorf("fallback name = %q", got)
	}

	m := &Agent{AgentName: "custom-name"}
	if got := agentNameFor("win", "task", m); got != "custom-name" {
		t.Errorf("stored name = %q, want custom-name", got)
	}

	empty := &Agent{}
	if got := agentNameFor("w", "t", empty); got != "subagent-w-t" {
		t.Errorf("empty stored name should fall back, got %q", got)
	}
}

func TestAgentJSONRoundTrip(t *testing.T) {
	a := Agent{PaneID: "%1", SessionID: "sid", CWD: "/x", AgentName: "n"}

	b, err := json.Marshal(a)
	if err != nil {
		t.Fatal(err)
	}

	var m map[string]any
	if err := json.Unmarshal(b, &m); err != nil {
		t.Fatal(err)
	}

	want := []string{"pane_id", "session_id", "cwd", "agent_name"}
	if len(m) != len(want) {
		t.Fatalf("Agent JSON has %d keys (%v), want exactly %v", len(m), m, want)
	}

	for _, k := range want {
		if _, ok := m[k]; !ok {
			t.Errorf("Agent JSON missing key %q", k)
		}
	}
}

func TestConfigFromEnv(t *testing.T) {
	// Unset -> defaults.
	t.Setenv("TMUX_AGENT_WAIT_TIMEOUT", "")
	t.Setenv("TMUX_AGENT_WAIT_POLL", "")

	if c := ConfigFromEnv(); c.WaitTimeout != 1800 || c.WaitPoll != 2 {
		t.Errorf("defaults wrong: WaitTimeout=%v WaitPoll=%v", c.WaitTimeout, c.WaitPoll)
	}
	// Override.
	t.Setenv("TMUX_AGENT_WAIT_TIMEOUT", "60")

	if c := ConfigFromEnv(); c.WaitTimeout != 60 {
		t.Errorf("override WaitTimeout=%v, want 60", c.WaitTimeout)
	}
	// Malformed -> default.
	t.Setenv("TMUX_AGENT_WAIT_TIMEOUT", "not-a-number")

	if c := ConfigFromEnv(); c.WaitTimeout != 1800 {
		t.Errorf("malformed should fall back to default, got %v", c.WaitTimeout)
	}
	// <=0 means infinite (still parsed as the value; waitDeadline interprets it).
	t.Setenv("TMUX_AGENT_WAIT_TIMEOUT", "0")

	if c := ConfigFromEnv(); c.WaitTimeout != 0 {
		t.Errorf("zero timeout = %v, want 0", c.WaitTimeout)
	}
	// Int override.
	t.Setenv("TMUX_AGENT_VERIFY_TAIL", "9")

	if c := ConfigFromEnv(); c.VerifyTailLines != 9 {
		t.Errorf("VerifyTailLines=%v, want 9", c.VerifyTailLines)
	}
}

func TestVerifySubmittedFrom(t *testing.T) {
	// Needle (last 40 chars of last line) absent from tail -> submitted.
	if !verifySubmittedFrom("❯ \nfooter line", "please do the thing", 6, 40) {
		t.Error("expected submitted=true when text absent from tail")
	}
	// Needle still on the input line -> NOT submitted.
	snap := "some output\n❯ please do the thing"
	if verifySubmittedFrom(snap, "please do the thing", 6, 40) {
		t.Error("expected submitted=false when text still on input line")
	}
	// Empty text -> trivially submitted.
	if !verifySubmittedFrom("anything", "   ", 6, 40) {
		t.Error("empty text should be treated as submitted")
	}
	// Trailing blank lines must be stripped before taking the tail, else the
	// still-present prompt would fall outside the slice and read as submitted.
	snapBlanks := "❯ unsubmitted text here\n\n\n\n\n\n\n\n"
	if verifySubmittedFrom(snapBlanks, "unsubmitted text here", 6, 40) {
		t.Error("trailing blanks should be stripped; prompt still present => not submitted")
	}
}

func TestShellQuoteJoin(t *testing.T) {
	if got := shellQuote("plain-path/ok.txt"); got != "plain-path/ok.txt" {
		t.Errorf("safe string should be unquoted, got %q", got)
	}

	if got := shellQuote("has space"); got != "'has space'" {
		t.Errorf("space should be quoted, got %q", got)
	}

	if got := shellQuote("it's"); got != `'it'"'"'s'` {
		t.Errorf("single quote escaping wrong, got %q", got)
	}

	if got := shellJoin([]string{"claude", "--resume", "abc"}); got != "claude --resume abc" {
		t.Errorf("shellJoin = %q", got)
	}

	if got := shellJoin([]string{"a", "b c"}); got != "a 'b c'" {
		t.Errorf("shellJoin quoting = %q", got)
	}
}

func TestPaneContextRegex(t *testing.T) {
	// contextRe used by paneContext; verify it pulls the usage out of a footer.
	line := "↑601 ↓131 R84.9k W1.9k $0.042 90.0k/1000.0k (9.0%)"
	if got := contextRe.FindString(line); got != "90.0k/1000.0k (9.0%)" {
		t.Errorf("context regex = %q, want 90.0k/1000.0k (9.0%%)", got)
	}

	if contextRe.FindString("no usage here") != "" {
		t.Error("regex should not match a line without usage")
	}
}

func TestClassifyWait(t *testing.T) {
	dialog := ` Bash command
   rtk ls -d ../dotfiles/skills/*
   Run shell command

 Do you want to proceed?
 ❯ 1. Yes
   2. Yes, and don't ask again for: rtk ls *
   3. No

 Esc to cancel · Tab to amend · ctrl+e to explain`
	if got := classifyWait(dialog); got != "permission" {
		t.Errorf("classifyWait(dialog) = %q, want permission", got)
	}

	// A normal working/idle pane (footer only) is not a permission prompt.
	if got := classifyWait("↑601 ↓131 R84.9k W1.9k $0.042 90.0k/1000.0k (9.0%)"); got != "" {
		t.Errorf("classifyWait(footer) = %q, want empty", got)
	}

	// The proceed header alone (no dialog footer) does not match.
	if got := classifyWait("Do you want to proceed? (discussing in prose)"); got != "" {
		t.Errorf("classifyWait(prose) = %q, want empty", got)
	}
}
