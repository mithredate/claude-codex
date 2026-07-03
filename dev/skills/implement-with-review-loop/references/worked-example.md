# Worked example — one fix, one fix round

A narrative walkthrough of a typical round-1-findings → fix-round → pass run. No code, no JSON — those live in the briefs. This file is here so a reader can see how the pieces interact.

## The request

The user reports that an authenticated user's session occasionally expires earlier than the configured TTL, and invokes the skill to implement the fix.

## Pre-flight

Main captures the verbatim request, captures `base_sha`, creates a worktree on `implement/<timestamp>-<short-ulid>-session-expiry-fix`, and — since `.claude/` is not in this repo's `.gitignore` — silently appends it to `.git/info/exclude`.

## Round 1

### Implementer

Orients itself in the session module and its tests. Diagnoses the root cause as a TTL comparison that uses wall-clock time on the client rather than the server's authoritative timestamp — so clients with skewed clocks see early expiry. Writes a test that reproduces the early-expiry behavior, fixes the comparison to use the server timestamp, runs the project's test/lint/typecheck commands, and returns `complete` with a populated `rationale_out` (problem understanding, root cause, approach, scope, no new surface, residual risks).

### Mechanical checks (main, no agent)

Main re-runs the test, lint, and typecheck commands in the worktree — all exit zero. The diff stays within `scope_declared`, no manifests changed, no debug prints or new TODOs. No mechanical findings.

### Reviewers (in parallel)

- **Correctness & Fit** — checks the fixed comparison against the rest of the repo. Finds two downstream consumers that still rely on the client-side comparison: a UI banner that warns about upcoming expiry, and a background job that pre-refreshes near-expiry sessions. Both will keep misbehaving. Raises two `fix` findings citing the unchanged consumers' `file:line`.
- **Craft & Economy** — walks the diff asking what it would delete. The implementer added a `clockSkewToleranceMs` option to the session config, defaulted and never varied — config for a constant, and absent from `new_surface_justified`. Raises one `fix` finding. The test itself reads cleanly; one naming taste comment goes to `fyi`.

### Verdict

Three `fix` findings across the two reviewers. Verdict: **fix round**.

## Round 2 — fix round

### Fix implementer

Receives the aggregated findings, round 1's `rationale_out`, and the fix directive. Inspects the cumulative diff first. Updates the two consumers to read the server timestamp (extending the test to cover both paths), and deletes the `clockSkewToleranceMs` option in favor of the plain comparison. The diff shrinks. `fyi` naming comment: skipped — optional. Returns `complete` with updated `rationale_out`.

### Mechanical checks + re-review

Commands pass. Both reviewers re-run stateless against the cumulative diff:

- **Correctness & Fit** — searches for remaining client-time comparisons in session-expiry paths. None remain; the consumers and the test cover the changed behavior. Empty `fix`.
- **Craft & Economy** — nothing left to delete; the code reads cleanly. Empty `fix`; re-raises the same naming comment as `fyi`.

### Verdict

No `fix` findings. Verdict: **pass**.

## Exit

Main commits in the worktree on the per-task branch, using the round-2 `rationale_out` for the commit message, with the `Refs:` trailer. Reports to the user: worktree path, branch, commit SHA, diff summary, the resolved-findings one-liner, the surviving `fyi` item, the implementer's final `rationale_out`, and a suggested merge command. The user is the merge gate.

## What the example illustrates

- **Everything evidence-backed gates, once.** The speculative config option was a craft-tier concern that the old four-tier design would have parked in a discardable `quality_note`; here it is a `fix` finding and it actually gets removed. The `fyi` naming comment, by contrast, never forces a round — it reaches the user in the report and dies there only if the user agrees it should.
- **Economy has an owner.** The diff got *smaller* in the fix round. No reviewer in the old design was briefed to make that happen.
- **The loop never runs a third round.** Had Correctness & Fit found a genuinely new problem in round 2, the loop would still have committed and handed it over as "unresolved — triage before merge" — two non-converging passes are the signal that a human judgment call is cheaper than a third spawn cycle.
- **Reviewers are stateless across rounds.** Round 2's reviewers had no memory of round 1. The clean verdict came from the cumulative diff itself meeting the bar, not from "the implementer said they addressed it."
