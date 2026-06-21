package main

// claude.go — read-only view over Claude's on-disk session state:
//   - transcript JSONL  ~/.claude/projects/<cwd-slug>/<session>.jsonl
//   - session status    ~/.claude/sessions/<pid>.json  (sessionId -> status)
//
// The cwd-slug encoding (every non-alphanumeric char -> "-") must match
// Claude's own encoding exactly, or jsonlPath misses the transcript.

import (
	"bufio"
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

var projectSlugRe = regexp.MustCompile(`[^a-zA-Z0-9]`)

// cwdToProjectDir encodes a working directory the way Claude names its project
// dir: every non-alphanumeric character (/ . _ space ...) becomes "-".
func cwdToProjectDir(cwd string) string {
	return projectSlugRe.ReplaceAllString(cwd, "-")
}

// claudeProjects is ~/.claude/projects.
func claudeProjects() string {
	return filepath.Join(homeDir(), ".claude", "projects")
}

// jsonlPath derives an agent's transcript path from its metadata.
func jsonlPath(meta Agent) string {
	cwd := meta.CWD
	if cwd == "" {
		cwd, _ = os.Getwd()
	}

	p := filepath.Join(claudeProjects(), cwdToProjectDir(cwd), meta.SessionID+".jsonl")
	logDebugf("jsonlPath cwd=%s -> %s", cwd, p)

	return p
}

// newJSONLScanner returns a bufio.Scanner with a large buffer, since assistant
// transcript lines can be big.
func newJSONLScanner(f *os.File) *bufio.Scanner {
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 64*1024), 16*1024*1024)

	return sc
}

type contentBlock struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

// jsonlRecord decodes a transcript line. Content is kept raw because the schema
// is polymorphic: assistant messages store an array of blocks, but user
// messages store a plain string. Decoding it eagerly into []contentBlock would
// fail (and warn-spam) on every user line; we decode it lazily, only for the
// assistant/end_turn lines we actually read.
type jsonlRecord struct {
	Type    string `json:"type"`
	CWD     string `json:"cwd"`
	Message struct {
		StopReason string          `json:"stop_reason"`
		Content    json.RawMessage `json:"content"`
	} `json:"message"`
}

// lastResponse returns the text of the last end_turn assistant message in a
// transcript, and whether one was found.
func lastResponse(jsonlFile string) (string, bool) {
	f, err := os.Open(jsonlFile)
	if err != nil {
		logDebugf("lastResponse: JSONL not found: %s", jsonlFile)

		return "", false
	}
	defer func() { _ = f.Close() }()

	var last string

	found := false

	sc := newJSONLScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" {
			continue
		}

		var rec jsonlRecord
		if err := json.Unmarshal([]byte(line), &rec); err != nil {
			logWarnf("lastResponse: bad JSON line in %s: %v", jsonlFile, err)

			continue
		}

		if rec.Type != "assistant" || rec.Message.StopReason != "end_turn" {
			continue
		}

		if text, ok := joinTextBlocks(rec.Message.Content); ok {
			last = text
			found = true
		}
	}

	return last, found
}

// joinTextBlocks decodes raw assistant message content and joins its text
// blocks with newlines. Returns ("", false) when content is not an array of
// blocks (e.g. an unexpected string) or carries no text — so callers skip the
// line quietly instead of warning.
func joinTextBlocks(raw json.RawMessage) (string, bool) {
	var blocks []contentBlock
	if err := json.Unmarshal(raw, &blocks); err != nil {
		return "", false
	}

	var texts []string

	for _, c := range blocks {
		if c.Type == "text" {
			texts = append(texts, c.Text)
		}
	}

	if len(texts) == 0 {
		return "", false
	}

	return strings.Join(texts, "\n"), true
}

