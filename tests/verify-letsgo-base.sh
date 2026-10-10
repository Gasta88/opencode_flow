#!/usr/bin/env bash
#
# verify-letsgo-base.sh — verification harness for issue-9 (/letsgo --base flag)
#
# Test command for specs/issue-9-spec.md. Exit 0 = all assertions pass.
#
# Two seams:
#   S1/S3 (static)  — `rg` assertions pin the required phrases in commands/letsgo.md
#   S2    (behaviour) — a scratch git repo simulates the bash templates emitted by
#                        Steps 0.1 / 6 / 8b on BOTH the --base path and the default
#                        path, asserting ancestry/merge-base against the spec's fixed
#                        worked topology (C0/C1/C2). Expected values come from git
#                        semantics declared at spec time, never from re-running the
#                        code under test and copying its output.
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

if [ ! -f "$CMD" ]; then
  printf 'FATAL: cannot find %s\n' "$CMD" >&2
  exit 2
fi

printf '=== Static assertions on commands/letsgo.md (seams S1 / S3) ===\n'

# UT1 — argument-hint advertises the flag
contains "UT1 argument-hint has [--base <branch>]" "$CMD" '[--base <branch>]'

# UT2 — Step 0 parsing: extraction, normalization, hard-stop validation
contains "UT2 BASE extraction rule (token after --base)" "$CMD" 'the token immediately after'
contains "UT2 origin/ prefix stripping"                  "$CMD" 'strip a leading'
contains "UT2 hard-stop message"                         "$CMD" '❌ --base requires a branch name (e.g. --base ai/integration).'

# UT3 — Step 0.5 banner echoes the effective base
contains "UT3 banner contains base="                     "$CMD" 'base=BASE_EFFECTIVE'

# UT4 — Step 8e passes the BARE name to gh, never a remote ref
contains "UT4 gh pr create --base uses \$BASE_BRANCH"     "$CMD" 'gh pr create --base "$BASE_BRANCH"'
# negative check scoped to actual gh command lines (prose guards may mention the words)
if rg -aNF 'gh pr create' "$CMD" | rg -qF '$BASE_REF'; then
  bad "UT4-neg a gh pr create line passes \$BASE_REF"
else
  ok "UT4-neg no gh pr create line passes \$BASE_REF"
fi
if rg -aNF 'gh pr create' "$CMD" | rg -qF 'origin/'; then
  bad "UT4-neg b gh pr create line passes origin/"
else
  ok "UT4-neg b no gh pr create line passes origin/"
fi

# UT5 — AC4 regression: the default-path strings survive verbatim
sc="$(rg -cF 'BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD' "$CMD" || echo 0)"
if [ "$sc" -ge 3 ]; then ok "UT5 default symbolic-ref derivation present in 0.1/6/8b (count=$sc)"; else bad "UT5 default derivation count=$sc (<3)"; fi
contains "UT5 default bare checkout survives"            "$CMD" 'git checkout -b $FEATURE_BRANCH'
contains "UT5 default gh pr create survives"             "$CMD" 'gh pr create --title "PR_TITLE" --body-file pr-description.md'

# UT6 — Step 9 report line + Step 7d inheritance untouched
contains "UT6 Step 9 Base: report line"                  "$CMD" 'Base:'
contains "UT6 Step 7d still inherits Step 6"             "$CMD" 'same commands as Step 6'

# S2 behaviour guard: the --base diff/log templates must consume BASE_REF
contains "IT2/IT3 template uses merge-base HEAD \$BASE_REF" "$CMD" 'git merge-base HEAD $BASE_REF'

printf '\n=== Scratch-repo simulation (seam S2) ===\n'

T="$(mktemp -d)"
cleanup() { rm -rf "$T"; }
trap cleanup EXIT

REMOTE="$T/remote.git"
WORK="$T/work"
git init -q --bare "$REMOTE"
mkdir -p "$WORK"
git -C "$WORK" init -q
git -C "$WORK" config user.email  harness@example.com
git -C "$WORK" config user.name   harness
git -C "$WORK" remote add origin "$REMOTE"

# Worked topology: C0 on both branches; main advances C1; ai/integration advances C2.
echo c0 > "$WORK/common.txt"
git -C "$WORK" add -A && git -C "$WORK" commit -qm C0
C0="$(git -C "$WORK" rev-parse HEAD)"
git -C "$WORK" branch -M main
git -C "$WORK" push -q -u origin main
git -C "$WORK" branch ai/integration
git -C "$WORK" push -q origin ai/integration

echo c1 > "$WORK/main-only.txt"
git -C "$WORK" add -A && git -C "$WORK" commit -qm C1
git -C "$WORK" push -q origin main
C1="$(git -C "$WORK" rev-parse main)"

git -C "$WORK" checkout -q ai/integration
echo c2 > "$WORK/integration-only.txt"
git -C "$WORK" add -A && git -C "$WORK" commit -qm C2
git -C "$WORK" push -q origin ai/integration
C2="$(git -C "$WORK" rev-parse ai/integration)"

