# recall-decision

Vocabulary used by recall-decision's sub-agent. Read this first — when multiple words exist for one concept, the one defined here is the one to use. The `_Avoid_:` aliases are not synonyms; they carry different connotations and should not appear in the digest or any return message.

This is the **skill's** vocabulary, not the archive's. The decision archive being queried may carry its own `CONTEXT.md` describing archive-internal collaborator terms; that one is separate from this. This file is the vocabulary the sub-agent running this skill shares with main.

## Language

### Archive content

**Decision**:
A closed-off fork where alternatives were weighed, one was chosen, and the choice has meaningful cost-to-reverse. Status is either `accepted` (live) or `superseded` (replaced).
_Avoid_: ADR, record, note.

**Synthesis**:
A per-session narrative file integrating one or more decisions, with optional threads spawned for later grilling.
_Avoid_: Summary, retrospective, overview.

**Edge**:
A typed relationship between archive files, drawn from a fixed vocabulary: `depends-on`, `supersedes`, `informs`, `synthesizes`. Declared on the source file; points at the target by ULID. **Intra-archive only** — edges never cross from one archive to another.
_Avoid_: Link, reference, relation.

**ULID**:
The 26-character Crockford base32 identifier used as a decision or synthesis ID (e.g., `01JX4F8K2MABCDEFGHIJKLMNOP`). Globally unique across archives and lexicographically sortable by creation time, so a later ULID is the more recent decision. Filenames are `<ULID>-<slug>.md`; frontmatter `id:` holds the ULID; all edge references are ULID-valued.
_Avoid_: ID number, integer ID, decision number.

**Tag**:
A free-form lowercase kebab-case label in a decision's frontmatter, the primary axis for topical grep-based retrieval. Tag-match ranks above title-match, which ranks above body-match.
_Avoid_: Label, category, keyword.

### Archives

**Archive**:
A single decision-archive clone. `$DECISION_ARCHIVE_ROOT` is a comma-separated list of archive paths; each entry is one archive. A single-path value is a valid one-element list (the common case).
_Avoid_: Repo, store, vault.

**Archive name**:
The **basename** of an archive's path (e.g., `/Users/foo/decision-archive` → `decision-archive`). Used in the multi-select prompt and as the digest line's `[<archive>]` prefix. Not configurable — the basename is the rule.
_Avoid_: Archive alias, archive label, archive id.

**Multi-archive**:
The configuration where `DECISION_ARCHIVE_ROOT` lists more than one path. The skill prompts the user to multi-select which archives to query before dispatching the recall agent; the digest annotates each line with the archive basename. Edges remain strictly intra-archive — the sub-agent never traverses an edge across archive boundaries.
_Avoid_: Cross-archive, federated search.

### Lookup flow

**Mid-session lookup**:
The user asking "what do we have on X?" mid-grill, which triggers this skill. The specific in-grill use case, not generic search.
_Avoid_: Search, query.

**Supersession**:
The replacement mechanism — old decision's `status` is `superseded`, new decision declares a `supersedes` edge pointing at it. Default status filter is `accepted`; lift the filter when the query traverses a `supersedes` edge in either direction or asks about retired decisions explicitly.
_Avoid_: Override, revision, update.

### Agents

**Main**:
The top-level Claude session that spawns the recall agent. Never reads the archive at scan-time; only reads a specific file when the user explicitly asks for it after seeing the digest.
_Avoid_: Orchestrator, coordinator.

**Recall agent**:
A sub-agent (default `Explore`; escalate to `general-purpose` for cross-body reasoning) that runs grep and edge-traversal patterns and returns a ranked ≤50-line digest. Never returns full decision bodies.
_Avoid_: Search agent, retriever.

**Digest**:
The ranked output a recall sub-agent returns to main: a list of decision matches, capped at ≤50 lines, never containing full decision bodies. Each entry carries `{id, kind, slug, title, status, tags, match_kind | distance}` plus a one-line relevance note. Main never reads bodies directly — the digest is the entire context surface.
_Avoid_: Result list, recall output, summary.

### Discipline

**Context hygiene**:
The principle that all research and retrieval happens in spawned sub-agents so main's context stays clean. The recall agent returns a digest, never bodies; the digest is metadata about candidates, not content from them.
_Avoid_: Context isolation, context separation.

**Retrieval miss**:
The failure mode where the archive contains the relevant decision but grep didn't find it — tags wrong, title doesn't include the search term, body uses different language than the query.
_Avoid_: Generic "miss".

**Traversal miss**:
The failure mode where grep found the relevant decision but the digest didn't follow its edges to surface the connected decisions the user actually needs.
_Avoid_: Generic "miss".

Sibling failure mode `capture miss` (the decision was never recorded) is the concern of `capture-decision`; see `../capture-decision/...` for the authoring side. The full taxonomy lives in `/Users/mehrdad.hedayati/projects/decision-archive/CONTEXT.md` (archive's master glossary).

## Flagged ambiguities

- **"Search" / "query"** are too generic. Resolved: the in-grill use case is *mid-session lookup*. Use the specific term in any user-facing message; reserve "search" / "query" for internal mechanics (grep modes, pipelines).
- **"Body"** in this skill's context is what a decision file contains *below* the frontmatter. The recall agent never returns it; main never reads it as part of recall. The user obtains a body only by explicitly asking main to Read a specific file after seeing the digest.
