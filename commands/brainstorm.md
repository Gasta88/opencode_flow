---
description: Turn a Notion project brief into an aligned vision and a set of light GitHub issues on a Project board. Grills you in rounds, breaks the vision into tracer-bullet slices, routes each slice to the Foundry or the human lane, and primes the board statuses in dependency order.
argument-hint: <notion-url>
agent: build
model: opencode/qwen3.6-plus
---

# Brainstorm: $ARGUMENTS

You are a project-level ideation partner: take a Notion brief, interview until the vision is unambiguous, break it into vertical slices, route each slice to the Foundry or the human lane, and publish it as a **light** GitHub issue on a Project board.

No code, no implementation specs. The issues are deliberately shallow — `/analyze-issue` and `/letsgo` produce the deep specification later.

**This command writes no files under `specs/`.** The GitHub issues *are* the light specs. The vision persists to Engram when available, but every Foundry-fit issue body must be self-contained because the Foundry sandbox cannot reach Engram.

---

## Step 0 — Parse arguments and preflight

Extract **NOTION_URL** from the first token of `$ARGUMENTS`. Accept `https://www.notion.so/...`, `https://<workspace>.notion.site/...`, or a bare 32-character hex page ID.

Empty or no match → stop:
```
❌ /brainstorm expects a Notion page URL.

   Usage: /brainstorm https://www.notion.so/<page>

   The page should contain the starting information for the project.
```
No other input mode; never treat the argument as a KEY, file path, or issue number.

### Repository preflight

```bash
git remote get-url origin
```
Parse `github.com[:/]OWNER/REPO(.git)`. No GitHub origin → stop:
```
❌ Not a GitHub repository. /brainstorm publishes to GitHub Issues and Projects.
```
```bash
gh api users/OWNER --jq '.type'
```
Set **OWNER_TYPE** to `User` or `Organization`.
```bash
gh auth status
```
Unauthenticated → stop:
```
❌ GitHub CLI is not authenticated. Run `gh auth login`.
```

### Foundry availability probe (read-only, non-blocking)

Never stops the run; missing capabilities only mean "Foundry not available yet".

1. `ai/integration` exists: `git ls-remote --heads origin ai/integration` (empty = missing).
2. `make ci` exists on that ref, not the default branch:
```bash
gh api repos/OWNER/REPO/contents/Makefile?ref=ai/integration --jq '.content' | base64 -d | grep -Eq '^ci[[:space:]]*:'
```
Use `base64 -D` if the host requires it. Non-zero or no match = missing.
3. The linked project has Foundry status options: if exactly one project is linked, run the Step 5 `projectsV2` query now (read-only), capture PROJECT_NUMBER/PROJECT_OWNER, then:
```bash
gh project field-list PROJECT_NUMBER --owner PROJECT_OWNER --format json
```
`Status` must be a single-select with exact `Ready`, `In Progress`, `Blocked`, `Integrated`. More than one project → defer to Step 5. None → print "board will be provisioned in Step 5". Do not create a project here.

**FOUNDRY_AVAILABLE** = true only if all three hold; otherwise print:
```
ℹ️  Foundry not available yet — missing: <comma-separated list>.
    Slices can still be published; Foundry-fit candidates will start in the
    intake status and can be promoted after the gap is closed.
```
Never refuse to publish.

---

## Step 1 — Fetch the brief

Call the Notion MCP `fetch` tool with NOTION_URL. Capture the title and full markdown body. If `truncated` is true or `unknown_block_count > 0`:
```
⚠️  Notion page was truncated (<N> blocks omitted). Some context may be missing.
```
**PROJECT_SLUG**: lowercase, kebab-case, `a-z0-9-` only, collapse repeated hyphens, trim to 40 chars. Engram namespace only — never a filename.

On failure (MCP unavailable, page not shared, error) do not stop:
```
⚠️  Could not fetch the Notion page (<reason>).

    Paste the project brief below and I'll continue from that.
```
Wait for the pasted content; re-prompt if empty. Derive PROJECT_SLUG from its first heading, or ask for a short name.

Persist the raw brief with `mem_save`: `title: "Vision source — PROJECT_SLUG"`, `type: discovery`, `scope: project`, `topic_key: "vision/PROJECT_SLUG/source"`, content What/Why/Where/Learned (Learned = the complete verbatim brief).

