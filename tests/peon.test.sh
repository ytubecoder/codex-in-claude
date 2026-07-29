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
t  "worktree is clean"             sh -c "test -d '$WT' && test -z \"\$(git -C '$WT' status --porcelain)\""
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
# I3: real test for reservation release (badbase above never reaches reserve_slug — this does)
mkdir -p "$PEON_HOME/worktrees"
chmod 500 "$PEON_HOME/worktrees" 2>/dev/null || true
tf "worktree add failure releases slug" "$PEON" dispatch fake "x" --repo "$R" --slug relslug
chmod 700 "$PEON_HOME/worktrees"
t  "reservation released"          sh -c "test ! -f '$PEON_HOME/meta/relslug.json'"
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
t  "list --repo filters out"       sh -c "'$PEON' list --repo '$RO' >'$TESTTMP/peonlist.$$' 2>&1 && ! grep -q listme '$TESTTMP/peonlist.$$'"
t  "report prints report"          sh -c "'$PEON' report listme | grep -q 'Peon Report'"
t  "report prints diffstat"        sh -c "'$PEON' report listme | grep -q 'FAKE_WORK-listme.txt'"
t  "diff shows content"            sh -c "'$PEON' diff listme | grep -q 'list me'"
tf "report unknown slug fails"     "$PEON" report nosuchpeon

# I2: reservation placeholder is valid JSON; meta_get / list / report must not traceback on a
# reserving/corrupt meta row
mkdir -p "$PEON_HOME/meta"
printf '{"slug":"ghost","state":"reserving"}\n' > "$PEON_HOME/meta/ghost.json"
t  "list survives reserving meta"              "$PEON" list
t  "report on reserving meta has no traceback" sh -c "! '$PEON' report ghost 2>&1 | grep -q Traceback"
tf "report on reserving meta fails cleanly"    "$PEON" report ghost
rm -f "$PEON_HOME/meta/ghost.json"

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

# --- Task 5: merge / scrap / failure paths / parallel ---
fresh_home
R="$(mkrepo)"
"$PEON" dispatch fake "mergeable work" --repo "$R" --slug landme >/dev/null 2>&1
WT="$PEON_HOME/worktrees/$(basename "$R")-landme"
t  "merge succeeds"                "$PEON" merge landme
t  "work landed on main"           test -f "$R/FAKE_WORK-landme.txt"
t  "report NOT landed"             sh -c "test ! -f '$R/PEON_REPORT.md'"
t  "merge commit exists"           sh -c "git -C '$R' log --oneline -1 | grep -q 'merge peon/landme'"
t  "worktree removed"              sh -c "test ! -d '$WT'"
t  "branch removed"                sh -c "! git -C '$R' show-ref --verify --quiet refs/heads/peon/landme"
t  "meta removed"                  sh -c "test ! -f '$PEON_HOME/meta/landme.json'"
t  "repo clean after merge"        sh -c "test -d '$R' && test -z \"\$(git -C '$R' status --porcelain)\""

# C1: merge must refuse when the peon worktree's HEAD isn't at the tip of its own branch
# (a peon that detached HEAD and committed there gets its report/diff reviewed off HEAD,
# but a plain merge of the branch would land the stale tip and cleanup would then destroy
# the unreachable commits)
"$PEON" dispatch fake "c1 stray head" --repo "$R" --slug c1slug >/dev/null 2>&1
WTC1="$PEON_HOME/worktrees/$(basename "$R")-c1slug"
git -C "$WTC1" checkout -q --detach
git -C "$WTC1" commit -q --allow-empty -m stray
tf "merge refuses detached peon HEAD" "$PEON" merge c1slug
"$PEON" scrap c1slug >/dev/null 2>&1

# C2: merge must refuse a detached TARGET repo HEAD unconditionally (not just under --into) —
# a merge commit onto detached HEAD is orphaned the moment you switch branches
"$PEON" dispatch fake "c2 detached target" --repo "$R" --slug c2slug >/dev/null 2>&1
git -C "$R" checkout -q --detach
tf "merge refuses detached target"   "$PEON" merge c2slug
git -C "$R" checkout -q -
t  "merge works again after checkout" "$PEON" merge c2slug

# conflict: peon and main both edit README.md
R2="$(mkrepo)"
"$PEON" dispatch fake "conflict me" --repo "$R2" --slug clash >/dev/null 2>&1
WT2="$PEON_HOME/worktrees/$(basename "$R2")-clash"
( cd "$WT2" && echo "peon side" > README.md && git add README.md && git commit -qm "fake: conflict edit" )
( cd "$R2" && echo "main side" > README.md && git add README.md && git commit -qm "main edit" )
tf "conflicting merge refused"     "$PEON" merge clash
t  "repo clean after aborted merge" sh -c "test -d '$R2' && test -z \"\$(git -C '$R2' status --porcelain)\""
t  "worktree intact after abort"   test -d "$WT2"
tf "merge --into wrong branch"     "$PEON" merge clash --into not-checked-out-branch
t  "scrap succeeds"                "$PEON" scrap clash
t  "scrap removed worktree"        sh -c "test ! -d '$WT2'"
t  "scrap removed branch"          sh -c "! git -C '$R2' show-ref --verify --quiet refs/heads/peon/clash"
t  "scrap removed meta"            sh -c "test ! -f '$PEON_HOME/meta/clash.json'"

