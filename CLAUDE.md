# codex-in-claude

Two Claude Code skills backed by external CLI agents (Codex, Grok, Gemini via gemini-cli or Antigravity/agy), plus the `bin/peon` script:

- `skills/plan-check/SKILL.md` — mediated plan review (opinions in). Read-only reviewers.
- `skills/peon-poke/SKILL.md` — farm implementation work out to worktree-isolated peons (labor out). `bin/peon` is the deterministic interface; the skill teaches workflow only.

This repo is the source of truth. Installed copies on this machine live in `~/.claude/skills/{plan-check,peon-poke}/` (that dir is its own git repo, no remote) and `~/.local/bin/peon` — re-sync installed copies after editing here.

## Invariants — plan-check
- Reviewers are independent: identical round-1 prompts; no reviewer sees another's output except a Claude-authored relay on a direct contradiction (escalation only).
- Plan content travels inside the prompt — reviewers work without repo access, read-only sandboxes.
- The skill never edits plan files.
- `codex exec resume` has NO `-s` flag — sandbox for resumed sessions goes via `-c sandbox_mode=...` (broke live 2026-07-29 on codex-cli 0.145.0).
- Gemini reviews run `--approval-mode plan` (read-only policy mode) from a dedicated `mktemp -d` dir: gemini sessions are per-directory and resumed by recency only, so the private dir is what makes `--resume latest` unambiguous across rounds.
- Antigravity (`agy`) reviews run `--mode plan --output-format json`; capture `conversation_id` from the JSON for rounds 2+ (`--conversation <id>`). Never seat both `gemini` and `agy` in one council — same model family, no independence.
- gemini-cli stopped serving consumer Google accounts (free/AI Pro/Ultra) on 2026-06-18 — "gemini" requests route to `agy` unless the machine has an enterprise/API-key gemini setup.

