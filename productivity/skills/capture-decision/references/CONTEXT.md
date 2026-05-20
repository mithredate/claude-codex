# capture-decision

Vocabulary used by capture-decision's sub-agents (capture agent, validator, archive auditor, quality reviewer, concision reviewer). Read this first — when multiple words exist for one concept, the one defined here is the one to use. The `_Avoid_:` aliases are not synonyms; they carry different connotations and should not appear in drafts or findings.

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
A typed relationship between archive files, drawn from a fixed vocabulary: `depends-on`, `supersedes`, `informs`, `synthesizes`. Edges are **intra-archive only** — every target ID in an edge field must refer to a file inside the current archive. Cross-archive references stay as prose in the body, never as structured edges.
_Avoid_: Link, reference, relation.

**ULID**:
The 26-character Crockford base32 identifier used as the primary ID for both decisions and synthesis files. Lexicographically sortable by creation time (the first 48 bits are a millisecond timestamp), globally unique across archives, opaque to humans. Filenames take the form `<ULID>-<namespace>-<slug>.md`; the `id:` frontmatter field holds the same string; edge target lists are ULID strings (no zero-padded integers).
_Avoid_: UUID, integer ID, sequential ID, numeric ID.

**Tag**:
A free-form lowercase kebab-case label in a decision's frontmatter, used for topical retrieval via grep.
_Avoid_: Label, category, keyword.

**Namespace**:
The lowercase kebab-case prefix on decision and synthesis slugs (e.g., `decision-archive-` in `decision-archive-two-skill-split`). Identifies which archive a decision belongs to. Distinct from the **archive name** (which is the basename of the archive path); the namespace is the slug prefix used inside files, while the archive name appears in prompts and commit messages.
_Avoid_: Prefix, project tag.

**Archive name**:
The basename of `$ARCHIVE_ROOT` — e.g., `/Users/foo/decision-archive` → `decision-archive`, `/Users/foo/team-a-archive` → `team-a-archive`. Used in user-facing prompts (destination selection), conversational text ("captured to <basename>"), and commit messages where helpful. Not configurable beyond basename.
_Avoid_: Archive label, archive title, archive id.

**Multi-archive**:
`$DECISION_ARCHIVE_ROOT` is a comma-separated list of archive paths; a single path is the one-element case. When more than one is configured, Pre-flight prompts the user to pick one destination archive for this session. The chosen path becomes `$ARCHIVE_ROOT` and is the only archive touched by the session — recall is scoped to it; edges are scoped to it.
_Avoid_: Multiple archives, archive list (informal), federated archive.

### Capture flow

**Scope confirmation**:
The one-turn exchange where main proposes which span of the conversation to capture and the user confirms or amends. Main proposes *scope*, not content.
_Avoid_: Summary confirmation, content review.

**Worktree**:
The dedicated per-session git worktree at `$ARCHIVE_ROOT/.claude/worktrees/capture-<YYYYMMDD-HHMMSS>-<slug>/` on a fresh branch `capture/<YYYYMMDD-HHMMSS>-<slug>`. All capture-time reads, writes, and `git diff` calls happen inside the worktree; the live archive clone is never touched during the iteration loop.
_Avoid_: Sandbox, draft directory, capture directory.

**Transcript**:
The faithful `user:`/`assistant:` dump of the in-scope conversation written to `transcripts/transcript-<timestamp>-<slug>.md`; committed on `accept`, deleted on `discard`. The source of truth for what was decided.
_Avoid_: Transcript scratch file, transcript summary, session notes, conversation dump.

**Iteration loop**:
The bounded retry mechanism inside this skill — up to 3 rounds of (capture agent → three parallel reviewers → verdict), optionally followed by a +1 bounce-back round if the Concision post-pass needs fact changes.
_Avoid_: Review cycle, retry loop, feedback loop.

**Concision post-pass**:
The sequential single-reviewer step that runs once after the V/A/Q iteration loop **passes** (not on cap-exhaustion). Tightens prose in decision files only — never synthesis, never frontmatter, never edges, never facts. If tightening requires a fact change, Concision flags it as `blocking` and the work bounces back for a +1 V/A/Q round; a second Concision bounce escalates to the human gate. Capped at two Concision passes per session.
_Avoid_: Polish pass, copyedit, prose review, style review.

**Bounce-back round**:
The single additional V/A/Q round triggered when the Concision post-pass returns `blocking`. Not a fresh 3-round budget — exactly one additional round. After it settles, Concision re-runs once.
_Avoid_: Extra round, retry, +1 iteration.

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
The four sub-agents that evaluate the capture agent's on-disk drafts: the three parallel V/A/Q reviewers (Validator, Archive Auditor, Quality Reviewer) running each iteration round, plus the **Concision Reviewer** that runs once sequentially after V/A/Q passes.
_Avoid_: Critics, checkers, linters.

**Validator**:
The mechanical reviewer (`Explore`) that checks frontmatter, slugs, IDs, edge schema, and target existence.
_Avoid_: Linter, schema checker.

**Archive Auditor**:
The semantic reviewer (`general-purpose`) that checks for contradictions with accepted decisions, near-duplicates, transcript-faithfulness, and edge-liveness.
_Avoid_: Consistency checker, conflict detector.

**Quality Reviewer**:
The write-up reviewer (`general-purpose`) that enforces the triple-filter, required sections, transcript-substance faithfulness, and synthesis coherence. Does **not** own prose tightening (that's Concision's job).
_Avoid_: Editor, critic.

**Concision Reviewer**:
The post-pass reviewer (`general-purpose`) that tightens prose in decision files after V/A/Q passes. The Concision Reviewer is **the writer** for pure-prose tightening: it edits decision files directly inside the worktree (requiring Edit/Write authority, which is why it is `general-purpose` and not `Explore`) and reports edits in `nit`. When tightening would require changing a fact in `Chosen` / `Rationale` / `Alternatives`, it does not edit — it flags `blocking` and the work bounces back for a +1 V/A/Q round. Never edits synthesis, frontmatter, edges, or structural skeleton.
_Avoid_: Copyeditor, prose reviewer, polish agent, style reviewer.

### Discipline

**Triple-filter**:
The three criteria a decision must satisfy to merit a file: hard to reverse, surprising without context, and a real trade-off (genuinely-considered alternatives existed).
_Avoid_: Decision criteria, capture gate.

**Curation gate**:
The end-to-end checkpoint where proposed content becomes committed history — scope confirmation + V/A/Q reviewer loop + Concision post-pass + human approval + commit.
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
- **"ID"** is no longer a zero-padded integer (`0014`, `0042`). Resolved: the ID is a **ULID** — a 26-char Crockford base32 string. Any integer ID encountered in the archive is legacy and would be migrated under a separate one-shot; the skill describes the target state. The Validator catches integer IDs in new files as legacy violations.
- **"Cross-archive reference"** has no structured form. Resolved: edges are intra-archive only. If a transcript mentions "this builds on a decision in the team-A archive," the reference stays as prose in `Rationale` or `Note`. The Archive Auditor flags any cross-archive ULID in an edge field as `blocking`.
