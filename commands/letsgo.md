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

The auto-flow driver reads `specs/issue-ISSUE_KEY-result.json` to learn how the run ended. This section is the single canonical contract: every exit carries a `Result hook (E1)`…`Result hook (E17)` line stating its exact `outcome`/`stage`/`reason`.

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

1. **Path**: `specs/issue-ISSUE_KEY-result.json` (git-ignored, never committed).
2. **Overwrite**: last-run-wins; never append.
3. **Atomic**: one `write` call with the complete JSON (no partial writes, no shell echo).
4. **Write-before-stop**: write **immediately before** printing the stop message; on E17, after `gh pr create` returns and before the Step 9 report.
5. **A failed write must not crash the pipeline**: print `⚠️  Result file write failed: <error>. Continuing with the stop anyway.` and proceed — the driver derives `no_result` from the missing file.

### Standing rule

Any current or future stop in `/letsgo` — including exits not enumerated as
E1–E17 — MUST write `specs/issue-ISSUE_KEY-result.json` per this contract
before ending, choosing the `stage` of the phase being exited and a `reason`
that describes the stop. When adding a new exit point to this command, add its
`Result hook` line in the same edit.

### Comment mirror (surface op F3) — exactly one result comment (Foundry mode)

In Foundry mode every exit upserts one issue comment carrying `<!-- opencode-flow:result -->`. Run surface op **F3** with `$GH_OWNER`, `$GH_REPO`, `$GH_ISSUE_NUMBER`, `$RESULT_COMMENT_FILE`. Body: marker line first, then `outcome`, `stage`, `reason`, `branch`, `pr_url`, timestamp. F3 finds by marker → PATCH, else create. Token hygiene: no token value ever appears in argv, stdout, `result.json`, comments, or files — ambient `gh auth` only. Delete `result-comment.md` after upsert; never commit it.

### Foundry hooks (E18–E23, E17-F) — registered per the standing rule

Schema unchanged; each hook's full line lives at its exit point.

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

`$ARGUMENTS`: a light-spec path followed by optional flags in any order. Extract:
- **FILE_PATH**: first token.
- **ISSUE_KEY**: basename without `.md`; strip one leading `issue-`.
- **QUICK_MODE**: `true` if `--quick` appears.
- **HEADLESS**: `true` if `--headless` appears.
- **MAX_SPEC_TURNS**: after `--max-spec-turns`, else `3`.
- **MAX_IMPL_PASSES**: after `--max-impl-passes`, else `3`.
- **MAX_FIX_PASSES**: after `--max-fix-passes`, else `3`.
- **AUTO_COMMIT**: `true` unless `--no-auto-commit` appears (`--auto-commit` forces `true`).
- **RISK_BUDGET**: after `--risk-budget`, else `0` (0 = no auto-continue).
- **STRICT_TESTS**: `true` if `--strict-tests` or HEADLESS; `false` only with `--no-strict-tests`.
- **MAKE_CI**: `true` if `--make-ci` appears.
- **SPEC_CONFIDENCE**: float after `--spec-confidence`, else `0.0` (0.0 = escalate all conflicts; 0.8 = only confidence >= 0.8).
- **BASE**: token immediately after `--base`, else `null`; strip a leading `origin/` so both forms resolve to the bare branch. If `--base` has no following token or the next token starts with `--`:
  📄 **Result hook (E1):** before this stop, write `specs/issue-ISSUE_KEY-result.json` per §Step R with `outcome="stopped"`, `stage="spec"`, `reason="--base requires a branch name"`.
  Print `❌ --base requires a branch name (e.g. --base ai/integration).` and STOP (hard stop, headless-safe; do not consume the flag-like token). Set **BASE_EFFECTIVE** = `BASE` if not null, else `default(origin/HEAD)`. BASE resolves once here and in Step 0.1 into `BASE_BRANCH`/`BASE_REF` (used by 0.1, 6, 7d, 8b, 8b.5, 8e, 9).
- **MERGE_MODE**: the token immediately after `--merge-mode` if present, else `auto`. Valid values: `auto`, `direct`. If absent, empty, flag-like, or invalid:
  📄 **Result hook (E18):** before this stop, write `specs/issue-ISSUE_KEY-result.json` per §Step R with `outcome="stopped"`, `stage="spec"`, `reason="--merge-mode requires auto or direct"`, `branch=""`, `pipeline` omitted.
  Print `❌ --merge-mode requires auto or direct (e.g. --merge-mode auto).` and STOP (hard stop, headless-safe; do not consume the flag-like token).
- **FOUNDRY_MODE**: `true` if and only if HEADLESS is `true` AND BASE is not `null`; else `false`. Activates Steps 0.6/0.7/0.1-F/0.8, the Push Protocol, Step 8e-L, and the Foundry Stop Protocol. Any other combination takes the interactive path, byte-for-byte unchanged.

**Load skill (AC1):** Foundry mode loads the shared surface:
```
Load skill: foundry-headless-contract
```
Reference operations F1–F4 from the skill; do not duplicate inline `gh project` recipes. `--quick` remains allowed in Foundry mode (it only skips the spec review gate; FR14).

## Step 0.5 — GitHub issue detection & materialize

If the first token matches `^[0-9]+$`, treat it as a GitHub issue: **ISSUE_NUMBER** = token; **ISSUE_KEY** = its string; **FILE_PATH** = `specs/{ISSUE_KEY}.md`.

```bash
gh issue view <ISSUE_NUMBER> --json number,title,body,url,state
```
- Unauthenticated/failure:
📄 **Result hook (E2):** before this stop, write `specs/issue-ISSUE_KEY-result.json` per §Step R with `outcome="stopped"`, `stage="spec"`, `reason="Could not fetch GitHub issue"`.
Stop and print:
```
❌ Could not fetch GitHub issue #<ISSUE_NUMBER>. Run `gh auth login` or verify the issue exists.
```
- `state == CLOSED` → non-blocking warning:
```
⚠️  GitHub issue #<ISSUE_NUMBER> is closed. Proceeding anyway.
```

