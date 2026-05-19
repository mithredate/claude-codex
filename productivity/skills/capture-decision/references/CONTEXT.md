# capture-decision

Vocabulary used by capture-decision's sub-agents (capture agent, validator, archive auditor, quality reviewer). Read this first — when multiple words exist for one concept, the one defined here is the one to use. The `_Avoid_:` aliases are not synonyms; they carry different connotations and should not appear in drafts or findings.

This is the **skill's** vocabulary, not the archive's. The decision archive being captured to may carry its own `CONTEXT.md` describing archive-internal collaborator terms; that one is separate from this. This file is the vocabulary the sub-agents running this skill share.

## Language

### Archive content

**Decision**:
A closed-off fork where alternatives were weighed, one was chosen, and the choice has meaningful cost-to-reverse.
_Avoid_: ADR, record, note.

**Synthesis**:
A per-session narrative file integrating one or more decisions and any threads spawned for later grilling.
_Avoid_: Summary, retrospective, overview.

**Thread**:
A topic worth grilling later, listed on a synthesis as `spawns-threads` but deliberately not grilled now.
_Avoid_: Todo, follow-up, open question.

**Edge**:
A typed relationship between archive files, drawn from a fixed vocabulary: `depends-on`, `supersedes`, `informs`, `synthesizes`.
_Avoid_: Link, reference, relation.

**Tag**:
A free-form lowercase kebab-case label in a decision's frontmatter, used for topical retrieval via grep.
_Avoid_: Label, category, keyword.

**Namespace**:
The lowercase kebab-case prefix on decision and synthesis slugs (e.g., `decision-archive-` in `decision-archive-two-skill-split`). Identifies which archive a decision belongs to, supports multi-archive scenarios in the future.
_Avoid_: Prefix, project tag.

### Capture flow

**Scope confirmation**:
The one-turn exchange where main proposes which span of the conversation to capture and the user confirms or amends. Main proposes *scope*, not content.
_Avoid_: Summary confirmation, content review.

**Worktree**:
The dedicated per-session git worktree at `$DECISION_ARCHIVE_ROOT/.claude/worktrees/capture-<YYYYMMDD-HHMMSS>-<slug>/` on a fresh branch `capture/<YYYYMMDD-HHMMSS>-<slug>`. All capture-time reads, writes, and `git diff` calls happen inside the worktree; the live archive clone is never touched during the iteration loop.
_Avoid_: Sandbox, draft directory, capture directory.

**Transcript**:
The faithful `user:`/`assistant:` dump of the in-scope conversation written to `transcripts/transcript-<timestamp>-<slug>.md`; committed on `accept`, deleted on `discard`. The source of truth for what was decided.
_Avoid_: Transcript scratch file, transcript summary, session notes, conversation dump.

**Iteration loop**:
The bounded retry mechanism inside this skill — up to 3 rounds of (capture agent → three parallel reviewers → verdict).
_Avoid_: Review cycle, retry loop, feedback loop.

**Human gate**:
The single explicit approval step after the iteration loop terminates, where the user replies `accept` / `accept with edits` / `request changes` / `discard`.
_Avoid_: Approval step, review, sign-off.

**Supersession**:
Replacing an earlier decision with a new one by flipping the old to `status: superseded` and pointing the new at it via a `supersedes` edge. Editing in place destroys history; supersession preserves it.
_Avoid_: Override, revision, update.

**Rewind**:
The user's act of returning to an old decision to re-evaluate whether its assumptions still hold. Surfaced in `drafting-brief.md` as "rewind candidate" — a decision the new batch may want to revisit.
_Avoid_: Revisit, audit.

### Agents

**Main**:
The top-level Claude session orchestrating this skill. Coordinates sub-agents but never reads decision bodies or transcript turns into its own context.
_Avoid_: Orchestrator, coordinator.

**Capture agent**:
A sub-agent (`general-purpose`) that drafts decision and synthesis files directly to disk as unstaged changes inside the per-session worktree.
_Avoid_: Drafting agent, writer agent.

**Reviewer agents**:
The three parallel sub-agents — Validator, Archive Auditor, Quality Reviewer — that evaluate the capture agent's on-disk drafts each iteration round.
_Avoid_: Critics, checkers, linters.

**Validator**:
The mechanical reviewer (`Explore`) that checks frontmatter, slugs, IDs, edge schema, and target existence.
_Avoid_: Linter, schema checker.

**Archive Auditor**:
The semantic reviewer (`general-purpose`) that checks for contradictions with accepted decisions, near-duplicates, transcript-faithfulness, and edge-liveness.
_Avoid_: Consistency checker, conflict detector.

**Quality Reviewer**:
The write-up reviewer (`general-purpose`) that enforces the triple-filter, required sections, and synthesis coherence.
_Avoid_: Editor, critic.

### Discipline

**Triple-filter**:
The three criteria a decision must satisfy to merit a file: hard to reverse, surprising without context, and a real trade-off (genuinely-considered alternatives existed).
_Avoid_: Decision criteria, capture gate.

**Curation gate**:
The end-to-end checkpoint where proposed content becomes committed history — scope confirmation + three-reviewer pass + human approval + commit.
_Avoid_: Approval workflow, review process.

**Context hygiene**:
The principle that all research and retrieval happens in spawned sub-agents so main's context stays clean.
_Avoid_: Context isolation, context separation.

**Disk-as-artifact**:
The discipline that during the iteration loop the real drafts are the unstaged files on disk; reviewers and the human inspect them via `git diff`, not via chat messages.
_Avoid_: Working tree drafts, on-disk drafts.

## Flagged ambiguities

- **"Draft"** is overloaded. Resolved: the on-disk unstaged files are the **drafts** (see *disk-as-artifact*). The JSON digests exchanged between main and the capture agent are *metadata about the drafts*, not the drafts themselves.
- **"Proposed"** is not a status. Resolved: the lifecycle is two-state — `accepted` and `superseded`. There is no `proposed`. The *curation gate* is the only gate; there is no "sleep on it" buffer.
- **"ADR"** is not a synonym for **decision**. ADRs live per-repo and lack the `edges` and `assumptions` fields. Flag the divergence if a reader brings ADR expectations.
