---
name: capture-decision
description: >-
  Capture closed-off forks from the current session into the user's decision archive as decision files plus an optional per-session synthesis. Trigger on end-of-session capture intent — phrases like "let's capture this", "archive what we decided", "write up the decisions", "wrap this up", "capture these decisions" — and when another skill's termination hands off to capture (e.g., grill-me at session end). Do NOT trigger proactively on conversational silence, on a single closed-off fork mid-session (that's mid-session signal, not capture intent), or when the archive working tree is dirty (the pre-flight refuses).
---

# Capture Decision

Capture the closed-off forks from the current session into the user's decision archive — N decision files plus at most one synthesis file plus any supersede flips on existing decisions — through a multi-agent loop that drafts on disk, reviews against the archive, and presents one human gate.

The archive lives at one of the paths listed in `$DECISION_ARCHIVE_ROOT` (a comma-separated list of local clones; a single path is the one-element case). Pre-flight parses the list and, when more than one entry is configured, prompts the user to pick one destination archive for this capture; the selected path is `$ARCHIVE_ROOT` and everything downstream uses it. Capture operates inside a **dedicated git worktree per session** at `$ARCHIVE_ROOT/.claude/worktrees/capture-<YYYYMMDD-HHMMSS>-<short-ulid>-<slug>/` on a fresh branch `capture/<YYYYMMDD-HHMMSS>-<short-ulid>-<slug>`. The `<short-ulid>` segment is the first 6 characters of a freshly-generated ULID — it disambiguates concurrent captures within the same second (the archive is multi-contributor; two captures landing in the same second is a realistic collision under cross-user activity). Drafts live as **unstaged files on disk** inside the worktree throughout the iteration loop. `git diff <base_sha>` (run inside the worktree) is the canonical surface reviewers and the human inspect; `git add` + `git commit` (inside the worktree) is the publish moment; `git worktree remove --force` is the discard path. Mergeback to `main` is left for the user to do manually (e.g., `gh pr create` or `git checkout main && git merge`).

## What the references contain

Sub-agents do not inherit the skill directory automatically. Brief templates pass these paths explicitly.

- `references/CONTEXT.md` — the skill's **vocabulary** file (Matt Pocock CONTEXT.md format). Each sub-agent brief lists it as the first input; sub-agents read it before anything else to align terminology and avoid the `_Avoid_:` aliases.
- `references/decision-format.md` — **normative** authoring spec (frontmatter, edge vocabulary, slug convention, ID assignment, body sections, triple-filter, supersede mechanics, synthesis structure).
- `references/drafting-brief.md` — template the capture sub-agent receives; round-1 vs round-N>1 inputs; surgical-fix directive; required output schema.
- `references/reviewer-validator-brief.md` — mechanical checklist; spawn as `Explore`.
- `references/reviewer-auditor-brief.md` — Archive Auditor's semantic / archive-integration checklist; spawn as `general-purpose`. Includes edge-liveness, transcript-faithfulness, near-duplicate, contradiction-with-accepted, cross-archive edge detection, and edge-justification (an edge declared but not supported by the body).
- `references/reviewer-quality-brief.md` — Quality Reviewer's write-up + triple-filter + synthesis-coherence checklist; spawn as `general-purpose`.
- `references/reviewer-concision-brief.md` — Concision Reviewer's prose-tightening checklist; spawn as `general-purpose` (the reviewer needs Edit/Write authority to apply prose tightenings directly to decision files inside the worktree). Runs once as a sequential post-pass after the V/A/Q loop settles, on decision files only (not synthesis). Has narrow authority to edit prose directly; bounces back to V/A/Q only when tightening requires fact changes.

## Pre-flight

Refuse to run unless `DECISION_ARCHIVE_ROOT` is set in the environment. The variable is a **comma-separated list** of archive paths; a single path is a valid one-element list (backward-compatible).

Parse the list. For each entry: trim whitespace; verify the path exists and is a git directory (i.e., `git -C "<path>" rev-parse --git-dir` succeeds). If any entry fails, refuse to proceed and tell the user which entry is invalid.

**Destination selection.** Let `$ARCHIVE_ROOT` denote the single archive this capture session targets:

- If exactly one entry is configured, `$ARCHIVE_ROOT` is that entry. No prompt.
- If more than one entry is configured, prompt the user to pick one. Present entries as `<basename> (<path>)`, single-select. The chosen entry becomes `$ARCHIVE_ROOT` for the rest of this session.

