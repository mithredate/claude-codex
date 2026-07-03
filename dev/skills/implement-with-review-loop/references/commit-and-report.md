# Commit, branch, and report

What main does after the loop exits — on pass, on round-2 exit with open findings, or on escape hatch.

## On pass or round-2 exit

Main creates a **single conventional-commits commit** in the worktree on the per-task branch, using the implementer's last `rationale_out` to construct the message. The message must include this trailer (non-standard; tooling can't infer it):

```
Refs: <branch-name>
```

(`<branch-name>` is `$BRANCH` verbatim — the `implement/<timestamp>-<short-ulid>-<slug>` set up in pre-flight.)

If the loop exited round 2 with open `fix` findings, append a second trailer:

```
Review-Status: unresolved (<n> fix)
```

`fyi` findings never produce a trailer — they travel in the report only.

## On escape hatch

When the implementer returned `status: "plan_broken"` or `"setup_blocked"`, **no commit is produced**. The worktree is left dirty for the user to inspect.

## Boundaries

**Do not merge to main. Do not push. Do not remove the worktree.** The user's manual merge is the gate.

## Final report

After committing (or immediately, for escape hatches), main reports to the user:

- **Unresolved — triage before merge** — if any `fix` findings remain open after round 2, this list comes **first**, formatted as a checklist the user works through before merging. Each item carries its `file:line` evidence and which source raised it (mechanical / correctness_fit / craft_economy).
- **Worktree path** — `$WORKTREE`.
- **Branch name** — `$BRANCH`.
- **Commit SHA(s)** — for the user to reference.
- **Diff summary** — file count, line additions/deletions, list of changed paths.
- **Final findings** — the last round's `fyi` items (and resolved `fix` items summarized in one line, e.g. "round 1 raised 4 fix findings; all resolved in round 2"), grouped by source.
- **Implementer `rationale_out`** — problem understanding, approach chosen, scope declared, new surface justified, residual risks accepted.
- **Suggested merge command** — e.g., `gh pr create --base main` from the worktree, or `git checkout main && git merge <branch>` in the parent repo.
- **Degraded-reviewer note** — if a reviewer's output was malformed twice and its findings were treated as empty, surface a one-line warning naming the reviewer.

Escalations (`plan_broken`, `setup_blocked`) use the same report shape, surfaced immediately — they do **not** wait for merge time.
