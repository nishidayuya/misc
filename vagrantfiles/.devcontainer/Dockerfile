FROM mcr.microsoft.com/devcontainers/base:debian-13

# Several RUN instructions below pipe a downloaded installer script or GPG key
# into another command. The default "/bin/sh -c" only reports the exit status of
# the last command of a pipeline, so a failed download would go unnoticed.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install git, gh, glab, Chromium, and other dependencies
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
    git \
    gh \
    glab \
    openssh-client \
    iptables \
    curl \
    ca-certificates \
    gpg \
    gnupg \
    build-essential \
    libssl-dev \
    libyaml-dev \
    libreadline6-dev \
    zlib1g-dev \
    libncurses5-dev \
    libffi-dev \
    libgdbm6 \
    libgdbm-dev \
    dbus \
    kmod \
    chromium \
    chromium-driver \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Install mise
# The repository serves both amd64 and arm64, so the architecture is taken from
# dpkg instead of being named: hard-coding amd64 leaves "apt-get install mise"
# without a candidate on an arm64 host, such as an Apple Silicon Mac.
RUN arch="$(dpkg --print-architecture)" \
    && install -dm 755 /etc/apt/keyrings \
    && curl -fsSL https://mise.jdx.dev/gpg-key.pub | gpg --dearmor -o /etc/apt/keyrings/mise-archive-keyring.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.gpg arch=${arch}] https://mise.jdx.dev/deb stable main" | tee /etc/apt/sources.list.d/mise.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends mise \
    && rm -rf /var/lib/apt/lists/*

USER vscode
ENV MISE_DATA_DIR=/home/vscode/.local/share/mise
ENV MISE_CONFIG_DIR=/home/vscode/.config/mise
ENV PATH="/home/vscode/.local/bin:/home/vscode/.devcontainers/bin:/home/vscode/.local/share/mise/shims:${PATH}"

# DevPod reports anonymous usage statistics unless told not to. The firewall
# blocks that endpoint anyway, so turn it off rather than have every invocation
# wait on a rejected connection.
ENV DEVPOD_DISABLE_TELEMETRY=true

# Install tools
# Dev Container CLI is installed with the standalone script, which bundles its
# own Node.js runtime (https://github.com/devcontainers/cli#install-script)
RUN curl -fsSL https://raw.githubusercontent.com/devcontainers/cli/main/scripts/install.sh | sh
# DevPod CLI runs the same devcontainer.json on a pluggable backend. It ships as
# a single static binary (https://devpod.sh/docs/getting-started/install), and
# the built-in "docker" provider is registered here so that it targets the local
# Docker daemon provided by the docker-in-docker feature. That provider is
# embedded in the binary, so adding it needs no network access.
#
# Git credential and ssh signature forwarding are turned off because both work
# by rewriting ~/.gitconfig inside the workspace. Here that file is a symlink
# into /dev_container_home (see post_start_command.d/10-dev-container-home), so
# DevPod would edit the shared configuration on the host and leave behind a
# credential helper and a gpg.ssh.program pointing at paths that only exist
# inside the workspace, breaking git outside of it.
#
# The default IDE is set to "none" because DevPod otherwise falls back to
# opening VS Code, and there is none to open in here. "devpod up" then just
# starts the workspace, and "devpod ssh" is how you enter it.
#
# The binary is downloaded straight to its final location: DevPod itself uses
# /tmp/devpod as a working directory, so staging the download there would make
# every later "mkdir /tmp/devpod" fail with "not a directory".
RUN arch="$(dpkg --print-architecture)" \
    && install -d -m 0755 /home/vscode/.local/bin \
    && curl -fsSL -o /home/vscode/.local/bin/devpod \
      "https://github.com/loft-sh/devpod/releases/latest/download/devpod-linux-${arch}" \
    && chmod 0755 /home/vscode/.local/bin/devpod \
    && devpod provider add docker \
    && devpod context set-options \
      -o SSH_INJECT_GIT_CREDENTIALS=false \
      -o GIT_SSH_SIGNATURE_FORWARDING=false \
    && devpod ide use none
# Install Claude Code via the native installer (https://code.claude.com/docs/ja/quickstart)
RUN curl -fsSL https://claude.ai/install.sh | bash
# Antigravity CLI is distributed as a native binary (installed to ~/.local/bin/agy), not via npm
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash
RUN mise use -g ruby@latest
# Node.js is not required anymore: the Dev Container CLI standalone installer
# bundles its own runtime. Uncomment if your project needs Node.js and npm.
# RUN mise use -g node@24
# Rust is not installed by default. Uncomment if your project needs rustc and
# cargo. mise installs and drives rustup under the hood.
# RUN mise use -g rust@latest
# Git is already provided by apt above. Uncomment to manage a newer Git with
# mise instead, using the asdf-git plugin
# (https://github.com/nishidayuya/asdf-git). It builds Git from source, so the
# first RUN below installs Git's extra build dependencies. Git 2.55 and later
# also build Rust code (libgitcore) unless NO_RUST is set, so the rust line
# above has to be uncommented too.
# RUN sudo apt-get update \
#     && sudo env -- DEBIAN_FRONTEND=noninteractive \
#     apt-get -y install --no-install-recommends \
#     gettext \
#     libcurl4-openssl-dev \
#     libexpat1-dev
# RUN mise plugin add git https://github.com/nishidayuya/asdf-git \
#     && mise use -g git@latest

# Setup shell for mise
# The single quotes are deliberate: mise has to be activated when the shell
# starts, not when the image is built.
# hadolint ignore=SC2016
RUN echo 'eval "$(mise activate bash)"' >> ~/.bashrc \
    && echo 'eval "$(mise activate zsh)"' >> ~/.zshrc

# Load ~/.bashrc.local.d and ~/.zshrc.local.d
# A drop-in directory keeps per-user or per-project shell settings out of the
# rc file itself, so that they can be added by symlinking them in from
# /dev_container_home (see post_start_command.d/10-dev-container-home) without
# editing anything the image ships.
#
# The blocks are appended last, so that they run after the mise activation above
# and can therefore override it. The glob expands in collation order, which is
# how the files are sourced alphabetically, and it also expands to nothing
# useful when the directory is empty: bash leaves the pattern as it is and the
# -f test rejects it, while zsh's (N) qualifier drops it. A missing directory is
# not an error either.
#
# The whole thing is one heredoc so that the two blocks read the way they end up
# in the rc files. It needs BuildKit, which every builder this image is built
# with uses: the classic "DOCKER_BUILDKIT=0" builder drops heredoc bodies.
RUN <<'DOCKERFILE_RUN'
cat >> ~/.bashrc <<'BASHRC'

# Source every file in ~/.bashrc.local.d, in alphabetical order.
if [ -d ~/.bashrc.local.d ]; then
  for __rc in ~/.bashrc.local.d/*; do
    [ -f "$__rc" ] && . "$__rc"
  done
  unset __rc
fi
BASHRC

cat >> ~/.zshrc <<'ZSHRC'

# Source every file in ~/.zshrc.local.d, in alphabetical order.
if [ -d ~/.zshrc.local.d ]; then
  for __rc in ~/.zshrc.local.d/*(N); do
    [ -f "$__rc" ] && . "$__rc"
  done
  unset __rc
fi
ZSHRC
DOCKERFILE_RUN
