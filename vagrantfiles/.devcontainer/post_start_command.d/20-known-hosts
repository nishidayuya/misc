#!/bin/bash

set -eu

# Hosts to scan for SSH host keys.
HOSTS="github.com"

KNOWN_HOSTS="${HOME}/.ssh/known_hosts"

mkdir -p "${HOME}/.ssh"
chmod 700 "${HOME}/.ssh"

touch "${KNOWN_HOSTS}"
chmod 600 "${KNOWN_HOSTS}"

# Number of attempts and the per-attempt connection timeout (seconds).
ATTEMPTS=3
TIMEOUT=10

for host in ${HOSTS}; do
  echo "Scanning SSH host keys for ${host}..."

  # Fetch the current host keys. ssh-keyscan can fail transiently (e.g. the
  # firewall may have whitelisted a different resolved IP than the one picked
  # here), so retry a few times before giving up.
  keys=""
  attempt=1
  while [ "${attempt}" -le "${ATTEMPTS}" ]; do
    if keys=$(ssh-keyscan -T "${TIMEOUT}" "${host}" 2>/dev/null) && [ -n "${keys}" ]; then
      break
    fi
    echo "ssh-keyscan for ${host} failed (attempt ${attempt}/${ATTEMPTS})." >&2
    keys=""
    attempt=$((attempt + 1))
  done

  # Populating known_hosts is best-effort: never let a failure here break the
  # container startup (postStartCommand).
  if [ -z "${keys}" ]; then
    echo "Could not fetch SSH host keys for ${host}. Skipping." >&2
    continue
  fi

  # Remove existing entries for this host to avoid duplicates, then append the
  # freshly fetched keys.
  ssh-keygen -R "${host}" -f "${KNOWN_HOSTS}" >/dev/null 2>&1 || true
  echo "${keys}" >> "${KNOWN_HOSTS}"

  echo "Added SSH host keys for ${host} to ${KNOWN_HOSTS}."
done
