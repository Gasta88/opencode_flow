---
description: Implement code changes from an existing spec file
argument-hint: <ISSUE_KEY>
agent: build
model: opencode/qwen3.5-plus
---

# Implement Spec: $ARGUMENTS

You are dispatching an implementation task. Do not write code yourself —
delegate to `@spec-implementer`.

## Step 1 — Locate the spec

`$ARGUMENTS` is the issue key (e.g. `FEAT-123`).

Verify these files exist:
- `specs/issue-$ARGUMENTS-spec.md`
- `specs/issue-$ARGUMENTS-progress.md`

If either is missing, stop and print:
```
❌ Spec not found for $ARGUMENTS. Run /analyze-issue first.
```

## Step 2 — Sanity-check the spec is complete

Read `specs/issue-$ARGUMENTS-progress.md`. Every phase checkbox must be ticked.
If any phase is unchecked, stop and print:
```
❌ Spec for $ARGUMENTS is incomplete. Re-run /analyze-issue.
Unfinished phases: <list>
```

## Step 3 — Delegate

Invoke `@spec-implementer` with this exact task:

> Implement issue **$ARGUMENTS** from `specs/issue-$ARGUMENTS-spec.md`.
> Track progress in `specs/issue-$ARGUMENTS-progress.md`.
> Follow the spec-driven-workflow skill exactly.
> The spec is the single source of truth — re-read the relevant section before
> every file edit.

## Step 4 — Report

After the subagent completes, print a one-line summary of the Definition-of-Done state:
```
✅ Implementation complete for $ARGUMENTS.
   See specs/issue-$ARGUMENTS-progress.md for the trail.
```
