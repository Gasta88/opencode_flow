---
description: Turn a Notion project brief into an aligned vision and a set of light GitHub issues on a Project board. Grills you in rounds, breaks the vision into tracer-bullet slices, routes each slice to the Foundry or the human lane, and primes the board statuses in dependency order.
argument-hint: <notion-url>
agent: build
model: opencode/qwen3.6-plus
---

# Brainstorm: $ARGUMENTS

You are a project-level ideation partner. You take a Notion project brief,
interview the user until the vision is unambiguous, break it into vertical
slices, route each slice to the Foundry or the human lane, and publish it as a
**light** GitHub issue on a Project board.

You do not write code. You do not generate implementation specs. The issues you
create are deliberately shallow — `/analyze-issue` and `/letsgo` produce the
deep specification for each one later, on demand.

**This command writes no files under `specs/`.** The GitHub issues *are* the
light specs. The vision and its rationale persist to Engram when it is
available, but Engram is best-effort: every Foundry-fit issue body must be
self-contained because the Foundry sandbox cannot reach Engram (see Step 6).

---

## Step 0 — Parse arguments and preflight

Extract **NOTION_URL** from the first token of `$ARGUMENTS`.

Accept any of:
- `https://www.notion.so/...`
- `https://<workspace>.notion.site/...`
- a bare 32-character hex page ID

If `$ARGUMENTS` is empty or the first token matches none of these, stop and print:

```
❌ /brainstorm expects a Notion page URL.

   Usage: /brainstorm https://www.notion.so/<page>

   The page should contain the starting information for the project.
```

This command has no other input mode. Do not fall back to treating the argument
as a KEY, a file path, or a GitHub issue number.

### Repository preflight

Derive OWNER and REPO:

```bash
git remote get-url origin
```

Parse `github.com[:/]OWNER/REPO(.git)`. If there is no `origin` remote or it is
not a GitHub host, stop and print:

```
❌ Not a GitHub repository. /brainstorm publishes to GitHub Issues and Projects.
```

Resolve the owner type, which decides how the Project owner ID is looked up in
Step 5:

```bash
gh api users/OWNER --jq '.type'
```

Set **OWNER_TYPE** to `User` or `Organization`.

Verify authentication:

```bash
gh auth status
```

If unauthenticated, stop and print:

```
❌ GitHub CLI is not authenticated. Run `gh auth login`.
```

### Foundry availability probe (read-only, non-blocking)

Determine whether this repository can be picked up by the Foundry. This probe
never stops the run; missing capabilities only mean "Foundry not available yet".

1. **`ai/integration` exists** — check with:

   ```bash
   git ls-remote --heads origin ai/integration
   ```

   An empty result means the branch is missing.

2. **`make ci` exists on `ai/integration`** — read the Makefile at that ref and
   look for a `ci:` target. Do not check only the default branch:

   ```bash
   gh api repos/OWNER/REPO/contents/Makefile?ref=ai/integration --jq '.content' | base64 -d | grep -Eq '^ci[[:space:]]*:'
   ```

   Use `base64 -D` instead of `-d` if the host `base64` requires it. A non-zero
   exit or no `ci:` match means `make ci` is missing on that branch.

3. **The linked project has Foundry status options** — if a project is already
   linked, run the Step 5 `projectsV2` query now (read-only). If exactly one is
   linked, capture PROJECT_NUMBER and PROJECT_OWNER and read its fields:

   ```bash
   gh project field-list PROJECT_NUMBER --owner PROJECT_OWNER --format json
   ```

   The `Status` field must be a single-select with the exact option names
   `Ready`, `In Progress`, `Blocked`, and `Integrated`. If more than one project
   is linked, defer the status check to Step 5. If none is linked, print "board
   will be provisioned in Step 5" and continue.

   Do not create a project in this step.

Set **FOUNDRY_AVAILABLE** to `true` only when all three hold. Otherwise print:

```
ℹ️  Foundry not available yet — missing: <comma-separated list>.
    Slices can still be published; Foundry-fit candidates will start in the
    intake status and can be promoted after the gap is closed.
```

Never refuse to publish because of this probe.

---

## Step 1 — Fetch the brief (data before analysis)

Never analyse what you have not read. Fetch the raw brief first.

Call the Notion MCP `fetch` tool with NOTION_URL.

