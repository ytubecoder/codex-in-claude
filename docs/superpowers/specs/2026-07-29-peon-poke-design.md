# peon-poke — design spec (2026-07-29)

**Status:** shipped 2026-07-29. Council-reviewed plan (Codex + Grok, 2 rounds), implemented via parallel agent streams, final whole-branch review + fix wave (2 criticals caught: detached-HEAD merge data-loss paths), 104 deterministic tests, live-verified per the testing plan below (all 4 tests). **Locked live findings:** grok headless commits require `--always-approve` (`GROK_APPROVE=always`, now the default — `mode:auto`/`mode:dontAsk` permit file edits but block git commits, tripping the contract gate); codex `exec resume <id> … - < promptfile` stdin form confirmed working; codex session id extraction from `--json` JSONL confirmed against production output.

## Purpose

Second function of this repo: farm implementation work out to the same external CLI backends `/plan-check` uses (Codex, Grok). `/plan-check` pulls **opinions** in; `/peon-poke` pushes **labor** out. Claude — or any future orchestration agent — is the foreman: it dispatches tasks, reviews the work, and merges or sends it back.

## Principles (inherited from plan-check)

- **Hub-and-spoke.** All work products return to the orchestrator. Peons never coordinate with each other or share state.
- **Draft-until-reviewed.** Peon output lands on an isolated branch; nothing reaches the real working tree without orchestrator review and an explicit merge.
- **Deterministic backends.** Same CLIs, same auth, same machines as plan-check.

Key difference from plan-check: reviewers were read-only and needed no repo access (plan travels in the prompt). Peons must read AND write code, so they get a full checkout — an isolated one.

## Architecture — two layers

### 1. `bin/peon` — the harness-agnostic interface

A small shell script that encapsulates all provider incantations behind one deterministic command. This is the piece that makes peons available to *any* orchestration agent — main Claude, subagents, Workflow scripts, the loops harness, cron jobs — anything that can run Bash. Skills are prose for Claude; the script is the contract for everyone else.

Commands:

| Command | Does |
|---|---|
| `peon dispatch <codex\|grok> "<task>" [--repo DIR] [--base REF] [--slug NAME]` | Create worktree + branch, run the provider CLI inside it, print slug + paths. Synchronous — callers background it if they want async. |
| `peon list [--repo DIR]` | Active peon worktrees + status |
| `peon report <slug>` | Print `PEON_REPORT.md` + diffstat vs base |
| `peon diff <slug>` | Full diff vs base |
| `peon poke <slug> "<feedback>"` | Resume the same provider session in the same worktree for revisions |
| `peon merge <slug> [--into REF]` | After review: merge the peon branch, then clean up |
| `peon scrap <slug>` | Remove worktree + branch, discarding the work |

### 2. Skill layer (Claude-facing)

Repo restructures from single root `SKILL.md` to `skills/plan-check/SKILL.md` + `skills/peon-poke/SKILL.md` (README install instructions updated to match). The peon-poke skill teaches the workflow, not the mechanics — mechanics live in `bin/peon`.

Skill flow:
1. **Scope the task.** Small, well-defined implementation chores: a feature slice, a refactor, tests, docs. If the task is ambiguous, tighten it before dispatch — peons execute, they don't design.
2. **Dispatch.** One peon per task (parallel peons = different tasks, not the same task twice; a "council of peons" is a non-goal). Provider choice: user's word, else either.
3. **Wait** (or background and continue other work).
4. **Review like a code review** — read report + diff, judge correctness/conventions/tests using conversation context. Then `poke` with feedback or `merge`.
5. **Report to the user.** Never merge without review.

## Worktree lifecycle

