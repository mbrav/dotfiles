# MY ALIASES BEGIN
export EDITOR='vim'
export VISUAL='vim'
alias vi="vim"

export ANSIBLE_CONFIG="$HOME/.ansible/ansible.cfg"

## MY ALIASES
alias disk-usage="du -h --max-depth 1"
alias tmux-new="tmux new -s "
alias tmux-reatch="tmux attach -t "
alias pass-gen="< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c" # $1 - number of bytes

# Python aliases
alias pip-upgrade="poetry update"
alias python-venv="python3 -m venv venv && source ./venv/bin/activate"
alias python-https-server="python3 ~/dev/HTTPSPythonServer/server-start.py"
alias dj-migrate="python manage.py makemigrations && python manage.py migrate"

# Docker aliases
alias dockup="sudo systemctl start docker.service"
alias dockdown="sudo systemctl stop docker.service"
alias dock-remove-all="docker ps -a -q | xargs docker rm"
alias dock-stop-all="docker ps -a -q | xargs docker stop"
alias dock-purge-all-WARNING="docker system prune --volumes --all --force"
alias dock-clean="dock-stop-all && dock-remove-all && docker image prune"

# Mount rclone 
alias rclone-crypt="rclone mount crypt:/ ~/Desktop/crypt/ --read-only --max-read-ahead=1G --acd-templink-threshold=0 --contimeout=15s --checkers=16 --bwlimit=0 --retries=3 --timeout=30s --low-level-retries=1 --transfers=8 --dir-cache-time=30m"
alias mi-display-fix="xrandr --output HDMI-0 --mode 3440x1440 --rate 60"

# Extract GPS data from image with imagemagick
# $1 file name 
alias image-gps="identify -format '%[EXIF:GPSLatitude],%[EXIF:GPSLongitude]\n' "

# Git aliases
alias git-log="git log --all --oneline --graph --decorate --branches"
alias git-undo="git reset --soft HEAD~1 && echo 'Undo last commit using SOFT reset'"
alias git-commit-all="git add . && git commit"
alias git-amend="git commit --amend"
alias git-amend-all="git add -A && git commit --amend"
alias git-force="git push --force"
alias git-force-ammend="git commit --amend && git push --force"

## Useful aliases
# Replace ls with exa
[ -x "$(command -v exa)" ] && \
# preferred listing
alias ls='exa -al --color=always --group-directories-first --icons' && \
# all files and dirs
alias la='exa -a --color=always --group-directories-first --icons' && \
# long format
alias ll='exa -l --color=always --group-directories-first --icons' && \
# tree listing
alias lt='exa -aT --color=always --group-directories-first --icons' && \
# show only dotfiles
alias l.="exa -a | egrep '^\.'" || \
echo "exa not installed!"

alias ip="ip -color"

# Replace some more things with better alternatives
[ -x "$(command -v pygmentize)" ] && alias cat="pygmentize -g " 
[ -x "$(command -v bat)" ] && alias cat='bat --style header --style snip --style changes --style header' 
[ ! -x /usr/bin/yay ] && [ -x /usr/bin/paru ] && alias yay='paru'

# Common use
alias grubup="sudo update-grub"
alias tarnow='tar -acf '
alias untar='tar -xvf '
alias wget='wget -c '
alias rmpkg="sudo pacman -Rdd"
alias psmem='ps auxf | sort -nr -k 4'
alias psmem10='ps auxf | sort -nr -k 4 | head -10'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ......='cd ../../../../..'
alias dir='dir --color=auto'
alias vdir='vdir --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias hw='hwinfo --short'                          # Hardware Info
alias big="expac -H M '%m\t%n' | sort -h | nl"     # Sort installed packages according to size in MB
alias gitpkg='pacman -Q | grep -i "\-git" | wc -l' # List amount of -git packages

# Cleanup orphaned packages
alias cleanup='sudo pacman -Rns (pacman -Qtdq)'

# Get the error messages from journalctl
alias jctl="journalctl -p 3 -xb"

# Recent installed packages
alias rip="expac --timefmt='%Y-%m-%d %T' '%l\t%n %v' | sort | tail -200 | nl"
