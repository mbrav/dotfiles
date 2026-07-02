ARG BASE_IMAGE=alpine:latest
FROM ${BASE_IMAGE}

ARG DOCKER_USER=${DOCKER_USER:-mbrav}
ARG DOCKER_UID=${DOCKER_UID:-1000}
ARG DOCKER_GID=${DOCKER_GID:-1000}
ARG DOTFILES_ROOT="/home/${DOCKER_USER:-mbrav}/.dotfiles/"

# Copy dotfiles config (scripts needed for package setup)
COPY ../dotfiles "$DOTFILES_ROOT/dotfiles/"

# Bootstrap bash — Alpine base ships only busybox, but pkgsetup needs bash
RUN sh -c 'command -v bash >/dev/null \
  || (command -v apk >/dev/null && apk add --no-cache bash) \
  || (command -v apt-get >/dev/null && apt-get update && apt-get install -y bash)'

# Install system packages (distro-aware: apk native, apt base + binstall rest)
RUN $DOTFILES_ROOT/dotfiles/.config/scripts/pkgsetup

# Setup docker user (distro-aware: busybox adduser vs useradd)
RUN sh -c 'if command -v apk >/dev/null; then \
      addgroup "$0" --gid "$1" \
      && adduser "$0" -G "$0" --uid "$2" --disabled-password; \
    else \
      getent group "$1" >/dev/null || groupadd -g "$1" "$0"; \
      useradd -m -u "$2" -g "$1" -s /bin/bash "$0"; \
    fi' "$DOCKER_USER" "$DOCKER_GID" "$DOCKER_UID" \
  && $DOTFILES_ROOT/dotfiles/.config/scripts/sedchad "palette = 'default'" "palette = 'nord-tan'" $DOTFILES_ROOT/dotfiles/.config/starship.toml \
  && mkdir -p /home/$DOCKER_USER/.config \
  && mkdir -p /home/$DOCKER_USER/.local/share/fish \
  && touch /home/$DOCKER_USER/.local/share/fish/fish_history \
  && chown -R "$DOCKER_USER" /home/$DOCKER_USER

WORKDIR /home/$DOCKER_USER
USER $DOCKER_USER

RUN force=1 $DOTFILES_ROOT/dotfiles/.config/scripts/dotinstall

ENTRYPOINT [ "fish" ]
