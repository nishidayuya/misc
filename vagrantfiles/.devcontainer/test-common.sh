#!/bin/bash

# Checks that run inside the dev container. Both .devcontainer/test-devpod.sh
# and .devcontainer/test-devcontainer.sh run this same script, so that the two
# CLIs are held to the same standard.

set -eux

# The Dockerfile appends a loader for ~/.bashrc.local.d and ~/.zshrc.local.d
# to each rc file. Check that an interactive shell sources the drop-ins in
# alphabetical order, and that it still starts cleanly once the directory is
# gone.
#
# Only the last line of the output is compared, because an interactive shell is
# free to print a banner or a warning of its own before it gets to the echo.
check_rc_d() {
  local shell="$1"
  local dir="$HOME/.${shell}rc.local.d"
  local marker='echo "rc_d=[${dot_devcontainer_rc_d:-}]"'

  mkdir -p "$dir"
  echo 'dot_devcontainer_rc_d="${dot_devcontainer_rc_d:-}b"' > "$dir/20-b"
  echo 'dot_devcontainer_rc_d="${dot_devcontainer_rc_d:-}a"' > "$dir/10-a"
  test "$("$shell" -i -c "$marker" 2>/dev/null | tail -n 1)" = "rc_d=[ab]"

  rm -r "$dir"
  test "$("$shell" -i -c "$marker" 2>/dev/null | tail -n 1)" = "rc_d=[]"
}

check_rc_d bash
check_rc_d zsh

ruby --version
gem install rake

# Node.js is not installed in the image anymore (the Dev Container CLI
# standalone installer bundles its own runtime), so install it here to verify
# that mise can fetch it and that npm works through the firewall.
mise use -g node@24
node --version
npm install -g es6-map

# Rust is not installed in the image either (see the commented-out lines in the
# Dockerfile), so install it here to verify that mise can bootstrap rustup and
# that cargo can reach the crates.io registry through the firewall.
mise use -g rust@latest
rustc --version
cargo --version
rust_test_dir="$(mktemp -d)"
cargo init --vcs none --name dot_devcontainer_rust_test "$rust_test_dir"
cd "$rust_test_dir"
cargo add anyhow
cargo build
cd -

# Git comes from apt in the image (see the commented-out lines in the
# Dockerfile), so install it here to verify that mise can build Git from source
# with the asdf-git plugin through the firewall. This has to run after the Rust
# step above: Git 2.55 and later build libgitcore with cargo unless NO_RUST is
# set.
#
# Install Git's extra build dependencies first, the same way the commented-out
# Dockerfile lines do.
sudo apt-get update
sudo env -- DEBIAN_FRONTEND=noninteractive \
  apt-get -y install --no-install-recommends \
  gettext \
  libcurl4-openssl-dev \
  libexpat1-dev
mise plugin add git https://github.com/nishidayuya/asdf-git
mise use -g git@latest
# The mise shims directory comes first in PATH, so plain "git" must now resolve
# to the mise-managed build instead of /usr/bin/git. hash -r drops any path this
# shell already remembered for git.
hash -r
git --version
test "$(git --exec-path)" = "$(mise where git)/libexec/git-core"
# git-subtree is one of the contrib commands the asdf-git plugin installs by
# default, so its presence proves the contrib build step ran too.
test -x "$(git --exec-path)/git-subtree"

devcontainer --version
devpod version

# Verify connectivity to AI API endpoints (Firewall test)
# Even with dummy keys, these should connect (getting 401/403/404 instead of timeout/refusal)
check_connectivity() {
  local url=$1
  echo "Testing connectivity to $url..."
  if curl -I -s --max-time 10 "$url" > /dev/null; then
    echo "Connectivity to $url: OK"
  else
    local exit_code=$?
    echo "Connectivity to $url: FAILED (curl exit code: $exit_code)"
    return 1
  fi
}

check_connectivity "https://antigravity.google/"
check_connectivity "https://api.anthropic.com/"

# Detect Antigravity connection
# Antigravity CLI authenticates via browser-based Google sign-in and stores
# its credentials under ~/.gemini. "agy models" requires a valid login, so we
# use it to probe whether the CLI is authenticated.
agy_authed=false
if agy models >/dev/null 2>&1
then
  agy_authed=true
fi

agy --version
if test "$agy_authed" = "true"
then
  agy --print "Hello, World!"
else
  agy --print --print-timeout 30s "Hello, World!" || echo "Antigravity prompt failed as expected without credentials"
fi

# Detect Claude connection
claude_authed=false
case "${ANTHROPIC_API_KEY:-}" in
  ""|dummy)
    ;;
  *)
    claude_authed=false
    ;;
esac
if test -f "$HOME/.claude/.credentials.json" && ! grep -q "dummy" "$HOME/.claude/.credentials.json"
then
  claude_authed=true
fi

claude --version
if test "$claude_authed" = true
then
  claude --no-session-persistence --print "Hello, World!"
else
  claude --no-session-persistence --print "Hello, World!" || echo "Claude prompt failed as expected with dummy credentials"
fi

# Check GitHub CLI connection
gh version
GH_TOKEN=dummy gh api https://github.com/nishidayuya/dot-devcontainer

# Check GitLab CLI connection
glab version
# The token is cleared here rather than set to a dummy value, unlike the gh
# check above: GitLab answers a request carrying an invalid token with 401 even
# for a public project, while an anonymous one succeeds. What this asserts is
# that gitlab.com is reachable through the firewall, not that credentials work.
GITLAB_TOKEN= glab api projects/gitlab-org%2Fgitlab