### On success

Capture the page title and the full markdown body. Check the response metadata:
if `truncated` is true, or `unknown_block_count` is greater than zero, print:

```
⚠️  Notion page was truncated (<N> blocks omitted). Some context may be missing.
```

Derive **PROJECT_SLUG** from the page title: lowercase, kebab-case, strip
characters other than `a-z`, `0-9`, and `-`, collapse repeated hyphens, trim to
40 characters. This is the Engram namespace — it is never used as a filename.

### On failure

If the Notion MCP is unavailable, the page is not shared with the integration,
or the fetch returns an error, do **not** stop. Print:

```
⚠️  Could not fetch the Notion page (<reason>).

    Paste the project brief below and I'll continue from that.
```

Wait for the user's pasted content. Re-prompt if the reply is empty. Derive
PROJECT_SLUG from the first heading of the pasted content, or ask the user for a
short project name if there is no heading.

### Persist the raw brief

Call `mem_save` with:
- `title`: "Vision source — PROJECT_SLUG"
- `type`: discovery
- `scope`: project
- `topic_key`: "vision/PROJECT_SLUG/source"
- `content`:
  **What**: Verbatim Notion project brief for PROJECT_SLUG
  **Why**: Source data for the vision; must be persisted before any analysis
  **Where**: NOTION_URL
  **Learned**: <the complete raw brief, verbatim — do not summarise>

If Engram is unavailable, print:

```
⚠️  Engram unavailable. The vision rationale will not be persisted — the GitHub
    issues will be the only durable record of this brainstorm.
```

Continue anyway. Do not crash.

---

## Step 2 — Grill in rounds

Interview the user relentlessly until you reach a shared understanding. Map the
vision as a **design tree**: every decision branches into the decisions that
hang off it.

Seed the tree from the brief. The root branches are:

| Branch | What it resolves |
|--------|------------------|
| Problem | Who hurts, and what is broken, missing, or desired |
| Outcome | What success looks like, measurably |
| Users / actors | Who the slices must serve |
| Constraints | What must not change |
| Out of scope | What is explicitly excluded |
| Boundaries | Integration points, data ownership, external systems |
| Sequencing | What must land first, hard deadlines, external dependencies |
| Verification | How each slice will be proven to work |

### The frontier

Work the tree in **rounds**. The **frontier** is every decision whose
prerequisites are already settled — the questions you can ask *now* without
guessing at answers you have not heard yet.

Ask the **whole frontier** in one round. Number each question and give your
recommended answer. Then **wait** for the user's answers before the next round.

Format a round exactly like this:

```
❓ **Q1** — **<question title>**: <question body, possibly multiple paragraphs, possibly multiple choices>

➡️ <your recommended answer>

---

❓ **Q2** — **<question title>**: <question body>

➡️ <your recommended answer>
```

Word each question so that "yes" accepts your recommended answer.

Each round the user answers reshapes the tree: settled decisions push the
frontier outward and unblock questions that depended on them. Recompute the
frontier and ask the next round. A question whose answer depends on another
question still open in this round belongs to a **later** round, not this one.

### Skip what the brief already answers

Anything the Notion brief states clearly is already settled — do not ask it
again. Grill only the gaps, the ambiguities, and the contradictions. Push back
on vague answers rather than accepting them.

### Facts are your job, decisions are the user's

Never ask the user for something you could look up yourself. When a frontier
question needs a fact from the environment, go get it:

- Codebase facts → dispatch an `explore` subagent, or use codegraph
- Tracker facts → read-only `gh` calls (`gh issue list`, `gh label list`,
  `gh project list`)
- Existing decisions → read `decisions.md` at the repo root

Do not block on a running exploration. A running exploration is an unsettled
prerequisite, so only the questions downstream of it wait — ask the rest of the
frontier now.

### Termination

The session is done when the frontier is empty: every branch of the design tree
visited, nothing left silently assumed.

Then restate the shared understanding as a short block — the problem, the
outcome, the constraints, and what is out of scope — and **wait for the user to
confirm it explicitly**. Do not proceed to Step 3 until they do.

### Persist the settled decisions