Materialize: if `FILE_PATH` exists, use it as-is (no overwrite) → Step 1. Else write:
```markdown
# {ISSUE_KEY}

<!-- Source: GitHub Issue #{ISSUE_KEY} — {url} -->

## Title
{issue title}

## Body
{issue body, verbatim}
```
→ Step 1.

Non-numeric first token → skip this step and continue with Step 0's FILE_PATH/ISSUE_KEY.

## Step 0.5b — Verify spec file (common gate)

After Step 0.5 resolves FILE_PATH and ISSUE_KEY, verify FILE_PATH exists and is readable. Not:
📄 **Result hook (E3):** before this stop, write `specs/issue-ISSUE_KEY-result.json` per §Step R with `outcome="stopped"`, `stage="spec"`, `reason="File not found"` (use the numeric first token as `issue`).
Stop and print:
```
❌ File not found: <FILE_PATH>
```

Banner:
```
🚀 /letsgo issue-ISSUE_KEY | quick=QUICK_MODE headless=HEADLESS base=BASE_EFFECTIVE foundry=FOUNDRY_MODE merge-mode=MERGE_MODE spec-turns=MAX_SPEC_TURNS impl-passes=MAX_IMPL_PASSES fix-passes=MAX_FIX_PASSES auto-commit=AUTO_COMMIT risk-budget=RISK_BUDGET strict-tests=STRICT_TESTS make-ci=MAKE_CI spec-confidence=SPEC_CONFIDENCE
```

## Step 0.6 — Foundry preflight (fail closed)

Runs ONLY when FOUNDRY_MODE is `true`, after the Step 0.5b banner and before Step 0.1. No write of any kind (branch, commit, push, board, spec) happens until this passes.

📄 **Result hook (E19):** before this stop, write `specs/issue-ISSUE_KEY-result.json` per §Step R with `outcome="stopped"`, `stage="spec"`, `reason="Foundry preflight failed: <specific>"`, `branch=""`, `pr_url=""`, `pipeline` omitted — then run the Foundry Stop Protocol (pre-mutex: no PR, no close).

**Live body (OD3):** parse the LIVE GitHub issue body, never the possibly-stale materialized file:
```bash
timeout 120 gh issue view <ISSUE_NUMBER> --json body --jq '.body'
```
Unset ISSUE_NUMBER (file-path under FOUNDRY_MODE), failure, or timeout ⇒ E19.

**F1 — project discovery:** exactly one node ⇒ bind PROJECT_NUMBER/PROJECT_OWNER (URL fallback). Zero or ≥2 ⇒ E19 (no writes, no `Blocked`).

**F2 — field precheck:** `Status` must be a single-select with exact `In Progress` and `Blocked` (plus readable `Ready`/`Integrated`). Any missing field/option ⇒ E19. Never create or rename options (contrast: `/brainstorm` provisions interactively).

**Foundry fit:** the live body must contain `## Foundry fit` with the exact line `Fit: yes` (2026-10-28 contract). Missing or `Fit: no` ⇒ E19.

**Blocked by:** accepted ref grammar is ONLY same-repo `#<N>` and external `OWNER/REPO#<N>` list refs (`- #<N> — <title>` / `- OWNER/REPO#<N> — <title>`); anything else — bare `N`, URL, `ISSUE-123` — fails closed ⇒ E19. `None — can start immediately` means no blockers. Resolve each ref:
- **C3 GitHub state:**
```bash
timeout 120 gh issue view <M> --json state
timeout 120 gh issue view <M> -R <OWNER>/<REPO> --json state
```
Pass ⇔ `CLOSED` (or `MERGED` for a merged PR).
- **C4 board Status (same-repo OPEN refs only):** `Integrated` is same-repo only; an external OPEN ref fails. Read the blocker's Status via GraphQL (canonical per `specs/issue-13-extdocs.md`). Pass ⇔ a node with `field.name == "Status"` and `name == "Integrated"` (exact, case-sensitive). Any other value, zero Status nodes, or query error ⇒ E19.

An unresolved blocker ⇒ E19. Every call is `timeout 120`; a timeout is that command's failure ⇒ E19, no blind retry.

## Step 0.7 — Board claim (In Progress)

Runs ONLY when FOUNDRY_MODE is `true`, immediately after Step 0.6 passes and before Step 0.1 — the claim is written before the first `git checkout -b`, commit, or push (AC2).
Run surface op **F2** with `$TARGET_STATUS` = `In Progress` (exact, case-sensitive). **Never write `Ready` or `Integrated`** — `Ready` is /brainstorm-owned and `Integrated` is the host reconciler's; `Blocked` only via the Foundry Stop Protocol.

On write error or timeout ⇒ 📄 **Result hook (E20):** before this stop, write `specs/issue-ISSUE_KEY-result.json` per §Step R with `outcome="stopped"`, `stage="spec"`, `reason="Board claim failed: <error>"`, `branch=""`, `pr_url=""`, `pipeline` omitted — then the Foundry Stop Protocol (its `Blocked` attempt still runs where the board is reachable).

## Foundry Stop Protocol (single definition)

Every Foundry-mode stop from Step 0.6 onward executes this protocol, in order. It is defined once here and referenced by each stop — stops do NOT restate it:

