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
| `peon dispatch <codex\|grok\|gemini\|agy> "<task>" [--repo DIR] [--base REF] [--slug NAME] [--force]` | Create worktree + `peon/<slug>` branch, run the provider inside it. Synchronous — background it to keep working. Fails loudly if the peon breaks contract (no commits / no report / dirty tree), preserving the worktree for inspection. |
| `peon list [--repo DIR]` | Active peons, report status, orphan detection |
| `peon report <slug>` | PEON_REPORT.md + commits + diffstat vs base (+ dirty-tree warning) |
| `peon diff <slug>` | Full diff vs base |
| `peon poke <slug> "<feedback>"` | Resume the same provider session for revisions; fails loudly on a no-op round |
| `peon merge <slug> [--into BRANCH]` | After review: merge, strip the report, clean up. `--into` only asserts BRANCH is already checked out — peon never switches your branch. |
| `peon scrap <slug>` | Discard the work, remove worktree + branch + metadata |

Slugs are globally unique across repos. Grok approval strategy is `GROK_APPROVE` (`mode:<m>` or `always`). Gemini peons run `--approval-mode yolo` (required for headless commits) and resume as `--resume latest` scoped to the worktree — never run your own gemini session inside a peon worktree, or the poke will resume the wrong session. `agy` (Antigravity) is the provider for Google AI Pro/Ultra subscriptions — gemini-cli stopped serving consumer accounts on 2026-06-18; when the user says "gemini" for labor and only `agy` works on this machine, dispatch `agy`. State (worktrees, logs, metadata) lives under `~/.peon/` by default, overridable via `PEON_HOME`.

## Workflow

1. **Scope the task.** Peons execute; they don't design. Good: a feature slice, a refactor, tests, docs — one well-defined chore with clear done-criteria. If the task is ambiguous, tighten it (or brainstorm with the user) before dispatch. Include acceptance criteria and relevant file paths in the task text.
2. **Dispatch.** One peon per task. Parallel peons = *different* tasks (never the same task to two providers — that's plan-check's council, not labor). Provider: user's choice if stated, else either. Dirty repo? Ask the user before `--force` — dispatch branches from the last *commit*, so uncommitted work is invisible to the peon.
3. **Wait.** Dispatch is synchronous (minutes). Background it and continue other work, or wait if idle. If a dispatch hangs (stuck provider), kill the process and `peon scrap` the slug — the worktree holds whatever happened.
4. **Review like a code review.** `peon report <slug>`, then `peon diff <slug>`. Judge correctness, conventions, tests, scope-creep against your conversation context — you know things the peon does not. Then either `peon poke <slug> "<specific feedback>"` (repeatable) or `peon merge <slug>`.
5. **Report to the user.** Summarize what the peon did, your review verdict, and what you merged or why you poked/scrapped.

## Rules

- **Never merge without reviewing the diff.** Draft-until-reviewed is the whole point.
- **Never bypass the script** to poke provider sessions or touch `peon/*` branches by hand.
- Peons are sandboxed to their worktree and may lack network access — don't dispatch tasks needing `npm install` of new deps without checking the result carefully.
- A failed peon leaves its worktree AND metadata for inspection: `peon report` still works; `peon scrap` cleans up. Logs live in `~/.peon/logs/` and are removed on merge/scrap; a long-ignored failed peon is the only thing that accumulates — `peon list` surfaces them.
- Merge conflicts are the foreman's job: resolve manually or `peon poke` the peon to rebase onto an updated base.
- Very large repos: `git worktree add` copies nothing but checkout time and LFS smudge can be slow — prefer `--base` on a small stable ref where possible.
