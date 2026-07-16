# Building & publishing the dashboard

The build is deterministic: you write a small **scorecard JSON**, a Node script injects it into a bundled HTML template, and you publish the result with the Artifact tool. You never hand-write chart code.

```bash
node scripts/build-dashboard.mjs --data /path/scorecard.json --out /path/dashboard.html
# then: publish /path/dashboard.html via the Artifact tool (favicon 📊)
```

The output is a self-contained page (inline CSS/JS/SVG, no external requests — Artifact-CSP-safe), light/dark aware, with four panels:

- **A · Toggle** — check features on/off; every dimension bar recomputes live. This is the "what does dropping X buy me?" view.
- **B1 · Radar** — one polygon per feature over the five dimensions; shape contrast at a glance.
- **B2 · Waterfall** — baseline → +feature → … → total; marginal cost building to the whole.
- **B3 · Heatmap** — features × dimensions, one number per cell.
- **Methodology** — at the very end: per dimension, what the number means and how it was derived this run. Required.

## Scorecard JSON contract

```jsonc
{
  "title": "PR #137 — shared-tool guardrail",     // shown in the header
  "subtitle": "Sliced into 2 features, scored 0–10 marginal per dimension.",
  "mode": "estimate",                              // measure | estimate | probe-by-implementing
  "dimensions": ["Cyclomatic","Cognitive","Coupling","Connascence","Change-amp"],
  "features": [
    {
      "id": "gate",
      "name": "Shared-tool gate",
      "role": "deep module · 1 layer · self-contained",   // one-line shown on the verdict card
      "blurb": "Blocking lint rule + target-aware pass",    // shown on the toggle
      "scores": [8, 5, 3, 2, 1],                            // same order as dimensions
      "core": true                                          // core features render first / accent colour
    },
    {
      "id": "autofill",
      "name": "Checklist trait + autofill",
      "role": "shallow + wide · 4 layers · duplicated logic",
      "blurb": "Auto-derived trait, checklist section, auto-verify wiring",
      "scores": [3, 6, 9, 8, 8]
    }
  ],
  "ownershipDims": ["Coupling","Connascence","Change-amp"],  // summed into the "ownership cost" headline
  "methodology": [
    {
      "dim": "Cyclomatic",
      "means": "Decision points the feature adds, +1 per function.",
      "derived": "Counted branches in sharedToolVersionCheck.evaluate (~13) + the two page watches (~7); estimated from the diff."
    },
    { "dim": "Cognitive", "means": "Reading difficulty, nesting-weighted.", "derived": "Gate is flat guard-clauses (low); autofill nests .some within .some (higher). Estimated." },
    { "dim": "Coupling", "means": "Modules touched × layers crossed.", "derived": "Gate ≈ 5 files in the linter layer; autofill spans 9 files across types/utils/config/server/UI. Counted from the diff." },
    { "dim": "Connascence", "means": "Strength × distance of coupling added.", "derived": "Autofill adds a 4-site magic-string name binding, a persisted optional-field invariant, and duplicated shared-tool logic (algorithm). Inspected." },
    { "dim": "Change-amp", "means": "Sites that must change together for one logical change.", "derived": "Redefining 'shared tool' edits 2 implementations for autofill vs 1 for the gate. Traced." }
  ],
  "verdict": "The gate is expensive to write, cheap to own; the autofill is the reverse — dropping it removes 25 units of ownership cost while keeping 100% of the blocking value."
}
```

### Field notes

- `scores` array length must equal `dimensions` length; values 0–10.
- `features` supports 2–6 entries; colours are assigned automatically (core feature gets the accent).
- `role`, `blurb`, `verdict`, `subtitle` are optional but strongly recommended — they're what a non-reader actually reads.
- `ownershipDims` defaults to the last three dimensions if omitted.
- `methodology` should have one entry per dimension. The script renders it as the closing table; a missing entry shows "—" and is a smell.

## After building

Publish with the Artifact tool (not by pasting HTML into chat), favicon `📊`. Then give the user the 2–3 line shape read-back from the SKILL workflow — don't retype the methodology table.
