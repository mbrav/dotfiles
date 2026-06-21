// Command claudemux orchestrates parallel Claude Code subagents in tmux panes
// under a detached `agents` session. See the tmux-subagents-claude skill
// (SKILL.md) for the full external contract.
package main

// main.go — CLI surface. Each subcommand owns a flag.FlagSet (stdlib `flag`,
// strict ordering: flags precede positionals). Exit codes mirror the contract:
// 0 ok, 1 runtime error, 2 usage/submission/wait failure.

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"runtime/debug"
	"slices"
	"strings"
)

const usageText = `claudemux — orchestrate Claude Code subagents in tmux panes

usage: claudemux <command> [flags] [args]

commands:
  spawn      [--model M] [--tools T] [--effort L] [--permission-mode P] <task> <prompt>
  prompt     [--wait] [--no-verify] <task> <text>
  result     [--wait] <task>
  status     [--all] [task]
  resurrect  <task> <session-id>
  hire       <session-id>
  dismiss    <session-id>
  init       [--model M] [--tools T] [--effort L] [--permission-mode P] [session-id]
  capture    <task> [full|log|stop]
  cleanup    <task | --all | --prune>
  recap      <task>
  compact    <task> [description]
  redraw
  version

flags must precede positionals (e.g. result --wait foo)

2026 github.com/mbrav`

func main() {
	cfg = ConfigFromEnv()

	setupLogging()

	if len(os.Args) < 2 {
		exitErrf(2, "%s", usageText)
	}

	cmd, rest := os.Args[1], os.Args[2:]

	if cmd == "-h" || cmd == "--help" || cmd == "help" {
		fmt.Println(usageText)

		return
	}

	if cmd == "-version" || cmd == "--version" || cmd == "version" {
		printVersion()

		return
	}

	run, ok := dispatch[cmd]
	if !ok {
		exitErrf(2, "unknown command: %s\n\n%s", cmd, usageText)
	}

	run(rest)
}

// dispatch maps each subcommand to its parse-and-run handler.
var dispatch = map[string]func([]string){
	"spawn":     runSpawn,
	"prompt":    runPrompt,
	"result":    runResult,
	"status":    runStatus,
	"resurrect": runResurrect,
	"hire":      runHire,
	"dismiss":   runDismiss,
	"init":      runInit,
	"capture":   runCapture,
	"cleanup":   runCleanup,
	"recap":     runRecap,
	"compact":   runCompact,
	"redraw":    runRedraw,
}

// printVersion prints the module version and VCS commit info embedded by the
// Go toolchain. With `go install ...@latest` the module version is the resolved
// tag or pseudo-version; vcs.revision/vcs.time are also present when built from
// a VCS checkout.
func printVersion() {
	info, ok := debug.ReadBuildInfo()
	if !ok {
		fmt.Println("version: unknown")
		return
	}

	ver := info.Main.Version
	if ver == "" {
		ver = "(unknown)"
	}

	fmt.Printf("%s %s\n", info.Main.Path, ver)

	var revision, commitTime, modified string

	for _, s := range info.Settings {
		switch s.Key {
		case "vcs.revision":
			revision = s.Value
		case "vcs.time":
			commitTime = s.Value
		case "vcs.modified":
			modified = s.Value
		}
	}

	if revision != "" {
		fmt.Printf("commit:   %s\n", revision)
	}

	if commitTime != "" {
		fmt.Printf("time:     %s\n", commitTime)
	}

	if modified == "true" {
		fmt.Println("modified: true (dirty tree)")
	}
}

// ---------------------------------------------------------------------------
// flag parsing helpers
// ---------------------------------------------------------------------------

