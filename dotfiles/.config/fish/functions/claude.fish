function claude --description 'Claude Code through the Headroom proxy, with per-project attribution'
    # Without headroom on PATH there is no proxy: run claude straight to Anthropic
    if not type -q headroom
        command claude $argv
        return
    end

    # HEADROOM_HOST / HEADROOM_PORT come from ~/.profile
    set -l host localhost
    set -q HEADROOM_HOST; and set host $HEADROOM_HOST
    set -l port 8787
    set -q HEADROOM_PORT; and set port $HEADROOM_PORT

    # Git repo name if inside one (stable from subfolders), else the current folder
    set -l root (git rev-parse --show-toplevel 2>/dev/null; or pwd)
    set -l project (basename $root)

    set -l headers "X-Headroom-Project: $project"
    if set -q ANTHROPIC_CUSTOM_HEADERS
        set headers "$ANTHROPIC_CUSTOM_HEADERS"\n"$headers"
    end

    ANTHROPIC_BASE_URL="http://$host:$port" ANTHROPIC_CUSTOM_HEADERS=$headers command claude $argv
end
