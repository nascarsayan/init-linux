#!/usr/bin/env bash
set -e

if [ $# -eq 0 ]; then
  exec /bin/bash -l
fi

case "$1" in
  -*)
    exec /bin/bash "$@"
    ;;
  bash|/bin/bash)
    shift
    if [ $# -eq 0 ]; then
      exec /bin/bash
    else
      exec /bin/bash "$@"
    fi
    ;;
  *)
    exec "$@"
    ;;
 esac
