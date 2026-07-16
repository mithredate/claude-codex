---
name: implement-with-review-loop
description: >-
  Deliver a substantive code change (fix, feature, refactor, chore) through a heavy multi-agent loop: worktree-isolated implementer rounds, four parallel adversarial reviewers, a learning ledger that survives resets, and design-failure resets between rounds. Costly by design — up to 3 implementer spawns plus 4 reviewers per reviewed round. Invoke explicitly via /implement-with-review-loop only. Args: max_rounds=N (default 3), debug (archive discarded attempts). Not for read-only tasks, trivial one-line edits, or repos with no runnable test command.
disable-model-invocation: true
---

# Implement with review loop

Deliver a code change through worktree-isolated implementer rounds and four parallel reviewers, with a learning ledger, design-failure resets, a hard round cap, and a branch-and-report exit (no auto-merge). Read this whole file before spawning the first subagent.

## Philosophy

The code of a failed round is disposable; the **learning** is the durable artifact. Local defects are patched in place. Design failures reset the work to base — the next round re-derives the approach from scratch, informed by the ledger, instead of patching symptoms on top of a flawed design.

## Shape at a glance

- **Explicit invocation only.** This loop is heavy — it never auto-triggers (`disable-model-invocation: true`). The user opts into the cost by invoking the command.
- A **per-task git worktree** is mandatory. Main creates it; the implementer writes inside it. Main does not edit code outside the worktree. This is a filesystem boundary that physically prevents main from bypassing the implementer.
- A **learning ledger** — a markdown file *outside* the worktree — accumulates design-level learnings across rounds. Main appends verbatim; main never curates, summarizes, or reprioritizes it.
- The implementer has **two success outcomes**: `implemented` (a change it believes in, going to review) and `learned` (a validated insight going to the ledger; the round's code is discarded). Both are wins.
- Each reviewed round = one **implementer spawn** followed by **four reviewers in parallel** (Validator, Codebase Auditor, Questioner, Craft Reviewer). Reviewers are stateless: no ledger, no round number, no history.
- The **verdict is mechanical** — main computes it from field occupancy across the four reviewer JSONs. Reviewers do not vote.
- **Graded response:** local defects (`blocking`, `quality_note`) → keep the code, patch in place. Design failures (`discrepancy`, or the implementer's own `learned`) → reset to base, fresh derivation against the ledger.
- **Main is a state machine.** Every branch it takes is decidable from field occupancy — terminate, patch, reset, escalate. Main never edits code, never curates the ledger, and never interrupts the loop mid-flight to ask the user anything.
- On pass, cap exhaustion, or escalation, main commits inside the worktree on the per-task branch (or leaves it dirty) and reports. **The user's manual merge is the gate.**

## Invocation arguments

Parsed from the invocation message; absent means default.

- `max_rounds=N` — cap on implementer spawns. Default **3**. Every implementer spawn consumes one round, including `learned` rounds — the cap counts what you pay for.
- `debug` — archive mode. Before each reset, the discarded attempt is committed and tagged so the user can inspect it later. Off by default: by philosophy, the ledger is the only artifact of a failed round.

## What the references contain

Sub-agents do not inherit the skill directory automatically. Main passes these paths explicitly in the spawn prompt.

- `references/recall-brief.md` — codebase orientation digest, runs once; spawn as `Explore`.
- `references/implementer-brief.md` — produces the change; two-outcome contract, ledger protocol, fresh/patch modes; spawn as `general-purpose`.
- `references/reviewer-common.md` — shared reviewer contract (adversarial stance, five-field schema including `learnings`, evidence rule, no-voting). Every reviewer reads this first.
- `references/validator-brief.md` — mechanical compliance reviewer; spawn as `Explore`.
- `references/codebase-auditor-brief.md` — fit-with-surrounding-code reviewer; spawn as `general-purpose`.
- `references/questioner-brief.md` — framing-and-decision reviewer; spawn as `general-purpose`. Sole authority over `discrepancy` — the only finding that resets the work.
- `references/craft-reviewer-brief.md` — code-craft-on-its-own-terms reviewer; spawn as `general-purpose`.
- `references/commit-and-report.md` — what main does after the loop exits: commit shape, trailers, report contents (including the ledger), boundaries.
- `references/worked-example.md` — narrative walkthrough of a reset round followed by a patch round and a pass.

## Pre-flight

Before spawning anything:

1. Confirm the user explicitly invoked this skill and the request is in scope (substantive code change; not read-only; not a one-line edit they asked to apply directly). If ambiguous, stop and ask — this is the one moment user interaction is allowed before the loop exits.
2. Parse invocation arguments (`max_rounds`, `debug`); apply defaults.
3. Capture `base_sha = git rev-parse HEAD` in the parent repo. This is the diff-invariant anchor; it never moves, so resets always return to it and the recall digest stays valid across resets.
4. Capture the `user_request` **verbatim**. Do not paraphrase. If the user dictated scope, acceptance criteria, a chosen approach, or a root-cause hypothesis, that dictation lives inside `user_request` and the implementer reads it from there.
5. Create the per-task worktree on a fresh branch, and the ledger file **next to** it (outside the worktree — a reset must not be able to kill it):

   ```
   WORKTREE="<repo_root>/.claude/worktrees/implement-<YYYYMMDD-HHMMSS>-<short-ulid>-<slug>"
   BRANCH="implement/<YYYYMMDD-HHMMSS>-<short-ulid>-<slug>"
   LEDGER="${WORKTREE}-ledger.md"
   git -C "<repo_root>" worktree add -b "$BRANCH" "$WORKTREE" "$base_sha"
   ```

   `<slug>` is a short kebab-case label main proposes from `user_request`. `<short-ulid>` is the first 6 characters of a freshly-generated ULID, to break ties on same-second concurrent invocations. Create `$LEDGER` with a one-line header naming the branch; entries are appended per the ledger protocol below.

6. **`.claude/` gitignore precondition.** The repo must have `.claude/` in `.gitignore` so worktree contents do not appear as untracked files in the live clone. If absent, stop and ask the user to add it (`echo '.claude/' >> .gitignore`, commit, re-invoke).

All subsequent reads, writes, `git diff`, `git add`, and `git commit` happen **inside the worktree** — never in the parent repo directly. All `git diff` calls use the **single-ref** form `git diff <base_sha>` (run with `git -C "$WORKTREE" diff "$base_sha"`) — committed, staged, and unstaged changes since base. This is the diff invariant; reviewers always see the cumulative change, never the per-round delta.

## The learning ledger

The ledger is the durable artifact of failed rounds. Rules:

- **Authorship.** Learnings are authored by the implementer (where the codebase resisted the approach) and by reviewers (design-level restatement of their findings — root cause, never symptom). Main authors nothing.
- **Append-only, verbatim.** After each round, main appends every learning exactly as written, tagged with round number and source, numbered sequentially:

  ```
  <n>. [round <r>][<implementer|validator|codebase_auditor|questioner|craft_reviewer>] <learning>
  ```

  The only transformation main may apply is dropping an entry that is an **exact duplicate** of an existing one. No rewording, no merging, no reprioritizing — curation is judgment, and main has none.
- **Code-independent.** Learnings state constraints on *any future implementation* ("any approach that holds the cache lock across an await deadlocks the request path"), never `file:line` — the cited code may not exist after a reset. The briefs enforce this phrasing.
- **Distribution.** The full ledger content is passed verbatim to **every implementer spawn** (fresh and patch mode). Reviewers never see it — statelessness is load-bearing. The ledger travels into the final report or escalation.

## Implementer contract

The implementer's full contract — two-outcome framing, inputs, ledger protocol, minimalism boundary, fresh/patch modes, output schema, escape hatches — lives in `references/implementer-brief.md`. Before spawning, main reads the brief and constructs the spawn prompt accordingly.

**What main does not pass:** `rationale`, `scope`, `acceptance_criteria`, `chosen approach`, `rejected alternatives`, `root cause hypothesis`. These are the implementer's job to derive — in fresh mode it derives them from scratch against the ledger. If the user dictated any of them, the dictation is inside `user_request` and the implementer picks it up there.

## Codebase recall

Before round 1, spawn a single recall sub-agent per the contract in `references/recall-brief.md`. Main passes the resulting digest verbatim to every implementer spawn. The digest describes the codebase at `base_sha`, and `base_sha` never moves — so the digest survives resets untouched; re-running would waste tokens.

**Silent-failure mode.** If the recall sub-agent returns empty content, an explicit refusal, or only an error message, set `codebase_recall` to an empty digest and proceed. Surface the degradation in the final report. Do not re-spawn within the same session.

## Per-round loop (cap: `max_rounds` implementer spawns, default 3)

### A. Implementer spawn (every round)

Spawn one implementer per `references/implementer-brief.md`, with the ledger content and one of two modes:

- **Fresh mode** — round 1, and every round after a reset. The worktree is at `base_sha`. The implementer derives the approach from scratch; the ledger tells it which approaches are already known dead.
- **Patch mode** — the round after a reviewed round whose gating findings were only `blocking`/`quality_note`. The prior code survives; the spawn prompt includes the prior round's aggregated findings JSON. The implementer addresses findings surgically without rewriting working code — unless it concludes the surviving code stands on a doomed design, in which case it returns `learned` instead of patching symptoms.

### B. Route on the implementer's outcome

- **`implemented`** → append any implementer `learnings` to the ledger, then fan out reviewers (step C).
- **`learned`** → append the implementer's `learnings` (required non-empty). Skip reviewers — spending four reviews on code the implementer has disowned is waste, and nothing unreviewed can ship anyway. Then:
  - rounds remain → **reset** (step E) and start the next round in fresh mode;
  - final round → **escalate**. Leave the worktree dirty (the disowned code is inspectable) and report with the ledger. Nothing reviewable exists to ship.
- **`plan_broken` / `setup_blocked`** → exit the loop and escalate immediately with `blocker_evidence`. No commit; worktree left dirty. `plan_broken` covers a broken premise *and* the unlicensed-novel-architecture case: a per-project architectural decision only the user can make, named with options.

### C. Reviewer fan-out

Spawn four reviewers in parallel against the current state of `git -C $WORKTREE diff $base_sha`. Each is stateless: no ledger, no round number, no history — a fresh attempt deserves fresh eyes, and a reviewer that knows history anchors on it.

- **Validator** (`Explore`) — brief: `references/validator-brief.md`.
- **Codebase Auditor** (`general-purpose`) — brief: `references/codebase-auditor-brief.md`.
- **Questioner** (`general-purpose`) — brief: `references/questioner-brief.md`. Sole authority over `discrepancy`.
- **Craft Reviewer** (`general-purpose`) — brief: `references/craft-reviewer-brief.md`.

**Each brief is the canonical contract for its reviewer's inputs and output schema.** Before spawning, main reads the brief, constructs the spawn prompt with the inputs the brief lists, and passes the brief's absolute path so the reviewer can re-load it on startup.

All four briefs share a five-field output schema (see `reviewer-common.md`):

- `blocking` — concrete local defect with `file:line` evidence. Any reviewer may populate. Gates the loop; routes to **patch**.
- `discrepancy` — design failure: wrong shape, wrong approach, wrong assumption — never a local defect. Questioner only. Gates the loop; routes to **reset**.
- `quality_note` — addressable craft / fit concern. Codebase Auditor, Questioner, Craft Reviewer may populate. Gates only when no `blocking` or `discrepancy` is present; routes to **patch**.
- `nit` — minor. Never gates.
- `learnings` — each gating finding restated as a design-level, code-independent constraint. Appended to the ledger; the only field that survives a reset.

Reviewers do **not** vote: any `status` or `verdict` field they emit is ignored. Main computes the verdict from field occupancy.

### D. Verdict aggregation (mechanical — main applies, reviewers never vote)

After collecting all four reviewer JSON outputs:

1. **Malformed JSON** — if any reviewer's output is malformed (missing required field, wrong type, non-parseable), re-spawn that reviewer once with the same brief plus a stricter "your previous output was malformed; conform to the schema" preamble. If the second attempt is still malformed, **escalate to the user**. Verdict-validation re-spawns do not count against the round cap. Do not re-spawn the implementer on a reviewer-validation failure — the reviewer is the broken component.

2. Once all four outputs are valid, append all reviewer `learnings` to the ledger, then compute the verdict from field occupancy in priority order:

   | Occupancy (first match wins) | Rounds remain | Final round |
   |---|---|---|
   | Any `discrepancy` | **reset-adjust** | **escalate** |
   | Any `blocking` | **patch-adjust** | **escalate** |
   | Any `quality_note` | **patch-adjust** | **pass** (quality is not a correctness gate) |
   | Only `nit`, or nothing | **pass** | **pass** |

   `discrepancy` outranks `blocking`: when the design is wrong, patching local defects into it is wasted work — the code is about to be discarded. Priority gating protects the round budget for correctness: quality iteration never starves a real `blocking`, and if a craft / fit concern is severe enough to block, the reviewer raises it as `blocking` (the briefs allow that re-classification).

### E. Iterate

- **pass** → commit and report (`references/commit-and-report.md`).
- **patch-adjust** → next round in patch mode (keep the code; pass the aggregated findings).
- **reset-adjust** → reset the worktree, next round in fresh mode:

  ```
  # debug mode only — archive the discarded attempt first:
  git -C "$WORKTREE" add -A && git -C "$WORKTREE" commit -m "attempt <r> (discarded)" && git -C "$WORKTREE" tag "${BRANCH}/attempt-<r>"
  # always:
  git -C "$WORKTREE" reset --hard "$base_sha" && git -C "$WORKTREE" clean -fd
  ```

  The ledger survives by construction — it lives outside the worktree.
- **escalate** → exit the loop. Commit current state in the worktree with a `Review-Status` trailer (see `commit-and-report.md`) and report with un-addressed findings labeled and the full ledger. The user decides next steps.

### Escalation triggers — exactly three, all mechanical

1. `plan_broken` / `setup_blocked` from the implementer (includes unlicensed novel architecture).
2. Final round ends with gating `blocking` or `discrepancy` outstanding.
3. Final round returns `learned` — nothing reviewable exists to ship.

There is no judgment-based early stop. If the loop burns every round and escalates, that is the design working: the ledger it hands over is the deliverable. When the loop exhausts rounds with only repetitive learnings, the human reading the ledger is the convergence detector — no mechanism substitutes for that.

## Commit, branch, and report

On `pass`, cap exhaustion, or escalation, main commits inside the worktree (or leaves it dirty for escape hatches and final-round `learned`), then reports to the user — including the full ledger and, in debug mode, the list of archived attempt tags. **Do not merge to main. Do not push. Do not remove the worktree.** Full contract — commit shape, trailers, report contents — lives in `references/commit-and-report.md`.
