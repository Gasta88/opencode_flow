---
name: foundry-headless-contract
description: Shared Foundry surface for headless commands — F1 project discovery, F2 status write, F3 result-comment upsert, F4 gh allowlist, runbook
---

# Foundry Headless Contract

## Scope + Load Contract

This skill defines the **single canonical surface** for Foundry board writes and result-comment upserts used by headless commands (`/letsgo --headless --base`, and `/review-pr` when it exists).

**Load line (AC1):** Every command file that performs board or result-comment writes MUST begin its Foundry prose with exactly:

```
Load skill: foundry-headless-contract
```

**Consumer contract:** Commands reference operations F1–F4 by name; they contain no duplicated inline `gh project` recipe strings (verified by static harness assertions).

**Fail-closed discipline:** All operations fail closed on ambiguity. No operation mutates the board schema (no field-create, no option rename, no new Status options).

---

## F1 — Project discovery (read-only)

**Input:** `$GH_OWNER`, `$GH_REPO`
**Output:** `$PROJECT_NUMBER`, `$PROJECT_OWNER` (login), or fail-closed `F1_UNRESOLVED` (zero writes of any kind)

**Recipe:**

```bash
timeout 120 gh api graphql -f query='{ repository(owner:"'"$GH_OWNER"'", name:"'"$GH_REPO"'") { id projectsV2(first:10){ nodes{ id number title url owner { __typename ... on User { login } ... on Organization { login } } } } } }'
```

**Rules:**

1. **Exactly-one rule:** Exactly one project node ⇒ bind `PROJECT_NUMBER` from `number`, `PROJECT_OWNER` from `owner.login`.
2. **Fallback:** When `owner.login` is null, parse `PROJECT_OWNER` from the project `url`.
3. **Fail-closed:** Zero or ≥2 nodes ⇒ `F1_UNRESOLVED`: no `item-edit`, no `field-list`, no surface-initiated comment (AC4).
4. **Never cached:** Re-resolve on every run (decision 2026-10-09).

---

## F2 — Status write (precheck → read → no-op or write)

**Input:** `$PROJECT_NUMBER`, `$PROJECT_OWNER`, `$GH_OWNER`, `$GH_REPO`, `$GH_ISSUE_NUMBER`, `$ISSUE_URL`, `$TARGET_STATUS` (callers pass exactly `In Progress` or `Blocked`)

### Precheck — field-list

```bash
timeout 120 gh project field-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --format json
```

**Rules:**

- `Status` must exist as a single-select containing the **exact, case-sensitive** option `$TARGET_STATUS`.
- Missing option ⇒ `F2_OPTION_MISSING` (clear failure, zero writes).
- Never `field-create`, never rename, never add options.

### Read current value

```bash
timeout 120 gh api graphql -f query='{ repository(owner:"'"$GH_OWNER"'", name:"'"$GH_REPO"'") { issue(number: '"$GH_ISSUE_NUMBER"') { projectItems(first: 20) { nodes { fieldValues(first: 20) { nodes { ... on ProjectV2ItemFieldSingleSelectValue { name field { ... on ProjectV2FieldCommon { name } } } } } } } } } }'
```

**Rules:**

- Lookup the node with `field.name == "Status"` on the item linked to the issue.
- Read failure ⇒ `F2_READ_FAIL` (fail closed; no blind write).
- Current `name == $TARGET_STATUS` ⇒ **no-op success** (AC2 — skip the write).

### Write (if needed)

```bash
timeout 120 gh project item-edit "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --url "$ISSUE_URL" --field "Status" --value "$TARGET_STATUS"
```

**Rules:**

- Write failure ⇒ `F2_WRITE_FAIL` (caller decides hard-stop vs best-effort: `/letsgo` E20 hard, FSP step 4 best-effort-continue).
- Never write `Ready` or `Integrated` — those are `/brainstorm` and host-reconciler owned.

---

## F3 — Result-comment upsert (idempotent)

**Input:** `$GH_OWNER`, `$GH_REPO`, `$GH_ISSUE_NUMBER`, `$RESULT_COMMENT_FILE` (first line = marker `<!-- opencode-flow:result -->`, then `outcome`, `stage`, `reason`, `branch`, `pr_url`, run timestamp; deleted after upsert, never committed)

**F1-independence:** This operation needs no project — only `<OWNER>/<REPO>/<N>`.

### Find existing marker comment

```bash
timeout 120 gh api "repos/$GH_OWNER/$GH_REPO/issues/$GH_ISSUE_NUMBER/comments" --jq '.[] | select(.body | contains("<!-- opencode-flow:result -->")) | .id'
```

### Update (if found)

```bash
timeout 120 gh api "repos/$GH_OWNER/$GH_REPO/issues/comments/$COMMENT_ID" -X PATCH -F body=@"$RESULT_COMMENT_FILE"
```

**Rule:** `-X PATCH` stays explicit — payload params alone would silently switch the method to POST.

### Create (if not found)

```bash
timeout 120 gh api "repos/$GH_OWNER/$GH_REPO/issues/$GH_ISSUE_NUMBER/comments" -F body=@"$RESULT_COMMENT_FILE"
```

**Rules (AC3):**

1. Exactly one marker comment per issue across N runs.
2. Marker literal unchanged (additive contract).
3. Token hygiene: no token value in argv, stdout, `result.json`, comments, or files — ambient `gh auth` only.
4. Delete `$RESULT_COMMENT_FILE` after upsert, never commit it.

---

## F4 — Headless `gh` allowlist

Canonical YAML permission block (documentation the host applies; the surface itself never asks):

```yaml
permission:
  bash:
    "gh project *": allow
    "gh pr *": allow
    "gh issue *": allow
    "gh api *": allow
```

**Note:** `gh api *` is required because F1/F3 execute through `gh api` (findings' three-family list omitted it — allowlist-gap ruling in Requirements).

**Static check:** The four patterns pinned verbatim in the skill; no `ask`-gated `gh` pattern on the headless path (AC5).

---

## Runbook

### Write ownership table

| Write | Owner | Notes |
|-------|-------|-------|
| `Status` = `In Progress` | Command lifecycle via F2 | Written by `/letsgo` before first implementation commit |
| `Status` = `Blocked` | Command lifecycle via F2 | Written on preflight failure or FSP stop |
| `Status` = `Ready` | `/brainstorm` | Surface never writes this value (decision 2026-10-28) |
| `Status` = `Integrated` | Host reconciler | Surface never writes this value (decision 2026-10-29) |
| Result comment (`<!-- opencode-flow:result -->`) | Command via F3 | Independent of board state (OD2) |

### Board-absent behavior

- **F1 fails closed** (`F1_UNRESOLVED`) ⇒ zero `gh project` writes, zero surface-initiated comments.
- **Command-level contract preserved:** `/letsgo` still writes `result.json` and posts its issue comment per E19 (OD2 — end-to-end, F3 orthogonal to F1).

### Sandbox install note

The Foundry sandbox image (`code_foundry`) must ship this skill. Install steps:

1. Mirror to host: `~/.config/opencode/skills/foundry-headless-contract/SKILL.md`
2. opencode resolves skills from `~/.config/opencode/skills/` and repo-local `skills/` directory.
3. Verify: `diff -u "$REPO_ROOT/skills/foundry-headless-contract/SKILL.md" ~/.config/opencode/skills/foundry-headless-contract/SKILL.md`

---
