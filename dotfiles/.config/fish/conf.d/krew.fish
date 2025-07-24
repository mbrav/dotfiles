# Add kubectl krew plugins to PATH if installed
set -l krew_path (set -q KREW_ROOT; and echo $KREW_ROOT/.krew/bin; or echo $HOME/.krew/bin)
if test -d $krew_path
    fish_add_path $krew_path
end