# dirty peon worktree: merge refuses, scrap proceeds
R5="$(mkrepo)"
"$PEON" dispatch fake "dirty merge" --repo "$R5" --slug dm >/dev/null 2>&1
WT5="$PEON_HOME/worktrees/$(basename "$R5")-dm"
echo "wip" > "$WT5/UNCOMMITTED.txt"
tf "merge refuses dirty worktree"  "$PEON" merge dm
t  "scrap discards dirty worktree" "$PEON" scrap dm

# mid-task provider death: residue preserved, then scrap cleans
R4="$(mkrepo)"
tf "failed dispatch exits nonzero" env PEON_FAKE_FAIL=1 "$PEON" dispatch fake "doomed" --repo "$R4" --slug doomed
WT4="$PEON_HOME/worktrees/$(basename "$R4")-doomed"
t  "worktree preserved"            test -d "$WT4"
t  "meta preserved"                test -f "$PEON_HOME/meta/doomed.json"
t  "report handles missing report" sh -c "'$PEON' report doomed | grep -qi 'no PEON_REPORT'"
tf "poke refuses empty session"    "$PEON" poke doomed "fix it"
t  "scrap cleans failed peon"      "$PEON" scrap doomed
t  "failed peon meta removed"      sh -c "test ! -f '$PEON_HOME/meta/doomed.json'"

# global slug uniqueness across repos
RA="$(mkrepo)"; RB="$(mkrepo)"
t  "slug in repo A"                "$PEON" dispatch fake "a" --repo "$RA" --slug shared
tf "same slug refused in repo B"   "$PEON" dispatch fake "b" --repo "$RB" --slug shared

# parallel: two fake peons on one repo, no interference
R3="$(mkrepo)"
"$PEON" dispatch fake "task one" --repo "$R3" --slug p1 >/dev/null 2>&1 &
"$PEON" dispatch fake "task two" --repo "$R3" --slug p2 >/dev/null 2>&1 &
wait
t  "parallel peon 1 exists"        test -f "$PEON_HOME/worktrees/$(basename "$R3")-p1/PEON_REPORT.md"
t  "parallel peon 2 exists"        test -f "$PEON_HOME/worktrees/$(basename "$R3")-p2/PEON_REPORT.md"
t  "parallel merge 1"              "$PEON" merge p1
t  "parallel merge 2"              "$PEON" merge p2
t  "both tasks landed"             sh -c "grep -q 'task one' '$R3/FAKE_WORK-p1.txt' && grep -q 'task two' '$R3/FAKE_WORK-p2.txt'"

# --- Task 6: real runners (dry-run seam; no provider CLIs needed) ---
fresh_home
R="$(mkrepo)"
export PEON_DRY_RUN=1
t  "codex dry dispatch ok"         "$PEON" dispatch codex "real task" --repo "$R" --slug cdx
CMD="$PEON_HOME/logs/cdx.cmd"
t  "codex cmd captured"            test -f "$CMD"
t  "codex uses exec --json"        sh -c "grep -q 'codex exec --json' '$CMD'"
t  "codex workspace-write"         sh -c "grep -q -- '-s workspace-write' '$CMD'"
t  "codex approval never"          sh -c "grep -q 'approval_policy=never' '$CMD'"
t  "grok dry dispatch ok"          "$PEON" dispatch grok "real task" --repo "$R" --slug grk
GCMD="$PEON_HOME/logs/grk.cmd"
t  "grok sandbox workspace"        sh -c "grep -q -- '--sandbox workspace' '$GCMD'"
t  "grok default approve mode"     sh -c "grep -q -- '--always-approve' '$GCMD'"
t  "grok pinned session"           sh -c "grep -qE -- '-s [0-9a-f-]{36}' '$GCMD'"
t  "grok prompt file"              sh -c "grep -q -- '--prompt-file' '$GCMD'"
t  "codex poke dry ok"             "$PEON" poke cdx "revise"
t  "codex resume by session id"    sh -c "grep -q 'codex exec resume dry-run' '$CMD'"
t  "codex resume sandbox via -c"   sh -c "grep -q 'sandbox_mode=\"workspace-write\"' '$CMD'"
t  "resume line has no -s flag"    sh -c "! grep -E -q 'resume .* -s ' '$CMD'"
t  "no --last anywhere"            sh -c "! grep -q -- '--last' '$CMD'"
t  "grok poke dry ok"              "$PEON" poke grk "revise"
t  "grok resume by session id"     sh -c "grep -q -- '--resume dry-run' '$GCMD'"
GA="$(GROK_APPROVE=mode:auto "$PEON" dispatch grok "x" --repo "$R" --slug grka >/dev/null 2>&1; grep -c -- '--permission-mode auto' "$PEON_HOME/logs/grka.cmd")"
t  "GROK_APPROVE=mode:auto maps flag" test "$GA" -ge 1

# I1/M10: invalid GROK_APPROVE must fail closed (not silently dispatch with no approve flag)
tf "invalid GROK_APPROVE fails closed" env GROK_APPROVE=bogus "$PEON" dispatch grok "x" --repo "$R" --slug ga1
t  "invalid GROK_APPROVE leaves no cmd log" sh -c "test ! -f '$PEON_HOME/logs/ga1.cmd'"
"$PEON" scrap ga1 >/dev/null 2>&1

unset PEON_DRY_RUN

echo; echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
