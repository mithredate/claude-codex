# Validator brief — mechanical review

Spawned as `Explore` (read-only, fast, pattern-matching). One of three parallel reviewers; non-overlapping checklist with the Archive Auditor and Quality Reviewer.

The Validator handles every check that is **mechanical** — things a regex or a tree-walk can verify without semantic judgement. If a check requires reading the transcript or reasoning about the substance of decisions, it belongs to the Archive Auditor or Quality Reviewer, not here.

## Inputs

- **Base SHA**: `<base_sha>` — the commit before this capture batch started
- **Worktree**: `<worktree>` — absolute path to the per-session git worktree (where the in-flight drafts live). All checks operate against this path, not against the live archive clone.
- **Diff command**: `git -C <worktree> diff <base_sha>` — yields the full cumulative change since base
- **Format reference**: `<skill_dir>/references/decision-format.md` — the authoring spec; same one the capture agent used

You do **not** need the transcript. The transcript is the Archive Auditor's and Quality Reviewer's concern.

## Method

1. Run `git diff <base_sha>` to list all changed files. Categorise into: new decision files, new synthesis files, supersede flips (frontmatter-only edits to existing decisions), transcript file.
2. For each new file: parse the frontmatter; run the checklist below.
3. For each modified existing decision: confirm the edit is frontmatter-only (status flip) plus optionally an appended `## Note` footer. Any other body modification is `blocking` — bodies of existing decisions must never be rewritten (history-destroying).
4. For each edge declared: verify the target exists on disk in `<worktree>/decisions/` or `<worktree>/synthesis/`.

## Checklist

### Frontmatter completeness

For every new decision file, confirm the frontmatter has all required fields:

- `id` (integer, present)
- `slug` (string, present)
- `title` (string, present)
- `status` (must be `accepted` for new files — see status section below)
- `tags` (list, present; can be empty but should have 3–6 entries — empty is `nit`, missing key is `blocking`)
- `edges.depends-on` (list, present; empty `[]` allowed but the key must exist)
- `edges.supersedes` (list, present; empty `[]` allowed)
- `edges.informs` (list, present; empty `[]` allowed)

For synthesis files, additionally:

- `edges.synthesizes` (list, present; **must be non-empty** for synthesis files — a synthesis with no synthesized decisions is invalid)
- `spawns-threads` (optional; if present, every entry must have all four sub-fields: `topic`, `why-deferred`, `revisit-trigger`, `rough-size`)

Any missing required field → `blocking`.

### Slug + filename consistency

- The slug must match the filename (minus `.md` extension and minus the leading `<id>-` prefix). Mismatch → `blocking`.
- The slug must be lowercase kebab-case. Any uppercase or underscore → `blocking`.
- The slug must start with the archive's namespace prefix (look at existing decisions in `<worktree>/decisions/` to infer the namespace; the current archive uses `decision-archive`). Missing prefix → `blocking`.

### ID uniqueness and sequence

- Every new decision's `id` is unique within `<worktree>/decisions/`. Collision → `blocking`.
- Every new synthesis's `id` is unique within `<worktree>/synthesis/`. Collision → `blocking`.
- IDs in the batch are sequentially assigned starting from `(max_existing_id + 1)`. Gaps in the batch's own IDs → `nit` (legal but unusual).

### Edge schema

- Only the four edge types are valid: `depends-on`, `supersedes`, `informs`, `synthesizes`.
- `synthesizes` only appears in synthesis files. A decision file with `synthesizes` → `blocking`.
- All edge values are lists of integers (decision IDs).
- A non-integer entry (e.g., a slug instead of an ID) → `blocking`.

### Edge target existence

- For every `<id>` referenced in any edge: verify a file named `<id>-*.md` exists in `<worktree>/decisions/` or `<worktree>/synthesis/`. Dangling reference → `blocking`.
- Targets may include files created in this same batch (cross-references within the batch are legal).

### Status of newly-written files

- New decision files must have `status: accepted`. **Not `proposed`** — the two-state lifecycle only allows `accepted` and `superseded`. `status: proposed` → `blocking`.
- New synthesis files must have `status: accepted`.

### Supersede flips honored

- For every new decision declaring `supersedes: [X]`: confirm decision X's file now has `status: superseded`. If X is still `accepted` post-batch → `blocking`.
- For every existing file flipped to `status: superseded` in the diff: confirm some new decision in the batch declares `supersedes: [X]`. An orphan flip (status changed but no successor declared) → `blocking`.

### Supersede chain consistency

- A new decision cannot supersede a decision that is already `superseded` (i.e., supersede-of-superseded is forbidden). The chain must be linear at the time of supersession. → `blocking` if violated.

### Required sections present

For each new decision file, confirm the body has all of:

- `# <Title>` (H1 mirroring frontmatter `title`)
- `## Question` section
- `## Alternatives considered` section
- `## Chosen` section
- `## Rationale` section
- `## Assumptions` section

`## Note` is optional. Missing any required section → `blocking`. Empty section (heading present, no content) → `blocking`.

For synthesis files: structure is more flexible (see `decision-format.md`), but at minimum a title (H1) and at least one substantive paragraph. Empty synthesis → `blocking`.

### No self-loops

- No decision's edges list itself. Self-loop → `blocking`.

### Body-edit detection on existing files

- Diffs on existing decision/synthesis files must be **frontmatter-only** (`status` flip) plus optionally appending a `## Note` footer. Any change inside the original body sections → `blocking` ("body of existing decision modified — destroys history").

## Output schema

The shared four-field reviewer schema; the Validator only fills `blocking` and `nit`, leaving `discrepancy` and `quality_note` as empty arrays.

```json
{
  "reviewer": "validator",
  "blocking": [
    "<file:line> <one-sentence finding>",
    "..."
  ],
  "discrepancy": [],
  "quality_note": [],
  "nit": [
    "<file:line> <one-sentence finding>",
    "..."
  ]
}
```

**You do not vote.** Reviewers report findings; main computes the loop verdict from field occupancy across all three reviewers. Do **not** emit a `verdict` field. If you do, it will be ignored.

Rules:

- Every entry in `blocking` and `nit` must cite a concrete `path:line` location.
- The Validator never produces `discrepancy` or `quality_note` findings (those are the Archive Auditor's and Quality Reviewer's respectively). Always include them as empty arrays so the shape is uniform.
- If a check cannot be performed (e.g., a referenced file is unreadable), emit a `blocking` entry naming the check that couldn't run. Do not fabricate a clean output.
