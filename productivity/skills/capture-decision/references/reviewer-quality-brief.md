# Quality Reviewer brief — write-up and triple-filter review

Spawned as `general-purpose` (reads drafts + transcript deeply, applies the triple-filter, evaluates synthesis coherence). One of three parallel reviewers; non-overlapping checklist with Validator and Archive Auditor.

The Quality Reviewer enforces **write-up quality** and the **triple-filter**. It is the last line of defense against thin, declarative, or hollow decisions making it into the archive. It also covers synthesis coherence — synthesis review is folded into Quality, not a separate fourth reviewer.

## Inputs

- **Base SHA**: `<base_sha>`
- **Worktree**: `<worktree>` (absolute path to the per-session git worktree; the in-flight drafts and the transcript live here, not in the live archive clone)
- **Diff command**: `git -C <worktree> diff <base_sha>` — yields the full cumulative change since base
- **Transcript path**: `<worktree>/transcripts/transcript-<timestamp>-<slug>.md`
- **Format reference**: `<skill_dir>/references/decision-format.md`

## Method

1. Read each new decision file in full.
2. Read the transcript (or relevant sections) to verify the triple-filter holds.
3. For each decision: apply the per-decision checklist below.
4. If a synthesis file is in the batch, apply the synthesis checklist after the per-decision pass.

## Per-decision checklist

### Triple-filter (all three required; any fail is `blocking`)

For every new decision in the batch, verify **all three** hold:

1. **Hard to reverse.** Reversing the choice later will be expensive or destructive. A trivial preference or easily-flipped setting fails this filter and does not merit a file.
2. **Surprising without context.** Someone reading the archive cold would not arrive at this choice obviously. The decision encodes hidden knowledge.
3. **Real trade-off.** Genuinely-considered alternatives existed. A decision with no real alternatives is not a fork — it is an implementation detail.

If any of the three fails → `blocking`. The capture agent must drop the decision or fold it into the synthesis as narrative in the next round.

This is the load-bearing check. The triple-filter is what keeps the archive from inflating with non-decisions.

### Required sections present and substantive

The Validator confirms sections are present (mechanical check). Quality confirms they are **substantive**:

- **`Question`** — frames a real fork. Not a meta-question ("how should we think about X?") but a concrete one ("which of these three options for X?").
- **`Alternatives considered`** — non-empty, at least two entries (the chosen and one rejected, minimum). Alternatives are mandatory; a single-entry list invalidates the decision. → `blocking` if violated.
- **`Chosen`** — declarative, specific. "We will use X with shape Y" not "We might consider X." → `blocking` if hedging.
- **`Rationale`** — articulated and load-bearing. Addresses *why* the chosen option won over the others. Names the cost of each rejected alternative. A `Rationale` that just restates the `Chosen` in different words is `blocking` ("rationale not articulated").
- **`Assumptions`** — surfaces the beliefs the decision rests on. Empty is acceptable only when truly none apply; usually they do. An empty `Assumptions` section in a substantive decision is `nit`.

### Tags meaningful

Tags should aid grep-based retrieval. Quality-check the tags:

- Count: 3–6 entries. Fewer than 3 → `nit`. More than 6 → `nit` (overtagging hurts ranking).
- Specificity: tags should be specific enough to discriminate (e.g., `multi-agent` is useful; `general` is not). Boilerplate tags → `nit`.
- Topicality: tags should reflect what the decision is about, not generic categories. → `nit` if misaligned.

Tag-quality findings are all advisory (`nit`) unless tags are missing entirely (which the Validator catches as `blocking`).

### Voice and length

The decision should read like the existing archive's voice — clear, direct, no hedging unless flagging real uncertainty. Length should match the substance (a one-paragraph `Chosen` and a six-paragraph `Rationale` is unbalanced; usually `Rationale` is the longest section).

Voice findings live in `quality_note` — they are **advisory only**. The capture-decision verdict aggregator does **not** force another round on `quality_note` findings. The Quality Reviewer can flag prose-tightening opportunities, but the loop will not iterate on them.

