#!/usr/bin/env bash
# test-issue-flow-005.sh — Unit tests for issue-flow-005 changes
# Verifies agent configuration changes per the spec's Test Strategy.

set -euo pipefail

PASS=0
FAIL=0

assert_contains() {
  local file="$1" pattern="$2" label="$3"
  if grep -qF "$pattern" "$file"; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label — pattern not found: $pattern"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local file="$1" pattern="$2" label="$3"
  if grep -qF "$pattern" "$file"; then
    echo "FAIL: $label — pattern should NOT be present: $pattern"
    FAIL=$((FAIL + 1))
  else
    echo "PASS: $label"
    PASS=$((PASS + 1))
  fi
}

DOD="agents/dod-evaluator.md"
SPEC="agents/spec-analyst.md"

echo "=== Unit Tests for issue-flow-005 ==="
echo ""

# Test 1: dod-evaluator frontmatter parses with tools.bash: true
assert_contains "$DOD" "  bash: true" "dod-evaluator has tools.bash: true"

# Test 2: dod-evaluator permission.bash allowlist intact
assert_contains "$DOD" '"pytest*": allow' "dod-evaluator has pytest in bash allowlist"
assert_contains "$DOD" '"npm test*": allow' "dod-evaluator has npm test in bash allowlist"
assert_contains "$DOD" '"pnpm test*": allow' "dod-evaluator has pnpm test in bash allowlist"
assert_contains "$DOD" '"yarn test*": allow' "dod-evaluator has yarn test in bash allowlist"
assert_contains "$DOD" '"go test*": allow' "dod-evaluator has go test in bash allowlist"
assert_contains "$DOD" '"cargo test*": allow' "dod-evaluator has cargo test in bash allowlist"
assert_contains "$DOD" '"git status*": allow' "dod-evaluator has git status in bash allowlist"
assert_contains "$DOD" '"git diff --stat*": allow' "dod-evaluator has git diff --stat in bash allowlist"

# Test 3: dod-evaluator frontmatter still has edit: deny
assert_contains "$DOD" "  edit: deny" "dod-evaluator has edit: deny in permission"
assert_contains "$DOD" "  edit: false" "dod-evaluator has edit: false in tools"

# Test 4: dod-evaluator has Step 2.5
assert_contains "$DOD" "2.5." "dod-evaluator has Step 2.5"
assert_contains "$DOD" "Independently re-run the test command" "dod-evaluator Step 2.5 has re-run instruction"
assert_contains "$DOD" "discrepancy note" "dod-evaluator Step 2.5 has discrepancy note handling"
assert_contains "$DOD" "UNVERIFIED" "dod-evaluator Step 2.5 has UNVERIFIED fallback"

# Test 5: spec-analyst Phase 5 template contains ### Test Command
assert_contains "$SPEC" "### Test Command" "spec-analyst Phase 5 has Test Command field"

# Test 6: spec-analyst Phase 5 template structure otherwise unchanged
assert_contains "$SPEC" "### Unit Tests" "spec-analyst Phase 5 still has Unit Tests"
assert_contains "$SPEC" "### Integration Tests" "spec-analyst Phase 5 still has Integration Tests"
assert_contains "$SPEC" "### E2E Scenarios" "spec-analyst Phase 5 still has E2E Scenarios"
assert_contains "$SPEC" "### Edge Cases" "spec-analyst Phase 5 still has Edge Cases"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
