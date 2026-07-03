---
name: implement-with-review-loop
description: >-
  Implement code changes — fixes, features, refactors, or substantive chores — under a worktree-isolated implement-then-review loop. Manual-invoke only: the user spawns this skill explicitly when they want the loop. In scope: substantive code changes. Out of scope: read-only tasks (analysis, exploration, summarization) and trivial one-line edits the user asks to apply directly.
disable-model-invocation: true
---

# Implement with review loop

Deliver a code change through a worktree-isolated implementer subagent and two parallel reviewers, with at most one fix round and a branch-and-report exit (no auto-merge). The loop optimizes for **better code per minute spent** — the user reviews before merge; the loop's job is to make that review short, not to replace it. Read this whole file before spawning the first subagent.

## Shape at a glance

- A **per-task git worktree** is mandatory. Main creates it; the implementer writes inside it. Main does not edit code — this is a filesystem boundary that physically prevents main from bypassing the implementer.
- Each round = one **implementer spawn**, then **mechanical checks run by main directly** (no agent), then **two reviewers in parallel** (Correctness & Fit, Craft & Economy).
- Findings have **two tiers**: `fix` (evidence-backed; gates) and `fyi` (never gates; travels to the report).
- **At most one fix round.** Round 1: implement + review. Round 2: fix everything + re-review. Anything still open after round 2 is handed to the user as an explicit "unresolved — triage before merge" list. There is no round 3.
- On exit, main **commits inside the worktree on the per-task branch** and reports. **The user's manual merge is the gate.**

Worst case: 6 subagent spawns (implementer + 2 reviewers, fix implementer + 2 reviewers). Common case — clean round 1 — is 3.

## What the references contain

Sub-agents do not inherit the skill directory automatically. Main passes these paths explicitly in the spawn prompt.

- `references/implementer-brief.md` — produces the change under a minimalism mandate; spawn as `general-purpose`.
- `references/reviewer-common.md` — shared reviewer contract (adversarial stance, two-tier schema, evidence rule, no-voting). Every reviewer reads this first.
- `references/correctness-fit-brief.md` — bugs and fit-with-surrounding-codebase reviewer; spawn as `general-purpose`.
- `references/craft-economy-brief.md` — code-craft and diff-economy reviewer; spawn as `general-purpose`.
- `references/commit-and-report.md` — what main does after the loop exits: commit shape, trailers, report contents, boundaries.
- `references/worked-example.md` — narrative walkthrough of a round-1-findings → fix-round → pass run.

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

5. **`.claude/` exclusion.** If `.claude/` is not already in the repo's `.gitignore`, append `.claude/` to `<repo_root>/.git/info/exclude` (local-only, no commit needed) so worktree contents do not appear as untracked files in the live clone. Do not stop or ask; this is silent and reversible.

All subsequent reads, writes, `git diff`, `git add`, and `git commit` happen **inside the worktree** — never in the parent repo directly. All `git diff` calls use the **single-ref** form `git diff <base_sha>` (run with `git -C "$WORKTREE" diff "$base_sha"`) — committed, staged, and unstaged changes since base. This is the diff invariant; reviewers always see the cumulative change, never the per-round delta.

There is no separate codebase-recall agent. The implementer is `general-purpose` and orients itself; the fix round inherits round 1's `scope_declared` and findings instead of a digest.

## Implementer contract

The implementer's full contract — inputs, output schema, minimalism mandate, boundaries, escape hatches — lives in `references/implementer-brief.md`. Before spawning, main reads the brief and constructs the spawn prompt accordingly.

**What main does not pass:** `rationale`, `scope`, `acceptance_criteria`, `chosen approach`, `root cause hypothesis`. These are the implementer's job to derive. If the user dictated any of them, the dictation is inside `user_request` and the implementer picks it up there.

When the implementer returns `status: "plan_broken"` or `"setup_blocked"`, **do not iterate** — exit the loop and escalate to the user with the implementer's `blocker_evidence`. The worktree is left dirty (no commit) for the user to inspect.

## Round 1 — implement, check, review

### A. Implementer

Spawn one implementer per `references/implementer-brief.md`.

### B. Mechanical checks (main, no agent)

