#!/bin/sh

# Starts this project's dev container with DevPod and runs the shared checks in
# it. Reaching test-common.sh at all already proves that DevPod applied capAdd,
# the /dev_container_home mount and postStartCommand, because
# .devcontainer/post_start_command.d/00-firewall would have failed otherwise.

set -eux

devpod version
devpod provider list

devpod_workspace=dot-devcontainer-test

# --ide none is passed explicitly even though the image sets it as the context
# default: CI drives DevPod from the runner, whose context has no such default,
# and a workspace keeps whatever IDE it was created with anyway.
devpod up . --provider docker --ide none --id "$devpod_workspace" --recreate

devpod ssh "$devpod_workspace" --command ".devcontainer/test-common.sh"

# Only reached when the checks passed, so a failing run leaves the workspace
# behind to inspect. Delete it by hand with:
#   devpod delete dot-devcontainer-test --force
devpod delete "$devpod_workspace" --force
