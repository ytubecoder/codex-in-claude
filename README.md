# codex-in-claude

Two Claude Code skills that put external CLI agents (Codex, Grok) to work for Claude:

- **plan-check** — pull *opinions* in: second-opinion plan review, with Claude mediating feedback across rounds (solo reviewer or parallel "council").
- **peon-poke** — push *labor* out: farm implementation chores to a "peon" working in an isolated git worktree; Claude reviews the diff and merges or sends it back.

## plan-check

When you've written a plan (design doc, spec, architecture note) and want another set of eyes on it, this skill runs Codex and/or Grok against the plan and has Claude critically evaluate the response. You get a consolidated `Agree / Partially agree / Disagree` summary per round, with Claude using its conversation context to filter signal from noise.

Default is 2 rounds. **Council mode** sends the identical prompt to all reviewers in parallel and merges their findings with attribution (*Both* / *Codex only* / *Grok only*). Reviewers never see each other's round-1 output — independent takes are the point.

| Invocation | Behavior |
|---|---|
| `/plan-check` | Auto-detects plan files, reviews with Codex |
| `/plan-check grok` | Reviews with Grok |
| `/plan-check council` | Reviews with all reviewers in parallel |
| `/plan-check path/to/plan.md` | Reviews a specific file |
| `/plan-check 3` | Runs 3 rounds instead of the default 2 |

## peon-poke

Give Claude an implementation chore to delegate ("have codex build the pagination", "farm the test backfill out to grok") and it dispatches a peon: an isolated git worktree on a `peon/<slug>` branch where the provider CLI works with write access, commits its changes, and files a `PEON_REPORT.md`. The harness enforces that contract — a peon that commits nothing, skips its report, or leaves a dirty tree fails loudly with the worktree preserved for inspection. Claude reviews the report and diff like a code review, iterates via `peon poke <slug> "<feedback>"` (same provider session, context intact), and only an explicit `peon merge` lands anything on your branch. `peon scrap` discards.

The mechanics live in `bin/peon` — a dependency-light shell script (git + python3 + uuidgen) any orchestrator can call, not just Claude:

```
peon dispatch <codex|grok> "<task>" [--repo DIR] [--base REF] [--slug NAME] [--force]
peon list | report <slug> | diff <slug>
peon poke <slug> "<feedback>"
peon merge <slug> | scrap <slug>
```

State lives under `~/.peon/` by default (worktrees, logs, metadata), overridable via `PEON_HOME` — never inside your repo.

## Requirements

- [Claude Code](https://claude.com/claude-code)
- At least one provider CLI, installed, authenticated, and on `PATH`:
  - [Codex CLI](https://github.com/openai/codex) (`codex`)
  - [Grok Build CLI](https://docs.x.ai/) (`grok`)
- For peon-poke: `git`, `python3`, `uuidgen` (all standard on macOS/Linux)

## Install

Clone, then link the skills and the `peon` script:

```bash
git clone https://github.com/ytubecoder/codex-in-claude.git
cd codex-in-claude

mkdir -p ~/.claude/skills/plan-check ~/.claude/skills/peon-poke ~/.local/bin
ln -sf "$(pwd)/skills/plan-check/SKILL.md" ~/.claude/skills/plan-check/SKILL.md
ln -sf "$(pwd)/skills/peon-poke/SKILL.md"  ~/.claude/skills/peon-poke/SKILL.md
ln -sf "$(pwd)/bin/peon" ~/.local/bin/peon   # or any writable PATH dir
```

Or install by copy: `curl -fsSL https://raw.githubusercontent.com/ytubecoder/codex-in-claude/main/skills/plan-check/SKILL.md -o ~/.claude/skills/plan-check/SKILL.md` (same pattern for peon-poke; copy `bin/peon` somewhere on PATH). Restart Claude Code (or start a new session) to pick up the skills.

**Upgrading from the single-skill layout:** `SKILL.md` moved to `skills/plan-check/SKILL.md`. If you installed by symlinking the old root `SKILL.md`, the link is now dangling — re-run the symlink line above.

## Tests

`bash tests/peon.test.sh` — deterministic lifecycle tests using a built-in fake provider and a dry-run seam; no provider CLIs needed, no cost.

## License

MIT
