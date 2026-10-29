#!/usr/bin/env bash
#
# verify-foundry-surface.sh — verification harness for issue-14
# (shared Foundry surface: F1–F4 operations + runbook)
#
# Test command for specs/issue-14-spec.md. Exit 0 = all assertions pass.
#
# Seams (per spec ## Test Strategy):
#   S1 (static)   — `rg` assertions pin load line, recipe centralization,
#                   decision-table rules, allowlist patterns, runbook headings.
#   S2 (behavior) — fake-`gh` shim execution of extracted F1/F2/F3 recipes
#                   against fixture JSON (0-node, 1-node, 2-node, option-missing,
#                   no-op, idempotency cases).
#   S3 (fixtures)  — python3 validation of rendered result-comment template
#                    (marker first line + frozen 7-field vocabulary) and
#                    structural parse of F4 YAML block.
#   S4 (manual)    — live-`gh` E2E checklist (not automatable here).
#
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$REPO_ROOT/skills/foundry-headless-contract/SKILL.md"
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

# count_occ <label> <fixed-string> <expected-occurrences> <file>
count_occ() {
  local n
  n="$(rg -aoF -- "$2" "$4" | wc -l | tr -d ' ')" || n=0
  if [ "$n" -eq "$3" ]; then ok "$1 (count=$n)"; else bad "$1 — expected $3 occurrences of '$2', got $n"; fi
}

if [ ! -f "$SKILL" ]; then
  printf 'FATAL: cannot find %s\n' "$SKILL" >&2
  exit 2
fi

printf '=== Sub-task 1 — surface scaffold + F1 project discovery (seam S1) ===\n'

# UT1 — load line present in letsgo.md (AC1)
contains "UT1 Load skill: foundry-headless-contract in letsgo.md" "$CMD" 'Load skill: foundry-headless-contract'

# UT2 — absence pins in letsgo.md (AC1)
absent "UT2 gh project item-edit absent from letsgo.md" "$CMD" 'gh project item-edit'
absent "UT2 gh project field-list absent from letsgo.md" "$CMD" 'gh project field-list'
absent "UT2 projectsV2(first:10) absent from letsgo.md" "$CMD" 'projectsV2(first:10)'
absent "UT2 select(.body | contains(\"<!-- opencode-flow:result -->\")) absent from letsgo.md" "$CMD" 'select(.body | contains("<!-- opencode-flow:result -->"))'
absent "UT2 -X PATCH -F body=@ absent from letsgo.md" "$CMD" '-X PATCH -F body=@'

# UT3 — skill frontmatter pins
contains "UT3 name: foundry-headless-contract" "$SKILL" 'name: foundry-headless-contract'
contains "UT3 non-empty description in frontmatter" "$SKILL" 'description: Shared Foundry surface'

# UT4 — F1 pins
contains "UT4 F1 projectsV2 graphql recipe with \$-variables" "$SKILL" 'timeout 120 gh api graphql -f query'
contains "UT4 exactly-one fail-closed rule" "$SKILL" 'Exactly one project node'
contains "UT4 fallback rule (owner.login null)" "$SKILL" 'When `owner.login` is null, parse'
contains "UT4 F1_UNRESOLVED zero-writes rule" "$SKILL" 'F1_UNRESOLVED'
contains "UT4 never cached rule" "$SKILL" 'Never cached'

printf '\n=== Sub-task 2 — F2 status write decision table (seam S1) ===\n'

# UT5 — F2 decision-table pins
contains "UT5 F2 field-list precheck recipe" "$SKILL" 'timeout 120 gh project field-list'
contains "UT5 F2_OPTION_MISSING zero-writes rule" "$SKILL" 'F2_OPTION_MISSING'
contains "UT5 no-op success rule (current == target)" "$SKILL" 'no-op success'
contains "UT5 never field-create rule" "$SKILL" 'Never `field-create`'
contains "UT5 never Ready/Integrated rule" "$SKILL" 'Never write `Ready` or `Integrated`'
contains "UT5 exact case-sensitive rule" "$SKILL" 'exact, case-sensitive'

printf '\n=== Sub-task 3 — F3 result-comment upsert (seam S1) ===\n'

# UT6 — F3 pins
contains "UT6 F3 marker literal" "$SKILL" '<!-- opencode-flow:result -->'
contains "UT6 F3 find-jq recipe" "$SKILL" '--jq '"'"'.[] | select(.body | contains('
contains "UT6 F3 explicit -X PATCH rule" "$SKILL" '-X PATCH'
contains "UT6 F3 create path" "$SKILL" 'Create (if not found)'
contains "UT6 F3 token-hygiene rule" "$SKILL" 'Token hygiene'
contains "UT6 F3 delete-after-upsert rule" "$SKILL" 'Delete `$RESULT_COMMENT_FILE` after upsert'
contains "UT6 F3 F1-independence rule" "$SKILL" 'F1-independence'

printf '\n=== Sub-task 4 — F4 allowlist + runbook (seam S1) ===\n'

# UT7 — F4 pins
contains "UT7 gh project * allowlist pattern" "$SKILL" '"gh project *": allow'
contains "UT7 gh pr * allowlist pattern" "$SKILL" '"gh pr *": allow'
contains "UT7 gh issue * allowlist pattern" "$SKILL" '"gh issue *": allow'
contains "UT7 gh api * allowlist pattern" "$SKILL" '"gh api *": allow'

# UT8 — runbook pins
contains "UT8 ## Runbook heading" "$SKILL" '## Runbook'
contains "UT8 ownership table In Progress/Blocked" "$SKILL" 'Command lifecycle via F2'
contains "UT8 ownership table Ready /brainstorm" "$SKILL" '/brainstorm'
contains "UT8 ownership table Integrated host reconciler" "$SKILL" 'Host reconciler'
contains "UT8 ownership table result comment via F3" "$SKILL" 'Command via F3'
contains "UT8 board-absent behavior sentence" "$SKILL" 'F1 fails closed'
contains "UT8 sandbox install note" "$SKILL" 'Sandbox install note'

printf '\n=== Sub-task 5 — consumer glob (AC1, seam S1) ===\n'

# UT9 — consumer glob: for every commands/*.md that uses board/comment writes, load line must be present
# Exempt brainstorm.md (findings Out-of-scope)
CONSUMER_COUNT=0
MISSING_LOAD=0
for cmdfile in "$REPO_ROOT"/commands/*.md; do
  [ -f "$cmdfile" ] || continue
  base="$(basename "$cmdfile")"
  [ "$base" = "brainstorm.md" ] && continue
  
  # Check if file contains board or comment write patterns
  if rg -qF 'gh project item-edit' "$cmdfile" || rg -qF 'opencode-flow:result' "$cmdfile"; then
    CONSUMER_COUNT=$((CONSUMER_COUNT+1))
    if ! rg -qF 'Load skill: foundry-headless-contract' "$cmdfile"; then
      bad "UT9 $base uses board/comment writes but missing load line"
      MISSING_LOAD=$((MISSING_LOAD+1))
    fi
  fi
done
if [ "$MISSING_LOAD" -eq 0 ]; then
  ok "UT9 all $CONSUMER_COUNT consumer(s) have load line"
fi

printf '\n'
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32mAll S1 assertions passed\033[0m (PASS=%d, FAIL=%d)\n' "$PASS" "$FAIL"
  exit 0
else
  printf '\033[31mSome S1 assertions failed\033[0m (PASS=%d, FAIL=%d)\n' "$PASS" "$FAIL"
  exit 1
fi
