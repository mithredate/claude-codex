# Worked example — one fix, three rounds: reset, then patch, then pass

A narrative walkthrough of a typical run under the graded-response loop: round 1 ends in a design failure and a reset, round 2 re-derives from the ledger and needs one surgical patch, round 3 passes. No code, no JSON — those live in the briefs. This file is here so a reader can see how the pieces interact.

## The request

The user reports that an authenticated user's session occasionally expires earlier than the configured TTL, and invokes `/implement-with-review-loop` (no args — cap defaults to 3 rounds, debug off).

## Pre-flight

Main captures the verbatim request, captures `base_sha`, creates a worktree on `implement/<timestamp>-<short-ulid>-session-expiry-fix`, creates the empty ledger file next to the worktree, and verifies `.claude/` is in `.gitignore`.

## Recall

The recall agent runs once. It returns a digest pointing at the session module, the test directory for it, the project's lint/test/typecheck commands from `CLAUDE.md`, and a note that two sibling modules already use a "refresh on activity" pattern. The digest describes the codebase at `base_sha`, so it stays valid across every later reset.

## Round 1 (fresh mode, empty ledger)

### Implementer

Reads the recall digest and the relevant files. Diagnoses the root cause as a TTL comparison that uses wall-clock time on the client rather than the server's authoritative timestamp — so clients with skewed clocks see early expiry. Writes a test that reproduces the early-expiry behavior, fixes the comparison to use the server timestamp, and returns `outcome: "implemented"` with a populated `rationale_out` and no learnings of its own.

### Reviewers (in parallel, stateless)

- **Validator** — re-runs test, lint, and typecheck commands in the worktree. All exit zero. Empty output across all arrays.
- **Codebase Auditor** — sweeps call sites of the changed symbol. Two downstream consumers (a UI banner that warns about expiry, and a background job that pre-refreshes near-expiry sessions) still rely on the client-side comparison. Raises `blocking` on each unchanged consumer with `file:line` evidence, and restates them in `learnings` as: "session-expiry information is consumed in at least three places (validation, warning banner, pre-refresh job); any fix must cover all consumers, not just the validator path."
- **Questioner** — steelmans the rejected alternative ("extend TTL") and agrees it was rightly rejected. But the deeper issue: the *real* root cause is that the system trusts client time anywhere at all. Fixing one comparison leaves the bug class alive. Raises `discrepancy` with surrounding-code evidence, and writes the learning: "any approach that trusts client-side wall-clock time anywhere in session-expiry paths recreates this bug; the server timestamp is the only authoritative time source."
- **Craft Reviewer** — the new test reads cleanly. No findings.

### Verdict and reset

Main appends the two reviewer learnings to the ledger (entries 1–2), then computes the verdict: `discrepancy` present → **reset-adjust** (rounds remain). `discrepancy` outranks the auditor's `blocking` — patching the consumers into a design that still trusts client time would be wasted work. Main runs `git reset --hard base_sha && git clean -fd` in the worktree. Round 1's code is gone; entries 1–2 are what survive. (In debug mode, the attempt would first have been committed and tagged `implement/<…>/attempt-1`.)

## Round 2 (fresh mode, ledger has 2 entries)

### Implementer

A fresh spawn. Reads the ledger before choosing an approach: client time is off the table everywhere, and there are three consumer sites. Derives a different design — a single server-time expiry resolver that all three sites call — implements it, updates the three sites, and writes tests covering the consumer paths. Returns `outcome: "implemented"`, plus one learning of its own from a mid-round pivot: "the pre-refresh job caches session records; any expiry fix must invalidate that cache or read through it." It handled the cache in its own diff, but the constraint is worth keeping.

### Reviewers (stateless — no memory of round 1, no ledger)

- **Validator** — all commands exit zero. Clean.
- **Codebase Auditor** — no client-time comparisons remain; consumers all route through the resolver. One `blocking`: the background job passes the session record to the resolver but ignores the resolver's error case, so a resolver failure silently skips pre-refresh — cites the `file:line`. No learning (a local defect with no design-level constraint beyond what the fix itself shows).
- **Questioner** — the bug class is gone; the framing holds. No findings.
- **Craft Reviewer** — resolver is a deep module with a narrow interface. No findings.

### Verdict

Main appends the implementer's learning (entry 3). Occupancy: one `blocking`, no `discrepancy` → **patch-adjust**. The design survived; the code stays.

## Round 3 (patch mode)

The implementer spawn receives the round-2 findings and the ledger. Inspects the cumulative diff, adds error handling for the resolver's failure case in the background job, extends the job's test. Returns `outcome: "implemented"`. All four reviewers come back clean. Verdict: **pass**.

## Exit

Main commits in the worktree on the per-task branch, using the round-3 `rationale_out` for the commit message, with the `Refs:` trailer. Reports: worktree path, branch, commit SHA, diff summary, the full ledger (3 entries), round accounting (3 of 3 spent: reset, patch-adjust, pass), the final reviewer findings (all empty), the implementer's final `rationale_out`, and a suggested merge command. The user is the merge gate.

## What the example illustrates

- **Graded response is the core mechanic.** Round 1's `discrepancy` discarded the code entirely; round 2's `blocking` kept the code and patched one site. Reset for design failures, patch for local defects — chosen by field occupancy, never by main's judgment.
- **The ledger is the only bridge across a reset.** Round 2's implementer never saw round 1's code. It avoided the dead approach purely because entries 1–2 stated the constraints design-level and code-independent. A `file:line` finding would have pointed at nothing.
- **`learned` would have been the other path.** If round 2's implementer had discovered mid-round that the resolver design collides with entry 1, it could have pivoted freely, or returned `outcome: "learned"` — skipping review, spending the round, and resetting. Both outcomes are wins; only pushing code it didn't believe in would have been a failure.
- **Reviewers are stateless across rounds.** Round 2's Questioner had no memory of round 1 and no ledger. The clean verdict came from the new diff meeting the bar on its own, not from "the implementer already addressed it."
- **The cap counts implementer spawns.** Three rounds were spent — one on a discarded attempt. That is the design working: the discarded attempt bought entries 1–2, which are why round 2 was right on the first derivation.
