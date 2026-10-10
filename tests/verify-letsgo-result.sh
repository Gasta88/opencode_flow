#!/usr/bin/env bash
#
# verify-letsgo-result.sh — verification harness for issue-10
# (specs/issue-N-result.json written at every /letsgo exit point)
#
# Test command for specs/issue-10-spec.md. Exit 0 = all assertions pass.
#
# Seams (per spec ## Test Strategy):
#   S1 (static)   — `rg` assertions pin the Result Contract, the 17 exit hooks
#                    (E1–E17), exact enum literals, field names, the standing
#                    "every stop writes" rule, and the issue-9 default-path
#                    survival strings in commands/letsgo.md.
#   S2 (payload)  — `python3` validates the result.json payload shape against
#                    the three known-good fixtures declared in spec
#                    ## API Contracts (independent source of truth — the
#                    fixtures are NOT recomputed from the command text),
#                    plus a negative control (IT4) proving the validator is real.
#
# Mirrors the pattern of tests/verify-letsgo-base.sh (issue-9). This repo has
# no test runner; this script IS the executable test command.
#
# --- S3 MANUAL E2E CHECKLIST (seam S3 — real `/letsgo --headless` run) ---
# Not automatable here: needs a live GitHub remote + `gh auth` and produces real
# side effects (branches, PRs). Executed by a human against a scratch issue:
#   E2E1  Run `/letsgo <N> --headless` on an issue whose spec forces a Step 3
#         headless conflict stop (e.g. seed a decisions.md conflict the analyst
#         cannot auto-resolve). Then:
#           cat specs/issue-<N>-result.json
#         Expect: outcome="stopped", stage="spec", live branch name, pipeline
#         .spec_turns == MAX_SPEC_TURNS, pr_url="".
#   E2E2  Run `/letsgo <N> --headless` to completion on a trivial issue. Expect:
#         outcome="pr_opened", stage="pr", pr_url = the real gh PR URL,
#         Step 9 report shows the `Result:` line.
#   E2E3  git check-ignore specs/issue-<N>-result.json   → must echo the path
#         (file never committed; specs/ is git-ignored).
#   EC6   Re-run `/letsgo <N> --headless` for the same issue. Expect: the file
#         is overwritten (last-run-wins), not appended to.
# Status (2026-10-10, sub-task 6): S3 NOT EXERCISED by the implementer — a live
# run opens a PR against the user's repo (side effect outside this task's
# scope). E2E3 was verified statically: `git check-ignore specs/issue-10-result.json`
# returns the path. Explicit negative evidence recorded in specs/issue-10-progress.md.
#
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CMD="$REPO_ROOT/commands/letsgo.md"

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
# the anchor must have a line containing the hook token within +/- window lines.
# Use for anchors that occur exactly once.
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
# hook_near_occ <label> <hook-token> <anchor-string> <occurrence-index> [window]
# — the Nth occurrence of the anchor must be near the hook token. Use for
# shared anchors (E5/E7 'Blocked', E8/E13 'Stopping /letsgo.').
hook_near_occ() {
  local label="$1" token="$2" anchor="$3" idx="$4" win="${5:-12}"
  local aline tlines t found=0
  aline="$(rg -naF -- "$anchor" "$CMD" | cut -d: -f1 | sort -n | sed -n "${idx}p")" || aline=""
  if [ -z "$aline" ]; then bad "$label — anchor occurrence #$idx not found: $anchor"; return; fi
  tlines="$(rg -naF -- "$token" "$CMD" | cut -d: -f1 | sort -n)" || tlines=""
  while IFS= read -r t; do
    [ -z "$t" ] && continue
    local d=$(( aline - t )); [ "$d" -lt 0 ] && d=$(( -d ))
    [ "$d" -le "$win" ] && found=1
  done <<< "$tlines"
  if [ "$found" -eq 1 ]; then ok "$label (anchor L$aline)"; else bad "$label — no '$token' within $win lines of anchor occurrence #$idx (L$aline)"; fi
}

