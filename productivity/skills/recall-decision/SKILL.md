---
name: recall-decision
description: >-
  Surface relevant prior decisions from the user's decision archive(s) mid-session via a sub-agent that returns a ranked digest. Trigger on lookup phrasings like "what do we have on X?", "have we decided about Y?", "what depends on the indexer decision?", "what supersedes the retrieval decision?". Also on edge-traversal phrasings: "what does the format decision supersede?", "what was informed by X?". Do NOT trigger for end-of-session capture intent (that's capture-decision) or for questions that don't require the archive.
---

# Recall Decision

Mid-session lookup against the user's decision archive(s). The skill exists to surface relevant prior decisions without polluting main's context with raw grep output or full file bodies. Main spawns a sub-agent that does the actual retrieval and returns a tight digest; main presents the digest; the user picks specific decisions to pull into context.

`$DECISION_ARCHIVE_ROOT` is a **comma-separated list of archive paths** (a single path is a valid one-element list — backward-compatible with single-archive setups). Each path is a local clone. Retrieval is via grep plus a small reference library of canonical Bash patterns for the 8 directional edge verbs. There is no indexer, no graph DB, no custom CLI — the sub-agent composes pipelines from the patterns on demand and fans them out across the selected archives.

**Edges are intra-archive only.** A decision in one archive cannot have a structured edge to a decision in another. The sub-agent never attempts cross-archive edge traversal.

## What the references contain

- `references/CONTEXT.md` — the skill's **vocabulary** file (Matt Pocock CONTEXT.md format). The sub-agent brief lists it as the first input; the recall agent reads it before anything else to align terminology and avoid the `_Avoid_:` aliases.
- `references/decision-format.md` — **descriptive** parsing spec. How to read frontmatter, what status means for filtering, edge directionality from the consumer's angle, what to surface in a digest.
- `references/recall-patterns.md` — canonical Bash incantations for the 8 directional traversal verbs, the three grep modes (tag / title / body), the status-filter discipline, the multi-hop pattern, and the digest assembly format.

Sub-agents do not inherit the skill directory. Main passes the absolute paths to these files in the brief.

## Pre-flight

Refuse to run unless `DECISION_ARCHIVE_ROOT` is set. Parse it as a **comma-separated list** of paths (whitespace around commas tolerated). For each entry:

- Trim whitespace.
- Resolve to an absolute path.
- Verify the directory exists. If any entry doesn't, stop and tell the user which entry is missing: "DECISION_ARCHIVE_ROOT entry `<path>` does not exist."

If the variable is unset or empty, stop and tell the user: "Set `DECISION_ARCHIVE_ROOT` to one or more archive paths (comma-separated) before invoking recall-decision."

The archives do **not** need to be in a clean state for recall (unlike capture-decision). Recall is read-only.

### Archive selection

- **Exactly 1 archive configured.** No prompt — search that one.
- **More than 1 archive configured.** Prompt the user with a multi-select. Show each archive by its **basename** (e.g., `/Users/foo/decision-archive` → `decision-archive`); include an `all` shortcut. The user picks any subset. The selected list (1..N) feeds the sub-agent brief.

The **archive name** used throughout (in prompts, digest annotations, briefs) is always the basename of the path — never the full path, never a configurable alias.

## Dispatch — spawn the recall sub-agent

Default sub-agent type: **`Explore`** (fast, read-only, pattern-matching). Escalate to **`general-purpose`** when the question requires full-body reasoning across multiple decisions — typically when the user's phrasing implies they want a synthesis-style answer, not a list of candidates.

Heuristic for escalation:

- "What do we have on X?" → `Explore` (topical search, return candidates).
- "What depends on the indexer decision?" → `Explore` (edge traversal, return list).
- "How do decisions about retrieval and indexing relate?" → `general-purpose` (cross-body reasoning, return narrative).
- "What's the story of these three decisions?" → `general-purpose` (the user wants the arc, not the files).

When in doubt, default to `Explore`. If the digest comes back too thin to answer the user's question, escalate to `general-purpose` on a follow-up turn.

## Sub-agent brief — template

Main fills in placeholders and hands the brief to the sub-agent at spawn time:

> **Objective:** Answer the user's question against the selected decision archive(s) at `<archive_roots>`. Return a tight ranked digest (≤50 lines). Do NOT return full decision bodies — those are read separately by main on request.
>
> **Inputs:**
> - Vocabulary: `<skill_dir>/references/CONTEXT.md` — the skill's vocabulary file. Read this first; use these terms (and not their `_Avoid_:` aliases) in the digest and any return message.
> - Archive roots: `<archive_roots>` — a list of one or more absolute paths. The archive name for digest annotation is the basename of each path.
> - User's question: `<verbatim user phrasing>`
> - Recall patterns reference: `<skill_dir>/references/recall-patterns.md`
> - Decision format reference: `<skill_dir>/references/decision-format.md`
>
> **Method:**
> 1. Read `CONTEXT.md` first to align on terminology.
> 2. Read `recall-patterns.md`. Identify which canonical pattern(s) match the user's question. The 8 directional verbs and the three grep modes (tag / title / body) cover the standard cases.
> 3. If no canonical pattern matches, compose a pipeline using the same primitives (grep, awk, find, git). Stay close to the patterns' shape — they are the deterministic anchor. **Fan out across every archive root in `<archive_roots>`**: run the pipeline against each, annotate each result with its archive basename, then union the results before ranking.
> 4. Run the pipeline(s). Default to `status: accepted` filter unless the user explicitly asks about superseded decisions ("what did the format decision supersede?", "show me retired decisions about X").
> 5. Rank results: tag-match results rank above title-match; title-match above body-match. Within a tier, prefer recent (later ULID, which sorts higher) over older. Ranking is global across the union — archive identity does not affect rank.
> 6. **Edges are intra-archive only.** When traversing an edge from a decision in archive A, only resolve target IDs within archive A. If an edge ID does not resolve within its own archive, surface that decision with `match=unresolved-edge:<id>` in the digest rather than silently dropping it.
> 7. Assemble the digest per the format in `recall-patterns.md` (`digest assembly format` section). When `<archive_roots>` contains more than one entry, prefix each line with `[<archive-basename>]`. When there is only one, the prefix may be omitted for cleanliness.
>
> **Output constraints:**
> - ≤50 lines total (including any header line).
> - One line per candidate decision.
> - Each line carries: `{archive (when multi-archive), id, kind, slug, title, status, tags, match_kind|distance, one-line-relevance}`.
> - **No full bodies.** Bodies are read by main on request, not by the sub-agent.
> - If no candidates match, return a short message ("no matches for <query>") and (when useful) a one-line hint about adjacent topics worth searching.