1. **Result file** — write `specs/issue-ISSUE_KEY-result.json` per the stop's `Result hook` line, before any message prints.
2. **Comment mirror** — upsert the single marker comment per C11: find by marker, PATCH if found, else create — exactly one, never a duplicate.
3. **Close the PR if one exists** — `timeout 120 gh pr close "$PR_NUMBER"`, only when the mutex PR exists (Step 0.8 onward). Pre-mutex stops (E19/E20/E21) skip this.
4. **Board release** — set the item to `Blocked` (surface op **F2** with `$TARGET_STATUS` = `Blocked`). If PROJECT_NUMBER/PROJECT_OWNER were never resolved or the write fails, record the error and continue — never abort mid-stop.
5. **Stop message** — print the distinct Foundry anchor: post-mutex stops print `Foundry mode: stopping, closing the draft PR and marking the issue as Blocked.`; pre-mutex stops print `Foundry mode: stopping and marking the issue as Blocked.` — then STOP. These strings replace the interactive/headless stop shapes; frozen anchors keep their occurrence counts.

The board is left `In Progress` on success — `/letsgo` never writes `Integrated` (the reconciler observes the merge and owns that transition).

### Step 0.1 — Create feature branch up front

Resolve the base branch and remote-tracking ref used by Steps 6, 7d, 8b, 8b.5, 8e, 9. Use exactly one path.

**When BASE is set** (normalized in Step 0 — leading `origin/` stripped):
```bash
BASE_BRANCH=<BASE>
BASE_REF=origin/$BASE_BRANCH
git fetch origin $BASE_BRANCH
```
Non-zero fetch (e.g. `couldn't find remote ref`):
📄 **Result hook (E4):** before this stop, write `specs/issue-ISSUE_KEY-result.json` per §Step R with `outcome="stopped"`, `stage="spec"`, `reason="Remote branch not found (fetch failed)"`, `branch=""`, `pipeline` omitted. Print `❌ Remote branch origin/<BASE> not found (fetch failed). Stopping.` and STOP before implementation (hard stop, headless-safe).
If the current branch equals BASE_BRANCH:
```bash
FEATURE_BRANCH="feat/ISSUE_KEY-$(date +%Y%m%d%H%M%S)"
git checkout -b $FEATURE_BRANCH $BASE_REF
```
Print `✅ Created feature branch $FEATURE_BRANCH from origin/$BASE_BRANCH.`
If already on a different non-base branch, use it as-is and set FEATURE_BRANCH to the current branch name — `BASE_REF` still points at `origin/<BASE>`.

**Step 0.1-F — Foundry branch variant (FOUNDRY_MODE only).** When FOUNDRY_MODE is `true`, this variant OVERRIDES the reuse sentence above — a non-base branch is never reused. After the fetch, `CURRENT_BRANCH=$(git branch --show-current)`:
- equals BASE_BRANCH → create from the remote-tracking ref:
```bash
FEATURE_BRANCH="feat/<N>-$(date +%Y%m%d%H%M%S)"
git checkout -b $FEATURE_BRANCH $BASE_REF
```
`<N>` is ISSUE_NUMBER (Foundry invocations are always numeric). Verify AC3: `git merge-base HEAD $BASE_REF` must equal `$(git rev-parse $BASE_REF)`; mismatch ⇒ E21.
- not BASE_BRANCH → RESUME_CHECK — never reuse it:
```bash
gh pr list --state open --json number,url,headRefName,isDraft --jq '[.[] | select(.headRefName | test("^feat/<N>-[0-9]{14}$"))]'
```
Exactly 1 match ⇒ adopt its `headRefName` as FEATURE_BRANCH and `number`/`url` as PR_NUMBER/PR_URL, then check out the tracking branch (`timeout 120 git fetch origin $FEATURE_BRANCH && timeout 120 git checkout $FEATURE_BRANCH`); Step 0.8 is skipped (PR exists; FR10 forbids a second). 0 or ≥2 matches ⇒ E21 fail-closed.

📄 **Result hook (E21):** before this stop, write `specs/issue-ISSUE_KEY-result.json` per §Step R with `outcome="stopped"`, `stage="spec"`, `reason="Branch safety stop: non-base branch not reused / resume ambiguity"`, `branch=""` (or FEATURE_BRANCH when the create path ran), `pr_url=""`, `pipeline` omitted — then the Foundry Stop Protocol (pre-mutex: comment + `Blocked`; no close).

**When BASE is null** (default path — behavior unchanged):
```bash
BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo main)
[ -z "$BASE_BRANCH" ] && BASE_BRANCH=main
```
Bind `BASE_REF=$BASE_BRANCH` (bare derived name — no `origin/` prefix, no `git fetch`, so later git commands emit exactly what they did before).
If the current branch equals BASE_BRANCH:
```bash
FEATURE_BRANCH="feat/ISSUE_KEY-$(date +%Y%m%d%H%M%S)"
git checkout -b $FEATURE_BRANCH
```
Print `✅ Created feature branch $FEATURE_BRANCH from origin/$BASE_BRANCH.`
If already on a non-default branch, use it as-is and set FEATURE_BRANCH to the current branch name.

Store BASE_BRANCH, BASE_REF, FEATURE_BRANCH for later steps.

## Step 0.8 — Draft-PR mutex (Foundry concurrency lock)

Runs ONLY when FOUNDRY_MODE is `true`, immediately after Step 0.1-F and before Step 0.25. This is the concurrency lock — the draft PR exists before any implementation commit (AC4). Skipped on a resumed run whose PR already exists (Step 0.1-F adopted one) — never open a second PR (FR10).

Write `pr-mutex-body.md` with `Foundry run in progress — pipeline results land here` (final body at Step 8e-L; delete the file after create, never commit), then:
```bash
git commit --allow-empty -m "chore(letsgo): reserve PR mutex for issue <N>"
```
Run the C10 pre-push scan (a match blocks the push), then push and create the draft:
```bash
timeout 120 git push -u origin "$FEATURE_BRANCH"
gh pr create --draft --base "$BASE_BRANCH" --title "ISSUE_KEY: <short summary>" --body-file pr-mutex-body.md
```
Capture PR_URL/PR_NUMBER. The create call takes only the bare `$BASE_BRANCH`: git plumbing consumes `$BASE_REF`; gh never does.

