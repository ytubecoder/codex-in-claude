# codex-in-claude

Two Claude Code skills backed by external CLI agents (Codex, Grok), plus the `bin/peon` script:

- `skills/plan-check/SKILL.md` — mediated plan review (opinions in). Read-only reviewers.
- `skills/peon-poke/SKILL.md` — farm implementation work out to worktree-isolated peons (labor out). `bin/peon` is the deterministic interface; the skill teaches workflow only.

This repo is the source of truth. Installed copies on this machine live in `~/.claude/skills/{plan-check,peon-poke}/` (that dir is its own git repo, no remote) and `~/.local/bin/peon` — re-sync installed copies after editing here.

## Invariants — plan-check
- Reviewers are independent: identical round-1 prompts; no reviewer sees another's output except a Claude-authored relay on a direct contradiction (escalation only).
- Plan content travels inside the prompt — reviewers work without repo access, read-only sandboxes.
- The skill never edits plan files.
- `codex exec resume` has NO `-s` flag — sandbox for resumed sessions goes via `-c sandbox_mode=...` (broke live 2026-07-29 on codex-cli 0.145.0).

## Invariants — peon-poke
- Hub-and-spoke: all work products return to the orchestrator; peons never share state.
- Draft-until-reviewed: peon output stays on `peon/<slug>` branches in `$PEON_HOME/worktrees/`; only explicit `peon merge` (after review) lands it. Never merge without reviewing the diff.
- Metadata is OUT of the worktree: `$PEON_HOME/meta/<slug>.json`, atomically reserved (noclobber) — slugs are global identities. Nothing peon-related is ever written into the user's repo or worktree by the harness.
- Contract gates after every provider run: commits since gate ref (dispatch: base; poke: pre-poke HEAD) + committed PEON_REPORT.md + clean worktree. Violations fail loudly and preserve the worktree.
- `bin/peon` is the only interface — skills and agents never hand-roll worktree or provider incantations. bash-3.2-compatible; deps: git, python3, uuidgen. Never jq, never `codex exec resume --last`.
- `merge` strips `PEON_REPORT.md` only when the merge target didn't already track it (review artifact, not product code).
- Tests: `bash tests/peon.test.sh` (fake provider + dry-run, deterministic, no provider CLIs needed). Run after any `bin/peon` change.

## Open decisions / roadmap
- Possible rename of repo + both skills (multi-provider name); deliberately deferred.
- Remote endpoints over tailscale/ssh for both skills: feasibility established, not built. Sessions are per-host, so all rounds/pokes of one review/peon must stick to one endpoint.
- v2 candidates: dispatch timeout/watchdog; richer `peon list` status.