- Dispatch: `git worktree add -b peon/<slug> ~/.peon/worktrees/<repoName>-<slug> <base>` (base defaults to current HEAD). Worktrees live outside the repo to avoid nesting; branches are namespaced `peon/*`.
- The provider CLI runs headless *inside the worktree* with a write-enabled, worktree-scoped sandbox:
  - codex: `codex exec -s workspace-write -c approval_policy=never`, cwd = worktree (resume: `-c sandbox_mode=` — resume has no `-s`)
  - grok: pinned session UUID (`-s`), `--sandbox workspace`, approve strategy via `GROK_APPROVE`, cwd = worktree
- **Peon prompt contract** (embedded in every dispatch): do the task; commit all changes to the current branch with clear messages; write `PEON_REPORT.md` (what changed, why, how verified, open questions) and commit it too; leave the worktree clean. The harness *enforces* this after every run (contract gate: commits since gate ref, committed report, clean tree — violations fail loudly with the worktree preserved).
- **Metadata (amended per council review):** `$PEON_HOME/meta/<slug>.json` — *outside* the worktree (provider, session id, task text, base sha, worktree path, timestamps) so any later session or agent can resume, review, or clean up cold. Slugs are global identities, atomically reserved. Original design placed `.peon.json` inside the worktree; moved out to avoid `info/exclude` mutation, races, and the peon committing harness state.

## Provider mechanics — verified 2026-07-29 (codex-cli 0.145.0, grok 0.2.112)

- ✅ Codex headless resume by session id: `codex exec resume <SESSION_ID> "<prompt>"` accepts a UUID — parallel-safe poke. (`resume --last` remains global-last; never use it.)
- ✅ Codex write flags: `--full-auto` does **not** exist on `codex exec` in 0.145.0. Use `-s workspace-write` (+ `-c approval_policy=never` if approvals surface), `-C <worktree>` for the working root. `-o/--output-last-message <file>` and `--json` (JSONL events, includes session id) give the harness deterministic capture of the session id at dispatch time.
- ✅ Grok headless writes: knobs exist — `--sandbox workspace` + `--permission-mode` (`auto`/`dontAsk`) or blanket `--always-approve`; `grok agent stdio|headless` also available. Which permission mode suffices without a TTY is confirmed by live test 1 below.
- Grok's native `--worktree`/`--worktree-ref` exist but we manage worktrees ourselves for provider parity.

## Error handling

- Dispatch failures (CLI missing, dirty base, name collision) fail loudly before any worktree is created.
- A peon that errors mid-task leaves its worktree intact for inspection — `report`/`diff` still work; `scrap` cleans up.
- `merge` refuses if the branch doesn't merge cleanly; orchestrator resolves or pokes the peon to rebase.

## Non-goals

- Peon-to-peon communication or shared state.
- Autonomous merge without orchestrator review.
- Same task to multiple providers for comparison (that's plan-check's council pattern, not labor).
- Remote endpoints — separate spec'd feature; composes later (dispatch over tailnet ssh).

## Testing plan (live, before shipping)

1. Throwaway git repo; dispatch a trivial real task to each provider ("add a --version flag and a test"); verify: commits on `peon/<slug>`, `PEON_REPORT.md` present, diff sane.
2. `poke` with a revision request; verify session resumed and diff updated.
3. `merge` lands the branch; `scrap` leaves no worktree/branch residue.
4. Two peons in parallel on different tasks; verify no interference.

## Relation to /plan-check

Same backends, opposite direction. Natural combo: `/plan-check` (or council) a plan, then `/peon-poke` the approved tasks out — reviewers vet the thinking, peons do the typing, Claude mediates both.

## Alternatives considered

- **Direct in-tree writes** (no worktree): simplest, but concurrent peons and Claude's own edits trample each other, and there's no review gate before code lands. Rejected as default; could return later as an explicit flag if worktree overhead annoys in practice.
- **Pure skill, no script**: every orchestration agent re-derives fragile CLI incantations from prose. Rejected — the script is what makes "other models through their harness" real.
- **Async daemon/queue**: YAGNI. Synchronous script + caller-side backgrounding covers it.