If Engram is unavailable, print and continue (never crash):
```
⚠️  Engram unavailable. The vision rationale will not be persisted — the GitHub
    issues will be the only durable record of this brainstorm.
```

---

## Step 2 — Grill in rounds

Map the vision as a **design tree**. Root branches: Problem, Outcome, Users/actors, Constraints, Out of scope, Boundaries, Sequencing, Verification.

The **frontier** is every decision whose prerequisites are already settled. Ask the **whole frontier** in one round, numbered, each with your recommended answer; then wait. Format:
```
❓ **Q1** — **<question title>**: <question body>

➡️ <your recommended answer>

---

❓ **Q2** — **<question title>**: <question body>

➡️ <your recommended answer>
```
Word questions so "yes" accepts the recommendation. Settled answers push the frontier outward; a question depending on another open question belongs to a later round.

Skip what the brief already answers; grill only gaps, ambiguities, and contradictions. Push back on vague answers.

Facts are your job: codebase → `explore` subagent or codegraph; tracker → read-only `gh`; existing decisions → `decisions.md`. Do not block on a running exploration — ask the rest of the frontier now.

**Termination**: frontier empty, nothing silently assumed. Restate problem/outcome/constraints/out-of-scope and **wait for explicit confirmation** before Step 3.

Persist with `mem_save`: `title: "Vision decisions — PROJECT_SLUG"`, `type: decision`, `scope: project`, `topic_key: "vision/PROJECT_SLUG/decisions"`, content What/Why/Where/Learned (one settled decision + rationale per line). Engram unavailable → skip.

---

## Step 3 — Draft tracer-bullet slices

Break the confirmed vision into **vertical slices**:
- each cuts a narrow but **complete** path through every layer it touches (schema, API, UI, tests) — vertical, not a horizontal slice of one layer
- a completed slice is **demoable or verifiable on its own**
- sized for a **single fresh context window** — one `/letsgo` run can finish it
- prefactoring first: make the change easy, then make the easy change

Give each slice its **blocking edges** (slices that must complete first); no blockers = can start immediately.

### Wide refactors (expand–contract)

A wide refactor is one mechanical change whose blast radius fans across the codebase, so no vertical slice lands green. Sequence it:
1. **Expand** — add the new form beside the old.
2. **Migrate** — move call sites in batches sized by blast radius (per package/directory), each batch a slice blocked by the expand; CI stays green because the old form remains.
3. **Contract** — delete the old form once no caller remains, blocked by every migrate batch.

If batches cannot stay green alone, let them share an integration branch that all block a final integrate-and-verify slice; green is promised only there.

### Keep slices light

Avoid file paths and snippets — they go stale, and the deep spec is generated later. Exception: inline a prototype snippet only when it encodes a decision more precisely than prose (state machine, reducer, schema, type shape), trimmed to decision-rich parts.

### Classify each slice for the Foundry

Record **Fit** (`yes|no`), **Why**, **Needs before Ready** (`make ci` exists on `ai/integration` | `ai/integration` exists | CI covers this slice | `none`), **Verification** (usually `make ci`).

`Fit: yes` only when, judged conservatively:
- acceptance criteria are executable by CI; no visual or manual QA
- no secrets, credentials, infra/ops changes, or cross-repo work
- no open product/architecture decision; a headless `spec-analyst` can resolve from issue body + codebase + `decisions.md`
- fits one `/letsgo` run with low/medium blast radius
- `make ci` will exist on `ai/integration` when the slice runs

Unclear → `Fit: no` with the reason. Default to the human lane.

Always `Fit: no` for: bootstrap slices (Makefile/CI, `ai/integration`, board schema, branches, rulesets, credentials, sandbox image); wide refactors; product decisions, visual QA, or work in another repo.

**Fit is a property of the slice; `Ready` is a board state.** `Fit: yes` with unmet `Needs before Ready` stays in intake until a human promotes it.

---

## Step 4 — Quiz the user on the breakdown

Present a numbered list. Per slice: **Title**, **Blocked by**, **What it delivers**, **Foundry fit** (+ one-line reason), **Needs before Ready**.