## Invariants — peon-poke
- Hub-and-spoke: all work products return to the orchestrator; peons never share state.
- Draft-until-reviewed: peon output stays on `peon/<slug>` branches in `$PEON_HOME/worktrees/`; only explicit `peon merge` (after review) lands it. Every merge gets exactly one review treatment — full-diff read (classic), the complete black-box gate set per `docs/BLACKBOX-ACCEPTANCE.md` (`peon check` + test audit + independent probes), or spot review (self-tested brief + foreman-run verify via `check` + diffstat + load-bearing hunks only) — never none.
- Evidence hierarchy: everything the peon writes (report prose, pasted test output) is generator-class self-reporting, advisory only; gates are computed foreman-side from git facts + foreman-run commands. Never chase a peon-reported test failure before reproducing via `peon check` (forced-color env leakage alone has faked failures, live 2026-08-02).
- Exit codes: 1 = usage/environment/provider error; 3 = peon contract violation, worktree + metadata preserved. The session id persists to meta BEFORE the contract gate, so poke/adopt still work after a tripped dispatch.
- `peon adopt <slug>` is the sanctioned recovery for sandbox-blocked commits (work + PEON_REPORT.md on disk, uncommitted, exit 3): foreman-commits the lot on the peon branch. Refuses a clean worktree or missing report. Adoption is mechanics, NOT acceptance — review still decides the merge. Never hand-roll `git add/commit` in a peon worktree.
- Color-forcing env vars (`CLICOLOR_FORCE`, `FORCE_COLOR`, `CLICOLOR`) are unset at the top of `bin/peon` — Claude Code's Bash tool exports CLICOLOR_FORCE=1, which leaks forced ANSI into peon test runs and the verify gate, faking failures in text-matching helpers.
- Merge subject truncation is char-safe via python — bash `printf '%.60s'` counts bytes and cut a multibyte char mid-sequence (invalid UTF-8 merge subject, live 2026-08-02).
- `peon check` `--allow`/`--verify` overrides: one-off when a contract was recorded at dispatch; late-DECLARE the contract (persisted to meta, merge-enforced) when none was — otherwise a check-time verify would never bind the merge.
- Acceptance contract in meta: `--allow` (file-scope globs, fnmatch, `*` crosses `/`) and `--verify` (command) recorded at dispatch. `peon check` executes them foreman-side and records the verify result against the branch tip sha; `peon merge` refuses out-of-scope files and failed/stale/never-run verify (`--unchecked` bypasses with a loud warning). Peon-pasted test output is advisory only — the foreman-run verify is the gate.
- `peon report` usage line is parsed from logs already on disk (codex JSONL: cumulative totals, counter-drop = run boundary, run finals summed; agy: last usage dict per JSON doc, summed; grok/gemini: no counts → `n/a`). Self-reported, approximate, observability only — NEVER add a "savings" estimate: the counterfactual never ran and a fabricated metric would nudge farming-out of tasks where the method is net-negative.
- Metadata is OUT of the worktree: `$PEON_HOME/meta/<slug>.json`, atomically reserved (noclobber) — slugs are global identities. Nothing peon-related is ever written into the user's repo or worktree by the harness.
- Contract gates after every provider run: commits since gate ref (dispatch: base; poke: pre-poke HEAD) + committed PEON_REPORT.md + clean worktree. Violations fail loudly and preserve the worktree.
- `bin/peon` is the only interface — skills and agents never hand-roll worktree or provider incantations. bash-3.2-compatible; deps: git, python3, uuidgen. Never jq, never `codex exec resume --last`.
- Grok headless can only COMMIT with `--always-approve` (`GROK_APPROVE=always`, the live-locked default); `--permission-mode auto`/`dontAsk` permit file edits but block git-commit shell calls — the peon then trips the contract gate having "succeeded". AND: in linked worktrees grok's sandbox cannot write the main repo's `.git/worktrees/` gitdir at all (observed 3× live 2026-08-02, loops repo), so even `--always-approve` grok exits 3 with work + report on disk — the healthy grok path is dispatch → exit 3 → review → `peon adopt` → merge, with each poke round repeating exit 3 → adopt. The dispatch prompt carries the no-escape rule (never improvise remotes/`.git` dirs around a blocked commit).
- Gemini peons run `--approval-mode yolo` with NO `-s`/`--sandbox`: a linked worktree's git dir lives under the main repo's `.git/worktrees/`, outside gemini's seatbelt project boundary, so a sandboxed peon could edit but never commit (grok-approve-class trap). Containment is the worktree + review. ⚠ Flag-semantics reasoning only (gemini-cli 0.53.0) — NOT live-verifiable on consumer accounts since the 2026-06-18 cutoff; verify before trusting on an enterprise setup.
- Gemini has no id-addressed resume: per-directory session store, poke runs `--resume latest` from the worktree cwd. Invariant: nothing but the harness ever runs gemini inside a peon worktree.
- `agy` (Antigravity) peons run `--dangerously-skip-permissions --output-format json --print-timeout 30m`, NO `--sandbox` (same worktree-git-dir reasoning as gemini). `conversation_id` is extracted fail-closed from the JSON (missing id or `status != SUCCESS` dies); poke resumes with `--conversation <id>`. The 30m print-timeout matters — agy's default is 5m, which would kill real dispatches mid-task. LIVE-LOCKED 2026-07-30 (agy 1.1.8): skip-permissions commits work; contract gate passes; resume keeps context.
- agy can MINT A NEW conversation_id on resume (observed live 2026-07-30 — context carries over but the id rotates). The log accumulates one JSON doc per run; `extract_agy_conversation` reads the LAST doc, and `cmd_poke` persists the new head to meta before the contract gate. Never resume an older id from the chain — later pokes' context silently vanishes.
- `merge` strips `PEON_REPORT.md` only when the merge target didn't already track it (review artifact, not product code).
- Tests: `bash tests/peon.test.sh` (fake provider + dry-run, deterministic, no provider CLIs needed). Run after any `bin/peon` change.

## Open decisions / roadmap
- Possible rename of repo + both skills (multi-provider name); deliberately deferred.
- Remote endpoints over tailscale/ssh for both skills: feasibility established, not built. Sessions are per-host, so all rounds/pokes of one review/peon must stick to one endpoint.
- v2 candidates: dispatch timeout/watchdog; richer `peon list` status.
