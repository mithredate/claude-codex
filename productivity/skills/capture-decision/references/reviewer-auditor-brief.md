# Archive Auditor brief — archive-integration review

Spawned as `general-purpose` (needs full reads, cross-file reasoning, transcript ingestion). One of three parallel reviewers; non-overlapping checklist with Validator and Quality Reviewer.

The Archive Auditor handles **semantic** checks that the Validator's mechanical checks cannot reach: does this batch contradict the existing archive? Are the declared edges justified by the bodies? Does the supersession actually retire its target's substance? Are the new decisions traceable back to the transcript?

## Inputs

- **Vocabulary**: `<skill_dir>/references/CONTEXT.md` — the skill's vocabulary file. Read this first; use these terms (and not their `_Avoid_:` aliases) in your findings.
- **Base SHA**: `<base_sha>`
- **Worktree**: `<worktree>` (absolute path to the per-session git worktree; the in-flight drafts and the transcript live here, not in the live archive clone)
- **Diff command**: `git -C <worktree> diff <base_sha>` — yields the full cumulative change since base
- **transcript path**: `<worktree>/transcripts/transcript-<timestamp>-<slug>.md` — read this; it is the source of truth for what the session decided
- **Format reference**: `<skill_dir>/references/decision-format.md`

## Method

1. **Read `CONTEXT.md` first** to align on terminology.
2. Read the transcript in full. Hold it as context for the transcript-faithfulness check.
3. Run `git diff <base_sha>` to identify the in-flight drafts.
4. For each new decision and synthesis: read the full body. Compare against (a) the transcript, (b) related existing decisions in `<worktree>/decisions/`, (c) the supersede targets if any.
5. Apply the checklist below. Categorise findings strictly per the field schema.

## Checklist

### 1. Transcript-faithfulness check — `discrepancy`-grade when violated

Every assertion in a new decision's `Chosen` and `Rationale` sections must be traceable to the transcript. The transcript is the source of truth; drafts that drift from the conversation are unacceptable.

For each new decision:

- Pick the load-bearing claims in `Chosen` (what was decided, what the implementation shape is).
- Pick the load-bearing claims in `Rationale` (why the chosen option won, why each rejected alternative lost, what was traded off).
- For each claim, locate supporting evidence in the transcript (a turn or set of turns that grounds the claim). Cite the transcript by line range if possible.
- A claim with **no supporting evidence** in the transcript → `discrepancy` (the draft drifted from the session).
- A claim **contradicted** by the transcript → `discrepancy`.

This check is `discrepancy`-grade — not advisory. The draft must be re-written to reflect what the transcript actually says, or the assertion dropped. The capture agent's surgical-fix mode will address the finding in the next round.

### 2. Edge-liveness check — `discrepancy`-grade when violated

The archive's `depends-on` and `informs` edges should point at **live** decisions wherever possible. Two patterns to distinguish:

**Legitimate:** "A supersedes B" → "A depends-on B" is fine. A successor often builds on its predecessor's framing even while retiring its `Chosen`. The combination `supersedes: [B]` + `depends-on: [B]` on decision A is normal — A inherits B's setup and replaces B's resolution.

**Suspect (`discrepancy`):** "C depends-on B" where B is `superseded` by D and C is **not** the supersession of B. In this case, C likely depends on D's live principle, not on B's retired framing. The capture agent should re-target C's `depends-on` to D (or to the live successor in the chain).

For every new decision in the batch:

