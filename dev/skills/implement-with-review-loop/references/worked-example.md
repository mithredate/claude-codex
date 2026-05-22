# Worked example — one fix, two rounds

A narrative walkthrough of a typical round-1-adjust → round-2-pass run. No code, no JSON — those live in the briefs. This file is here so a reader can see how the pieces interact.

## The request

The user reports that an authenticated user's session occasionally expires earlier than the configured TTL. The user has already approved a plan to fix it and asks for implementation.

## Pre-flight

Main captures the verbatim request, captures `base_sha`, creates a worktree on `implement/<timestamp>-<short-ulid>-session-expiry-fix`, and verifies `.claude/` is in `.gitignore`.

## Recall

The recall agent runs once. It returns a digest pointing at the session module, the test directory for it, the project's lint/test/typecheck commands from `CLAUDE.md`, and a note that two sibling modules already use a "refresh on activity" pattern.

## Round 1

### Implementer

Reads the recall digest and the relevant files. Diagnoses the root cause as a TTL comparison that uses wall-clock time on the client rather than the server's authoritative timestamp — so clients with skewed clocks see early expiry. Writes a test that reproduces the early-expiry behavior, fixes the comparison to use the server timestamp, and reports the change with a populated `rationale_out` (problem understanding, root cause, approach, rejected alternatives including "extend TTL", scope, residual risks).

### Reviewers (in parallel)

- **Validator** — re-runs test, lint, and typecheck commands in the worktree. All exit zero. No commented-out code, no debug prints, no scope escape. Output is empty across all four arrays.
- **Codebase Auditor** — checks the new code against the sibling modules. Notes that the fixed module now reads the server timestamp, but two downstream consumers (a UI banner that warns about expiry, and a background job that pre-refreshes near-expiry sessions) still rely on the client-side comparison. Both will continue to misbehave. Raises `blocking` on the unchanged consumers, with `file:line` evidence for each.
- **Questioner** — reads `rationale_out` against the diff. Steelmans the rejected alternative ("extend TTL") and concludes the implementer correctly rejected it. But then notes a deeper issue: the *real* root cause is that the system trusts client time anywhere at all. The diff fixes one comparison; the same client-time pattern recurs in the two consumers the Codebase Auditor flagged, and the comparison fix at one site without a broader cleanup leaves the bug class alive. Raises `discrepancy` citing the surrounding-code evidence — re-coding to the same plan will paper over the symptom while the pattern persists.
- **Craft Reviewer** — reads the new test as if inheriting it. Notes the test name is descriptive, the arrange/act/assert is clear. No findings.

### Verdict

Main computes the verdict from field occupancy. `discrepancy` is present (Questioner). Priority gating selects `discrepancy` over the Codebase Auditor's `blocking`. Verdict: **adjust**.

## Round 2

### Implementer (surgical-fix mode)

Receives the aggregated findings and the surgical-fix directive. Inspects the current worktree diff. The discrepancy asks for a broader re-frame: stop trusting client time anywhere it touches expiry. The implementer extracts a shared "session-expiry resolver" helper that reads the server timestamp, updates the three sites (the original fix plus the two consumers the auditor flagged), and updates the test to cover the consumer paths too. Returns an updated `rationale_out` with the new framing — the root cause is now "client-time comparison pattern in session-expiry code paths," not "one comparison in one function."

### Reviewers (stateless, no awareness of round 2)

- **Validator** — re-runs the commands. Pass.
- **Codebase Auditor** — searches for remaining client-time comparisons in session-expiry paths. None remain. No findings.
- **Questioner** — steelmans the alternatives against the new diff. The bug class is gone. No findings.
- **Craft Reviewer** — reads the new helper. Single responsibility, clean naming, the tests read as small stories. No findings.

### Verdict

All four arrays empty across all four reviewers. Verdict: **pass**.

## Exit

Main commits in the worktree on the per-task branch, using the round-2 `rationale_out` for the commit message. Includes the `Refs:` trailer. Reports to the user: worktree path, branch, commit SHA, diff summary, the full reviewer findings (round 2 — all empty), the implementer's final `rationale_out`, and a suggested merge command. The user is the merge gate.

## What the example illustrates

- **Role boundaries are load-bearing.** Both the Codebase Auditor and the Questioner saw the consumer-misbehavior evidence. The Codebase Auditor raised it as `blocking` (a defect in the implementer's coverage of the diff). The Questioner saw the same evidence and raised it as `discrepancy` (a defect in the framing). Priority gating ensures the `discrepancy` drives the next round — re-coding to fix the consumers alone would still leave the bug class alive.
- **Reviewers are stateless across rounds.** Round 2's Questioner had no memory of round 1. The clean verdict in round 2 came from the diff itself meeting the bar, not from "the implementer already addressed it."
- **Quality findings would have forced a round 3.** If round 2's Craft Reviewer had raised a `quality_note` about, say, a slightly verbose helper name — with no `blocking` or `discrepancy` anywhere else — the verdict would have been `adjust`, not `pass`, because rounds remain. Only when the 3-round cap is reached does a lone `quality_note` `pass`. The cap protects correctness iteration without letting quality findings starve the budget.
