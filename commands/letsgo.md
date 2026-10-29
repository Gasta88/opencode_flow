---
description: Run the full pipeline end-to-end — analyze, auto-resolve spec conflicts, implement, review along three axes (bugs/standards/spec), remediate, and open a PR.
argument-hint: <path-to-light-spec> [--quick] [--headless] [--base <branch>] [--merge-mode <auto|direct>] [--max-spec-turns N] [--max-impl-passes N] [--max-fix-passes N] [--auto-commit] [--no-auto-commit] [--risk-budget N] [--strict-tests] [--no-strict-tests] [--make-ci] [--spec-confidence N]
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

## Step R — Result Contract

The auto-flow driver reads `specs/issue-ISSUE_KEY-result.json` to learn how this
`/letsgo` run ended — outcome, stage, and PR URL — without parsing logs. This
section is the single canonical contract. Every exit point in this command
carries a `Result hook (E1)` … `Result hook (E17)` line stating the exact
`outcome`/`stage`/`reason` for that exit; the hooks reference this section.

### JSON template

Write exactly these fields — the schema is frozen by the driver contract: never
add a field, never rename one, never write driver-side outcome values
(`timeout`, `no_result`, `interrupted`, `make_ci_failed`, `merge_failed` are the
driver's to synthesize; `/letsgo` never writes them):

```json
{
  "issue": 42,
  "outcome": "pr_opened",
  "stage": "pr",
  "reason": "PR opened successfully",
  "branch": "feat/42-20261010120000",
  "pr_url": "https://github.com/owner/repo/pull/43",
  "pipeline": { "spec_turns": 2, "impl_passes": 1, "fix_passes": 2 }
}
```

### Field derivation rules

| Field | Type | Rule |
|-------|------|------|
| `issue` | JSON number or string | `ISSUE_KEY`; emit as a JSON **number** when it matches `^[0-9]+$` (GitHub-issue path, Step 0.5), else as a JSON **string** (file-path arg like `FEAT-123`). At exits before Step 0.5 (E1), use the first token of `$ARGUMENTS` when it is numeric, else the Step 0 derived key. |
| `outcome` | string enum | Exactly `"pr_opened"` (E17 only) or `"stopped"` (E1–E16). |
| `stage` | string enum | One of `"spec"`, `"dod"`, `"tests"`, `"review"`, `"pr"` — the **last phase reached before exit**, not the phase that would have run next. Each hook declares its value; E11 (Step 7.5) maps to `"tests"` because the failing gate is the test gate (its `reason` records "post-review"). |
| `reason` | string | Non-empty; quotes the printed ⚠️/❌ stop message for the exit (each hook states the exact value to write). |
| `branch` | string | `FEATURE_BRANCH` if set (Step 0.1 onward), else `""` — never null. |
| `pr_url` | string | The URL returned by `gh pr create` at E17, else `""` — never null. |
| `pipeline` | object, optional | `{ "spec_turns": int, "impl_passes": int, "fix_passes": int }` — `spec_turns` = Step 2 conflict-loop turns executed (0 when Step 2 is skipped: quick/trivial); `impl_passes` = Step 5 implementation passes completed (1 in quick mode); `fix_passes` = Step 7 review-remediation passes completed (0 if Step 7 was skipped for a trivial diff — the Step 5b/7.5 test-fix loops are NOT counted). Unreached counters = 0. **Omit the `pipeline` key entirely** (not `{}`, not `null`) when no counter has been initialised — the exits before Step 1 (E1–E4). |

### Write protocol

1. **Path**: `specs/issue-ISSUE_KEY-result.json`, relative to the repo root.
   `specs/` is git-ignored, so the artifact is never committed.
2. **Overwrite**: last-run-wins — overwrite the file on every exit; never append.
3. **Atomic**: use the `write` tool with the complete JSON document in a single
   call (no partial writes, no shell `echo` concatenation).
4. **Write-before-stop**: write the file **immediately before** printing the
   stop message, so the artifact exists even if the session dies mid-message.
   On success (E17), write immediately after `gh pr create` returns the URL and
   before the Step 9 report prints.
5. **A failed write must not crash the pipeline**: if the write itself errors,
   print `⚠️  Result file write failed: <error>. Continuing with the stop anyway.`
   and proceed to the stop — the driver derives `no_result` from a missing file;
   never abort mid-stop because of the artifact.

### Standing rule

Any current or future stop in `/letsgo` — including exits not enumerated as
E1–E17 — MUST write `specs/issue-ISSUE_KEY-result.json` per this contract
before ending, choosing the `stage` of the phase being exited and a `reason`
that describes the stop. When adding a new exit point to this command, add its
`Result hook` line in the same edit.

### Comment mirror (surface op F3) — exactly one result comment (Foundry mode)

In Foundry mode every exit upserts a single issue comment carrying the marker
line `<!-- opencode-flow:result -->` (AC7). Run surface operation **F3** with
`$GH_OWNER`, `$GH_REPO`, `$GH_ISSUE_NUMBER`, `$RESULT_COMMENT_FILE`.
The comment body is written to `result-comment.md`: marker line first, then `outcome`, `stage`, `reason`,
`branch`, `pr_url` and the run timestamp. F3 finds by marker → PATCH, else create — exactly one marker comment per issue.
Token hygiene (AC9): no token value ever appears in argv, stdout, `result.json`,
comments, or files — rely on ambient `gh auth` only. Delete `result-comment.md`
after the upsert; it is never committed.

### Foundry hooks (E18–E23, E17-F) — registered per the standing rule

Enumeration extension only — the schema above is unchanged. Each hook's full
`Result hook` line lives at its exit point; this table is the registration.

| Hook | Exit | outcome | stage | reason | Extra Foundry actions |
|------|------|---------|-------|--------|------------------------|
| E18 | `--merge-mode` invalid (Step 0) | `stopped` | `spec` | `--merge-mode requires auto or direct` | none (pre-board) |
| E19 | Preflight fail (Step 0.6) | `stopped` | `spec` | preflight failure — see the Step 0.6 exit contract | comment; `Blocked` iff board reachable |
| E20 | Board claim fail (Step 0.7) | `stopped` | `spec` | claim write error — see Step 0.7 | comment; no branch/PR exists |
| E21 | Branch safety stop (Step 0.1-F) | `stopped` | `spec` | branch safety — see Step 0.1-F | comment; `Blocked` |
| E22 | Mutex fail (Step 0.8) | `stopped` | `pr` | mutex failure — see Step 0.8 | close PR iff created; `Blocked`; comment |
| E23 | Land fail (Step 8e-L) | `stopped` | `pr` | land failure — see Step 8e-L | close PR + `Blocked` (OD1); comment |
| E17-F | Success (Step 8e-L complete) | `pr_opened` | `pr` | `PR opened successfully` | board left `In Progress`; comment; `pr_url` = existing PR URL |

Existing E1–E16 keep their declared values verbatim; every post-mutex stop
additionally executes the Foundry Stop Protocol.

---

## Step 0 — Parse arguments

`$ARGUMENTS` contains a path to a light spec file, followed by optional flags
in any order.

Extract:
- **FILE_PATH**: the first token (e.g. `specs/FEAT-123.md`)
- **ISSUE_KEY**: the basename of FILE_PATH without the `.md` extension. If the
  derived key starts with `issue-`, strip that prefix (first occurrence only).
- **QUICK_MODE**: `true` if `--quick` appears anywhere in `$ARGUMENTS`, else `false`
- **HEADLESS**: `true` if `--headless` appears anywhere in `$ARGUMENTS`, else `false`
- **MAX_SPEC_TURNS**: the integer after `--max-spec-turns` if present, else `3`
- **MAX_IMPL_PASSES**: the integer after `--max-impl-passes` if present, else `3`
- **MAX_FIX_PASSES**: the integer after `--max-fix-passes` if present, else `3`
- **AUTO_COMMIT**: `true` by default. `false` only if `--no-auto-commit` appears
  anywhere in `$ARGUMENTS`. (`--auto-commit` is still accepted for backwards
  compatibility and forces `true`.)
- **RISK_BUDGET**: the integer after `--risk-budget` if present, else `0` (0 = no auto-continue on residual findings)
- **STRICT_TESTS**: `true` if `--strict-tests` appears, or if HEADLESS is `true`.
  `false` only if `--no-strict-tests` appears anywhere.
- **MAKE_CI**: `true` if `--make-ci` appears anywhere in `$ARGUMENTS`, else `false`
- **SPEC_CONFIDENCE**: the float after `--spec-confidence` if present, else `0.0`
  (0.0 = escalate all conflicts regardless of confidence; 0.8 = escalate only
  conflicts tagged with confidence >= 0.8)
- **BASE**: the token immediately after `--base` if present, else `null`.
  Normalization: strip a leading `origin/` from the value, so `--base origin/ai/integration`
  and `--base ai/integration` both resolve to the bare branch name `ai/integration`.
  Validation: if `--base` appears but there is no following token, or the next token
  starts with `--`:
  📄 **Result hook (E1):** before this stop, write `specs/issue-ISSUE_KEY-result.json`
  per §Step R — Result Contract with `outcome="stopped"`, `stage="spec"`,
  `reason="--base requires a branch name"`.
  Print `❌ --base requires a branch name (e.g. --base ai/integration).` and STOP
  immediately (hard stop — no interactive prompt, so this is headless-safe; do NOT
  consume the flag-like token as the branch name).
  Set **BASE_EFFECTIVE** = `BASE` if BASE is not null, else `default(origin/HEAD)`.
  BASE is resolved once here and in Step 0.1 into `BASE_BRANCH`/`BASE_REF` for the
  steps that follow (0.1, 6, 7d, 8b, 8b.5, 8e, 9).
- **MERGE_MODE**: the token immediately after `--merge-mode` if present, else `auto`.
  Valid values: `auto`, `direct`. Validation: if `--merge-mode` appears but there is
  no following token, or the next token starts with `--`, or the value is neither
  `auto` nor `direct`:
  📄 **Result hook (E18):** before this stop, write `specs/issue-ISSUE_KEY-result.json`
  per §Step R — Result Contract with `outcome="stopped"`, `stage="spec"`,
  `reason="--merge-mode requires auto or direct"`, `branch=""` (FEATURE_BRANCH does
  not exist yet) and the `pipeline` key omitted (no counter initialised).
  Print `❌ --merge-mode requires auto or direct (e.g. --merge-mode auto).` and STOP
  immediately (hard stop — no interactive prompt, so this is headless-safe; do NOT
  consume the flag-like token as the mode value).
- **FOUNDRY_MODE**: `true` if and only if HEADLESS is `true` AND BASE is not `null`
  (i.e. both `--headless` and `--base <branch>` are present); `false` otherwise.
  Foundry mode activates Steps 0.6/0.7/0.1-F/0.8, the Push Protocol, the Step 8e-L
  land path, and the Foundry Stop Protocol. Any other combination takes the existing
  interactive path, byte-for-byte unchanged.

**Load skill (AC1):** Foundry mode loads the shared surface:
```
Load skill: foundry-headless-contract
```
Reference operations F1–F4 from the skill; do not duplicate inline `gh project` recipes.
- **QUICK × FOUNDRY**: `--quick` remains allowed in Foundry mode; it only skips the
  spec review gate — that semantics is unchanged (FR14).

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
- If `gh` is not authenticated or the call fails:
📄 **Result hook (E2):** before this stop, write `specs/issue-ISSUE_KEY-result.json`
per §Step R — Result Contract with `outcome="stopped"`, `stage="spec"`,
`reason="Could not fetch GitHub issue"`.
Stop and print:
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

If the first token does NOT match `^[0-9]+$`, skip the detection/fetch/materialize
sub-steps and continue with the existing FILE_PATH and ISSUE_KEY from Step 0.

## Step 0.5b — Verify spec file (common gate)

This gate runs for both numeric (GitHub issue) and file-path arguments, after
Step 0.5 has resolved FILE_PATH and ISSUE_KEY.

Verify FILE_PATH exists and is readable. If not:
📄 **Result hook (E3):** before this stop, write `specs/issue-ISSUE_KEY-result.json`
per §Step R — Result Contract with `outcome="stopped"`, `stage="spec"`,
`reason="File not found"` (use the first token of `$ARGUMENTS` as `issue` when numeric).
Stop and print:
```
❌ File not found: <FILE_PATH>
```

Print banner:
```
🚀 /letsgo issue-ISSUE_KEY | quick=QUICK_MODE headless=HEADLESS base=BASE_EFFECTIVE foundry=FOUNDRY_MODE merge-mode=MERGE_MODE spec-turns=MAX_SPEC_TURNS impl-passes=MAX_IMPL_PASSES fix-passes=MAX_FIX_PASSES auto-commit=AUTO_COMMIT risk-budget=RISK_BUDGET strict-tests=STRICT_TESTS make-ci=MAKE_CI spec-confidence=SPEC_CONFIDENCE
```

## Step 0.6 — Foundry preflight (fail closed)

Runs ONLY when FOUNDRY_MODE is `true` — after the Step 0.5b banner, before Step 0.1.
No write of any kind (no branch, no commit, no push, no board write, no spec work)
happens until this preflight passes. Every violation exits through one contract:

📄 **Result hook (E19):** before this stop, write `specs/issue-ISSUE_KEY-result.json`
per §Step R — Result Contract with `outcome="stopped"`, `stage="spec"`,
`reason="Foundry preflight failed: <specific>"` (substitute the specific cause),
`branch=""`, `pr_url=""`, and the `pipeline` key omitted (no counter initialised) —
then run the Foundry Stop Protocol (pre-mutex variant: no PR exists, so no close
is attempted).

**Live body (OD3):** parse the LIVE GitHub issue body, never the possibly-stale
materialized file (Step 0.5's "exists → use as-is"):
```bash
timeout 120 gh issue view <ISSUE_NUMBER> --json body --jq '.body'
```
If ISSUE_NUMBER is unset (a file-path argument under FOUNDRY_MODE), or the call
fails or times out ⇒ E19 (live-body read failure).

**Project discovery (surface op F1):** run surface operation **F1** with `$GH_OWNER`, `$GH_REPO`.
Exactly one node ⇒ bind `PROJECT_NUMBER`, `PROJECT_OWNER` (fallback to URL parse).
Zero or ≥2 nodes ⇒ E19 (fail closed before any write; when no board resolves, no `Blocked` write is attempted).

**Field precheck (surface op F2):** run surface operation **F2** precheck with `$PROJECT_NUMBER`, `$PROJECT_OWNER`.
`Status` must be a single-select field containing the exact option names
`In Progress` and `Blocked` (plus readable `Ready` and `Integrated`). The Foundry
cannot ask, so it fails: any missing field or option ⇒ E19. This step never creates or renames options
(contrast: `/brainstorm` provisions interactively).

**Foundry fit:** the live body must contain a `## Foundry fit` section with the
exact line `Fit: yes` (2026-10-28 /brainstorm contract). A missing section or
`Fit: no` ⇒ E19.

**Blocked by:** parse the `## Blocked by` section. The accepted ref grammar is ONLY
same-repo `#<N>` and external `OWNER/REPO#<N>` list refs (`- #<N> — <title>` /
`- OWNER/REPO#<N> — <title>`); anything else — a bare `N`, a URL, `ISSUE-123`
style — fails closed ⇒ E19. The line `None — can start immediately` means no
blockers ⇒ pass. Resolve each ref:

- **C3 GitHub state:**
```bash
timeout 120 gh issue view <M> --json state
timeout 120 gh issue view <M> -R <OWNER>/<REPO> --json state
```
  Pass ⇔ state is `CLOSED` (or `MERGED` where the ref resolves to a merged PR).
- **C4 board Status (same-repo OPEN refs only):** the `Integrated` escape hatch is
  same-repo only — an external OPEN ref always fails. Read the blocker item's
  Status via GraphQL (canonical per `specs/issue-13-extdocs.md`).
  Pass ⇔ a node with `field.name == "Status"` and `name == "Integrated"` (exact, case-sensitive).
  Any other value, zero Status nodes, or a query error ⇒ E19.

An unresolved blocker ref ⇒ E19. C13 bounds: every call above is wrapped
`timeout 120`; a timeout is treated as that command's failure ⇒ E19, no blind retry.

## Step 0.7 — Board claim (In Progress)

Runs ONLY when FOUNDRY_MODE is `true`, immediately after Step 0.6 passes and
before Step 0.1 — the claim is written before the first `git checkout -b`, commit, or push (AC2).
Run surface op **F2** with `$TARGET_STATUS` = `In Progress`.
The value is exactly `In Progress` (case-sensitive, per the exact option names the
precheck verified). **Never write `Ready` or `Integrated`** — `Ready` is
/brainstorm-owned and `Integrated` is the host reconciler's; `Blocked` is written
only by the Foundry Stop Protocol below.

On write error or timeout ⇒ 📄 **Result hook (E20):** before this stop, write
`specs/issue-ISSUE_KEY-result.json` per §Step R — Result Contract with
`outcome="stopped"`, `stage="spec"`, `reason="Board claim failed: <error>"`,
`branch=""`, `pr_url=""`, `pipeline` omitted — then the Foundry Stop Protocol
(the protocol's `Blocked` attempt still runs where the board is reachable).

## Foundry Stop Protocol (single definition)

Every Foundry-mode stop from Step 0.6 onward executes this protocol, in order.
It is defined once here and referenced by each stop — stops do NOT restate it:

1. **Result file** — write `specs/issue-ISSUE_KEY-result.json` per the stop's own
   `Result hook` line (§Step R — Result Contract), before any message prints.
2. **Comment mirror** — upsert the single result marker comment on the issue per
   C11 (§Step R — Comment mirror): find the comment containing the marker, PATCH
   it if found, else create it — exactly one marker comment per issue, never a
   duplicate (AC7).
3. **Close the PR if one exists** — `timeout 120 gh pr close "$PR_NUMBER"`, and
   only when the mutex PR exists (Step 0.8 onward). Pre-mutex stops (E19/E20/E21)
   skip this — no PR exists yet.
4. **Board release** — set the item to `Blocked` (surface op **F2** with `$TARGET_STATUS` = `Blocked`).
   When PROJECT_NUMBER/PROJECT_OWNER were never resolved (discovery failed) or the
   write itself fails, record the error and continue — never abort mid-stop.
5. **Stop message** — print the distinct Foundry anchor: post-mutex stops print
   `Foundry mode: stopping, closing the draft PR and marking the issue as Blocked.`;
   pre-mutex stops print `Foundry mode: stopping and marking the issue as Blocked.`
   — then STOP. In Foundry mode these strings replace the interactive/headless
   stop shapes; the frozen anchors keep their existing occurrence counts.

The board is left `In Progress` on success — `/letsgo` never writes `Integrated`
(the reconciler observes the merge and owns that transition).

### Step 0.1 — Create feature branch up front

Resolve the base branch and the remote-tracking ref that every later step
(Steps 6, 7d, 8b, 8b.5, 8e, 9) consumes. Use exactly one of the two paths below,
depending on whether BASE was set in Step 0.

**When BASE is set** (the `--base <branch>` flag was passed; BASE was already
normalized in Step 0 — leading `origin/` stripped):
```bash
BASE_BRANCH=<BASE>
BASE_REF=origin/$BASE_BRANCH
git fetch origin $BASE_BRANCH
```
If the `git fetch` exits non-zero (e.g. `couldn't find remote ref`):
📄 **Result hook (E4):** before this stop, write `specs/issue-ISSUE_KEY-result.json`
per §Step R — Result Contract with `outcome="stopped"`, `stage="spec"`,
`reason="Remote branch not found (fetch failed)"`, `branch=""` (FEATURE_BRANCH does
not exist yet) and the `pipeline` key omitted (no counter initialised).
Print `❌ Remote branch origin/<BASE> not found (fetch failed). Stopping.` and STOP
before any implementation runs (hard stop — no interactive prompt, headless-safe).
If the current branch equals BASE_BRANCH (i.e. already checked out on the base):
```bash
FEATURE_BRANCH="feat/ISSUE_KEY-$(date +%Y%m%d%H%M%S)"
git checkout -b $FEATURE_BRANCH $BASE_REF
```
Print `✅ Created feature branch $FEATURE_BRANCH from origin/$BASE_BRANCH.`
If already on a different non-base branch, use it as-is and set FEATURE_BRANCH to
the current branch name — `BASE_REF` still points at `origin/<BASE>` for later steps.

**Step 0.1-F — Foundry branch variant (FOUNDRY_MODE only).** When FOUNDRY_MODE is
`true`, this variant OVERRIDES the reuse sentence above — a non-base branch is
never reused. After the fetch above, take `CURRENT_BRANCH=$(git branch --show-current)`:

- CURRENT_BRANCH equals BASE_BRANCH → create from the remote-tracking ref:
```bash
FEATURE_BRANCH="feat/<N>-$(date +%Y%m%d%H%M%S)"
git checkout -b $FEATURE_BRANCH $BASE_REF
```
  `<N>` is ISSUE_NUMBER (Foundry invocations are always numeric). Verify AC3
  immediately: `git merge-base HEAD $BASE_REF` must equal `$(git rev-parse $BASE_REF)`;
  a mismatch ⇒ E21.
- CURRENT_BRANCH is not BASE_BRANCH → run RESUME_CHECK — never reuse it:
```bash
gh pr list --state open --json number,url,headRefName,isDraft --jq '[.[] | select(.headRefName | test("^feat/<N>-[0-9]{14}$"))]'
```
  Exactly 1 match ⇒ adopt its `headRefName` as FEATURE_BRANCH and its `number`/`url`
  as PR_NUMBER/PR_URL, then check out the tracking branch
  (`timeout 120 git fetch origin $FEATURE_BRANCH && timeout 120 git checkout $FEATURE_BRANCH`);
  Step 0.8 is skipped — the PR already exists and FR10 forbids a second one.
  0 or ≥2 matches ⇒ E21 fail-closed (never pick one).

📄 **Result hook (E21):** before this stop, write `specs/issue-ISSUE_KEY-result.json`
per §Step R — Result Contract with `outcome="stopped"`, `stage="spec"`,
`reason="Branch safety stop: non-base branch not reused / resume ambiguity"`,
`branch=""` (or FEATURE_BRANCH when the create path ran), `pr_url=""`, `pipeline`
omitted — then the Foundry Stop Protocol (pre-mutex: comment + `Blocked`; no close).

**When BASE is null** (default path — behavior unchanged):
Determine the base branch:
```bash
BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo main)
[ -z "$BASE_BRANCH" ] && BASE_BRANCH=main
```
Bind `BASE_REF=$BASE_BRANCH` (the bare derived name — no `origin/` prefix is added
and no `git fetch` is run on the default path, so every later git command emits
exactly what it did before).
If the current branch equals BASE_BRANCH (i.e. still on `main`/`master`):
```bash
FEATURE_BRANCH="feat/ISSUE_KEY-$(date +%Y%m%d%H%M%S)"
git checkout -b $FEATURE_BRANCH
```
Print `✅ Created feature branch $FEATURE_BRANCH from origin/$BASE_BRANCH.`
If already on a non-default branch, use it as-is and set FEATURE_BRANCH to the current branch name.

Store BASE_BRANCH, BASE_REF and FEATURE_BRANCH as variables for later steps.

## Step 0.8 — Draft-PR mutex (Foundry concurrency lock)

Runs ONLY when FOUNDRY_MODE is `true`, immediately after Step 0.1-F and before Step 0.25.
This is the concurrency lock — the draft PR exists before any implementation commit (AC4).
Skipped entirely on a resumed run whose PR already exists (Step 0.1-F adopted one) —
never open a second PR (FR10).

Write `pr-mutex-body.md` in the repo root with the placeholder body
`Foundry run in progress — pipeline results land here` (the final body arrives at
Step 8e-L; the file is deleted right after the create call and never committed), then:

```bash
git commit --allow-empty -m "chore(letsgo): reserve PR mutex for issue <N>"
```
Run the C10 pre-push scan (Push Protocol, next section) — a sensitive-pattern match
blocks the push — then push and create the draft:
```bash
timeout 120 git push -u origin "$FEATURE_BRANCH"
gh pr create --draft --base "$BASE_BRANCH" --title "ISSUE_KEY: <short summary>" --body-file pr-mutex-body.md
```
Capture **PR_URL** and **PR_NUMBER** from the create output. The create call takes
only the bare `$BASE_BRANCH` value — the two-variable split of decision 2026-10-10
applies: git plumbing consumes `$BASE_REF`; the gh surface never does.

On empty-commit failure, C10 scan match, push rejection, create failure, or a
timeout ⇒ 📄 **Result hook (E22):** before this stop, write
`specs/issue-ISSUE_KEY-result.json` per §Step R — Result Contract with
`outcome="stopped"`, `stage="pr"`, `reason="Draft-PR mutex failed: <error>"`,
`branch=FEATURE_BRANCH`, `pr_url=""` unless the PR was already created, `pipeline`
omitted — then the Foundry Stop Protocol (close the PR iff it was created; `Blocked`).

## Push Protocol (Foundry mode)

The `/letsgo` governor owns every `git push` — dispatched subagents commit only
(see the push-governance rule in `agents/spec-implementer.md`).

- **Checkpoint pushes (C9):** `timeout 120 git push origin "$FEATURE_BRANCH"` runs
  after each commit-producing stage: Step 5 pass end, Step 5b fix-loop end (if it
  committed), Step 7d fix pass end, Step 7.5 fix-loop end, Step 8c final commit.
  Checkpoints are per-stage, not per-commit.
- **No force-push:** force-push in any form is forbidden everywhere in `/letsgo`.
  A rejected non-force push means another writer holds the branch — treat it as that
  stage's failure (mutex stage ⇒ E22; later stages ⇒ their own hook) and run the
  Foundry Stop Protocol. Never retry with a forced push.
- **Scan-before-every-push (C10):** before EVERY push — the mutex push and each
  checkpoint — check staged and working-tree paths against the sensitive patterns
  `.env*`, `*.pem`, `*.key`, `*credentials*`, `*secret*`, `.DS_Store` via
  `git status --short` and `git diff --cached --name-only`. A match ⇒ stop at the
  current stage with `reason="Sensitive-file pattern matched before push"`, then the
  Foundry Stop Protocol (close PR + `Blocked` post-mutex).
- **Timeout bounds (C13):** every git/gh network call in Foundry mode is wrapped
  `timeout 120 ...` (hosts without GNU coreutils use `gtimeout 120 ...` — see
  `specs/issue-13-extdocs.md`); a timeout is that command's failure ⇒ its hook + the
  Foundry Stop Protocol, never a blind retry.

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
- If SPEC_CONFIDENCE > 0.0, filter the CHECK_OUTPUT conflicts by confidence.
  Only escalate conflicts where the checker expressed confidence >= SPEC_CONFIDENCE.
  If after filtering no conflicts remain at critical/warning severity, print:
```
ℹ️  Spec for ISSUE_KEY conflicts filtered out by confidence threshold (SPEC_CONFIDENCE).
    Auto-approving and proceeding.
```
  Proceed to **Step 4**.
- Otherwise (MAX_SEVERITY is `critical` or `warning`), proceed to **Step 3**.

---

## Step 3 — Human escalation

Only reached if automated resolution did not clear within budget AND
MAX_SEVERITY is `critical` or `warning`.

### 3-headless — Headless mode

If HEADLESS is `true`, do NOT ask the user. Print:
```
⚠️  Spec for ISSUE_KEY still has open conflicts after MAX_SPEC_TURNS automated turns.
    Headless mode: stopping and marking as Blocked.
```
📄 **Result hook (E5):** before this stop, write `specs/issue-ISSUE_KEY-result.json`
per §Step R — Result Contract with `outcome="stopped"`, `stage="spec"`,
`reason="Spec conflicts unresolved after MAX_SPEC_TURNS automated turns; headless stop (Blocked)"`.
If FOUNDRY_MODE is `true`, run the Foundry Stop Protocol after this hook (close the PR + `Blocked`).
Call `mem_update` with:
- `topic_key`: "pipeline/ISSUE_KEY/automated-spec-review"
- `title`: "Headless Stop — Spec Conflicts for ISSUE_KEY"
- `type`: manual
- `scope`: project
- `content`:
  **What**: Pipeline stopped in headless mode due to unresolved spec conflicts
  **Why**: HEADLESS mode; no human available to resolve conflicts
  **Where**: specs/issue-ISSUE_KEY-spec.md
  **Learned**: Conflicts: CHECK_OUTPUT

Stop the entire pipeline. Do not proceed to implementation, review, or PR creation.

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
📄 **Result hook (E6):** before this stop, write `specs/issue-ISSUE_KEY-result.json`
per §Step R — Result Contract with `outcome="stopped"`, `stage="spec"`,
`reason="Spec was not approved (human rejection at Step 3c)"`.
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
If FOUNDRY_MODE is `true`, run the C9 checkpoint push before proceeding.

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

If CRITICAL_COUNT > 0:
- If HEADLESS is `true`, print:
```
⚠️  ISSUE_KEY hit impl pass budget (MAX_IMPL_PASSES) with critical DoD failures.
    Headless mode: stopping and marking as Blocked.
```
  📄 **Result hook (E7):** before this stop, write `specs/issue-ISSUE_KEY-result.json`
  per §Step R — Result Contract with `outcome="stopped"`, `stage="dod"`,
  `reason="Critical DoD failures after MAX_IMPL_PASSES passes; headless stop (Blocked)"`.
  If FOUNDRY_MODE is `true`, run the Foundry Stop Protocol after this hook (close the PR + `Blocked`).
  Stop the entire pipeline.
- Otherwise, stop and ask:
```
⚠️  ISSUE_KEY hit impl pass budget (MAX_IMPL_PASSES) with critical DoD failures:
<list critical FAIL_REASON lines>

[C] Continue to test gate & code review anyway
[S] Stop here
```
If the user chose [S], write result.json per §Step R before printing the stop;
if [C], do not write — continue.
📄 **Result hook (E8):** before this stop, write `specs/issue-ISSUE_KEY-result.json`
per §Step R — Result Contract with `outcome="stopped"`, `stage="dod"`,
`reason="User chose [S] after critical DoD failures (Step 5d)"`.
If Stop, print `⚠️  Stopping /letsgo.` and end. If Continue, set DOD_CONTINUED = `true` and proceed to **Step 5b**.

---

## Step 5b — Convention-based test-suite gate

If MAKE_CI is `true`, look for a `make ci` target in the Makefile.
If found, set TEST_COMMAND = `make ci`, TEST_SOURCE = "make ci", and run it.
If not found:
📄 **Result hook (E9):** before this stop, write `specs/issue-ISSUE_KEY-result.json`
per §Step R — Result Contract with `outcome="stopped"`, `stage="tests"`,
`reason="--make-ci specified but no 'make ci' target found"`.
Print `⚠️  --make-ci specified but no 'make ci' target found. Stopping.`
and stop the pipeline.

Otherwise, look up the test command in this order (first match wins):

1. **AGENTS.md** — look for a `## Test` / `## Tests` / `## Testing` heading
2. **README.md** — same headings
3. **Makefile** — look for a `test:` target

If none of these yield a command, fall back to heuristics: `pytest tests/`, `npm test`, `go test ./...`, or `cargo test` based on project files.

If no test command found, print `ℹ️  No test command found. Skipping test gate.`, set TEST_RESULT = "skipped", TEST_SOURCE = "not found", proceed to **Step 6**.

Otherwise, record TEST_SOURCE and run tests.

### If tests pass
Print `✅ Tests passed (source: TEST_SOURCE).` Set TEST_RESULT = "passed", proceed to **Step 6**.

### If tests fail
Run a bounded fix loop (up to MAX_FIX_PASSES): invoke `@code-fixer` with test output; fall back to `@spec-implementer` if spec context needed (its prompt inherits the `debugging-and-error-recovery` skill — the fix must follow the diagnosis phases, not guess). Re-run tests after each fix.

If tests pass within budget, print `✅ Tests passed after N fix pass(es) (source: TEST_SOURCE).` Set TEST_RESULT = "passed-after-fix", proceed to **Step 6**.
If FOUNDRY_MODE is `true` and the fix loop committed, run the C9 checkpoint push before Step 6.

If tests still fail:
- If STRICT_TESTS is `true`:
  📄 **Result hook (E10):** before this stop, write `specs/issue-ISSUE_KEY-result.json`
  per §Step R — Result Contract with `outcome="stopped"`, `stage="tests"`,
  `reason="Tests still failing after MAX_FIX_PASSES fix passes; strict-tests stop"`.
  If FOUNDRY_MODE is `true`, run the Foundry Stop Protocol after this hook (close the PR + `Blocked`).
  Print `⚠️  Tests still failing after MAX_FIX_PASSES fix passes. Strict-tests mode: stopping.` and stop the pipeline.
- Otherwise, print `⚠️  Tests still failing after MAX_FIX_PASSES fix passes. Continuing to code review.` Set TEST_RESULT = "failed", proceed to **Step 6**.

---

## Step 6 — Three-axis code review

Review runs along three independent axes (Bugs, Standards, Spec), dispatched
as parallel subagents in Step 7a so they don't pollute each other's context.
Findings are never reranked across axes.

Collect the diff:

- **When BASE is set** (`BASE_REF=origin/<base>` was established in Step 0.1):
  ```bash
  git diff $(git merge-base HEAD $BASE_REF)..HEAD
  git log $(git merge-base HEAD $BASE_REF)..HEAD --oneline
  ```
- **When BASE is null** (default path — behavior unchanged):
  ```bash
  BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo main)
  [ -z "$BASE_BRANCH" ] && BASE_BRANCH=main
  git diff $(git merge-base HEAD $BASE_BRANCH)..HEAD
  git log $(git merge-base HEAD $BASE_BRANCH)..HEAD --oneline
  ```

If the diff is empty, print `✅ No changes detected vs BASE_BRANCH. Skipping review.`
and go to **Step 8**.

If fewer than 5 lines changed (additions + deletions), print
`ℹ️  Diff is trivial (<5 lines). Skipping code review.` and go to **Step 8**.
(Deliberate: spec-fidelity could flag missing requirements even on a small
diff, but the DoD gate at Step 5 already covers that case.)

Otherwise run the remediation loop below.

---

## Step 7 — Remediation loop

Initialize FIX_PASS = 1, ISSUES_REMAIN = true.

Repeat while ISSUES_REMAIN and FIX_PASS <= MAX_FIX_PASSES:

**7a — Review**

Dispatch the following subagent invocations **together, in a single message**,
so they run concurrently (same prompt shapes as `/review-code` Step 3):

1. `@code-reviewer` with the current diff and recent commits. Capture as BUGS_OUTPUT.
2. `@standards-reviewer` with the current diff and recent commits. Capture as STANDARDS_OUTPUT.
3. `@spec-fidelity-reviewer` with the current diff, recent commits, and:
   > Spec: `specs/issue-ISSUE_KEY-spec.md`
   Capture as SPEC_OUTPUT. (The spec always exists here — it was generated in
   Step 1 — so this axis always runs, in quick mode too, where the contract is
   the spec's `## What` / `## Done When` sections.)

Combine the three outputs with `## Bugs`, `## Standards`, `## Spec` markers
into REVIEWER_OUTPUT.

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
  **Why**: Three-axis code review (bugs / standards / spec fidelity) for ISSUE_KEY
  **Where**: Diff vs BASE_BRANCH
  **Learned**: FINAL_OUTPUT

If Engram MCP is unavailable, append to `specs/issue-ISSUE_KEY-progress.md`:
```markdown
## Code Review Pass FIX_PASS
FINAL_OUTPUT
```

**7d — Fix, if needed**

If ISSUES_REMAIN and FIX_PASS < MAX_FIX_PASSES, route findings by axis:

- Bugs and Standards findings → invoke `@code-fixer` with:
  > Address review findings for **ISSUE_KEY**: <bugs/standards findings from FINAL_OUTPUT>. Fix only what's listed. Read current state first.
- Spec findings (`missing-requirement | scope-creep | spec-drift`) always need
  spec context → invoke `@spec-implementer` with:
  > Address spec-fidelity review findings for **ISSUE_KEY**. Spec: `specs/issue-ISSUE_KEY-spec.md`. Findings: <spec findings from FINAL_OUTPUT>. Re-check against spec before resolving. Track progress.

If FOUNDRY_MODE is `true`, run the C9 checkpoint push after the fix pass commits.
Re-collect the diff (same commands as Step 6) before looping back to 7a, since
the fix pass changed it.

Increment FIX_PASS.

**7e — Exit or escalate**

If ISSUES_REMAIN == false, print:
```
✅ Code review clean for ISSUE_KEY (pass FIX_PASS-1/MAX_FIX_PASSES).
```
and proceed to **Step 8**.

If ISSUES_REMAIN == true after MAX_FIX_PASSES passes, count findings by severity: CRITICAL_FINDINGS, WARNING_FINDINGS, NITPICK_FINDINGS. (Smell findings are judgement calls — they count as warning or nitpick, never critical.)

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

Otherwise:
- If HEADLESS is `true`, print:
```
⚠️  ISSUE_KEY still has review findings after MAX_FIX_PASSES passes.
    Headless mode: stopping and marking as Needs Review.
```
  📄 **Result hook (E12):** before this stop, write `specs/issue-ISSUE_KEY-result.json`
  per §Step R — Result Contract with `outcome="stopped"`, `stage="review"`,
  `reason="Review findings unresolved after MAX_FIX_PASSES passes; headless stop (Needs Review)"`.
  If FOUNDRY_MODE is `true`, run the Foundry Stop Protocol after this hook (close the PR + `Blocked`).
  Stop the pipeline. Do NOT open a PR.
- Otherwise, stop and ask:
```
⚠️  ISSUE_KEY still has review findings after MAX_FIX_PASSES passes:
FINAL_OUTPUT

[C] Continue to PR creation anyway
[S] Stop here
```
If the user chose [S], write result.json per §Step R before printing the stop;
if [C], do not write — continue.
📄 **Result hook (E13):** before this stop, write `specs/issue-ISSUE_KEY-result.json`
per §Step R — Result Contract with `outcome="stopped"`, `stage="review"`,
`reason="User chose [S] after unresolved review findings (Step 7e)"`.
If Stop, print `⚠️  Stopping /letsgo.` and end. If Continue, set REVIEW_CONTINUED = `true` and proceed to **Step 8**.

---

## Step 7.5 — Post-review test re-run

If TEST_RESULT was "passed" or "passed-after-fix" from Step 5b, and code review
made changes (ISSUES_REMAIN was true at any point), re-run the test suite to
catch regressions introduced by code-fixer changes.

Run the same TEST_COMMAND from Step 5b.

If tests pass, print `✅ Post-review tests passed.` Set POST_REVIEW_TEST = "passed".
Proceed to **Step 8**.

If tests fail:
- Run a bounded fix loop (up to MAX_FIX_PASSES): invoke `@code-fixer` with test output; re-run tests after each fix.
- If tests pass within budget, print `✅ Post-review tests passed after N fix pass(es).` Set POST_REVIEW_TEST = "passed-after-fix", proceed to **Step 8**.
  If FOUNDRY_MODE is `true`, run the C9 checkpoint push after the fix loop commits.
- If STRICT_TESTS is `true` and tests still fail:
  📄 **Result hook (E11):** before this stop, write `specs/issue-ISSUE_KEY-result.json`
  per §Step R — Result Contract with `outcome="stopped"`, `stage="tests"` (the failing
  gate is the test gate), `reason="Post-review tests still failing; strict-tests stop (Step 7.5)"`.
  If FOUNDRY_MODE is `true`, run the Foundry Stop Protocol after this hook (close the PR + `Blocked`).
  Print `⚠️  Post-review tests still failing. Strict-tests mode: stopping.` and stop the pipeline.
- Otherwise, print `⚠️  Post-review tests still failing after fix passes. Continuing to PR creation (test result from Step 5b was green).` Set POST_REVIEW_TEST = "failed", proceed to **Step 8**.

If TEST_RESULT was "failed" or "skipped" from Step 5b, skip this step.
Set POST_REVIEW_TEST = "skipped".

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

Analyse the changes against the base:

- **When BASE is set** (`BASE_REF=origin/<base>` was established in Step 0.1):
  ```bash
  git status --short
  git branch --show-current
  git diff $(git merge-base HEAD $BASE_REF)..HEAD
  git log $(git merge-base HEAD $BASE_REF)..HEAD --oneline
  ```
- **When BASE is null** (default path — behavior unchanged):
  ```bash
  BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo main)
  [ -z "$BASE_BRANCH" ] && BASE_BRANCH=main
  git status --short
  git branch --show-current
  git diff $(git merge-base HEAD $BASE_BRANCH)..HEAD
  git log $(git merge-base HEAD $BASE_BRANCH)..HEAD --oneline
  ```

### 8b.5 — Feature branch verification

The feature branch was created in Step 0.1. Verify we are on it:
```bash
CURRENT_BRANCH=$(git branch --show-current)
```
If CURRENT_BRANCH equals the bare `BASE_BRANCH` name (compare against `BASE_BRANCH`,
never `BASE_REF` — this holds in both modes: default and `--base`) (unexpected — should
not happen), create it now:

- **When BASE is set** (create from the remote-tracking ref):
  ```bash
  FEATURE_BRANCH="feat/ISSUE_KEY-$(date +%Y%m%d%H%M%S)"
  git checkout -b $FEATURE_BRANCH $BASE_REF
  ```
- **When BASE is null** (default path — create from current HEAD):
  ```bash
  FEATURE_BRANCH="feat/ISSUE_KEY-$(date +%Y%m%d%H%M%S)"
  git checkout -b $FEATURE_BRANCH
  ```
Otherwise, continue on the existing FEATURE_BRANCH.

### 8c — Review and commit changes

If the working tree is clean, skip to 8d.

1. Print the full list of changed files from `git status --short`.
2. Scan for risk patterns: `.env`, `.env.*`, `*.pem`, `*.key`, `*credentials*`,
   `*secret*`, `.DS_Store`. If any risk-pattern file appears:
📄 **Result hook (E14):** before this stop, write `specs/issue-ISSUE_KEY-result.json`
per §Step R — Result Contract with `outcome="stopped"`, `stage="pr"`,
`reason="Sensitive-file pattern matched before commit"`.
Stop and print:
```
⚠️  <file> matches a sensitive-file pattern and is about to be committed.
    Remove it from the working tree or add it to .gitignore before re-running /letsgo.
```
If FOUNDRY_MODE is `true`, run the Foundry Stop Protocol after this hook (close the PR + `Blocked`).
3. If AUTO_COMMIT is `true` and no risk patterns detected:
   - Count the total changed files and total lines changed (additions + deletions).
     Exclude files under `specs/` from the count (spec artefacts are tracked separately).
   - If changed files > 50 OR total lines changed > 5000, print:
```
⚠️  Diff exceeds auto-commit thresholds (<N> files, <N> lines).
    Manual confirmation required.
```
     Then fall through to step 4 (manual confirmation).
    - Otherwise, generate a commit message from the diff and run
      `git add -A -- ':!specs/' && git commit -m "<message>"` without asking.
      Print `✅ Committed automatically (auto-commit on by default).`
      If FOUNDRY_MODE is `true`, run the C9 checkpoint push (the C10 scan already
      ran at step 2 above).
4. If AUTO_COMMIT is `false` (`--no-auto-commit`) or thresholds exceeded: generate a commit message
   from the diff, print it with the file list (excluding `specs/`), and ask the user to confirm
   before running `git add -A -- ':!specs/' && git commit`.
   If the user declines the confirmation:
   📄 **Result hook (E15):** before this stop, write `specs/issue-ISSUE_KEY-result.json`
   per §Step R — Result Contract with `outcome="stopped"`, `stage="pr"`,
   `reason="Manual commit confirmation declined (Step 8c)"`.
   Print `⚠️  Commit confirmation declined. Stopping /letsgo.` and stop the pipeline.

### 8d — Draft the PR description

Skip all preambles and keep prose brief. Use the project's domain language
(from `GLOSSARY.md` if it exists). Follow this template:

```markdown
## Summary

<the smallest visual that makes the key point clear: pseudocode for logic,
call tree for control flow, component/file tree for structure or broad
refactors, Mermaid for interaction/data flow, or a diff-shaped sketch when
the surrounding shape already exists. Place each visual next to the short
text it supports; use one or a few, not all.>

## Evidence

- **Before:** <from Step 5b: failing test output, or "tests passed first run (source: TEST_SOURCE)">
  **After:** <passing test output from Step 5b / Step 7.5 (POST_REVIEW_TEST); screenshots are S-tier for visual changes when available>

## Merge Danger

**Door:** <one-way | two-way>

<optional: one-sentence description>

**Blast Radius:** <one-word description>

<optional: potential ramifications of merge>

## Related Issues
- ISSUE_KEY

## Pipeline Notes
- <mention if spec was approved via automated conflict resolution vs human escalation>
- <mention if DoD or code review budgets were exhausted and continued on human override>
```

**Evidence rules**: never invent evidence — use the captured TEST_RESULT /
POST_REVIEW_TEST outputs and test names from Steps 5b and 7.5. If no automated
evidence exists (TEST_RESULT = "skipped"), state what is true (e.g. "no test
runner configured; DoD verified by @dod-evaluator").

**Merge Danger derivation (no human prompt — must work headless)**:
- **Door**: `one-way` if the diff contains destructive or hard-to-reverse
  changes — schema drops/destructive migrations, data deletion or transforms,
  removed public API, deleted files other consumers import, credential or
  permission changes. Otherwise `two-way`.
- **Blast Radius**: one word derived from the diff's reach — `none` (docs,
  comments), `single-module`, `cross-module`, `all-consumers` (public API),
  `schema` (database/migrations). Then optional ramifications.

Write it to `pr-description.md` in the repo root. Never commit this file.

### 8e — Create the PR

- **When FOUNDRY_MODE is `true`** — skip the create calls below: the mutex PR from
  Step 0.8 is the PR; proceed to Step 8e-L.
- **When BASE is set** (pass the bare branch name — gh resolves the PR target
  server-side; never pass `origin/<base>` or `$BASE_REF` to gh here):
  ```bash
  gh pr create --base "$BASE_BRANCH" --title "PR_TITLE" --body-file pr-description.md
  ```
- **When BASE is null** (default path — behavior unchanged; gh targets the repo
  default branch):
  ```bash
  gh pr create --title "PR_TITLE" --body-file pr-description.md
  ```

If `gh pr create` fails for any reason (including auth):
📄 **Result hook (E16):** before this stop, write `specs/issue-ISSUE_KEY-result.json`
per §Step R — Result Contract with `outcome="stopped"`, `stage="pr"`,
`reason="gh pr create failed: not authenticated"` when the failure is an auth
failure, else `reason="gh pr create failed: <error>"`, `pr_url=""`.
If FOUNDRY_MODE is `true`, run the Foundry Stop Protocol after this hook (close the PR + `Blocked`).
Stop and tell the user to run `gh auth login` on an auth failure, or report the
error otherwise.

### 8e-L — Foundry land path (FOUNDRY_MODE only)

Runs ONLY when FOUNDRY_MODE is `true`, after Step 8d has written `pr-description.md`
and Step 8c has committed and checkpoint-pushed. The mutex PR is the PR — this step
lands it. Order: update body → conditional ready → exactly one merge strategy.

1. Update the PR body:
```bash
timeout 120 gh pr edit "$PR_NUMBER" --body-file pr-description.md
```
2. Make ready only when the PR is still a draft — OD2: a resumed run may find it
   already non-draft (crash after a previous `ready`), so the step is guarded, not
   assumed:
```bash
[ "$(timeout 120 gh pr view "$PR_NUMBER" --json isDraft --jq '.isDraft')" = "true" ] && timeout 120 gh pr ready "$PR_NUMBER"
```
3. Merge with exactly one strategy, chosen by MERGE_MODE — never compose the squash
   or rebase variants, never retry a failed merge with a different strategy:
   - `--merge-mode auto` (default): `timeout 120 gh pr merge "$PR_NUMBER" --auto --merge`
   - `--merge-mode direct`: `timeout 120 gh pr merge "$PR_NUMBER" --merge`

The board stays `In Progress` — the host reconciler owns `Integrated` and merge
truth; `/letsgo` never writes either. Never add a `Closes: #N` trailer to any PR
body (merges target the base branch, not the default branch).

On any edit / ready / merge failure or timeout ⇒ 📄 **Result hook (E23):** before
this stop, write `specs/issue-ISSUE_KEY-result.json` per §Step R — Result Contract
with `outcome="stopped"`, `stage="pr"`, `reason="Land failed: <error>"`,
`branch=FEATURE_BRANCH`, `pr_url=PR_URL` — then the Foundry Stop Protocol:
close the PR (OD1 — a lingering open PR holds the mutex, even a ready one) and
set `Blocked`.

On success ⇒ 📄 **Result hook (E17-F):** write `specs/issue-ISSUE_KEY-result.json`
per §Step R — Result Contract with `outcome="pr_opened"`, `stage="pr"`,
`reason="PR opened successfully"`, `branch=FEATURE_BRANCH`, `pr_url=PR_URL` (the
existing mutex PR URL — no new PR was created) — then print the Step 9 report.
`/letsgo` reports the PR it opened and armed; it never claims a merge.

### 8f — Clean up

```bash
rm pr-description.md
```

---

## Step 9 — Final report

📄 **Result hook (E17):** on the success path, immediately after `gh pr create`
returned the PR URL (Step 8e) and before printing this report, write
`specs/issue-ISSUE_KEY-result.json` per §Step R — Result Contract with
`outcome="pr_opened"`, `stage="pr"`, `reason="PR opened successfully"`,
`branch=FEATURE_BRANCH`, and `pr_url` set to the URL gh returned.
When FOUNDRY_MODE is `true`, the E17-F hook (Step 8e-L) has already written the
result file with the mutex PR URL — no second create happened; print the report
below plus the Foundry line.
Print a summary of the whole run:
```
🎉 /letsgo complete for ISSUE_KEY

  Spec:          <auto-resolved in N turns | human-approved after escalation | trivial-change bypass | headless-stopped: conflicts>
  Implementation: <PASS in N passes | continued with unmet DoD items (non-critical only) | headless-stopped: DoD>
  Test suite:    <passed | passed-after-fix | failed | skipped> (source: TEST_SOURCE)
  Post-review:   <passed | passed-after-fix | failed | skipped>
  Code review:   <clean in N passes | continued with residual findings (within risk budget) | headless-stopped: review> (residual per axis: bugs=N standards=N spec=N)
  Branch:        <branch name>
  Base:          <BASE_EFFECTIVE — e.g. ai/integration, or default(origin/HEAD) when --base was omitted>
  PR:            <URL returned by gh pr create>
  Result:        specs/issue-ISSUE_KEY-result.json (outcome=pr_opened, stage=pr)
  Foundry: preflight=passed claim=In Progress mutex=<PR_URL or resumed> land=<armed | direct> (Foundry runs only)

See specs/issue-ISSUE_KEY-progress.md for the full audit trail.
```

If the pipeline stopped in headless mode at any point, print:
```
⚠️  Pipeline stopped in headless mode. See Engram or progress.md for the blocking reason.
    Issue remains on the board for human attention.
```
