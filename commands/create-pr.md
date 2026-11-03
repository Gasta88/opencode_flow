---
description: Create a PR automatically with a derived title and structured description
agent: build
model: opencode/qwen3.5-plus
---

# Create PR

**Autonomy**: Never ask the user to confirm the title, description, or commit. Derive everything and proceed. Stop only for: a sensitive-file match, unauthenticated `gh`, or a failed `gh pr create`.

## Step 1 — Commit any uncommitted changes

Run `git status --short`; clean → Step 2. Otherwise:

1. Print the full list of changed files.
2. Scan for `.env`, `.env.*`, `*.pem`, `*.key`, `*credentials*`, `*secret*`, `.DS_Store`. Match → stop:
   `⚠️  <file> matches a sensitive-file pattern. Remove it or add to .gitignore before re-running /create-pr.`
3. Generate a commit message from the diff; print it with the file list, then run `git add -A && git commit -m "<message>"` without asking.

## Step 2 — Analyse changes

```bash
BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo main)
[ -z "$BASE_BRANCH" ] && BASE_BRANCH=main
git status --short
git branch --show-current
git diff $(git merge-base HEAD $BASE_BRANCH)..HEAD
git log $(git merge-base HEAD $BASE_BRANCH)..HEAD --oneline
```

Derive `PR_TITLE` without asking and ignoring any supplied argument. In order:

1. Exactly one commit since the merge-base → use its subject.
2. Otherwise humanize the branch name: strip a leading `feat/`, `fix/`, `chore/`, `docs/`, `refactor/`, or `test/`; strip an issue key and a `YYYYMMDDHHMMSS` suffix; replace `-` and `_` with spaces; sentence case the result.
3. Fallback → the first commit subject, then `Update <BASE_BRANCH>`.

Truncate `PR_TITLE` to 72 characters.

## Step 3 — Gather evidence

Run the test suite if one exists and capture output; for a new/fixed test, note its name and before/after result. Visual change → screenshots if feasible, else execution evidence. No automated evidence → state what is true (e.g. "manual smoke test: <what was exercised>"). Never invent evidence.

## Step 4 — Draft the PR description

Skip preambles; keep prose brief; use project domain language (`GLOSSARY.md` if present). Do not ask the user to approve the description; write it and continue.

```markdown
## Summary

<the smallest visual that makes the key point clear — see guidance below>

## Evidence

- **Before:** <screenshot/output/failing test run>
  **After:** <screenshot/output/passing test run>

## Merge Danger

**Door:** <one-way | two-way>

<optional: one-sentence description>

**Blast Radius:** <one-word description>

<optional: potential ramifications of merge>

## Related Issues
- <issue keys mentioned in commit messages, e.g. FEAT-123>
```

### Summary guidance

Pick the smallest view; one visual is usually enough. Options: pseudocode (logic/algorithm), call tree (runtime flow), component tree (UI structure), shallow annotated file tree (responsibilities/refactor), Mermaid (interaction/data flow), `+`/`-` diff sketch (shape already exists), full block (mostly new).

### Evidence guidance

Screenshots are S-tier for visual changes; execution evidence (test/console output) is A-tier — show the exact test that failed before and passes now.

### Merge Danger guidance

- **Door**: two-way = cheap revert; one-way = destructive actions, schema drops, migrations, removed public API, hard-to-reverse decisions.
- **Blast Radius**: one word (`none`, `single-module`, `all-consumers`, `schema`) plus optional ramifications (consumer breakage, layout shift, migrations).

## Step 5 — Write the description to disk

Write it to `pr-description.md` in the repo root. Never commit it — it is a working artefact.

## Step 6 — Create the PR

```bash
gh pr create --title "$PR_TITLE" --body-file pr-description.md
```

Not authenticated → stop and tell the user to run `gh auth login`.

## Step 7 — Clean up

```bash
rm pr-description.md
```

Print the PR URL returned by `gh pr create`.
