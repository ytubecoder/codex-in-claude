# Session Log

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
