package main

// config.go — constants, environment-driven config, logging, and small
// process-level helpers (shell quoting, stderr/exit). Everything here is
// dependency-free so the rest of the program (and the tests) can rely on it.

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// prefix names the tool everywhere: state dir, log file, agent_name prefix.
const prefix = "tmux-subagents-claude"

// Claude --model choices offered by `spawn --model`. Newest first; keep in sync
// with SKILL.md / tools-and-models.md.
var models = []string{
	"claude-opus-4-8",
	"claude-opus-4-7",
	"claude-opus-4-5",
	"claude-sonnet-4-6",
	"claude-sonnet-4-5",
	"claude-haiku-4-5",
	"claude-haiku-4-5-20251001",
}

// effortLevels are the `--effort` choices passed through to claude.
var effortLevels = []string{"low", "medium", "high", "xhigh", "max", "auto"}

// permissionModes are the `--permission-mode` choices. "auto" proceeds without
// the one-time "Bypass Permissions mode" confirmation screen that would wedge a
// freshly spawned, unattended pane. bypassPermissions is intentionally excluded.
var permissionModes = []string{"auto", "acceptEdits", "dontAsk", "default", "plan"}

const defaultPermissionMode = "auto"

// keeperWindow anchors the detached `agents` session. Without it, the last agent
// pane exiting closes the only window and tmux destroys the whole session,
// breaking status/result/capture/cleanup. The keeper tails the log file: `tail
// -F` never exits (so the session survives) and doubles as a live activity view
// when the agents session is attached. `-F` follows by name and retries if the
// file is missing/rotated; `-n +1` shows existing contents from the top.
const keeperWindow = "__keeper__"

func keeperCmd() string {
	return "exec tail -n +1 -F " + shellQuote(logPath())
}

// ---------------------------------------------------------------------------
// Environment-derived paths and flags
// ---------------------------------------------------------------------------

func homeDir() string {
	if h, err := os.UserHomeDir(); err == nil && h != "" {
		return h
	}
	return os.Getenv("HOME")
}

func stateDir() string {
	return filepath.Join(homeDir(), ".local", "share", prefix)
}

func logPath() string {
	return envOr("TMUX_AGENT_LOG_PATH", filepath.Join("/tmp", prefix+".log"))
}

func logEnabled() bool { return envBool("TMUX_AGENT_LOG", true) }
func logDebugOn() bool { return envBool("TMUX_AGENT_DEBUG", false) }

func envOr(name, def string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return def
}

func envBool(name string, def bool) bool {
	v := strings.ToLower(strings.TrimSpace(os.Getenv(name)))
	if v == "" {
		return def
	}
	return v == "1" || v == "true" || v == "yes"
}

func envFloat(name string, def float64) float64 {
	v := strings.TrimSpace(os.Getenv(name))
	if v == "" {
		return def
	}
	if f, err := strconv.ParseFloat(v, 64); err == nil {
		return f
	}
	return def
}

func envInt(name string, def int) int {
	v := strings.TrimSpace(os.Getenv(name))
	if v == "" {
		return def
	}
	if n, err := strconv.Atoi(v); err == nil {
		return n
	}
	return def
}

// ---------------------------------------------------------------------------
// Config — all timing/limit "magic numbers" in one place, env-overridable via
// the existing TMUX_AGENT_* convention. Built once in main via ConfigFromEnv.
// ---------------------------------------------------------------------------

// Config holds tunables. Durations are in seconds (converted to time.Duration
// at use). WaitTimeout <= 0 means "wait forever" (preserves the old behavior).
type Config struct {
	SpawnReadyTimeout float64 // wait for the ❯ prompt after launching claude
	SpawnPoll         float64 // poll interval while waiting for ❯
	RedrawSettle      float64 // pause after shrinking the window by a row
	RedrawAfter       float64 // pause after restoring window height
	ResetSettle       float64 // pause after C-u clears the input line
	PasteSettle       float64 // pause between paste and Enter
	VerifySettle      float64 // pause before capturing to verify submission
	WaitPoll          float64 // poll interval for --wait loops
	WaitTimeout       float64 // max --wait duration (<=0 = infinite)
	VerifyTailLines   int     // how many trailing lines to scan for the needle
	VerifyNeedleLen   int     // length of the text tail used as the needle
	CaptureScrollback int     // lines for `capture full`
}

