# Capture agent brief — drafting template

This is the brief main hands to the capture sub-agent (`general-purpose`). Main fills in the placeholders before spawning.

---

## Objective

Draft the closed-off forks from the in-scope conversation into the per-session git worktree at `<worktree>` — a checkout of the user's decision archive on a dedicated capture branch. Produce N decision files plus at most one synthesis file plus any supersede flips on existing decisions, **directly on disk as unstaged changes**. Return a tight JSON digest describing what was written. **All reads, writes, and `git` calls happen inside `<worktree>`. The live archive clone is not touched during the iteration loop.**

## Inputs (round 1)

- **Worktree**: `<worktree>` (absolute path to the per-session git worktree, e.g., `/Users/<user>/projects/decision-archive/.claude/worktrees/capture-<timestamp>-<slug>`). All operations happen here, not in the live clone.
- **Base SHA**: `<base_sha>` (the capture-decision pre-flight captured this; the diff invariant is `git diff <base_sha>`)
- **Transcript path**: `<worktree>/transcripts/transcript-<timestamp>-<slug>.md` — read this faithfully; treat it as the source of truth for what the session decided
- **Recall digest**: <inline ≤50-line digest of related existing decisions from the recall sub-agent>
- **Format reference**: `<skill_dir>/references/decision-format.md` — read this before drafting; it defines the schema, the slug convention, the body sections, the triple-filter, and the supersede mechanics

## Inputs (round 2+ — additive, not substitutive)

- All round-1 inputs (unchanged — transcript, recall digest, format reference, archive root, base SHA)
- **Current cumulative diff**: `git -C <worktree> diff <base_sha>` — the unstaged drafts you produced in the prior round
- **Aggregated reviewer findings**: all `blocking` and `discrepancy` items from all three reviewers, with their `path:line` cites
- **Surgical-fix mode directive** (see below — apply verbatim)

## Method

1. **Read the transcript first.** Not the recall digest, not the format reference — the transcript. This is the source-of-truth for what was decided. Reviewers will hold every assertion in your `Chosen` and `Rationale` sections to what the transcript supports.

2. **Then read the format reference** (`decision-format.md`). Internalise: the triple-filter, the edge vocabulary, the slug convention, the supersede mechanics, the synthesis structure. The reviewers enforce all of it.

3. **Then read the recall digest.** Use it to identify likely edge targets. Edges declared in your drafts must reflect real relationships visible in the transcript — not just "this decision is about a related topic." The Archive Auditor checks edge justification.

4. **Apply the triple-filter** to every candidate fork:
   - Hard to reverse?
   - Surprising without context?
   - Real trade-off (genuinely-considered alternatives)?

   If any of the three fails, the fork is not a decision. Drop it or fold it into the synthesis as narrative.

5. **Draft alternatives-non-empty.** Every decision file must have at least two entries in `Alternatives considered`. An empty or single-item list invalidates the decision; the Quality Reviewer catches this as `blocking`.

6. **Articulate the `Rationale`.** A thin `Rationale` is a Quality Reviewer finding. Address every non-chosen alternative explicitly: what it would have cost, what it would have prevented. Without explicit rejection notes, a future reader cannot tell whether the rejected options were considered or merely overlooked.

7. **Surface assumptions.** The `Assumptions` section is where you list the beliefs this decision rests on. When an assumption later turns out wrong, the decision becomes a rewind candidate. Empty assumptions are tolerated when truly none apply; usually they don't.

8. **Handle supersessions in the same round.** If a new decision supersedes an existing one, you must in this same round:
   - Set the new decision's `supersedes: [X]` edge.
   - `Edit` X's frontmatter to flip `status: accepted` → `status: superseded`.
   - Cite X in the new decision's `Rationale` — explain what changed and why.
   - Optionally add a `## Note — Superseded by <new-id>` footer to X's body.

