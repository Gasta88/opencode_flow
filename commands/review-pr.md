---
description: Bounded repair loop for a red Foundry PR — gate, poll checks, merge on green, diagnose and fix on red up to --max-attempts, then mark the issue Blocked via the shared Foundry surface. Headless-safe: never prompts.
argument-hint: <PR number|URL> [--merge-mode <auto|direct>] [--base <branch>] [--max-attempts N] [--poll-interval S] [--deadline S]
agent: build
model: opencode/qwen3.6-plus
---

# /review-pr: $ARGUMENTS

Load skill: foundry-headless-contract

You are the PR repair governor. Do not diagnose or fix code yourself — gate, poll, dispatch subagents inline (commands cannot invoke other commands), and enforce the bounds. Follow the spec-driven-workflow skill and the foundry-headless-contract surface exactly.

## Step 0 — Parse arguments

- **PR_REF**: first token — PR number or full URL. Missing/neither ⇒ one-line exit `❌ /review-pr requires a PR number or URL.` (no mutation).
- **MERGE_MODE**: after `--merge-mode`, default `auto`; values `auto|direct`; invalid ⇒ `❌ --merge-mode requires auto or direct.` (no mutation).
- **BASE**: after `--base`; strip a leading `origin/`. If null, derive `BASE_BRANCH` with `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo main`; set `BASE_REF=origin/$BASE_BRANCH` for git plumbing. Bare name for every `gh` comparison; `gh` never receives `origin/<name>`.
- **MAX_ATTEMPTS**: after `--max-attempts`, default `2`.
- **POLL_INTERVAL**: seconds after `--poll-interval`, default `60`.
- **DEADLINE**: seconds after `--deadline`, default `900`.

Banner: `🔁 /review-pr PR_REF | merge-mode=… base=… max-attempts=… poll-interval=…s deadline=…s`.

## Step 1 — Fetch PR metadata and gate

```bash
timeout 120 gh pr view "$PR_REF" --json number,url,state,isDraft,baseRefName,headRefName,headRefOid,autoMergeRequest,body,repository
timeout 120 gh repo view --json nameWithOwner
```

Any gate row failing ⇒ print one line `⏭️  review-pr: skipping PR <ref> — <reason>. No changes made.` and STOP (zero writes):

| Check | Pass condition |
|-------|----------------|
| Same repo | `repository.nameWithOwner` equals `gh repo view --json nameWithOwner` |
| State | `state == "OPEN"` (rejects CLOSED and MERGED) |
| Draft | `isDraft == false` — a draft is owned by an in-flight /letsgo |
| Base | `baseRefName == BASE_BRANCH` (bare-name compare) |

Bind `PR_NUMBER`, `PR_URL`, `HEAD_BRANCH=headRefName`, `HEAD_SHA=headRefOid`. Extract `GH_ISSUE_NUMBER` from the PR body using the Step 6 grammar.

## Step 2 — Verdict memoization

Read-only use of surface op **F3**'s find step on `$GH_ISSUE_NUMBER` (Step 6 grammar; no linked issue ⇒ skip memoization — harmless).

```bash
# F3 find step (from foundry-headless-contract skill)
timeout 120 gh api "repos/$GH_OWNER/$GH_REPO/issues/$GH_ISSUE_NUMBER/comments" --jq '.[] | select(.body | contains("<!-- opencode-flow:result -->")) | .body'
```

If a marker comment records a terminal exhaustion verdict containing `head <SHA>` equal to current `HEAD_SHA` ⇒ `⏭️  review-pr: prior terminal verdict recorded for head <SHA> — <summary>. No changes made.` STOP. Terminal verdicts are memoized per head SHA; green/armed outcomes need no memoization (the Step 4 armed-check is idempotent).

## Step 3 — Poll checks

```bash
timeout 120 gh pr checks "$PR_REF" --json name,bucket,link
```

- Classify by `bucket`: `pass`/`skipping` = terminal-green, `fail` = terminal-red, `pending` = non-terminal. **Never** use the process exit code to classify state.
- All terminal ⇒ any `fail` = RED (list failing names + links), else GREEN. Zero checks ⇒ GREEN (nothing failing).
- Otherwise `sleep "$POLL_INTERVAL"` (bounded; wall clock checked against `START_TIME + DEADLINE`) and re-poll.
- Deadline with non-terminal checks ⇒ `⏳ review-pr: checks still pending at deadline — <pending names>. No changes made.` STOP (not a terminal verdict, not memoized).
- `--watch` is forbidden (unbounded). Every poll call is `timeout 120`-wrapped.

## Step 4 — Green path

Immediately before ANY merge: re-run `timeout 120 gh pr view "$PR_REF" --json baseRefName` and compare to `BASE_BRANCH`; mismatch ⇒ stop, no merge.

- **auto**: re-read `timeout 120 gh pr view "$PR_REF" --json autoMergeRequest` — non-null ⇒ `✅ review-pr: green, auto-merge already armed — no action.` STOP. Null ⇒ exactly one `timeout 120 gh pr merge "$PR_REF" --auto --merge`, then `✅ review-pr: green, armed auto-merge.` STOP.
- **direct**: `timeout 120 gh pr checkout "$PR_REF"` ⇒ `timeout 1800 make ci` (larger bound because CI suites exceed 120 s). Pass ⇒ exactly one `timeout 120 gh pr merge "$PR_REF" --merge`. Fail ⇒ `❌ review-pr: green checks but make ci failed at head <SHA> — not merging, stopping.`
- Merge command failure ⇒ report, do NOT retry with another strategy. PR stays as-is; no board write (merge truth belongs to the reconciler).

