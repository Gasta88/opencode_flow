---
description: Implement a spec and loop until the Definition of Done is fully satisfied, or the turn budget is exhausted.
argument-hint: <ISSUE_KEY> [--max-passes N]
agent: build
model: opencode/qwen3.5-plus
---

# Implement Loop: $ARGUMENTS

Loop governor. Do not write code yourself. Alternate `@spec-implementer` and `@dod-evaluator` until DoD is met or the pass budget is exhausted.

## Step 1 — Parse arguments

**ISSUE_KEY**: first token. **MAX_PASSES**: integer after `--max-passes`, default `3`.

## Step 2 — Locate the spec

Require `specs/issue-ISSUE_KEY-spec.md` and `specs/issue-ISSUE_KEY-progress.md`. Missing → stop:
```
❌ Spec not found for ISSUE_KEY. Run /analyze-issue first.
```

## Step 2.1 — Reject quick-mode specs

If `progress.md` contains `MODE: quick`, stop:
`❌ ISSUE_KEY is a quick-mode spec. Use /implement-spec instead — quick specs skip iterative DoD evaluation.`

## Step 2.2 — Verify phase completion

Every `- [ ]`/`- [x]` line under `## Phases` must be `[x]`. Else stop:
```
❌ Spec for ISSUE_KEY is incomplete. Re-run /analyze-issue.
Unfinished phases: <list>
```

## Step 2.3 — Human review gate

Require a `## Human Review` section with `- [x] Approved by user on <date>`. Else stop:
```
❌ Spec for ISSUE_KEY has not been human-reviewed.
   Run /review-spec ISSUE_KEY first.
```

## Step 2.5 — Fetch external documentation

Invoke `@external-scout`:
> Fetch external dependency docs for issue **ISSUE_KEY**.
> Spec: `specs/issue-ISSUE_KEY-spec.md`

`NO_EXTERNAL_DEPS` → Step 3. extdocs is fetched once before the loop and reused across passes.

## Step 3 — Loop

PASS_NUMBER = 1, VERDICT = "FAIL". Repeat until VERDICT == "PASS" or PASS_NUMBER > MAX_PASSES.

### 3a — Implement pass

Pass 1:
> Implement issue **ISSUE_KEY** from `specs/issue-ISSUE_KEY-spec.md`. Track progress. Follow the skill exactly.

Later passes:
> Resume **ISSUE_KEY** from `specs/issue-ISSUE_KEY-spec.md`. Previous DoD failures: <FAIL_REASON>. Address only failing items. Track progress.

### 3b — Evaluate

Invoke `@dod-evaluator`:
> Evaluate the Definition of Done for issue **ISSUE_KEY**.
> Spec: `specs/issue-ISSUE_KEY-spec.md`
> Progress: `specs/issue-ISSUE_KEY-progress.md`

Capture the full response as EVALUATOR_OUTPUT. VERDICT = "PASS" if it starts with "PASS", else "FAIL"; on FAIL capture the failure lines as FAIL_REASON.

### 3c — Log pass result

`mem_update` with `topic_key: "loop/ISSUE_KEY/passes"`, `title: "Loop Pass PASS_NUMBER — <PASS or FAIL> for ISSUE_KEY"`, `type: manual`, `scope: project`, content What/Why/Where/Learned (Learned = EVALUATOR_OUTPUT failure details if FAIL).

If Engram is unavailable, append to `progress.md`:
```markdown
## Loop Pass PASS_NUMBER — <PASS or FAIL>
Evaluator output:
<EVALUATOR_OUTPUT>
```

Increment PASS_NUMBER.

## Step 4 — Report

PASS:
```
✅ Implementation complete for ISSUE_KEY (pass PASS_NUMBER-1 / MAX_PASSES).
   All DoD items satisfied.
   See specs/issue-ISSUE_KEY-progress.md for the full trail.
```

FAIL after the budget:
```
⚠️  ISSUE_KEY hit the pass budget (MAX_PASSES passes) without satisfying all DoD items.
Remaining failures:
<FAIL_REASON>
Inspect specs/issue-ISSUE_KEY-progress.md and resolve manually or re-run with --max-passes N.
```
