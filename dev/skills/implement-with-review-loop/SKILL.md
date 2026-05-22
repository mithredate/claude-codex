---
name: implement-with-review-loop
description: >-
  Implement code changes — fixes, features, refactors, or substantive chores — under a worktree-isolated implement-then-review loop. Trigger when the user has approved a plan and asked for implementation, or uses phrases like "implement X", "add feature Y", "fix bug Z", "refactor M", "build out the auth flow". Use this skill even when the user does not explicitly ask for review — review is the default for substantive changes. Do NOT trigger for read-only tasks (analysis, exploration, summarization), trivial one-line edits the user explicitly asks to apply directly, or work in a repo with no runnable test command.
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

Sub-agents do not inherit the skill directory automatically. Main passes these paths explicitly in the spawn prompt.

- `references/recall-brief.md` — codebase orientation digest, runs once; spawn as `Explore`.
- `references/implementer-brief.md` — produces the change; spawn as `general-purpose`.
- `references/reviewer-common.md` — shared reviewer contract (adversarial stance, four-field schema, evidence rule, no-voting). Every reviewer reads this first.
- `references/validator-brief.md` — mechanical compliance reviewer; spawn as `Explore`.
- `references/codebase-auditor-brief.md` — fit-with-surrounding-code reviewer; spawn as `general-purpose`.
- `references/questioner-brief.md` — framing-and-decision reviewer; spawn as `general-purpose`. Sole authority over `discrepancy`.
- `references/craft-reviewer-brief.md` — code-craft-on-its-own-terms reviewer; spawn as `general-purpose`.
- `references/commit-and-report.md` — what main does after the loop exits: commit shape, trailers, report contents, boundaries.
- `references/worked-example.md` — narrative walkthrough of a fix-scenario round-1-adjust → round-2-pass.

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

## Implementer contract

The implementer's full contract — inputs, output schema, boundaries, escape hatches — lives in `references/implementer-brief.md`. Before spawning, main reads the brief and constructs the spawn prompt accordingly.

**What main does not pass:** `rationale`, `scope`, `acceptance_criteria`, `chosen approach`, `rejected alternatives`, `root cause hypothesis`. These are the implementer's job to derive. If the user dictated any of them, the dictation is inside `user_request` and the implementer picks it up there.

## Codebase recall

Before round 1, spawn a single recall sub-agent per the contract in `references/recall-brief.md`. Main passes the resulting digest verbatim to every implementer spawn (round 1 and every retry) — the set of relevant files does not change between rounds; re-running would waste tokens.

**Silent-failure mode.** If the recall sub-agent returns empty content, an explicit refusal, or only an error message, set `codebase_recall` to an empty digest and proceed. Surface the degradation in the final report. Do not re-spawn within the same session.

## Per-round loop (hard cap: 3 rounds)

Each round = one implementer spawn followed by four parallel reviewer spawns. Reviewers are **stateless every round** — re-derived from scratch against the current `git diff <base_sha>`, never told which round it is. Carrying state would bias reviewers toward confirming a prior verdict and would let regressions in previously-clean regions slip through.

### A. Implementer subagent (round 1 and every retry)

Spawn one implementer per the contract in `references/implementer-brief.md`. Round-N>1 adds two things to the round-1 inputs:

- The aggregated reviewer findings JSON from the prior round.
- **Surgical-fix mode directive (verbatim):**

  > Surgical fix mode — you operate on the same worktree across retries. Inspect the current cumulative state via `git -C "$WORKTREE" diff "$base_sha"` before editing. Address every `blocking` and `discrepancy` item from the verdict; if neither is present in this round's findings, address `quality_note` items. Never address `nit`. Do not rewrite working code or expand scope. If you believe a finding requires a larger restructure than the prior approach supports, return `plan_broken` with evidence rather than silently expanding.

