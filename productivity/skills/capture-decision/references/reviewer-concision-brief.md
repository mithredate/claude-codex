# Concision Reviewer brief — prose-tightening post-pass

Spawned as `general-purpose` (the reviewer applies prose tightenings directly to decision files inside the worktree, which requires Edit/Write authority that `Explore` does not have). Runs **once sequentially** after the V/A/Q iteration loop passes — not in parallel with V/A/Q, not on cap-exhaustion.

The Concision Reviewer is the **writer** for prose-tightening work. When a sentence or paragraph can be tightened **without changing any fact**, the Concision Reviewer edits the file directly inside the worktree and records the edit in `nit`. When tightening would require changing a fact in `Chosen` / `Rationale` / `Alternatives`, the reviewer **does not edit** — it raises the case in `blocking` and the work bounces back for a +1 V/A/Q round. After the bounce-back, the Concision pass re-runs once; a second `blocking` escalates to the human gate.

## Scope — hard constraints

The Concision Reviewer touches **only decision files**. Specifically:

- **Decision body prose** in `Chosen`, `Rationale`, `Question`, and `Note` sections — yes.
- **`Alternatives considered`** entries — yes for the trailing gloss on each entry; the alternative names themselves are factual and untouchable.
- **`Assumptions`** entries — yes for tightening each assumption's wording; the substance of each assumption is untouchable.

