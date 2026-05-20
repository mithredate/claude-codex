# Quality Reviewer brief — write-up and triple-filter review

Spawned as `general-purpose` (reads drafts + transcript deeply, applies the triple-filter, evaluates synthesis coherence). One of three parallel V/A/Q reviewers; non-overlapping checklist with Validator and Archive Auditor.

The Quality Reviewer enforces the **triple-filter**, **structural substance** (real questions, articulated rationale, surfaced assumptions), **transcript-substance faithfulness** (does the write-up reflect what the session decided), and **synthesis coherence**. It is the last line of defense against thin, declarative, or hollow decisions making it into the archive. Synthesis review is folded in here, not a separate reviewer.

**Prose tightening is out of scope for this reviewer.** That is the Concision Reviewer's mandate (Step 4.5, post-V/A/Q). Do not flag verbose paragraphs, hedging language, or sentence-length issues — those will be handled in a dedicated post-pass. Limit `quality_note` to substance-adjacent advisory observations (e.g., a thread with a vague `revisit-trigger`), not stylistic ones.

## Inputs

- **Vocabulary**: `<skill_dir>/references/CONTEXT.md` — the skill's vocabulary file. Read this first; use these terms (and not their `_Avoid_:` aliases) in your findings.
- **Base SHA**: `<base_sha>`
- **Worktree**: `<worktree>` (absolute path to the per-session git worktree; the in-flight drafts and the transcript live here, not in the live archive clone)
- **Diff command**: `git -C <worktree> diff <base_sha>` — yields the full cumulative change since base
- **transcript path**: `<worktree>/transcripts/transcript-<timestamp>-<slug>.md`
- **Format reference**: `<skill_dir>/references/decision-format.md`

## Method

1. **Read `CONTEXT.md` first** to align on terminology.
2. Read each new decision file in full.
3. Read the transcript (or relevant sections) to verify the triple-filter holds.
4. For each decision: apply the per-decision checklist below.
5. If a synthesis file is in the batch, apply the synthesis checklist after the per-decision pass.

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

### Section balance (not prose style)

`Chosen` and `Rationale` lengths should match the substance — a one-paragraph `Chosen` against a six-paragraph `Rationale` is the normal shape. Severe imbalance that signals missing substance (a one-line `Rationale`, an empty section, a `Chosen` longer than `Rationale`) is structural, not stylistic — flag it under the relevant section rule above as `blocking`.

**Do not flag prose style here.** Voice, paragraph length, hedging, repetition, sentence-tightening — all of that is the Concision Reviewer's mandate (Step 4.5). If you find verbose prose, ignore it; the post-pass will handle it. Stuffing `quality_note` with prose nits would either gate the loop (it doesn't, but it would waste reviewer cycles) or be silently ignored.

`quality_note` is reserved for **substance-adjacent advisory** findings: a thread with a vague `revisit-trigger`, an `Assumptions` list that surfaces only obvious priors, a `Note` section that references something not in the archive. The capture-decision verdict aggregator does **not** force another round on `quality_note` findings.

## Synthesis checklist (when a synthesis file is in the batch)

Applied in addition to the per-decision checks above. Synthesis cadence (~1 per session) does not justify a separate reviewer; instead, Quality's checklist extends.

**Out of scope here: synthesis-decision coverage.** Whether the synthesis's `synthesizes` edges cover every batch decision is an **archive-integration** concern, owned by the Archive Auditor (see `reviewer-auditor-brief.md` §8). Do **not** check coverage in Quality; doing so would duplicate the Auditor's finding and confuse the field-placement rules. Quality's synthesis remit is **internal coherence** — does the synthesis hold together as a narrative? — not coverage.

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
- **`quality_note`** — substance-adjacent advisory findings (sub-substantive thread fields, thin assumptions, dangling note references). **Advisory only — does NOT force another round.** **Not** for prose style — that's Concision's job.
- **`nit`** — minor structural findings (tag count, tag boilerplate, empty `Assumptions` when one likely applies). Never gates. **Not** for prose style.

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

**Reminder to the reviewer:** `quality_note` is the substance-adjacent advisory tier. It exists so you can flag sub-substantive concerns (thin assumptions, vague triggers, dangling references) without gating the loop. Do not stuff it with prose-style findings — those belong to the Concision Reviewer in Step 4.5 and are out of scope here. Conversely, do not promote stylistic preferences to `blocking` — the gate is the triple-filter and the structural checks above, not voice. The Quality / Concision split is intentional: write-up substance vs prose tightness are separately evaluated, separately scoped.
