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

# --- Task 2: dispatch (fake) ---
fresh_home
R="$(mkrepo)"
t  "dispatch fake succeeds"        "$PEON" dispatch fake "add a greeting feature" --repo "$R" --slug greet
WT="$PEON_HOME/worktrees/$(basename "$R")-greet"
t  "worktree exists"               test -d "$WT"
t  "branch exists"                 git -C "$R" show-ref --verify --quiet refs/heads/peon/greet
t  "fake work committed"           sh -c "git -C '$WT' log --oneline | grep -q 'fake: do task'"
t  "report committed"              sh -c "git -C '$WT' log --oneline | grep -q 'fake: report'"
t  "PEON_REPORT.md present"        test -f "$WT/PEON_REPORT.md"
t  "fake work file present"        test -f "$WT/FAKE_WORK-greet.txt"
t  "meta file present"             test -f "$PEON_HOME/meta/greet.json"
t  "meta has provider"             sh -c "grep -q '\"provider\": \"fake\"' '$PEON_HOME/meta/greet.json'"
t  "meta has session"              sh -c "grep -q '\"session\": \"fake-greet\"' '$PEON_HOME/meta/greet.json'"
t  "meta records worktree path"    sh -c "grep -q '\"worktree\":' '$PEON_HOME/meta/greet.json'"
t  "worktree is clean"             test -z "$(git -C "$WT" status --porcelain)"
t  "nothing extra in worktree"     sh -c "test ! -e '$WT/.peon.json'"
tf "slug collision refused"        "$PEON" dispatch fake "again" --repo "$R" --slug greet
tf "unknown provider refused"      "$PEON" dispatch claude "task" --repo "$R"
tf "missing task refused"          "$PEON" dispatch fake --repo "$R"
tf "invalid slug refused"          "$PEON" dispatch fake "task" --repo "$R" --slug "Bad Slug!"
echo "dirty" >> "$R/README.md"
tf "dirty repo refused"            "$PEON" dispatch fake "task" --repo "$R" --slug d1
t  "dirty repo + --force ok"       "$PEON" dispatch fake "task" --repo "$R" --slug d1 --force
git -C "$R" checkout -q -- README.md
NR="$TESTTMP/not-a-repo"; mkdir -p "$NR"
tf "outside git repo refused"      "$PEON" dispatch fake "task" --repo "$NR"
RB2="$(mkrepo)"
( cd "$RB2" && echo r > PEON_REPORT.md && git add PEON_REPORT.md && git commit -qm r )
tf "report tracked at base refused" "$PEON" dispatch fake "x" --repo "$RB2" --slug rb
tf "bad base ref refused"          "$PEON" dispatch fake "x" --repo "$R" --slug badbase --base nosuchref
t  "no stale reservation left"     sh -c "test ! -f '$PEON_HOME/meta/badbase.json'"
tf "contract gate trips on dirt"   env PEON_FAKE_DIRTY=1 "$PEON" dispatch fake "dirty task" --repo "$R" --slug dirtyp
t  "dirty peon worktree preserved" test -d "$PEON_HOME/worktrees/$(basename "$R")-dirtyp"

# --- Task 3: list / report / diff ---
fresh_home
R="$(mkrepo)"
"$PEON" dispatch fake "list me" --repo "$R" --slug listme >/dev/null 2>&1
t  "list shows slug"               sh -c "'$PEON' list | grep -q listme"
t  "list shows provider"           sh -c "'$PEON' list | grep -q fake"
t  "list --repo filters in"        sh -c "'$PEON' list --repo '$R' | grep -q listme"
RO="$(mkrepo)"
t  "list --repo filters out"       sh -c "! '$PEON' list --repo '$RO' | grep -q listme"
t  "report prints report"          sh -c "'$PEON' report listme | grep -q 'Peon Report'"
t  "report prints diffstat"        sh -c "'$PEON' report listme | grep -q 'FAKE_WORK-listme.txt'"
t  "diff shows content"            sh -c "'$PEON' diff listme | grep -q 'list me'"
tf "report unknown slug fails"     "$PEON" report nosuchpeon

# --- Task 4: poke ---
fresh_home
R="$(mkrepo)"
"$PEON" dispatch fake "build the widget" --repo "$R" --slug widget >/dev/null 2>&1
WT="$PEON_HOME/worktrees/$(basename "$R")-widget"
BEFORE=$(git -C "$WT" rev-list --count HEAD)
t  "poke succeeds"                 "$PEON" poke widget "make it rounder"
AFTER=$(git -C "$WT" rev-list --count HEAD)
t  "poke added commits"            test "$AFTER" -gt "$BEFORE"
t  "feedback applied"              sh -c "grep -q 'make it rounder' '$WT/FAKE_WORK-widget.txt'"
t  "report updated"                sh -c "grep -q 'revised' '$WT/PEON_REPORT.md'"
tf "no-op poke trips gate"         env PEON_FAKE_NOOP=1 "$PEON" poke widget "do nothing"
tf "poke unknown slug fails"       "$PEON" poke nosuchpeon "feedback"
tf "poke without feedback fails"   "$PEON" poke widget

echo; echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