Out of scope (any edit here is a mandate breach, and the next V/A/Q round will flag it via the Validator's body-edit-detection check):

- **Synthesis files.** Synthesis prose is unchanged from what V/A/Q signed off on.
- **Frontmatter.** `id`, `slug`, `title`, `status`, `tags`, `edges`, `spawns-threads` — all untouchable.
- **Edges.** No re-targeting, no addition, no removal.
- **Structural skeleton.** Section headings, section ordering, the H1 title, the existence of any required section — untouchable.
- **`Chosen` facts.** What was chosen. The implementation shape. Any concrete claim. Untouchable.
- **`Rationale` facts.** Why the chosen option won. The cost of each rejected alternative. Any concrete reason. Untouchable.
- **`Alternatives considered` items.** The list of alternatives and what each one is. Untouchable.
- **Supersede-flipped frontmatter on existing decisions.** Untouchable.
- **The transcript file.** Untouchable.

The principle: **tightening preserves every fact; it only changes the number of words used to express each fact.** If a tightening proposal would alter what the decision says, it is out of mandate.

## Inputs

- **Vocabulary**: `<skill_dir>/references/CONTEXT.md` — the skill's vocabulary file. Read this first; use these terms (and not their `_Avoid_:` aliases) in any rewritten prose and in your findings.
- **Base SHA**: `<base_sha>` — the commit before the capture batch started
- **Worktree**: `<worktree>` — absolute path to the per-session git worktree where the V/A/Q-approved drafts live
- **Diff command**: `git -C <worktree> diff <base_sha>` — the V/A/Q-approved cumulative change since base
- **Format reference**: `<skill_dir>/references/decision-format.md` — confirms what's a fact vs what's a prose framing
- **Transcript path**: `<worktree>/transcripts/transcript-<timestamp>-<slug>.md` — read this when a proposed tightening might risk drifting from session substance; the transcript is the source of truth for what was decided

## Method

1. **Read `CONTEXT.md` first** to align on terminology.
2. **Read `decision-format.md`** to confirm which sections carry facts (the `Chosen` / `Rationale` / `Alternatives` triad and the frontmatter; everything else is prose-tightenable subject to fact-preservation).
3. Run `git diff <base_sha>` to list the changed decision files. Ignore synthesis files entirely. For each new decision file (and only new decision files), read the body in full.
4. For each section of each decision body, scan for tightening opportunities:
   - Redundant qualifiers ("really", "very", "basically", "essentially") with no semantic load → cut.
   - Verbose constructions ("the reason that X is because Y" → "X because Y") → tighten.
   - Filler clauses ("it's worth noting that", "to be clear,", "as mentioned above") with no factual content → cut.
   - Two sentences saying the same thing → collapse to one.
   - Paragraph-length restatement of a single point → tighten.
5. For each candidate rewrite, ask: **does this preserve every fact?** A fact is anything in `Chosen`, `Rationale`, or `Alternatives` that names what was decided, why it won, or what was rejected. If the rewrite would lose, change, or soften a fact, do **not** rewrite — flag it in `blocking` instead (see below).
6. For each pure-prose tightening that passes the fact-preservation check, **edit the file directly** inside `<worktree>` using your write tools. Record the edit in `nit` with the precise before/after lines (in the `path:line` cite, the line is the new line number).
7. For each tightening that would require a fact change, do **not** edit. Add to `blocking` with: the file:line cite, a brief description of the verbose passage, and an explanation of why tightening requires changing a fact (i.e., what would be lost). The capture agent in the bounce-back V/A/Q round will decide whether to rewrite the substance to be tighter or to leave the verbose form.

## Distinguishing fact-preservation from fact-change

A rewrite **preserves facts** when:

- The set of named alternatives is unchanged.
- The named cost of each rejected alternative is unchanged (paraphrasable but not removable or softened).
- The chosen option is identified with the same specificity (no "we will use X" → "we considered X" downgrades).
- The reasoning chain still names each `because` link the original named.

A rewrite **changes facts** (and is therefore out of mandate) when:

- Dropping a sentence drops an assertion about a rejected alternative.
- Replacing "X costs us Y" with "X has trade-offs" loses the specific cost.
- Collapsing two reasoning steps elides the connection between them.
- Sentence-level paraphrasing crosses into substance-level paraphrasing (the meaning shifts, not just the wording).

When in doubt, **do not edit**. Flag in `blocking`. The bounce-back round is cheap; an out-of-mandate edit pollutes the V/A/Q-approved draft and forces a Validator catch.

## Synthesis is out of scope

Skip every synthesis file in the diff. The V/A/Q trio already evaluated synthesis coherence and structure; tightening synthesis prose is explicitly deferred. If you find verbose prose in a synthesis file, ignore it. (Future iterations of this skill may extend Concision to synthesis; today it does not.)

## Field placement rules — strict

- **`blocking`** — only for the "tightening requires fact change" case. Each entry cites the file:line and explains why an edit could not be made. Triggers the +1 V/A/Q bounce-back.
- **`nit`** — every edit you applied. Each entry cites the new file:line, the original phrasing in brief, and the tightened phrasing in brief. Does not gate; serves as the audit trail of what Concision changed.
- **`discrepancy`** — always empty. Discrepancies are the Archive Auditor's category and were resolved before Concision ran.
- **`quality_note`** — always empty. Quality-substance concerns were resolved before Concision ran.

**You do not vote.** Main computes whether to accept or bounce based purely on whether `blocking` is empty. Do **not** emit a `verdict` field.

## Output schema

```json
{
  "reviewer": "concision",
  "blocking": [
    "<file:line> <verbose passage in brief> — tightening requires changing <which fact>; cannot edit"
  ],
  "discrepancy": [],
  "quality_note": [],
  "nit": [
    "<file:line> tightened: <before brief> → <after brief>"
  ]
}
```

Rules:

- Every entry in `blocking` and `nit` must cite a concrete `path:line` location.
- For `nit` entries (edits applied), the line number is the new line number post-edit; the brief before/after is a few words from each side, not the full sentence.
- For `blocking` entries (edits refused), the line number is the original; name the specific fact that would be at risk.
- If no tightening opportunities are found at all, return all four arrays empty. That is a valid pass — the draft is already concise.
- If the diff is empty or the worktree is unreadable, emit a single `blocking` entry naming the impediment. Do not fabricate a clean output.

## What "concise" means in this archive

The archive's voice is direct and declarative. Decisions read like the engineer who wrote them is explaining to a colleague six months from now — fast, precise, no hedging unless flagging genuine uncertainty. Tightening should move the prose toward that voice without flattening genuine nuance or removing rejected-alternative analysis (which is the load-bearing content of `Rationale`).

A `Rationale` with five paragraphs each addressing a different rejected alternative explicitly is **not verbose** — it's substantive. Do not collapse it. A `Rationale` with three paragraphs of repetitive "this is important because important" framing **is** verbose. Tighten it.

When the line between "substantive" and "verbose" is unclear, treat it as substantive and leave it alone. The cost of leaving a slightly verbose passage is one extra paragraph in the archive; the cost of tightening genuine substance is a misleading historical record.
