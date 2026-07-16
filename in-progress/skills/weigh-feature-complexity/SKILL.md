---
name: weigh-feature-complexity
description: >-
  Break a spec or PR into individual features and visualize the complexity each one adds, so you can decide whether a feature earns its cost before signing off. Produces an interactive dashboard (toggle features on/off, radar, waterfall, heatmap) scored on five complexity dimensions, with a methodology section stating how every number was derived. Use when reviewing a spec or PR, discussing implementation trade-offs, deciding what to cut, or when the user asks about "complexity", "maintainability", "is this feature worth it", "what does dropping X buy me", or "before/after" per feature. Do NOT use for raw line-count/LOC questions — this measures complexity, not size.
---

# Weigh Feature Complexity

Decide, per feature, whether it earns its complexity cost — and show it visually, because the audience is reviewing a spec and does not want to read prose.

The unit is the **feature**, not the PR and not the file. A feature is a coherent capability that could ship or be cut on its own (e.g. "the blocking gate" vs "the checklist autofill" inside one PR). One PR usually contains several.

## Workflow

Run these phases in order. Do not skip the confirmation gate in phase 1 or the methodology recording in phase 3.

1. **Decompose → confirm.** Read the spec/PR/diff. Propose a feature split — each with a one-line description and which files/sections it spans. **Present it and let the user correct the boundaries before scoring.** A wrong split invalidates every number downstream.
2. **Pick a metric mode.** Choose how the numbers are sourced: `measure`, `estimate`, or `probe-by-implementing`. See [references/metric-modes.md](references/metric-modes.md). Ask the user if the mode isn't obvious from context (spec time → estimate/probe; existing PR → measure/hybrid).
3. **Score each feature × 5 dimensions** (Cyclomatic, Cognitive, Coupling, Connascence, Change-amplification), as a **0–10 marginal** score — the complexity that feature *adds*, not the codebase's absolute complexity. Rubric and anchors: [references/dimensions.md](references/dimensions.md). **For every score, record what it means and exactly how you derived it this run** — that text becomes the dashboard's methodology table. No un-sourced numbers.
4. **Build the dashboard.** Write the scorecard JSON (contract in [references/dashboard.md](references/dashboard.md)), run the build script, then publish with the Artifact tool:
   ```bash
   node scripts/build-dashboard.mjs --data /path/scorecard.json --out /path/dashboard.html
   ```
5. **Read the shapes back** in 2–3 lines. Name the trade-off the picture reveals (e.g. "the gate is a deep module — spiky on cyclomatic only; the autofill is shallow-and-wide — spiky on coupling/connascence/change-amp, the ownership-cost cluster"). Do not restate the table.

## Guardrails

- **Marginal, not absolute.** Every score is the delta this feature introduces. If two features share code, attribute it to the one that *needs* it and say so in the methodology.
- **Complexity ≠ size.** If the diff is dominated by reindentation/formatting churn, exclude it and say so. LOC is not a dimension here.
- **Estimates are labelled estimates.** In `estimate` mode, the methodology column says "estimated" and gives the reasoning; never present a guess as measured.
- **Keep the churn out of context.** In `probe-by-implementing` mode, delegate each build to an isolated subagent and ingest only the reported numbers — never pull the throwaway implementations into the main session.
- **The dashboard is the deliverable.** Prefer publishing the artifact over writing a wall of text; the whole point is that people don't read.

## Concrete example

A worked scorecard (the Atlas PR #137 "gate vs autofill" case) is in [references/dashboard.md](references/dashboard.md) — copy its JSON shape.
