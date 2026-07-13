---
description: Implement a spec and loop until the Definition of Done is fully satisfied, or the turn budget is exhausted.
argument-hint: <ISSUE_KEY> [--max-passes N]
agent: build
model: opencode/qwen3.5-plus
---

# Implement Loop: $ARGUMENTS

You are a loop governor. Do not write code yourself.
Drive `@spec-implementer` and `@dod-evaluator` in alternation until DoD is met
or the pass budget is exhausted.

## Step 1 — Parse arguments

`$ARGUMENTS` is the issue key, optionally followed by `--max-passes N`.

Extract:
- **ISSUE_KEY**: the first token (e.g. `FEAT-123`)
- **MAX_PASSES**: the integer after `--max-passes` if present, else default to `3`

## Step 2 — Locate the spec

Verify these files exist:
- `specs/issue-ISSUE_KEY-spec.md`
- `specs/issue-ISSUE_KEY-progress.md`

If either is missing, stop and print:
```
❌ Spec not found for ISSUE_KEY. Run /analyze-issue first.
```

## Step 2.1 — Reject quick-mode specs

Read the first lines of `specs/issue-ISSUE_KEY-progress.md`. If it contains the
line `MODE: quick`, stop and print:

```
❌ ISSUE_KEY was generated with --quick. /implement-loop requires a full spec
   (Definition of Done section) to evaluate against.
   Use /implement-spec ISSUE_KEY instead — quick specs complete in one pass
   and don't need iterative DoD evaluation.
```

## Step 2.2 — Verify phase completion

Read `specs/issue-ISSUE_KEY-progress.md`. Under the `## Phases` heading, scan
all `- [ ]` / `- [x]` lines. Every checkbox must be `[x]`. If any checkbox is
`[ ]`, stop and print:
```
❌ Spec for ISSUE_KEY is incomplete. Re-run /analyze-issue.
Unfinished phases: <list>
```

## Step 2.3 — Human review gate (full-mode only)

Read `specs/issue-ISSUE_KEY-progress.md`. If it contains `MODE: quick`, skip
this step and continue to Step 2.5. (Note: quick-mode specs are already rejected
by Step 2.1, so this is a defensive check.)

Otherwise, search for a `## Human Review` section containing
`- [x] Approved by user on <date>`. If the section is absent or the checkbox
is unchecked, stop and print:
```
❌ Spec for ISSUE_KEY has not been human-reviewed.
   Run /review-spec ISSUE_KEY to review and approve the spec before implementation.
   (Quick-mode specs are exempt from this gate.)
```

## Step 2.5 — Fetch external documentation

Invoke `@external-scout` with:

> Fetch external dependency docs for issue **ISSUE_KEY**.
> Spec: `specs/issue-ISSUE_KEY-spec.md`

If the scout returns `NO_EXTERNAL_DEPS`, skip to Step 3.
extdocs.md is fetched once before the loop begins and reused across all passes.

## Step 3 — Loop

Initialize: PASS_NUMBER = 1, VERDICT = "FAIL"

Repeat until VERDICT == "PASS" or PASS_NUMBER > MAX_PASSES:

### 3a — Implement pass

If PASS_NUMBER == 1, invoke `@spec-implementer` with:

> Implement issue **ISSUE_KEY** from `specs/issue-ISSUE_KEY-spec.md`.
> Track progress in `specs/issue-ISSUE_KEY-progress.md`.
> Follow the spec-driven-workflow skill exactly.
> The spec is the single source of truth — re-read the relevant section before every file edit.

If PASS_NUMBER > 1, you have a FAIL reason from the previous evaluation.
Invoke `@spec-implementer` with:

> Resume implementation of **ISSUE_KEY** from `specs/issue-ISSUE_KEY-spec.md`.
> The previous pass failed the DoD evaluation. Unsatisfied items:
> <FAIL_REASON from previous evaluator output>
> Address only the failing items. Do not re-implement what is already passing.
> Track all changes in `specs/issue-ISSUE_KEY-progress.md`.

### 3b — Evaluate

Invoke `@dod-evaluator` with:

> Evaluate the Definition of Done for issue **ISSUE_KEY**.
> Spec: `specs/issue-ISSUE_KEY-spec.md`
> Progress: `specs/issue-ISSUE_KEY-progress.md`

Capture the full response as EVALUATOR_OUTPUT.
Set VERDICT = "PASS" if output starts with "PASS", else "FAIL".
If VERDICT == "FAIL", capture the failure lines as FAIL_REASON.

### 3c — Log pass result

Append to `specs/issue-ISSUE_KEY-progress.md`:

```markdown
## Loop Pass PASS_NUMBER — <PASS or FAIL>
Evaluator output:
<EVALUATOR_OUTPUT>
```

Increment PASS_NUMBER.

## Step 4 — Report

If VERDICT == "PASS":
```
✅ Implementation complete for ISSUE_KEY (pass PASS_NUMBER-1 / MAX_PASSES).
   All DoD items satisfied.
   See specs/issue-ISSUE_KEY-progress.md for the full trail.
```

If VERDICT == "FAIL" after exhausting MAX_PASSES:
```
⚠️  ISSUE_KEY hit the pass budget (MAX_PASSES passes) without satisfying all DoD items.
Remaining failures:
<FAIL_REASON>
Inspect specs/issue-ISSUE_KEY-progress.md and resolve manually or re-run with --max-passes N.
```