if [ ! -f "$CMD" ]; then
  printf 'FATAL: cannot find %s\n' "$CMD" >&2
  exit 2
fi

printf '=== Static assertions on commands/letsgo.md (seam S1) ===\n'

# UT1 — Result Contract section exists (canonical heading, em dash)
contains "UT1 Result Contract section exists" "$CMD" '## Step R — Result Contract'

# UT2 — canonical JSON template pins all 7 schema field names
contains "UT2 field 'issue' pinned"      "$CMD" '"issue":'
contains "UT2 field 'outcome' pinned"   "$CMD" '"outcome":'
contains "UT2 field 'stage' pinned"     "$CMD" '"stage":'
contains "UT2 field 'reason' pinned"    "$CMD" '"reason":'
contains "UT2 field 'branch' pinned"    "$CMD" '"branch":'
contains "UT2 field 'pr_url' pinned"    "$CMD" '"pr_url":'
contains "UT2 field 'pipeline' pinned"  "$CMD" '"pipeline":'

# UT3 — outcome enum literals pinned
contains "UT3 outcome enum pr_opened" "$CMD" '"pr_opened"'
contains "UT3 outcome enum stopped"   "$CMD" '"stopped"'

# UT4 — stage enum literals pinned
contains "UT4 stage enum spec"   "$CMD" '"spec"'
contains "UT4 stage enum dod"    "$CMD" '"dod"'
contains "UT4 stage enum tests"  "$CMD" '"tests"'
contains "UT4 stage enum review" "$CMD" '"review"'
contains "UT4 stage enum pr"     "$CMD" '"pr"'

# UT5 — standing rule: every current or future stop writes result.json
contains "UT5 standing rule (any current or future stop)" "$CMD" 'Any current or future stop'
contains "UT5 write-before-stop protocol"                 "$CMD" 'immediately before'
# EC6 (S1 half) — contract pins overwrite semantics (S3 half: manual re-run checklist)
contains "EC6 overwrite last-run-wins wording"            "$CMD" 'last-run-wins'

printf '\n=== Exit hooks E1–E6: spec-stage exits (seam S1, UT6) ===\n'

# Each exit anchor must carry an adjacent `Result hook (E<n)>` line.
# Shared-anchor exits (E5/E7 'Blocked', E8/E13 'Stopping /letsgo.') are pinned
# by occurrence index: occurrence order in the file matches E-number order.
hook_near     "UT6-E1 hook adjacent to --base validation stop"   'Result hook (E1)' '❌ --base requires a branch name (e.g. --base ai/integration).'
hook_near     "UT6-E2 hook adjacent to gh fetch-fail stop"       'Result hook (E2)' '❌ Could not fetch GitHub issue #<ISSUE_NUMBER>.'
hook_near     "UT6-E3 hook adjacent to file-not-found stop"      'Result hook (E3)' '❌ File not found: <FILE_PATH>'
hook_near     "UT6-E4 hook adjacent to remote-branch fetch stop" 'Result hook (E4)' '❌ Remote branch origin/<BASE> not found (fetch failed). Stopping.'
count_occ     "UT6-E5/E7 shared 'Blocked' anchor occurs exactly 2x" 'Headless mode: stopping and marking as Blocked.' 2
hook_near_occ "UT6-E5 hook adjacent to headless spec-conflict stop (occ 1)" 'Result hook (E5)' 'Headless mode: stopping and marking as Blocked.' 1
hook_near     "UT6-E6 hook adjacent to human spec-rejection stop" 'Result hook (E6)' '⚠️  Spec for ISSUE_KEY was not approved. Stopping /letsgo.'

printf '\n=== Exit hooks E7–E11: dod + tests stages (seam S1, UT6/UT7) ===\n'