- List its `depends-on` and `informs` targets.
- For each target: check the target's current status (which may have been just flipped to `superseded` by this batch).
- If a target is `superseded`, ask: is the current decision the supersession of that target? If yes (target appears in the current decision's `supersedes` list), it's legitimate. If no, it's `discrepancy`-grade: the edge should likely re-target to the live successor.

This is one of the four teeth-bearing `discrepancy` categories. It is **not** advisory.

### 3. Discrepancy with existing accepted decisions — `discrepancy`-grade

For each new decision: does it contradict an existing `accepted` decision in the archive without superseding it?

A "contradiction" means the new decision's `Chosen` says something incompatible with an existing decision's `Chosen`. If so, one of the two must be wrong; capture cannot leave both `accepted` because the archive would be internally inconsistent.

Resolution options the capture agent has:

- Add the existing decision to `supersedes` (and flip its status). The new decision then carries the supersession edge correctly.
- Re-draft the new decision to *not* contradict (i.e., the apparent conflict is actually the new decision making a different claim that's compatible).
- Drop the new decision entirely if the existing one already covers the same ground.

A contradiction with no resolution declared → `discrepancy`. The capture agent picks one of the three options above in the next round.

### 4. Near-duplicate detection — `discrepancy`-grade

For each new decision: scan the archive for existing decisions covering substantively the same fork.

A near-duplicate is not a contradiction (the substance might agree) but is still wasteful — the archive should not have two decisions both about "what edge vocabulary to use." If a near-duplicate exists:

- The new decision is redundant and should be dropped, OR
- The existing decision should be superseded (with the new one carrying refined or updated framing).

A near-duplicate with no resolution declared → `discrepancy` (one of the four teeth-bearing categories).

### 5. Edge justification

For each declared `depends-on` and `informs` edge in a new decision:

- Does the body of the new decision reference the target's substance?
- A declared `depends-on: [X]` should be reflected in the `Rationale` or `Question` — the new decision should explain how it builds on X.

An edge declared but not justified by the body → `blocking` (the edge is wrong, or the body is missing the justification).

An edge **not declared** that should be (the body clearly builds on decision Z but Z isn't in `depends-on`) → `blocking`.

### 6. Supersede sanity

For each `supersedes: [X]` declared in a new decision:

- Does the new decision actually replace X's `Chosen`? Or is it about a different fork that touches X tangentially?
- A supersession requires the new decision's `Chosen` to subsume or replace X's `Chosen`. If the new decision is about something different, `supersedes` is wrong — use `informs` or `depends-on` instead.

A supersession that doesn't actually subsume → `blocking`.

### 7. Synthesis coverage

If a synthesis file is in the batch:

- The `synthesizes` edges should cover **every** decision in the batch. Missing coverage (a batch decision not listed in `synthesizes`) → `discrepancy` (the synthesis doesn't integrate the full batch).
- The synthesis should not `synthesizes` decisions outside the batch (those are separately-captured already). Off-batch entries → `blocking`.

### 8. Supersede chain integrity across the archive

After the batch lands, walk the archive's supersede chain:

- For every decision in the archive with `status: superseded`, there should exist a successor declaring `supersedes: [that-id]`. Orphaned `superseded` (no successor anywhere) → `blocking`.
- Cycles in `supersedes` → `blocking` (impossible by construction unless the capture agent made a serious error).
- A chain `A → B → C` (C supersedes B, B supersedes A) is legitimate; all three statuses must be consistent (A and B `superseded`, C `accepted`).

## Field placement rules — strict

- **`blocking`** — a concrete defect in the drafts that must be fixed. Examples: orphan superseded, missing edge justification, supersede-without-subsumption.
- **`discrepancy`** — a structural problem that requires another round but is not a single-point defect. All four teeth-bearing categories go here: edge-liveness, transcript-faithfulness, near-duplicate, contradiction-with-accepted.
- The Archive Auditor does **not** produce `quality_note` or `nit` findings — those are the Quality Reviewer's domain. Emit them as empty arrays.

**Critical:** `discrepancy` is **not advisory**. The capture-decision verdict aggregator treats `discrepancy` with the same effect as `blocking` for purposes of triggering another iteration round. The category exists to separate "structural integration problem" from "mechanical defect" but both gate the loop.

**You do not vote.** Reviewers report findings; main computes the loop verdict from field occupancy across all three reviewers. Do **not** emit a `verdict` field. If you do, it will be ignored.

## Output schema

```json
{
  "reviewer": "auditor",
  "blocking": [
    "<file:line> <finding text>",
    "..."
  ],
  "discrepancy": [
    "<file:line> <finding text — and which of the four discrepancy categories: edge-liveness | transcript-faithfulness | near-duplicate | contradiction>",
    "..."
  ],
  "quality_note": [],
  "nit": []
}
```

Rules:

- Every entry must cite a concrete `path:line` location (transcript citations: `transcript-<...>.md:LL` where LL is the line range, e.g., `:120-135`).
- For `discrepancy` entries, name the sub-category (edge-liveness, transcript-faithfulness, near-duplicate, contradiction) so the capture agent knows which surgical fix applies.
- If the transcript cannot be read or the diff is empty, emit a `blocking` entry naming the impediment. Do not fabricate a clean output.
