---
description: Run a 3-agent adversarial code review on the current git diff vs main, with a bounded fix loop
argument-hint: [--max-fix-passes N]
agent: build
model: opencode/qwen3.5-plus
---

# Adversarial Code Review

## Step 0 — Parse arguments

Extract **MAX_FIX_PASSES**: the integer after `--max-fix-passes` if present in `$ARGUMENTS`, else `3`.

## Step 1 — Collect the diff

Run:
```bash
BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo main)
[ -z "$BASE_BRANCH" ] && BASE_BRANCH=main
FULL_DIFF="$(git diff $(git merge-base HEAD $BASE_BRANCH)..HEAD 2>/dev/null || true)
$(git diff --cached HEAD 2>/dev/null || true)
$(git diff HEAD 2>/dev/null || true)"
```
and:
```bash
git log $(git merge-base HEAD $BASE_BRANCH)..HEAD --oneline
```

If `FULL_DIFF` is empty, stop and print: `✅ No changes detected vs $BASE_BRANCH. Nothing to review.`

## Step 2 — Guard against trivial diffs

Count the changed lines (additions + deletions, ignoring file headers) from `FULL_DIFF`.
If fewer than 5 lines changed, print:
```
ℹ️  Diff is trivial (<5 lines). Skipping adversarial review.
```
and stop.

## Step 3 — Run the adversarial reviewer

Invoke `@code-reviewer` with:
> Review the following git diff.
> ---DIFF START--- <FULL_DIFF> ---DIFF END---
> Recent commits: <git log --oneline>
Capture as REVIEWER_OUTPUT.

## Step 4 — Run the meta-reviewer

Invoke `@code-review-filter` with:
> Filter this review output against the original diff.
> ---REVIEWER OUTPUT START--- <REVIEWER_OUTPUT> ---REVIEWER OUTPUT END---
> ---DIFF START--- <FULL_DIFF> ---DIFF END---
Capture as FINAL_OUTPUT.

## Step 5 — Fix loop

If FINAL_OUTPUT contains `0 issues flagged`, print FINAL_OUTPUT verbatim and stop.

Otherwise, initialize FIX_PASS = 1, ISSUES_REMAIN = true.

Repeat while ISSUES_REMAIN and FIX_PASS <= MAX_FIX_PASSES:

### 5a — Apply fixes

Invoke `@code-fixer` with:

> Apply the following review findings.
> Findings:
> FINAL_OUTPUT

Capture the response as FIXER_OUTPUT.

### 5b — Re-collect the diff

Run the same git diff commands from Step 1 to produce a new FULL_DIFF.

### 5c — Re-review

Invoke `@code-reviewer` with the new diff (same prompt shape as Step 3).
Capture as REVIEWER_OUTPUT.

Invoke `@code-review-filter` with REVIEWER_OUTPUT and the new diff (same
prompt shape as Step 4). Capture as FINAL_OUTPUT.

### 5d — Check for remaining issues

If FINAL_OUTPUT contains `0 issues flagged`, set ISSUES_REMAIN = false.

Increment FIX_PASS.

### 5e — Exit or report

If ISSUES_REMAIN == false, print:
```
✅ Code review clean after FIX_PASS-1 fix pass(es).
```
and print FINAL_OUTPUT verbatim.

If ISSUES_REMAIN == true after MAX_FIX_PASSES passes, print:
```
⚠️  Issues remain after MAX_FIX_PASSES fix passes.
```
and print FINAL_OUTPUT verbatim. Print the FIXER_OUTPUT summary so the user
can see which findings were applied and which were not.