On empty-commit failure, C10 match, push rejection, create failure, or timeout ⇒ 📄 **Result hook (E22):** before this stop, write `specs/issue-ISSUE_KEY-result.json` per §Step R with `outcome="stopped"`, `stage="pr"`, `reason="Draft-PR mutex failed: <error>"`, `branch=FEATURE_BRANCH`, `pr_url=""` unless the PR was created, `pipeline` omitted — then the Foundry Stop Protocol (close the PR iff created; `Blocked`).

## Push Protocol (Foundry mode)

The `/letsgo` governor owns every `git push` — dispatched subagents commit only (see `agents/spec-implementer.md`).

- **Checkpoint pushes (C9):** `timeout 120 git push origin "$FEATURE_BRANCH"` after each commit-producing stage: Step 5 pass end, Step 5b fix-loop end (if committed), Step 7d fix pass end, Step 7.5 fix-loop end, Step 8c final commit. Per-stage, not per-commit.
- **No force-push:** force-push in any form is forbidden everywhere in `/letsgo`. A rejected non-force push means another writer holds the branch — treat it as that stage's failure (mutex ⇒ E22; later ⇒ their hook) and run the Foundry Stop Protocol. Never retry with a forced push.
- **Scan-before-every-push (C10):** before EVERY push, check staged and working-tree paths against `.env*`, `*.pem`, `*.key`, `*credentials*`, `*secret*`, `.DS_Store` via `git status --short` and `git diff --cached --name-only`. A match ⇒ stop at the current stage with `reason="Sensitive-file pattern matched before push"`, then the Foundry Stop Protocol (close PR + `Blocked` post-mutex).
- **Timeout bounds (C13):** every git/gh network call in Foundry mode is wrapped `timeout 120 ...` (or `gtimeout 120 ...` — see `specs/issue-13-extdocs.md`); a timeout is that command's failure ⇒ its hook + the Foundry Stop Protocol, never a blind retry.

### Step 0.25 — Trivial-change detection

If `## Title` or `## Body` in FILE_PATH contains any (case-insensitive) of `typo`, `rename`, `reorder`, `bump version`, `update version`, `whitespace`, `format`, `trailing`, `remove unused`, `fix typo`, AND the body is a single-file or single-line change, TRIVIAL_MODE = `true`; else `false`.

TRIVIAL_MODE `true` and QUICK_MODE `false` → print:
```
ℹ️  Trivial change detected. Skipping spec review gate.
```
Set SKIP_SPEC_REVIEW = `true`. This does NOT skip spec generation (Step 1) — only Steps 2–3.

---

## Step 1 — Analyze issue

QUICK_MODE `true` → `@spec-analyst-quick`:
> Generate a fast-path spec for issue **ISSUE_KEY** from `FILE_PATH`. Store outputs under `specs/`. Follow the spec-driven-workflow skill exactly.

QUICK_MODE `false` → `@spec-analyst`:
> Generate a full 6-phase spec for issue **ISSUE_KEY** from `FILE_PATH`. Store outputs under `specs/`. Follow the spec-driven-workflow skill exactly.

Print:
```
✅ Spec ready: specs/issue-ISSUE_KEY-{findings,progress,spec}.md
```

QUICK_MODE or SKIP_SPEC_REVIEW `true` → **Step 4** (skip the review gate).

---

## Step 2 — Automated spec conflict resolution (full mode only)

Initialize AUTO_TURN = 1, VERDICT = "CONFLICTS", MAX_SEVERITY = "none".

Repeat while VERDICT == "CONFLICTS" and AUTO_TURN <= MAX_SPEC_TURNS:

### 2a — Check

Invoke `@spec-conflict-checker`:
> Check issue **ISSUE_KEY** for conflicts.
> Spec: `specs/issue-ISSUE_KEY-spec.md`

Parse CHECK_OUTPUT: starts with `CLEAR` → VERDICT = "CLEAR"; starts with `CONFLICTS` → VERDICT = "CONFLICTS" and MAX_SEVERITY = highest of `critical` > `warning` > `cosmetic` (untagged = `warning`).

### 2b — Log the turn

Call `mem_update` with `topic_key: "pipeline/ISSUE_KEY/automated-spec-review"`, `title: "Automated Spec Review — Turn AUTO_TURN for ISSUE_KEY"`, `type: manual`, `scope: project`, content What/Why/Where/Learned (Learned = CHECK_OUTPUT). Engram unavailable → append the same block to `specs/issue-ISSUE_KEY-progress.md`.

### 2c — Revise on conflict

If VERDICT == "CONFLICTS" and AUTO_TURN < MAX_SPEC_TURNS, invoke `@spec-analyst`:
> Revise the spec for issue **ISSUE_KEY** to resolve these automated conflict findings. Existing spec: `specs/issue-ISSUE_KEY-spec.md`.
> Existing progress: `specs/issue-ISSUE_KEY-progress.md`.
> Conflicts to resolve:
> CHECK_OUTPUT
> Regenerate only affected sections. Do not discard unrelated work. Update progress.md with the revised sections.

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
  Log the auto-approval via `mem_update` with `topic_key: "pipeline/ISSUE_KEY/automated-spec-review"`, `title: "Automated Spec Review — Auto-approved for ISSUE_KEY"`, `type: manual`, `scope: project`, content What/Why/Where/Learned (Learned = auto-approved after budget exhaustion). Engram unavailable → append the same block to `progress.md`.
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
📄 **Result hook (E5):** before this stop, write `specs/issue-ISSUE_KEY-result.json` per §Step R with `outcome="stopped"`, `stage="spec"`, `reason="Spec conflicts unresolved after MAX_SPEC_TURNS automated turns; headless stop (Blocked)"`.
If FOUNDRY_MODE is `true`, run the Foundry Stop Protocol after this hook (close the PR + `Blocked`).
Call `mem_update` with `topic_key: "pipeline/ISSUE_KEY/automated-spec-review"`, `title: "Headless Stop — Spec Conflicts for ISSUE_KEY"`, `type: manual`, `scope: project`, content What/Why/Where/Learned (Learned = `Conflicts: CHECK_OUTPUT`).

