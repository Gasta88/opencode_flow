---
description: Bounded repair loop for a red Foundry PR — gate, poll checks, merge on green, diagnose and fix on red up to --max-attempts, then mark the issue Blocked via the shared Foundry surface. Headless-safe: never prompts.
argument-hint: <PR number|URL> [--merge-mode <auto|direct>] [--base <branch>] [--max-attempts N] [--poll-interval S] [--deadline S]
agent: build
model: opencode/qwen3.6-plus
---

# /review-pr: $ARGUMENTS

Load skill: foundry-headless-contract

You are the PR repair governor. You do not diagnose or fix code yourself — you gate, poll, dispatch subagents inline (commands cannot invoke other commands), and enforce the bounds. Follow the spec-driven-workflow skill and the foundry-headless-contract surface exactly.

## Step 0 — Parse arguments

Extract the following from `$ARGUMENTS`:

- **PR_REF**: first token — a PR number or full URL. Missing / neither ⇒ one-line exit `❌ /review-pr requires a PR number or URL.` (no mutation).
- **MERGE_MODE**: token after `--merge-mode`, default `auto`; values `auto|direct`; invalid ⇒ one-line exit `❌ --merge-mode requires auto or direct.` (no mutation).
- **BASE**: token after `--base`; normalize: strip leading `origin/` if present. If null, derive `BASE_BRANCH` with `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo main`; set `BASE_REF=origin/$BASE_BRANCH` for git plumbing. Bare name for every `gh` comparison; `gh` never receives `origin/<name>`.
- **MAX_ATTEMPTS**: integer after `--max-attempts`, default `2`.
- **POLL_INTERVAL**: integer seconds after `--poll-interval`, default `60`.
- **DEADLINE**: integer seconds after `--deadline`, default `900`.

Print banner: `🔁 /review-pr PR_REF | merge-mode=… base=… max-attempts=… poll-interval=…s deadline=…s`.

## Step 1 — Fetch PR metadata and gate (FR1)

```bash
timeout 120 gh pr view "$PR_REF" --json number,url,state,isDraft,baseRefName,headRefName,headRefOid,autoMergeRequest,body,repository
timeout 120 gh repo view --json nameWithOwner
```

Gate table — any row failing ⇒ print exactly one line `⏭️  review-pr: skipping PR <ref> — <reason>. No changes made.` and STOP (zero writes):

| Check | Pass condition |
|-------|----------------|
| Same repo | `repository.nameWithOwner` equals output of `gh repo view --json nameWithOwner` |
| State | `state == "OPEN"` (rejects CLOSED and MERGED) |
| Draft | `isDraft == false` — "a draft is owned by an in-flight /letsgo" |
| Base | `baseRefName == BASE_BRANCH` (bare-name compare) |

Bind `PR_NUMBER`, `PR_URL`, `HEAD_BRANCH=headRefName`, `HEAD_SHA=headRefOid`. Extract `GH_ISSUE_NUMBER` from the PR body (for F2/F3) using the Step 6 grammar.

## Step 2 — Verdict memoization (FR10)

Read-only use of surface op **F3**'s find step on `$GH_ISSUE_NUMBER` (resolved with the Step 6 grammar; if no linked issue resolves, memoization is skipped — harmless).

```bash
# F3 find step (from foundry-headless-contract skill)
timeout 120 gh api "repos/$GH_OWNER/$GH_REPO/issues/$GH_ISSUE_NUMBER/comments" --jq '.[] | select(.body | contains("<!-- opencode-flow:result -->")) | .body'
```

