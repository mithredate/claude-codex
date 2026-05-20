# Capture agent brief — drafting template

This is the brief main hands to the capture sub-agent (`general-purpose`). Main fills in the placeholders before spawning.

---

## Objective

Draft the closed-off forks from the in-scope conversation into the per-session git worktree at `<worktree>` — a checkout of the user's decision archive on a dedicated capture branch. Produce N decision files plus at most one synthesis file plus any supersede flips on existing decisions, **directly on disk as unstaged changes**. Return a tight JSON digest describing what was written. **All reads, writes, and `git` calls happen inside `<worktree>`. The live archive clone is not touched during the iteration loop.**

## Inputs (round 1)

- **Vocabulary**: `<skill_dir>/references/CONTEXT.md` — the skill's vocabulary file. Read this first; it pins the names you must use in `Chosen`, `Rationale`, slugs, tags, and the returned digest. The `_Avoid_:` aliases are not synonyms.
- **Worktree**: `<worktree>` (absolute path to the per-session git worktree, e.g., `/Users/<user>/projects/decision-archive/.claude/worktrees/capture-<timestamp>-<slug>`). All operations happen here, not in the live clone.
- **Base SHA**: `<base_sha>` (the capture-decision pre-flight captured this; the diff invariant is `git diff <base_sha>`)
- **transcript path**: `<worktree>/transcripts/transcript-<timestamp>-<slug>.md` — read this faithfully; treat it as the source of truth for what the session decided
- **Recall digest**: <inline ≤50-line digest of related existing decisions from the recall agent>
- **Format reference**: `<skill_dir>/references/decision-format.md` — read this before drafting; it defines the schema, the slug convention, the body sections, the triple-filter, and the supersede mechanics

## Inputs (round 2+ — additive, not substitutive)

- All round-1 inputs (unchanged — transcript, recall digest, format reference, archive root, base SHA)
- **Current cumulative diff**: `git -C <worktree> diff <base_sha>` — the unstaged drafts you produced in the prior round
- **Aggregated reviewer findings**: all `blocking` and `discrepancy` items from all three reviewers, with their `path:line` cites
- **Surgical-fix mode directive** (see below — apply verbatim)

## Method

1. **Read `CONTEXT.md` first.** Pin the vocabulary in your head before you touch substance — what counts as a *decision* vs *synthesis* vs *thread*, what *supersession* means, what the `_Avoid_:` aliases are. This is the cheap, foundational step.

2. **Then read the transcript.** Not the recall digest, not the format reference — the transcript. This is the source-of-truth for what was decided. Reviewers will hold every assertion in your `Chosen` and `Rationale` sections to what the transcript supports.

3. **Then read the format reference** (`decision-format.md`). Internalise: the triple-filter, the edge vocabulary, the slug convention, the supersede mechanics, the synthesis structure. The reviewers enforce all of it.

4. **Then read the recall digest.** Use it to identify likely edge targets. Edges declared in your drafts must reflect real relationships visible in the transcript — not just "this decision is about a related topic." The Archive Auditor checks edge justification.

5. **Apply the triple-filter** to every candidate fork:
   - Hard to reverse?
   - Surprising without context?
   - Real trade-off (genuinely-considered alternatives)?

   If any of the three fails, the fork is not a decision. Drop it or fold it into the synthesis as narrative.

6. **Draft alternatives-non-empty.** Every decision file must have at least two entries in `Alternatives considered`. An empty or single-item list invalidates the decision; the Quality Reviewer catches this as `blocking`.

7. **Articulate the `Rationale`.** A thin `Rationale` is a Quality Reviewer finding. Address every non-chosen alternative explicitly: what it would have cost, what it would have prevented. Without explicit rejection notes, a future reader cannot tell whether the rejected options were considered or merely overlooked.

8. **Surface assumptions.** The `Assumptions` section is where you list the beliefs this decision rests on. When an assumption later turns out wrong, the decision becomes a rewind candidate. Empty assumptions are tolerated when truly none apply; usually they don't.

9. **Handle supersessions in the same round.** If a new decision supersedes an existing one, you must in this same round:
   - Set the new decision's `supersedes: [<ULID-of-X>]` edge.
   - `Edit` X's frontmatter to flip `status: accepted` → `status: superseded`.
   - Cite X in the new decision's `Rationale` — explain what changed and why.
   - Optionally add a `## Note — Superseded by <new-ULID>` footer to X's body.

