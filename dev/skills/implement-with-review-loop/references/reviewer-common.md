# Reviewer common contract

All four reviewers (Validator, Codebase Auditor, Questioner, Craft Reviewer) read this file first, then their role-specific brief. Anything stated here applies to every reviewer.

## Adversarial stance

The implementer's job was to make the change work; their incentive is to declare success. Your job is to find what's wrong with it; your incentive is to find what they missed. The category lists in each role-specific brief are illustrative starting points, not a closed checklist — if you spot something that does not fit a listed category but is wrong, flag it with evidence.

## You do not vote

Reviewers report findings. Main computes the loop verdict from field occupancy across all four reviewers — not from any per-reviewer status. Do **not** emit a `verdict` or `status` field on your output. If you do, it will be ignored.

## Five-field output schema

Every reviewer returns the same five arrays. Roles differ only in which fields they populate.

```json
{
  "reviewer": "<role>",
  "blocking":      ["<file:line> <one-sentence finding>", "..."],
  "discrepancy":   ["<file:line or rationale_out quote> <one-sentence finding>", "..."],
  "quality_note":  ["<file:line> <one-sentence finding>", "..."],
  "nit":           ["<file:line> <one-sentence finding>", "..."],
  "learnings":     ["<design-level, code-independent constraint>", "..."]
}
```

### Field semantics

- **`blocking`** — a concrete local defect with `file:line` evidence that the implementer should fix by re-coding to the same plan. Any reviewer may populate. Gates the loop; routes to a surgical patch.
- **`discrepancy`** — a design failure: wrong shape, wrong approach, wrong assumption — "the plan itself is wrong; re-coding to this plan will not fix it." Never a local code defect. **Questioner only**; the other three reviewers always leave it empty. Gates the loop and **resets the work to base** — the next round re-derives the approach from scratch against the learning ledger, or returns `plan_broken`.
- **`quality_note`** — an addressable craft or fit concern. Codebase Auditor, Questioner, and Craft Reviewer may populate; Validator always leaves it empty. Gates the loop only when no `blocking` or `discrepancy` is present in the round; routes to a surgical patch.
- **`nit`** — minor. Never gates. Any reviewer may populate.
- **`learnings`** — every finding you placed in `blocking`, `discrepancy`, or `quality_note`, restated as a design-level constraint on **any future implementation**. `nit` findings produce no learnings.

### Writing learnings

Findings die with the code — after a reset, your `file:line` citations point at nothing. Learnings are the only part of your output that survives, appended verbatim to a ledger that steers every future implementation round. Therefore:

- **Name the root cause, not the symptom.** "The banner shows the wrong time" is a symptom; "any code that trusts client-side wall-clock time in session-expiry paths recreates this bug" is a learning.
- **Code-independent phrasing.** State the constraint a future implementation must respect; no `file:line`, no references to identifiers that exist only in the current diff. (This is the one field exempt from the evidence requirement below — the evidence lives in the finding it restates.)
- **Skip purely mechanical findings.** A finding that carries no design-level constraint (a command exited non-zero, a debug print left in, a scope escape) produces no learning — restating it would only add noise to an uncurated ledger.

If you find yourself wanting to put the same finding in both `blocking` and `discrepancy`, place it in `discrepancy` only — the implementer cannot fix it by re-coding to the same plan.

If a craft or fit concern is severe enough to demonstrably break correctness, raise it as `blocking`, not `quality_note`. The category lists permit this re-classification.

## Evidence requirement

Every entry in `blocking`, `discrepancy`, `quality_note`, and `nit` must cite a concrete `file:line` location and state what the cited code shows. For `discrepancy` findings about framing, you may instead cite a quoted phrase from `rationale_out` paired with the diff or surrounding-code site that contradicts it.

"I think there might be a better way" or "this feels off" with no anchored evidence does not qualify. Drop it; do not downgrade to `nit`.

The cited file may be **anywhere in the repository** — not just inside the diff. Cross-cutting structural findings often hinge on how unchanged code interacts with the change.

## Empty arrays are valid

If you have no findings in a category, return that array empty. Clean code is a valid outcome; do not invent findings to look thorough. Always include all five arrays in the output even when empty, so the shape is uniform.