Stop the entire pipeline. Do not proceed to implementation, review, or PR creation.

### 3.0 — decisions.md fallback

If `decisions.md` exists and a `Decision` conflict is unambiguously covered by a matching decision, apply it:
1. Invoke `@spec-analyst`:
> Apply the existing decision from `decisions.md` to resolve the conflict in the spec for issue **ISSUE_KEY**. Existing spec: `specs/issue-ISSUE_KEY-spec.md`.
> Conflict: <specific conflict from CHECK_OUTPUT>
> Applicable decision: <paste matching entry>
> Update only the conflicting section.
2. Re-invoke `@spec-conflict-checker`. If `CLEAR`, print `✅ Spec for ISSUE_KEY resolved via decisions.md.` and proceed to **Step 4**.

Otherwise present the spec as `/review-spec` does (read it in full, show CHECK_OUTPUT), then ask:
```
How would you like to proceed?
  [A] Approve as-is
  [R] Request changes
  [J] Reject
```

### 3a — On approval

Call `mem_update` with `topic_key: "pipeline/ISSUE_KEY/human-review"`, `title: "Human Review — Approved for ISSUE_KEY"`, `type: manual`, `scope: project`, content What/Why/Where/Learned (Learned = user approved after MAX_SPEC_TURNS unresolved conflicts). Engram unavailable → append to `progress.md`:
```markdown
## Human Review
- [x] Approved by user on <YYYY-MM-DD> (after MAX_SPEC_TURNS unresolved automated conflicts)
```
Print `✅ Spec approved for ISSUE_KEY.` and proceed to **Step 4**.

### 3b — On request changes

1. Collect free-text feedback; re-prompt if empty.
2. Invoke `@spec-analyst` with the `/review-spec` Step 5b revision contract and the feedback.
3. Re-present changed sections and return to the decision prompt. This human loop is not subject to MAX_SPEC_TURNS.

### 3c — On rejection (or no resolution reached)

Do NOT delete any files. Print:
```
⚠️  Spec for ISSUE_KEY was not approved. Stopping /letsgo.
    Files remain on disk as an audit trail under specs/.
```
📄 **Result hook (E6):** before this stop, write `specs/issue-ISSUE_KEY-result.json` per §Step R with `outcome="stopped"`, `stage="spec"`, `reason="Spec was not approved (human rejection at Step 3c)"`.
Stop the entire pipeline. Do not proceed to implementation, review, or PR creation.

---

## Step 4 — Fetch external documentation

Invoke `@external-scout`:
> Fetch external dependency docs for issue **ISSUE_KEY**.
> Spec: `specs/issue-ISSUE_KEY-spec.md`

`NO_EXTERNAL_DEPS` → continue. Otherwise `specs/issue-ISSUE_KEY-extdocs.md` is written for the implementer.

---

## Step 5 — Implementation

### QUICK_MODE `true`

Invoke `@spec-implementer`:
> Implement issue **ISSUE_KEY** from `specs/issue-ISSUE_KEY-spec.md`. Track progress. Follow the skill exactly.

Print `✅ Implementation complete for ISSUE_KEY.` → **Step 5b**.

### QUICK_MODE `false` — DoD-gated loop

IMPL_PASS = 1, DOD_VERDICT = "FAIL". Repeat while DOD_VERDICT == "FAIL" and IMPL_PASS <= MAX_IMPL_PASSES:

**5a — Implement pass**

Pass 1:
> Implement issue **ISSUE_KEY** from `specs/issue-ISSUE_KEY-spec.md`. Track progress. Follow the skill exactly.

Later passes:
> Resume **ISSUE_KEY** from `specs/issue-ISSUE_KEY-spec.md`. Previous DoD failures: <FAIL_REASON>. Address only failing items. Track progress.

**5b — Evaluate**

Invoke `@dod-evaluator`:
> Evaluate the Definition of Done for issue **ISSUE_KEY**.
> Spec: `specs/issue-ISSUE_KEY-spec.md`
> Progress: `specs/issue-ISSUE_KEY-progress.md`

DOD_VERDICT = "PASS" if the response starts with `PASS`, else "FAIL"; on FAIL capture failure lines as FAIL_REASON.

**5c — Log the pass**

`mem_update` with `topic_key: "pipeline/ISSUE_KEY/impl-passes"`, `title: "Implementation Loop Pass IMPL_PASS — <PASS or FAIL> for ISSUE_KEY"`, `type: manual`, `scope: project`, content What/Why/Where/Learned (Learned = EVALUATOR_OUTPUT). Engram unavailable → append `## Loop Pass IMPL_PASS — <PASS or FAIL>` + evaluator output to `progress.md`. Increment IMPL_PASS.

**5d — Exit or escalate**

PASS:
```
✅ Implementation complete for ISSUE_KEY (pass IMPL_PASS-1/MAX_IMPL_PASSES). All DoD items satisfied.
```
→ **Step 5b** (test gate). If FOUNDRY_MODE is `true`, run the C9 checkpoint push before proceeding.

FAIL after MAX_IMPL_PASSES: classify **critical** (core functionality, security, data integrity) vs **non-critical** (edge cases, docs, naming, non-core gaps); count CRITICAL_COUNT.

CRITICAL_COUNT == 0 → print `ℹ️  ISSUE_KEY impl budget exhausted but only non-critical DoD items remain. Auto-continuing.`, log via `mem_update` (`topic_key: "pipeline/ISSUE_KEY/dod-budget"`, `title: "DoD Budget Exhausted — Auto-continue for ISSUE_KEY"`, `type: manual`, `scope: project`, Learned = remaining non-critical summaries); Engram unavailable → same block in `progress.md`. Set DOD_CONTINUED = `true` → **Step 5b**.

