#!/usr/bin/env bash
# tests/peon.test.sh — deterministic tests for bin/peon (fake provider + dry-run; no real CLI calls)
set -u

PEON="$(cd "$(dirname "$0")/.." && pwd)/bin/peon"
PASS=0; FAIL=0
TESTTMP="$(mktemp -d "${TMPDIR:-/tmp}/peon-tests.XXXXXX")"
trap 'rm -rf "$TESTTMP"' EXIT

t()  { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "ok - $d"; else FAIL=$((FAIL+1)); echo "FAIL - $d"; fi; }
tf() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then FAIL=$((FAIL+1)); echo "FAIL (expected failure) - $d"; else PASS=$((PASS+1)); echo "ok - $d"; fi; }

fresh_home() { export PEON_HOME="$TESTTMP/peon-home-$RANDOM$RANDOM"; }

mkrepo() {
  local r="$TESTTMP/repo-$RANDOM$RANDOM"
  mkdir -p "$r"
  git -C "$r" init -q
  git -C "$r" config user.email peon@test
  git -C "$r" config user.name peon
  echo "hello" > "$r/README.md"
  git -C "$r" add README.md
  git -C "$r" commit -qm "initial"
  echo "$r"
}

# --- Task 1: skeleton ---
t  "usage exits 0"                 "$PEON" help
t  "usage mentions dispatch"       sh -c "'$PEON' help | grep -q dispatch"
tf "unknown command fails"         "$PEON" frobnicate
tf "no args fails"                 "$PEON"

echo; echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
