# Commit, branch, and report

What main does after the loop exits — on `pass`, on 3-round cap exhaustion, or on escape hatch.

## On `pass` or 3-round cap

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

## On escape hatch

When the implementer returned `status: "plan_broken"` or `"setup_blocked"`, **no commit is produced**. The worktree is left dirty for the user to inspect.

## Boundaries

**Do not merge to main. Do not push. Do not remove the worktree.** The user's manual merge is the gate.

## Final report

After committing (or immediately, for escape hatches), main reports to the user:

- **Worktree path** — `$WORKTREE`.
- **Branch name** — `$BRANCH`.
- **Commit SHA(s)** — for the user to reference.
- **Diff summary** — file count, line additions/deletions, list of changed paths.
- **Final reviewer findings** — all four reviewers' findings across all four field types (`blocking`, `discrepancy`, `quality_note`, `nit`), grouped by reviewer. Outstanding `blocking` and `discrepancy` (if cap-exhausted) are surfaced prominently; `quality_note` and `nit` follow.
- **Implementer `rationale_out`** — the implementer's framing of the problem, the approach chosen, alternatives rejected, scope declared, residual risks accepted, TDD posture.
- **Suggested merge command** — e.g., `gh pr create --base main` from the worktree, or `git checkout main && git merge <branch>` in the parent repo.
- **Degraded-input note** — if codebase recall returned degraded output, surface a one-line warning.

Escalations (cap-exhausted with outstanding findings, `plan_broken`, `setup_blocked`) use the same report shape, surfaced immediately — they do **not** wait for merge time.
