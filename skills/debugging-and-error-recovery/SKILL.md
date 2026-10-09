---
name: debugging-and-error-recovery
description: Six-phase diagnosis loop (feedback loop → reproduce+minimise → hypothesise → instrument → fix+guard → cleanup), stop-the-line rule, and 3-strike escalation. Use when a test, build, or runtime action fails repeatedly, or when diagnosing a hard bug or performance regression.
---

# Debugging and Error Recovery

## When to use

Invoke this skill whenever a test, build, lint, or runtime action fails — especially when the same action fails more than once in a row — or when diagnosing a hard bug or a performance regression. Do not guess at fixes; follow the phases. Skip phases only when explicitly justified.

When exploring the codebase, read `GLOSSARY.md` (if it exists) for a clear mental model of the relevant modules, and respect recorded decisions in `decisions.md` for the area you are touching.

## Redaction

This skill has you capture commands, outputs, and artifacts. **Redact every secret first**: write `<REDACTED>` in its place. Build loops against env vars so credentials stay in the environment rather than in captured output. Captured artifacts carry auth headers: quote only the lines that carry the signal. If the redacted output is not enough to diagnose, say so and ask the user.

## Phase 1 — Build a feedback loop

**This is the skill.** Everything else is mechanical. If you have a **tight** pass/fail signal that goes red on _this_ bug, you will find the cause; bisection, hypothesis-testing, and instrumentation all just consume it. If you don't have one, no amount of staring at code will save you. Spend disproportionate effort here.

### Ways to construct one, in roughly this order

1. **Failing test** at whatever seam reaches the bug: unit, integration, e2e.
2. **Curl / HTTP script** against a running dev server.
3. **CLI invocation** with a fixture input, diffing stdout against a known-good snapshot.
4. **Headless browser script** (Playwright / Puppeteer) that drives the UI and asserts on DOM/console/network.
5. **Replay a captured trace**: save a real request/payload/event log to disk; replay it through the code path in isolation.
6. **Throwaway harness**: spin up a minimal subset of the system (one service, mocked deps) that exercises the bug code path with a single function call.
7. **Property / fuzz loop**: if the bug is "sometimes wrong output", run many random inputs and look for the failure mode.
8. **Bisection harness**: if the bug appeared between two known states (commit, dataset, version), automate "boot at state X, check, repeat" so you can `git bisect run` it.
9. **Differential loop**: run the same input through old vs new version (or two configs) and diff outputs.
10. **Human-in-the-loop script**: last resort. If a human must click, give them a structured step-by-step script so the loop is still repeatable and their captured output feeds back to you.

### Tighten the loop

Treat the loop as a product. Once you have _a_ loop, tighten it:

- **Faster?** Cache setup, skip unrelated init, narrow the test scope.
- **Sharper signal?** Assert on the specific symptom, not "didn't crash".
- **More deterministic?** Pin time, seed RNG, isolate filesystem, freeze network.

A 30-second flaky loop is barely better than no loop; a 2-second deterministic one is a debugging superpower.

### Non-deterministic bugs

The goal is not a clean repro but a **higher reproduction rate**. Loop the trigger 100×, parallelise, add stress, narrow timing windows, inject sleeps. A 50%-flake bug is debuggable; 1% is not — keep raising the rate until it is.

### Completion criterion

Phase 1 is done when you can name **one command** (script path, test invocation, curl) that you have **already run at least once** (show the invocation and its redacted output), and that is:

- [ ] **Red-capable**: drives the actual bug code path and asserts the exact symptom, so it can go red on this bug and green once fixed — not "runs without erroring".
- [ ] **Deterministic**: same verdict every run (flaky bugs: a pinned, high reproduction rate).
- [ ] **Fast**: seconds, not minutes.
- [ ] **Agent-runnable**: you can run it unattended.

**Hard gate**: if you catch yourself reading code to build a theory before this command exists, stop — jumping straight to a hypothesis is the exact failure this skill prevents. No red-capable command, no Phase 3.

### When you genuinely cannot build a loop

Stop and say so explicitly. List what you tried. Ask the user for: (a) access to whatever environment reproduces it, (b) a redacted captured artifact (HAR file, log dump, screen recording with timestamps), or (c) permission to add temporary instrumentation. Do **not** proceed to hypothesise without a loop. This counts as a strike under the 3-strike rule.