CRITICAL_COUNT > 0:
- HEADLESS `true`:
```
⚠️  ISSUE_KEY hit impl pass budget (MAX_IMPL_PASSES) with critical DoD failures.
    Headless mode: stopping and marking as Blocked.
```
  📄 **Result hook (E7):** before this stop, write `specs/issue-ISSUE_KEY-result.json` per §Step R with `outcome="stopped"`, `stage="dod"`, `reason="Critical DoD failures after MAX_IMPL_PASSES passes; headless stop (Blocked)"`.
  If FOUNDRY_MODE is `true`, run the Foundry Stop Protocol after this hook (close the PR + `Blocked`).
  Stop the pipeline.
- Otherwise ask:
```
⚠️  ISSUE_KEY hit impl pass budget (MAX_IMPL_PASSES) with critical DoD failures:
<list critical FAIL_REASON lines>

[C] Continue to test gate & code review anyway
[S] Stop here
```
[S] stop:
📄 **Result hook (E8):** before this stop, write `specs/issue-ISSUE_KEY-result.json` per §Step R with `outcome="stopped"`, `stage="dod"`, `reason="User chose [S] after critical DoD failures (Step 5d)"`.
Print `⚠️  Stopping /letsgo.` and end. [C] → DOD_CONTINUED = `true` → **Step 5b** (no result write).

---

## Step 5b — Convention-based test-suite gate

If MAKE_CI is `true`, look for a `make ci` target. Found → TEST_COMMAND = `make ci`, TEST_SOURCE = "make ci", run it. Not found:
📄 **Result hook (E9):** before this stop, write `specs/issue-ISSUE_KEY-result.json` per §Step R with `outcome="stopped"`, `stage="tests"`, `reason="--make-ci specified but no 'make ci' target found"`.
Print `⚠️  --make-ci specified but no 'make ci' target found. Stopping.` and stop.

Otherwise find the test command (first match wins): `## Test`/`## Tests`/`## Testing` in `AGENTS.md`, then `README.md`; then a `test:` target in `Makefile`; else heuristics (`pytest tests/`, `npm test`, `go test ./...`, `cargo test`).

No command → print `ℹ️  No test command found. Skipping test gate.`, TEST_RESULT = "skipped", TEST_SOURCE = "not found", go to **Step 6**. Else record TEST_SOURCE and run.

### If tests pass
Print `✅ Tests passed (source: TEST_SOURCE).` TEST_RESULT = "passed", go to **Step 6**.

