package main

// io_test.go — tests for the filesystem-touching read logic (transcript parsing,
// session status, cwd recovery, path derivation) using a temp HOME, plus the
// pure buildRows core with injected dependencies.

import (
	"os"
	"path/filepath"
	"strconv"
	"testing"
)

func writeFile(t *testing.T, path, content string) {
	t.Helper()

	err := os.MkdirAll(filepath.Dir(path), 0o755)
	if err != nil {
		t.Fatal(err)
	}

	err = os.WriteFile(path, []byte(content), 0o644)
	if err != nil {
		t.Fatal(err)
	}
}

func TestJSONLPath(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	meta := Agent{CWD: "/a/b_c", SessionID: "sid-1"}

	want := filepath.Join(home, ".claude", "projects", "-a-b-c", "sid-1.jsonl")
	if got := jsonlPath(meta); got != want {
		t.Errorf("jsonlPath = %q, want %q", got, want)
	}
}

func TestLastResponse(t *testing.T) {
	dir := t.TempDir()
	jf := filepath.Join(dir, "t.jsonl")
	writeFile(t, jf, `{"type":"user","message":{"role":"user"}}
{"type":"user","message":{"role":"user","content":"a plain string, not an array"}}
{"type":"assistant","message":{"stop_reason":"tool_use","content":[{"type":"text","text":"ignore tool_use"}]}}
{"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"older"}]}}
{"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"l1"},{"type":"thinking","text":"hidden"},{"type":"text","text":"l2"}]}}
`)

	got, ok := lastResponse(jf)
	if !ok {
		t.Fatal("expected a response")
	}

	if got != "l1\nl2" {
		t.Errorf("lastResponse = %q, want %q (last end_turn, text blocks joined, non-text ignored)", got, "l1\nl2")
	}

	// No end_turn anywhere -> not found.
	jf2 := filepath.Join(dir, "none.jsonl")
	writeFile(t, jf2, `{"type":"assistant","message":{"stop_reason":"tool_use","content":[{"type":"text","text":"x"}]}}
`)

	if _, ok := lastResponse(jf2); ok {
		t.Error("expected no response when no end_turn present")
	}

	// Missing file -> not found, no error.
	if _, ok := lastResponse(filepath.Join(dir, "nope.jsonl")); ok {
		t.Error("missing file should report not found")
	}
}

func TestSessionStatuses(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	sdir := filepath.Join(home, ".claude", "sessions")
	writeFile(t, filepath.Join(sdir, "100.json"), `{"sessionId":"aaa","status":"busy"}`)
	writeFile(t, filepath.Join(sdir, "101.json"), `{"sessionId":"bbb"}`) // no status -> idle
	writeFile(t, filepath.Join(sdir, "bad.json"), `{not json`)           // skipped

	st := sessionStatuses()
	if st["aaa"] != "busy" {
		t.Errorf("aaa = %q, want busy", st["aaa"])
	}

	if st["bbb"] != "idle" {
		t.Errorf("bbb = %q, want idle (default)", st["bbb"])
	}

	if _, ok := st["bad"]; ok {
		t.Error("malformed session file should be skipped")
	}
}

func TestSessionIsLive(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	sdir := filepath.Join(home, ".claude", "sessions")

	// Live: a session file named after THIS process's pid.
	writeFile(t, filepath.Join(sdir, strconv.Itoa(os.Getpid())+".json"), `{"sessionId":"live-sid","status":"busy"}`)
	// Dead: a pid above pid_max, so signal-0 returns ESRCH.
	writeFile(t, filepath.Join(sdir, "999999999.json"), `{"sessionId":"dead-sid"}`)

	if !sessionIsLive("live-sid") {
		t.Error("live-sid should be live (file named after current pid)")
	}

	if sessionIsLive("dead-sid") {
		t.Error("dead-sid should be not live (defunct pid)")
	}

	if sessionIsLive("no-such-sid") {
		t.Error("unknown session should be not live")
	}
}

func TestSessionCWD(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	jf := filepath.Join(home, ".claude", "projects", "-some-slug", "sid-9.jsonl")
	writeFile(t, jf, `{"type":"control"}
{"type":"user","cwd":"/real/project/dir","message":{}}
`)

	got, ok := sessionCWD("sid-9")
	if !ok || got != "/real/project/dir" {
		t.Errorf("sessionCWD = (%q,%v), want (/real/project/dir,true)", got, ok)
	}

	if _, ok := sessionCWD("does-not-exist"); ok {
		t.Error("unknown session should report not found")
	}
}