If a marker comment exists whose body records a terminal `review-pr` exhaustion verdict containing `head <SHA>` equal to current `HEAD_SHA` ⇒ print `⏭️  review-pr: prior terminal verdict recorded for head <SHA> — <summary>. No changes made.` and STOP. Terminal verdicts are memoized per head SHA; green/armed outcomes need no memoization (Step 4's armed-check is itself idempotent).

## Step 3 — Poll Checks (FR2)

```bash
timeout 120 gh pr checks "$PR_REF" --json name,bucket,link
```

- Classify each check by `bucket`: `pass`/`skipping` = terminal-green, `fail` = terminal-red, `pending` = non-terminal. **Never** use the process exit code to classify state (light-spec Goal 2).
- All checks terminal ⇒ verdict: any `fail` ⇒ RED (list failing names + links); else GREEN. Zero checks ⇒ GREEN (GitHub merge semantics: nothing failing) — analyst ruling, stated in the command.
- Otherwise `sleep "$POLL_INTERVAL"` (bounded per-interval sleep; loop wall-clock checked against `START_TIME + DEADLINE`) and re-poll.
- Deadline reached with non-terminal checks ⇒ `⏳ review-pr: checks still pending at deadline — <pending names>. No changes made.` STOP (ticker re-ticks later; NOT a terminal verdict, not memoized).
- `gh pr checks --watch` is forbidden (unbounded). Every poll call is `timeout 120`-wrapped.

## Step 4 — Green path (FR3/FR4, AC3)

Immediately before ANY merge action: re-run `timeout 120 gh pr view "$PR_REF" --json baseRefName` and compare to `BASE_BRANCH`; mismatch ⇒ stop, no merge (FR12).

- **auto**: re-read `timeout 120 gh pr view "$PR_REF" --json autoMergeRequest` (avoid staleness) — non-null ⇒ `✅ review-pr: green, auto-merge already armed — no action.` STOP. Null ⇒ exactly one `timeout 120 gh pr merge "$PR_REF" --auto --merge`, then `✅ review-pr: green, armed auto-merge.` STOP.
- **direct**: `timeout 120 gh pr checkout "$PR_REF"` ⇒ `timeout 1800 make ci` (bounded; larger bound because CI suites legitimately exceed 120 s — analyst ruling, host concern in Risks). Pass ⇒ exactly one `timeout 120 gh pr merge "$PR_REF" --merge`. Fail ⇒ `❌ review-pr: green checks but make ci failed at head <SHA> — not merging, stopping.` (do-not-guess).
- Merge command failure ⇒ report, do NOT retry with another strategy (decision 13 invariant). PR stays as-is; no board write (merge truth belongs to the reconciler).

## Step 5 — Red repair cycle (FR5/FR6/FR11, AC4)

`for ATTEMPT in 1..MAX_ATTEMPTS` while RED:

1. `SHA_BEFORE = HEAD_SHA`.
2. **Diagnose**: for each failing check, extract the run id from its `link` (`runs/<id>` path segment) and fetch `timeout 120 gh run view <run-id> --log-failed`, truncated to a bounded excerpt (`tail -c 20000`). **Any log unretrievable ⇒ `❌ review-pr: could not retrieve failing log for <check> — stopping rather than guessing.` and STOP the whole invocation** (light-spec constraint; not memoized — next tick may retrieve it).
3. **Worktree**: `timeout 120 gh pr checkout "$PR_REF"`; verify local head == `HEAD_SHA`. Diff context: `git diff $(git merge-base HEAD $BASE_REF)..HEAD` + `git log $(git merge-base HEAD $BASE_REF)..HEAD --oneline` (BASE_REF per decision 2026-10-10).
4. **Dispatch reviewers inline** (FR8) — same prompt shapes as `/review-code` Steps 3–4 / `/letsgo` Step 7a, plus a failing-check context block:

```
---FAILING CHECKS START---
Failing checks: <names + links>
Log excerpts:
<bounded log excerpts from gh run view --log-failed | tail -c 20000>
---FAILING CHECKS END---
```

Dispatch `@code-reviewer`, `@standards-reviewer`, `@spec-fidelity-reviewer` **together in one message** (parallel); the spec axis runs only if `specs/issue-<LINKED_N>-spec.md` exists (else `SPEC_OUTPUT = "SKIPPED — no spec available"`, exactly as `/review-code` Step 3). Combine under `## Bugs`/`## Standards`/`## Spec`, then `@code-review-filter` ⇒ `FINAL_OUTPUT`. One review round per attempt — no nested fix-pass loop (NFR: bounded wall clock).
5. **Fix, no commits**: route by axis — bugs/standards ⇒ `@code-fixer`; spec findings ⇒ `@spec-implementer` (with spec path). Every dispatch carries the directive: *"Apply fixes in the working tree only. Do NOT run git commit, do NOT run git push."* (governor owns the single commit — AC4 "each pushes at most one commit"; deviation handling in 8).
6. **No-progress check** (FR11): `git status --short` clean AND `git rev-parse HEAD == SHA_BEFORE` ⇒ `⚠️  review-pr: no progress at attempt <N> — head unchanged. Stopping.` STOP (not counted, not retried).
7. **Sensitive scan** (FR19): working-tree/staged paths vs `.env*`, `*.pem`, `*.key`, `*credentials*`, `*secret*`, `.DS_Store`; match ⇒ stop, leave tree dirty, no push.
8. **Commit exactly one**: `git add -A -- ':!specs/'` then `git commit -m "fix(review-pr): attempt <N> — <summary>"`. If a subagent committed despite the directive (detect via `git log SHA_BEFORE..HEAD --oneline` count before the governor commits), the governor does NOT create a second commit — it verifies the count is exactly 1 and pushes; >1 ⇒ `❌ review-pr: expected ≤1 new commit, found <K> — stopping without push.` (invariant beats convenience; no history rewriting).
9. **Push**: `timeout 120 git push origin "$HEAD_BRANCH"` — never `--force`/`-f`. Rejected ⇒ `❌ review-pr: push rejected (another writer holds the branch) — stopping without retry.` STOP.
10. **Re-poll**: `HEAD_SHA = new headRefOid`; return to Step 3 with a fresh `DEADLINE` window (per-cycle deadline; total invocation bounded by `(MAX_ATTEMPTS+1) × DEADLINE + fix time` — stated in the command). GREEN ⇒ Step 4. Pending at deadline ⇒ Step 3's deadline exit. RED ⇒ next attempt.

## Step 6 — Exhaustion (FR7, AC5)

Reached when `MAX_ATTEMPTS` cycles completed and the PR is still red:

1. **Resolve LINKED_N** (FR9, precedence stated in the command):
   - (a) `HEAD_BRANCH` matches `^feat/([0-9]+)-` ⇒ N
   - (b) else scan the PR body (`gh pr view --json body`) for a `Related Issues` entry `#<N>` ⇒ N
   - (c) else unresolved ⇒ print `⚠️  review-pr: exhausted <MAX_ATTEMPTS> attempts at head <SHA> — <failing check names>. No linked issue resolved: no board write, no comment. PR left OPEN.` and STOP (analyst ruling: F2 and F3 both key off the issue; with no issue there is nothing to mark or comment on; inventing a PR comment is out of contract).
2. **F1** project discovery (surface op). `F1_UNRESOLVED` ⇒ skip F2 (zero project writes), continue to F3 (F3 is F1-independent per skill).
3. **F2** with `$TARGET_STATUS = Blocked`. Write failure ⇒ record and continue (never abort mid-stop — skill runbook).
4. **F3** upsert exactly one marker comment: `outcome="stopped"`, `stage="pr"`, `reason="review-pr: exhausted <MAX_ATTEMPTS> repair attempts at head <SHA>; attempts: <per-attempt summaries>; remaining failing checks: <names>"`, `branch=HEAD_BRANCH`, `pr_url=PR_URL`, run timestamp. The `head <SHA>` token in `reason` is the memoization key read by Step 2 (frozen 7-field vocabulary untouched — no schema overload, FR18/Notes).
5. Print `🛑 review-pr: exhausted <MAX_ATTEMPTS> attempts — issue #<N> marked Blocked, one comment posted. PR left OPEN.` STOP. Never `gh pr close`, never merge, never `Integrated`.

## Step 7 — Exit-line vocabulary

Every stop prints exactly one line from a fixed set (harness-pinned prefixes):
- `⏭️  review-pr: skipping PR …` (gates + memoization)
- `⏳ review-pr: checks still pending at deadline …`
- `✅ review-pr: green, …`
- `❌ review-pr: …` (hard stops: log unretrievable, push rejected, commit-count violation, make ci failed)
- `⚠️  review-pr: no progress …`
- `🛑 review-pr: exhausted …`

No interactive prompts anywhere (FR20).
