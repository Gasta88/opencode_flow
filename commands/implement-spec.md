---
description: Implement code changes from an existing spec file, working the Implementation Plan as a task graph with optional parallel frontier dispatch
argument-hint: <ISSUE_KEY> [--max-parallel N]
agent: build
model: opencode/qwen3.5-plus
---

# Implement Spec: $ARGUMENTS

You are dispatching an implementation task. Do not write code yourself —
delegate to `@spec-implementer`.

## Step 0 — Parse arguments

`$ARGUMENTS` contains the issue key (e.g. `FEAT-123`), optionally followed by
`--max-parallel N`.

Extract:
- **ISSUE_KEY**: the first token.
- **MAX_PARALLEL**: the integer after `--max-parallel` if present, else `2`.
  `1` means strictly sequential (one implementer at a time, sub-tasks in
  `Depends On` order).

## Step 1 — Locate the spec

Verify these files exist:
- `specs/issue-ISSUE_KEY-spec.md`
- `specs/issue-ISSUE_KEY-progress.md`

If either is missing, stop and print:
```
❌ Spec not found for ISSUE_KEY. Run /analyze-issue first.
```

## Step 2 — Sanity-check the spec is complete

Read `specs/issue-ISSUE_KEY-progress.md`. Under the `## Phases` heading, scan
all `- [ ]` / `- [x]` lines. Every checkbox must be `[x]`. If any checkbox is
`[ ]`, stop and print:
```
❌ Spec for ISSUE_KEY is incomplete. Re-run /analyze-issue.
Unfinished phases: <list>
```

## Step 2.3 — Human review gate

Read `specs/issue-ISSUE_KEY-progress.md`. If it contains `MODE: quick`, skip
this step. Otherwise, search for a `## Human Review` section containing
`- [x] Approved by user on <date>`. If absent or unchecked, stop and print:
```
❌ Spec for ISSUE_KEY has not been human-reviewed.
   Run /review-spec ISSUE_KEY first.
```

## Step 2.5 — Fetch external documentation

Invoke `@external-scout` with:

> Fetch external dependency docs for issue **ISSUE_KEY**.
> Spec: `specs/issue-ISSUE_KEY-spec.md`

If the scout returns `NO_EXTERNAL_DEPS`, skip to Step 3.
Otherwise, `specs/issue-ISSUE_KEY-extdocs.md` is now written and the
implementer will read it automatically.

## Step 3 — Parse the task graph

Read the `## Implementation Plan` table in `specs/issue-ISSUE_KEY-spec.md`.
Each row is a sub-task node with:
- `#` — sub-task number
- `Depends On` — its **blocking edges** (other sub-task numbers, or `—` for none)
- `Files` — its declared file set (when the column is present)

Cross-reference `specs/issue-ISSUE_KEY-progress.md` (and Engram
`impl/ISSUE_KEY/progress` when available): any sub-task already checked with an
`Evidence:` line is **done**.

A sub-task is on the **frontier** when every sub-task in its `Depends On` is
done and it is not itself done.

If the plan has no `Depends On` information, or MAX_PARALLEL is `1`, treat the
plan as a linear chain: dispatch a single implementer for the whole plan (the
pre-frontier behaviour):

> Invoke `@spec-implementer` with:
> Implement issue **ISSUE_KEY** from `specs/issue-ISSUE_KEY-spec.md`. Track progress. Follow the skill exactly.

Then go to Step 4.

## Step 3.5 — Frontier waves (MAX_PARALLEL > 1)

Repeat while any sub-task remains not done:

1. Compute the frontier (Step 3 definition).
2. **Disjointness guard**: from the frontier, select up to MAX_PARALLEL
   sub-tasks whose declared `Files` sets do not intersect each other. A
   sub-task with no declared file set, or one whose files intersect another
   frontier member's, is deferred to a later wave (run it sequentially in this
   wave only if it is the sole selectable task). If two sub-tasks would touch
   the same file, they must never run in the same wave.
3. Dispatch one `@spec-implementer` per selected sub-task — **all invocations
   in a single message** so they run concurrently — each with:
   > Implement **only sub-task N** of issue **ISSUE_KEY** from
   > `specs/issue-ISSUE_KEY-spec.md`. Touch only the files declared for
   > sub-task N. Other sub-tasks are being implemented concurrently by other
   > agents — do not modify their files, do not commit their work, and do not
   > mark any other sub-task complete. Track progress under Engram topic_key
   > `impl/ISSUE_KEY/subtask-N` (fallback: append only sub-task N's line to
   > progress.md). Follow the skill exactly.
4. After the wave completes, update `specs/issue-ISSUE_KEY-progress.md` from
   the per-sub-task evidence (check off completed sub-tasks, copy Evidence
   lines), then recompute the frontier and repeat.
5. If a wave reports a failure or a 3-strike escalation on any sub-task, stop
   dispatching new waves and surface the escalation to the user.

## Step 4 — Report

After all sub-tasks are done, print a one-line summary of the
Definition-of-Done state:
```
✅ Implementation complete for ISSUE_KEY.
   See specs/issue-ISSUE_KEY-progress.md for the trail.
```
