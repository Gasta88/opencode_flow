---
name: debugging-and-error-recovery
description: Five-step error triage (reproduce → localize → reduce → fix → guard), stop-the-line rule, and 3-strike escalation. Use when a test, build, or runtime action fails repeatedly.
---

# Debugging and Error Recovery

## When to use

Invoke this skill whenever a test, build, lint, or runtime action fails — especially when the same action fails more than once in a row. Do not guess at fixes; follow the steps.

## The five steps

### 1. Reproduce

Run the failing action and capture the full output. Do not attempt to fix anything until you can reproduce the failure reliably. Record the exact command and output.

### 2. Localize

Narrow the failure to the smallest possible scope:
- Which file? Which function? Which line?
- Is it a syntax error, a type error, a runtime exception, or a test assertion failure?
- Use `grep`, `glob`, and targeted `read` to find the relevant code.

Do not proceed until you can point to a specific location.

### 3. Reduce

Strip away everything unrelated to the failure. If the error is in a test, run only that test. If it is in a module, isolate the minimal reproduction. The goal is to eliminate noise so the root cause is visible.

### 4. Fix

Apply the smallest possible change that resolves the failure. Do not refactor, do not polish, do not address adjacent issues. Fix the one thing that is broken.

After applying the fix, re-run the action from Step 1. If it passes, proceed to Step 5. If it fails, return to Step 2 with the new output.

### 5. Guard

Add or update a test that would have caught this failure. If a test already exists, ensure it covers the edge case that triggered the bug. Do not skip this step — a fix without a guard is a regression waiting to happen.

## Stop-the-line rule

If the fix from Step 4 introduces a **new** failure in a previously-passing test, stop immediately. Do not continue iterating. Revert the fix and return to Step 2. A fix that breaks something else is not a fix.

## 3-strike escalation

If the same action fails **3 consecutive times** despite following the five steps:

1. **Do not guess.** Do not try a fourth approach based on intuition.
2. **Log the failure** in `progress.md` under `## Errors` with:
   - The action that failed
   - The three approaches attempted
   - The output of each attempt
3. **Escalate to the user** with a concise summary:
   - What you were trying to do
   - What failed each time
   - What you believe the root cause is (if known)
   - What you recommend the user do next

This rule applies inside all loops governed by the `spec-driven-workflow` skill. The loop budgets (`--max-impl-passes`, `--max-fix-passes`) in that skill are separate from this 3-strike rule — the 3-strike rule fires *within* a single pass, while the loop budgets govern re-entry of the entire implementer/reviewer.

## Finding the test command

When you need to run tests but do not know the command, look it up in this order (first match wins):

1. **AGENTS.md** — look for a `## Test` / `## Tests` / `## Testing` heading
2. **README.md** — same headings
3. **Makefile** — look for a `test:` target

If none of these yield a command, fall back to heuristics:
- `pytest` / `pytest tests/` if `pytest` is in the project
- `npm test` if `package.json` exists
- `go test ./...` if `go.mod` exists
- `cargo test` if `Cargo.toml` exists

If no test command can be found, **skip with a printed note** — never guess a stack.
