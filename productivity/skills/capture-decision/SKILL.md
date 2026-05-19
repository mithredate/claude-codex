---
name: capture-decision
description: >-
  Capture closed-off forks from the current session into the user's decision archive as decision files plus an optional per-session synthesis. Trigger when the user signals end-of-session capture intent — phrases like "let's capture this", "archive what we decided", "write up the decisions", "wrap this up", "capture these decisions" — and when another skill's termination hands off to capture (e.g., grill-me transfers control at session end). Do NOT trigger proactively on conversational silence, on a single closed-off fork mid-session (that's mid-session signal, not capture intent), or when the archive working tree is dirty (the pre-flight refuses). The skill runs scope confirmation, dumps a faithful transcript, dispatches a recall agent, then iterates a capture-plus-three-reviewer loop (hard cap 3 rounds) before a single human gate. Drafts live on disk as unstaged files; accept commits them, discard rolls them back.
---

# Capture Decision

Capture the closed-off forks from the current session into the user's decision archive — N decision files plus at most one synthesis file plus any supersede flips on existing decisions — through a multi-agent loop that drafts on disk, reviews against the archive, and presents one human gate.

The archive lives at `$DECISION_ARCHIVE_ROOT` (a local clone of the user's decision-archive repo). Capture operates inside a **dedicated git worktree per session** at `$DECISION_ARCHIVE_ROOT/.claude/worktrees/capture-<YYYYMMDD-HHMMSS>-<slug>/` on a fresh branch `capture/<YYYYMMDD-HHMMSS>-<slug>` — mirrors the mithredate-skills import-skill convention. Drafts live as **unstaged files on disk** inside the worktree throughout the iteration loop. `git diff <base_sha>` (run inside the worktree) is the canonical surface reviewers and the human inspect; `git add` + `git commit` (inside the worktree) is the publish moment; `git worktree remove --force` is the discard path. Mergeback to `main` is left for the user to do manually (e.g., `gh pr create` or `git checkout main && git merge`).

## What the references contain

Sub-agents do not inherit the skill directory automatically. Brief templates pass these paths explicitly.

- `references/CONTEXT.md` — the skill's **vocabulary** file (Matt Pocock CONTEXT.md format). Each sub-agent brief lists it as the first input; sub-agents read it before anything else to align terminology and avoid the `_Avoid_:` aliases.
- `references/decision-format.md` — **normative** authoring spec (frontmatter, edge vocabulary, slug convention, ID assignment, body sections, triple-filter, supersede mechanics, synthesis structure).
- `references/drafting-brief.md` — template the capture sub-agent receives; round-1 vs round-N>1 inputs; surgical-fix directive; required output schema.
- `references/reviewer-validator-brief.md` — mechanical checklist; spawn as `Explore`.
- `references/reviewer-auditor-brief.md` — Archive Auditor's semantic / archive-integration checklist; spawn as `general-purpose`. Includes edge-liveness, transcript-faithfulness, near-duplicate, contradiction-with-accepted detection.
- `references/reviewer-quality-brief.md` — Quality Reviewer's write-up + triple-filter + synthesis-coherence checklist; spawn as `general-purpose`.

## Pre-flight

Refuse to run unless `DECISION_ARCHIVE_ROOT` is set in the environment and points at an existing git directory. Stop and inform the user otherwise.

Run `git -C "$DECISION_ARCHIVE_ROOT" status --porcelain`. If the output is non-empty, refuse to proceed and tell the user to commit or stash their changes first — mixing pre-existing uncommitted work with capture-produced drafts makes the diff invariant ambiguous.

Capture `base_sha = git -C "$DECISION_ARCHIVE_ROOT" rev-parse HEAD`. The worktree itself is created at the end of Step 1, once the slug is confirmed.

## Step 1 — Scope, slug, and worktree

Main proposes **scope** — a cut of the conversation — not a content summary. Example proposals:

- "Capture from the start of the session, or from when we shifted to discussing the indexer design?"
- "The scope I see is roughly turns 5 through 30 — does that match what you want captured?"

User confirms or amends scope. **Do not iterate.** If the user wants to refine content, that happens later via the human gate.

This step also nails the **slug** for the transcript filename. Main proposes one (kebab-case, descriptive, namespaced by topic). User can override.

Once `<slug>` is confirmed, create the per-session worktree from `base_sha`:

```
WORKTREE="$DECISION_ARCHIVE_ROOT/.claude/worktrees/capture-<YYYYMMDD-HHMMSS>-<slug>"
BRANCH="capture/<YYYYMMDD-HHMMSS>-<slug>"
git -C "$DECISION_ARCHIVE_ROOT" worktree add -b "$BRANCH" "$WORKTREE" "$base_sha"
```

`<YYYYMMDD-HHMMSS>` is the current date+time. All subsequent writes, edits, `git diff`, `git add`, and `git commit` happen **inside the worktree** — never in `$DECISION_ARCHIVE_ROOT` directly. All `git diff` calls in this skill use the **single-ref** form `git diff <base_sha>` (run with `git -C "$WORKTREE" diff "$base_sha"`) — committed, staged, and unstaged changes since base. This is the diff invariant; reviewers always see the cumulative change, never the per-round delta. The `.claude/` directory must be gitignored in the archive repo so worktree contents do not appear as untracked files in the live clone.

## Step 2 — Transcript dump

Main writes the in-scope conversation **faithfully** to:

```
$WORKTREE/transcripts/transcript-<YYYYMMDD-HHMMSS>-<slug>.md
```

Where `$WORKTREE` is the per-session worktree created in Pre-flight; `<YYYYMMDD-HHMMSS>` and `<slug>` match the worktree's branch name.

Format: `user:` / `assistant:` prefixed turns. No summarization, no editorial paraphrase, no compression beyond what main's own context already imposes. If main's context has been auto-compacted, dump what main has and note the fidelity ceiling in a footer comment in the transcript file (this is a known limitation, not a defect).

The transcript file is an **unstaged** addition. It will travel with the decisions through the human gate:

- On `accept` → committed alongside the decisions.
- On `discard` → file is deleted (along with the unstaged decision/synthesis edits).

Main does **not** pass a summary to sub-agents. Briefs reference the transcript path; sub-agents read the file themselves.

## Step 3 — Recall research (one-shot)

Spawn the **recall sub-agent** as `general-purpose` (capture-time recall is heavier than mid-session lookup because it needs cross-body reasoning, not just pattern-matching).

Brief contents:

- Operating root: `$WORKTREE` — the per-session worktree from Pre-flight. **All reads and writes happen here.** The live archive clone at `$DECISION_ARCHIVE_ROOT` is not touched by sub-agents during the iteration loop.
- Absolute path to recall patterns: resolve from this skill's directory as `<this-skill-dir>/../recall-decision/references/recall-patterns.md` and pass the resulting absolute path verbatim in the brief. (Assumes `capture-decision` and `recall-decision` are co-located under the same `skills/` parent — true within this plugin repo.)
- Path to the transcript file from Step 2 (lives inside `$WORKTREE/transcripts/`).
- Instructions: "Read the transcript. Identify likely edge candidates — decisions this batch may `depends-on`, `informs`, `supersedes`, or be `synthesized` into. Use the canonical Bash patterns in the recall-patterns file whose absolute path is in this brief. Return a ≤50-line digest with one line per candidate: `{id, slug, kind, status, why-relevant}`."
- Digest schema is strict; no full bodies in the digest.

Recall runs **once**, not per iteration round. The set of related existing decisions does not change between rounds; re-running would waste tokens and add latency.

Hold the returned digest as `recall_digest`. It is passed verbatim to every round of the capture agent's brief.

## Step 4 — Iteration loop (hard cap: 3 rounds)

Each round = one capture-agent spawn followed by three parallel reviewer spawns. Reviewers are **stateless every round** — re-derived from scratch against the current `git diff <base_sha>`, never told which round it is.

### Round 1

Spawn the **capture agent** as `general-purpose`. Brief = `references/drafting-brief.md` with round-1 inputs filled in:

- Worktree: `$WORKTREE` — the per-session worktree path from Pre-flight. **All reads, writes, and `git diff` calls happen inside the worktree.** The live archive clone is not touched. In the brief's `<worktree>` placeholder, pass `$WORKTREE` verbatim.
- Transcript path: from Step 2 (already inside `$WORKTREE/transcripts/`)
- Recall digest: from Step 3
- Format reference path: `references/decision-format.md`
- Base SHA: `base_sha` (for the diff invariant; `git -C "$WORKTREE" diff "$base_sha"` is the cumulative-change command)

The capture agent writes/edits files directly at canonical paths inside `$WORKTREE`:

- New decision files in `decisions/<id>-<namespace>-<slug>.md` with `status: accepted`.
- An optional synthesis file in `synthesis/<id>-<namespace>-<slug>.md`.
- Edits to existing decisions to flip `status: accepted` → `status: superseded` when the batch supersedes them.

Capture agent returns a tight JSON digest (≤15 lines) — see `drafting-brief.md` for the schema. The digest never contains file bodies; the bodies are on disk.

**Escape hatch from capture agent.** If the capture agent returns `status: "session_not_capture_ready"`, exit the loop and surface to the human with the evidence. Do not iterate. The hatch fires when the agent determines the session does not contain capture-worthy material (no closed-off forks meeting the triple-filter, transcript too thin, scope confirmation captured the wrong span).

### Reviewer fan-out (every round)

Spawn three reviewers in parallel against the current state of `git diff <base_sha>`:

- **Validator** (`Explore`) — brief: `references/reviewer-validator-brief.md`
- **Archive Auditor** (`general-purpose`) — brief: `references/reviewer-auditor-brief.md`
- **Quality Reviewer** (`general-purpose`) — brief: `references/reviewer-quality-brief.md`

Each reviewer receives:

- `base_sha`
- A hint about the meaning of committed vs uncommitted changes in the archive repository
- Archive root path
- Path to `references/decision-format.md`
- Path to the transcript (Archive Auditor and Quality Reviewer only — Validator does not need session context)

Reviewers return strict JSON. The field schema is fixed at four arrays across all three reviewers; some reviewers fill only a subset (the rest are empty arrays):

- `blocking` — concrete defects that must be addressed. Filled by any reviewer. The Quality Reviewer folds **triple-filter** failures into this field (a triple-filter fail is blocking).
- `discrepancy` — structural problems that require another round but aren't single-point defects. **Archive Auditor only** — Validator and Quality Reviewer leave this empty. Four sub-categories (see below).
- `quality_note` — voice/style notes; **advisory only, never gates**. **Quality Reviewer only.**
- `nit` — minor stylistic findings; never gates. Filled by Validator or Quality Reviewer.

Reviewers do **not** vote: any `verdict` field a reviewer emits is treated as an ignored courtesy field. Main computes the loop verdict from field occupancy.

### Verdict aggregation (mechanical — main applies, reviewers never vote)

After collecting all three reviewer JSON outputs, apply this rule in order:

1. If any reviewer's findings JSON is malformed (missing required field, wrong type, non-parseable), **re-spawn that reviewer once** with the same brief plus a stricter "your previous output was malformed; conform to the schema" preamble. If the second attempt is still malformed, **escalate to the human**. Verdict-validation re-spawns do not count against the 3-round cap. Do not re-spawn the capture agent on a reviewer-validation failure — the reviewer is the broken component.

2. Once all three outputs are valid, compute the verdict from field occupancy across all three:
   - Any `blocking` finding (from any reviewer — includes triple-filter failures folded in by the Quality Reviewer) → **adjust** if rounds remain, else **escalate**.
   - Any `discrepancy` finding (Archive Auditor only) → **adjust** if rounds remain, else **escalate**.
   - Only `quality_note` and/or `nit` findings → **pass** → exit loop.
   - No findings at all → **pass** → exit loop.

**`discrepancy` has teeth.** It is **not** advisory. Four specific structural findings from the Archive Auditor are categorised as `discrepancy` (forcing another round, not just a note):

- **Edge-liveness violation.** A new decision declares `depends-on: [X]` where `X` is `superseded` and an active successor `Y` exists, *and* the new decision is not itself the supersession of `X`. The legitimate pattern is "A supersedes B → A depends-on B"; the suspect pattern is "C depends-on B (where B is superseded by D, C is not the supersession of B)". The Archive Auditor calls these out and the capture agent rewires the edge in the next round.
- **Transcript-faithfulness gap.** A `Chosen` or `Rationale` assertion in a draft is not supported by anything in the transcript. The draft drifted from the conversation. Re-draft.
- **Near-duplicate of an existing accepted decision.** A draft substantively re-decides what an `accepted` decision already settles without superseding it.
- **Contradiction with an existing accepted decision.** A draft's `Chosen` is incompatible with the `Chosen` of an existing `accepted` decision, without superseding it. The capture agent must either add the existing decision to `supersedes` (and flip its status), re-draft to not contradict, or drop the new decision.

These four are blocking-grade in their effect on the loop. Calling them `discrepancy` rather than `blocking` is a categorisation distinction (they're archive-integration concerns rather than mechanical defects), not an advisory distinction.

**`quality_note` is genuinely advisory.** Voice, length, prose-tightening, stylistic preferences. The Quality Reviewer can flag these; main records them for the human gate's summary but they do not force another round. If they did, the loop would oscillate on subjective preferences.

### Round 2 and Round 3

If the verdict is `adjust` and rounds remain, spawn a fresh capture agent (new context — no carry-over from the prior agent's memory). Brief = `references/drafting-brief.md` with round-N>1 inputs added (not substituted):

- All round-1 inputs (unchanged)
- The aggregated findings from all three reviewers
- The **surgical-fix mode directive** — its canonical text lives in `references/drafting-brief.md` under "Surgical-fix mode directive (round 2+ — apply verbatim)". Main pastes that block verbatim into the round-N>1 brief.

Then spawn the three reviewers in parallel (identical brief — no awareness of round number).

After Round 3, exit the loop regardless of verdict. Carry the final state to the human gate.

## Step 5 — Human gate

Present to the user:

- **Files touched** — bulleted list of paths (decisions, synthesis, supersede flips, transcript), each one inspectable via `git diff` or in their editor.
- **Findings summary** — collapsed by category:
  - Outstanding `blocking` items (if any survived to cap-exhaustion) — show each finding's text and `path:line` cite.
  - Outstanding `discrepancy` items (if any) — same shape.
  - `quality_note` items — terse, advisory.
  - `nit` items — count only, not enumerated.
- **The base SHA**, so the user can independently run `git diff <base_sha>` to inspect.
- **No file bodies in main's context.** Main does not Read the drafts. The user inspects via git.

Wait for the user's verdict. Four options:

- `accept` → Step 6 (commit).
- `accept with edits` → user edits on disk in their editor first, then says `done` or `commit`. Main commits the current disk state (which includes their edits). The diff invariant still holds because their edits are part of `git diff <base_sha>`.
- `request changes [reason]` → re-enter the iteration loop with the user's reason injected as a finding-shaped input (in `blocking` if specific, in `discrepancy` if structural). If the 3-round cap is already exhausted, `request changes` is the explicit cap-raise: it counts as a new round. The user may instead `accept with edits` (take over manually) or `discard`.
- `discard` → Step 6 (rollback).

## Step 6 — Commit or discard

### On accept (or accept-with-edits):

Commit the changes **inside the worktree** on the capture branch. Single commit for the whole batch:

```
cd "$WORKTREE"
git add decisions/ synthesis/ transcripts/
git commit -m "<message below>"
```

Commit message structure:

```
capture: <one-line scope summary> (N decisions, optional synthesis)

- decisions/<id>-<slug>.md
- decisions/<id>-<slug>.md
- synthesis/<id>-<slug>.md
- transcripts/transcript-<timestamp>-<slug>.md
- supersede flips: <id>, <id>

Refs: transcript-<timestamp>-<slug>
```

The commit lands on the `capture/<timestamp>-<slug>` branch only. Do **not** merge to `main`, do **not** push, do **not** remove the worktree. The user merges manually when ready (e.g. `gh pr create --base main` from the worktree, or `git checkout main && git merge capture/<timestamp>-<slug>` in the parent repo). The post-commit pre-merge window is the user's "sleep on it" buffer.

After committing, tell the user: the worktree path, the branch name, and the suggested merge command. Do not act on their behalf.

### On discard:

Atomic rollback: remove the worktree and its branch in one operation.

```
git -C "$DECISION_ARCHIVE_ROOT" worktree remove --force "$WORKTREE"
git -C "$DECISION_ARCHIVE_ROOT" branch -D "$BRANCH"
```

This removes the entire worktree directory (including all unstaged decision/synthesis edits and the transcript) and deletes the per-session branch. After rollback, `$DECISION_ARCHIVE_ROOT` is byte-identical to the pre-Pre-flight state. No prompt — discard is a single atomic operation.

## Escape hatches and edge cases

- **`session_not_capture_ready` from capture agent.** Exit loop, surface to human with the agent's evidence. The session may genuinely have no closed-off forks worth capturing. The user decides: discard, expand scope and retry, or amend the brief.
- **Verdict-validation failure on reviewer JSON.** Re-spawn that reviewer once (does not count against the 3-round cap). Second failure → escalate to human with the malformed verdicts and the current diff. Do not re-spawn the capture agent — the reviewer is the broken component.
- **3-round cap exhaustion with outstanding `blocking` or `discrepancy`.** Cap exhaustion routes directly to the human gate with the current on-disk state and the un-addressed findings clearly labeled. Do not ask to extend rounds before presentation. The user may raise the cap via `request changes` post-gate, which counts as a new iteration round.
- **User says `request changes` after cap-exhaustion.** Do not silently restart the loop. Ask explicitly: "The 3-round cap is exhausted. Do you want to raise the cap and retry, or would you prefer to take over manually?"
- **Capture agent writes a file outside `decisions/` or `synthesis/`.** Validator catches this as `blocking`. The capture-agent brief's boundaries section forbids it.

## Borrowed disciplines (inline reference)

From `dev/skills/implement-with-review-loop/` — the following patterns transfer verbatim in spirit, adapted for the decision-archive domain:

- **Pre-flight clean-tree check.** Mixing pre-existing uncommitted changes with capture-produced ones makes the diff ambiguous.
- **Single-ref diff invariant.** `git diff <base_sha>` only. Never the per-round delta. Reviewers always evaluate the cumulative change.
- **Stateless reviewers.** Each reviewer spawn re-derives the verdict from scratch. No awareness of round number. Prevents drift.
- **Verdict validation.** Re-spawn once on malformed JSON; escalate on second failure. The reviewer is the broken component, not the change.
- **Hard cap with escalation.** Three rounds. Cap exhaustion is not failure — it routes to the human gate with the current state preserved on disk.
- **Additive inputs on retry.** Round-N>1 inputs add to round-1 inputs; they do not replace them. The transcript and recall digest persist across rounds.
- **Escape hatch from the worker.** `session_not_capture_ready` is the capture agent's equivalent of `plan_broken`. Do not iterate when the plan itself is broken.
- **Surgical-fix mode directive.** Verbatim in the round-N>1 brief. Prevents oscillation between drafting strategies.

The pattern is borrowed inline, not factored. Factoring waits for a third instance of the worker-plus-reviewer pattern to appear.