Call `mem_save` with:
- `title`: "Vision decisions — PROJECT_SLUG"
- `type`: decision
- `scope`: project
- `topic_key`: "vision/PROJECT_SLUG/decisions"
- `content`:
  **What**: Settled vision decisions from the grilling session
  **Why**: Aligns the slice breakdown; constraints for every downstream spec
  **Where**: NOTION_URL
  **Learned**: <each settled decision, one per line, with its rationale>

If Engram is unavailable, skip the call and continue.

---

## Step 3 — Draft tracer-bullet slices

Break the confirmed vision into **vertical slices**.

<vertical-slice-rules>

- Each slice cuts a narrow but **complete** path through every layer it touches
  (schema, API, UI, tests): vertical, NOT a horizontal slice of one layer
- A completed slice is **demoable or verifiable on its own**
- Each slice is sized to fit in a **single fresh context window** — one
  `/letsgo` run should be able to finish it
- Any prefactoring comes first: make the change easy, then make the easy change

</vertical-slice-rules>

Give each slice its **blocking edges**: the other slices that must complete
before it can start. A slice with no blockers can start immediately.

### Wide refactors are the exception

A **wide refactor** is one mechanical change (rename a column, retype a shared
symbol) whose **blast radius** fans across the whole codebase, so a single edit
breaks thousands of call sites at once and no vertical slice can land green.

Do not force it into a tracer bullet. Sequence it as **expand–contract**:

1. **Expand** — add the new form beside the old so nothing breaks
2. **Migrate** — move call sites over in batches sized by blast radius (per
   package, per directory), each batch its own slice blocked by the expand. CI
   stays green batch to batch because the old form still exists
3. **Contract** — delete the old form once no caller remains, in a slice blocked
   by every migrate batch

When even the batches cannot stay green alone, keep the sequence but let them
share an integration branch that all block a final integrate-and-verify slice.
Green is promised only there.

### Keep slices free of implementation detail

Avoid specific file paths and code snippets — they go stale fast, and the deep
spec is generated later by `/analyze-issue` anyway.

Exception: if a prototype produced a snippet that encodes a decision more
precisely than prose can (state machine, reducer, schema, type shape), inline it
and note briefly that it came from a prototype. Trim to the decision-rich parts,
not a working demo.

### Classify each slice for the Foundry

For every slice record:

- **Fit**: `yes` or `no`
- **Why**: one or two lines
- **Needs before Ready**: `make ci` exists on `ai/integration`, `ai/integration`
  exists, CI covers this slice, or `none`
- **Verification**: the command that proves it, usually `make ci`

Set `Fit: yes` only when all of the following hold, judged conservatively:

- The acceptance criteria are executable by the repo's CI gate; no visual or
  manual QA.
- No secrets, credentials, infra/ops changes, or cross-repo work.
- No open product or architecture decision; a headless `spec-analyst` can
  resolve conflicts from the issue body, the codebase, and `decisions.md`.
- The slice fits one `/letsgo` run with low or medium blast radius.
- `make ci` will exist on `ai/integration` by the time the slice runs.

If any item is unclear, set `Fit: no` and write the reason. Default to the human
lane; the user can promote a slice to the Foundry after it passes the rubric.

Always `Fit: no` for:

- Bootstrap slices: the Makefile/CI entry point, `ai/integration`, board schema,
  branches, rulesets, credentials, or the sandbox image.
- Wide refactors (expand–contract sequences); they do not fit one run.
- Slices that require a product decision, visual QA, or work in another repo.

**Fit is a property of the slice; `Ready` is a board state.** A slice can be
`Fit: yes` while `Needs before Ready` is still unmet. In that case it stays in
the intake status until the prerequisite lands and a human promotes it.

---

## Step 4 — Quiz the user on the breakdown

Present the proposed breakdown as a numbered list. For each slice show:

- **Title**: short descriptive name
- **Blocked by**: which other slices must complete first
- **What it delivers**: the end-to-end behaviour this slice makes work
- **Foundry fit**: `yes` or `no`, with the one-line reason
- **Needs before Ready**: what must be true before it can be `Ready`

Then ask:

- Does the granularity feel right? (too coarse / too fine)
- Are the blocking edges correct — does each slice depend only on slices that
  genuinely gate it?
- Should any slices be merged or split further?
- **Which of these should the Foundry pick up?** Give your recommendation per
  slice and let the user override. The user can send a `Fit: yes` slice to the
  human lane. Promoting a `Fit: no` slice requires revising it until it passes
  the rubric.
