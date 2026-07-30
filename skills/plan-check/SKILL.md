---
name: plan-check
description: "Iterative plan review with Codex, Grok, Gemini/Antigravity, or all (council). Trigger phrases: 'get codex to check', 'codex review', 'grok review', 'gemini review', 'agy review', 'what does grok/gemini think', 'ask both', 'ask all three', 'council review', 'second opinion on this plan'. Claude mediates — agrees, pushes back, or negotiates across multiple rounds."
user_invocable: true
---

# Plan Check — Iterative Plan Review (Codex / Grok / Gemini / Council)

Conversational plan review where Claude acts as mediator. An external reviewer (Codex, Grok, Gemini, or several in parallel) reviews the plan for general completeness, risks, sequencing, and feasibility. Claude synthesizes the feedback, agrees or pushes back, and iterates until the plan is solid.

## Reviewers

| Reviewer | CLI | Selected when the user says |
|---|---|---|
| **Codex** (default) | `codex` | "codex review", "send to codex", nothing provider-specific |
| **Grok** | `grok` | "grok review", "send to grok", "what does grok think" |
| **Gemini** (enterprise/API-key only) | `gemini` | "gemini review" — but see the routing note below |
| **Antigravity** (Gemini models via Google AI Pro/Ultra) | `agy` | "agy review", "antigravity review", and usually "gemini review" too |
| **Council** (all in parallel) | all installed | "ask both", "ask all three", "council review", "all reviewers" |

**Gemini routing note:** Google cut `gemini` (gemini-cli) off from consumer accounts — free, AI Pro, and Ultra — on 2026-06-18; it now only serves Gemini Code Assist Standard/Enterprise licenses and API keys. When the user says "gemini" and `agy` is installed, use Antigravity — it runs the same Gemini model family on their subscription. Only use `gemini` directly if the machine actually has a working enterprise/API-key setup. One review = one reviewer: never run both `gemini` and `agy` as separate council members (same models, no independence).

If a requested CLI is not installed (`command -v codex` / `command -v grok` / `command -v agy`), say so and offer the others. Council means every installed reviewer unless the user names a subset ("codex and agy").

## Trigger Phrases

- "get codex to check" / "get grok to check" / "get gemini to check"
- "lets review with codex" / "lets review with grok" / "lets review with gemini"
- "send to codex" / "send to grok" / "send to gemini"
- "codex review" / "grok review" / "gemini review"
- "have codex look at this" / "what does grok think" / "what does gemini think"
- "second opinion on this plan"
- "ask both" / "ask all three" / "council review" / "third opinion"

## Invocation

| Invocation | Mode |
|---|---|
| `/plan-check` | Auto-detect plan files, review with Codex |
| `/plan-check grok` | Review with Grok |
| `/plan-check gemini` | Review with Gemini models (via `agy` on consumer subscriptions — see routing note) |
| `/plan-check agy` | Review with Antigravity |
| `/plan-check council` | Review with all reviewers in parallel |
| `/plan-check path/to/plan.md` | Review specific file(s) |
| `/plan-check 3` | Run 3 rounds of review |
| Trigger phrase (see above) | Same, reviewer per the table |

Modifiers combine: `/plan-check council 3 docs/plan.md`.

---

## Step 1: Identify Plan Files

Figure out which files to send. In order of priority:

1. If the user specified paths, use those.
2. If a plan was just produced in this conversation (written to a file), use that file.
3. Search for plan files in the current project:
   - `plan.md`, `PLAN.md`, `*plan*.md`, `*design*.md`, `*spec*.md`, `*architecture*.md`
   - `.md` files in `plans/` or `docs/` directories
4. If multiple candidates, ask which ones.
5. If none found, tell the user to write the plan to a file first.

Read the plan files so you (Claude) have the full content in context.

## Step 2: Determine Rounds

- If the user specified a number (e.g. `/plan-check 3` or "do 3 rounds"), use that.
- If not specified, default to **2 rounds**.
- Tell the user upfront: "Sending to [reviewer(s)] for N rounds of review."

