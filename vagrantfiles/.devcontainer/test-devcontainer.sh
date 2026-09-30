#!/bin/sh

# Starts this project's dev container with the Dev Container CLI and runs the
# shared checks in it.

set -eux

devcontainer --version

devcontainer build
devcontainer up --workspace-folder . --remove-existing-container
exec devcontainer exec .devcontainer/test-common.sh
