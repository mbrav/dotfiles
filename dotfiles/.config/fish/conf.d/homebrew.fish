if test -d /opt/homebrew/sbin
    fish_add_path /opt/homebrew/sbin
end

if test -d /opt/homebrew/opt/libpq/bin
    fish_add_path /opt/homebrew/opt/libpq/bin
end

# Replace old rsync
if test -f /opt/homebrew/bin/rsync
    alias rsync="/opt/homebrew/bin/rsync"
end
