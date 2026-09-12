#!/bin/sh

# A portable stand-in for "run-parts --exit-on-error --verbose".
#
# initializeCommand runs on the host, and run-parts ships with Debian's
# debianutils, so it is missing on a macOS host. This reimplements the subset of
# run-parts that this repository relies on, using only POSIX sh.

set -eu

if test "$#" -ne 1
then
  echo "usage: $0 DIRECTORY" >&2
  exit 1
fi

directory="$1"

if ! test -d "${directory}"
then
  echo "$0: ${directory}: not a directory" >&2
  exit 1
fi

# run-parts ignores any name holding a character outside [A-Za-z0-9_-], which is
# how it skips editor backups and package manager leftovers such as
# foo.dpkg-dist. LC_ALL=C keeps both that character range and the execution
# order from depending on the host locale.
LC_ALL=C
export LC_ALL

for path in "${directory}"/*
do
  # The glob stays literal when the directory is empty.
  test -e "${path}" || continue

  name="${path##*/}"
  case "${name}" in
    *[!A-Za-z0-9_-]*)
      continue
      ;;
  esac

  # Skips directories, and anything that is not marked executable.
  test -f "${path}" || continue
  test -x "${path}" || continue

  # --verbose writes to stderr, so that a script's own stdout stays clean.
  echo "run-parts: executing ${path}" >&2

  # "|| code=$?" keeps set -e from firing here, so that the failure can be
  # reported the way run-parts reports it.
  code=0
  "${path}" || code="$?"

  # --exit-on-error, propagating the script's own exit status.
  if test "${code}" -ne 0
  then
    echo "run-parts: ${path} exited with return code ${code}" >&2
    exit "${code}"
  fi
done