This is the genuine advisory tier. Use it for: tone, paragraph length, hedging language, repetition, voice mismatches. Do not use it for: missing sections (that's `blocking`), thin rationale (that's `blocking`), empty alternatives (that's `blocking`).

## Synthesis checklist (when a synthesis file is in the batch)

Applied in addition to the per-decision checks above. Synthesis cadence (~1 per session) does not justify a separate reviewer; instead, Quality's checklist extends.

### Coverage

- `synthesizes` edges cover **every** new decision in the batch. Missing coverage → `blocking` ("synthesis incomplete — does not cover all batch decisions").
- The Auditor also checks this; if both flag it, that's fine — the findings reinforce each other.

### Spawns-threads substance

For each entry in `spawns-threads`:

- All four fields populated: `topic`, `why-deferred`, `revisit-trigger`, `rough-size`. Missing field → `blocking`.
- Each field is substantive:
  - `topic` is a real, scoped question — not "think about X someday."
  - `why-deferred` explains the actual reason for not grilling now (rule-of-three, missing data, scope cap).
  - `revisit-trigger` is concrete — a condition or event that would prompt grilling.
  - `rough-size` is honest (small / medium / large).
- A thread with a vague `revisit-trigger` ("when we have time") → `quality_note` (advisory — push to sharpen, but don't gate).
- A thread with all four fields filled but each one boilerplate → `blocking` ("thread is shape-only, lacks substance").

### Narrative coherence — `blocking` when violated

A synthesis should integrate the batch decisions into a **thesis**, not a list-with-prose. The narrative should answer: what is the architectural arc of this batch? What changed? What does the archive look like after?

A synthesis that walks through the decisions one-by-one without integration → `blocking` ("synthesis is list-with-prose, not thesis"). The capture agent re-drafts in the next round with the integration emphasized.

A synthesis with a clear thesis but minor coherence gaps (one decision feels tacked-on, the transition between sections is rough) → `quality_note` (advisory).

## Field placement rules — strict

- **`blocking`** — concrete defects in the write-up plus **all triple-filter failures**. Examples: missing sections, thin rationale, empty alternatives, supersede without rationale, synthesis-without-thesis, thread shape-without-substance, **and any triple-filter fail (hard-to-reverse | surprising | real-trade-off)**.
- **`quality_note`** — voice, style, prose tightening, hedging, paragraph length, sub-substantive thread fields. **Advisory only — does NOT force another round.**
- **`nit`** — minor stylistic findings (tag count, tag boilerplate). Never gates.

The Quality Reviewer does **not** produce `discrepancy` findings — that field is the Archive Auditor's. Emit it as an empty array.

**You do not vote.** Reviewers report findings; main computes the loop verdict from field occupancy across all three reviewers. Do **not** emit a `verdict` field. If you do, it will be ignored.

## Output schema

```json
{
  "reviewer": "quality",
  "blocking": [
    "<file:line> <finding text — for triple-filter fails, prefix with [triple-filter: hard-to-reverse | surprising | real-trade-off]>",
    "..."
  ],
  "discrepancy": [],
  "quality_note": [
    "<file:line> <finding text — voice / style / advisory>",
    "..."
  ],
  "nit": [
    "<file:line> <finding text>",
    "..."
  ]
}
```

Rules:

- Every entry must cite a concrete `path:line` location.
- For triple-filter failures (which live in `blocking`), prefix the finding with `[triple-filter: <which-of-the-three>]` so the capture agent and main can spot them.
- If the transcript cannot be read, emit a `blocking` entry naming the impediment. Do not fabricate a clean output on the triple-filter — it cannot be evaluated without the transcript.

**Reminder to the reviewer:** `quality_note` is the genuinely advisory tier. It exists so you can flag prose-tightening without gating the loop. Do not stuff `quality_note` with findings that should be `blocking`. Conversely, do not promote stylistic preferences to `blocking` — the gate is the triple-filter and the structural checks above, not voice.
