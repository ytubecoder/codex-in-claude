# Black-Box Acceptance — farm out labor, accept on evidence, never read the diff 1:1

Farming implementation out to a peon only saves the foreman's tokens if
acceptance doesn't cost them back. A line-by-line diff review of a large
returned change can cost as much as writing the code — and it's the weakest
gate anyway: plausible-looking code reads fine and still lies. This method
moves trust off the returned code and onto evidence the peon cannot fake.

Field-proven 2026-08-02: a ~1,500-line, 11-file feature (spec, dispatch, one
acceptance pass, zero pokes, merged) with the foreman never reading the
implementation diff. Roughly 70% of the implementation-phase tokens saved vs
coding it inline.

## When to use it

Use black-box acceptance when ALL of these hold:

- The task is big enough that a spec is cheaper than the implementation
  (multi-file features, migrations, test backfills — not one-line fixes).
- The repo has a runnable, deterministic verify command (test suite + linter).
- You can enumerate the files the peon may touch (an allowlist).

Otherwise use the classic flow: `peon report` + full `peon diff`, judged like
a code review. Small chores are cheaper to read than to spec. For the middle
ground — too big to read 1:1, too small to spec — see the **Spot review**
variant at the bottom. **Every merge gets one of the treatments — never none.**

## The method

### 1. Spec first — all judgment happens before dispatch

Write a self-contained spec document (the peon has no conversation context)
and commit it before dispatch (peons branch from the last commit). It must
carry:

- **Product requirements** and **every design decision pre-made** — names,
  enums, precedence rules, error types, which existing seams to reuse.
  Ambiguity is what forces revision rounds; remove it here.
- **Verified seams**: file:line anchors plus a quoted line of context, so the
  peon lands edits where you mean (and drift is survivable).
- **Mandated tests** — names *and assertions*, spelled out. This is the
  load-bearing trick: it makes coverage auditable later by reading the test
  file alone, never the implementation.
- **Hard constraints**: the file allowlist, the verify command, forbidden
  actions (no schema changes, no writes outside the worktree, which suites
  must never run), evidence requirements for PEON_REPORT.md.
- **A Definition of Done** the peon can self-check.

### 2. Dispatch with the contract recorded

```
peon dispatch <provider> "Implement <spec path> exactly. Self-verify per its
  Definition of Done and paste evidence into PEON_REPORT.md." \
  --repo <repo> \
  --allow "src/*.py,tests/test_foo*.py,docs/spec.md" \
  --verify "python3 -m pytest tests/test_tdd_*.py -q"
```

`--allow` and `--verify` are stored in the peon's metadata. They aren't just
notes — `peon check` executes them and `peon merge` enforces them.
(Glob note: `*` crosses `/`, so `tests/*` covers nested paths.)

While the peon works, **pre-author your independent probes** (step 5) — the
waiting time is free.

### 3. Mechanical gates: `peon check <slug>`

One command runs everything deterministic, foreman-side:

- **Contract** — commits exist, PEON_REPORT.md committed, clean tree.
- **Scope** — every touched file matches the allowlist. Out-of-scope files
  are listed and fail the check.
- **Verify** — the recorded command runs in the worktree *from the foreman's
  process*. The peon's pasted test output is advisory only; this run is the
  gate. The result is recorded against the branch tip SHA, so a later poke
  invalidates it automatically.

### 4. Test audit — the only code you read

`peon diff <slug> --files` for the touched-file list (never the bare
`peon diff`, which prints the full diff). Then read ONLY the test files and
check them against the spec's mandated list: every mandated case present,
really asserting (not stubbed), no tautologies, no test-gaming (hardcoded
expected outputs, sleeps, monkeypatched harness).

### 5. Independent probes — behavior the peon never saw

Run 2–3 small scripts you authored yourself against the public API in the
worktree: a fixture probe (end-to-end behavior on synthetic data), an
integration surface probe (catalogs/registries expose the new thing), a
negative probe (containment, refusals, error paths). A
plausible-but-wrong implementation passes its own tests; it does not pass
probes it never knew existed.

### 6. Verdict

Findings → `peon poke <slug> "<specific finding>"` and re-run from step 3
(`check` re-verifies at the new tip). Clean → `peon merge <slug>` — which
independently re-enforces scope and refuses a failed, stale, or missing
verify. `--unchecked` exists for deliberate overrides and warns loudly.

### 7. After merge

Deploy and verify the user-visible behavior live (UI changes get a real
browser pass). Black-box acceptance proves the contract; it does not replace
seeing the feature work.

## What each gate catches

| Gate | Catches |
|---|---|
| Contract (check) | Half-done work, dirty trees, missing report |
| Scope (check + merge) | Scope creep, sneaky edits outside the task |
| Foreman-run verify (check + merge) | Broken builds, failing tests, "it passed for me" reports |
| Test audit (human) | Stubbed/tautological tests, missing mandated cases, test-gaming |
| Independent probes (human) | Plausible-but-wrong logic that satisfies its own tests |
| Live E2E (human, post-merge) | Integration and UX failures no unit gate sees |

What this deliberately does NOT check: internal code style and architecture
taste. That's the trade. If style review is the point of the task, use the
classic full-diff flow.

## Variants

- **Test-gated dispatch** (sibling variant): the *foreman* authors the tests,
  proves they fail red on the base ref, locks them read-only, and the peon's
  task is "make these pass". Stronger assurance, higher foreman cost. Shares
  this tooling (`--verify`, `check`, merge gates); adds path-locking.

- **Spot review** (token-lean middle tier; field-proven 3× on 2026-08-02):
  for mid-size chores where a full spec is overkill but a 1:1 diff read is
  waste. The brief makes the peon a *self-tested work unit*: "add the
  mandated tests, run them plus the full suite, paste BOTH actual outputs
  into PEON_REPORT.md" — and include the no-escape rule: if the sandbox
  blocks `git commit`, leave the tree + report as-is and say so; the foreman
  commits (`peon adopt`). Mandating self-testing improves the work product,
  but the pasted outputs are *triage, not trust*: self-reports are the
  weakest evidence class — frontier models demonstrably game their own
  checks (METR's reward-hacking findings), and an orchestrator that accepts
  "tests: pass" strings verifies protocol compliance, not truth. The gate is
  the foreman-run verify: `peon check <slug> --verify "<suite>"` (persisted
  as the contract if none was recorded at dispatch, so `merge` enforces it).
  Review = report + `peon diff --stat` + reading only the load-bearing hunks
  (interfaces, error paths, anything the suite can't see). No allowlist or
  independent probes mandated — that's the trade vs full black-box. If the
  diffstat surprises you, escalate to a stronger treatment.