## Step 3: Round 1 — Reviewer(s) Review

### The review prompt (same for every reviewer)

```
Review the following plan files for completeness, risks, and feasibility.

For each file, assess:
- Missing requirements or edge cases
- Technical risks or blockers
- Dependencies that aren't accounted for
- Sequencing issues
- Performance or operational concerns
- Anything ambiguous or underspecified

Be specific — reference sections by name.
Flag severity: critical (blocks implementation), warning (likely problem), or note (suggestion).

Plan files:

$PLAN_CONTENTS
```

### Codex call

```bash
cat <<'PROMPT_EOF' | codex exec -s read-only -
$REVIEW_PROMPT
PROMPT_EOF
```

If the working directory is not a git repository, add `--skip-git-repo-check`.

### Grok call

```bash
GROK_SESSION=$(uuidgen | tr 'A-Z' 'a-z')
PROMPT_FILE=$(mktemp -t plan-check)
cat > "$PROMPT_FILE" <<'PROMPT_EOF'
$REVIEW_PROMPT
PROMPT_EOF
grok -s "$GROK_SESSION" --sandbox read-only --prompt-file "$PROMPT_FILE"
```

Keep `$GROK_SESSION` for the whole review — rounds 2+ resume it.

### Gemini call

```bash
GEMINI_DIR=$(mktemp -d -t plan-check-gemini)
cat > "$PROMPT_FILE" <<'PROMPT_EOF'
$REVIEW_PROMPT
PROMPT_EOF
( cd "$GEMINI_DIR" && gemini --approval-mode plan -p "$(cat "$PROMPT_FILE")" )
```

`--approval-mode plan` is Gemini's read-only mode. Gemini stores sessions per-directory and resumes by recency, not by id — the dedicated `$GEMINI_DIR` guarantees `--resume latest` in rounds 2+ refers to this review and not some other gemini session. Keep `$GEMINI_DIR` for the whole review.

### Antigravity call

```bash
AGY_OUT=$(agy --mode plan --output-format json --print-timeout 15m -p "$(cat "$PROMPT_FILE")")
AGY_CONV=$(printf '%s' "$AGY_OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["conversation_id"])')
printf '%s' "$AGY_OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["response"])'
```

`--mode plan` is Antigravity's read-only mode. Keep `$AGY_CONV` for the whole review — rounds 2+ resume it by id. Optionally pick a stronger model with `--model` (list with `agy models`, e.g. `gemini-3.1-pro-high`).

### Council: run reviewers in parallel

Reviewers are independent processes — launch them concurrently (background both and `wait`, or parallel tool calls). Wall time is the slowest reviewer, not the sum. Send each reviewer the **identical** review prompt. Never include one reviewer's output in another's round-1 prompt — independent takes are the whole point.

```bash
{ cat <<'PROMPT_EOF' | codex exec -s read-only - > "$WORKDIR/codex-review.md" 2>&1
$REVIEW_PROMPT
PROMPT_EOF
} &
grok -s "$GROK_SESSION" --sandbox read-only --prompt-file "$PROMPT_FILE" > "$WORKDIR/grok-review.md" 2>&1 &
agy --mode plan --output-format json --print-timeout 15m -p "$(cat "$PROMPT_FILE")" > "$WORKDIR/agy-review.json" 2>&1 &
wait
```

Present a clearly-labeled summary of each reviewer's output to the user.

## Step 4: Claude Evaluates Feedback

After the reviewer responds, Claude does NOT just pass the output through. Claude acts as an informed mediator.

**For each finding:**

1. **Agree** — if the point is valid and the plan should change. Say so clearly: "Codex is right about X."
2. **Partially agree** — there's merit but severity or suggestion is off: "Grok flags X as critical, but Y mitigates it — downgrade to note."
3. **Push back** — reviewer is wrong, misunderstood, or over-cautious: "Codex raises X but it doesn't apply because Z."

Claude should use knowledge of the conversation, the user's goals, and the codebase to make these judgments. The user has been working with Claude — Claude knows things the reviewers do not.