# E7 shares the 'Blocked' anchor with E5 — must sit at occurrence #2 (Step 5d impl block).
hook_near_occ "UT6-E7 hook adjacent to headless critical-DoD stop (occ 2)" 'Result hook (E7)' 'Headless mode: stopping and marking as Blocked.' 2
# UT7 — '⚠️  Stopping /letsgo.' occurs exactly twice (E8 DoD block + E13 review block),
# each preceded by a hook. Sub-task 3 pins the E8 side; sub-task 4 pins the E13 side.
count_occ     "UT7 'Stopping /letsgo.' anchor occurs exactly 2x (E8+E13)" '⚠️  Stopping /letsgo.' 2
hook_near_occ "UT6-E8 hook adjacent to DoD human [S] stop (occ 1, DoD block)" 'Result hook (E8)' '⚠️  Stopping /letsgo.' 1
hook_near     "UT6-E9 hook adjacent to make-ci-missing stop"        'Result hook (E9)' "⚠️  --make-ci specified but no 'make ci' target found. Stopping."
hook_near     "UT6-E10 hook adjacent to strict-tests stop"          'Result hook (E10)' '⚠️  Tests still failing after MAX_FIX_PASSES fix passes. Strict-tests mode: stopping.'
hook_near     "UT6-E11 hook adjacent to post-review strict stop"    'Result hook (E11)' '⚠️  Post-review tests still failing. Strict-tests mode: stopping.'

printf '\n=== Exit hooks E12–E17: review + pr + success (seam S1, UT6/UT7/UT8) ===\n'

hook_near     "UT6-E12 hook adjacent to headless review stop"       'Result hook (E12)' 'Headless mode: stopping and marking as Needs Review.'
hook_near_occ "UT6-E13 hook adjacent to review human [S] stop (occ 2, review block)" 'Result hook (E13)' '⚠️  Stopping /letsgo.' 2
hook_near     "UT6-E14 hook adjacent to sensitive-file stop"        'Result hook (E14)' 'matches a sensitive-file pattern and is about to be committed.'
hook_near     "UT6-E15 hook adjacent to declined-commit stop"       'Result hook (E15)' 'Commit confirmation declined. Stopping /letsgo.'
hook_near     "UT6-E16 hook adjacent to gh-pr-create-fail stop"       'Result hook (E16)' 'If `gh pr create` fails for any reason (including auth):'
hook_near     "UT6-E17 hook adjacent to success report"             'Result hook (E17)' '🎉 /letsgo complete for ISSUE_KEY'
# UT8 — Step 9 final report carries the Result: line
contains      "UT8 Step 9 report Result: line" "$CMD" 'specs/issue-ISSUE_KEY-result.json (outcome=pr_opened'

printf '\n=== Issue-9 default-path freeze regression guard (seam S1, IT5) ===\n'

# decision 2026-10-10 AC4: the --base freeze must survive every hook insertion.
# Same three survival assertions as tests/verify-letsgo-base.sh UT5 (re-pinned here).
sc="$(rg -caF 'BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD' "$CMD" || echo 0)"
if [ "$sc" -ge 3 ]; then ok "IT5 default symbolic-ref derivation survives in 0.1/6/8b (count=$sc)"; else bad "IT5 default derivation count=$sc (<3)"; fi
contains "IT5 default bare checkout survives"  "$CMD" 'git checkout -b $FEATURE_BRANCH'
contains "IT5 default gh pr create survives"   "$CMD" 'gh pr create --title "PR_TITLE" --body-file pr-description.md'

printf '\n=== Payload-shape validation against spec fixtures (seam S2) ===\n'

T="$(mktemp -d)"
cleanup() { rm -rf "$T"; }
trap cleanup EXIT

# The validator implements the frozen schema of spec ## API Contracts.
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

# --- Known-good fixtures, verbatim from spec ## API Contracts ---
cat > "$T/success.json" <<'EOF'
{
  "issue": 42,
  "outcome": "pr_opened",
  "stage": "pr",
  "reason": "PR opened successfully",
  "branch": "feat/42-20261010120000",
  "pr_url": "https://github.com/owner/repo/pull/43",
  "pipeline": { "spec_turns": 2, "impl_passes": 1, "fix_passes": 2 }
}
EOF

