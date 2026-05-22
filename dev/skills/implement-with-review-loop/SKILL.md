---
name: implement-with-review-loop
description: >-
  Implement code changes — fixes, features, refactors, or substantive chores — under a worktree-isolated implement-then-review loop. Trigger when the user has approved a plan and asked for implementation, or uses phrases like "implement X", "add feature Y", "fix bug Z", "refactor M", "build out the auth flow". Use this skill even when the user does not explicitly ask for review — review is the default for substantive changes. Do NOT trigger for read-only tasks (analysis, exploration, summarization) or trivial one-line edits the user explicitly asks to apply directly.
---

# Implement with review loop

Deliver a code change through a worktree-isolated implementer subagent and four parallel reviewers, with a hard iteration cap and a branch-and-report exit (no auto-merge). Read this whole file before spawning the first subagent.

## Shape at a glance

- A **per-task git worktree** is mandatory. Main creates it; the implementer writes inside it. Main does not edit code outside the worktree. This is a filesystem boundary that physically prevents main from bypassing the implementer.
- A **one-shot codebase recall** (pointers, not content) runs before round 1 and is passed verbatim to every implementer spawn.
- Each round = one **implementer spawn** followed by **four reviewers in parallel** (Validator, Codebase Auditor, Questioner, Craft Reviewer).
- The **verdict is mechanical** — main computes it from field occupancy across the four reviewer JSONs. Reviewers do not vote.
- On `pass` or 3-fail cap or escape hatch, the implementer **commits inside the worktree on the per-task branch and stops**. Main reports to the user; **the user's manual merge is the gate**.

## What the references contain

Sub-agents do not inherit the skill directory automatically. Briefs pass these paths explicitly.

- `references/validator-brief.md` — mechanical compliance reviewer; spawn as `Explore`.
- `references/codebase-auditor-brief.md` — fit-with-surrounding-code reviewer; spawn as `general-purpose`.
- `references/questioner-brief.md` — framing-and-decision reviewer; spawn as `general-purpose`. Sole authority over `discrepancy`.
- `references/craft-reviewer-brief.md` — code-craft-on-its-own-terms reviewer; spawn as `general-purpose`.

## Pre-flight

Before spawning anything:

1. Confirm the user's request is in scope (substantive code change; not read-only; not a one-line edit they asked to apply directly). If ambiguous, stop and ask.
2. Capture `base_sha = git rev-parse HEAD` in the parent repo. This is the diff-invariant anchor.
3. Capture the `user_request` **verbatim**. Do not paraphrase. If the user dictated scope, acceptance criteria, a chosen approach, or a root-cause hypothesis, that dictation lives inside `user_request` and the implementer reads it from there.
4. Create the per-task worktree on a fresh branch:

   ```
   WORKTREE="<repo_root>/.claude/worktrees/implement-<YYYYMMDD-HHMMSS>-<short-ulid>-<slug>"
   BRANCH="implement/<YYYYMMDD-HHMMSS>-<short-ulid>-<slug>"
   git -C "<repo_root>" worktree add -b "$BRANCH" "$WORKTREE" "$base_sha"
   ```

   `<slug>` is a short kebab-case label main proposes from `user_request`. `<short-ulid>` is the first 6 characters of a freshly-generated ULID, to break ties on same-second concurrent invocations.

5. **`.claude/` gitignore precondition.** The repo must have `.claude/` in `.gitignore` so worktree contents do not appear as untracked files in the live clone. If absent, stop and ask the user to add it (`echo '.claude/' >> .gitignore`, commit, re-invoke).

All subsequent reads, writes, `git diff`, `git add`, and `git commit` happen **inside the worktree** — never in the parent repo directly. All `git diff` calls use the **single-ref** form `git diff <base_sha>` (run with `git -C "$WORKTREE" diff "$base_sha"`) — committed, staged, and unstaged changes since base. This is the diff invariant; reviewers always see the cumulative change, never the per-round delta.

## Worker brief contract — what main passes the implementer

Main passes **raw context plus infrastructure**, not pre-chewed decisions. Specifically:

- `user_request` — verbatim user phrasing. No paraphrase.
- `codebase_recall` — the digest from the recall step below; pointers only.
- `workspace` — `$WORKTREE`.
- `base_sha` — for the diff invariant.
- Paths to relevant references the user supplied or that the repo's CLAUDE.md points at.

