---
description: Run a three-axis code review (bugs / standards / spec fidelity) on the current git diff vs main, with a bounded fix loop
argument-hint: [--max-fix-passes N] [--spec ISSUE_KEY]
agent: build
model: opencode/qwen3.5-plus
---

# Three-Axis Code Review

Three independent axes, dispatched as parallel subagents so they don't pollute each other's context:
- **Bugs** (`@code-reviewer`): adversarial bug/logic/security hunting
- **Standards** (`@standards-reviewer`): documented repo standards + Fowler smell baseline
- **Spec** (`@spec-fidelity-reviewer`): fidelity to the originating spec

Findings are reported per axis and never reranked across axes.

## Step 0 — Parse arguments

**MAX_FIX_PASSES**: integer after `--max-fix-passes`, default `3`.

**SPEC_KEY**: token after `--spec`. If absent, infer from the branch (`feat/FEAT-123-...`) or recent commit messages, then look for `specs/issue-<KEY>-spec.md`; else `none`.

## Step 1 — Collect the diff

```bash
BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo main)
[ -z "$BASE_BRANCH" ] && BASE_BRANCH=main
FULL_DIFF="$(git diff $(git merge-base HEAD $BASE_BRANCH)..HEAD 2>/dev/null || true)
$(git diff --cached HEAD 2>/dev/null || true)
$(git diff HEAD 2>/dev/null || true)"
git log $(git merge-base HEAD $BASE_BRANCH)..HEAD --oneline
```

Empty `FULL_DIFF` → `✅ No changes detected vs $BASE_BRANCH. Nothing to review.`

## Step 2 — Guard against trivial diffs

Fewer than 5 changed lines (additions + deletions, ignoring file headers):
```
ℹ️  Diff is trivial (<5 lines). Skipping review.
```
stop.

## Step 3 — Run the reviewers in parallel

Dispatch **together, in a single message**:

1. `@code-reviewer`:
   > Review the following git diff.
   > ---DIFF START--- <FULL_DIFF> ---DIFF END---
   > Recent commits: <git log --oneline>
   Capture as BUGS_OUTPUT.

2. `@standards-reviewer`:
   > Review the following git diff against this repo's documented coding standards and the smell baseline.
   > ---DIFF START--- <FULL_DIFF> ---DIFF END---
   > Recent commits: <git log --oneline>
   Capture as STANDARDS_OUTPUT.

3. Only if SPEC_KEY is not none — `@spec-fidelity-reviewer`:
   > Review the following git diff for fidelity to the spec.
   > Spec: `specs/issue-<SPEC_KEY>-spec.md`
   > ---DIFF START--- <FULL_DIFF> ---DIFF END---
   > Recent commits: <git log --oneline>
   Capture as SPEC_OUTPUT. If SPEC_KEY is none, set `SPEC_OUTPUT = "SKIPPED — no spec available"`.

Combine BUGS_OUTPUT, STANDARDS_OUTPUT, SPEC_OUTPUT with `## Bugs`, `## Standards`, `## Spec` markers into REVIEWER_OUTPUT.

## Step 4 — Run the meta-reviewer

`@code-review-filter`:
> Filter this review output against the original diff.
> ---REVIEWER OUTPUT START--- <REVIEWER_OUTPUT> ---REVIEWER OUTPUT END---
> ---DIFF START--- <FULL_DIFF> ---DIFF END---
Capture as FINAL_OUTPUT.

## Step 5 — Fix loop

If FINAL_OUTPUT contains `0 issues flagged`, print it verbatim and stop. Otherwise FIX_PASS = 1, ISSUES_REMAIN = true.

While ISSUES_REMAIN and FIX_PASS <= MAX_FIX_PASSES:

### 5a — Apply fixes

- Bugs/Standards → `@code-fixer`:
  > Apply the following review findings.
  > Findings:
  > <bugs/standards findings from FINAL_OUTPUT>
- Spec findings (`missing-requirement | scope-creep | spec-drift`) → `@spec-implementer`:
  > Address spec-fidelity review findings for **SPEC_KEY**.
  > Spec: `specs/issue-<SPEC_KEY>-spec.md`.
  > Findings: <spec findings from FINAL_OUTPUT>.
  > Re-check against spec before resolving. Track progress.

Capture as FIXER_OUTPUT.

### 5b — Re-collect the diff

Run the Step 1 git commands again → new FULL_DIFF.

### 5c — Re-review

Re-dispatch the Step 3 parallel set with the new diff, then re-run the filter (same prompt shape as Step 4). Capture as FINAL_OUTPUT.

### 5d — Check for remaining issues

`0 issues flagged` → ISSUES_REMAIN = false. Increment FIX_PASS.

### 5e — Exit or report

Clean:
```
✅ Code review clean after FIX_PASS-1 fix pass(es).
```
then FINAL_OUTPUT verbatim.

Remaining after MAX_FIX_PASSES:
```
⚠️  Issues remain after MAX_FIX_PASSES fix passes.
```
then FINAL_OUTPUT verbatim, grouped under `## Bugs`/`## Standards`/`## Spec` with a per-axis count and the worst issue per axis (never a single winner across axes). Print FIXER_OUTPUT so the user sees what was applied and what was not.