## Step 5 — Red repair cycle

`for ATTEMPT in 1..MAX_ATTEMPTS` while RED:

1. `SHA_BEFORE = HEAD_SHA`.
2. **Diagnose**: per failing check, extract the run id from its `link` (`runs/<id>`) and fetch `timeout 120 gh run view <run-id> --log-failed`, truncated with `tail -c 20000`. **Any log unretrievable ⇒ `❌ review-pr: could not retrieve failing log for <check> — stopping rather than guessing.` STOP the whole invocation** (not memoized; next tick may retrieve it).
3. **Worktree**: `timeout 120 gh pr checkout "$PR_REF"`; verify local head == `HEAD_SHA`. Context: `git diff $(git merge-base HEAD $BASE_REF)..HEAD` + `git log $(git merge-base HEAD $BASE_REF)..HEAD --oneline`.
4. **Dispatch reviewers inline** — same prompt shapes as `/review-code` Steps 3–4 / `/letsgo` Step 7a, plus a failing-check block:

```
---FAILING CHECKS START---
Failing checks: <names + links>
Log excerpts:
<bounded log excerpts from gh run view --log-failed | tail -c 20000>
---FAILING CHECKS END---
```

Dispatch `@code-reviewer`, `@standards-reviewer`, `@spec-fidelity-reviewer` **together in one message** (parallel); the spec axis runs only if `specs/issue-<LINKED_N>-spec.md` exists (else `SPEC_OUTPUT = "SKIPPED — no spec available"`, as `/review-code` Step 3). Combine under `## Bugs`/`## Standards`/`## Spec`, then `@code-review-filter` ⇒ `FINAL_OUTPUT`. One review round per attempt — no nested fix-pass loop.
5. **Fix, no commits**: route by axis — bugs/standards ⇒ `@code-fixer`; spec findings ⇒ `@spec-implementer` (with spec path). Every dispatch carries: *"Apply fixes in the working tree only. Do NOT run git commit, do NOT run git push."* (the governor owns the single commit).
6. **No-progress check**: `git status --short` clean AND `git rev-parse HEAD == SHA_BEFORE` ⇒ `⚠️  review-pr: no progress at attempt <N> — head unchanged. Stopping.` STOP (not counted, not retried).
7. **Sensitive scan**: working-tree/staged paths vs `.env*`, `*.pem`, `*.key`, `*credentials*`, `*secret*`, `.DS_Store`; match ⇒ stop, leave tree dirty, no push.
8. **Commit exactly one**: `git add -A -- ':!specs/'` then `git commit -m "fix(review-pr): attempt <N> — <summary>"`. If a subagent committed despite the directive (detect via `git log SHA_BEFORE..HEAD --oneline` count before the governor commits), do NOT create a second commit — verify the count is exactly 1 and push; >1 ⇒ `❌ review-pr: expected ≤1 new commit, found <K> — stopping without push.` (no history rewriting).
9. **Push**: `timeout 120 git push origin "$HEAD_BRANCH"` — never `--force`/`-f`. Rejected ⇒ `❌ review-pr: push rejected (another writer holds the branch) — stopping without retry.` STOP.
10. **Re-poll**: `HEAD_SHA = new headRefOid`; return to Step 3 with a fresh `DEADLINE` window. GREEN ⇒ Step 4. Pending at deadline ⇒ Step 3 exit. RED ⇒ next attempt.

## Step 6 — Exhaustion

Reached when `MAX_ATTEMPTS` cycles completed and the PR is still red:

1. **Resolve LINKED_N**:
   - (a) `HEAD_BRANCH` matches `^feat/([0-9]+)-` ⇒ N
   - (b) else scan the PR body (`gh pr view --json body`) for a `Related Issues` entry `#<N>` ⇒ N
   - (c) else unresolved ⇒ `⚠️  review-pr: exhausted <MAX_ATTEMPTS> attempts at head <SHA> — <failing check names>. No linked issue resolved: no board write, no comment. PR left OPEN.` STOP.
2. **F1** project discovery. `F1_UNRESOLVED` ⇒ skip F2 (zero project writes), continue to F3 (F1-independent).
3. **F2** with `$TARGET_STATUS = Blocked`. Write failure ⇒ record and continue (never abort mid-stop).
4. **F3** upsert exactly one marker comment: `outcome="stopped"`, `stage="pr"`, `reason="review-pr: exhausted <MAX_ATTEMPTS> repair attempts at head <SHA>; attempts: <per-attempt summaries>; remaining failing checks: <names>"`, `branch=HEAD_BRANCH`, `pr_url=PR_URL`, run timestamp. The `head <SHA>` token is the memoization key read by Step 2.
5. Print `🛑 review-pr: exhausted <MAX_ATTEMPTS> attempts — issue #<N> marked Blocked, one comment posted. PR left OPEN.` STOP. Never close the PR, never merge, never `Integrated`.

## Exit lines

Each stop prints one line with a fixed prefix: `⏭️  review-pr: skipping PR …` / `⏳ review-pr: checks still pending at deadline …` / `✅ review-pr: green, …` / `❌ review-pr: …` / `⚠️  review-pr: no progress …` / `🛑 review-pr: exhausted …`.

No interactive prompts anywhere.
