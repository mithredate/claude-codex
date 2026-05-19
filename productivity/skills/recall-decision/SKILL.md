---
name: recall-decision
description: >-
  Surface relevant prior decisions from the user's decision archive mid-session, without polluting main's context with raw greps or full bodies. Trigger when the user asks lookup questions like "what do we have on X?", "have we decided about Y?", "is there a decision about Z?", "what depends on 0042?", "what supersedes the indexer decision?", "show me decisions about retrieval", or any phrasing that signals a mid-session lookup against the archive. Also trigger on edge-traversal phrasings: "what does 0007 supersede?", "what was informed by the format decision?", "what decisions are connected to 0014?". The skill dispatches a sub-agent (default Explore; general-purpose when full-body reasoning is needed) which composes grep against the archive and returns a ≤50-line ranked digest. Main never reads decision bodies directly — context hygiene is mandatory. Do NOT trigger for end-of-session capture intent (that's capture-decision) or for questions that don't require the archive.
---

# Recall Decision

Mid-session lookup against the user's decision archive. The skill exists to surface relevant prior decisions without polluting main's context with raw grep output or full file bodies. Main spawns a sub-agent that does the actual retrieval and returns a tight digest; main presents the digest; the user picks specific decisions to pull into context.

The archive lives at `$DECISION_ARCHIVE_ROOT` (a local clone). Retrieval is via grep plus a small reference library of canonical Bash patterns for the 8 directional edge verbs. There is no indexer, no graph DB, no custom CLI — the sub-agent composes pipelines from the patterns on demand.

## What the references contain

- `references/decision-format.md` — **descriptive** parsing spec. How to read frontmatter, what status means for filtering, edge directionality from the consumer's angle, what to surface in a digest.
- `references/recall-patterns.md` — canonical Bash incantations for the 8 directional traversal verbs, the three grep modes (tag / title / body), the status-filter discipline, the multi-hop pattern, and the digest assembly format.

Sub-agents do not inherit the skill directory. Main passes the absolute paths to these files in the brief.

## Pre-flight

Refuse to run unless `DECISION_ARCHIVE_ROOT` is set in the environment and points at an existing directory. If unset, stop and tell the user: "Set `DECISION_ARCHIVE_ROOT` to the path of your decision-archive clone before invoking recall-decision."

The archive does **not** need to be in a clean state for recall (unlike capture-decision). Recall is read-only.

## Dispatch — spawn the recall sub-agent

Default sub-agent type: **`Explore`** (fast, read-only, pattern-matching). Escalate to **`general-purpose`** when the question requires full-body reasoning across multiple decisions — typically when the user's phrasing implies they want a synthesis-style answer, not a list of candidates.

Heuristic for escalation:

- "What do we have on X?" → `Explore` (topical search, return candidates).
- "What depends on 0042?" → `Explore` (edge traversal, return list).
- "How do decisions about retrieval and indexing relate?" → `general-purpose` (cross-body reasoning, return narrative).
- "What's the story of decisions 0007, 0012, 0013?" → `general-purpose` (the user wants the arc, not the files).

When in doubt, default to `Explore`. If the digest comes back too thin to answer the user's question, escalate to `general-purpose` on a follow-up turn.

## Sub-agent brief — template

Main fills in placeholders and hands the brief to the sub-agent at spawn time:

> **Objective:** Answer the user's question against the decision archive at `<archive_root>`. Return a tight ranked digest (≤50 lines). Do NOT return full decision bodies — those are read separately by main on request.
>
> **Inputs:**
> - Archive root: `<archive_root>` (absolute path)
> - User's question: `<verbatim user phrasing>`
> - Recall patterns reference: `<skill_dir>/references/recall-patterns.md`
> - Decision format reference: `<skill_dir>/references/decision-format.md`
>
> **Method:**
> 1. Read `recall-patterns.md` first. Identify which canonical pattern(s) match the user's question. The 8 directional verbs and the three grep modes (tag / title / body) cover the standard cases.
> 2. If no canonical pattern matches, compose a pipeline using the same primitives (grep, awk, find, git). Stay close to the patterns' shape — they are the deterministic anchor.
> 3. Run the pipeline against `<archive_root>`. Default to `status: accepted` filter unless the user explicitly asks about superseded decisions ("what did 0007 supersede?", "show me retired decisions about X").
> 4. Rank results: tag-match results rank above title-match; title-match above body-match. Within a tier, prefer recent (higher ID) over older.
> 5. Assemble the digest per the format in `recall-patterns.md` (`digest assembly format` section).
>
> **Output constraints:**
> - ≤50 lines total (including any header line).
> - One line per candidate decision.
> - Each line carries: `{id, kind, slug, title, status, tags, match_kind|distance, one-line-relevance}`.
> - **No full bodies.** Bodies are read by main on request, not by the sub-agent.
> - If no candidates match, return a short message ("no matches for <query>") and (when useful) a one-line hint about adjacent topics worth searching.

## Digest format

Each line of the digest follows this shape:

```
<id> <kind> <slug> | status=<status> tags=[<t1>, <t2>] match=<kind|distance> | <one-line-relevance>
```

Where:

- `<id>` — integer ID, zero-padded to 4 digits (e.g., `0014`).
- `<kind>` — `decision` or `synthesis`.
- `<slug>` — the namespaced kebab-case slug.
- `<status>` — `accepted` or `superseded`.
- `<tags>` — the frontmatter tags (3–6 typical).
- `<match>` — what matched: `tag:<tag>` / `title:<term>` / `body:<term>` for grep results; `<verb>:<id>` / `hops:N` for edge traversals.
- `<one-line-relevance>` — a short string lifted from the title or first paragraph; the sub-agent does not paraphrase, it extracts.

Cap: ≤50 lines. If more than ~40 candidates match, the sub-agent surfaces the top-ranked subset and notes the truncation ("12 more matches; refine with tag X or status filter").

## Presentation by main

After receiving the digest, main:

1. Presents the digest to the user verbatim (or lightly reformatted for readability).
2. Offers to Read specific decisions into main's context: "Want me to pull 0014 and 0017 into context for the discussion?"
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

If a query consistently returns nothing useful, that's a **retrieval miss** (per the failure-mode taxonomy in CONTEXT.md). The user captures the miss; later analysis may inform changes to the tagging discipline or the recall patterns.

## Edge cases

- **Empty archive.** If `<archive_root>/decisions/` is empty, the sub-agent returns "no decisions in archive yet."
- **Unparseable frontmatter on a file.** The sub-agent reports the file in the digest with a note ("frontmatter parse error") rather than skipping it silently.
- **Query mentions a specific ID that doesn't exist.** The sub-agent returns "no decision with id <N>" plus a one-line hint about the highest existing ID.
- **Cross-archive query.** Out of scope for v1 — multi-archive support is deferred. If the user mentions another archive, main suggests they switch `DECISION_ARCHIVE_ROOT` and re-invoke.