Present a unified summary:
```
## Round 1 — Consolidated Feedback

### Agree (will address)
- [finding] — [why Claude agrees]

### Partially agree (discuss)
- [finding] — [Claude's nuanced take]

### Disagree (pushing back)
- [finding] — [why Claude disagrees]
```

**Council merge:** dedupe findings across reviewers first, attributing each — *All*, *Codex+Gemini*, *Grok only*, etc. Consensus findings carry extra weight; single-reviewer findings get extra scrutiny (they are often the most valuable catches, but also where hallucinated concerns live). Then apply the same agree / partially / disagree triage to the merged list, one consolidated summary — not one summary per reviewer.

## Step 5: Subsequent Rounds — Negotiate

For rounds 2+, resume each reviewer's session so context stays warm.

Build a follow-up prompt that:
1. Acknowledges valid points: "We agree with X and Y and have noted them for implementation."
2. Pushes back on disagreements: "Regarding Z — this doesn't apply because [reason]. The plan accounts for this via [section]."
3. Asks the reviewer to focus on remaining concerns.
4. States round count: "This is round N of M."

### Codex follow-up

```bash
cat <<'PROMPT_EOF' | codex exec resume --last -c sandbox_mode="read-only" -
$FOLLOW_UP_PROMPT
PROMPT_EOF
```

(`codex exec resume` accepts no `-s`/`--sandbox` flag — the sandbox must be set via the `-c sandbox_mode=...` config override.)

### Grok follow-up

```bash
cat > "$PROMPT_FILE" <<'PROMPT_EOF'
$FOLLOW_UP_PROMPT
PROMPT_EOF
grok --resume "$GROK_SESSION" --sandbox read-only --prompt-file "$PROMPT_FILE"
```

If `$GROK_SESSION` was lost (fresh shell), fall back to `grok --continue`, which resumes the most recent session for the current directory.

### Gemini follow-up

```bash
cat > "$PROMPT_FILE" <<'PROMPT_EOF'
$FOLLOW_UP_PROMPT
PROMPT_EOF
( cd "$GEMINI_DIR" && gemini --resume latest --approval-mode plan -p "$(cat "$PROMPT_FILE")" )
```

If `$GEMINI_DIR` was lost (fresh shell), there is no reliable resume — start a fresh session in a new temp dir and restate the agreed/contested items in the prompt.

### Antigravity follow-up

```bash
agy --conversation "$AGY_CONV" --mode plan --output-format json --print-timeout 15m -p "$(cat "$PROMPT_FILE")"
```

Extract `response` from the JSON as in round 1. The conversation id is stable across rounds.

**Council cross-examination (escalation only):** reviewers never talk to each other directly. But when they directly contradict each other on a specific point, Claude may relay the substance of one reviewer's argument into the other's follow-up prompt ("another reviewer argues X because Y — does that change your position?") and let each respond in its own session. Use this only for genuine conflicts, not for consensus items.

After each round, Claude re-synthesizes (same agree/partially/disagree structure) and presents the consolidated view.

## Step 6: Final Summary

After all rounds complete, present a consolidated summary:

```
## Plan Review Complete (N rounds — [reviewer(s)])

### Agreed changes to make:
- [list of accepted feedback items]

### Unresolved disagreements:
- [items where Claude and reviewer(s) still differ — user decides; note who holds which position]

### Plan verdict: [Ready / Needs revision]
```

If there are unresolved disagreements, ask the user to make the call on those specific items.

## Important Rules

- **Do NOT edit plan files automatically.** Present findings and let the user decide what to change.
- **Do NOT just pass through reviewer output.** Claude must evaluate every point using conversation context.
- **Stay in character as mediator.** Claude represents the user's intent and context knowledge. The reviewers provide independent outside opinions.
- **Keep reviewers independent.** Identical round-1 prompts, no cross-contamination; cross-examination only as escalation on direct conflicts.
- **Be honest.** If a reviewer catches something Claude missed, say so. Don't defend the plan out of ego.
- **Keep rounds focused.** Each subsequent round should narrow, not rehash settled points.
