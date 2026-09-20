---
description: Run the full pipeline end-to-end — analyze, auto-resolve spec conflicts, implement, adversarially review, remediate, and open a PR.
argument-hint: <path-to-light-spec> [--quick] [--max-spec-turns N] [--max-impl-passes N] [--max-fix-passes N] [--auto-commit] [--risk-budget N]
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
- **AUTO_COMMIT**: `true` if `--auto-commit` appears anywhere in `$ARGUMENTS`, else `false`
- **RISK_BUDGET**: the integer after `--risk-budget` if present, else `0` (0 = no auto-continue on residual findings)

## Step 0.5 — GitHub issue detection & materialize

If the first token of `$ARGUMENTS` matches `^[0-9]+$`, treat it as a GitHub
issue number instead of a file path.

**Detection:**
- Extract **ISSUE_NUMBER** from the first token.
- Set **ISSUE_KEY** = ISSUE_NUMBER (as a string).
- Set **FILE_PATH** = `specs/{ISSUE_KEY}.md`.

**Fetch:**
Run:
```bash
gh issue view <ISSUE_NUMBER> --json number,title,body,url,state
```
- If `gh` is not authenticated or the call fails, stop and print:
```
❌ Could not fetch GitHub issue #<ISSUE_NUMBER>. Run `gh auth login` or verify the issue exists.
```
- If `state` is `CLOSED`, print a non-blocking warning and continue:
```
⚠️  GitHub issue #<ISSUE_NUMBER> is closed. Proceeding anyway.
```

**Materialize:**
- If `FILE_PATH` already exists on disk, use it as-is (do not overwrite) and
  proceed to Step 1.
- If `FILE_PATH` does not exist, write it:
```markdown
# {ISSUE_KEY}

<!-- Source: GitHub Issue #{ISSUE_KEY} — {url} -->

## Title
{issue title}

## Body
{issue body, verbatim}
```
Then proceed to Step 1.

If the first token does NOT match `^[0-9]+$`, skip this step entirely and
proceed to Step 1 with the existing FILE_PATH and ISSUE_KEY from Step 0.

Verify FILE_PATH exists and is readable. If not, stop and print:
```
❌ File not found: <FILE_PATH>
```

Print banner:
```
🚀 /letsgo issue-ISSUE_KEY | quick=QUICK_MODE spec-turns=MAX_SPEC_TURNS impl-passes=MAX_IMPL_PASSES fix-passes=MAX_FIX_PASSES auto-commit=AUTO_COMMIT risk-budget=RISK_BUDGET
```

### Step 0.25 — Trivial-change detection

Read the light spec file at FILE_PATH. If the `## Title` or `## Body` contains
any of these keywords (case-insensitive): `typo`, `rename`, `reorder`,
`bump version`, `update version`, `whitespace`, `format`, `trailing`,
`remove unused`, `fix typo`,
AND the body describes a single-file or single-line change, set
TRIVIAL_MODE = `true`. Otherwise TRIVIAL_MODE = `false`.

If TRIVIAL_MODE is `true` and QUICK_MODE is `false`, print:
```
ℹ️  Trivial change detected. Skipping spec review gate.
```
and set SKIP_SPEC_REVIEW = `true`. This does NOT skip spec generation (Step 1)
— it only skips Steps 2–3 (conflict checks and human escalation).

---

## Step 1 — Analyze issue

If QUICK_MODE is `true`, invoke `@spec-analyst-quick` with:
> Generate a fast-path spec for issue **ISSUE_KEY** from `FILE_PATH`. Store outputs under `specs/`. Follow the spec-driven-workflow skill exactly.

If QUICK_MODE is `false`, invoke `@spec-analyst` with:
> Generate a full 6-phase spec for issue **ISSUE_KEY** from `FILE_PATH`. Store outputs under `specs/`. Follow the spec-driven-workflow skill exactly.

After the subagent completes, print:
```
✅ Spec ready: specs/issue-ISSUE_KEY-{findings,progress,spec}.md
```

