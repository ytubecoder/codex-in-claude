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
- Draft-until-reviewed: peon output stays on `peon/<slug>` branches in `$PEON_HOME/worktrees/`; only explicit `peon merge` (after review) lands it. Never merge without reviewing the diff.
- Metadata is OUT of the worktree: `$PEON_HOME/meta/<slug>.json`, atomically reserved (noclobber) — slugs are global identities. Nothing peon-related is ever written into the user's repo or worktree by the harness.
- Contract gates after every provider run: commits since gate ref (dispatch: base; poke: pre-poke HEAD) + committed PEON_REPORT.md + clean worktree. Violations fail loudly and preserve the worktree.
- `bin/peon` is the only interface — skills and agents never hand-roll worktree or provider incantations. bash-3.2-compatible; deps: git, python3, uuidgen. Never jq, never `codex exec resume --last`.
- Grok headless can only COMMIT with `--always-approve` (`GROK_APPROVE=always`, the live-locked default); `--permission-mode auto`/`dontAsk` permit file edits but block git-commit shell calls — the peon then trips the contract gate having "succeeded".
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
