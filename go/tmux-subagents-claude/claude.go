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

type jsonlRecord struct {
	Type    string `json:"type"`
	CWD     string `json:"cwd"`
	Message struct {
		StopReason string `json:"stop_reason"`
		Content    []struct {
			Type string `json:"type"`
			Text string `json:"text"`
		} `json:"content"`
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
	defer f.Close()

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
		var texts []string
		for _, c := range rec.Message.Content {
			if c.Type == "text" {
				texts = append(texts, c.Text)
			}
		}
		if len(texts) > 0 {
			last = strings.Join(texts, "\n")
			found = true
		}
	}
	return last, found
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
				f.Close()
				logDebugf("sessionCWD %s -> %s", sessionID, rec.CWD)
				return rec.CWD, true
			}
		}
		f.Close()
	}
	logDebugf("sessionCWD %s -> not found", sessionID)
	return "", false
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
