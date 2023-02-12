# MY ALIASES BEGIN
export EDITOR='nvim'
export VISUAL='nvim'
alias vi='vim'
alias vim='nvim'

export ANSIBLE_CONFIG='$HOME/.ansible/ansible.cfg'

## MY ALIASES
alias d-u='du -h --max-depth 1'
# Force tmux color 
alias tmux='tmux -2'
alias tmux-new='tmux -2 new -s '
alias tmux-reatch='tmux -2 attach -t '
# alias pass-gen='< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c' # $1 - number of bytes

# Folder aliases
alias dev="cd ~/dev"

# Python aliases
alias pip-install='pip install --upgrade --no-cache pip wheel setuptools '
alias python-venv='python3 -m venv venv && source ./venv/bin/activate'
alias python-https-server='python3 ~/dev/HTTPSPythonServer/server-start.py'
alias dj-migrate='python manage.py makemigrations && python manage.py migrate'

# Rust aliases
alias clpy='cargo clippy -- -W clippy::pedantic -W clippy::nursery -W clippy::unwrap_used'
alias clpy-fix='cargo clippy --fix --allow-dirty -- -W clippy::pedantic -W clippy::nursery -W clippy::unwrap_used'

# Docker aliases
alias doup='sudo systemctl start docker.service'
alias dodown='sudo systemctl stop docker.service'
alias do-remove-all='docker ps -a -q | xargs docker rm'
alias do-stop-all='docker ps -a -q | xargs docker stop'
alias do-purge-all-WARNING='docker system prune --volumes --all --force'
alias do-clean='dock-stop-all && dock-remove-all && docker image prune'

# Mount rclone 
alias rclone-crypt='rclone mount crypt:/ ~/Desktop/crypt/ --read-only --max-read-ahead=1G --acd-templink-threshold=0 --contimeout=15s --checkers=16 --bwlimit=0 --retries=3 --timeout=30s --low-level-retries=1 --transfers=8 --dir-cache-time=30m'
alias mi-display-fix='xrandr --output HDMI-0 --mode 3440x1440 --rate 60'

# Extract GPS data from image with imagemagick
# $1 file name 
alias image-gps='identify -format "%[EXIF:GPSLatitude],%[EXIF:GPSLongitude]\n" '

# Git aliases
alias g='git'
alias gl='git log --all --oneline --graph --decorate --branches'
alias gu='git reset --soft HEAD~1 && echo "Undo last commit using SOFT reset"'
alias gca='git add . && git commit'
alias ga='git commit --amend'
alias gaa='git add -A && git commit --amend'
alias gf='git push --force'
alias gfa='git commit --amend && git push --force'

# Python utils
alias pip-req-txt-to-toml="echo 'Adding requirements.txt to pyprpoject.toml' && cat requirements.txt | grep -E '^[^# ]' | cut -d= -f1 | xargs -n 1 poetry add"

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
alias l.='exa -a | egrep"^\."'

alias ip='ip -color'

# Replace some more things with better alternatives
[ -x "$(command -v pygmentize)" ] && alias cat='pygmentize -g ' 
[ -x "$(command -v bat)" ] && alias cat='bat --style header --style snip --style changes --style header' 
[ ! -x /usr/bin/yay ] && [ -x /usr/bin/paru ] && alias yay='paru'

# Common use
alias grubup='sudo update-grub'
alias tarnow='tar -acf '
alias untar='tar -xvf '
alias wget='wget -c '
alias rmpkg='sudo pacman -Rdd'
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
alias big='expac -H M "%m\t%n" | sort -h | nl'     # Sort installed packages according to size in MB
alias gitpkg='pacman -Q | grep -i "\-git" | wc -l' # List amount of -git packages

# Cleanup orphaned packages
alias cleanup='sudo pacman -Rns (pacman -Qtdq)'

# Get the error messages from journalctl
alias jctl='journalctl -p 3 -xb'

# Recent installed packages
alias rip='expac --timefmt="%Y-%m-%d %T" "%l\t%n %v" | sort | tail -200 | nl'

# Use QEMU system URI
export LIBVIRT_DEFAULT_URI="qemu:///system"