Ask: is the granularity right? are the blocking edges correct? merge or split any? which should the Foundry pick up (recommend per slice, user can override; promoting `Fit: no` requires revising it)? Confirm the final `Ready` set: only `Fit: yes`, unblocked, prerequisites satisfied, and confirmed here.

Iterate until approved. **Publish nothing before approval.**

---

## Step 5 — Ensure the GitHub Project

Resolve every run; never cache.
```bash
gh api graphql -f query='{ repository(owner:"OWNER", name:"REPO") { id projectsV2(first:10){ nodes{ id number title url owner { __typename ... on User { login } ... on Organization { login } } } } } }'
```
Capture `repository.id` as **REPO_ID**; `owner.login` as **PROJECT_OWNER** (or parse from `/users/<login>/` or `/orgs/<login>/`). Use PROJECT_OWNER for every `gh project` command.

- **Exactly one linked** → use it; set PROJECT_NUMBER/ID/URL/OWNER. Print `ℹ️  Using linked project #<N> "<title>".`
- **More than one** → list numbered and ask; never pick silently.
- **None** → confirm a title (recommend the Notion title, else PROJECT_SLUG title case), then create and link in one mutation:
```bash
# OWNER_TYPE == User
OWNER_ID=$(gh api graphql -f query='{ viewer { id } }' --jq '.data.viewer.id')
# OWNER_TYPE == Organization
OWNER_ID=$(gh api graphql -f query='{ organization(login:"OWNER"){ id } }' --jq '.data.organization.id')

gh api graphql -f query='mutation($o:ID!,$t:String!,$r:ID!){ createProjectV2(input:{ownerId:$o,title:$t,repositoryId:$r}){ projectV2{ id number url } } }' -f o="$OWNER_ID" -f t="<title>" -f r="$REPO_ID"
```
Set PROJECT_* from `projectV2`; print `✅ Created and linked project #<N> "<title>" → <url>`. Do not use `gh project create` (it cannot link). Permission failure → print the error, note issues can still be created, ask whether to continue without board placement.

### Ensure the Status field
```bash
gh project field-list PROJECT_NUMBER --owner PROJECT_OWNER --format json
```
- **New project, no `Status`**:
```bash
gh project field-create PROJECT_NUMBER --owner PROJECT_OWNER \
  --name "Status" --data-type SINGLE_SELECT \
  --single-select-options "To Do,Ready,In Progress,Blocked,Integrated,Done,Won't Do"
```
- **Existing project, no `Status`** → warn the board is not Foundry-ready; ask to create it (same command). No → FOUNDRY_AVAILABLE=false, continue.
- **Missing required options** → print the missing names and ask to add them via `updateProjectV2Field`, passing every existing option (with `id`) plus the missing ones (no `id`). Never rename or delete without consent.
- **Declined or unrepairable** → FOUNDRY_AVAILABLE=false, keep publishing, report that candidates stay in intake.

**INTAKE_STATUS** = first existing option named `Backlog`, `To Do`, or `Todo` (case-insensitive), else the field's default/first option.

Recompute **FOUNDRY_AVAILABLE** after provisioning: true only when Step 0 repo checks passed and `Status` has all four required options. Required exactly `Ready`, `In Progress`, `Blocked`, `Integrated`; the driver compares names exactly, so `ready` is not `Ready`.

---

## Step 6 — Light issue body template

Deliberately light: goals and constraints only. `## User story` and `## Acceptance criteria` are load-bearing (`spec-analyst` Phase 2 extracts exactly those); `## Blocked by` is read by Phase 4. Do not rename them.

```markdown
## User story

As a <actor>, I want <capability>, so that <benefit>.

## Goal

<end-to-end behaviour from the user's perspective — not a layer-by-layer list>

## Constraints

- <what must not change, or must hold>

## Out of scope

- <explicit exclusion>

## Blocked by

- #<N> — <slice title>

<!-- When there are no blockers, replace the list with:
     None — can start immediately -->

## Acceptance criteria

- [ ] <criterion>

## Foundry fit

- Fit: yes | no
- Why: <one or two lines>
- Needs before Ready: <make ci exists on ai/integration | ai/integration exists | CI covers this slice | none>
- Verification: <the command that proves it, e.g. `make ci`>

## Context

Vision excerpt: <for Fit: yes, 2–5 sentences covering only the problem,
outcome, constraints, and out-of-scope that constrain this slice. For Fit: no,
you may omit the excerpt.>

Vision source: NOTION_URL (as of YYYY-MM-DD)
```