func TestSessionName(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	// Live session file `name` wins.
	writeFile(t, filepath.Join(home, ".claude", "sessions", "200.json"),
		`{"sessionId":"live-1","name":"my-live-agent"}`)

	if got := sessionName("live-1"); got != "my-live-agent" {
		t.Errorf("sessionName(live) = %q, want my-live-agent", got)
	}

	// No live file -> fall back to transcript custom-title (last one wins).
	writeFile(t, filepath.Join(home, ".claude", "projects", "-slug", "dead-1.jsonl"),
		`{"type":"user","message":{}}
{"type":"custom-title","customTitle":"renamed-agent"}
`)

	if got := sessionName("dead-1"); got != "renamed-agent" {
		t.Errorf("sessionName(transcript) = %q, want renamed-agent", got)
	}

	// Unknown session -> "".
	if got := sessionName("nope"); got != "" {
		t.Errorf("sessionName(unknown) = %q, want empty", got)
	}
}

func TestSanitizeTask(t *testing.T) {
	cases := map[string]string{
		"subagent-dotfiles-smoke": "subagent-dotfiles-smoke", // already clean
		"My Session":              "My-Session",              // space -> -
		"a/b c":                   "a-b-c",                   // slash + space
		"  trim ":                 "trim",                    // outer separators trimmed
	}
	for in, want := range cases {
		if got := sanitizeTask(in); got != want {
			t.Errorf("sanitizeTask(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestBuildRows(t *testing.T) {
	agents := map[string]Agent{
		"a": {PaneID: "%1", SessionID: "s1", CWD: "/repo/sub"},   // busy
		"b": {PaneID: "%2", SessionID: "s2", CWD: "/repo-other"}, // foreign cwd (hired) -> dead pane
		"c": {PaneID: "%3", SessionID: "s3", CWD: "/repo"},       // idle+resp
		"d": {PaneID: "%4", SessionID: "s4", CWD: "/repo/x"},     // dead pane
		"e": {PaneID: "%5", SessionID: "s5", CWD: "/repo/y"},     // live no-status
		"f": {PaneID: "%6", SessionID: "s6", CWD: "/repo/z"},     // idle no-resp -> empty
	}
	panes := map[string]bool{"%1": true, "%3": true, "%5": true, "%6": true} // %2,%4 dead
	statuses := map[string]string{"s1": "busy", "s3": "idle", "s6": "idle"}
	hasResponse := func(m Agent) bool { return m.SessionID == "s3" } // only c has a reply
	paneCtx := func(string) string { return "CTX" }

	rows := buildRows("win", agents, rowDeps{
		panes:       panes,
		statuses:    statuses,
		hasResponse: hasResponse,
		paneCtx:     paneCtx,
	})

	// No cwd filter: every agent shows, sorted by task: a,b,c,d,e,f.
	if len(rows) != 6 {
		t.Fatalf("got %d rows, want 6 (no scope filter): %+v", len(rows), rows)
	}

	byTask := map[string]StatusRow{}
	order := make([]string, 0, len(rows))

	for _, r := range rows {
		byTask[r.Task] = r
		order = append(order, r.Task)
	}

	if got := order; !equalSlice(got, []string{"a", "b", "c", "d", "e", "f"}) {
		t.Errorf("row order = %v, want [a b c d e f] (sorted)", got)
	}

	checks := []struct {
		task, status, pane, ctx string
	}{
		{"a", "busy", "%1", "CTX"},
		{"b", "dead", "%2", "-"}, // foreign-cwd hired agent, dead pane -> dead
		{"c", "idle", "%3", "CTX"},
		{"d", "dead", "%4", "-"},       // dead pane -> dead + no context
		{"e", "starting", "%5", "CTX"}, // live, no session status yet
		{"f", "empty", "%6", "CTX"},    // idle but no reply -> empty
	}
	for _, c := range checks {
		r := byTask[c.task]
		if r.Status != c.status || r.Pane != c.pane || r.Context != c.ctx {
			t.Errorf("task %s = {status:%q pane:%q ctx:%q}, want {status:%q pane:%q ctx:%q}",
				c.task, r.Status, r.Pane, r.Context, c.status, c.pane, c.ctx)
		}
		// Regression anchor for the old r[1]/r[2] bug: Task and Pane are distinct
		// fields; a status <task> filter must match Task, never Pane.
		if r.Task == r.Pane {
			t.Errorf("task %s: Task and Pane should be different fields", c.task)
		}
	}
}

func equalSlice(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}

	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}

	return true
}
