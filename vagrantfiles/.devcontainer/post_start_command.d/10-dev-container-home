#!/bin/bash

set -eu

DOT_DEVCONTAINER_HOME="${DOT_DEVCONTAINER_HOME:-/dev_container_home}"

if [ ! -d "${DOT_DEVCONTAINER_HOME}" ]; then
  echo "${DOT_DEVCONTAINER_HOME} is not mounted. Skipping."
  exit 0
fi

if [ "${DOT_DEVCONTAINER_HOME}" = "${HOME}" ]; then
  echo "${DOT_DEVCONTAINER_HOME} is the home directory itself. Skipping."
  exit 0
fi

# Include dotfiles, and expand to nothing when the directory is empty.
shopt -s dotglob nullglob

for path in "${DOT_DEVCONTAINER_HOME}"/*; do
  name="$(basename "${path}")"
  link="${HOME}/${name}"

  # Existing entries in the home directory are replaced by the symlink.
  rm -rf "${link}"
  ln -s "${path}" "${link}"

  echo "Linked ${link} -> ${path}."
done