## Digest format

Each line of the digest follows this shape:

```
[<archive>] <id> <kind> <slug> | status=<status> tags=[<t1>, <t2>] match=<kind|distance> | <one-line-relevance>
```

The `[<archive>]` prefix is **present when more than one archive was selected** and **omitted when only one** (whether configured or selected from a larger set).

Where:

- `<archive>` — basename of the archive root (e.g., `decision-archive`, `team-a-archive`). Globally unambiguous because the ID space is ULID-based; the prefix is purely for the user's benefit when results span multiple archives.
- `<id>` — the ULID of the decision (26-char Crockford base32). ULIDs are globally unique across archives and lexicographically sortable by creation time, so a later ULID is the more recent decision.
- `<kind>` — `decision` or `synthesis`.
- `<slug>` — the namespaced kebab-case slug.
- `<status>` — `accepted` or `superseded`.
- `<tags>` — the frontmatter tags (3–6 typical).
- `<match>` — what matched: `tag:<tag>` / `title:<term>` / `body:<term>` for grep results; `<verb>:<id>` / `hops:N` for edge traversals; `unresolved-edge:<id>` when a declared edge target cannot be found within the same archive.
- `<one-line-relevance>` — a short string lifted from the title or first paragraph; the sub-agent does not paraphrase, it extracts.

Cap: ≤50 lines. If more than ~40 candidates match, the sub-agent surfaces the top-ranked subset and notes the truncation ("12 more matches; refine with tag X or status filter").

## Presentation by main

After receiving the digest, main:

1. Presents the digest to the user verbatim (or lightly reformatted for readability).
2. Offers to Read specific decisions into main's context: "Want me to pull these two into context for the discussion?" (Identify them by archive + the **shortest unambiguous ULID prefix, minimum 6 characters** — e.g., `01JX4F` — or by slug when more legible. Six chars of Crockford base32 yields ~10⁹ possibilities, almost always enough; extend only when results in the current set genuinely collide on the first 6.)
3. The user picks. Main runs targeted `Read` calls on the chosen files. No broad scans.

Main does **not**:

- Read decision bodies as part of answering the recall query.
- Inline raw grep output.
- Volunteer to read everything just-in-case.
- Read more than the user explicitly requests.

This is the context-hygiene discipline applied to the read path. The archive will be queried often; per-query context-pollution compounds across a session.

## Boundaries

- **Main never reads the archive directly.** Every retrieval goes through a recall sub-agent. The only exception is the user explicitly asking main to Read a specific file (which is a one-file targeted read, not a scan).
- **Main never invokes the archive without going through a recall sub-agent**, even for a "quick" check. The discipline holds across query sizes — there is no "small enough to inline" exception.
- **Sub-agents return digests, never bodies.** A sub-agent that returns a full decision body is misbehaving. If the user needs a body, main runs the Read in a separate, explicit step.
- **The default status filter is `accepted`.** Superseded decisions are accessible but hidden by default. The user asks for them explicitly to see them ("what's been superseded?", "show me the retired indexer decisions").

## Escalation

If the `Explore` sub-agent returns a thin or unhelpful digest:

- Main can suggest to the user that an escalation to `general-purpose` would help ("the lookup didn't find clear matches — want me to do a deeper search that reads bodies?").
- The user opts in. Main re-spawns with `general-purpose` and the same brief (plus the prior digest as context).
- The `general-purpose` agent may read full bodies; its digest is still ≤50 lines and still does not return bodies to main.

If a query consistently returns nothing useful, that's a **retrieval miss** (per the retrieval-miss / traversal-miss taxonomy in CONTEXT.md). The user captures the miss; later analysis may inform changes to the tagging discipline or the recall patterns.

## Edge cases

- **Empty archive.** If a selected archive's `decisions/` directory is empty, the sub-agent notes it in the digest ("no decisions in <archive-basename> yet") and continues with the other selected archives.
- **Unparseable frontmatter on a file.** The sub-agent reports the file in the digest with a note ("frontmatter parse error") rather than skipping it silently.
- **Query mentions a specific ID that doesn't exist.** The sub-agent returns "no decision with id <ULID> in <archive>" plus a one-line hint (e.g., the closest matching slug, or the most recent decision in that archive).
- **Unresolved intra-archive edge.** A decision declares an edge to an ID that does not exist within the same archive. Surface that decision with `match=unresolved-edge:<id>` rather than dropping or chasing cross-archive.
