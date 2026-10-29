#!/usr/bin/env bash
#
# verify-review-pr.sh — verification harness for issue-15
# (/review-pr bounded repair loop governor)
#
# Test command for specs/issue-15-spec.md. Exit 0 = all assertions pass.
#
# Seams (per spec ## Test Strategy):
#   S1 (static)   — `rg` assertions pin canonical gh/git strings, bounds,
#                   agent names, exit vocabulary, forbidden patterns
#   S2 (cross-consumer) — verify-foundry-surface.sh UT9 counts review-pr.md
#   S3 (live-gh)  — manual E2E checklist (not exercised by this harness)
#
# This repo has no test runner; this script IS the executable test command.
#
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CMD="$REPO_ROOT/commands/review-pr.md"

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

# count_occ <label> <fixed-string> <expected-occurrences> <file>
count_occ() {
  local n
  n="$(rg -aoF -- "$2" "$4" | wc -l | tr -d ' ')" || n=0
  if [ "$n" -eq "$3" ]; then ok "$1 (count=$n)"; else bad "$1 — expected $3 occurrences of '$2', got $n"; fi
}

# hook_near <label> <hook-token> <anchor-string> [window]
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
    [ "$found" -eq 0 ] && okall=0
  done <<< "$alines"
  if [ "$okall" -eq 1 ]; then ok "$label"; else bad "$label — hook '$token' not within ±$win lines of anchor '$anchor'"; fi
}

if [ ! -f "$CMD" ]; then
  printf 'FATAL: cannot find %s\n' "$CMD" >&2
  exit 2
fi

printf '=== UT-parse — frontmatter + argument parsing (seam S1) ===\n'

contains "UT1 model: opencode/qwen3.6-plus" "$CMD" 'model: opencode/qwen3.6-plus'
contains "UT2 Load skill: foundry-headless-contract" "$CMD" 'Load skill: foundry-headless-contract'
count_occ "UT3 --max-attempts default 2" '--max-attempts' 3 "$CMD"  # Step 0 parse + Step 5 loop + Step 6 exhaustion
contains "UT4 --poll-interval default 60" "$CMD" '--poll-interval'
contains "UT5 --deadline default 900" "$CMD" '--deadline'
contains "UT6 --merge-mode validation present" "$CMD" '--merge-mode requires auto or direct'

printf '\n=== UT-gate — PR metadata fetch + gate table (seam S1) ===\n'

contains "UT7 gh pr view --json gate fields" "$CMD" 'gh pr view "$PR_REF" --json number,url,state,isDraft,baseRefName,headRefName,headRefOid,autoMergeRequest,body,repository'
contains "UT8 gh repo view --json nameWithOwner" "$CMD" 'gh repo view --json nameWithOwner'
contains "UT9 draft guard isDraft == false" "$CMD" 'isDraft == false'
contains "UT10 skip exit line" "$CMD" '⏭️  review-pr: skipping PR'

printf '\n=== UT-poll — bounded check polling (seam S1) ===\n'

contains "UT11 gh pr checks --json bucket" "$CMD" 'gh pr checks "$PR_REF" --json name,bucket,link'
# UT12 — --watch must not appear as a composed command (prose mentions it as forbidden)
absent "UT12 --watch forbidden" "$CMD" 'gh pr checks --watch '
contains "UT13 bucket classification prose" "$CMD" 'bucket'
contains "UT14 deadline exit line" "$CMD" '⏳ review-pr: checks still pending at deadline'

printf '\n=== UT-green — merge path assertions (seam S1) ===\n'

contains "UT15 auto merge canonical" "$CMD" 'gh pr merge "$PR_REF" --auto --merge'
contains "UT16 direct merge canonical" "$CMD" 'gh pr merge "$PR_REF" --merge'
absent "UT17 --squash forbidden" "$CMD" '--squash'
absent "UT18 --rebase forbidden" "$CMD" '--rebase'
contains "UT19 autoMergeRequest re-check" "$CMD" 'autoMergeRequest'
contains "UT20 make ci bounded" "$CMD" 'make ci'

printf '\n=== UT-red — repair cycle assertions (seam S1) ===\n'

contains "UT21 @code-reviewer" "$CMD" '@code-reviewer'
contains "UT22 @standards-reviewer" "$CMD" '@standards-reviewer'
contains "UT23 @spec-fidelity-reviewer" "$CMD" '@spec-fidelity-reviewer'
contains "UT24 @code-review-filter" "$CMD" '@code-review-filter'
contains "UT25 @code-fixer" "$CMD" '@code-fixer'
contains "UT26 @spec-implementer" "$CMD" '@spec-implementer'
# UT27/UT28 — check the dispatch section (Step 5.4), not the negative "cannot invoke other commands" sentence
absent "UT27 @code-review absent" "$CMD" '@code-review '  # space after to avoid matching @code-reviewer
absent "UT28 /code-review absent" "$CMD" '/code-review'
contains "UT29 gh run view --log-failed" "$CMD" 'gh run view'
contains "UT30 --log-failed pin" "$CMD" '--log-failed'
contains "UT31 tail bound" "$CMD" 'tail -c 20000'
contains "UT32 no-progress exit" "$CMD" '⚠️  review-pr: no progress'
contains "UT33 git add -A -- specs excluded" "$CMD" "git add -A -- ':!specs/'"

printf '\n=== UT-exhaust — exhaustion + surface ops (seam S1) ===\n'

contains "UT34 exhausted exit line" "$CMD" '🛑 review-pr: exhausted'
contains "UT35 Blocked via F2 named" "$CMD" 'Blocked'
contains "UT36 F3 head SHA memoization" "$CMD" 'head <SHA>'
# UT37 — gh pr close must NOT be composed as an action (check for the command invocation pattern)
absent "UT37 gh pr close absent" "$CMD" 'gh pr close "$PR'
# UT39 — Integrated must not be written as a status value
absent "UT39 Integrated absent" "$CMD" '--value "Integrated"'

printf '\n=== UT-hygiene — token + push safety (seam S1) ===\n'

absent "UT40 GH_TOKEN absent" "$CMD" 'GH_TOKEN'
absent "UT41 gh auth token absent" "$CMD" 'gh auth token'
contains "UT42 git push origin" "$CMD" 'git push origin "$HEAD_BRANCH"'
# UT43 — --force must not appear on git push (check the actual push line)
absent "UT43 --force forbidden" "$CMD" 'git push.*--force'
absent "UT44 -f forbidden" "$CMD" 'push.*-f'

printf '\n=== UT-bounds — timeout wrapping (seam S1) ===\n'

count_occ "UT45 timeout 120 occurrences" 'timeout 120' 13 "$CMD"
contains "UT46 timeout 1800 make ci" "$CMD" 'timeout 1800 make ci'

printf '\n'
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32mAll S1 assertions passed\033[0m (PASS=%d, FAIL=%d)\n' "$PASS" "$FAIL"
  exit 0
else
  printf '\033[31mSome S1 assertions failed\033[0m (PASS=%d, FAIL=%d)\n' "$PASS" "$FAIL"
  exit 1
fi