If QUICK_MODE is `true` or SKIP_SPEC_REVIEW is `true`, skip directly to
**Step 4**. Quick specs and trivial changes skip the review gate entirely.

---

## Step 2 — Automated spec conflict resolution (full mode only)

Initialize AUTO_TURN = 1, VERDICT = "CONFLICTS", MAX_SEVERITY = "none".

Repeat while VERDICT == "CONFLICTS" and AUTO_TURN <= MAX_SPEC_TURNS:

### 2a — Check

Invoke `@spec-conflict-checker` with:

> Check issue **ISSUE_KEY** for conflicts.
> Spec: `specs/issue-ISSUE_KEY-spec.md`

Capture the response as CHECK_OUTPUT. Parse the output:
- If it starts with `CLEAR`, set VERDICT = "CLEAR".
- If it starts with `CONFLICTS`, set VERDICT = "CONFLICTS" and extract the
  highest severity among all listed conflicts. Severity levels are
  `critical` > `warning` > `cosmetic`. Set MAX_SEVERITY to the highest
  found. If severity is not tagged, default to `warning`.

### 2b — Log the turn

Call `mem_update` with:
- `topic_key`: "pipeline/ISSUE_KEY/automated-spec-review"
- `title`: "Automated Spec Review — Turn AUTO_TURN for ISSUE_KEY"
- `type`: manual
- `scope`: project
- `content`:
  **What**: Automated spec conflict check turn AUTO_TURN
  **Why**: Spec conflict resolution for ISSUE_KEY
  **Where**: specs/issue-ISSUE_KEY-spec.md
  **Learned**: CHECK_OUTPUT

If Engram MCP is unavailable, append to `specs/issue-ISSUE_KEY-progress.md`:
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

If VERDICT == "CONFLICTS" after MAX_SPEC_TURNS turns:
- If MAX_SEVERITY == "cosmetic", print:
```
ℹ️  Spec for ISSUE_KEY has only cosmetic conflicts after MAX_SPEC_TURNS turns.
    Auto-approving and proceeding.
```
  Append via `mem_update` with:
- `topic_key`: "pipeline/ISSUE_KEY/automated-spec-review"
- `title`: "Automated Spec Review — Auto-approved for ISSUE_KEY"
- `type`: manual
- `scope`: project
- `content`:
  **What**: Auto-approved cosmetic conflicts after MAX_SPEC_TURNS turns
  **Why**: Only cosmetic conflicts remained, auto-approving to proceed
  **Where**: specs/issue-ISSUE_KEY-spec.md
  **Learned**: Auto-approved after budget exhaustion

If Engram MCP is unavailable, append to `specs/issue-ISSUE_KEY-progress.md`:
```markdown
## Automated Spec Review — Auto-approved
- [x] Auto-approved (cosmetic-only conflicts after MAX_SPEC_TURNS turns)
```
  Proceed to **Step 4**.
- Otherwise (MAX_SEVERITY is `critical` or `warning`), proceed to **Step 3**.

---

## Step 3 — Human escalation

Only reached if automated resolution did not clear within budget AND
MAX_SEVERITY is `critical` or `warning`. Print:
```
⚠️  Spec for ISSUE_KEY still has open conflicts after MAX_SPEC_TURNS automated turns.
    Escalating to human review.
```

### 3.0 — decisions.md fallback

Before presenting to the user, check if `decisions.md` exists. For each conflict of type `Decision`, check if a matching decision covers the conflicted file/subsystem. If one exists and unambiguously resolves the conflict, apply it:

1. Invoke `@spec-analyst` with:
> Apply the existing decision from `decisions.md` to resolve the conflict in the spec for issue **ISSUE_KEY**. Existing spec: `specs/issue-ISSUE_KEY-spec.md`.
> Conflict: <specific conflict from CHECK_OUTPUT>
> Applicable decision: <paste matching entry>
> Update only the conflicting section.

