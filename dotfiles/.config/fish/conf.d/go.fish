# Add go to path if present
if test -d ~/go/bin
    if not contains -- ~/go/bin $PATH
        set -p PATH ~/go/bin
    end
end
