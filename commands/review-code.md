---
description: Run a 3-agent adversarial code review on the current git diff vs main
agent: build
model: opencode/qwen3.5-plus
---

# Adversarial Code Review

## Step 1 — Collect the diff

Run:
```bash
git diff $(git merge-base HEAD main)..HEAD
```
and:
```bash
git log $(git merge-base HEAD main)..HEAD --oneline
```

If the diff is empty, stop and print:
```
✅ No changes detected vs main. Nothing to review.
```

## Step 2 — Guard against trivial diffs

Count the changed lines (additions + deletions, ignoring file headers).
If fewer than 5 lines changed, print:
```
ℹ️  Diff is trivial (<5 lines). Skipping adversarial review.
```
and stop.

## Step 3 — Run the adversarial reviewer

Invoke `@code-reviewer` with this exact prompt:

> Review the following git diff.
>
> ---DIFF START---
> <full diff output from Step 1>
> ---DIFF END---
>
> Recent commits for context:
> <git log --oneline output from Step 1>

Capture the full response as REVIEWER_OUTPUT.

## Step 4 — Run the meta-reviewer

Invoke `@code-review-filter` with this exact prompt:

> Filter the following code review output.
>
> ---REVIEWER OUTPUT START---
> <REVIEWER_OUTPUT from Step 3>
> ---REVIEWER OUTPUT END---
>
> Original diff for reference:
> ---DIFF START---
> <full diff output from Step 1>
> ---DIFF END---

Capture the full response as FINAL_OUTPUT.

## Step 5 — Print results

Print FINAL_OUTPUT verbatim. Do not add commentary, summaries, or follow-up
suggestions after it.
