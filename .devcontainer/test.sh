#!/bin/sh

set -eux

devcontainer --version
gemini --version

devcontainer build
devcontainer up --workspace-folder . --remove-existing-container
exec devcontainer exec bash -eux -c '
  ruby --version
  gem install rake

  node --version
  npm install -g es6-map

  devcontainer --version

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

  check_connectivity "https://generativelanguage.googleapis.com/"
  check_connectivity "https://api.anthropic.com/"

  # Detect Gemini authentication
  gemini_authed=false
  if [ -n "${GEMINI_API_KEY:-}" ] && [ "${GEMINI_API_KEY:-}" != "dummy" ]; then
    gemini_authed=true
  elif [ -f "$HOME/.gemini/oauth_creds.json" ]; then
    gemini_authed=true
  fi

  gemini --version
  if [ "$gemini_authed" = true ]; then
    echo "Gemini authentication detected. Running prompt..."
    # In CI with dummy credentials, we expect potential failure, so do not fail the script
    if [ "${GEMINI_API_KEY:-}" = "dummy" ] || grep -q "dummy" "$HOME/.gemini/oauth_creds.json" 2>/dev/null; then
      gemini --prompt "Hello, World!" || echo "Gemini prompt failed as expected with dummy credentials"
    else
      gemini --prompt "Hello, World!"
    fi
  else
    echo "Skipping gemini prompt test: No API key or credential file found"
  fi

  # Detect Claude authentication
  claude_authed=false
  if [ -n "${ANTHROPIC_API_KEY:-}" ] && [ "${ANTHROPIC_API_KEY:-}" != "dummy" ]; then
    claude_authed=true
  elif [ -f "$HOME/.claude/.credentials.json" ] || { claude auth status --output-format json 2>/dev/null | grep -q "\"loggedIn\": true"; }; then
    claude_authed=true
  fi

  claude --version
  if [ "$claude_authed" = true ]; then
    echo "Claude authentication detected. Running print..."
    # In CI with dummy credentials, we expect potential failure, so do not fail the script
    if [ "${ANTHROPIC_API_KEY:-}" = "dummy" ] || grep -q "dummy" "$HOME/.claude/.credentials.json" 2>/dev/null || { claude auth status --output-format json 2>/dev/null | grep -q "dummy"; }; then
      claude --no-session-persistence --print "Hello, World!" || echo "Claude print failed as expected with dummy credentials"
    else
      claude --no-session-persistence --print "Hello, World!"
    fi
  else
    echo "Skipping claude print test: No API key or credential file found"
  fi

  # Check GitHub CLI authentication
  gh auth status

  # Verify SSH agent forwarding (success, no identities found, or agent not reachable)
  ssh-add -l || [ $? -le 2 ]
'
