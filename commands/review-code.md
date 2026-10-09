---
description: Run a three-axis code review (bugs / standards / spec fidelity) on the current git diff vs main, with a bounded fix loop
argument-hint: [--max-fix-passes N] [--spec ISSUE_KEY]
agent: build
model: opencode/qwen3.5-plus
---

# Three-Axis Code Review

Review runs along three independent axes, dispatched as parallel subagents so
they don't pollute each other's context:

- **Bugs** (`@code-reviewer`): adversarial bug/logic/security hunting
- **Standards** (`@standards-reviewer`): documented repo standards + Fowler smell baseline
- **Spec** (`@spec-fidelity-reviewer`): fidelity to the originating spec

A change can pass one axis and fail another; findings are reported per axis
and never reranked across axes.

## Step 0 — Parse arguments

Extract **MAX_FIX_PASSES**: the integer after `--max-fix-passes` if present in `$ARGUMENTS`, else `3`.

Extract **SPEC_KEY**: the token after `--spec` if present in `$ARGUMENTS`. If
absent, try to infer it: check the current branch name for an issue-key pattern
(e.g. `feat/FEAT-123-...`) and recent commit messages for issue keys, then look
for `specs/issue-<KEY>-spec.md`. If a spec file is found, set SPEC_KEY; else
SPEC_KEY = none.

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
ℹ️  Diff is trivial (<5 lines). Skipping review.
```
and stop.

## Step 3 — Run the reviewers in parallel

Dispatch the following subagent invocations **together, in a single message**,
so they run concurrently:

1. `@code-reviewer` with:
   > Review the following git diff.
   > ---DIFF START--- <FULL_DIFF> ---DIFF END---
   > Recent commits: <git log --oneline>
   Capture as BUGS_OUTPUT.

2. `@standards-reviewer` with:
   > Review the following git diff against this repo's documented coding
   > standards and the smell baseline.
   > ---DIFF START--- <FULL_DIFF> ---DIFF END---
   > Recent commits: <git log --oneline>
   Capture as STANDARDS_OUTPUT.

3. Only if SPEC_KEY is not none — `@spec-fidelity-reviewer` with:
   > Review the following git diff for fidelity to the spec.
   > Spec: `specs/issue-<SPEC_KEY>-spec.md`
   > ---DIFF START--- <FULL_DIFF> ---DIFF END---
   > Recent commits: <git log --oneline>
   Capture as SPEC_OUTPUT. If SPEC_KEY is none, set
   SPEC_OUTPUT = "SKIPPED — no spec available".

Combine BUGS_OUTPUT, STANDARDS_OUTPUT, and SPEC_OUTPUT (with `## Bugs`,
`## Standards`, `## Spec` markers between them) into REVIEWER_OUTPUT.

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

Route findings by axis:

- Bugs and Standards findings → invoke `@code-fixer` with:
  > Apply the following review findings.
  > Findings:
  > <bugs/standards findings from FINAL_OUTPUT>
- Spec findings (`missing-requirement | scope-creep | spec-drift`) need spec
  context → invoke `@spec-implementer` with:
  > Address spec-fidelity review findings for **SPEC_KEY**.
  > Spec: `specs/issue-<SPEC_KEY>-spec.md`.
  > Findings: <spec findings from FINAL_OUTPUT>.
  > Re-check against spec before resolving. Track progress.

Capture the responses as FIXER_OUTPUT.

### 5b — Re-collect the diff

Run the same git diff commands from Step 1 to produce a new FULL_DIFF.

### 5c — Re-review

Re-dispatch the same parallel reviewer set from Step 3 with the new diff, then
re-run the filter (same prompt shape as Step 4). Capture as FINAL_OUTPUT.

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
and print FINAL_OUTPUT verbatim, keeping findings grouped under `## Bugs`,
`## Standards`, `## Spec` headings with a per-axis count and the worst issue
within each axis (never a single winner across axes). Print the FIXER_OUTPUT
summary so the user can see which findings were applied and which were not.