## Phase 2 — Reproduce and minimise

Run the loop. Watch it go red as the bug appears. Confirm:

- [ ] The loop produces the failure mode that was **actually reported**, not a different failure that happens to be nearby. Wrong bug = wrong fix.
- [ ] The failure is reproducible across multiple runs (or at a pinned high rate for non-deterministic bugs).
- [ ] You have captured the exact symptom (error message, wrong output, slow timing) so later phases can verify the fix addresses it.

Then **minimise**: shrink the repro to the smallest scenario that still goes red. Cut inputs, callers, config, data, and steps **one at a time**, re-running the loop after each cut. Done when **every remaining element is load-bearing** — removing any one of them makes the loop go green.

Narrow the failure to the smallest possible scope: which file, which function, which line; syntax error, type error, runtime exception, or assertion failure. Use `grep`, `glob`, and targeted `read`. Do not proceed until you can point to a specific location.

Why bother: a minimal repro shrinks the hypothesis space and becomes the clean regression test in Phase 5.

## Phase 3 — Hypothesise

Generate **3–5 ranked hypotheses** before testing any of them. Single-hypothesis generation anchors on the first plausible idea.

Each hypothesis must be **falsifiable** — state the prediction it makes:

> "If <X> is the cause, then <changing Y> will make the bug disappear / <changing Z> will make it worse."

If you cannot state the prediction, the hypothesis is a vibe: discard or sharpen it.

Show the ranked list to the user when one is available — they often re-rank instantly ("we just deployed a change to #3"). Don't block on it; proceed with your ranking if the user is AFK (headless runs proceed silently).

## Phase 4 — Instrument

Each probe must map to a specific prediction from Phase 3. **Change one variable at a time.**

Tool preference:

1. **Debugger / REPL inspection** if the environment supports it. One breakpoint beats ten logs.
2. **Targeted logs** at the boundaries that distinguish hypotheses.
3. Never "log everything and grep".

**Tag every debug log** with a unique prefix, e.g. `[DEBUG-a4f2]`. Cleanup at the end becomes a single grep. Untagged logs survive; tagged logs die.

**Perf branch**: for performance regressions, logs are usually wrong. Instead establish a baseline measurement (timing harness, profiler, query plan), then bisect. Measure first, fix second.

## Phase 5 — Fix and guard

Write the regression test **before the fix**, but only if there is a **correct seam** for it: a boundary where the test exercises the real bug pattern as it occurs at the call site. If the only available seam is too shallow (a single-caller test when the bug needs multiple callers; a unit test that can't replicate the chain that triggered the bug), a regression test there gives false confidence. **If no correct seam exists, that itself is the finding** — note it in `progress.md`; the codebase architecture is preventing the bug from being locked down.

If a correct seam exists:

1. Turn the minimised repro into a failing test at that seam.
2. Watch it fail. If you forced the red by mutating code or a fixture, `diff` against a pristine copy to prove the mutation landed before you trust it.
3. Apply the **smallest possible fix**. Do not refactor, do not polish, do not address adjacent issues. Fix the one thing that is broken.
4. Watch it pass.
5. Re-run the Phase 1 feedback loop against the original (un-minimised) scenario.

If it still fails, return to Phase 3 with the new evidence — do not repeat the same hypothesis.

## Phase 6 — Cleanup

Required before declaring done:

- [ ] Original repro no longer reproduces (re-run the Phase 1 loop)
- [ ] Regression test passes (or absence of a correct seam is documented in `progress.md`)
- [ ] All `[DEBUG-...]` instrumentation removed (`grep` the prefix)
- [ ] Throwaway harnesses and prototypes deleted
- [ ] The hypothesis that turned out correct is stated in the commit message or progress evidence, so the next debugger learns

## Stop-the-line rule

If the fix from Phase 5 introduces a **new** failure in a previously-passing test, stop immediately. Do not continue iterating. Revert the fix and return to Phase 3 with the new failure as evidence. A fix that breaks something else is not a fix.

## 3-strike escalation

If the same action fails **3 consecutive times** despite following the phases:

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

Failing to build a feedback loop (Phase 1) after three genuine attempts triggers the same escalation.

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
