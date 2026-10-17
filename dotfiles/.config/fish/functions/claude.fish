function claude --description 'Claude Code through the Headroom proxy, with per-project attribution'
    # HEADROOM_HOST / HEADROOM_PORT / HEADROOM_PROXY_TOKEN come from ~/.profile.
    # Keep in sync with the bash version in ~/.config/scripts/_claude
    set -l base
    set -l port 8787
    set -q HEADROOM_PORT; and set port $HEADROOM_PORT

    if type -q headroom
        # Local proxy; the SessionStart hook starts it if it is not up yet
        set -l host localhost
        set -q HEADROOM_HOST; and set host $HEADROOM_HOST
        set base "http://$host:$port"
    else if set -q HEADROOM_HOST
        # Remote proxy (no CLI here, e.g. a server using rag's container).
        # Nothing would start it, so check it is up rather than fail every request
        set base "http://$HEADROOM_HOST:$port"
        if not curl -sf -m 1 "$base/health" >/dev/null 2>&1
            echo "claude: Headroom proxy at $base is down, running direct" >&2
            command claude $argv
            return
        end
    else
        command claude $argv
        return
    end

    # Git repo name if inside one (stable from subfolders), else the current folder
    set -l root (git rev-parse --show-toplevel 2>/dev/null; or pwd)
    set -l project (basename $root)

    set -l headers "X-Headroom-Project: $project"
    # Remote proxies are token-gated; Claude's own Authorization still reaches Anthropic
    if set -q HEADROOM_PROXY_TOKEN
        set headers "$headers"\n"X-Headroom-Proxy-Token: $HEADROOM_PROXY_TOKEN"
    end
    if set -q ANTHROPIC_CUSTOM_HEADERS
        set headers "$ANTHROPIC_CUSTOM_HEADERS"\n"$headers"
    end

    ANTHROPIC_BASE_URL=$base ANTHROPIC_CUSTOM_HEADERS=$headers command claude $argv
end