The **archive name** (used in prompts, conversational text, and commit messages where relevant) is the basename of `$ARCHIVE_ROOT` — e.g., `/Users/foo/decision-archive` → `decision-archive`, `/Users/foo/team-a-archive` → `team-a-archive`. No archive-name configurability beyond basename.

Run `git -C "$ARCHIVE_ROOT" status --porcelain`. If the output is non-empty, refuse to proceed and tell the user to commit or stash their changes in `<basename>` first — mixing pre-existing uncommitted work with capture-produced drafts makes the diff invariant ambiguous.

**`.claude/` gitignore precondition.** Capture writes worktrees under `$ARCHIVE_ROOT/.claude/worktrees/`, so the archive's `.gitignore` must ignore `.claude/`. Verify by inspecting the file directly — `grep -qE '^/?\.claude/?$' "$ARCHIVE_ROOT/.gitignore"` (matches `.claude`, `.claude/`, `/.claude`, `/.claude/`). Do **not** use `git check-ignore` here: on a fresh archive where `.claude/` hasn't been materialized yet, its behavior is version-dependent and can refuse spuriously. If the `.gitignore` file is missing or the entry is absent, refuse to proceed and tell the user to run, from the archive root, `echo '.claude/' >> .gitignore`, commit the change, and re-invoke capture-decision.

Capture `base_sha = git -C "$ARCHIVE_ROOT" rev-parse HEAD`. The worktree itself is created at the end of Step 1, once the slug is confirmed.

## Step 1 — Scope, slug, and worktree

Main proposes **scope** — a cut of the conversation — not a content summary. Example proposals:

- "Capture from the start of the session, or from when we shifted to discussing the indexer design?"
- "The scope I see is roughly turns 5 through 30 — does that match what you want captured?"

User confirms or amends scope. One amend round is allowed; after that, scope is committed and any further refinement happens at the human gate.

This step also nails the **slug** for the transcript filename. Main proposes one (kebab-case, descriptive, namespaced by topic). User can override.

Once `<slug>` is confirmed, generate a fresh ULID and take its first 6 characters as `<short-ulid>`. Then create the per-session worktree from `base_sha`:

```
WORKTREE="$ARCHIVE_ROOT/.claude/worktrees/capture-<YYYYMMDD-HHMMSS>-<short-ulid>-<slug>"
BRANCH="capture/<YYYYMMDD-HHMMSS>-<short-ulid>-<slug>"
git -C "$ARCHIVE_ROOT" worktree add -b "$BRANCH" "$WORKTREE" "$base_sha"
```

`<YYYYMMDD-HHMMSS>` is the current date+time; `<short-ulid>` is the 6-char Crockford prefix that breaks ties when two captures land in the same second. All subsequent writes, edits, `git diff`, `git add`, and `git commit` happen **inside the worktree** — never in `$ARCHIVE_ROOT` directly. All `git diff` calls in this skill use the **single-ref** form `git diff <base_sha>` (run with `git -C "$WORKTREE" diff "$base_sha"`) — committed, staged, and unstaged changes since base. This is the diff invariant; reviewers always see the cumulative change, never the per-round delta. The `.claude/` directory must be gitignored in the archive repo so worktree contents do not appear as untracked files in the live clone.

