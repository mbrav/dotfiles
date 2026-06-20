function gclone -d "Clone a git repo into ~/dev/<host>/<user>/<repo> and cd into it"
    if test (count $argv) -ne 1
        echo "Usage: gclone <git-url>" >&2
        echo "  HTTPS: https://github.com/user/repo[.git]" >&2
        echo "  SSH:   git@github.com:user/repo[.git]" >&2
        return 1
    end

    if not type -q git
        echo "gclone: git is not installed" >&2
        return 1
    end

    set -l url $argv[1]
    set -l host ""
    set -l user ""
    set -l repo ""

    # Parse HTTPS: https://host/user/repo[.git]
    if string match -qr '^https?://' -- $url
        set -l stripped (string replace -r '^https?://' '' -- $url)
        set host (string split "/" -- $stripped)[1]
        set user (string split "/" -- $stripped)[2]
        set repo (string split "/" -- $stripped)[3]
    # Parse SSH: git@host:user/repo[.git]
    else if string match -qr '^git@' -- $url
        set -l stripped (string replace -r '^git@' '' -- $url)
        set host (string split ":" -- $stripped)[1]
        set -l path (string split ":" -- $stripped)[2]
        set user (string split "/" -- $path)[1]
        set repo (string split "/" -- $path)[2]
    else
        echo "gclone: unrecognised URL format: $url" >&2
        return 1
    end

    # Strip trailing .git from repo name
    set repo (string replace -r '\.git$' '' -- $repo)

    if test -z "$host" -o -z "$user" -o -z "$repo"
        echo "gclone: could not parse host/user/repo from URL: $url" >&2
        return 1
    end

    set -l target "$HOME/dev/$host/$user/$repo"

    if test -d "$target"
        echo "gclone: $target already exists, skipping clone"
        cd "$target"
        return 0
    end

    mkdir -p (dirname "$target")
    git clone "$url" "$target"; and cd "$target"
end
