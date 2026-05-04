# claude-in-codex

A Claude Code skill for getting a second opinion on plans from Codex. Claude reads your plan, sends it to Codex for review, then mediates the feedback — agreeing, pushing back, or negotiating across multiple rounds — instead of blindly passing the output through.

## What it does

When you've written a plan (design doc, spec, architecture note) and want another set of eyes on it, this skill runs Codex against the plan and has Claude critically evaluate the response. You get a consolidated `Agree / Partially agree / Disagree` summary per round, with Claude using its conversation context to filter signal from noise.

Default is 2 rounds. Each subsequent round narrows the discussion — settled points drop out, remaining concerns get sharper.

## Requirements

- [Claude Code](https://claude.com/claude-code)
- [Codex CLI](https://github.com/openai/codex) installed and authenticated, with `codex` on `PATH`

The skill shells out to `codex exec` and `codex exec resume --last`, so anything that breaks those will break the skill.

## Install

Copy `SKILL.md` into your Claude Code skills directory:

```bash
mkdir -p ~/.claude/skills/plan-check
curl -fsSL https://raw.githubusercontent.com/ytubecoder/claude-in-codex/main/SKILL.md \
  -o ~/.claude/skills/plan-check/SKILL.md
```

Or clone and symlink:

```bash
git clone https://github.com/ytubecoder/claude-in-codex.git
mkdir -p ~/.claude/skills/plan-check
ln -s "$(pwd)/claude-in-codex/SKILL.md" ~/.claude/skills/plan-check/SKILL.md
```

Restart Claude Code (or start a new session) to pick up the skill.

## Usage

Trigger phrases:

- "get codex to check"
- "lets review with codex"
- "send to codex"
- "codex review"
- "second opinion on this plan"

Or invoke directly:

| Invocation | Behavior |
|---|---|
| `/plan-check` | Auto-detects plan files in the project |
| `/plan-check path/to/plan.md` | Reviews a specific file |
| `/plan-check 3` | Runs 3 rounds instead of the default 2 |

## How it works

1. Claude finds the plan file(s) — either explicit paths, the file just produced in conversation, or candidates like `plan.md`, `*design*.md`, `*spec*.md`.
2. Codex reviews for missing requirements, technical risks, sequencing, dependencies, and ambiguities, flagging severity (critical / warning / note).
3. Claude evaluates each finding against conversation context and presents a unified summary, taking a position on every point.
4. Subsequent rounds resume the Codex session and focus on unresolved items.
5. Final summary lists agreed changes, unresolved disagreements (user decides), and a verdict.

The skill never edits plan files automatically. It hands you findings and a recommendation; you make the calls.

## License

MIT