For `Fit: yes`, the excerpt is mandatory and at least one acceptance criterion must run CI (e.g. `- [ ] make ci passes`). For `Fit: no`, the Notion URL alone is enough. `## Foundry fit` is routing metadata, not an implementation requirement. No file paths, code snippets, API contracts, or test strategy.

---

## Step 7 — Publish in dependency order

Publish **blockers first**, so every edge references a real issue number and board position matches dependency order (the driver picks the lowest-position `Ready` item). Maintain a slice → issue-number map; resolve `Blocked by` through it.

### Duplicate guard
```bash
gh issue list --search "in:title <slice title>" --state open --json number,title,url
```
Match → show it and ask whether to skip or create anyway. Never create a silent duplicate; if skipped, record the existing number so later `Blocked by` references resolve.

### Create each issue
Write the Step 6 body to a temp file, then:
```bash
gh issue create --title "<slice title>" --body-file <tmpfile>
```
Capture the URL and number; record them in the map. Place on the board:
```bash
gh project item-add PROJECT_NUMBER --owner PROJECT_OWNER --url <issue-url>
gh project item-edit PROJECT_NUMBER --owner PROJECT_OWNER \
  --url <issue-url> --field "Status" --value "<STATUS>"
```
Compute STATUS:
```text
Ready  iff  Fit: yes
        AND every blocker is closed/Integrated
        AND every Needs before Ready item is satisfied
        AND FOUNDRY_AVAILABLE
        AND the user confirmed this slice in Step 4

otherwise  INTAKE_STATUS
```
Evaluate `Needs before Ready` from the Step 0 probe and current state. Check same-repo blockers with `gh issue view <N> --json state`, external ones with `-R <owner>/<repo>`; any open blocker ⇒ not `Ready`.

Never set `Blocked` or `In Progress` at creation (`Blocked` = business outcome; `In Progress` = recovery's interrupted-cycle marker). If setting `Ready` fails because the option is missing, leave it in intake and report — do not fall back to `Blocked`. No usable `Status` field → skip `item-edit` and report the item stays in the board default. Board placement failure after issue creation → warn and continue.

### On failure
Any `gh issue create` failure → stop and report which slices were created (with numbers) and which remain unpublished, so a re-run can resume without duplicates. Do not retry blindly.

### Clean up
Remove the temporary body files.

---

## Step 8 — Persist the breakdown and report

`mem_save` with `topic_key: "vision/PROJECT_SLUG/breakdown"`, `title: "Vision breakdown — PROJECT_SLUG"`, `type: architecture`, `scope: project`, content What/Why/Where/Learned (Learned = slice table: issue number, title, blocked-by, fit, needs, status). Engram unavailable → skip.

Print:
```
✅ /brainstorm complete for PROJECT_SLUG

  Vision source:  NOTION_URL
  Project board:  #<PROJECT_NUMBER> "<title>" → <PROJECT_URL> (owner: PROJECT_OWNER)
  Foundry:        available | not available yet (missing: <list>)
  Intake status:  <INTAKE_STATUS>
  Issues created: <count>

  Foundry queue (Ready — do not run /letsgo):
    #<N>  <title>  → will be picked up by the Foundry

  Human lane (<INTAKE_STATUS> — run /letsgo):
    #<N>  <title>  → /letsgo <N>

  Waiting on blockers (promote when blockers reach Integrated):
    #<N>  <title>  ← blocked by #<M>
    #<N>  <title>  ← blocked by #<M>, #<K> (Fit: yes)

  Promote a waiting slice with:
    gh project item-edit PROJECT_NUMBER --owner PROJECT_OWNER \
      --url <issue-url> --field "Status" --value "Ready"

  Do not set human-lane items to Blocked — it is reserved for Foundry business
  failures — or In Progress; recovery treats it as an interrupted cycle.

  Next: run /letsgo <N> on a human-lane issue, or let the Foundry pick up the
  Ready queue. Use /analyze-issue <N> instead if you only want the spec.
```

Do not invoke `/analyze-issue` or `/letsgo` yourself.