When the implementer returns `status: "plan_broken"` or `"setup_blocked"`, **do not iterate** — exit the loop and escalate to the user with the implementer's `blocker_evidence`. The worktree is left dirty (no commit) for the user to inspect.

### B. Reviewer fan-out (every round)

Spawn four reviewers in parallel against the current state of `git -C $WORKTREE diff $base_sha`. Each is stateless; no awareness of round number.

- **Validator** (`Explore`) — brief: `references/validator-brief.md`.
- **Codebase Auditor** (`general-purpose`) — brief: `references/codebase-auditor-brief.md`.
- **Questioner** (`general-purpose`) — brief: `references/questioner-brief.md`. Sole authority over `discrepancy`.
- **Craft Reviewer** (`general-purpose`) — brief: `references/craft-reviewer-brief.md`.

**Each brief is the canonical contract for its reviewer's inputs and output schema.** Before spawning, main reads the brief, constructs the spawn prompt with the inputs the brief lists, and passes the brief's absolute path so the reviewer can re-load it on startup.

All four briefs share a four-array output schema used for verdict aggregation:

- `blocking` — concrete defect with `file:line` evidence. Any reviewer may populate. Gates the loop.
- `discrepancy` — structural framing problem. Questioner only. Gates the loop.
- `quality_note` — addressable craft / fit concern. Codebase Auditor, Questioner, Craft Reviewer may populate. Gates the loop only when no `blocking` or `discrepancy` is present.
- `nit` — minor. Never gates.

Reviewers do **not** vote: any `status` or `verdict` field they emit is ignored. Main computes the loop verdict from field occupancy.

### C. Verdict aggregation (mechanical — main applies, reviewers never vote)

After collecting all four reviewer JSON outputs, apply this rule **in order**:

1. **Malformed JSON** — if any reviewer's output is malformed (missing required field, wrong type, non-parseable), re-spawn that reviewer once with the same brief plus a stricter "your previous output was malformed; conform to the schema" preamble. If the second attempt is still malformed, **escalate to the user**. Verdict-validation re-spawns do not count against the 3-round cap. Do not re-spawn the implementer on a reviewer-validation failure — the reviewer is the broken component.

2. Once all four outputs are valid, compute the verdict from field occupancy in priority order:
   - Any `blocking` finding (from any reviewer) → **adjust** if rounds remain, else **escalate**.
   - Any `discrepancy` finding (Questioner only) → **adjust** if rounds remain, else **escalate**.
   - Any `quality_note` finding (and no `blocking`/`discrepancy` this round) → **adjust** if rounds remain, else **pass** (quality is not a correctness gate; do not escalate).
   - Only `nit` findings, or no findings at all → **pass** → exit loop and proceed to commit.

   Priority gating protects the round budget for correctness: the implementer addresses the highest-priority finding type in each round, so quality iteration never starves a real `blocking`. If a craft / fit concern is severe enough to block, the reviewer raises it as `blocking` instead of `quality_note` — the brief categories allow that re-classification.

### D. Iterate

- **pass** → commit and report (next section).
- **adjust** → spawn a fresh implementer (step A) with round-N>1 inputs (including the aggregated findings and the surgical-fix directive). Then spawn the four reviewers in parallel (identical brief — no awareness of round number).
- **escalate** → exit the loop. Commit current state in the worktree with a `Review-Status` trailer (see next section) and report to the user with un-addressed findings labeled. The user decides next steps.
- **Hard cap: 3 `adjust` rounds.** After round 3, exit the loop regardless of verdict. If outstanding `blocking` or `discrepancy` remain, this is the `escalate` branch. If only `quality_note` remains, this is `pass` — the quality findings travel to the final report but do not block commit.

## Commit, branch, and report

On `pass`, 3-round cap exhaustion, or escape hatch, main commits inside the worktree (or leaves it dirty for escape hatches), then reports to the user. **Do not merge to main. Do not push. Do not remove the worktree.** Full contract — commit shape, trailers, report contents — lives in `references/commit-and-report.md`.

