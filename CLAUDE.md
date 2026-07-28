# codex-in-claude

Claude Code skill (`plan-check`) for mediated plan review by external CLIs — Codex, Grok, or both in parallel ("council"). `SKILL.md` in this repo is the source of truth; users install it by copy or symlink into `~/.claude/skills/plan-check/` (see README). If it was installed by copy on this machine, re-sync the installed copy after editing here.

## Invariants
- Reviewers are independent: identical round-1 prompts, no reviewer ever sees another's output except a Claude-authored relay in rounds 2+ on a direct contradiction (escalation only). All feedback flows back to Claude, which mediates.
- Plan content travels inside the prompt — reviewers must work without repo access.
- Reviewers run read-only (`codex -s read-only`, `grok --sandbox read-only`); the skill never edits plan files.

## Open decisions / roadmap
- Possible rename of repo + skill (multi-provider name); deliberately deferred.
- Remote reviewer endpoints over tailnet/ssh: feasibility established (per-provider runner indirection; remote host needs one-time interactive CLI login; sessions are per-host so a review's rounds must stick to one endpoint). Not built.
