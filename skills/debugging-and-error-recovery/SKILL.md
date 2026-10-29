---
name: debugging-and-error-recovery
description: Use when a test/build/runtime action fails repeatedly or a hard bug/performance regression needs diagnosis.
---

# Debugging and Error Recovery

## When to use

When a test, build, lint, or runtime action fails — especially more than once — or when diagnosing a hard bug or performance regression. Do not guess at fixes; follow the phases. Read `GLOSSARY.md` if present; respect `decisions.md` for the area.

## Redaction

Redact every secret first (`<REDACTED>`). Build loops against env vars so credentials stay out of captured output. Quote only lines carrying signal. If redacted output is insufficient, say so and ask.

## Phase 1 — Build a feedback loop

**This is the skill.** A tight pass/fail signal that goes red on *this* bug is what finds the cause; everything else consumes it. Spend disproportionate effort here.

Ways to construct one, in order:
1. Failing test at the seam that reaches the bug (unit, integration, e2e).
2. Curl/HTTP script against a dev server.
3. CLI invocation with a fixture, diffing stdout against a known-good snapshot.
4. Replay a captured trace (request/payload/event log) through the code path.
5. Throwaway harness: minimal subset of the system exercising the bug path.
6. Bisection harness: automate "boot at state X, check" so `git bisect run` works.
7. Differential loop: same input through old vs new version (or two configs), diff outputs.
8. Human-in-the-loop script: last resort; give a structured, repeatable script and feed captured output back.

Tighten it: faster (cache setup, narrow scope), sharper (assert the symptom, not "didn't crash"), more deterministic (pin time, seed RNG, isolate filesystem/network).

Non-deterministic bugs: aim for a higher reproduction rate, not a clean repro — loop 100×, parallelise, add stress, narrow timing. 50% is debuggable; 1% is not.

Completion criterion — one command you have already run (show invocation + redacted output) that is:
- [ ] **Red-capable**: drives the bug path and asserts the exact symptom.
- [ ] **Deterministic**: same verdict every run (or pinned high rate).
- [ ] **Fast**: seconds.
- [ ] **Agent-runnable**: unattended.

**Hard gate**: reading code to build a theory before this command exists is the exact failure this skill prevents. No red-capable command, no Phase 3.

If you genuinely cannot build a loop: stop, list what you tried, and ask for (a) access, (b) a redacted artifact (HAR/log/timestamped recording), or (c) permission for temporary instrumentation. This counts as a strike.

## Phase 2 — Reproduce and minimise

Run the loop; watch it go red. Confirm:
- [ ] The failure mode is the one **actually reported** (wrong bug = wrong fix).
- [ ] It reproduces across runs (or at a pinned high rate).
- [ ] You captured the exact symptom for later verification.

Minimise: cut inputs, callers, config, data, steps **one at a time**, re-running after each cut. Done when every remaining element is load-bearing. Narrow to the file/function/line and failure type; use `grep`, `glob`, targeted `read`. Do not proceed until you can point to a location.

## Phase 3 — Hypothesise

Generate **3–5 ranked hypotheses** before testing any. Each must be falsifiable:

> "If <X> is the cause, then <changing Y> makes the bug disappear / <changing Z> makes it worse."

No prediction = a vibe; discard or sharpen. Show the ranked list when a user is available; proceed with your ranking if AFK.

## Phase 4 — Instrument

Each probe maps to a Phase 3 prediction. **Change one variable at a time.**

1. Debugger/REPL if supported — one breakpoint beats ten logs.
2. Targeted logs at hypothesis-distinguishing boundaries.
3. Never "log everything and grep".

Tag every debug log with a unique prefix (`[DEBUG-a4f2]`); cleanup becomes one grep.

Perf branch: establish a baseline (timing harness, profiler, query plan), then bisect. Measure first, fix second.

## Phase 5 — Fix and guard

Write the regression test **before the fix**, but only at a **correct seam** — a boundary where the test exercises the real bug pattern as it occurs at the call site. A too-shallow seam (single-caller test for a multi-caller bug; unit test that can't replicate the trigger chain) gives false confidence. **If no correct seam exists, that is the finding** — note it in `progress.md`.

If a correct seam exists:
1. Turn the minimised repro into a failing test.
2. Watch it fail; if you forced red by mutating code/fixtures, `diff` against a pristine copy.
3. Apply the **smallest possible fix**. No refactor, no polish, no adjacent issues.
4. Watch it pass.
5. Re-run the Phase 1 loop against the original scenario.

Still failing → return to Phase 3 with new evidence; do not repeat the same hypothesis.

## Phase 6 — Cleanup

- [ ] Original repro no longer reproduces (re-run Phase 1 loop)
- [ ] Regression test passes (or absent seam documented in `progress.md`)
- [ ] All `[DEBUG-...]` instrumentation removed (`grep` the prefix)
- [ ] Throwaway harnesses/prototypes deleted
- [ ] Correct hypothesis stated in commit message or progress evidence

## Stop-the-line rule

If the Phase 5 fix introduces a **new** failure in a previously-passing test, stop. Revert and return to Phase 3 with the new failure as evidence. A fix that breaks something else is not a fix.

## 3-strike escalation

If the same action fails **3 consecutive times** despite following the phases:
1. **Do not guess** a fourth approach.
2. **Log** in `progress.md` under `## Errors`: the action, the three approaches, and each output.
3. **Escalate** with: what you were doing, what failed, suspected root cause, recommended next step.

Failing to build a feedback loop after three genuine attempts triggers the same escalation. This fires *within* a single pass; the skill's loop budgets govern re-entry of the whole implementer/reviewer.

## Finding the test command

First match wins: `## Test`/`## Tests`/`## Testing` in `AGENTS.md`, then `README.md`; then a `test:` target in `Makefile`. Else heuristics: `pytest`, `npm test` (`package.json`), `go test ./...` (`go.mod`), `cargo test` (`Cargo.toml`). If none, **skip with a printed note** — never guess a stack.
