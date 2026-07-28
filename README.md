# codex-in-claude

A Claude Code skill for getting a second opinion on plans from Codex, Grok, or both. Claude reads your plan, sends it to an external reviewer for review, then mediates the feedback — agreeing, pushing back, or negotiating across multiple rounds — instead of blindly passing the output through.

## What it does

When you've written a plan (design doc, spec, architecture note) and want another set of eyes on it, this skill runs Codex and/or Grok against the plan and has Claude critically evaluate the response. You get a consolidated `Agree / Partially agree / Disagree` summary per round, with Claude using its conversation context to filter signal from noise.

Default is 2 rounds. Each subsequent round narrows the discussion — settled points drop out, remaining concerns get sharper.

**Council mode** sends the identical prompt to all reviewers in parallel and merges their findings with attribution (*Both* / *Codex only* / *Grok only*). Reviewers never see each other's round-1 output — independent takes are the point; consensus findings gain confidence, unique findings get extra scrutiny. When reviewers directly contradict each other, Claude can relay one's argument into the other's next round and let each respond in its own session.

## Requirements

- [Claude Code](https://claude.com/claude-code)
- At least one reviewer CLI, installed, authenticated, and on `PATH`:
  - [Codex CLI](https://github.com/openai/codex) (`codex`)
  - [Grok Build CLI](https://docs.x.ai/) (`grok`)

The skill shells out to `codex exec` / `codex exec resume --last` and `grok --single` / `grok --resume`, so anything that breaks those will break the skill.

## Install

Copy `SKILL.md` into your Claude Code skills directory:

```bash
mkdir -p ~/.claude/skills/plan-check
curl -fsSL https://raw.githubusercontent.com/ytubecoder/codex-in-claude/main/SKILL.md \
  -o ~/.claude/skills/plan-check/SKILL.md
```

Or clone and symlink:

```bash
git clone https://github.com/ytubecoder/codex-in-claude.git
mkdir -p ~/.claude/skills/plan-check
ln -s "$(pwd)/codex-in-claude/SKILL.md" ~/.claude/skills/plan-check/SKILL.md
```

Restart Claude Code (or start a new session) to pick up the skill.

## Usage

Trigger phrases:

- "get codex to check" / "get grok to check"
- "lets review with codex" / "lets review with grok"
- "send to codex" / "send to grok"
- "codex review" / "grok review"
- "second opinion on this plan"
- "ask both" / "council review" / "third opinion"

Or invoke directly:

| Invocation | Behavior |
|---|---|
| `/plan-check` | Auto-detects plan files, reviews with Codex |
| `/plan-check grok` | Reviews with Grok |
| `/plan-check council` | Reviews with all reviewers in parallel |
| `/plan-check path/to/plan.md` | Reviews a specific file |
| `/plan-check 3` | Runs 3 rounds instead of the default 2 |

Modifiers combine: `/plan-check council 3 docs/plan.md`.

## How it works

1. Claude finds the plan file(s) — either explicit paths, the file just produced in conversation, or candidates like `plan.md`, `*design*.md`, `*spec*.md`.
2. The reviewer(s) review for missing requirements, technical risks, sequencing, dependencies, and ambiguities, flagging severity (critical / warning / note). Council mode runs reviewers concurrently — wall time is the slowest reviewer, not the sum.
3. Claude evaluates each finding against conversation context and presents a unified summary, taking a position on every point. Council findings are deduped and attributed per reviewer first.
4. Subsequent rounds resume each reviewer's own session and focus on unresolved items.
5. Final summary lists agreed changes, unresolved disagreements (user decides), and a verdict.

The skill never edits plan files automatically. It hands you findings and a recommendation; you make the calls.

## License

MIT
