# if test -d /opt/homebrew/sbin
#     fish_add_path /opt/homebrew/sbin
# end
#
# if test -d /opt/homebrew/opt/libpq/bin
#     fish_add_path /opt/homebrew/opt/libpq/bin
# end

# Prioritize Homebrew bin over system (ensures `which rsync` resolves correctly)
if test -d /opt/homebrew/bin
    fish_add_path --move /opt/homebrew/bin
end

# Fix aws
if test -f ~/.venv/bin/aws
    alias aws="~/.venv/bin/aws"
end