# origin/HEAD -> origin/main for the default-path derivation (IT4)
git -C "$WORK" remote set-head origin main 2>/dev/null || true

git -C "$WORK" checkout -q main
# EC5 wrinkle: make the LOCAL ai/integration stale (point at C0) so any use of the
# local branch instead of origin/ai/integration would be detectable.
git -C "$WORK" branch -f ai/integration "$C0"

# ---- IT1 (AC1) + EC5: Step 0.1 --base template ----
BASE_BRANCH=ai/integration
BASE_REF=origin/$BASE_BRANCH
if git -C "$WORK" fetch -q origin "$BASE_BRANCH"; then
  if git -C "$WORK" checkout -q -b feat/TEST-IT1 "$BASE_REF"; then ok "IT1 checkout -b from \$BASE_REF succeeded"; else bad "IT1 checkout -b failed"; fi
else
  bad "IT1 git fetch origin ai/integration failed"
fi
if git -C "$WORK" merge-base --is-ancestor "$C2" HEAD; then ok "IT1 C2 is ancestor of feature HEAD"; else bad "IT1 C2 NOT ancestor (origin ref not used?)"; fi
if git -C "$WORK" merge-base --is-ancestor "$C1" HEAD 2>/dev/null; then bad "IT1 C1 unexpectedly ancestor (branched from main?)"; else ok "IT1 C1 not ancestor (EC5: stale local branch ignored)"; fi

# ---- IT2 (AC2): Step 6 --base template after a feature commit C3 ----
echo c3 > "$WORK/feature.txt"
git -C "$WORK" add -A && git -C "$WORK" commit -qm C3
MB2="$(git -C "$WORK" merge-base HEAD "$BASE_REF")"
if [ "$MB2" = "$C2" ]; then ok "IT2 merge-base HEAD \$BASE_REF == C2"; else bad "IT2 merge-base != C2 (got $MB2)"; fi
DIFF2="$(git -C "$WORK" diff --name-only "$MB2"..HEAD)"
case "$DIFF2" in *feature.txt*) ok "IT2 diff includes feature.txt (C3)";; *) bad "IT2 diff missing feature.txt";; esac
case "$DIFF2" in *main-only.txt*) bad "IT2 diff wrongly includes main-only.txt (C1)";; *) ok "IT2 diff excludes main-only.txt";; esac

# ---- IT3 (AC5): Step 8b --base template — same merge-base semantics as IT2 ----
MB3="$(git -C "$WORK" merge-base HEAD "$BASE_REF")"
if [ "$MB3" = "$C2" ]; then ok "IT3 Step 8b merge-base HEAD \$BASE_REF == C2"; else bad "IT3 merge-base != C2 (got $MB3)"; fi
LOG3="$(git -C "$WORK" log --oneline "$MB3"..HEAD)"
case "$LOG3" in *C3*) ok "IT3 log includes C3";; *) bad "IT3 log missing C3";; esac

# ---- EC4: already checked out on the base branch -> create from origin/<base> ----
git -C "$WORK" checkout -q ai/integration            # local (stale) branch, name == BASE_BRANCH
if git -C "$WORK" checkout -q -b feat/TEST-EC4 "$BASE_REF"; then
  if [ "$(git -C "$WORK" rev-parse HEAD)" = "$C2" ]; then ok "EC4 recreation from \$BASE_REF lands on C2 (not stale C0)"; else bad "EC4 recreation not on C2"; fi
else
  bad "EC4 checkout -b from \$BASE_REF failed"
fi

# ---- IT4 (AC4): default path — unchanged Step 0.1/6 derivation, no BASE ----
git -C "$WORK" checkout -q --detach "$C2"            # sit on ai/integration lineage, off main
DEF_BRANCH="$(git -C "$WORK" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo main)"
[ -z "$DEF_BRANCH" ] && DEF_BRANCH=main
if [ "$DEF_BRANCH" = "main" ]; then ok "IT4 default derivation yields BASE_BRANCH=main"; else bad "IT4 default derivation got '$DEF_BRANCH'"; fi
git -C "$WORK" checkout -q -b feat/TEST-IT4          # no start-point: created from current HEAD
if [ "$(git -C "$WORK" rev-parse HEAD)" = "$C2" ]; then ok "IT4 branch created from current HEAD (C2)"; else bad "IT4 branch not from current HEAD"; fi
MB4="$(git -C "$WORK" merge-base HEAD "$DEF_BRANCH")"
if [ "$MB4" = "$C0" ]; then ok "IT4 merge-base against derived main == C0 (C0-lineage)"; else bad "IT4 merge-base != C0 (got $MB4)"; fi

# ---- IT5 (error contract): fetch of a nonexistent remote branch must fail ----
if git -C "$WORK" fetch -q origin no-such-branch-xyz 2>/dev/null; then
  bad "IT5 fetch of nonexistent branch unexpectedly succeeded"
else
  ok "IT5 fetch of nonexistent branch exits non-zero (hard-stop observable)"
fi

printf '\n=== Summary ===\n'
printf 'passed=%d failed=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