Main does **not** pass: `rationale`, `scope`, `acceptance_criteria`, `chosen approach`, `rejected alternatives`, `root cause hypothesis`. These are the implementer's job to derive. If the user dictated any of them, the dictation is inside `user_request` and the implementer picks it up there.

The implementer is also told to **read the repo's CLAUDE.md** for test/lint/typecheck commands, TDD posture, and project conventions. This skill says nothing about TDD specifically — TDD posture is a project-level concern the implementer reads from CLAUDE.md.

## Codebase recall — one-shot, pointers only

Before round 1, spawn a single **recall sub-agent** as `Explore` (read-only, fast, pattern-matching). The recall agent returns a tight digest (≤25 lines) of:

- `relevant_paths` — file paths likely to matter, each with a one-line "why" annotation.
- `conventions` — test command, lint command, typecheck command (read from CLAUDE.md), plus style notes the agent observed.
- `search_hints` — additional pointers (e.g., "auth symbol appears in 14 files; most relevant cluster is `lib/auth/`").

**Pointers, not content.** The digest is a search-index hint, not a knowledge dump. The implementer Reads files itself on demand. The recall runs **once** and the same digest is passed to every implementer spawn (round 1 and every retry). Set of relevant files does not change between rounds; re-running would waste tokens.

**Silent-failure mode.** If the recall sub-agent returns nothing or content that does not contain at least one digest-shaped line, set `codebase_recall` to an empty digest and proceed. Surface the degradation in the final report. Do not re-spawn within the same session.

## Per-round loop (hard cap: 3 rounds)

Each round = one implementer spawn followed by four parallel reviewer spawns. Reviewers are **stateless every round** — re-derived from scratch against the current `git diff <base_sha>`, never told which round it is. Carrying state would bias reviewers toward confirming a prior verdict and would let regressions in previously-clean regions slip through.

### A. Implementer subagent (round 1 and every retry)

Spawn one implementer (`general-purpose`) with:

- **Round-1 inputs (always — same every round):**
  - `user_request`, `codebase_recall`, `workspace = $WORKTREE`, `base_sha`, references the user supplied.
  - Instruction to read the repo's `CLAUDE.md` for test/lint/typecheck commands and TDD posture.

- **Round-N>1 inputs (additions, not substitutions):**
  - The previous full cumulative diff (`git diff <base_sha>` at the end of the prior round).
  - The aggregated reviewer findings JSON from the prior round.
  - **Surgical-fix mode directive (verbatim):**

    > Surgical fix mode — you operate on the same worktree across retries. The prior diff is shown to you as context for what is already in place, not as a patch to apply. Address every `blocking` and `discrepancy` item from the verdict without regressing unchanged regions. Do not rewrite working code or expand scope. If you believe a finding requires a larger restructure than the prior approach supports, return `plan_broken` with evidence rather than silently expanding.

- **Boundaries:**
  - All writes happen inside `$WORKTREE`. Touching anything outside the worktree is a violation that the Validator will catch.
  - Do not add new runtime dependencies without flagging in `residual_risks_accepted`.

