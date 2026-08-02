# Session Log

## 2026-08-02 — Black-box acceptance codified: recorded contracts, peon check, gated merge, usage line

### Summary
- Codified the field-proven black-box acceptance method (same-day farm-out: ~1,500-line 11-file feature, zero pokes, foreman never read the implementation diff) into `docs/BLACKBOX-ACCEPTANCE.md` and the tooling: `peon dispatch --allow/--verify` records the acceptance contract in meta; new `peon check` runs contract + scope + foreman-side verify (result bound to the branch tip sha, invalidated by pokes); `peon merge` refuses out-of-scope files and failed/stale/never-run verify (`--unchecked` bypasses loudly); `peon diff` grew `--stat`/`--files` and now rejects unknown options (previously swallowed them and dumped the full diff — the exact 1:1-read trap).
- `peon report` gained a provider-self-reported token usage line parsed from logs already on disk (codex JSONL run-final banking; agy per-doc; grok/gemini → `n/a`).
- 27 new tests (144 total green); SKILL.md now forces choosing the review mode BEFORE dispatch.

### Lessons Learned
- **Accepted:** trust moves off the returned code onto evidence the peon can't fake — spec-mandated tests audited by reading the test file alone, plus foreman-authored probes the peon never saw. Merge-time enforcement in the script beats prose rules.
- **Rejected:** a "tokens saved" estimate in `peon report` — the counterfactual never ran; any number is a proxy dressed as telemetry, and a visible metric would nudge farming out small tasks where spec overhead is net-negative. Usage stays observability-only.
- **Gotcha:** `cmd_diff` silently ignored unknown arguments — an arg-parsing gap that actively fought the method (a foreman asking for `--stat` got the full diff). Strict option parsing everywhere.

### Decisions
- Implemented the shared tooling core of the untracked draft `docs/superpowers/plans/2026-08-02-test-gated-dispatch.md` (verify-vs-tip-sha, merge refusal, loud bypass) compatibly; its `--lock` path-locking variant stays unimplemented pending its own discussion. `docs/superpowers/` is now gitignored (local-only planning notes).
- fnmatch allowlist semantics: `*` crosses `/` — documented, deliberate (glob lists stay short).

## 2026-07-30 — peon-poke: spec → council-reviewed plan → parallel build → live-verified ship

### Summary
- Shipped the repo's second function: `bin/peon` (dispatch implementation tasks to codex/grok in isolated worktrees; dispatch/list/report/diff/poke/merge/scrap; 104 deterministic tests) + `skills/peon-poke/SKILL.md`; repo restructured to `skills/{plan-check,peon-poke}/`. Installed: `~/.local/bin/peon` symlink + skills copied into `~/.claude/skills/`.
- Process was the full gauntlet: brainstorm → spec → written plan → `/plan-check council` (2 rounds) → plan r2 → subagent-driven build in two parallel streams → final whole-branch review (found 2 criticals) → fix wave → scoped re-review → live verification (all 4 spec tests, real provider calls).
- Fixed a live bug in plan-check itself: its round-2 codex incantation used `exec resume -s`, which codex-cli 0.145.0 rejects — discovered when the council's own round 2 returned empty.

### Lessons Learned
- **Accepted:** council plan review before building — Grok caught the codex-resume flag break (verified live 3×); the review also drove metadata out of the worktree (`~/.peon/meta/`) and two-stage contract gates. No unresolved disagreements after 2 rounds.
- **Accepted:** contract gates earned their keep on the FIRST real dispatch — grok exited 0 having committed nothing; pre-gate this would have been a silent no-op merge.
- **Accepted:** final whole-branch review on the strongest model with reproduction required — it *reproduced* two detached-HEAD data-loss paths in `merge` (worktree HEAD ≠ branch tip half-merges then destroys; detached target commits into the void) that briefs, tests, and council all missed.
- **Rejected:** grok headless `--permission-mode auto`/`dontAsk` — both allow file edits but block the git-commit shell calls; only `--always-approve` lets a peon commit. Locked as `GROK_APPROVE=always` default.
- **Gotcha:** `codex exec resume` accepts no `-s/--sandbox` — sandbox via `-c sandbox_mode=`. Broke plan-check's own skill live; both repo and installed copies fixed.
- **Gotcha:** a dry-run stub that writes byte-identical file content commits fine once, then fails under `set -e` on the second round ("nothing to commit") — Stream A root-caused and fixed with `--allow-empty`.

### Decisions
- peon metadata lives OUTSIDE the worktree at `$PEON_HOME/meta/<slug>.json`, atomically reserved (noclobber); spec amended — kills `info/exclude` mutation, races, and peon-commits-metadata risk.
- Poke's contract gate compares against pre-poke HEAD (not base) so a no-op revision round fails loudly.
- `merge` strips `PEON_REPORT.md` (review artifact) and refuses detached HEADs on either side; scrap warns-then-discards.
- Worktree path-hash (M3) parked with ruling: fails safe, unreachable with global slugs.
- peon-poke stays in this repo — same backends as plan-check, opposite direction (opinions in / labor out). Repo rename still open.

## 2026-07-29 — Add Grok reviewer and council mode

### Summary
- Extended the plan-check skill from Codex-only to multi-provider: Codex (default), Grok (Grok Build CLI), or both in parallel as a mediated council. README, repo description, and topics updated to match.
- All CLI mechanics live-tested before shipping: grok headless single-turn (`-p`/`--prompt-file`), pinned-UUID sessions (`-s` + `--resume`), `--sandbox read-only`; council fan-out ran both reviewers concurrently (codex 32s, grok 79s, wall time = slowest).

### Lessons Learned
- **Accepted:** grok session pinning via client-generated UUID (`-s <uuid>` then `--resume <uuid>`) — deterministic multi-round resume, immune to the "most recent session" ambiguity that codex `resume --last` has.
- **Accepted:** independent parallel reviews over reviewer-to-reviewer discussion — on the same seeded-flaw test plan, each reviewer produced unique real findings the other missed (codex: rate-limit evasion by rotating fake API keys; grok: webhook/health exemptions, deploy-before-tests sequencing). Convergence would have laundered those away.
- **Gotcha:** `codex exec` refuses to run outside a trusted/git directory — needs `--skip-git-repo-check`. Documented in SKILL.md.
- **Gotcha:** grok's `--prompt-file` sidesteps heredoc quoting entirely; prompt content (including full plan text) travels in-band, so reviewers need no repo access.

### Decisions
- Repo name stays `codex-in-claude` for now; rename is an open decision.
- Council architecture is hub-and-spoke: all feedback returns to Claude, reviewers never exchange messages. Sole exception: Claude may relay one reviewer's argument into the other's round-2 prompt on a direct contradiction (escalation only, Claude-authored).
- A standalone `grok-check` skill was built and tested first, then folded into plan-check and deleted — one skill, provider routing by trigger phrase.
- Remote reviewer endpoints (run the CLI on another tailnet host over ssh) assessed as feasible (per-provider runner indirection; remote host needs one-time CLI login; sessions are per-host so all rounds must stick to one endpoint) — spec'd, deliberately not built.