// sessionCWD recovers the directory a session was created in, by scanning its
// transcript for a recorded cwd. This survives cleanup popping the in-memory
// metadata, so resurrect can cd back to the original project dir. Resurrect-only
// fallback. Returns ("", false) if no transcript or no cwd is found.
func sessionCWD(sessionID string) (string, bool) {
	matches, _ := filepath.Glob(filepath.Join(claudeProjects(), "*", sessionID+".jsonl"))
	for _, jf := range matches {
		f, err := os.Open(jf)
		if err != nil {
			continue
		}

		sc := newJSONLScanner(f)
		for sc.Scan() {
			line := strings.TrimSpace(sc.Text())
			if line == "" {
				continue
			}

			var rec struct {
				CWD string `json:"cwd"`
			}
			if err := json.Unmarshal([]byte(line), &rec); err != nil {
				continue
			}

			if rec.CWD != "" {
				_ = f.Close()

				logDebugf("sessionCWD %s -> %s", sessionID, rec.CWD)

				return rec.CWD, true
			}
		}

		_ = f.Close()
	}

	logDebugf("sessionCWD %s -> not found", sessionID)

	return "", false
}

// sessionName returns a human-friendly name for a session: the live session
// file's `name`, else a `custom-title` recorded in the transcript (the source
// claudeman uses for dead sessions). "" if neither is found.
func sessionName(sessionID string) string {
	if n := sessionNameFromFile(sessionID); n != "" {
		return n
	}

	return sessionNameFromTranscript(sessionID)
}

// sessionNameFromFile reads `name` from the live ~/.claude/sessions/*.json whose
// sessionId matches (the session must still be running).
func sessionNameFromFile(sessionID string) string {
	matches, _ := filepath.Glob(filepath.Join(homeDir(), ".claude", "sessions", "*.json"))
	for _, p := range matches {
		data, err := os.ReadFile(p)
		if err != nil {
			continue
		}

		var s struct {
			SessionID string `json:"sessionId"`
			Name      string `json:"name"`
		}
		if json.Unmarshal(data, &s) == nil && s.SessionID == sessionID {
			return s.Name
		}
	}

	return ""
}

// sessionNameFromTranscript reads the last `custom-title` recorded in a
// session's transcript (survives the session ending).
func sessionNameFromTranscript(sessionID string) string {
	matches, _ := filepath.Glob(filepath.Join(claudeProjects(), "*", sessionID+".jsonl"))
	for _, jf := range matches {
		f, err := os.Open(jf)
		if err != nil {
			continue
		}

		title := scanCustomTitle(f)
		_ = f.Close()

		if title != "" {
			return title
		}
	}

	return ""
}

// scanCustomTitle returns the last custom-title text in a transcript, or "".
func scanCustomTitle(f *os.File) string {
	var title string

	sc := newJSONLScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" {
			continue
		}

		var rec struct {
			Type        string `json:"type"`
			CustomTitle string `json:"customTitle"`
		}
		if json.Unmarshal([]byte(line), &rec) == nil && rec.Type == "custom-title" && rec.CustomTitle != "" {
			title = rec.CustomTitle
		}
	}

	return title
}

// sessionStatuses returns {sessionId: status} for all running claude sessions,
// read from ~/.claude/sessions/*.json.
func sessionStatuses() map[string]string {
	statuses := map[string]string{}
	dir := filepath.Join(homeDir(), ".claude", "sessions")

	matches, _ := filepath.Glob(filepath.Join(dir, "*.json"))
	for _, p := range matches {
		data, err := os.ReadFile(p)
		if err != nil {
			logWarnf("sessionStatuses: skipping %s: %v", filepath.Base(p), err)

			continue
		}

		var s struct {
			SessionID string `json:"sessionId"`
			Status    string `json:"status"`
		}
		if err := json.Unmarshal(data, &s); err != nil {
			logWarnf("sessionStatuses: skipping %s: %v", filepath.Base(p), err)

			continue
		}

		if s.SessionID != "" {
			st := s.Status
			if st == "" {
				st = "idle"
			}

			statuses[s.SessionID] = st
		}
	}

	return statuses
}
