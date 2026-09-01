# Point at the socket-activated systemd --user ssh-agent
if not set -q SSH_AUTH_SOCK
    set -gx SSH_AUTH_SOCK "$XDG_RUNTIME_DIR/ssh-agent.socket"
end
