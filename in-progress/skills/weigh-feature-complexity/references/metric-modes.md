# Metric modes — where the numbers come from

Three ways to source the scores. Pick per run; you can mix (hybrid) — measure the dimensions a tool covers, estimate the rest. Whatever the source, the methodology column must name it.

## 1. `measure` — run tooling on real code

Use when the code already exists (an open PR, a merged change).

- Cyclomatic: `escomplex` / `typhonjs-escomplex`, or ESLint `complexity`.
- Coupling: `madge --json` or `dependency-cruiser` for the edges/files the feature adds.
- Cognitive: SonarLint/SonarQube if available.
- Connascence + change-amp: no clean tool — inspect the diff (these are always partly judged).

Objective and repeatable, but **PR-time only** — it can't answer a spec-time question because there's nothing to run yet. Attribute shared code to one feature and note it.

## 2. `estimate` — judge from the spec or diff

Use at spec time, or for a fast read when tooling isn't set up.

Score each dimension from the proposed design using the anchors in `dimensions.md`. Always available, no setup. The cost is subjectivity — so **label every number "estimated"** in the methodology and give the one-line reasoning that produced it (which branches you counted, which connascences you enumerated). Never launder an estimate as a measurement.

## 3. `probe-by-implementing` — build it, then measure it

Use when estimates are contested, the stakes are high, and the code doesn't exist yet — the honest way to turn an *estimated* connascence/coupling number into a *measured* one.

**Delegate each feature's implementation to an isolated subagent so the throwaway code never enters the main session's context.** Pattern:

- For each feature (or each variant: baseline / +feature-A / +feature-A+B), spawn a subagent with `isolation: "worktree"` and a tight brief: "implement only this feature against this spec; do not implement the others."
- Instruct the subagent to run the `measure`-mode tools on its own worktree and **return only the numbers** (a small JSON per `dimensions.md`), plus a one-line note per dimension on how it got them.
- The main session ingests just those JSON blobs. It never reads the generated code. The worktrees are disposable.

To get a clean *marginal* number, diff the variants: `score(+A+B) − score(+A)` is B's marginal cost. Run variants as parallel subagents (or a small Workflow pipeline) and subtract.

This is the most expensive mode (it writes real code) and the most defensible. Reserve it for when a feature's inclusion is genuinely in dispute. Say in the methodology that the numbers are measured-from-a-probe, and note that a probe implementation is one point estimate, not the only possible implementation.

## Choosing quickly

| Situation | Mode |
|---|---|
| Reviewing an open/merged PR | `measure` (hybrid with estimate for connascence/change-amp) |
| Discussing a spec, low stakes | `estimate` |
| Discussing a spec, contested feature, high stakes | `probe-by-implementing` |
| No tooling on PATH | `estimate` |