### If tests fail
Bounded fix loop (up to MAX_FIX_PASSES): `@code-fixer` with test output; `@spec-implementer` if spec context is needed (it inherits the `debugging-and-error-recovery` skill — diagnose, don't guess). Re-run tests after each fix.

Pass within budget → print `✅ Tests passed after N fix pass(es) (source: TEST_SOURCE).`, TEST_RESULT = "passed-after-fix", go to **Step 6**. If FOUNDRY_MODE is `true` and the fix loop committed, run the C9 checkpoint push before Step 6.

Still failing:
- STRICT_TESTS `true`:
  📄 **Result hook (E10):** before this stop, write `specs/issue-ISSUE_KEY-result.json` per §Step R with `outcome="stopped"`, `stage="tests"`, `reason="Tests still failing after MAX_FIX_PASSES fix passes; strict-tests stop"`.
  If FOUNDRY_MODE is `true`, run the Foundry Stop Protocol after this hook (close the PR + `Blocked`).
  Print `⚠️  Tests still failing after MAX_FIX_PASSES fix passes. Strict-tests mode: stopping.` and stop.
- Otherwise print `⚠️  Tests still failing after MAX_FIX_PASSES fix passes. Continuing to code review.`, TEST_RESULT = "failed", go to **Step 6**.

---

## Step 6 — Three-axis code review

Three independent axes (Bugs, Standards, Spec), dispatched in parallel in Step 7a; findings are never reranked across axes.

Collect the diff:
- **BASE set** (`BASE_REF=origin/<base>` from Step 0.1):
  ```bash
  git diff $(git merge-base HEAD $BASE_REF)..HEAD
  git log $(git merge-base HEAD $BASE_REF)..HEAD --oneline
  ```
- **BASE null** (default path):
  ```bash
  BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo main)
  [ -z "$BASE_BRANCH" ] && BASE_BRANCH=main
  git diff $(git merge-base HEAD $BASE_BRANCH)..HEAD
  git log $(git merge-base HEAD $BASE_BRANCH)..HEAD --oneline
  ```

Empty diff → `✅ No changes detected vs BASE_BRANCH. Skipping review.` → **Step 8**.
Fewer than 5 changed lines → `ℹ️  Diff is trivial (<5 lines). Skipping code review.` → **Step 8**.
Otherwise run the remediation loop.

---

## Step 7 — Remediation loop

Initialize FIX_PASS = 1, ISSUES_REMAIN = true.

Repeat while ISSUES_REMAIN and FIX_PASS <= MAX_FIX_PASSES:

**7a — Review**

Dispatch **together, in a single message** (same prompt shapes as `/review-code` Step 3):
1. `@code-reviewer` with the current diff and recent commits → BUGS_OUTPUT.
2. `@standards-reviewer` with the current diff and recent commits → STANDARDS_OUTPUT.
3. `@spec-fidelity-reviewer` with the current diff, recent commits, and:
   > Spec: `specs/issue-ISSUE_KEY-spec.md`
   → SPEC_OUTPUT. The spec always exists (Step 1), so this axis always runs, including quick mode where the contract is `## What` / `## Done When`.

Combine with `## Bugs`, `## Standards`, `## Spec` markers into REVIEWER_OUTPUT.

Invoke `@code-review-filter` with REVIEWER_OUTPUT and the diff (same shape as `/review-code` Step 4) → FINAL_OUTPUT.

**7b — Check for issues**

If FINAL_OUTPUT contains `0 issues flagged`, set ISSUES_REMAIN = false.

**7c — Log the pass**

Call `mem_update` with `topic_key: "pipeline/ISSUE_KEY/code-review"`, `title: "Code Review Pass FIX_PASS for ISSUE_KEY"`, `type: manual`, `scope: project`, content What/Why/Where/Learned (Learned = FINAL_OUTPUT). Engram unavailable → append `## Code Review Pass FIX_PASS` + FINAL_OUTPUT to `progress.md`.

**7d — Fix, if needed**

If ISSUES_REMAIN and FIX_PASS < MAX_FIX_PASSES, route by axis:
- Bugs/Standards → `@code-fixer`:
  > Address review findings for **ISSUE_KEY**: <bugs/standards findings from FINAL_OUTPUT>. Fix only what's listed. Read current state first.
- Spec findings (`missing-requirement | scope-creep | spec-drift`) → `@spec-implementer`:
  > Address spec-fidelity review findings for **ISSUE_KEY**. Spec: `specs/issue-ISSUE_KEY-spec.md`. Findings: <spec findings from FINAL_OUTPUT>. Re-check against spec before resolving. Track progress.

If FOUNDRY_MODE is `true`, run the C9 checkpoint push after the fix pass commits. Re-collect the diff (same commands as Step 6) before looping to 7a.

Increment FIX_PASS.

**7e — Exit or escalate**

If ISSUES_REMAIN == false, print:
```
✅ Code review clean for ISSUE_KEY (pass FIX_PASS-1/MAX_FIX_PASSES).
```
and proceed to **Step 8**.

If ISSUES_REMAIN == true after MAX_FIX_PASSES passes, count findings by severity: CRITICAL_FINDINGS, WARNING_FINDINGS, NITPICK_FINDINGS. (Smell findings are judgement calls — they count as warning or nitpick, never critical.)

If RISK_BUDGET > 0 and CRITICAL_FINDINGS == 0 and (WARNING_FINDINGS + NITPICK_FINDINGS) <= RISK_BUDGET, print `ℹ️  ISSUE_KEY code review within risk budget. Auto-continuing.`, call `mem_update` with `topic_key: "pipeline/ISSUE_KEY/code-review"`, `title: "Code Review — Auto-continue within risk budget for ISSUE_KEY"`, `type: manual`, `scope: project`, content What/Why/Where/Learned (Learned = residual WARNING_FINDINGS warning(s), NITPICK_FINDINGS nitpick(s)). Engram unavailable → append the same block to `progress.md`. Set REVIEW_CONTINUED = `true` and proceed to **Step 8**.

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
If the user chose [S]:
📄 **Result hook (E13):** before this stop, write `specs/issue-ISSUE_KEY-result.json` per §Step R with `outcome="stopped"`, `stage="review"`, `reason="User chose [S] after unresolved review findings (Step 7e)"`.
Print `⚠️  Stopping /letsgo.` and end. If Continue, set REVIEW_CONTINUED = `true` and proceed to **Step 8** (no result write).

---

## Step 7.5 — Post-review test re-run

If TEST_RESULT was "passed" or "passed-after-fix" from Step 5b and code review made changes, re-run the same TEST_COMMAND to catch regressions from code-fixer changes.

Pass → print `✅ Post-review tests passed.` POST_REVIEW_TEST = "passed" → **Step 8**.

Fail:
- Bounded fix loop (up to MAX_FIX_PASSES): `@code-fixer` with test output; re-run after each fix.
- Pass within budget → print `✅ Post-review tests passed after N fix pass(es).`, POST_REVIEW_TEST = "passed-after-fix" → **Step 8**. If FOUNDRY_MODE is `true`, run the C9 checkpoint push after the fix loop commits.
- STRICT_TESTS `true` and still failing:
  📄 **Result hook (E11):** before this stop, write `specs/issue-ISSUE_KEY-result.json` per §Step R with `outcome="stopped"`, `stage="tests"` (the failing gate is the test gate), `reason="Post-review tests still failing; strict-tests stop (Step 7.5)"`.
  If FOUNDRY_MODE is `true`, run the Foundry Stop Protocol after this hook (close the PR + `Blocked`).
  Print `⚠️  Post-review tests still failing. Strict-tests mode: stopping.` and stop.
- Otherwise print `⚠️  Post-review tests still failing after fix passes. Continuing to PR creation (test result from Step 5b was green).`, POST_REVIEW_TEST = "failed" → **Step 8**.

TEST_RESULT "failed"/"skipped" → skip this step; POST_REVIEW_TEST = "skipped".

---

## Step 8 — Create PR

### 8a — Derive the PR title

Read `specs/issue-ISSUE_KEY-spec.md`: take the first sentence of `### User Story` (full mode) or `## What` (quick mode). Compose:
```
ISSUE_KEY: <short summary, trimmed to ~60 chars>
```
Use as PR_TITLE; no usable summary → `ISSUE_KEY: implementation`.

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

Verify we are on the feature branch created in Step 0.1:
```bash
CURRENT_BRANCH=$(git branch --show-current)
```
If CURRENT_BRANCH equals the bare `BASE_BRANCH` (compare against `BASE_BRANCH`, never `BASE_REF` — holds in both modes) (unexpected), create it now:
- **BASE set** (from the remote-tracking ref):
  ```bash
  FEATURE_BRANCH="feat/ISSUE_KEY-$(date +%Y%m%d%H%M%S)"
  git checkout -b $FEATURE_BRANCH $BASE_REF
  ```
- **BASE null** (from current HEAD):
  ```bash
  FEATURE_BRANCH="feat/ISSUE_KEY-$(date +%Y%m%d%H%M%S)"
  git checkout -b $FEATURE_BRANCH
  ```
Otherwise continue on the existing FEATURE_BRANCH.

### 8c — Review and commit changes

Working tree clean → 8d.

1. Print changed files from `git status --short`.
2. Scan `.env`, `.env.*`, `*.pem`, `*.key`, `*credentials*`, `*secret*`, `.DS_Store`. Match:
📄 **Result hook (E14):** before this stop, write `specs/issue-ISSUE_KEY-result.json` per §Step R with `outcome="stopped"`, `stage="pr"`, `reason="Sensitive-file pattern matched before commit"`.
Stop and print:
```
⚠️  <file> matches a sensitive-file pattern and is about to be committed.
    Remove it from the working tree or add it to .gitignore before re-running /letsgo.
```
If FOUNDRY_MODE is `true`, run the Foundry Stop Protocol after this hook (close the PR + `Blocked`).
3. AUTO_COMMIT `true` and no risk patterns:
   - Count changed files and lines (additions + deletions), excluding `specs/`.
   - >50 files or >5000 lines → print:
```
⚠️  Diff exceeds auto-commit thresholds (<N> files, <N> lines).
    Manual confirmation required.
```
     fall through to step 4.
   - Otherwise generate a commit message and run `git add -A -- ':!specs/' && git commit -m "<message>"` without asking. Print `✅ Committed automatically (auto-commit on by default).` If FOUNDRY_MODE is `true`, run the C9 checkpoint push (C10 scan already ran at step 2).
4. AUTO_COMMIT `false` or thresholds exceeded: generate a message, print it with the file list (excluding `specs/`), ask confirmation before `git add -A -- ':!specs/' && git commit`. Declined:
   📄 **Result hook (E15):** before this stop, write `specs/issue-ISSUE_KEY-result.json` per §Step R with `outcome="stopped"`, `stage="pr"`, `reason="Manual commit confirmation declined (Step 8c)"`.
   Print `⚠️  Commit confirmation declined. Stopping /letsgo.` and stop the pipeline.

### 8d — Draft the PR description

Brief prose, project domain language (`GLOSSARY.md` if present).

```markdown
## Summary

<smallest visual that makes the key point clear: pseudocode, call tree, component/file tree, Mermaid, or diff sketch; one or a few, not all.>

## Evidence

- **Before:** <Step 5b failing test output, or "tests passed first run (source: TEST_SOURCE)">
  **After:** <Step 5b / Step 7.5 passing output; screenshots are S-tier for visual changes>

## Merge Danger

**Door:** <one-way | two-way>

<optional: one-sentence description>

**Blast Radius:** <one-word description>

<optional: potential ramifications of merge>

## Related Issues
- ISSUE_KEY

## Pipeline Notes
- <automated conflict resolution vs human escalation>
- <DoD or review budget exhausted and continued on human override>
```

**Evidence**: never invent — use TEST_RESULT / POST_REVIEW_TEST from Steps 5b/7.5. If TEST_RESULT = "skipped", state what is true (e.g. "no test runner configured; DoD verified by @dod-evaluator").

**Merge Danger (headless-safe, no prompt)**:
- **Door**: `one-way` for destructive/hard-to-reverse changes (schema drops/migrations, data deletion/transforms, removed public API, deleted imported files, credential/permission changes); else `two-way`.
- **Blast Radius**: one word from the diff's reach — `none`, `single-module`, `cross-module`, `all-consumers`, `schema` — plus optional ramifications.

Write `pr-description.md` in the repo root. Never commit it.

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

Runs ONLY when FOUNDRY_MODE is `true`, after Step 8d wrote `pr-description.md` and Step 8c committed/checkpoint-pushed. The mutex PR is the PR. Order: update body → conditional ready → exactly one merge strategy.

1. Update the body: `timeout 120 gh pr edit "$PR_NUMBER" --body-file pr-description.md`
2. Make ready only if still a draft (OD2: a resumed run may be non-draft):
```bash
[ "$(timeout 120 gh pr view "$PR_NUMBER" --json isDraft --jq '.isDraft')" = "true" ] && timeout 120 gh pr ready "$PR_NUMBER"
```
3. Exactly one merge strategy by MERGE_MODE — never compose squash/rebase variants, never retry a failed merge with a different strategy:
   - `--merge-mode auto` (default): `timeout 120 gh pr merge "$PR_NUMBER" --auto --merge`
   - `--merge-mode direct`: `timeout 120 gh pr merge "$PR_NUMBER" --merge`

The board stays `In Progress` — the host reconciler owns `Integrated` and merge truth; `/letsgo` never writes either. Never add a `Closes: #N` trailer (merges target the base branch, not the default branch).

Any edit/ready/merge failure or timeout ⇒ 📄 **Result hook (E23):** before this stop, write `specs/issue-ISSUE_KEY-result.json` per §Step R with `outcome="stopped"`, `stage="pr"`, `reason="Land failed: <error>"`, `branch=FEATURE_BRANCH`, `pr_url=PR_URL` — then the Foundry Stop Protocol: close the PR (OD1 — a lingering open PR holds the mutex) and set `Blocked`.

Success ⇒ 📄 **Result hook (E17-F):** write `specs/issue-ISSUE_KEY-result.json` per §Step R with `outcome="pr_opened"`, `stage="pr"`, `reason="PR opened successfully"`, `branch=FEATURE_BRANCH`, `pr_url=PR_URL` (existing mutex PR — no new PR) — then print the Step 9 report. `/letsgo` reports the PR it opened and armed; it never claims a merge.

### 8f — Clean up

```bash
rm pr-description.md
```

---

## Step 9 — Final report

📄 **Result hook (E17):** on success, immediately after `gh pr create` returns the PR URL (Step 8e) and before this report, write `specs/issue-ISSUE_KEY-result.json` per §Step R with `outcome="pr_opened"`, `stage="pr"`, `reason="PR opened successfully"`, `branch=FEATURE_BRANCH`, `pr_url` = returned URL.
In FOUNDRY_MODE, the E17-F hook (Step 8e-L) already wrote it with the mutex PR URL — no second create; print the report plus the Foundry line.
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