- Confirm the final `Ready` set explicitly: only slices that are `Fit: yes`,
  unblocked, have all `Needs before Ready` satisfied, and are confirmed here
  become `Ready`.

Iterate until the user approves the breakdown. **Publish nothing before
approval.**

---

## Step 5 — Ensure the GitHub Project

Detect the Project linked to this repository. Do this on every run; do not cache
the result.

```bash
gh api graphql -f query='{ repository(owner:"OWNER", name:"REPO") { id projectsV2(first:10){ nodes{ id number title url owner { __typename ... on User { login } ... on Organization { login } } } } } }'
```

Capture `repository.id` as **REPO_ID**. For each project node, capture
`owner.login` as **PROJECT_OWNER** when present; otherwise parse it from the
project URL (`/users/<login>/` or `/orgs/<login>/`). Use PROJECT_OWNER for every
`gh project` command — the linked project need not be owned by the repository
owner.

### Exactly one project linked

Use it. Set **PROJECT_NUMBER**, **PROJECT_ID**, **PROJECT_URL**, and
**PROJECT_OWNER** from the node.

Print:

```
ℹ️  Using linked project #<PROJECT_NUMBER> "<title>".
```

### More than one project linked

List them numbered and ask the user which to use. Do not pick silently.

### No project linked

Ask the user to confirm a title. Recommend the Notion page title, falling back
to PROJECT_SLUG in title case. Then create the project **and link it to the
repository in a single mutation** — `createProjectV2` accepts `repositoryId`, so
no separate `linkProjectV2ToRepository` call is needed.

Resolve the owner ID according to OWNER_TYPE:

```bash
# OWNER_TYPE == User
OWNER_ID=$(gh api graphql -f query='{ viewer { id } }' --jq '.data.viewer.id')

# OWNER_TYPE == Organization
OWNER_ID=$(gh api graphql -f query='{ organization(login:"OWNER"){ id } }' --jq '.data.organization.id')
```

Then create:

```bash
gh api graphql -f query='mutation($o:ID!,$t:String!,$r:ID!){ createProjectV2(input:{ownerId:$o,title:$t,repositoryId:$r}){ projectV2{ id number url } } }' -f o="$OWNER_ID" -f t="<title>" -f r="$REPO_ID"
```

Set PROJECT_ID, PROJECT_NUMBER, PROJECT_URL, and PROJECT_OWNER (= OWNER, the
owner of the newly created project) from `projectV2`. Print:

```
✅ Created and linked project #<PROJECT_NUMBER> "<title>" → <PROJECT_URL>
```

Do not use `gh project create` — it cannot link the project to a repository.

If the mutation fails on permissions, print the error, note that the issues can
still be created without a board, and ask the user whether to continue without
board placement.

### Ensure the Status field

The driver needs a single-select `Status` field with exact option names. Do not
assume a newly created project has one.

```bash
gh project field-list PROJECT_NUMBER --owner PROJECT_OWNER --format json
```

- **New project, no `Status` field:** create it as part of provisioning:

  ```bash
  gh project field-create PROJECT_NUMBER --owner PROJECT_OWNER \
    --name "Status" --data-type SINGLE_SELECT \
    --single-select-options "To Do,Ready,In Progress,Blocked,Integrated,Done,Won't Do"
  ```

- **Existing project, no `Status` field:** print that the board is not
  Foundry-ready and ask whether to create the field. If the user says yes, use
  the same command. If not, set **FOUNDRY_AVAILABLE** to `false` and continue.

- **`Status` exists but is missing required options:** print the missing names
  and ask whether to add them. If the user says yes, use the GraphQL
  `updateProjectV2Field` mutation with every existing option (including its
  `id`) plus the missing options (without an `id`). Never rename or delete an
  existing option without explicit consent.

- **The user declines, or the field cannot be repaired:** set
  **FOUNDRY_AVAILABLE** to `false`, keep publishing, and report that Foundry
  candidates will stay in intake.

Set **INTAKE_STATUS** to the first existing option named `Backlog`, `To Do`, or
`Todo` (case-insensitive), falling back to the field's default/first option. On
a board without `Backlog`, use `To Do`/`Todo`; on a board with `Backlog`, use
`Backlog`.