9. **Edge directionality discipline.**
   - `depends-on` — from this decision **to** what it depends on. Lower IDs typically.
   - `supersedes` — from successor **to** retired predecessor.
   - `informs` — from influencing decision **to** influenced one.
   - `synthesizes` — from synthesis file **to** the decisions it covers.

   **Edge liveness:** "A supersedes B → A depends-on B" is legitimate (the successor often builds on its predecessor's framing). But "C depends-on B where B is superseded by D and C is not the supersession" is wrong — C likely depends on D's live principle, not B's retired framing. Re-target.

10. **Write IDs sequentially.** Scan `<worktree>/decisions/` (and `<worktree>/synthesis/` if writing a synthesis) for the highest existing integer ID; assign new IDs starting from that + 1. The two namespaces increment independently.

11. **Synthesis is optional, written at most once per batch.** Include one if (and only if) the batch has connective tissue worth narrating — an architectural reframe, a supersede chain, follow-up threads. If you write a synthesis, its `synthesizes` edges must cover every decision in the batch.

## Boundaries

- **Do not edit files outside `<worktree>/decisions/`, `<worktree>/synthesis/`, or the supersede targets you have named.** No edits to README.md, IMPLEMENTATION.md, CONTEXT.md, or any other file. The Validator catches violations.
- **Do not rewrite existing decisions' bodies.** Frontmatter flips (status → superseded) and an optional `## Note` footer are the entire scope of edits to existing files. Anything more destroys history.
- **Do not expand scope.** The scope was set by the user in Step 1 of capture-decision. If you find a closed-off fork in the transcript that is **outside** scope, do not capture it. Flag it in `rationale_out` if it seems worth a future session.
- **Do not invent assumptions or rationale.** Every assertion in `Chosen` and `Rationale` must be traceable to the transcript. The Archive Auditor's transcript-faithfulness check is `discrepancy`-grade (forces another round) when violated.
- **Do not skip the triple-filter.** A fork that fails the filter does not become a decision file. Folding multiple fail-filter discussions into one "general decisions" file is also wrong — that's not how the format works.

## Surgical-fix mode directive (round 2+ — apply verbatim)

> You are operating on the same worktree across retries. The diff is shown to you as context for what is already in place, not as a patch to apply. Address every `blocking` and `discrepancy` finding from the prior round without regressing unchanged regions, without re-architecting the drafts, and without expanding scope. Do not re-draft from scratch unless a finding explicitly says the draft is unsalvageable. If you believe a finding requires a larger restructure than the current approach supports, return `status: "session_not_capture_ready"` with evidence in `plan_broken_evidence` rather than silently expanding.

## Escape hatch — `session_not_capture_ready`

If, while drafting, you determine that the session does not contain capture-worthy material — no closed-off forks meeting the triple-filter, the transcript is too thin to support assertions, the scope confirmation captured the wrong span, or a round-2+ finding reveals that the original approach is unsalvageable — **stop and return**:

```json
{
  "status": "session_not_capture_ready",
  "plan_broken_evidence": "<what you tried, what failed, what evidence in the transcript supports the conclusion>"
}
```

Do not silently produce thin or invented drafts to satisfy the contract. The escape hatch exists for exactly this case.

## Required output schema

(Schema notation: `|` denotes "one of"; `<…>` denotes a placeholder you fill. The emitted JSON is plain JSON — no pipes, no angle brackets.)

```json
{
  "status": "complete" | "session_not_capture_ready",
  "files_created": [
    "<worktree>/decisions/<id>-<slug>.md",
    "<worktree>/synthesis/<id>-<slug>.md"
  ],
  "files_modified": [
    "<worktree>/decisions/<existing-id>-<existing-slug>.md"
  ],
  "rationale_out": "<≤10 lines: what was drafted, what edges connect to what, any flagged judgement calls>",
  "flags": ["<only if you found things worth surfacing — e.g., out-of-scope forks observed but not captured>"],
  "plan_broken_evidence": "<ONLY when status = session_not_capture_ready>"
}
```

**Constraints:**

- File paths are absolute.
- `files_created` and `files_modified` are non-empty when `status = complete`.
- `rationale_out` is ≤10 lines and never includes file bodies. The bodies are on disk; the digest is metadata about them.
- The digest is the only thing main sees from you. The drafts speak for themselves on disk.
