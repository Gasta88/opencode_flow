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

Read `specs/issue-ISSUE_KEY-progress.md`. Every phase checkbox (Phases 1–6)
must be ticked. If any phase is unchecked, stop and print:
```
❌ Spec for ISSUE_KEY is incomplete. Re-run /analyze-issue.
Unfinished phases: <list>
```

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