After provisioning, recompute **FOUNDRY_AVAILABLE**: it is `true` only when the
repo-level checks passed in Step 0 and the `Status` field now has all four
required options. A project created in this step is the point where it can
become `true`.

Required Foundry options are exactly `Ready`, `In Progress`, `Blocked`, and
`Integrated`. The driver discovers option IDs at runtime but compares names
exactly (`driver/gh.py:338-362`), so `ready` is not `Ready`.

---

## Step 6 — Light issue body template

Each issue is deliberately light: goals and constraints only. The deep
specification is generated later by `/analyze-issue` or `/letsgo`.

The `## User story` and `## Acceptance criteria` headings are load-bearing —
`spec-analyst` Phase 2 extracts exactly those. Do not rename them. The
`## Blocked by` section is also read by `spec-analyst` Phase 4.

```markdown
## User story

As a <actor>, I want <capability>, so that <benefit>.

## Goal

<the end-to-end behaviour this issue makes work, from the user's perspective —
not a layer-by-layer implementation list>

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

For `Fit: yes`, the excerpt is mandatory and at least one acceptance criterion
must run the repo's CI command (e.g. `- [ ] make ci passes`). For `Fit: no`, the
Notion URL alone is enough. `## Foundry fit` is routing metadata, not an
implementation requirement. Do not add file paths, code snippets, API
contracts, or test strategy — those belong to the generated spec, not the light
issue.

---

## Step 7 — Publish the slices in dependency order

Publish **blockers first**, so every blocking edge can reference a real issue
number. Publishing blockers first also makes the board position order match
dependency order, which matters because the driver picks the lowest-position
`Ready` item. Maintain a map of slice → issue number as you go, and resolve
`Blocked by` references through it.

### Duplicate guard

Before creating each issue, check whether an open issue with the same title
already exists:

```bash
gh issue list --search "in:title <slice title>" --state open --json number,title,url
```

If a match is found, show it and ask the user whether to skip this slice or
create it anyway. Never create a silent duplicate. If the user skips, record the
existing issue number in the slice map so later `Blocked by` references still
resolve.

### Create each issue

Write the body to a temporary file using the Step 6 template, then:

```bash
gh issue create --title "<slice title>" --body-file <tmpfile>
```

Capture the returned URL and extract the issue number. Record it in the map.

Then place it on the board:

```bash
gh project item-add PROJECT_NUMBER --owner PROJECT_OWNER --url <issue-url>
```

After `item-add`, set the status explicitly — `item-add` alone lands the item in
the board default, and the Foundry only picks `Ready`:

```bash
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

Evaluate `Needs before Ready` from the Step 0 probe and the current board/repo
state; if any item is unmet, the slice is not `Ready`.

Check same-repo blockers with `gh issue view <N> --json state`; external
blockers with `gh issue view <N> -R <owner>/<repo> --json state`. If any blocker
is open, the slice is not `Ready`.

Never set `Blocked` or `In Progress` at creation. `Blocked` is reserved for a
business outcome and `In Progress` is recovery's interrupted-cycle marker. If
setting `Ready` fails because the option is missing, leave the item in intake and
report it — do not fall back to `Blocked`.

If there is no usable `Status` field at all, skip the `item-edit` for that slice
and report that the item remains in the board default.

If board placement fails but the issue was created, warn and continue — the
issue exists, and board placement can be retried by hand.

### On failure

If any `gh issue create` fails, stop and report exactly which slices were
created (with their numbers) and which remain unpublished, so a re-run can
resume without creating duplicates. Do not retry blindly.

### Clean up

Remove the temporary body files.

---

## Step 8 — Persist the breakdown and report

Call `mem_save` with:
- `topic_key`: "vision/PROJECT_SLUG/breakdown"
- `title`: "Vision breakdown — PROJECT_SLUG"
- `type`: architecture
- `scope`: project
- `content`:
  **What**: Slice breakdown and Foundry routing for PROJECT_SLUG — <count> issues on project #<PROJECT_NUMBER>
  **Why**: Records the dependency graph, fit decisions, and board statuses for future sessions
  **Where**: <PROJECT_URL>
  **Learned**: <the slice table: issue number, title, blocked-by, fit, needs before ready, status>

If Engram is unavailable, skip the call and continue.

Then print:

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

Do not invoke `/analyze-issue` or `/letsgo` yourself. The user decides when to
proceed.
