FROM alpine:latest

ARG DOCKER_USER=${DOCKER_USER:-mbrav}
ARG DOCKER_UID=${DOCKER_UID:-1000}
ARG DOCKER_GID=${DOCKER_GID:-1000}
ARG DOTFILES_ROOT="/home/${DOCKER_USER:-mbrav}/.config/dotfiles/"

# Install system packages
RUN apk add --upgrade --latest \
  bash \
  fish \
  curl \
  musl \
  build-base \
  unzip \
  git \
  # CLI tools
  grep \
  ripgrep \
  fzf \
  fd \
  bat \
  yq \
  jq \
  # Dev
  vim \
  neovim \
  lazygit \
  npm \
  python3 \
  && apk cache clean

# Copy dotfiles config
COPY ../dotfiles "$DOTFILES_ROOT/dotfiles/"
COPY ../install.sh "$DOTFILES_ROOT"

# Setup docker user
RUN addgroup "$DOCKER_USER" --gid "$DOCKER_GID" \
  && adduser "$DOCKER_USER" -G "$DOCKER_USER" --uid "$DOCKER_UID" --disabled-password \
  && $DOTFILES_ROOT/dotfiles/.config/scripts/binstall eza \
  && $DOTFILES_ROOT/dotfiles/.config/scripts/binstall mcfly \
  && $DOTFILES_ROOT/dotfiles/.config/scripts/binstall upx \
  && $DOTFILES_ROOT/dotfiles/.config/scripts/binstall starship \
  && $DOTFILES_ROOT/dotfiles/.config/scripts/sedchad "palette = 'default'" "palette = 'nord-tan'" $DOTFILES_ROOT/dotfiles/.config/starship.toml \
  && mkdir -p /home/$DOCKER_USER/.config \
  && chown -R "$DOCKER_USER" /home/$DOCKER_USER

WORKDIR /home/$DOCKER_USER
USER $DOCKER_USER

RUN force=1 /home/$DOCKER_USER/.config/dotfiles/install.sh

ENTRYPOINT [ "fish" ]