func defaultConfig() Config {
	return Config{
		SpawnReadyTimeout: 30,
		SpawnPoll:         0.25,
		RedrawSettle:      0.15,
		RedrawAfter:       0.20,
		ResetSettle:       0.05,
		PasteSettle:       0.05,
		VerifySettle:      0.30,
		WaitPoll:          2,
		WaitTimeout:       1800,
		VerifyTailLines:   6,
		VerifyNeedleLen:   40,
		CaptureScrollback: 3000,
	}
}

// ConfigFromEnv returns the defaults overlaid with any TMUX_AGENT_* overrides.
// Malformed values fall back to the default for that field.
func ConfigFromEnv() Config {
	c := defaultConfig()
	c.SpawnReadyTimeout = envFloat("TMUX_AGENT_SPAWN_TIMEOUT", c.SpawnReadyTimeout)
	c.SpawnPoll = envFloat("TMUX_AGENT_SPAWN_POLL", c.SpawnPoll)
	c.RedrawSettle = envFloat("TMUX_AGENT_REDRAW_SETTLE", c.RedrawSettle)
	c.RedrawAfter = envFloat("TMUX_AGENT_REDRAW_AFTER", c.RedrawAfter)
	c.ResetSettle = envFloat("TMUX_AGENT_RESET_SETTLE", c.ResetSettle)
	c.PasteSettle = envFloat("TMUX_AGENT_PASTE_SETTLE", c.PasteSettle)
	c.VerifySettle = envFloat("TMUX_AGENT_VERIFY_SETTLE", c.VerifySettle)
	c.WaitPoll = envFloat("TMUX_AGENT_WAIT_POLL", c.WaitPoll)
	c.WaitTimeout = envFloat("TMUX_AGENT_WAIT_TIMEOUT", c.WaitTimeout)
	c.VerifyTailLines = envInt("TMUX_AGENT_VERIFY_TAIL", c.VerifyTailLines)
	c.VerifyNeedleLen = envInt("TMUX_AGENT_VERIFY_NEEDLE", c.VerifyNeedleLen)
	c.CaptureScrollback = envInt("TMUX_AGENT_SCROLLBACK", c.CaptureScrollback)
	return c
}

// cfg is the process-wide config, set in main().
var cfg = defaultConfig()

func sleep(seconds float64) {
	if seconds > 0 {
		time.Sleep(time.Duration(seconds * float64(time.Second)))
	}
}

// ---------------------------------------------------------------------------
// Logging — file-only (never stdout), controlled by TMUX_AGENT_LOG* env vars.
// ---------------------------------------------------------------------------

var logWriter io.Writer

func setupLogging() {
	if !logEnabled() {
		return
	}
	f, err := os.OpenFile(logPath(), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err == nil {
		logWriter = f
	}
}

func logl(level, format string, a ...any) {
	if logWriter == nil {
		return
	}
	if level == "DEBUG" && !logDebugOn() {
		return
	}
	msg := fmt.Sprintf(format, a...)
	fmt.Fprintf(logWriter, "%s %-5s %s %s\n",
		time.Now().Format("2006-01-02 15:04:05"), level, prefix, msg)
}

func logDebugf(f string, a ...any) { logl("DEBUG", f, a...) }
func logInfof(f string, a ...any)  { logl("INFO", f, a...) }
func logWarnf(f string, a ...any)  { logl("WARN", f, a...) }
func logErrorf(f string, a ...any) { logl("ERROR", f, a...) }

// ---------------------------------------------------------------------------
// stderr / exit helpers (mirror the Python sys.exit semantics: 0 ok, 1 error,
// 2 submission-or-wait failure).
// ---------------------------------------------------------------------------

func stderrln(format string, a ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", a...)
}

func exitErr(code int, format string, a ...any) {
	stderrln(format, a...)
	os.Exit(code)
}

// shellQuote mimics Python's shlex.quote: returns a POSIX-shell-safe single
// token. Used for the keeper command and the resurrect `cd <dir> && ...` line.
func shellQuote(s string) string {
	if s == "" {
		return "''"
	}
	safe := true
	for _, r := range s {
		if !(r == '_' || r == '-' || r == '/' || r == '.' || r == '@' ||
			(r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9')) {
			safe = false
			break
		}
	}
	if safe {
		return s
	}
	return "'" + strings.ReplaceAll(s, "'", `'"'"'`) + "'"
}

// shellJoin mimics Python's shlex.join: shell-quote each part and space-join.
func shellJoin(parts []string) string {
	q := make([]string, len(parts))
	for i, p := range parts {
		q[i] = shellQuote(p)
	}
	return strings.Join(q, " ")
}
