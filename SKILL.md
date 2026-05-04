---
name: plan-check
description: "Iterative plan review with Codex. Trigger phrases: 'get codex to check', 'lets review with codex', 'send to codex', 'codex review', 'second opinion on this plan'. Claude mediates — agrees, pushes back, or negotiates across multiple rounds."
user_invocable: true
---

# Plan Check — Iterative Codex Plan Check

Conversational plan review where Claude acts as mediator. Codex reviews the plan for general completeness, risks, sequencing, and feasibility. Claude synthesizes the feedback, agrees or pushes back, and iterates until the plan is solid.

## Trigger Phrases

This skill should activate when the user says things like:
- "get codex to check"
- "lets review with codex"
- "send to codex"
- "codex review"
- "have codex look at this"
- "what does codex think"
- "second opinion on this plan"

## Invocation

| Invocation | Mode |
|---|---|
| `/plan-check` | Auto-detect plan files and start review |
| `/plan-check path/to/plan.md` | Review specific file(s) |
| `/plan-check 3` | Run 3 rounds of review |
| Trigger phrase (see above) | Same as `/plan-check` |

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
- Tell the user upfront: "Sending to Codex for N rounds of review."

## Step 3: Round 1 — Codex Review

### Codex call (general review)

```bash
cat <<'PROMPT_EOF' | codex exec -s read-only -
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

PROMPT_EOF
```

Present a clearly-labeled summary of Codex's output to the user.

## Step 4: Claude Evaluates Feedback

After Codex responds, Claude does NOT just pass the output through. Claude acts as an informed mediator.

**For each finding:**

1. **Agree** — if the point is valid and the plan should change. Say so clearly: "Codex is right about X."
2. **Partially agree** — there's merit but severity or suggestion is off: "Codex flags X as critical, but Y mitigates it — downgrade to note."
3. **Push back** — reviewer is wrong, misunderstood, or over-cautious: "Codex raises X but it doesn't apply because Z."

Claude should use knowledge of the conversation, the user's goals, and the codebase to make these judgments. The user has been working with Claude — Claude knows things Codex does not.

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

## Step 5: Subsequent Rounds — Negotiate

For rounds 2+, resume Codex's session so context stays warm.

Build a follow-up prompt that:
1. Acknowledges valid points: "We agree with X and Y and have noted them for implementation."
2. Pushes back on disagreements: "Regarding Z — this doesn't apply because [reason]. The plan accounts for this via [section]."
3. Asks Codex to focus on remaining concerns.
4. States round count: "This is round N of M."

### Codex follow-up

```bash
cat <<'PROMPT_EOF' | codex exec resume --last -s read-only -
$CODEX_FOLLOW_UP_PROMPT
PROMPT_EOF
```

After each round, Claude re-synthesizes (same agree/partially/disagree structure) and presents the consolidated view.

## Step 6: Final Summary

After all rounds complete, present a consolidated summary:

```
## Plan Review Complete (N rounds — Codex)

### Agreed changes to make:
- [list of accepted feedback items]

### Unresolved disagreements:
- [items where Claude and Codex still differ — user decides]

### Plan verdict: [Ready / Needs revision]
```

If there are unresolved disagreements, ask the user to make the call on those specific items.

## Important Rules

- **Do NOT edit plan files automatically.** Present findings and let the user decide what to change.
- **Do NOT just pass through reviewer output.** Claude must evaluate every point using conversation context.
- **Stay in character as mediator.** Claude represents the user's intent and context knowledge. Codex provides an independent second opinion.
- **Be honest.** If Codex catches something Claude missed, say so. Don't defend the plan out of ego.
- **Keep rounds focused.** Each subsequent round should narrow, not rehash settled points.