**Untracked-file diff visibility — `git add -N`.** New files created by capture (decisions, synthesis, transcripts) are untracked and would otherwise not appear in `git diff <base_sha>` until staged. To keep reviewers seeing one canonical cumulative diff, the capture sub-agent runs `git -C "$WORKTREE" add -N decisions/ synthesis/ transcripts/` after each file write (or once before returning — agent's choice as long as it happens before control returns to main). `-N` introduces the path to the index without staging content, so the file shows up in `git diff` as an addition while remaining unstaged for content purposes. On discard, `git worktree remove --force` removes the worktree directory and its index together — no special cleanup is needed.

## Step 2 — Transcript dump

Main writes the in-scope conversation **faithfully** to:

```
$WORKTREE/transcripts/transcript-<YYYYMMDD-HHMMSS>-<short-ulid>-<slug>.md
```

Where `$WORKTREE` is the per-session worktree created in Pre-flight; `<YYYYMMDD-HHMMSS>`, `<short-ulid>`, and `<slug>` match the worktree's branch name.

Format: `user:` / `assistant:` prefixed turns. No summarization, no editorial paraphrase, no compression beyond what main's own context already imposes. If main's context has been auto-compacted, dump what main has and note the fidelity ceiling in a footer comment in the transcript file (this is a known limitation, not a defect).

The transcript file is an **unstaged** addition. It will travel with the decisions through the human gate:

- On `accept` → committed alongside the decisions.
- On `discard` → file is deleted (along with the unstaged decision/synthesis edits).

Main does **not** pass a summary to sub-agents. Briefs reference the transcript path; sub-agents read the file themselves.

## Step 3 — Recall research (one-shot)

Spawn the **recall sub-agent** as `Explore`. The capture-time recall task is the same shape as a mid-session lookup — compose grep patterns against the archive, return a ranked digest — and Explore is the matching weight. The cross-body reasoning happens later inside the capture agent (which is `general-purpose`); the recall agent's job is pattern-matching plus ranking, no more.

The recall is **scoped to the selected `$ARCHIVE_ROOT` only** — it does not fan out across the other archives configured in `$DECISION_ARCHIVE_ROOT`. The sub-agent receives only `$ARCHIVE_ROOT` (and `$WORKTREE`, its checkout), not the full list.

Brief contents:

- Operating root: `$WORKTREE` — the per-session worktree from Pre-flight. **All reads and writes happen here.** The live archive clone at `$ARCHIVE_ROOT` is not touched by sub-agents during the iteration loop.
- Absolute path to recall patterns: `<this-skill-dir>/references/recall-patterns.md` — the local copy bundled in this skill. (Path coupling to the sibling `recall-decision` skill was removed; a future skill-reviewer meta skill will reconcile drift between the two copies.)
- Path to the transcript file from Step 2 (lives inside `$WORKTREE/transcripts/`).
- Instructions: "Read the transcript. Identify likely edge candidates — decisions this batch may `depends-on`, `informs`, `supersedes`, or be `synthesized` into. Use the canonical Bash patterns in the recall-patterns file whose absolute path is in this brief. Return a ≤50-line **text** digest, one line per candidate, in the format `<id> <kind> <slug> | status=<status> tags=[...] match=<kind|distance> | <one-line-relevance>` (the same shape recall-decision uses; the recall-patterns reference describes it under `digest assembly format`). Do NOT return JSON; do NOT return file bodies."
- Digest schema is strict; no full bodies in the digest.

Recall runs **once**, not per iteration round. The set of related existing decisions does not change between rounds; re-running would waste tokens and add latency.

Hold the returned digest as `recall_digest`. It is passed verbatim to every round of the capture agent's brief.

**Silent-failure mode.** If the recall sub-agent returns nothing, errors out, or returns content that does not contain at least one digest-shaped line (no `<id> <kind> <slug> | ...` line matching the format above, and not a recognized "no matches" sentence), capture does **not** halt. Set `recall_digest` to an empty digest (zero candidates) and proceed to Step 4. Record the degraded recall as a finding-shaped note attached to the human-gate summary in Step 5: "Recall research returned degraded output (malformed / empty / errored); capture proceeded without related-decision context." The user is informed at the gate; they may `discard` and re-run if the missing context matters. Do not re-spawn the recall agent inside the same session — one degraded result is a signal, not a retry trigger.

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

- New decision files in `decisions/<ULID>-<namespace>-<slug>.md` with `status: accepted`. The capture agent generates a fresh ULID per decision at draft time.
- An optional synthesis file in `synthesis/<ULID>-<namespace>-<slug>.md`.
- Edits to existing decisions to flip `status: accepted` → `status: superseded` when the batch supersedes them.

Capture agent returns a tight JSON digest (≤15 lines) — see `drafting-brief.md` for the schema. The digest never contains file bodies; the bodies are on disk.

**Escape hatches from capture agent.** Two distinct codes; either exits the loop immediately and routes to the human gate with the agent's evidence. Do not iterate.

- `status: "no_decisions_found"` — fires in **round 1** when the capture agent determines the session contains no capture-worthy material at all (no closed-off forks meeting the triple-filter, transcript too thin, scope confirmation captured the wrong span). Human handling: usually `discard`; occasionally `request changes` to expand scope.
- `status: "scope_unsalvageable"` — fires in **round 2 or 3** when, after at least one drafting attempt, the capture agent determines the scope cannot yield clean decisions even with surgical fixes (the original approach is fundamentally wrong, not just defective in specific places). Human handling: usually `discard` and re-scope; occasionally `request changes` to restructure the scope.

The human-gate summary in Step 5 branches on the code so the user gets the right next-action suggestion.

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
- `quality_note` — substance-adjacent advisory findings (sub-substantive thread fields, thin assumptions, dangling note references); **advisory only, never gates**. **Quality Reviewer only.** Prose-style concerns belong to the Concision Reviewer in Step 4.5, not here.
- `nit` — minor structural findings (tag count, tag boilerplate); never gates. Filled by Validator or Quality Reviewer.

Reviewers do **not** vote: any `verdict` field a reviewer emits is treated as an ignored courtesy field. Main computes the loop verdict from field occupancy.

### Verdict aggregation (mechanical — main applies, reviewers never vote)

After collecting all three reviewer JSON outputs, apply this rule in order:

1. If any reviewer's findings JSON is malformed (missing required field, wrong type, non-parseable), **re-spawn that reviewer once** with the same brief plus a stricter "your previous output was malformed; conform to the schema" preamble. If the second attempt is still malformed, **escalate to the human**. Verdict-validation re-spawns do not count against the 3-round cap. Do not re-spawn the capture agent on a reviewer-validation failure — the reviewer is the broken component.

2. Once all three outputs are valid, compute the verdict from field occupancy across all three:
   - Any `blocking` finding (from any reviewer — includes triple-filter failures folded in by the Quality Reviewer) → **adjust** if rounds remain, else **escalate**.
   - Any `discrepancy` finding (Archive Auditor only) → **adjust** if rounds remain, else **escalate**.
   - Only `quality_note` and/or `nit` findings → **pass** → exit V/A/Q loop and proceed to Step 4.5 (Concision post-pass).
   - No findings at all → **pass** → exit V/A/Q loop and proceed to Step 4.5 (Concision post-pass).

Cap-exhaustion with outstanding `blocking` or `discrepancy` does **not** run the Concision post-pass — it routes directly to the human gate with the un-addressed findings. Concision is only meaningful on a draft the V/A/Q trio considered acceptable.

**`discrepancy` has teeth.** It is **not** advisory. Four specific structural findings from the Archive Auditor are categorised as `discrepancy` (forcing another round, not just a note):

- **Edge-liveness violation.** A new decision declares `depends-on: [X]` where `X` is `superseded` and an active successor `Y` exists, *and* the new decision is not itself the supersession of `X`. The legitimate pattern is "A supersedes B → A depends-on B"; the suspect pattern is "C depends-on B (where B is superseded by D, C is not the supersession of B)". The Archive Auditor calls these out and the capture agent rewires the edge in the next round.
- **Transcript-faithfulness gap.** A `Chosen` or `Rationale` assertion in a draft is not supported by anything in the transcript. The draft drifted from the conversation. Re-draft.
- **Near-duplicate of an existing accepted decision.** A draft substantively re-decides what an `accepted` decision already settles without superseding it.
- **Contradiction with an existing accepted decision.** A draft's `Chosen` is incompatible with the `Chosen` of an existing `accepted` decision, without superseding it. The capture agent must either add the existing decision to `supersedes` (and flip its status), re-draft to not contradict, or drop the new decision.

These four are blocking-grade in their effect on the loop. Calling them `discrepancy` rather than `blocking` is a categorisation distinction (they're archive-integration concerns rather than mechanical defects), not an advisory distinction.

**`quality_note` is genuinely advisory.** Voice, length, stylistic preferences, transcript-substance nuances. The Quality Reviewer can flag these; main records them for the human gate's summary but they do not force another round. If they did, the loop would oscillate on subjective preferences. **Prose tightening is no longer a Quality concern** — it belongs to the Concision Reviewer in Step 4.5.

### Round 2 and Round 3

If the verdict is `adjust` and rounds remain, spawn a fresh capture agent (new context — no carry-over from the prior agent's memory). Brief = `references/drafting-brief.md` with round-N>1 inputs added (not substituted):

- All round-1 inputs (unchanged)
- The aggregated findings from all three reviewers
- The **surgical-fix mode directive** — its canonical text lives in `references/drafting-brief.md` under "Surgical-fix mode directive (round 2+ — apply verbatim)". Main pastes that block verbatim into the round-N>1 brief.

Then spawn the three reviewers in parallel (identical brief — no awareness of round number).

After Round 3, exit the loop regardless of verdict. Carry the final state to the human gate (skipping the Concision post-pass — see above).

## Step 4.5 — Concision post-pass (sequential, runs once)

Runs once, only after the V/A/Q loop **passed** (not on cap-exhaustion). Mandate: prose-only tightening on **decision files**. Synthesis is out of scope — synthesis prose is unchanged from what V/A/Q signed off on. Triple-filter, frontmatter, edges, structural skeleton, and all facts in `Chosen` / `Rationale` / `Alternatives` are untouchable.

Spawn one **Concision Reviewer** as `general-purpose` (the reviewer applies edits directly to decision files inside the worktree, which Explore cannot do). Brief = `references/reviewer-concision-brief.md`. Inputs:

- `base_sha`
- `$WORKTREE`
- `git -C "$WORKTREE" diff "$base_sha"` — the V/A/Q-approved cumulative change
- Path to `references/CONTEXT.md`
- Path to `references/decision-format.md`
- Path to the transcript (so the reviewer can confirm a proposed tightening doesn't drift from session substance)

The Concision Reviewer is **the writer**, not just a flagger. When its proposed rewrites are pure prose (no fact changes), it edits decision files directly inside `$WORKTREE` and surfaces them in `nit` as a record of what changed. When it determines that tightening **requires** a fact change — a sentence cannot be tightened without altering what `Chosen`, `Rationale`, or `Alternatives` asserts — it does **not** edit; it surfaces the case in `blocking` with the precise rationale.

Aggregate Concision's output:

- `blocking` empty → accept the now-tightened draft and proceed to Step 5 (human gate). Any `nit` items are folded into the gate summary as Concision edits made.
- `blocking` non-empty → bounce back to a **+1 V/A/Q round** (not a fresh 3-round budget — exactly one additional round). The bounce-back round receives the Concision findings as additional finding-shaped input. After this +1 V/A/Q round settles, re-run the Concision post-pass once.
- If the second Concision pass also returns `blocking` non-empty → **escalate to the human gate** with the un-tightened draft and both Concision bounce notes. Do not loop a third time.

Concision never runs more than twice per capture session. The bounce-back budget is bounded: 3-round V/A/Q + 1 bounce-back V/A/Q + 2 Concision passes is the hard worst case.

Concision **does not** edit synthesis files, frontmatter, or edge fields. The Validator's body-edit-detection check still applies on the next V/A/Q round if Concision touches anything outside its mandate — that would itself surface as a `blocking` from the Validator.

## Step 5 — Human gate

Present to the user:

- **Destination archive** — the basename of `$ARCHIVE_ROOT` selected in Pre-flight.
- **Files touched** — bulleted list of paths (decisions, synthesis, supersede flips, transcript), each one inspectable via `git diff` or in their editor.
- **Findings summary** — collapsed by category:
  - Outstanding `blocking` items (if any survived to cap-exhaustion or to a second Concision bounce) — show each finding's text and `path:line` cite.
  - Outstanding `discrepancy` items (if any) — same shape.
  - `quality_note` items — terse, advisory.
  - `nit` items — count only, not enumerated. Includes any Concision prose edits applied during Step 4.5.
- **Degraded-input notes** — if recall research returned malformed/empty/errored output, surface a one-line warning here ("Recall research returned degraded output; capture proceeded without related-decision context").
- **Escape-hatch branch** — if the capture agent exited via `no_decisions_found` or `scope_unsalvageable`, present the code, the agent's evidence, and a tailored next-action suggestion: for `no_decisions_found`, suggest `discard` or `request changes` to expand scope; for `scope_unsalvageable`, suggest `discard` and re-scope, or `request changes` to restructure.
- **The base SHA**, so the user can independently run `git diff <base_sha>` to inspect.
- **No file bodies in main's context.** Main does not Read the drafts. The user inspects via git.

Wait for the user's verdict. Four options:

- `accept` → Step 6 (commit).
- `accept with edits` → user edits on disk in their editor first, then says `done` or `commit`. Main commits the current disk state (which includes their edits). The diff invariant still holds because their edits are part of `git diff <base_sha>`.
- `request changes [reason]` → re-enter the iteration loop with the user's reason injected as a finding-shaped input (in `blocking` if specific, in `discrepancy` if structural). If the 3-round cap is already exhausted, `request changes` is the explicit cap-raise: it counts as a new round. If that round's V/A/Q verdict is `pass`, the Concision post-pass runs as usual (so the worst case remains bounded: 3 V/A/Q rounds + 1 user-raised round + Concision passes). The user may instead `accept with edits` (take over manually) or `discard`.
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

- decisions/<ULID>-<namespace>-<slug>.md
- decisions/<ULID>-<namespace>-<slug>.md
- synthesis/<ULID>-<namespace>-<slug>.md
- transcripts/transcript-<timestamp>-<short-ulid>-<slug>.md
- supersede flips: <ULID>, <ULID>

Refs: transcript-<timestamp>-<short-ulid>-<slug>
```

The commit lands on the `capture/<timestamp>-<short-ulid>-<slug>` branch only. Do **not** merge to `main`, do **not** push, do **not** remove the worktree. The user merges manually when ready (e.g. `gh pr create --base main` from the worktree, or `git checkout main && git merge capture/<timestamp>-<short-ulid>-<slug>` in the parent repo). The post-commit pre-merge window before manual merge gives the user a chance to revisit the capture in their editor before it lands on main.

After committing, tell the user: the worktree path, the branch name, and the suggested merge command. Do not act on their behalf.

### On discard:

Atomic rollback: remove the worktree and its branch in one operation.

```
git -C "$ARCHIVE_ROOT" worktree remove --force "$WORKTREE"
git -C "$ARCHIVE_ROOT" branch -D "$BRANCH"
```

This removes the entire worktree directory (including all unstaged decision/synthesis edits and the transcript) and deletes the per-session branch. After rollback, `$ARCHIVE_ROOT` is byte-identical to the pre-Pre-flight state. No prompt — discard is a single atomic operation.

## Escape hatches and edge cases

- **`no_decisions_found` from capture agent (round 1).** Exit loop, surface to human with the agent's evidence. The session has no capture-worthy material at all. Human-gate summary suggests `discard` or `request changes` to expand scope.
- **`scope_unsalvageable` from capture agent (round 2+).** Exit loop, surface to human with the agent's evidence. The scope cannot yield clean decisions even with surgical fixes. Human-gate summary suggests `discard` and re-scope, or `request changes` to restructure.
- **Verdict-validation failure on reviewer JSON.** Re-spawn that reviewer once (does not count against the 3-round cap). Second failure → escalate to human with the malformed verdicts and the current diff. Do not re-spawn the capture agent — the reviewer is the broken component.
- **3-round cap exhaustion with outstanding `blocking` or `discrepancy`.** Cap exhaustion routes directly to the human gate with the current on-disk state and the un-addressed findings clearly labeled. Do not ask to extend rounds before presentation. The user may raise the cap via `request changes` post-gate, which counts as a new iteration round.
- **User says `request changes` after cap-exhaustion.** Do not silently restart the loop. Ask explicitly: "The 3-round cap is exhausted. Do you want to raise the cap and retry, or would you prefer to take over manually?"
- **Capture agent writes a file outside `decisions/` or `synthesis/`.** Validator catches this as `blocking`. The capture-agent brief's boundaries section forbids it.
- **Concision bounces twice.** If the post-pass returns `blocking` (fact-change-required) twice in a row, escalate to the human gate with the un-tightened V/A/Q-approved draft plus both Concision bounce notes. Do not run Concision a third time.
- **Concision edits outside its mandate.** If the Concision Reviewer touches synthesis, frontmatter, edges, or structure, the bounce-back V/A/Q round catches it via the Validator's body-edit-detection check. Treat as a normal `blocking` finding in that round.

## Borrowed disciplines (inline reference)

From `dev/skills/implement-with-review-loop/` — the following patterns transfer verbatim in spirit, adapted for the decision-archive domain:

- **Pre-flight clean-tree check.** Mixing pre-existing uncommitted changes with capture-produced ones makes the diff ambiguous.
- **Single-ref diff invariant.** `git diff <base_sha>` only. Never the per-round delta. Reviewers always evaluate the cumulative change.
- **Stateless reviewers.** Each reviewer spawn re-derives the verdict from scratch. No awareness of round number. Prevents drift.
- **Verdict validation.** Re-spawn once on malformed JSON; escalate on second failure. The reviewer is the broken component, not the change.
- **Hard cap with escalation.** Three rounds. Cap exhaustion is not failure — it routes to the human gate with the current state preserved on disk.
- **Additive inputs on retry.** Round-N>1 inputs add to round-1 inputs; they do not replace them. The transcript and recall digest persist across rounds.
- **Escape hatch from the worker.** `no_decisions_found` (round 1) and `scope_unsalvageable` (round 2+) are the capture agent's two equivalents of `plan_broken`. Do not iterate when the plan itself is broken.
- **Surgical-fix mode directive.** Verbatim in the round-N>1 brief. Prevents oscillation between drafting strategies.

The pattern is borrowed inline, not factored. Factoring waits for a third instance of the worker-plus-reviewer pattern to appear.
