# Validator brief — mechanical review

Spawned as `Explore` (read-only, fast, pattern-matching). One of three parallel reviewers; non-overlapping checklist with the Archive Auditor and Quality Reviewer.

The Validator handles every check that is **mechanical** — things a regex or a tree-walk can verify without semantic judgement. If a check requires reading the transcript or reasoning about the substance of decisions, it belongs to the Archive Auditor or Quality Reviewer, not here.

## Inputs

- **Vocabulary**: `<skill_dir>/references/CONTEXT.md` — the skill's vocabulary file. Read this first; use these terms (and not their `_Avoid_:` aliases) in your findings.
- **Base SHA**: `<base_sha>` — the commit before this capture batch started
- **Worktree**: `<worktree>` — absolute path to the per-session git worktree (where the in-flight drafts live). All checks operate against this path, not against the live archive clone.
- **Diff command**: `git -C <worktree> diff <base_sha>` — yields the full cumulative change since base
- **Format reference**: `<skill_dir>/references/decision-format.md` — the authoring spec; same one the capture agent used

You do **not** need the transcript. That is the Archive Auditor's and Quality Reviewer's concern.

## Method

1. **Read `CONTEXT.md` first** to align on terminology.
2. Run `git diff <base_sha>` to list all changed files. Categorise into: new decision files, new synthesis files, supersede flips (frontmatter-only edits to existing decisions), transcript.
3. For each new file: parse the frontmatter; run the checklist below.
4. For each modified existing decision: confirm the edit is frontmatter-only (status flip) plus optionally an appended `## Note` footer. Any other body modification is `blocking` — bodies of existing decisions must never be rewritten (history-destroying).
5. For each edge declared: verify the target exists on disk in `<worktree>/decisions/` or `<worktree>/synthesis/`.

## Checklist

### Frontmatter completeness

For every new decision file, confirm the frontmatter has all required fields:

- `id` (ULID string, present — 26 characters, Crockford base32 alphabet; uppercase is conventional). The canonical regex for an `id:` value is `^[0-9A-HJKMNP-TV-Z]{26}$` — the 32-character Crockford alphabet excludes `I`, `L`, `O`, `U`. Anything failing this regex is a `blocking` "invalid ULID" finding.
- `slug` (string, present)
- `title` (string, present)
- `status` (must be `accepted` for new files — see status section below)
- `tags` (list, present; can be empty but should have 3–6 entries — empty is `nit`, missing key is `blocking`)
- `edges.depends-on` (list, present; empty `[]` allowed but the key must exist)
- `edges.supersedes` (list, present; empty `[]` allowed)
- `edges.informs` (list, present; empty `[]` allowed)

Synthesis files must satisfy all of the decision-file frontmatter rules above (including explicit `edges.depends-on: []`, `edges.supersedes: []`, `edges.informs: []` when empty), plus:

- `edges.synthesizes` (list, present; **must be non-empty** for synthesis files — a synthesis with no synthesized decisions is invalid)
- `spawns-threads` (optional; if present, every entry must have all four sub-fields: `topic`, `why-deferred`, `revisit-trigger`, `rough-size`)

Any missing required field → `blocking`.

### Slug + filename consistency

- The slug must match the filename (minus `.md` extension and minus the leading `<ULID>-` prefix). Mismatch → `blocking`.
- The slug must be lowercase kebab-case. Any uppercase or underscore → `blocking`.
- The slug must start with the archive's namespace prefix (look at existing decisions in `<worktree>/decisions/` to infer the namespace; the current archive uses `decision-archive`). Missing prefix → `blocking`.

### ID format and uniqueness

- Every new file's `id` (and its filename prefix) is a valid **ULID**: exactly 26 characters, Crockford base32. Match against the canonical regex `^[0-9A-HJKMNP-TV-Z]{26}$` (the alphabet excludes `I`, `L`, `O`, `U`). Anything else → `blocking`.
- **Legacy detection.** A zero-padded integer prefix (`0014-...`) or a numeric `id:` value in a new file → `blocking` (legacy convention; the archive uses ULIDs).
- Every new file's `id` is unique across `<worktree>/decisions/` **and** `<worktree>/synthesis/` (ULIDs are globally unique by construction, so any collision indicates a generation bug). Collision → `blocking`.
- The `id` value in the frontmatter must match the ULID portion of the filename. Mismatch → `blocking`.

### Edge schema

- Only the four edge types are valid: `depends-on`, `supersedes`, `informs`, `synthesizes`.
- `synthesizes` only appears in synthesis files. A decision file with `synthesizes` → `blocking`.
- All edge values are lists of **ULID strings**. A list of integers (legacy) or a list containing slugs → `blocking`.
- A non-ULID entry (string that fails the canonical regex `^[0-9A-HJKMNP-TV-Z]{26}$`) → `blocking`.

### Edge target existence

- For every `<ULID>` referenced in any edge: verify a file named `<ULID>-*.md` exists in `<worktree>/decisions/` or `<worktree>/synthesis/`. Dangling reference → `blocking`.
- Targets may include files created in this same batch (cross-references within the batch are legal).
- Cross-archive references (a ULID that does not resolve to any file in `<worktree>`) → `blocking`. Edges are intra-archive only.

### Status of newly-written files

- New decision files must have `status: accepted`. **Not `proposed`** — the two-state lifecycle only allows `accepted` and `superseded`. `status: proposed` → `blocking`.
- New synthesis files must have `status: accepted`.

### Supersede flips honored

- For every new decision declaring `supersedes: [<ULID-of-X>]`: confirm decision X's file now has `status: superseded`. If X is still `accepted` post-batch → `blocking`.
- For every existing file flipped to `status: superseded` in the diff: confirm some new decision in the batch declares `supersedes: [<ULID-of-X>]`. An orphan flip (status changed but no successor declared) → `blocking`.

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

Diffs on existing decision/synthesis files are restricted to two specific shapes; anything outside both is `blocking` ("body of existing decision modified — destroys history"):

- **Frontmatter changes** confined to `status` (e.g., `accepted` → `superseded`).
- **A new `## Note` section appended at the end of the file**, after all pre-existing sections. The Note section is allowed because it records the supersession event (e.g., a one-line "Superseded by `<ULID>`" reference); modifications inside or insertions before any pre-existing section remain `blocking`.

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
