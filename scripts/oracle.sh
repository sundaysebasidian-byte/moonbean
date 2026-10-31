#!/usr/bin/env bash
# Conformance harness for moonbean.
#
# Installs a pinned Beancount release into a throwaway virtual environment and
# compares bean-check / bean-query output with moonbean's CLI. Beancount is
# GPL-2.0 software used here strictly as an external black-box oracle: it is
# never linked into, embedded in, or distributed with moonbean.
#
# Usage:
#   scripts/oracle.sh                 # install deps if needed and compare
#   scripts/oracle.sh --markdown      # print a markdown table
#   scripts/oracle.sh --reinstall     # recreate the virtual environment
#
# Environment:
#   MOONBEAN_ORACLE_VENV         virtualenv location (default: .oracle-venv)
#   MOONBEAN_BEANCOUNT_VERSION   pinned beancount version (default: 3.2.3)
#   MOONBEAN_BEANQUERY_VERSION   pinned beanquery version (default: 0.2.0)
#   MOONBEAN_PYTHON              interpreter used to create the venv
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV="${MOONBEAN_ORACLE_VENV:-$ROOT/.oracle-venv}"
BEANCOUNT_VERSION="${MOONBEAN_BEANCOUNT_VERSION:-3.2.3}"
BEANQUERY_VERSION="${MOONBEAN_BEANQUERY_VERSION:-0.2.0}"
PYTHON="${MOONBEAN_PYTHON:-python3}"
REINSTALL=0
EXTRA=()
for argument in "$@"; do
  case "$argument" in
    --reinstall) REINSTALL=1 ;;
    *) EXTRA+=("$argument") ;;
  esac
done

if [ "$REINSTALL" = "1" ]; then
  rm -rf "$VENV"
fi

if [ ! -x "$VENV/bin/bean-check" ] || [ ! -x "$VENV/bin/bean-query" ]; then
  echo "==> creating oracle virtual environment at $VENV" >&2
  "$PYTHON" -m venv "$VENV"
  "$VENV/bin/python" -m pip install --quiet --upgrade pip
  "$VENV/bin/python" -m pip install --quiet \
    "beancount==$BEANCOUNT_VERSION" "beanquery==$BEANQUERY_VERSION"
fi

BEANCOUNT_ACTUAL="$("$VENV/bin/python" -c 'import beancount; print(beancount.__version__)')"
BEANQUERY_ACTUAL="$("$VENV/bin/python" -c 'import beanquery; print(beanquery.__version__)')"

if ! command -v moon >/dev/null 2>&1; then
  if [ -d "$HOME/.moon/bin" ]; then
    export PATH="$HOME/.moon/bin:$PATH"
  else
    echo "moon toolchain not found; add it to PATH first" >&2
    exit 1
  fi
fi

echo "==> building moonbean (native)" >&2
(cd "$ROOT" && moon build --target native >/dev/null)

EXE="$ROOT/_build/native/debug/build/cmd/main/main.exe"
if [ ! -x "$EXE" ]; then
  echo "moonbean executable not found at $EXE" >&2
  exit 1
fi

echo "==> oracle beancount $BEANCOUNT_ACTUAL, beanquery $BEANQUERY_ACTUAL" >&2
"$PYTHON" "$ROOT/scripts/conformance.py" \
  --ours "$EXE" \
  --oracle "$VENV/bin" \
  --ledgers "$ROOT/tests/ledgers" \
  --oracle-version "beancount $BEANCOUNT_ACTUAL / beanquery $BEANQUERY_ACTUAL" \
  ${EXTRA[@]+"${EXTRA[@]}"}
