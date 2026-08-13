# Commit, branch, and report

What main does after the loop exits — on `pass`, on round-cap exhaustion, or on escalation.

## On `pass` or cap exhaustion with only quality findings

Main creates a **single conventional-commits commit** in the worktree on the per-task branch, using the implementer's last `rationale_out` to construct the message. The message must include this trailer (non-standard; tooling can't infer it):

```
Refs: <branch-name>
```

(`<branch-name>` is `$BRANCH` verbatim — the `implement/<timestamp>-<short-ulid>-<slug>` set up in pre-flight.)

If cap-exhausted with outstanding `blocking` or `discrepancy`, append a second trailer:

```
Review-Status: unresolved (<n> blocking, <m> discrepancy)
```

Outstanding `quality_note` does not produce a `Review-Status` trailer — quality findings travel in the report, not in the commit.

## On escalation without reviewable code

Two cases produce **no commit**; the worktree is left dirty for the user to inspect:

- The implementer returned `plan_broken` or `setup_blocked`.
- The final round returned `outcome: "learned"` — the disowned attempt stays in the worktree, uncommitted, and the ledger explains why it was disowned.

## Boundaries

**Do not merge to main. Do not push. Do not remove the worktree. Do not delete the ledger file.** The user's manual merge is the gate.

## Final report

After committing (or immediately, for escalations without a commit), main reports to the user:

- **Worktree path** — `$WORKTREE`.
- **Branch name** — `$BRANCH`.
- **Commit SHA(s)** — for the user to reference.
- **Diff summary** — file count, line additions/deletions, list of changed paths.
- **Learning ledger** — the full contents of `$LEDGER` verbatim (when non-empty), plus its path. This is the durable record of every discarded approach and why it died; on escalation it is the primary deliverable.
- **Round accounting** — rounds spent out of `max_rounds`, and each round's outcome (`implemented`+verdict, `learned`, escalation).
- **Final reviewer findings** — all four reviewers' findings across all field types (`blocking`, `discrepancy`, `quality_note`, `nit`), grouped by reviewer. Outstanding `blocking` and `discrepancy` (if cap-exhausted) are surfaced prominently; `quality_note` and `nit` follow.
- **Implementer `rationale_out`** — the implementer's framing of the problem, the approach chosen, alternatives rejected, scope declared, residual risks accepted, TDD posture. (Absent when the loop ended without an `implemented` round.)
- **Debug archives** — in debug mode, the list of `${BRANCH}/attempt-<r>` tags pointing at discarded attempts.
- **Suggested merge command** — e.g., `gh pr create --base main` from the worktree, or `git checkout main && git merge <branch>` in the parent repo.
- **Degraded-input note** — if codebase recall returned degraded output, surface a one-line warning.

Escalations (cap-exhausted with outstanding findings, final-round `learned`, `plan_broken`, `setup_blocked`) use the same report shape, surfaced immediately — they do **not** wait for merge time. When the escalation stems from an unlicensed novel architectural decision, lead the report with the decision the user must make and the options, quoted from the `plan_broken` evidence or the Questioner's learning.