2. Re-invoke `@spec-conflict-checker`. If "CLEAR", print `✅ Spec for ISSUE_KEY resolved via decisions.md.` and proceed to **Step 4**.

If no decision covers the conflict or re-check still returns CONFLICTS, proceed to the full human review below.

Present the spec as `/review-spec` does: read `specs/issue-ISSUE_KEY-spec.md` in full, show CHECK_OUTPUT (outstanding conflicts), then ask:
```
How would you like to proceed?
  [A] Approve as-is
  [R] Request changes
  [J] Reject
```

### 3a — On approval

Call `mem_update` with:
- `topic_key`: "pipeline/ISSUE_KEY/human-review"
- `title`: "Human Review — Approved for ISSUE_KEY"
- `type`: manual
- `scope`: project
- `content`:
  **What**: Spec approved by user after MAX_SPEC_TURNS unresolved automated conflicts
  **Why**: Human escalation from automated conflict resolution
  **Where**: specs/issue-ISSUE_KEY-spec.md
  **Learned**: User approved spec for ISSUE_KEY

If Engram MCP is unavailable, append to `specs/issue-ISSUE_KEY-progress.md`:
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
> Implement issue **ISSUE_KEY** from `specs/issue-ISSUE_KEY-spec.md`. Track progress. Follow the skill exactly.

Print `✅ Implementation complete for ISSUE_KEY.` and proceed to **Step 5b**.

### If QUICK_MODE is `false` — DoD-gated loop

Initialize IMPL_PASS = 1, DOD_VERDICT = "FAIL".

Repeat while DOD_VERDICT == "FAIL" and IMPL_PASS <= MAX_IMPL_PASSES:

**5a — Implement pass**

If IMPL_PASS == 1, invoke `@spec-implementer` with:
> Implement issue **ISSUE_KEY** from `specs/issue-ISSUE_KEY-spec.md`. Track progress. Follow the skill exactly.

If IMPL_PASS > 1, invoke `@spec-implementer` with:
> Resume **ISSUE_KEY** from `specs/issue-ISSUE_KEY-spec.md`. Previous DoD failures: <FAIL_REASON>. Address only failing items. Track progress.

**5b — Evaluate**

Invoke `@dod-evaluator` with:

> Evaluate the Definition of Done for issue **ISSUE_KEY**.
> Spec: `specs/issue-ISSUE_KEY-spec.md`
> Progress: `specs/issue-ISSUE_KEY-progress.md`

Capture the response as EVALUATOR_OUTPUT. Set DOD_VERDICT = "PASS" if it
starts with `PASS`, else `"FAIL"`. If `"FAIL"`, capture the failure lines as
FAIL_REASON.

**5c — Log the pass**

Call `mem_update` with:
- `topic_key`: "pipeline/ISSUE_KEY/impl-passes"
- `title`: "Implementation Loop Pass IMPL_PASS — <PASS or FAIL> for ISSUE_KEY"
- `type`: manual
- `scope`: project
- `content`:
  **What**: Implementation pass IMPL_PASS evaluated as <PASS or FAIL>
  **Why**: DoD-gated implementation loop for ISSUE_KEY
  **Where**: specs/issue-ISSUE_KEY-spec.md, specs/issue-ISSUE_KEY-progress.md
  **Learned**: EVALUATOR_OUTPUT

If Engram MCP is unavailable, append to `specs/issue-ISSUE_KEY-progress.md`:
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
and proceed to **Step 5b** (test gate).

If DOD_VERDICT == "FAIL" after MAX_IMPL_PASSES passes, classify failures: **critical** (core functionality, security, data integrity) vs **non-critical** (edge cases, docs, naming, non-core gaps). Count CRITICAL_COUNT.