10. **Edge directionality discipline.**
    - `depends-on` — from this decision **to** what it depends on. Earlier ULIDs (lexicographically smaller) typically.
    - `supersedes` — from successor **to** retired predecessor.
    - `informs` — from influencing decision **to** influenced one.
    - `synthesizes` — from synthesis file **to** the decisions it covers.

    **Edge liveness:** "A supersedes B → A depends-on B" is legitimate (the successor often builds on its predecessor's framing). But "C depends-on B where B is superseded by D and C is not the supersession" is wrong — C likely depends on D's live principle, not B's retired framing. Re-target.

    **Intra-archive only:** Every ULID in an edge field must refer to a file inside `<worktree>` (the archive you are writing into). If the transcript mentions a decision in a different archive, that reference belongs in the body prose (`Rationale` or `Note`), never as a structured edge. The Archive Auditor flags any cross-archive ULID in an edge field as `blocking`.

11. **Generate a fresh ULID per new file.** ULIDs are 26-character Crockford base32 strings, lexicographically sortable by creation time. Use this stdlib-only Python one-liner as the canonical producer:

    ```bash
    python3 -c '
    import secrets, time
    A = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    def b32(n, w): return "".join(A[(n >> (5*i)) & 31] for i in range(w-1, -1, -1))
    t = time.time_ns() // 1_000_000
    r = int.from_bytes(secrets.token_bytes(10), "big")
    print(b32(t, 10) + b32(r, 16))
    '
    ```

    It emits a 26-character string (10-char ms-timestamp prefix + 16-char randomness, Crockford base32). Use the generated ULID as the file's `id:` frontmatter value and as the filename prefix: `<ULID>-<namespace>-<slug>.md`. ULIDs are globally unique by construction, so there is no scan-for-max-and-increment and no risk of collision between `decisions/` and `synthesis/`. Within a batch, generate ULIDs in the order the decisions logically build on each other (foundational first) — the lexicographic sort will mirror that.

12. **Synthesis is optional, written at most once per batch.** Include one if (and only if) the batch has connective tissue worth narrating — an architectural reframe, a supersede chain, follow-up threads. If you write a synthesis, its `synthesizes` edges must cover every decision in the batch.

13. **Run `git add -N` on each new file.** New files are untracked by default and would not appear in `git diff <base_sha>` until staged. Reviewers expect to see one cumulative diff that includes new files. After writing any new file (or once before returning — your choice, as long as it happens before control returns to main), run:

    ```bash
    git -C <worktree> add -N decisions/ synthesis/ transcripts/
    ```

    `-N` introduces the path to the index without staging content, making the file visible in `git diff` as an addition while remaining unstaged for content purposes. This is mechanical — do not edit content while running it.

## Boundaries

- **Do not edit files outside `<worktree>/decisions/`, `<worktree>/synthesis/`, or the supersede targets you have named.** No edits to README.md, IMPLEMENTATION.md, CONTEXT.md, or any other file. The Validator catches violations.
- **Do not rewrite existing decisions' bodies.** Frontmatter flips (status → superseded) and an optional `## Note` footer are the entire scope of edits to existing files. Anything more destroys history.
- **Do not expand scope.** The scope was set by the user in Step 1 of capture-decision. If you find a closed-off fork in the transcript that is **outside** scope, do not capture it. Flag it in `rationale_out` if it seems worth a future session.
- **Do not invent assumptions or rationale.** Every assertion in `Chosen` and `Rationale` must be traceable to the transcript. The Archive Auditor's transcript-faithfulness check is `discrepancy`-grade (forces another round) when violated.
- **Do not skip the triple-filter.** A fork that fails the filter does not become a decision file. Folding multiple fail-filter discussions into one "general decisions" file is also wrong — that's not how the format works.

## Surgical-fix mode directive (round 2+ — apply verbatim)

> You are operating on the same worktree across retries. The diff is shown to you as context for what is already in place, not as a patch to apply. Address every `blocking` and `discrepancy` finding from the prior round without regressing unchanged regions, without re-architecting the drafts, and without expanding scope. Do not re-draft from scratch unless a finding explicitly says the draft is unsalvageable. If you believe a finding requires a larger restructure than the current approach supports, return `status: "scope_unsalvageable"` with evidence in `plan_broken_evidence` rather than silently expanding.

## Escape hatches — `no_decisions_found` and `scope_unsalvageable`

Two distinct exit codes, one per situation. Pick the one that matches; do not silently produce thin or invented drafts to satisfy the contract.

### `no_decisions_found` — round 1 only

Fires when, on the first drafting attempt, you determine the session contains no capture-worthy material at all: no closed-off forks meeting the triple-filter, the transcript is too thin to support any decision, or the scope confirmation captured a span with no real forks in it. **Stop and return**:

```json
{
  "status": "no_decisions_found",
  "plan_broken_evidence": "<what you looked for, what was absent, what evidence in the transcript supports the conclusion>"
}
```

The human gate will typically suggest `discard` or `request changes` to expand scope.

### `scope_unsalvageable` — round 2 or 3 only

Fires when, after at least one drafting attempt, a round-2+ finding reveals that the scope cannot yield clean decisions even with surgical fixes — the original approach is fundamentally wrong, not just defective in specific places, and patching it further would compound the drift. **Stop and return**:

```json
{
  "status": "scope_unsalvageable",
  "plan_broken_evidence": "<what you tried in the prior round(s), what the findings revealed about the structural problem, what evidence in the transcript supports the conclusion>"
}
```

The human gate will typically suggest `discard` and re-scope, or `request changes` to restructure.

The distinction matters because the two codes signal different problems and call for different human responses — do not collapse them into one.

## Required output schema

(Schema notation: `|` denotes "one of"; `<…>` denotes a placeholder you fill. The emitted JSON is plain JSON — no pipes, no angle brackets.)

```json
{
  "status": "complete" | "no_decisions_found" | "scope_unsalvageable",
  "files_created": [
    "<worktree>/decisions/<ULID>-<slug>.md",
    "<worktree>/synthesis/<ULID>-<slug>.md"
  ],
  "files_modified": [
    "<worktree>/decisions/<existing-ULID>-<existing-slug>.md"
  ],
  "rationale_out": "<≤10 lines: what was drafted, what edges connect to what, any flagged judgement calls>",
  "flags": ["<only if you found things worth surfacing — e.g., out-of-scope forks observed but not captured>"],
  "plan_broken_evidence": "<ONLY when status = no_decisions_found or scope_unsalvageable>"
}
```

**Constraints:**

- File paths are absolute.
- `files_created` and `files_modified` are non-empty when `status = complete`.
- `rationale_out` is ≤10 lines and never includes file bodies. The bodies are on disk; the digest is metadata about them.
- The digest is the only thing main sees from you. The drafts speak for themselves on disk.
- `no_decisions_found` is round-1-only; `scope_unsalvageable` is round-2-or-later only. Pick the one that matches the round you are in.
