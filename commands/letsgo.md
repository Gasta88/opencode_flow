---
description: Run the full pipeline end-to-end — analyze, auto-resolve spec conflicts, implement, adversarially review, remediate, and open a PR.
argument-hint: <path-to-light-spec> [--quick] [--max-spec-turns N] [--max-impl-passes N] [--max-fix-passes N]
agent: build
model: opencode/qwen3.6-plus
---

# Let's Go: $ARGUMENTS

You are the top-level pipeline governor. You do not analyse, write code, or
review anything yourself — you dispatch to subagents in sequence and enforce
the gates between phases. This command inlines the logic of `/analyze-issue`,
`/review-spec`, `/implement-spec`, `/implement-loop`, `/review-code`, and
`/create-pr` because commands cannot invoke other commands directly. Follow
the spec-driven-workflow skill exactly throughout.

## Step 0 — Parse arguments

`$ARGUMENTS` contains a path to a light spec file, followed by optional flags
in any order.

Extract:
- **FILE_PATH**: the first token (e.g. `specs/FEAT-123.md`)
- **ISSUE_KEY**: the basename of FILE_PATH without the `.md` extension. If the
  derived key starts with `issue-`, strip that prefix (first occurrence only).
- **QUICK_MODE**: `true` if `--quick` appears anywhere in `$ARGUMENTS`, else `false`
- **MAX_SPEC_TURNS**: the integer after `--max-spec-turns` if present, else `3`
- **MAX_IMPL_PASSES**: the integer after `--max-impl-passes` if present, else `3`
- **MAX_FIX_PASSES**: the integer after `--max-fix-passes` if present, else `3`

Verify FILE_PATH exists and is readable. If not, stop and print:
```
❌ File not found: <FILE_PATH>
```

Print a short banner so the user can see the whole run's parameters up front:
```
🚀 /letsgo issue-ISSUE_KEY (quick=QUICK_MODE, spec-turns=MAX_SPEC_TURNS, impl-passes=MAX_IMPL_PASSES, fix-passes=MAX_FIX_PASSES)
```

---

## Step 1 — Analyze issue

If QUICK_MODE is `true`, invoke `@spec-analyst-quick` with this exact task:

> Generate a fast-path spec for issue **ISSUE_KEY**, reading the light spec file
> at `FILE_PATH`. Store all output files under `specs/`.
> Follow the spec-driven-workflow skill exactly.

If QUICK_MODE is `false`, invoke `@spec-analyst` with this exact task:

> Generate a full 6-phase implementation spec for issue **ISSUE_KEY**, reading
> the light spec file at `FILE_PATH`. Store all output files under `specs/`.
> Follow the spec-driven-workflow skill exactly.

After the subagent completes, print:
```
✅ Spec ready: specs/issue-ISSUE_KEY-{findings,progress,spec}.md
```

If QUICK_MODE is `true`, skip directly to **Step 4**. Quick specs skip the
review gate entirely, matching `/review-spec`'s existing quick-mode behaviour.

---

## Step 2 — Automated spec conflict resolution (full mode only)

Initialize AUTO_TURN = 1, VERDICT = "CONFLICTS".

Repeat while VERDICT == "CONFLICTS" and AUTO_TURN <= MAX_SPEC_TURNS:

### 2a — Check

Invoke `@spec-conflict-checker` with:

> Check issue **ISSUE_KEY** for conflicts.
> Spec: `specs/issue-ISSUE_KEY-spec.md`

Capture the response as CHECK_OUTPUT. Set VERDICT = "CLEAR" if it starts with
`CLEAR`, else `"CONFLICTS"`.

### 2b — Log the turn

Append to `specs/issue-ISSUE_KEY-progress.md`:
```markdown
## Automated Spec Review — Turn AUTO_TURN
CHECK_OUTPUT
```

### 2c — Revise on conflict

If VERDICT == "CONFLICTS" and AUTO_TURN < MAX_SPEC_TURNS, invoke `@spec-analyst` with:

> Revise the spec for issue **ISSUE_KEY** to resolve the following automated
> conflict findings. Existing spec: `specs/issue-ISSUE_KEY-spec.md`.
> Existing progress: `specs/issue-ISSUE_KEY-progress.md`.
> Conflicts to resolve:
> CHECK_OUTPUT
> Regenerate only the affected sections. Do not discard unrelated work.
> Update progress.md to reflect which sections were revised.

Increment AUTO_TURN.

### 2d — Exit the loop

If VERDICT == "CLEAR", print:
```
✅ Spec for ISSUE_KEY cleared automated conflict checks (turn AUTO_TURN/MAX_SPEC_TURNS).
```
and proceed to **Step 4**.

If VERDICT == "CONFLICTS" after MAX_SPEC_TURNS turns, proceed to **Step 3**.

---

## Step 3 — Human escalation

Only reached if automated resolution did not clear within budget. Print:
```
⚠️  Spec for ISSUE_KEY still has open conflicts after MAX_SPEC_TURNS automated turns.
    Escalating to human review.
```

Present the spec to the user exactly as `/review-spec` does:

1. Read `specs/issue-ISSUE_KEY-spec.md` in full and present it section by
   section (Requirements, Technical Specification, Implementation Plan, Test
   Strategy, Definition of Done).
2. Show the final CHECK_OUTPUT (the outstanding conflicts) alongside the spec
   so the user can see exactly what automation could not resolve.
3. Ask the user:
```
How would you like to proceed?
  [A] Approve as-is
  [R] Request changes
  [J] Reject
```

### 3a — On approval

Append to `specs/issue-ISSUE_KEY-progress.md`:
```markdown
## Human Review
- [x] Approved by user on <YYYY-MM-DD> (after MAX_SPEC_TURNS unresolved automated conflicts)
```
Print `✅ Spec approved for ISSUE_KEY.` and proceed to **Step 4**.

### 3b — On request changes

1. Collect free-text feedback. Re-prompt if empty.
2. Invoke `@spec-analyst` with the same revision contract as `/review-spec`
   Step 5b, using the user's feedback.
3. Re-present the changed sections and return to the decision prompt (Step 3,
   point 3). This human-driven loop is not subject to MAX_SPEC_TURNS — a live
   human is now steering it directly.

### 3c — On rejection (or no resolution reached)

Do NOT delete any files. Print:
```
⚠️  Spec for ISSUE_KEY was not approved. Stopping /letsgo.
    Files remain on disk as an audit trail under specs/.
```
Stop the entire pipeline. Do not proceed to implementation, review, or PR creation.

---

## Step 4 — Fetch external documentation

Invoke `@external-scout` with:

> Fetch external dependency docs for issue **ISSUE_KEY**.
> Spec: `specs/issue-ISSUE_KEY-spec.md`

If it returns `NO_EXTERNAL_DEPS`, continue. Otherwise
`specs/issue-ISSUE_KEY-extdocs.md` is now written for the implementer to read.

---

## Step 5 — Implementation

### If QUICK_MODE is `true`

Invoke `@spec-implementer` with:

> Implement issue **ISSUE_KEY** from `specs/issue-ISSUE_KEY-spec.md`.
> Track progress in `specs/issue-ISSUE_KEY-progress.md`.
> Follow the spec-driven-workflow skill exactly.

Print `✅ Implementation complete for ISSUE_KEY.` and proceed to **Step 6**.

### If QUICK_MODE is `false` — DoD-gated loop

Initialize IMPL_PASS = 1, DOD_VERDICT = "FAIL".

Repeat while DOD_VERDICT == "FAIL" and IMPL_PASS <= MAX_IMPL_PASSES:

**5a — Implement pass**

If IMPL_PASS == 1, invoke `@spec-implementer` with:

> Implement issue **ISSUE_KEY** from `specs/issue-ISSUE_KEY-spec.md`.
> Track progress in `specs/issue-ISSUE_KEY-progress.md`.
> Follow the spec-driven-workflow skill exactly.

If IMPL_PASS > 1, invoke `@spec-implementer` with:

> Resume implementation of **ISSUE_KEY** from `specs/issue-ISSUE_KEY-spec.md`.
> The previous pass failed the DoD evaluation. Unsatisfied items:
> <FAIL_REASON from previous evaluator output>
> Address only the failing items. Do not re-implement what is already passing.
> Track all changes in `specs/issue-ISSUE_KEY-progress.md`.

**5b — Evaluate**

Invoke `@dod-evaluator` with:

> Evaluate the Definition of Done for issue **ISSUE_KEY**.
> Spec: `specs/issue-ISSUE_KEY-spec.md`
> Progress: `specs/issue-ISSUE_KEY-progress.md`

Capture the response as EVALUATOR_OUTPUT. Set DOD_VERDICT = "PASS" if it
starts with `PASS`, else `"FAIL"`. If `"FAIL"`, capture the failure lines as
FAIL_REASON.

**5c — Log the pass**

Append to `specs/issue-ISSUE_KEY-progress.md`:
```markdown
## Loop Pass IMPL_PASS — <PASS or FAIL>
Evaluator output:
EVALUATOR_OUTPUT
```
Increment IMPL_PASS.

**5d — Exit or escalate**

If DOD_VERDICT == "PASS", print:
```
✅ Implementation complete for ISSUE_KEY (pass IMPL_PASS-1/MAX_IMPL_PASSES). All DoD items satisfied.
```
and proceed to **Step 6**.

If DOD_VERDICT == "FAIL" after MAX_IMPL_PASSES passes, stop and ask the user:
```
⚠️  ISSUE_KEY hit the implementation pass budget (MAX_IMPL_PASSES) without
    satisfying all DoD items. Remaining failures:
FAIL_REASON

How would you like to proceed?
  [C] Continue to code review & PR anyway
  [S] Stop here — I'll finish this manually
```
If the user chooses Stop, print `⚠️  Stopping /letsgo. See specs/issue-ISSUE_KEY-progress.md.`
and end the pipeline. If Continue, proceed to **Step 6** noting the unmet DoD
items in the final report.

---

## Step 6 — Adversarial code review

Collect the diff:
```bash
BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo main)
[ -z "$BASE_BRANCH" ] && BASE_BRANCH=main
git diff $(git merge-base HEAD $BASE_BRANCH)..HEAD
git log $(git merge-base HEAD $BASE_BRANCH)..HEAD --oneline
```

If the diff is empty, print `✅ No changes detected vs BASE_BRANCH. Skipping review.`
and go to **Step 8**.

If fewer than 5 lines changed (additions + deletions), print
`ℹ️  Diff is trivial (<5 lines). Skipping adversarial review.` and go to **Step 8**.

Otherwise run the remediation loop below.

---

## Step 7 — Remediation loop

Initialize FIX_PASS = 1, ISSUES_REMAIN = true.

Repeat while ISSUES_REMAIN and FIX_PASS <= MAX_FIX_PASSES:

**7a — Review**

Invoke `@code-reviewer` with the current diff and recent commits (same prompt
shape as `/review-code` Step 3). Capture as REVIEWER_OUTPUT.

Invoke `@code-review-filter` with REVIEWER_OUTPUT and the diff (same prompt
shape as `/review-code` Step 4). Capture as FINAL_OUTPUT.

**7b — Check for issues**

If FINAL_OUTPUT contains `0 issues flagged`, set ISSUES_REMAIN = false.

**7c — Log the pass**

Append to `specs/issue-ISSUE_KEY-progress.md`:
```markdown
## Code Review Pass FIX_PASS
FINAL_OUTPUT
```

**7d — Fix, if needed**

If ISSUES_REMAIN and FIX_PASS < MAX_FIX_PASSES, invoke `@spec-implementer` with:

> Address the following code review findings for issue **ISSUE_KEY**.
> Spec: `specs/issue-ISSUE_KEY-spec.md`
> Findings:
> FINAL_OUTPUT
> Fix only what is listed. Re-check your changes against the spec before
> considering a finding resolved. Track changes in `specs/issue-ISSUE_KEY-progress.md`.

Re-collect the diff (same commands as Step 6) before looping back to 7a, since
the fix pass changed it.

Increment FIX_PASS.

**7e — Exit or escalate**

If ISSUES_REMAIN == false, print:
```
✅ Code review clean for ISSUE_KEY (pass FIX_PASS-1/MAX_FIX_PASSES).
```
and proceed to **Step 8**.

If ISSUES_REMAIN == true after MAX_FIX_PASSES passes, stop and ask the user:
```
⚠️  ISSUE_KEY still has flagged code review findings after MAX_FIX_PASSES passes:
FINAL_OUTPUT

How would you like to proceed?
  [C] Continue to PR creation anyway
  [S] Stop here — I'll finish this manually
```
If Stop, print `⚠️  Stopping /letsgo. See specs/issue-ISSUE_KEY-progress.md.`
and end the pipeline. If Continue, proceed to **Step 8** noting the residual
findings in the final report.

---

## Step 8 — Create PR

### 8a — Derive the PR title

Read `specs/issue-ISSUE_KEY-spec.md`. If it has a `### User Story` section
(full mode), take its first sentence. If it has a `## What` section (quick
mode), take its first sentence. Compose:

```
ISSUE_KEY: <short summary, trimmed to ~60 chars>
```

Use this as PR_TITLE. If no usable summary can be extracted, fall back to
`ISSUE_KEY: implementation`.

### 8b — Analyse changes

```bash
BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo main)
[ -z "$BASE_BRANCH" ] && BASE_BRANCH=main
git status --short
git branch --show-current
git diff $(git merge-base HEAD $BASE_BRANCH)..HEAD
git log $(git merge-base HEAD $BASE_BRANCH)..HEAD --oneline
```

### 8c — Review and commit changes

If the working tree is clean, skip to 8d.

1. Print the full list of changed files from `git status --short`.
2. Scan for risk patterns: `.env`, `.env.*`, `*.pem`, `*.key`, `*credentials*`,
   `*secret*`, `.DS_Store`. If any risk-pattern file appears, stop and print:
```
⚠️  <file> matches a sensitive-file pattern and is about to be committed.
    Remove it from the working tree or add it to .gitignore before re-running /letsgo.
```
3. Otherwise generate a commit message from the diff, print it with the file
   list, and ask the user to confirm before running `git add -A && git commit`.

### 8d — Draft the PR description

```markdown
## What Changed
- <bullet points of key changes, grounded in the diff>

## Why This Change
- <business or technical justification, inferred from commits and diff>

## Testing Done
- <what tests were added or run>

## Related Issues
- ISSUE_KEY

## Pipeline Notes
- <mention if spec was approved via automated conflict resolution vs human escalation>
- <mention if DoD or code review budgets were exhausted and continued on human override>
```

Write it to `pr-description.md` in the repo root. Never commit this file.

### 8e — Create the PR

```bash
gh pr create --title "PR_TITLE" --body-file pr-description.md
```

If `gh` is not authenticated, stop and tell the user to run `gh auth login`.

### 8f — Clean up

```bash
rm pr-description.md
```

---

## Step 9 — Final report

Print a summary of the whole run:
```
🎉 /letsgo complete for ISSUE_KEY

  Spec:        <auto-resolved in N turns | human-approved after escalation>
  Implementation: <PASS in N passes | continued with unmet DoD items>
  Code review: <clean in N passes | continued with residual findings>
  PR:          <URL returned by gh pr create>

See specs/issue-ISSUE_KEY-progress.md for the full audit trail.
```
</content>
