# nvm for fish without a plugin manager: put the default nvm Node on PATH.
# Does not provide the `nvm` command; use bash for `nvm install`/`nvm use`.
set -gx NVM_DIR "$HOME/.nvm"

if test -f "$NVM_DIR/alias/default"
    set -l default_version (string trim < "$NVM_DIR/alias/default")
    # Newest installed version whose name starts with the default alias (e.g. "20" → v20.*)
    set -l node_bin (string match -r ".*" "$NVM_DIR/versions/node/v$default_version"* 2>/dev/null | sort -V | tail -n 1)
    if test -n "$node_bin"; and test -d "$node_bin/bin"
        fish_add_path -g "$node_bin/bin"
    end
end