cat > "$T/headless-stop.json" <<'EOF'
{
  "issue": 42,
  "outcome": "stopped",
  "stage": "spec",
  "reason": "Spec still has open conflicts after 3 automated turns. Headless mode: stopping and marking as Blocked.",
  "branch": "feat/42-20261010120000",
  "pr_url": "",
  "pipeline": { "spec_turns": 3, "impl_passes": 0, "fix_passes": 0 }
}
EOF

cat > "$T/early-stop.json" <<'EOF'
{
  "issue": 42,
  "outcome": "stopped",
  "stage": "spec",
  "reason": "--base requires a branch name",
  "branch": "",
  "pr_url": ""
}
EOF

# EC1 — non-numeric ISSUE_KEY (file-path arg like FEAT-123): issue is a JSON string
cat > "$T/nonnumeric-issue.json" <<'EOF'
{
  "issue": "FEAT-123",
  "outcome": "stopped",
  "stage": "spec",
  "reason": "File not found",
  "branch": "",
  "pr_url": ""
}
EOF

# IT4 negative control — headless fixture with the required 'stage' key removed
cat > "$T/malformed-missing-stage.json" <<'EOF'
{
  "issue": 42,
  "outcome": "stopped",
  "reason": "Spec still has open conflicts after 3 automated turns. Headless mode: stopping and marking as Blocked.",
  "branch": "feat/42-20261010120000",
  "pr_url": "",
  "pipeline": { "spec_turns": 3, "impl_passes": 0, "fix_passes": 0 }
}
EOF

vp() { python3 "$T/validate.py" "$1" >/dev/null 2>&1; }

# IT1 — success fixture: shape + spec-declared expectations
if vp "$T/success.json"; then
  if python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert type(d["issue"]) is int and d["issue"] == 42
assert d["outcome"] == "pr_opened"
assert d["stage"] == "pr"
assert d["pr_url"] != ""
assert set(d["pipeline"]) == {"spec_turns", "impl_passes", "fix_passes"}
assert all(type(v) is int for v in d["pipeline"].values())
' "$T/success.json" 2>/dev/null; then ok "IT1 success fixture validates"; else bad "IT1 success fixture field expectations"; fi
else bad "IT1 success fixture failed shape validation"; fi

# IT2 — headless-stop fixture
if vp "$T/headless-stop.json"; then
  if python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d["outcome"] == "stopped"
assert d["stage"] == "spec"
assert d["pr_url"] == ""
assert d["pipeline"]["impl_passes"] == 0
' "$T/headless-stop.json" 2>/dev/null; then ok "IT2 headless-stop fixture validates"; else bad "IT2 headless-stop fixture field expectations"; fi
else bad "IT2 headless-stop fixture failed shape validation"; fi

# IT3 — early-stop fixture: pipeline key ABSENT (not {}/null), branch/pr_url empty
if vp "$T/early-stop.json"; then
  if python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert "pipeline" not in d
assert d["branch"] == ""
assert d["pr_url"] == ""
assert set(d) == {"issue", "outcome", "stage", "reason", "branch", "pr_url"}
' "$T/early-stop.json" 2>/dev/null; then ok "IT3 early-stop fixture validates (pipeline absent, 6 keys)"; else bad "IT3 early-stop fixture field expectations"; fi
else bad "IT3 early-stop fixture failed shape validation"; fi

# EC1 — non-numeric ISSUE_KEY emitted as JSON string, not number
if vp "$T/nonnumeric-issue.json"; then
  if python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert type(d["issue"]) is str and d["issue"] == "FEAT-123"
' "$T/nonnumeric-issue.json" 2>/dev/null; then ok "EC1 non-numeric issue validates as JSON string"; else bad "EC1 issue field is not a JSON string"; fi
else bad "EC1 nonnumeric fixture failed shape validation"; fi

# IT4 — negative control: the validator must REJECT a payload missing 'stage'
if vp "$T/malformed-missing-stage.json"; then
  bad "IT4 negative control FAILED — validator accepted a payload missing 'stage'"
else
  ok "IT4 validator rejects payload missing 'stage' (negative control)"
fi

printf '\n=== Summary ===\n'
printf 'passed=%d failed=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
