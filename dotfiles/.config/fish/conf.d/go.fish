# Add go to path if present if present in home
if test -d ~/go/bin
    fish_add_path ~/go/bin
end

# Add go to path if present if present in /usr/local
if test -d /usr/local/go/bin
    fish_add_path /usr/local/go/bin
end