- **Escape hatch — `plan_broken` / `setup_blocked`.** If the implementer discovers the plan itself is wrong (the approach won't compile, the root-cause diagnosis is incorrect, a hidden constraint contradicts the approach, the failing test it writes does not actually fail), it returns `status: "plan_broken"` with evidence. If the test harness cannot exercise the relevant module in isolation despite reasonable effort, it returns `status: "setup_blocked"` rather than mocking the world. **Do not iterate** when the implementer returns either code — escalate to the user with the evidence.

- **Required output schema:**

  ```json
  {
    "status": "complete" | "plan_broken" | "setup_blocked",
    "diff": "<output of `git -C $WORKTREE diff <base_sha>` — full cumulative change; empty if status != complete>",
    "new_or_modified_tests": ["<test identifier in the runner's format>", "..."],
    "commands_run": ["<test cmd>", "<lint cmd>", "<typecheck cmd>"],
    "rationale_out": {
      "problem_understanding": "<what the worker took the problem to be>",
      "root_cause":            "<for fixes; 'n/a' for features/chores>",
      "approach_chosen":       "<one paragraph>",
      "alternatives_rejected": [{"alternative": "...", "reason": "..."}, "..."],
      "scope_declared":        ["<file path>", "..."],
      "residual_risks_accepted": ["...", "..."],
      "tdd_applied":           {"applied": true, "justification": "<brief>"}
    },
    "blocker_evidence": "<only when status != complete: what you tried, what failed, why it shows the plan/setup is broken>"
  }
  ```

`scope_declared` feeds the Validator (it checks the diff stays within this allow-list). The rest of `rationale_out` feeds the Questioner.

### B. Reviewer fan-out (every round)

Spawn four reviewers in parallel against the current state of `git -C $WORKTREE diff $base_sha`. Each is stateless; no awareness of round number.

- **Validator** (`Explore`) — brief: `references/validator-brief.md`.
- **Codebase Auditor** (`general-purpose`) — brief: `references/codebase-auditor-brief.md`.
- **Questioner** (`general-purpose`) — brief: `references/questioner-brief.md`. Receives `rationale_out` in full.
- **Craft Reviewer** (`general-purpose`) — brief: `references/craft-reviewer-brief.md`.

Each reviewer receives:

- `base_sha`
- `workspace = $WORKTREE`
- Paths to the repo's `CLAUDE.md` and any references the user supplied
- For the Questioner: the full `rationale_out` block from the implementer
- For the Validator: `scope_declared` from `rationale_out` (the diff allow-list)

Reviewers return strict JSON. The field schema is **fixed at four arrays across all four reviewers**; some reviewers fill only a subset (the rest are empty arrays):

- `blocking` — concrete defect in the diff with `file:line` evidence. **Any reviewer may populate.** Forces another round.
- `discrepancy` — structural problem requiring re-think (right problem? right root cause? right approach vs the rejected alternatives?). **Questioner only.** Forces another round.
- `quality_note` — advisory; never gates. Codebase Auditor, Questioner, Craft Reviewer may populate.
- `nit` — minor; never gates. Any reviewer may populate.

Reviewers do **not** vote: any `status` or `verdict` field they emit is treated as ignored courtesy. Main computes the loop verdict from field occupancy.

### C. Verdict aggregation (mechanical — main applies, reviewers never vote)

After collecting all four reviewer JSON outputs, apply this rule **in order**:

1. **Malformed JSON** — if any reviewer's output is malformed (missing required field, wrong type, non-parseable), re-spawn that reviewer once with the same brief plus a stricter "your previous output was malformed; conform to the schema" preamble. If the second attempt is still malformed, **escalate to the user**. Verdict-validation re-spawns do not count against the 3-round cap. Do not re-spawn the implementer on a reviewer-validation failure — the reviewer is the broken component.

2. Once all four outputs are valid, compute the verdict from field occupancy:
   - Any `blocking` finding (from any reviewer) → **adjust** if rounds remain, else **escalate**.
   - Any `discrepancy` finding (Questioner only) → **adjust** if rounds remain, else **escalate**.
   - Only `quality_note` and/or `nit` findings, or no findings at all → **pass** → exit loop and proceed to commit.

### D. Iterate

- **pass** → commit and report (next section).
- **adjust** → spawn a fresh implementer (step A) with round-N>1 inputs (including the aggregated findings and the surgical-fix directive). Then spawn the four reviewers in parallel (identical brief — no awareness of round number).
- **escalate** → exit the loop. Commit current state in the worktree with a `Review-Status` trailer (see next section) and report to the user with un-addressed findings labeled. The user decides next steps.
- **Hard cap: 3 `adjust` rounds.** After round 3, exit the loop regardless of verdict. If outstanding `blocking` or `discrepancy` remain, this is the `escalate` branch.

## Commit, branch, and report

When the loop converges (`pass` verdict OR 3-round cap exhausted OR escape hatch from worker), the implementer commits **inside the worktree** on the per-task branch. Single commit per task:

```
cd "$WORKTREE"
git add -A
git commit -m "<message below>"
```

Commit message structure (conventional commits — blank lines between subject, body, and trailers are required for `git interpret-trailers` and downstream tooling to parse correctly):

```
<type>(<scope-short>): <one-line summary>

- <bullet of change>
- <bullet of change>

Refs: implement-<YYYYMMDD-HHMMSS>-<short-ulid>-<slug>
```

`<type>` is inferred from `user_request` and the diff: `fix`, `feat`, `refactor`, `chore`, `docs`, `test`. If cap-exhausted with outstanding findings, append a trailer block (preceded by a blank line):

```
Review-Status: unresolved (<n> blocking, <m> discrepancy)
```

The commit lands on the `implement/<timestamp>-<short-ulid>-<slug>` branch only. **Do not merge to main. Do not push. Do not remove the worktree.** The user's manual merge is the gate.

After committing, main **reports to the user**:

- **Worktree path** — `$WORKTREE`.
- **Branch name** — `$BRANCH`.
- **Commit SHA(s)** — for the user to reference.
- **Diff summary** — file count, line additions/deletions, list of changed paths.
- **Final reviewer verdicts** — the four reviewers' findings, summarised. Outstanding `blocking` and `discrepancy` (if cap-exhausted) are surfaced prominently.
- **Worker `rationale_out`** — the worker's framing of the problem, the approach chosen, alternatives rejected, scope declared, residual risks accepted, TDD posture.
- **Suggested merge command** — e.g., `gh pr create --base main` from the worktree, or `git checkout main && git merge <branch>` in the parent repo.
- **Degraded-input note** — if codebase recall returned degraded output, surface a one-line warning.

Mid-loop escalations (Questioner `discrepancy` that exhausts the cap, `plan_broken`, `setup_blocked`) surface to the user immediately with the same report shape — they do **not** wait for merge time. For `plan_broken` / `setup_blocked`, no commit is produced (the diff may be empty or partial); the worktree is left dirty for the user to inspect.

## Escape hatches and edge cases

- **`plan_broken` from worker.** Exit loop. Surface to user with the agent's evidence; worktree left dirty (no commit). The worker cannot fix a broken plan by retrying.
- **`setup_blocked` from worker.** Exit loop. Surface to user with the agent's evidence; worktree left dirty (no commit). The test harness cannot be made to exercise the relevant module in isolation.
- **Malformed reviewer JSON.** Re-spawn that reviewer once; escalate to user on second malformed output. Does not count against the 3-round cap. Do not re-spawn the implementer — the reviewer is the broken component.
- **3-round cap exhaustion with outstanding `blocking` or `discrepancy`.** Commit anyway with the `Review-Status` trailer; report to user with findings labeled. The user decides whether to merge, iterate further (by re-invoking), or take over manually.
- **User-supplied dictation in `user_request`.** Passed through verbatim. The implementer reads it and treats it as part of its inputs. Main does not pre-digest it.
- **Implementer writes outside `$WORKTREE`.** The Validator catches this as `blocking`. Main does not enforce it directly — the filesystem boundary plus the Validator's check together form the guarantee.
- **Codebase recall returns malformed/empty/errored output.** Set `codebase_recall` to empty and proceed; surface the degradation in the final report. Do not re-spawn inside the same session.

## Borrowed disciplines (inline reference)

From `productivity/skills/capture-decision/` — the following patterns transfer verbatim in spirit, adapted for the code-change domain:

- **Pre-flight clean-tree check via dedicated worktree.** All in-flight changes live in a per-task worktree off `base_sha`. The parent repo's working tree is never touched. Discard = `git worktree remove --force`.
- **Single-ref diff invariant.** `git diff <base_sha>` only. Never the per-round delta. Reviewers always evaluate the cumulative change.
- **Stateless reviewers.** Each reviewer spawn re-derives the verdict from scratch. No awareness of round number. Prevents drift and prevents regressions in previously-clean regions from slipping through.
- **Mechanical verdict aggregation.** Reviewers do not vote. Main computes the loop verdict from field occupancy across all four reviewer JSONs.
- **Verdict validation.** Re-spawn once on malformed reviewer JSON; escalate on second failure. The reviewer is the broken component, not the change.
- **Hard cap with escalation, branch-and-report exit.** Three rounds. Cap exhaustion is not failure — it routes to the user with the current state preserved on disk in the worktree. The user's manual merge is the gate.
- **Additive inputs on retry.** Round-N>1 inputs add to round-1 inputs; they do not replace them. The codebase recall digest persists across rounds.
- **Escape hatch from the worker.** `plan_broken` and `setup_blocked` are the implementer's equivalents of capture's `no_decisions_found` / `scope_unsalvageable`. Do not iterate when the plan itself is broken.
- **Surgical-fix mode directive.** Verbatim in the round-N>1 brief. Prevents oscillation between implementation strategies.

The pattern is borrowed inline, not factored. Factoring waits for a third instance of the worker-plus-reviewer loop to appear.
