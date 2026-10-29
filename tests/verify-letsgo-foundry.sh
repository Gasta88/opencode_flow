#!/usr/bin/env bash
#
# verify-letsgo-foundry.sh — verification harness for issue-13
# (/letsgo Foundry mode — preflight, board lifecycle, draft-PR mutex, land)
#
# Test command for specs/issue-13-spec.md. Exit 0 = all assertions pass.
#
# Seams (per spec ## Test Strategy):
#   S1 (static)   — `rg` assertions pin the canonical commands C1–C13, the new
#                    exit hooks E18–E23 + E17-F, forbidden compositions
#                    (--squash/--rebase/force-push/`Closes #`/`Integrated`
#                    writes), and the anchor-budget guards that keep the two
#                    frozen harnesses (verify-letsgo-base.sh,
#                    verify-letsgo-result.sh) green UNMODIFIED.
#   S2 (behaviour) — scratch git repo simulates C7/C8/C9: branch ancestry from
#                    origin/<base>, 14-digit name shape, empty-commit mutex
#                    push, resume-pattern uniqueness, idempotent re-entry.
#   S3 (fixtures)  — python3 validation of spec-declared result.json fixtures
#                    (E19/E21/E22/E23/E17-F) against the frozen 7-field schema,
#                    plus the rendered marker-comment template.
#   S4 (manual)    — live-`gh` E2E checklist (see S4 block below); needs
#                    a scratch repo + Project board + gh auth; NOT automatable
#                    here. Explicit negative evidence when not exercised.
#
# --- S4 MANUAL LIVE-`gh` E2E CHECKLIST (seam S4 — scratch repo + Project V2
#     board + `gh auth`; real side effects; mirrors verify-letsgo-result.sh
#     L22–41 precedent) ---
#   E2E1  Happy path: `/letsgo <N> --headless --base ai/integration` on a Ready,
#         fit-yes, unblocked issue ⇒ board `In Progress` before first commit;
#         draft PR exists before first implementation commit (baseRefName ==
#         ai/integration, isDraft == true); on completion: body updated,
#         isDraft == false, auto-merge armed with --merge, board left
#         `In Progress`, result.json outcome=pr_opened, one marker comment.
#   E2E2  Preflight fail (`Fit: no` or unresolved blocker): no branch, no PR,
#         no spec files written; board `Blocked`; one comment; result.json
#         outcome=stopped stage=spec.
#   E2E3  Forced headless stop after the mutex (seed a red test under
#         --strict-tests): draft PR closed, board `Blocked`, comment updated,
#         result.json written before the stop message.
#   E2E4  Idempotent re-entry after the E2E3 blocker is resolved: second run
#         finds the existing PR/branch, never opens a second PR, never
#         force-pushes.
#   E2E5  `--merge-mode direct`: PR goes non-draft and is merged with exactly
#         one --merge invocation; no --squash/--rebase observed in the log.
# Status (2026-10-29, sub-task 6): S4 NOT EXERCISED by the implementer — a live
# run opens real PRs and writes a real board against the user's repo (side
# effects outside this task's scope). Explicit negative evidence recorded in
# specs/issue-13-progress.md.
#
# This repo has no test runner; this script IS the executable test command
# (mirrors tests/verify-letsgo-base.sh and tests/verify-letsgo-result.sh).
#
# Platform note (C13 / extdocs): stock macOS has no GNU `timeout`; the S1
# assertions pin the `timeout 120` pattern statically only. Hosts run
# `gtimeout` (coreutils) or an equivalent bound at runtime.
#
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CMD="$REPO_ROOT/commands/letsgo.md"
IMPL="$REPO_ROOT/agents/spec-implementer.md"

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  \033[31m✗\033[0m %s\n' "$1"; }

# contains <label> <file> <fixed-string>
contains() {
  if rg -aqF -- "$3" "$2"; then ok "$1"; else bad "$1 — missing: $3"; fi
}
# absent <label> <file> <fixed-string>
absent() {
  if rg -aqF -- "$3" "$2"; then bad "$1 — unexpectedly present: $3"; else ok "$1"; fi
}
# count_occ <label> <fixed-string> <expected-occurrences> — total occurrences in CMD
count_occ() {
  local n
  n="$(rg -aoF -- "$2" "$CMD" | wc -l | tr -d ' ')" || n=0
  if [ "$n" -eq "$3" ]; then ok "$1 (count=$n)"; else bad "$1 — expected $3 occurrences of '$2', got $n"; fi
}
# hook_near <label> <hook-token> <anchor-string> [window] — EVERY occurrence of
# the anchor must have a line containing the hook token within +/- window lines
# (same semantics as tests/verify-letsgo-result.sh).
hook_near() {
  local label="$1" token="$2" anchor="$3" win="${4:-12}"
  local alines tlines a t d found okall=1
  alines="$(rg -naF -- "$anchor" "$CMD" | cut -d: -f1 | sort -n)" || alines=""
  if [ -z "$alines" ]; then bad "$label — anchor not found: $anchor"; return; fi
  tlines="$(rg -naF -- "$token" "$CMD" | cut -d: -f1 | sort -n)" || tlines=""
  if [ -z "$tlines" ]; then bad "$label — hook token missing: $token"; return; fi
  while IFS= read -r a; do
    [ -z "$a" ] && continue
    found=0
    while IFS= read -r t; do
      [ -z "$t" ] && continue
      d=$(( a - t )); [ "$d" -lt 0 ] && d=$(( -d ))
      [ "$d" -le "$win" ] && found=1
    done <<< "$tlines"
    [ "$found" -eq 1 ] || { okall=0; bad "$label — anchor line $a has no '$token' within $win lines"; }
  done <<< "$alines"
  [ "$okall" -eq 1 ] && ok "$label"
}

if [ ! -f "$CMD" ]; then
  printf 'FATAL: cannot find %s\n' "$CMD" >&2
  exit 2
fi

printf '=== Anchor-budget guards (frozen-harness non-collision) ===\n'
# These two counts are asserted by the FROZEN verify-letsgo-result.sh
# (L151, L161). Re-pinned here so every Foundry slice re-checks that its new
# stop text uses the distinct `Foundry mode: …` anchor family instead of
# colliding with the frozen counts.
count_occ "GUARD-A 'Headless mode: stopping and marking as Blocked.' stays at exactly 2" 'Headless mode: stopping and marking as Blocked.' 2
count_occ "GUARD-B '⚠️  Stopping /letsgo.' stays at exactly 2" '⚠️  Stopping /letsgo.' 2

printf '\n=== Sub-task 1 — activation & flag contract (seam S1) ===\n'

# UT1 — --merge-mode flag contract
contains "UT1 argument-hint advertises [--merge-mode <auto|direct>]" "$CMD" '[--merge-mode <auto|direct>]'
contains "UT1 MERGE_MODE extraction rule (token after --merge-mode, default auto)" "$CMD" 'the token immediately after `--merge-mode` if present, else `auto`'
contains "UT1 valid values pinned auto/direct" "$CMD" 'Valid values: `auto`, `direct`'
contains "UT1 E18 hard-stop message" "$CMD" '❌ --merge-mode requires auto or direct (e.g. --merge-mode auto).'
hook_near "UT1 E18 hook adjacent to --merge-mode validation stop" 'Result hook (E18)' '❌ --merge-mode requires auto or direct (e.g. --merge-mode auto).'

# UT2 — FOUNDRY_MODE activation gate + banner
contains "UT2 FOUNDRY_MODE derivation (headless AND base, iff)" "$CMD" 'FOUNDRY_MODE**: `true` if and only if HEADLESS is `true` AND BASE is not `null`'
contains "UT2 interactive path unchanged sentence" "$CMD" 'byte-for-byte unchanged'
contains "UT2 --quick orthogonal in Foundry mode" "$CMD" '`--quick` remains allowed in Foundry mode'
contains "UT2 banner foundry=FOUNDRY_MODE" "$CMD" 'foundry=FOUNDRY_MODE'
contains "UT2 banner merge-mode=MERGE_MODE" "$CMD" 'merge-mode=MERGE_MODE'

printf '\n=== Sub-task 2 — preflight & board claim (seam S1) ===\n'

# UT3 — Step 0.6 preflight (fail closed, live body per OD3)
contains "UT3 Step 0.6 heading" "$CMD" '## Step 0.6 — Foundry preflight (fail closed)'
contains "UT3 live-body rule (OD3)" "$CMD" 'parse the LIVE GitHub issue body, never the possibly-stale'
contains "UT3 Foundry fit section anchor" "$CMD" '`## Foundry fit`'
contains "UT3 Fit: yes exact line" "$CMD" '`Fit: yes`'
contains "UT3 ref grammar restricted to #N / OWNER/REPO#N" "$CMD" 'same-repo `#<N>` and external `OWNER/REPO#<N>`'
contains "UT3 grammar violation fails closed" "$CMD" 'fails closed'
contains "UT3 no-blockers line" "$CMD" 'None — can start immediately'
contains "UT3 C3 same-repo state command" "$CMD" 'timeout 120 gh issue view <M> --json state'
contains "UT3 C3 external state command" "$CMD" 'timeout 120 gh issue view <M> -R <OWNER>/<REPO> --json state'
contains "UT3 C4 GraphQL single-select value node" "$CMD" '... on ProjectV2ItemFieldSingleSelectValue { name field { ... on ProjectV2FieldCommon { name } } }'
contains "UT3 C4 Integrated exact match" "$CMD" '`name == "Integrated"` (exact, case-sensitive)'
contains "UT3 C1 projectsV2 discovery query" "$CMD" 'projectsV2(first:10){ nodes{ id number title url owner'
contains "UT3 C1 exactly-one fail-closed rule" "$CMD" 'project node must resolve — zero or two-or-more'
contains "UT3 C2 field-list precheck command" "$CMD" 'timeout 120 gh project field-list PROJECT_NUMBER --owner PROJECT_OWNER --format json'
contains "UT3 C2 no option creation" "$CMD" 'never creates or renames options'
hook_near "UT3 E19 hook adjacent to the preflight exit contract" 'Result hook (E19)' 'Foundry preflight failed: <specific>'

# UT4 — Step 0.7 board claim + release values (C5/C6)
contains "UT4 Step 0.7 heading" "$CMD" '## Step 0.7 — Board claim (In Progress)'
contains "UT4 C5 claim exact value" "$CMD" '--field "Status" --value "In Progress"'
contains "UT4 C6 release exact value" "$CMD" '--field "Status" --value "Blocked"'
contains "UT4 claim precedes branch ops" "$CMD" 'before the first `git checkout -b`, commit, or push'
contains "UT4 never Ready/Integrated write" "$CMD" 'Never write `Ready` or `Integrated`'
contains "UT4 exact case-sensitive values" "$CMD" 'case-sensitive'
hook_near "UT4 E20 hook adjacent to the board claim failure" 'Result hook (E20)' 'Board claim failed:'

# Foundry Stop Protocol — single definition, distinct anchors (anchor budget)
contains "FSP single-definition heading" "$CMD" '## Foundry Stop Protocol (single definition)'
contains "FSP canonical post-mutex anchor" "$CMD" 'Foundry mode: stopping, closing the draft PR and marking the issue as Blocked.'
contains "FSP pre-mutex distinct anchor" "$CMD" 'Foundry mode: stopping and marking the issue as Blocked.'
contains "FSP close PR if exists" "$CMD" 'timeout 120 gh pr close "$PR_NUMBER"'
contains "FSP board release is best-effort" "$CMD" 'record the error and continue — never abort mid-stop'
# UT12 (band 1) — timeout bound on the preflight/claim network calls
contains "UT12 timeout bound on live-body read" "$CMD" 'timeout 120 gh issue view <ISSUE_NUMBER> --json body'

printf '\n=== Sub-task 3 — branch safety + draft-PR mutex (seam S1) ===\n'

# UT5 — Step 0.1-F Foundry branch variant
contains "UT5 Step 0.1-F heading" "$CMD" '**Step 0.1-F — Foundry branch variant (FOUNDRY_MODE only)'
contains "UT5 overrides the reuse sentence" "$CMD" 'OVERRIDES the reuse sentence'
contains "UT5 never reuse it" "$CMD" 'never reuse it'
contains "UT5 RESUME_CHECK jq regex" "$CMD" 'select(.headRefName | test("^feat/<N>-[0-9]{14}$"))'
contains "UT5 resume ambiguity fails closed" "$CMD" '0 or ≥2 matches ⇒ E21'
contains "UT5 AC3 merge-base verification" "$CMD" 'must equal `$(git rev-parse $BASE_REF)`'
hook_near "UT5 E21 hook adjacent to branch safety stop" 'Result hook (E21)' 'Branch safety stop:'

# UT6 — Step 0.8 draft-PR mutex (C8)
contains "UT6 Step 0.8 heading" "$CMD" '## Step 0.8 — Draft-PR mutex'
contains "UT6 mutex precedes implementation commits" "$CMD" 'the draft PR exists before any implementation commit'
contains "UT6 C8 empty commit" "$CMD" 'git commit --allow-empty -m "chore(letsgo): reserve PR mutex for issue'
contains "UT6 C8 push -u" "$CMD" 'git push -u origin "$FEATURE_BRANCH"'
contains "UT6 C8 draft create with bare base" "$CMD" 'gh pr create --draft --base "$BASE_BRANCH"'
hook_near "UT6 E22 hook adjacent to mutex failure" 'Result hook (E22)' 'Draft-PR mutex failed:'

# UT7/UT8 — Push Protocol (C9 checkpoints, C10 scan-before-every-push)
contains "UT7 Push Protocol heading" "$CMD" '## Push Protocol (Foundry mode)'
contains "UT7 governor owns every push" "$CMD" 'owns every `git push`'
contains "UT7 C9 checkpoint command" "$CMD" 'git push origin "$FEATURE_BRANCH"'
contains "UT7 C9 checkpoint sites" "$CMD" 'Step 5 pass end, Step 5b fix-loop end'
contains "UT7 no-force prohibition" "$CMD" 'force-push in any form is forbidden'
contains "UT8 C10 scan-before-every-push" "$CMD" 'before EVERY push'
contains "UT8 C10 pattern list" "$CMD" '`.env*`, `*.pem`, `*.key`, `*credentials*`, `*secret*`, `.DS_Store`'
contains "UT8 C10 stop reason" "$CMD" 'reason="Sensitive-file pattern matched before push"'
contains "UT8 C10 staged+worktree surfaces" "$CMD" 'git status --short'
contains "UT12 timeout bound on pushes" "$CMD" 'timeout 120 git push'

# UT7-neg — no force-push flag token anywhere in the command text
if rg -aqF -- '--force' "$CMD"; then
  bad "UT7-neg a --force flag token appears in the command text"
else
  ok "UT7-neg no --force/--force-with-lease token anywhere"
fi

# UT13 — agents/spec-implementer.md push governance (permission block untouched)
if [ ! -f "$IMPL" ]; then
  bad "UT13 cannot find $IMPL"
else
  contains "UT13 implementer commits but never pushes" "$IMPL" 'commits but never pushes'
  contains "UT13 governor owns pushes" "$IMPL" 'the `/letsgo` governor owns every `git push`'
  n="$(rg -aoF -- '"git push*": allow' "$IMPL" | wc -l | tr -d ' ')" || n=0
  if [ "$n" -eq 1 ]; then ok "UT13 permission block unchanged ('git push*': allow once) (count=$n)"; else bad "UT13 permission line count=$n (expected 1)"; fi
fi

printf '\n=== Sub-task 3 — scratch-git simulation (seam S2) ===\n'

T="$(mktemp -d)"
cleanup() { rm -rf "$T"; }
trap cleanup EXIT

REMOTE="$T/remote.git"
WORK="$T/work"
git init -q --bare "$REMOTE"
mkdir -p "$WORK"
git -C "$WORK" init -q
git -C "$WORK" config user.email harness@example.com
git -C "$WORK" config user.name harness
git -C "$WORK" remote add origin "$REMOTE"

# Worked topology: C0 on main; ai/integration advances to C2 on the remote.
echo c0 > "$WORK/common.txt"
git -C "$WORK" add -A && git -C "$WORK" commit -qm C0
git -C "$WORK" branch -M main
git -C "$WORK" push -q -u origin main
git -C "$WORK" branch ai/integration
git -C "$WORK" checkout -q ai/integration
echo c2 > "$WORK/integration-only.txt"
git -C "$WORK" add -A && git -C "$WORK" commit -qm C2
C2T="$(git -C "$WORK" rev-parse ai/integration)"
git -C "$WORK" push -q origin ai/integration
git -C "$WORK" checkout -q main
# Stale local ai/integration pointing at main's tip (C0): any use of the LOCAL
# branch instead of origin/<base> becomes observable.
git -C "$WORK" branch -f ai/integration "$(git -C "$WORK" rev-parse main)"

# ---- IT1/IT2 (AC3): C7 create-path template ----
BASE_BRANCH=ai/integration
BASE_REF=origin/$BASE_BRANCH
git -C "$WORK" fetch -q origin "$BASE_BRANCH"
git -C "$WORK" checkout -q ai/integration          # CURRENT_BRANCH == BASE_BRANCH
FEATURE_BRANCH="feat/13-$(date +%Y%m%d%H%M%S)"
if git -C "$WORK" checkout -q -b "$FEATURE_BRANCH" "$BASE_REF"; then ok "S2-C7 checkout -b from \$BASE_REF succeeded"; else bad "S2-C7 checkout -b failed"; fi
if printf '%s' "$FEATURE_BRANCH" | rg -q '^feat/13-[0-9]{14}$'; then ok "S2-IT2 branch name matches ^feat/13-[0-9]{14}\$ (14-digit shape)"; else bad "S2-IT2 branch name shape wrong: $FEATURE_BRANCH"; fi
if git -C "$WORK" merge-base --is-ancestor "$C2T" HEAD; then ok "S2-IT1 C2 tip is ancestor of feature HEAD (branched from origin ref)"; else bad "S2-IT1 C2 NOT ancestor (stale local used?)"; fi
if [ "$(git -C "$WORK" merge-base HEAD "$BASE_REF")" = "$(git -C "$WORK" rev-parse "$BASE_REF")" ]; then ok "S2-AC3 merge-base HEAD \$BASE_REF == rev-parse \$BASE_REF"; else bad "S2-AC3 merge-base != origin/<base> tip"; fi

# ---- IT3 (mutex, C8): empty commit + push -u against the local bare remote ----
git -C "$WORK" commit -q --allow-empty -m "chore(letsgo): reserve PR mutex for issue 13"
if git -C "$WORK" push -q -u origin "$FEATURE_BRANCH"; then ok "S2-IT3 mutex empty-commit push -u created the remote branch"; else bad "S2-IT3 push -u failed"; fi
if git -C "$WORK" ls-remote --heads origin "$FEATURE_BRANCH" | rg -q "refs/heads/$FEATURE_BRANCH"; then ok "S2-IT3 remote branch visible on origin"; else bad "S2-IT3 remote branch missing"; fi
MC="$(git -C "$WORK" log --format='%s' | rg -c 'chore\(letsgo\): reserve PR mutex' || echo 0)"
if [ "$MC" = "1" ]; then ok "S2-IT3 exactly one mutex commit on the branch (count=$MC)"; else bad "S2-IT3 mutex commit count=$MC (expected 1)"; fi

# ---- EC6 (S2 half): non-base branch is NOT reused — stop leaves HEAD untouched ----
git -C "$WORK" checkout -q main
git -C "$WORK" checkout -q -b some-unrelated-branch
HEAD_BEFORE="$(git -C "$WORK" rev-parse HEAD)"
# RESUME_CHECK pattern over remote branch names: no feat/13-<14d> decoy on the
# un-pushed state of a fresh issue number ⇒ 0 matches ⇒ E21 (simulated stop).
MATCHES="$(git -C "$WORK" ls-remote --heads origin | rg -c 'refs/heads/feat/99-[0-9]{14}$' || true)"
[ "${MATCHES:-0}" = "0" ] && ok "S2-EC6 resume pattern finds 0 PRs for an untouched issue (E21 path)" || bad "S2-EC6 unexpected pattern matches"
if [ "$(git -C "$WORK" rev-parse HEAD)" = "$HEAD_BEFORE" ] && [ "$(git -C "$WORK" branch --show-current)" = "some-unrelated-branch" ]; then ok "S2-EC6 simulated E21 stop leaves the non-base branch untouched"; else bad "S2-EC6 branch state mutated"; fi

printf '\n=== Sub-task 6 — re-entry + resume decoys + interactive freeze (seams S2/S1) ===\n'

# IT4 — the resume pattern selects exactly one branch among decoys
git -C "$WORK" branch feat/13-manual main 2>/dev/null
git -C "$WORK" push -q origin feat/13-manual
git -C "$WORK" branch feat/14-20261029120000 main 2>/dev/null
git -C "$WORK" push -q origin feat/14-20261029120000
git -C "$WORK" branch feat/13-2026102912000 main 2>/dev/null
git -C "$WORK" push -q origin feat/13-2026102912000
SEL="$(git -C "$WORK" ls-remote --heads origin | rg -c 'refs/heads/feat/13-[0-9]{14}$' || true)"
if [ "${SEL:-0}" = "1" ]; then ok "S2-IT4 resume pattern selects the keeper among decoys manual/other-issue/13-digit (count=$SEL)"; else bad "S2-IT4 resume pattern count=$SEL (expected 1)"; fi

# IT3 (re-entry half) — fresh clone adopts the tracking branch; Step 0.8 skipped,
# so NO second `chore(letsgo): reserve PR mutex` commit appears
git clone -q "$REMOTE" "$T/reenter"
git -C "$T/reenter" checkout -q "$FEATURE_BRANCH"
RESUME_HITS="$(git -C "$T/reenter" ls-remote --heads origin | rg -c 'refs/heads/feat/13-[0-9]{14}$' || true)"
if [ "${RESUME_HITS:-0}" = "1" ]; then ok "S2-IT3 re-entry RESUME_CHECK adopts the single existing branch (count=$RESUME_HITS)"; else bad "S2-IT3 re-entry pattern count=$RESUME_HITS (expected 1)"; fi
MC2="$(git -C "$T/reenter" log --format='%s' | rg -c 'chore\(letsgo\): reserve PR mutex' || echo 0)"
if [ "$MC2" = "1" ]; then ok "S2-IT3 no second mutex commit on re-entry (count=$MC2)"; else bad "S2-IT3 mutex commit count after re-entry=$MC2 (expected 1)"; fi

# UT14 — interactive-path freeze: default-path survival strings + the non-Foundry
# reuse sentence intact (the hard stop is FOUNDRY_MODE-gated only)
sc14="$(rg -caF 'BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD' "$CMD" || echo 0)"
if [ "$sc14" -ge 3 ]; then ok "UT14 default symbolic-ref derivation survives (count=$sc14)"; else bad "UT14 default derivation count=$sc14 (<3)"; fi
contains "UT14 default bare checkout survives" "$CMD" 'git checkout -b $FEATURE_BRANCH'
contains "UT14 default gh pr create survives" "$CMD" 'gh pr create --title "PR_TITLE" --body-file pr-description.md'
contains "UT14 non-Foundry reuse sentence intact" "$CMD" 'If already on a different non-base branch, use it as-is and set FEATURE_BRANCH to'
contains "UT14 hard stop is FOUNDRY-gated" "$CMD" 'Step 0.1-F — Foundry branch variant (FOUNDRY_MODE only).'

printf '\n=== Sub-task 4 — pipeline checkpoints + land path (seam S1) ===\n'

# UT7 — five checkpoint sites (Steps 5, 5b, 7d, 7.5, 8c) + protocol definition
count_occ "UT7 C9 checkpoint sites (5 post-mutex commit stages)" 'run the C9 checkpoint push' 5

# UT9 — Step 8e-L land path (C12)
contains "UT9 Step 8e-L heading" "$CMD" '### 8e-L — Foundry land path (FOUNDRY_MODE only)'
contains "UT9 8e skips create in Foundry" "$CMD" 'skip the create calls below'
contains "UT9 C12 body update" "$CMD" 'gh pr edit "$PR_NUMBER" --body-file pr-description.md'
contains "UT9 C12 conditional ready guard (isDraft)" "$CMD" 'gh pr view "$PR_NUMBER" --json isDraft'
contains "UT9 C12 gh pr ready invocation" "$CMD" 'timeout 120 gh pr ready "$PR_NUMBER"'
contains "UT9 C12 auto mode merge" "$CMD" 'gh pr merge "$PR_NUMBER" --auto --merge'
contains "UT9 C12 direct mode merge" "$CMD" 'gh pr merge "$PR_NUMBER" --merge'
contains "UT9 one-strategy prohibition" "$CMD" 'never retry a failed'
contains "UT9 board stays In Progress" "$CMD" 'The board stays `In Progress`'
contains "UT9 OD1 close ready PR on land failure" "$CMD" 'close the PR (OD1'
hook_near "UT9 E23 hook adjacent to land failure" 'Result hook (E23)' 'Land failed:'
contains "UT9 E17-F success hook" "$CMD" 'Result hook (E17-F)'
# negative scans: no composed squash/rebase on any merge line; no Closes # trailer
if rg -aNF 'gh pr merge' "$CMD" | rg -qF -e '--squash'; then
  bad "UT9-neg a gh pr merge line composes --squash"
else
  ok "UT9-neg no gh pr merge line composes --squash"
fi
if rg -aNF 'gh pr merge' "$CMD" | rg -qF -e '--rebase'; then
  bad "UT9-neg a gh pr merge line composes --rebase"
else
  ok "UT9-neg no gh pr merge line composes --rebase"
fi
absent "UT9-neg no Closes # in any PR-body text" "$CMD" 'Closes #'

# UT10 — Foundry branches on every post-mutex stop (E5/E7/E10/E11/E12/E14/E16)
count_occ "UT10 Foundry Stop Protocol branches at 7 existing stops" 'run the Foundry Stop Protocol after this hook' 7
contains "UT10 protocol referenced, not restated" "$CMD" 'It is defined once here and referenced by each stop'

# Step 9 Foundry report lines
contains "UT-Step9 Foundry report line" "$CMD" 'Foundry: preflight=passed claim=In Progress mutex='

printf '\n=== Sub-task 2 — preflight-fail fixture (seam S3) ===\n'

# Validator: the frozen 7-field schema, identical to verify-letsgo-result.sh
# L194–241 (independent known-good — the schema lives in the frozen harness and
# the driver contract, NOT in the text under test).
cat > "$T/validate.py" <<'PYEOF'
import json, sys
REQUIRED = ["issue", "outcome", "stage", "reason", "branch", "pr_url"]
ALLOWED = set(REQUIRED + ["pipeline"])
STAGES = {"spec", "dod", "tests", "review", "pr"}
OUTCOMES = {"pr_opened", "stopped"}
def fail(msg):
    print("VALIDATOR-FAIL: " + msg)
    sys.exit(1)
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
except Exception as e:
    fail("invalid JSON: %s" % e)
if not isinstance(data, dict):
    fail("top level must be an object")
extra = set(data) - ALLOWED
if extra:
    fail("keys outside frozen 7-field schema: %s" % sorted(extra))
for k in REQUIRED:
    if k not in data:
        fail("missing required key: %s" % k)
if isinstance(data["issue"], bool) or not isinstance(data["issue"], (int, str)):
    fail("issue must be a JSON number or string")
if isinstance(data["issue"], str) and not data["issue"]:
    fail("issue string must be non-empty")
if data["outcome"] not in OUTCOMES:
    fail("outcome enum violation: %r" % data["outcome"])
if data["stage"] not in STAGES:
    fail("stage enum violation: %r" % data["stage"])
if not isinstance(data["reason"], str) or not data["reason"]:
    fail("reason must be a non-empty string")
for k in ("branch", "pr_url"):
    if not isinstance(data[k], str):
        fail("%s must be a string (empty string when unavailable, never null)" % k)
if "pipeline" in data:
    p = data["pipeline"]
    if not isinstance(p, dict):
        fail("pipeline must be an object")
    if set(p) != {"spec_turns", "impl_passes", "fix_passes"}:
        fail("pipeline must have exactly the 3 counters")
    for k, v in p.items():
        if isinstance(v, bool) or not isinstance(v, int):
            fail("pipeline.%s must be an integer" % k)
        if v < 0:
            fail("pipeline.%s must be >= 0" % k)
print("shape ok")
PYEOF

# E19 fixture — verbatim from spec IT5: stopped/spec/branch=""/pipeline absent
cat > "$T/e19-preflight-fail.json" <<'EOF'
{
  "issue": 13,
  "outcome": "stopped",
  "stage": "spec",
  "reason": "Foundry preflight failed: no '## Foundry fit' with Fit: yes",
  "branch": "",
  "pr_url": ""
}
EOF

if python3 "$T/validate.py" "$T/e19-preflight-fail.json" >/dev/null 2>&1; then
  if python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d["outcome"] == "stopped"
assert d["stage"] == "spec"
assert d["branch"] == "" and d["pr_url"] == ""
assert "pipeline" not in d
assert d["reason"].startswith("Foundry preflight failed:")
' "$T/e19-preflight-fail.json" 2>/dev/null; then ok "S3-E19 preflight-fail fixture validates (stopped/spec, branch empty, pipeline absent)"; else bad "S3-E19 fixture field expectations"; fi
else bad "S3-E19 fixture failed frozen-schema shape validation"; fi

printf '\n=== Sub-task 5 — observability: comment mirror + hooks table (seam S1) ===\n'

# UT11 — C11 comment upsert contract + token hygiene + hook table registration
contains "UT11 marker literal pinned" "$CMD" '<!-- opencode-flow:result -->'
contains "UT11 find step (jq select on marker)" "$CMD" 'select(.body | contains("<!-- opencode-flow:result -->")) | .id'
contains "UT11 PATCH update path" "$CMD" '-X PATCH -F body=@result-comment.md'
contains "UT11 create path" "$CMD" 'issues/<N>/comments" -F body=@result-comment.md'
contains "UT11 token hygiene rule (AC9)" "$CMD" 'no token value ever appears in argv, stdout'
contains "UT11 comment mirror section" "$CMD" '### Comment mirror (C11) — exactly one result comment (Foundry mode)'
contains "UT11 hooks table section" "$CMD" '### Foundry hooks (E18–E23, E17-F) — registered per the standing rule'
contains "UT11 hooks row E18" "$CMD" '| E18 |'
contains "UT11 hooks row E19" "$CMD" '| E19 |'
contains "UT11 hooks row E20" "$CMD" '| E20 |'
contains "UT11 hooks row E21" "$CMD" '| E21 |'
contains "UT11 hooks row E22" "$CMD" '| E22 |'
contains "UT11 hooks row E23" "$CMD" '| E23 |'
contains "UT11 hooks row E17-F" "$CMD" '| E17-F |'

# UT12 — timeout bound per network-command class + gtimeout fallback note
contains "UT12 timeout bound on board writes" "$CMD" 'timeout 120 gh project item-edit'
contains "UT12 timeout bound on graphql calls" "$CMD" 'timeout 120 gh api graphql'
contains "UT12 timeout bound on comment mirror" "$CMD" 'timeout 120 gh api "repos'
contains "UT12 timeout bound on land edits" "$CMD" 'timeout 120 gh pr edit'
contains "UT12 timeout bound on merge" "$CMD" 'timeout 120 gh pr merge'
contains "UT12 timeout bound on pr close" "$CMD" 'timeout 120 gh pr close'
contains "UT12 gtimeout fallback note" "$CMD" 'gtimeout 120'

printf '\n=== Sub-task 5 — new-exit fixtures + comment template (seam S3) ===\n'

# IT5 — E21/E22/E23/E17-F fixtures (spec-declared) against the frozen validator
cat > "$T/e21-branch-safety.json" <<'EOF'
{
  "issue": 13,
  "outcome": "stopped",
  "stage": "spec",
  "reason": "Branch safety stop: non-base branch not reused / resume ambiguity",
  "branch": "",
  "pr_url": ""
}
EOF

cat > "$T/e22-mutex-fail.json" <<'EOF'
{
  "issue": 13,
  "outcome": "stopped",
  "stage": "pr",
  "reason": "Draft-PR mutex failed: push rejected",
  "branch": "feat/13-20261029120000",
  "pr_url": ""
}
EOF

cat > "$T/e23-land-fail.json" <<'EOF'
{
  "issue": 13,
  "outcome": "stopped",
  "stage": "pr",
  "reason": "Land failed: gh pr merge returned non-zero",
  "branch": "feat/13-20261029120000",
  "pr_url": "https://github.com/owner/repo/pull/14"
}
EOF

cat > "$T/e17f-success.json" <<'EOF'
{
  "issue": 13,
  "outcome": "pr_opened",
  "stage": "pr",
  "reason": "PR opened successfully",
  "branch": "feat/13-20261029120000",
  "pr_url": "https://github.com/owner/repo/pull/14",
  "pipeline": { "spec_turns": 1, "impl_passes": 1, "fix_passes": 0 }
}
EOF

# Negative controls — prove the freeze is real: merge truth and extra fields reject
cat > "$T/neg-merged-outcome.json" <<'EOF'
{
  "issue": 13,
  "outcome": "merged",
  "stage": "pr",
  "reason": "PR merged",
  "branch": "feat/13-20261029120000",
  "pr_url": "https://github.com/owner/repo/pull/14"
}
EOF

cat > "$T/neg-extra-field.json" <<'EOF'
{
  "issue": 13,
  "outcome": "stopped",
  "stage": "pr",
  "reason": "Land failed: timeout",
  "branch": "feat/13-20261029120000",
  "pr_url": "https://github.com/owner/repo/pull/14",
  "merge_sha": "deadbeef"
}
EOF

fx() { python3 "$T/validate.py" "$1" >/dev/null 2>&1; }

if fx "$T/e21-branch-safety.json" && python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d["stage"] == "spec" and d["branch"] == "" and d["pr_url"] == "" and "pipeline" not in d
' "$T/e21-branch-safety.json" 2>/dev/null; then ok "S3-IT5 E21 fixture validates (stopped/spec, no branch, pipeline absent)"; else bad "S3-IT5 E21 fixture"; fi

if fx "$T/e22-mutex-fail.json" && python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d["stage"] == "pr" and d["branch"] != "" and d["pr_url"] == "" and "pipeline" not in d
' "$T/e22-mutex-fail.json" 2>/dev/null; then ok "S3-IT5 E22 fixture validates (stopped/pr, branch set, pr_url empty)"; else bad "S3-IT5 E22 fixture"; fi

if fx "$T/e23-land-fail.json" && python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d["stage"] == "pr" and d["pr_url"] != ""
' "$T/e23-land-fail.json" 2>/dev/null; then ok "S3-IT5 E23 fixture validates (stopped/pr, pr_url set)"; else bad "S3-IT5 E23 fixture"; fi

if fx "$T/e17f-success.json" && python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d["outcome"] == "pr_opened" and d["pr_url"] != "" and d["pipeline"]["impl_passes"] == 1
' "$T/e17f-success.json" 2>/dev/null; then ok "S3-IT5 E17-F fixture validates (pr_opened/pr, existing PR URL, counters)"; else bad "S3-IT5 E17-F fixture"; fi

if fx "$T/neg-merged-outcome.json"; then
  bad "S3-IT5 negative control — validator accepted outcome=merged (reconciler owns merge truth)"
else
  ok "S3-IT5 validator rejects outcome=merged (freeze holds)"
fi
if fx "$T/neg-extra-field.json"; then
  bad "S3-IT5 negative control — validator accepted a field outside the 7-field schema"
else
  ok "S3-IT5 validator rejects extra field merge_sha (freeze holds)"
fi

# IT6 — rendered comment template: marker exactly once, no token-shaped strings
cat > "$T/result-comment.md" <<'EOF'
<!-- opencode-flow:result -->
outcome=stopped
stage=spec
reason=Foundry preflight failed: no '## Foundry fit' with Fit: yes
branch=
pr_url=
run=2026-10-29T12:00:00Z
EOF
mc="$(rg -aoF -- '<!-- opencode-flow:result -->' "$T/result-comment.md" | wc -l | tr -d ' ')"
if [ "$mc" = "1" ]; then ok "S3-IT6 marker occurs exactly once in the rendered comment (AC7 premise)"; else bad "S3-IT6 marker count=$mc (expected 1)"; fi
if rg -aq -- 'ghp_[A-Za-z0-9]|gho_|ghs_|github_pat_|token=' "$T/result-comment.md" "$T/e17f-success.json" "$T/e23-land-fail.json"; then
  bad "S3-IT6 token-shaped string found in fixtures/template (AC9)"
else
  ok "S3-IT6 no token-shaped strings in fixtures or comment template (AC9)"
fi

printf '\n=== Summary ===\n'
printf 'passed=%d failed=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