If CRITICAL_COUNT == 0, print `ℹ️  ISSUE_KEY impl budget exhausted but only non-critical DoD items remain. Auto-continuing.`, call `mem_update` with:
- `topic_key`: "pipeline/ISSUE_KEY/dod-budget"
- `title`: "DoD Budget Exhausted — Auto-continue for ISSUE_KEY"
- `type`: manual
- `scope`: project
- `content`:
  **What**: DoD budget exhausted, auto-continuing with non-critical items remaining
  **Why**: No critical failures, proceeding to test gate
  **Where**: specs/issue-ISSUE_KEY-spec.md
  **Learned**: Non-critical items remaining: <list summaries>

If Engram MCP is unavailable, append to progress.md:
```markdown
## DoD Budget Exhausted — Auto-continue
- Non-critical items remaining: <list summaries>
```
Set DOD_CONTINUED = `true` and proceed to **Step 5b**.

If CRITICAL_COUNT > 0, stop and ask:
```
⚠️  ISSUE_KEY hit impl pass budget (MAX_IMPL_PASSES) with critical DoD failures:
<list critical FAIL_REASON lines>

[C] Continue to test gate & code review anyway
[S] Stop here
```
If Stop, print `⚠️  Stopping /letsgo.` and end. If Continue, set DOD_CONTINUED = `true` and proceed to **Step 5b**.

---

## Step 5b — Convention-based test-suite gate

Look up the test command in this order (first match wins):

1. **AGENTS.md** — look for a `## Test` / `## Tests` / `## Testing` heading
2. **README.md** — same headings
3. **Makefile** — look for a `test:` target

If none of these yield a command, fall back to heuristics: `pytest tests/`, `npm test`, `go test ./...`, or `cargo test` based on project files.

If no test command found, print `ℹ️  No test command found. Skipping test gate.`, set TEST_RESULT = "skipped", TEST_SOURCE = "not found", proceed to **Step 6**.

Otherwise, record TEST_SOURCE and run tests.

### If tests pass
Print `✅ Tests passed (source: TEST_SOURCE).` Set TEST_RESULT = "passed", proceed to **Step 6**.

### If tests fail
Run a bounded fix loop (up to MAX_FIX_PASSES): invoke `@code-fixer` with test output; fall back to `@spec-implementer` if spec context needed. Re-run tests after each fix.

If tests pass within budget, print `✅ Tests passed after N fix pass(es) (source: TEST_SOURCE).` Set TEST_RESULT = "passed-after-fix", proceed to **Step 6**.

If tests still fail, print `⚠️  Tests still failing after MAX_FIX_PASSES fix passes. Continuing to code review.` Set TEST_RESULT = "failed", proceed to **Step 6**.

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

Call `mem_update` with:
- `topic_key`: "pipeline/ISSUE_KEY/code-review"
- `title`: "Code Review Pass FIX_PASS for ISSUE_KEY"
- `type`: manual
- `scope`: project
- `content`:
  **What**: Code review pass FIX_PASS completed
  **Why**: Adversarial code review for ISSUE_KEY
  **Where**: Diff vs BASE_BRANCH
  **Learned**: FINAL_OUTPUT

If Engram MCP is unavailable, append to `specs/issue-ISSUE_KEY-progress.md`:
```markdown
## Code Review Pass FIX_PASS
FINAL_OUTPUT
```

**7d — Fix, if needed**

If ISSUES_REMAIN and FIX_PASS < MAX_FIX_PASSES, invoke `@code-fixer` with:

> Address review findings for **ISSUE_KEY**: FINAL_OUTPUT. Fix only what's listed. Read current state first.

If spec context needed, fall back to `@spec-implementer` with:
> Address review findings for **ISSUE_KEY**. Spec: `specs/issue-ISSUE_KEY-spec.md`. Findings: FINAL_OUTPUT. Re-check against spec before resolving. Track progress.

Re-collect the diff (same commands as Step 6) before looping back to 7a, since
the fix pass changed it.

Increment FIX_PASS.

**7e — Exit or escalate**

If ISSUES_REMAIN == false, print:
```
✅ Code review clean for ISSUE_KEY (pass FIX_PASS-1/MAX_FIX_PASSES).
```
and proceed to **Step 8**.

