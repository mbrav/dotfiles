# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
[ -z "$PS1" ] && return

# don't put duplicate lines in the history. See bash(1) for more options
# ... or force ignoredups and ignorespace
HISTCONTROL=ignoredups:ignorespace

# Ignore specific trivial commands
HISTIGNORE="ls *:history:cd:cd -:exit"

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=999999
HISTFILESIZE=999999

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# Ignore specific trivial commands
HISTIGNORE="ls *:history:cd:cd -:exit"

# Add timestamp to each entry
HISTTIMEFORMAT="%F %T: "

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "$debian_chroot" ] && [ -r /etc/debian_chroot ]; then
  debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
*color) color_prompt=yes ;;
alacritty) color_prompt=yes ;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
  if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
    # We have color support; assume it's compliant with Ecma-48
    # (ISO/IEC-6429). (Lack of such support is extremely rare, and such
    # a case would tend to support setf rather than setaf.)
    color_prompt=yes
  else
    color_prompt=
  fi
fi

# Set color prompt
if [ "$color_prompt" = yes ]; then
  # Load starship prompt if starship is installed:
  command -v starship >/dev/null &&
    eval "$(starship init bash)" ||
    PS1='\[\033[90m\]\D{%Y-%m-%d %H:%M:%S} \[\033[32m\]\u@\H \[\033[34m\]\w\[\033[33m\]$(b=$(git branch --show-current 2>/dev/null); [ -n "$b" ] && printf " [%s]" "$b")\[\033[00m\]\$ '
else
  PS1='${debian_chroot:+($debian_chroot)}\u@\H:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm* | rxvt*)
  PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
  ;;
*) ;;
esac

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
  source ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if [ -f /etc/bash_completion ] && ! shopt -oq posix; then
  source /etc/bash_completion
fi

# Add local bin to path if it exists
[[ -d $HOME/.local/bin ]] && PATH="$PATH:$HOME/.local/bin"

# Add go bin to path if it exists
[[ -d /usr/local/go/bin ]] && PATH="$PATH:/usr/local/go/bin"

# Go config
[[ -d "$HOME/go/bin" ]] && PATH="$PATH:$HOME/go/bin"

# Cargo config
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

# Go config
[[ -d "$HOME/go/bin" ]] && PATH="$PATH:$HOME/go/bin"

# Init custom scripts
[[ -f "$HOME/.config/scripts/_aliases" ]] && source "$HOME/.config/scripts/_aliases"
[[ -f "$HOME/.config/scripts/_secrets" ]] && source "$HOME/.config/scripts/_secrets"

# Load exceutable scripts and add to PATH
[[ -d "$HOME/.config/scripts" ]] && PATH="$PATH:$HOME/.config/scripts"

# Kubectl aliases based on shell
# Based on https://github.com/ahmetb/kubectl-aliases
[[ -f "$HOME/.config/scripts/kubectl-aliases/.kubectl_aliases" ]] && source "$HOME/.config/scripts/kubectl-aliases/.kubectl_aliases"

# Autocompletion

# Load zoxide if installed:
command -v zoxide >/dev/null && eval "$(zoxide init bash)"

# Load Atuin history lookup plugin if installed:
command -v atuin >/dev/null && eval "$(atuin init bash)"

# init atuin completions
command -v atuin >/dev/null && eval "$(atuin gen-completions --shell bash)"

# init talosctl
command -v talosctl >/dev/null && eval "$(talosctl completion bash)"

# init cilium
command -v cilium >/dev/null && eval "$(cilium completion bash)"

# init hubble
command -v hubble >/dev/null && eval "$(hubble completion bash)"

# init netbird
command -v netbird >/dev/null && eval "$(netbird completion bash)"

# Source tmux function
# [[ -f "$HOME/.config/scripts/start_tmux" ]] && source "$HOME/.config/scripts/start_tmux"

# Source herdr function
[[ -f "$HOME/.config/scripts/start_herdr" ]] && source "$HOME/.config/scripts/start_herdr"