// newFlagSet builds a ContinueOnError FlagSet whose usage prints the one-line
// synopsis. Errors and usage go to stderr; main maps the parse result to an
// exit code.
func newFlagSet(name, synopsis string) *flag.FlagSet {
	fs := flag.NewFlagSet(name, flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	fs.Usage = func() {
		fmt.Fprintf(os.Stderr, "usage: %s %s\n", prefix, synopsis)
	}

	return fs
}

// parseFlags parses args and returns the positionals, enforcing the count is in
// [minPos, maxPos] (maxPos < 0 means unbounded). `-h` exits 0; any other parse
// or arity error exits 2. flag already prints the message + usage on error.
func parseFlags(fs *flag.FlagSet, args []string, minPos, maxPos int) []string {
	switch err := fs.Parse(args); {
	case errors.Is(err, flag.ErrHelp):
		os.Exit(0)
	case err != nil:
		os.Exit(2)
	}

	pos := fs.Args()
	if len(pos) < minPos || (maxPos >= 0 && len(pos) > maxPos) {
		fs.Usage()
		exitErrf(2, "%s: wrong number of arguments (got %d)", fs.Name(), len(pos))
	}

	return pos
}

// validateChoice exits 2 if val is not one of choices.
func validateChoice(flag, val string, choices []string) {
	if !slices.Contains(choices, val) {
		exitErrf(2, "invalid %s %q (choose from %s)", flag, val, strings.Join(choices, ", "))
	}
}

// ---------------------------------------------------------------------------
// per-command parsing
// ---------------------------------------------------------------------------

func runSpawn(args []string) {
	fs := newFlagSet("spawn", "spawn [--model M] [--tools T] [--effort L] [--permission-mode P] <task> <prompt>")
	model := fs.String("model", "", "claude model")
	tools := fs.String("tools", "", "comma-separated allowed tools")
	effort := fs.String("effort", "", "reasoning effort level")
	perm := fs.String("permission-mode", defaultPermissionMode, "claude permission mode")
	pos := parseFlags(fs, args, 2, 2)

	if *model != "" {
		validateChoice("--model", *model, models)
	}

	if *effort != "" {
		validateChoice("--effort", *effort, effortLevels)
	}

	if *perm == "" {
		*perm = defaultPermissionMode
	}

	validateChoice("--permission-mode", *perm, permissionModes)

	cmdSpawn(pos[0], pos[1], *model, *tools, *effort, *perm)
}

func runPrompt(args []string) {
	fs := newFlagSet("prompt", "prompt [--wait] [--no-verify] <task> <text>")
	wait := fs.Bool("wait", false, "block until a new reply lands")
	noVerify := fs.Bool("no-verify", false, "skip submit verification")
	pos := parseFlags(fs, args, 2, 2)
	cmdPrompt(pos[0], pos[1], *wait, !*noVerify)
}

func runResult(args []string) {
	fs := newFlagSet("result", "result [--wait] <task>")
	wait := fs.Bool("wait", false, "block while busy, then print the reply")
	pos := parseFlags(fs, args, 1, 1)
	cmdResult(pos[0], *wait)
}

func runStatus(args []string) {
	fs := newFlagSet("status", "status [--all] [task]")
	all := fs.Bool("all", false, "show agents across all projects, not just this repo")
	pos := parseFlags(fs, args, 0, 1)

	task := ""
	if len(pos) == 1 {
		task = pos[0]
	}

	cmdStatus(task, *all)
}

func runResurrect(args []string) {
	fs := newFlagSet("resurrect", "resurrect <task> <session-id>")
	pos := parseFlags(fs, args, 2, 2)
	cmdResurrect(pos[0], pos[1])
}

func runHire(args []string) {
	fs := newFlagSet("hire", "hire <session-id>")
	pos := parseFlags(fs, args, 1, 1)
	cmdHire(pos[0])
}

func runDismiss(args []string) {
	fs := newFlagSet("dismiss", "dismiss <session-id>")
	pos := parseFlags(fs, args, 1, 1)
	cmdDismiss(pos[0])
}

func runInit(args []string) {
	fs := newFlagSet("init", "init [--model M] [--tools T] [--effort L] [--permission-mode P] [session-id]")
	model := fs.String("model", "", "claude model")
	tools := fs.String("tools", "", "comma-separated allowed tools")
	effort := fs.String("effort", "", "reasoning effort level")
	perm := fs.String("permission-mode", defaultPermissionMode, "claude permission mode")
	pos := parseFlags(fs, args, 0, 1)

	sessionID := ""
	if len(pos) == 1 {
		sessionID = pos[0]
	}

	if *model != "" {
		validateChoice("--model", *model, models)
	}

	if *effort != "" {
		validateChoice("--effort", *effort, effortLevels)
	}

	if *perm == "" {
		*perm = defaultPermissionMode
	}

	validateChoice("--permission-mode", *perm, permissionModes)

	cmdInit(sessionID, *model, *tools, *effort, *perm)
}

func runCapture(args []string) {
	fs := newFlagSet("capture", "capture <task> [full|log|stop]")
	pos := parseFlags(fs, args, 1, 2)

	mode := ""
	if len(pos) == 2 {
		mode = pos[1]
		validateChoice("mode", mode, []string{"full", "log", "stop"})
	}

	cmdCapture(pos[0], mode)
}

func runCleanup(args []string) {
	fs := newFlagSet("cleanup", "cleanup <task | --all | --prune>")
	all := fs.Bool("all", false, "kill all agents in this window")
	prune := fs.Bool("prune", false, "drop dead entries across all windows")
	pos := parseFlags(fs, args, 0, 1)

	task := ""
	if len(pos) == 1 {
		task = pos[0]
	}
	// Required mutually-exclusive group: exactly one of task / --all / --prune.
	chosen := 0

	for _, set := range []bool{task != "", *all, *prune} {
		if set {
			chosen++
		}
	}

	if chosen != 1 {
		exitErrf(2, "cleanup requires exactly one of: <task>, --all, --prune")
	}

	cmdCleanup(task, *all, *prune)
}

func runRecap(args []string) {
	fs := newFlagSet("recap", "recap <task>")
	pos := parseFlags(fs, args, 1, 1)
	cmdRecap(pos[0])
}

func runCompact(args []string) {
	fs := newFlagSet("compact", "compact <task> [description]")
	pos := parseFlags(fs, args, 1, 2)

	desc := ""
	if len(pos) == 2 {
		desc = pos[1]
	}

	cmdCompact(pos[0], desc)
}

func runRedraw(args []string) {
	fs := newFlagSet("redraw", "redraw")
	parseFlags(fs, args, 0, 0)
	cmdRedraw()
}