If ISSUES_REMAIN == true after MAX_FIX_PASSES passes, count findings by severity: CRITICAL_FINDINGS, WARNING_FINDINGS, NITPICK_FINDINGS.

If RISK_BUDGET > 0 and CRITICAL_FINDINGS == 0 and (WARNING_FINDINGS + NITPICK_FINDINGS) <= RISK_BUDGET, print `ℹ️  ISSUE_KEY code review within risk budget. Auto-continuing.`, call `mem_update` with:
- `topic_key`: "pipeline/ISSUE_KEY/code-review"
- `title`: "Code Review — Auto-continue within risk budget for ISSUE_KEY"
- `type`: manual
- `scope`: project
- `content`:
  **What**: Code review within risk budget, auto-continuing
  **Why**: Residual findings within acceptable risk threshold
  **Where**: Diff vs BASE_BRANCH
  **Learned**: Residual findings: WARNING_FINDINGS warning(s), NITPICK_FINDINGS nitpick(s)

If Engram MCP is unavailable, append to progress.md:
```markdown
## Code Review — Auto-continue within risk budget
- Residual findings: WARNING_FINDINGS warning(s), NITPICK_FINDINGS nitpick(s)
```
Set REVIEW_CONTINUED = `true` and proceed to **Step 8**.

Otherwise, stop and ask:
```
⚠️  ISSUE_KEY still has review findings after MAX_FIX_PASSES passes:
FINAL_OUTPUT

[C] Continue to PR creation anyway
[S] Stop here
```
If Stop, print `⚠️  Stopping /letsgo.` and end. If Continue, set REVIEW_CONTINUED = `true` and proceed to **Step 8**.

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

### 8b.5 — Auto-create branch if on default branch

If the current branch equals BASE_BRANCH (i.e. still on `main`/`master`):
```bash
FEATURE_BRANCH="feat/ISSUE_KEY-$(date +%Y%m%d%H%M%S)"
git checkout -b $FEATURE_BRANCH
git push -u origin $FEATURE_BRANCH
```
Print `✅ Created branch $FEATURE_BRANCH.` and re-run the commands from 8b
to get the updated branch name.

### 8c — Review and commit changes

If the working tree is clean, skip to 8d.

1. Print the full list of changed files from `git status --short`.
2. Scan for risk patterns: `.env`, `.env.*`, `*.pem`, `*.key`, `*credentials*`,
   `*secret*`, `.DS_Store`. If any risk-pattern file appears, stop and print:
```
⚠️  <file> matches a sensitive-file pattern and is about to be committed.
    Remove it from the working tree or add it to .gitignore before re-running /letsgo.
```
3. If AUTO_COMMIT is `true` and no risk patterns detected:
   - Count the total changed files and total lines changed (additions + deletions).
   - If changed files > 50 OR total lines changed > 5000, print:
```
⚠️  Diff exceeds auto-commit thresholds (<N> files, <N> lines).
    Manual confirmation required.
```
     Then fall through to step 4 (manual confirmation).
   - Otherwise, generate a commit message from the diff and run
     `git add -A && git commit -m "<message>"` without asking.
     Print `✅ Committed automatically (--auto-commit).`
4. If AUTO_COMMIT is `false` or thresholds exceeded: generate a commit message
   from the diff, print it with the file list, and ask the user to confirm
   before running `git add -A && git commit`.

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

  Spec:          <auto-resolved in N turns | human-approved after escalation | trivial-change bypass>
  Implementation: <PASS in N passes | continued with unmet DoD items (non-critical only)>
  Test suite:    <passed | passed-after-fix | failed | skipped> (source: TEST_SOURCE)
  Code review:   <clean in N passes | continued with residual findings (within risk budget)>
  Branch:        <branch name>
  PR:            <URL returned by gh pr create>

See specs/issue-ISSUE_KEY-progress.md for the full audit trail.
```
