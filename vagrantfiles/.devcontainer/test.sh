#!/bin/sh

# Runs both CLIs, one after the other. Call the per-CLI scripts directly to test
# just one of them; CI runs them as two parallel jobs.

set -eux

.devcontainer/test-devcontainer.sh
exec .devcontainer/test-devpod.sh
