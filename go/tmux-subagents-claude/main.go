package main

// main.go — CLI surface. A small hand-rolled argument parser (stdlib only) that
// preserves the Python argparse contract: 9 subcommands, the same flags/choices/
// defaults, optional positionals, cleanup's required mutually-exclusive group,
// and exit code 2 for usage errors.

import (
	"fmt"
	"os"
	"strings"
)

const usageText = `tmux-subagents-claude — orchestrate Claude Code subagents in tmux panes

usage: tmux-subagents-claude <command> [args]

commands:
  spawn      <task> <prompt> [--model M] [--tools T] [--effort L] [--permission-mode P]
  prompt     <task> <text> [--wait] [--no-verify]
  result     <task> [--wait]
  status     [task] [--all]
  resurrect  <task> <session-id>
  capture    <task> [full|log|stop]
  cleanup    <task | --all | --prune>
  recap      <task>
  compact    <task> [description]

2026 github.com/mbrav`

func main() {
	cfg = ConfigFromEnv()
	setupLogging()

	if len(os.Args) < 2 {
		exitErr(2, "%s", usageText)
	}
	cmd := os.Args[1]
	rest := os.Args[2:]

	switch cmd {
	case "-h", "--help", "help":
		fmt.Println(usageText)
	case "spawn":
		runSpawn(rest)
	case "prompt":
		runPrompt(rest)
	case "result":
		runResult(rest)
	case "status":
		runStatus(rest)
	case "resurrect":
		runResurrect(rest)
	case "capture":
		runCapture(rest)
	case "cleanup":
		runCleanup(rest)
	case "recap":
		runRecap(rest)
	case "compact":
		runCompact(rest)
	default:
		exitErr(2, "unknown command: %s\n\n%s", cmd, usageText)
	}
}

// ---------------------------------------------------------------------------
// argument parsing helpers
// ---------------------------------------------------------------------------

func argErr(format string, a ...any) {
	exitErr(2, format, a...)
}

func set(items ...string) map[string]bool {
	m := make(map[string]bool, len(items))
	for _, s := range items {
		m[s] = true
	}
	return m
}

// parseArgs separates positionals from flags, supporting `--flag value`,
// `--flag=value`, boolean flags, `--` terminator, and `-h`/`--help`. Flags may
// appear before or after positionals (argparse-style intermixing).
func parseArgs(args []string, valFlags, boolFlags map[string]bool) (
	pos []string, vals map[string]string, bools map[string]bool, help bool,
) {
	vals = map[string]string{}
	bools = map[string]bool{}
	i := 0
	for i < len(args) {
		a := args[i]
		switch {
		case a == "--":
			pos = append(pos, args[i+1:]...)
			return
		case a == "-h" || a == "--help":
			help = true
			i++
		case strings.HasPrefix(a, "--"):
			name := a
			inline := ""
			hasInline := false
			if eq := strings.IndexByte(a, '='); eq >= 0 {
				name, inline, hasInline = a[:eq], a[eq+1:], true
			}
			switch {
			case boolFlags[name]:
				if hasInline {
					argErr("flag %s takes no value", name)
				}
				bools[name] = true
				i++
			case valFlags[name]:
				if hasInline {
					vals[name] = inline
					i++
				} else if i+1 < len(args) {
					vals[name] = args[i+1]
					i += 2
				} else {
					argErr("flag %s requires a value", name)
				}
			default:
				argErr("unknown flag: %s", name)
			}
		case strings.HasPrefix(a, "-") && len(a) > 1:
			argErr("unknown flag: %s", a)
		default:
			pos = append(pos, a)
			i++
		}
	}
	return
}

func validateChoice(flag, val string, choices []string) {
	for _, c := range choices {
		if c == val {
			return
		}
	}
	argErr("invalid %s '%s' (choose from %s)", flag, val, strings.Join(choices, ", "))
}

// ---------------------------------------------------------------------------
// per-command parsing
// ---------------------------------------------------------------------------