After the implementer returns `complete`, main runs these directly inside the worktree. Each failure becomes a `fix` finding tagged `mechanical`, with `file:line` or a command-output excerpt as evidence:

1. **Command exit codes.** Run the test, lint, and typecheck commands declared in the repo's `CLAUDE.md`. Non-zero exit → `fix`, citing the failing output excerpt. A declared command that cannot be executed is a `fix` finding, not a silent skip.
2. **Scope respected.** Every path in `git -C $WORKTREE diff $base_sha --name-only` is within the implementer's `scope_declared` (new files within its directory hints). Escapes → `fix`.
3. **No silent dependency additions.** Changes to dependency manifests (`package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, etc.) must appear in `rationale_out.residual_risks_accepted`. Silent additions → `fix`.
4. **Diff hygiene.** Grep the diff for commented-out code, debug prints (`console.log`, `print(`, `dbg!`, …), and new `TODO`/`FIXME`/`XXX`/`HACK` markers. Hits → `fix`.

These checks are cheap; run them before spawning reviewers. If the test command fails outright, skip the reviewer fan-out and go straight to the fix round with the mechanical findings — reviewing a broken build wastes two spawns.

### C. Reviewer fan-out

Spawn two reviewers in parallel against the current state of `git -C $WORKTREE diff $base_sha`:

- **Correctness & Fit** (`general-purpose`) — brief: `references/correctness-fit-brief.md`. Owns bugs, edge cases, downstream consumers, conventions, placement, missed reuse.
- **Craft & Economy** (`general-purpose`) — brief: `references/craft-economy-brief.md`. Owns over-engineering, diff size vs. problem size, SOLID/code smells, naming, hardcoded literals, test quality.

**Each brief is the canonical contract for its reviewer's inputs and output schema.** Before spawning, main reads the brief, constructs the spawn prompt with the inputs the brief lists, and passes the brief's absolute path plus the path to `reviewer-common.md` so the reviewer can re-load them on startup.

Reviewers are **stateless** — re-derived from scratch against the cumulative diff, never told which round it is. Reviewers do **not** vote: any `status` or `verdict` field they emit is ignored.

### D. Verdict (mechanical — main applies)

1. **Malformed JSON** — if a reviewer's output is malformed (missing required field, wrong type, non-parseable), re-spawn that reviewer once with the same brief plus a stricter "your previous output was malformed; conform to the schema" preamble. If the second attempt is still malformed, treat that reviewer's findings as empty and flag the degradation prominently in the final report. Do not re-spawn the implementer on a reviewer-validation failure.
2. Merge the mechanical-check findings and both reviewers' outputs. Then:
   - Any `fix` finding → **fix round** (below).
   - Only `fyi` findings, or none → **pass** → commit and report.

## Round 2 — fix round (at most one)

### A. Fix implementer

Spawn a fresh implementer per the brief, with the round-1 inputs plus:

- The aggregated findings JSON from round 1 (mechanical + both reviewers).
- Round 1's `rationale_out` (so it inherits the framing and `scope_declared` without re-deriving them).
- **Fix directive (verbatim):**

  > Fix mode — you operate on the same worktree as the prior implementer. Inspect the current cumulative state via `git -C "$WORKTREE" diff "$base_sha"` before editing. Address **every** `fix` finding; `fyi` items are optional. Do not rewrite working code, do not expand scope, and the minimalism mandate still applies — the smallest change that resolves each finding. If you believe a finding requires a larger restructure than the current approach supports, return `plan_broken` with evidence rather than silently expanding.

### B. Mechanical checks + re-review

Re-run the mechanical checks, then spawn both reviewers again (identical briefs, stateless, no awareness of the round). Merge findings as before:

- No `fix` findings → **pass** → commit and report.
- Any `fix` finding remaining → **stop anyway**. Commit with a `Review-Status` trailer and hand the open items to the user as an explicit **"unresolved — triage before merge"** list in the report. There is no round 3: if two passes didn't converge, the open items are usually judgment calls the user settles faster than another agent round would.

## Commit, branch, and report

On pass, round-2 exit, or escape hatch, main commits inside the worktree (or leaves it dirty for escape hatches), then reports to the user. **Do not merge to main. Do not push. Do not remove the worktree.** Full contract — commit shape, trailers, report contents — lives in `references/commit-and-report.md`.
