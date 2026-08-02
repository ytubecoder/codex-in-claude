---
name: peon-poke
description: "Farm implementation work out to external CLI agents (Codex, Grok, Gemini, Antigravity) in isolated git worktrees, then review and merge. Trigger phrases: 'peon-poke', 'dispatch a peon', 'farm this out', 'send this task to codex/grok/gemini/agy', 'have codex build', 'get grok to implement', 'gemini can build this', 'poke the peon'. Claude is the foreman: dispatches, reviews, pokes with feedback, merges."
user_invocable: true
---

# Peon Poke — Farm Implementation Work to External CLI Agents

`/plan-check` pulls **opinions** in; `/peon-poke` pushes **labor** out. An external agent (a "peon") does an implementation chore in an isolated git worktree; Claude — the foreman — reviews the work and merges it or sends it back. Nothing reaches the real working tree without review and an explicit merge.

All mechanics live in the `peon` script — never hand-roll worktrees or provider CLI calls. If `command -v peon` fails, tell the user to install it (README of ytubecoder/codex-in-claude) and stop.

## Commands

| Command | Does |
|---|---|
| `peon dispatch <codex\|grok\|gemini\|agy> "<task>" [--repo DIR] [--base REF] [--slug NAME] [--force] [--allow "glob[,glob...]"] [--verify "cmd"]` | Create worktree + `peon/<slug>` branch, run the provider inside it. Synchronous — background it to keep working. Fails loudly if the peon breaks contract (no commits / no report / dirty tree), preserving the worktree. `--allow`/`--verify` record the acceptance contract (file-scope allowlist + verify command) that `check` executes and `merge` enforces. |
| `peon list [--repo DIR]` | Active peons, report status, orphan detection |
| `peon report <slug>` | PEON_REPORT.md + commits + diffstat vs base + provider-self-reported token usage (codex/agy; `n/a` for grok/gemini) (+ dirty-tree warning). Usage is observability only — never quote it as "savings"; the counterfactual is unmeasurable. |
| `peon diff <slug> [--stat\|--files]` | Diff vs base. `--stat`/`--files` for black-box review (never print the full diff you don't intend to read); bare = full diff for classic review |
| `peon check <slug> [--allow ...] [--verify ...]` | Mechanical acceptance gates, foreman-side: contract + allowlist scope + verify command run in the worktree (result recorded against the branch tip; a later poke invalidates it). Overrides are one-off when a contract was recorded at dispatch; when none was, they late-declare the contract (persisted, merge-enforced). |
| `peon adopt <slug> [-m "msg"]` | Foreman-commits work a sandbox-blocked provider left uncommitted (work + `PEON_REPORT.md` on disk, dispatch/poke exited 3). Refuses a clean worktree or a missing report. Adoption is mechanics, not acceptance — review still decides the merge. |
| `peon poke <slug> "<feedback>"` | Resume the same provider session for revisions; fails loudly on a no-op round |
| `peon merge <slug> [--into BRANCH] [--unchecked]` | After review: merge, strip the report, clean up. Refuses out-of-scope files and failed/stale/missing verify when a contract was recorded; `--unchecked` bypasses loudly. `--into` only asserts BRANCH is already checked out — peon never switches your branch. |
| `peon scrap <slug>` | Discard the work, remove worktree + branch + metadata |

Slugs are globally unique across repos. Exit codes: `1` = usage/environment/provider error; `3` = peon contract violation with the worktree preserved. Grok approval strategy is `GROK_APPROVE` (`mode:<m>` or `always`) — but expect grok dispatches to exit 3 even on success: grok's sandbox cannot write a linked worktree's git dir (it lives under the main repo's `.git/worktrees/`), so the peon leaves work + report on disk uncommitted. That is the healthy grok path, not a crash: review, `peon adopt <slug>`, continue. The session persists before the gate, so pokes still work — and each poke round repeats the exit-3 → adopt pattern. Gemini peons run `--approval-mode yolo` (required for headless commits) and resume as `--resume latest` scoped to the worktree — never run your own gemini session inside a peon worktree, or the poke will resume the wrong session. `agy` (Antigravity) is the provider for Google AI Pro/Ultra subscriptions — gemini-cli stopped serving consumer accounts on 2026-06-18; when the user says "gemini" for labor and only `agy` works on this machine, dispatch `agy`. State (worktrees, logs, metadata) lives under `~/.peon/` by default, overridable via `PEON_HOME`.

## Workflow

1. **Scope the task.** Peons execute; they don't design. Good: a feature slice, a refactor, tests, docs — one well-defined chore with clear done-criteria. If the task is ambiguous, tighten it (or brainstorm with the user) before dispatch. Include acceptance criteria and relevant file paths in the task text.
2. **Pick the review mode BEFORE dispatch** — it changes how you dispatch:
   - **Black-box acceptance** (default for spec-driven, multi-file work in a repo with a runnable test suite): write a self-contained spec (all design decisions pre-made, mandated tests with names+assertions, file allowlist, DoD), commit it, then dispatch with `--allow` and `--verify` so the contract is recorded. Full method: `docs/BLACKBOX-ACCEPTANCE.md` in the codex-in-claude repo.
   - **Spot review** (mid-size self-tested chores — too big to read 1:1, too small to spec): brief the peon as a *self-tested work unit* — "add the mandated tests, run them plus the full suite, paste BOTH actual outputs into PEON_REPORT.md". Dispatch with `--verify` (or late-declare it at check time). You will read the diffstat and only the load-bearing hunks, never the full diff. See the Spot review variant in `docs/BLACKBOX-ACCEPTANCE.md`.
   - **Classic full-diff review** (small chores, no test harness, or style/architecture is the point): dispatch with the criteria in the task text; you will read the whole diff.
3. **Dispatch.** One peon per task. Parallel peons = *different* tasks (never the same task to two providers — that's plan-check's council, not labor). Provider: user's choice if stated, else either. Dirty repo? Ask the user before `--force` — dispatch branches from the last *commit*, so uncommitted work is invisible to the peon. While a black-box peon works, pre-author your independent probes — the wait is free.
4. **Review.**
   - *Black-box:* `peon report <slug>` → `peon check <slug>` (contract + scope + foreman-run verify; never trust the report's pasted test output) → `peon diff <slug> --files` → read ONLY the test files against the spec's mandated list (really asserting, no tautologies, no test-gaming) → run your independent probes in the worktree. Do NOT read the implementation diff — that's the token sink this mode exists to avoid.
   - *Spot:* `peon report <slug>` (pasted outputs are triage, never the gate) → `peon check <slug>` (the foreman-run verify IS the gate) → `peon diff <slug> --stat` → read only the hunks where a defect would slip past the verify suite: interfaces, error paths, anything security- or data-touching. If the diffstat surprises you — unexpected files, outsized churn — escalate to a stronger treatment instead of squinting harder.
   - *Classic:* `peon report <slug>`, then `peon diff <slug>`. Judge correctness, conventions, tests, scope-creep against your conversation context — you know things the peon does not.
   Then either `peon poke <slug> "<specific feedback>"` (repeatable; re-run `check` after — a poke invalidates the recorded verify) or `peon merge <slug>`.
5. **Report to the user.** Summarize what the peon did, your review verdict (which mode, which gates), and what you merged or why you poked/scrapped.

## Rules

- **Every merge gets exactly one review treatment: the full-diff read (classic), the complete black-box gate set (check + test audit + probes), or the spot set (foreman-run verify + diffstat + load-bearing hunks). Never none.** Draft-until-reviewed is the whole point; `merge` mechanically enforces recorded scope/verify gates, and `--unchecked` is for deliberate, stated overrides only.
- **Evidence beats claims.** Everything the peon writes — report prose, pasted test output, "all green" — is generator-class self-reporting and advisory only. The gates that decide (contract, scope, verify) are computed foreman-side from git facts and foreman-run commands. Never chase a peon-*reported* test failure before reproducing it with `peon check` — forced-color env leakage alone has faked failures.
- **Never bypass the script** to poke provider sessions or touch `peon/*` branches by hand.
- Peons are sandboxed to their worktree and may lack network access — don't dispatch tasks needing `npm install` of new deps without checking the result carefully.
- A failed peon leaves its worktree AND metadata for inspection: `peon report` still works; `peon scrap` cleans up. Logs live in `~/.peon/logs/` and are removed on merge/scrap; a long-ignored failed peon is the only thing that accumulates — `peon list` surfaces them.
- Merge conflicts are the foreman's job: resolve manually or `peon poke` the peon to rebase onto an updated base.
- Very large repos: `git worktree add` copies nothing but checkout time and LFS smudge can be slow — prefer `--base` on a small stable ref where possible.