func runSpawn(args []string) {
	pos, vals, _, help := parseArgs(args, set("--model", "--tools", "--effort", "--permission-mode"), nil)
	if help {
		fmt.Println("usage: spawn <task> <prompt> [--model M] [--tools T] [--effort L] [--permission-mode P]")
		return
	}
	if len(pos) != 2 {
		argErr("spawn requires exactly <task> and <prompt> (got %d positional args)", len(pos))
	}
	model := vals["--model"]
	if model != "" {
		validateChoice("--model", model, models)
	}
	effort := vals["--effort"]
	if effort != "" {
		validateChoice("--effort", effort, effortLevels)
	}
	perm := vals["--permission-mode"]
	if perm == "" {
		perm = defaultPermissionMode
	} else {
		validateChoice("--permission-mode", perm, permissionModes)
	}
	cmdSpawn(pos[0], pos[1], model, vals["--tools"], effort, perm)
}

func runPrompt(args []string) {
	pos, _, bools, help := parseArgs(args, nil, set("--wait", "--no-verify"))
	if help {
		fmt.Println("usage: prompt <task> <text> [--wait] [--no-verify]")
		return
	}
	if len(pos) != 2 {
		argErr("prompt requires <task> and <text> (got %d positional args)", len(pos))
	}
	cmdPrompt(pos[0], pos[1], bools["--wait"], !bools["--no-verify"])
}

func runResult(args []string) {
	pos, _, bools, help := parseArgs(args, nil, set("--wait"))
	if help {
		fmt.Println("usage: result <task> [--wait]")
		return
	}
	if len(pos) != 1 {
		argErr("result requires <task> (got %d positional args)", len(pos))
	}
	cmdResult(pos[0], bools["--wait"])
}

func runStatus(args []string) {
	pos, _, bools, help := parseArgs(args, nil, set("--all"))
	if help {
		fmt.Println("usage: status [task] [--all]")
		return
	}
	if len(pos) > 1 {
		argErr("status takes at most one task (got %d)", len(pos))
	}
	task := ""
	if len(pos) == 1 {
		task = pos[0]
	}
	cmdStatus(task, bools["--all"])
}

func runResurrect(args []string) {
	pos, _, _, help := parseArgs(args, nil, nil)
	if help {
		fmt.Println("usage: resurrect <task> <session-id>")
		return
	}
	if len(pos) != 2 {
		argErr("resurrect requires <task> and <session-id> (got %d positional args)", len(pos))
	}
	cmdResurrect(pos[0], pos[1])
}

func runCapture(args []string) {
	pos, _, _, help := parseArgs(args, nil, nil)
	if help {
		fmt.Println("usage: capture <task> [full|log|stop]")
		return
	}
	if len(pos) < 1 || len(pos) > 2 {
		argErr("capture requires <task> and an optional mode (got %d positional args)", len(pos))
	}
	mode := ""
	if len(pos) == 2 {
		mode = pos[1]
		validateChoice("mode", mode, []string{"full", "log", "stop"})
	}
	cmdCapture(pos[0], mode)
}

func runCleanup(args []string) {
	pos, _, bools, help := parseArgs(args, nil, set("--all", "--prune"))
	if help {
		fmt.Println("usage: cleanup <task | --all | --prune>")
		return
	}
	if len(pos) > 1 {
		argErr("cleanup takes at most one task (got %d)", len(pos))
	}
	task := ""
	if len(pos) == 1 {
		task = pos[0]
	}
	// Required mutually-exclusive group: exactly one of task / --all / --prune.
	n := 0
	if task != "" {
		n++
	}
	if bools["--all"] {
		n++
	}
	if bools["--prune"] {
		n++
	}
	if n != 1 {
		argErr("cleanup requires exactly one of: <task>, --all, --prune")
	}
	cmdCleanup(task, bools["--all"], bools["--prune"])
}

func runRecap(args []string) {
	pos, _, _, help := parseArgs(args, nil, nil)
	if help {
		fmt.Println("usage: recap <task>")
		return
	}
	if len(pos) != 1 {
		argErr("recap requires <task> (got %d positional args)", len(pos))
	}
	cmdRecap(pos[0])
}

func runCompact(args []string) {
	pos, _, _, help := parseArgs(args, nil, nil)
	if help {
		fmt.Println("usage: compact <task> [description]")
		return
	}
	if len(pos) < 1 || len(pos) > 2 {
		argErr("compact requires <task> and an optional description (got %d positional args)", len(pos))
	}
	desc := ""
	if len(pos) == 2 {
		desc = pos[1]
	}
	cmdCompact(pos[0], desc)
}
