# Decision format — parsing spec (descriptive)

How to read a decision file or a synthesis file in the archive. Use this when retrieving and ranking, not when drafting.

The capture-decision skill ships a sibling `decision-format.md` written from the authoring perspective — same fields, different angle. This reference says "when you see X, it means Y"; the authoring one says "always include X."

---

## Archive layout you'll be reading

`$DECISION_ARCHIVE_ROOT` is a **comma-separated list** of archive paths; each path has this layout:

```
<archive-root>/
├── decisions/
│   └── <ULID>-<namespace>-<slug>.md
├── synthesis/
│   └── <ULID>-<namespace>-<slug>.md
└── transcripts/
    └── transcript-<YYYYMMDD-HHMMSS>-<slug>.md
```

- **decisions/** — closed-off forks, one file each.
- **synthesis/** — per-session narratives integrating one or more decisions.
- **transcripts/** — committed source conversations (one per capture batch). Searchable if you need to ground a decision in its session; not typically surfaced in a recall digest.

IDs are **ULIDs** (26-char Crockford base32, e.g., `01JX4F8K2MABCDEFGHIJKLMNOP`). They are globally unique and lexicographically sortable by creation time — a later ULID is the more recent decision. The two directories share no ID space concerns (every ULID is unique anywhere), and IDs do not collide across archives either.

**Edges are intra-archive only.** A decision's `depends-on`, `supersedes`, `informs`, or `synthesizes` ULIDs always reference targets in the *same* archive. The sub-agent never resolves an edge ID against a different archive — if a target isn't found in the home archive, surface it as `match=unresolved-edge:<id>` instead.

---

## Reading the frontmatter

```yaml
---
id: 01JX4F8K2MABCDEFGHIJKLMNOP
slug: decision-archive-two-skill-split
title: Two skills — capture-decision and recall-decision
status: accepted
tags: [decision-archive, skill-architecture, v1]
edges:
  depends-on: [01JX1A3B4C5D6E7F8G9H0J1K2L, 01JX2M3N4O5P6Q7R8S9T0U1V2W]
  supersedes: []
  informs: [01JX3X4Y5Z6A7B8C9D0E1F2G3H]
---
```

### What each field tells you

| Field | What it tells you |
|---|---|
| `id` | The unique ULID key for this decision (26-char Crockford base32). Edges reference by ULID, never by slug — so this is the key you'll see in other decisions' `depends-on` / `supersedes` / `informs` lists. ULIDs are globally unique and lexicographically sortable by creation time. |
| `slug` | The kebab-case label, namespaced (`decision-archive-*` in the current archive). Useful for human-readable references and for matching against title-style queries. |
| `title` | The one-line human-readable title. The H1 in the body mirrors this. Most useful for ranking — title-match outranks body-match. |
| `status` | `accepted` = live. `superseded` = retired (a successor exists in the archive). **No third state.** When filtering for "current decisions only", filter to `accepted`. |
| `tags` | Free-form lowercase kebab-case labels. The primary axis for topical retrieval. Tag-match outranks title-match in ranking. |
| `edges.depends-on` | Decisions this one builds on. **Direction: from this file TO the targets.** If you're reading file F with `depends-on: [X, Y]`, F depends on X and Y. Targets are ULIDs within the **same archive**. |
| `edges.supersedes` | Decisions this one retires. **Direction: from successor TO retired predecessor.** If F has `supersedes: [X]`, F retires X (X's status is now `superseded`). Intra-archive only. |
| `edges.informs` | Decisions this one influences (weaker than `depends-on`). **Direction: from influencing decision TO influenced one.** Intra-archive only. |

### Synthesis-only fields

Synthesis files have an additional edge type and an optional `spawns-threads` block:

```yaml
edges:
  synthesizes: [01JX4F8K2MABCDEFGHIJKLMNOP, 01JX4F8K3NBBCDEFGHIJKLMNOP, 01JX4F8K4ODBCDEFGHIJKLMNOP]
  informs: []
spawns-threads:
  - topic: Tag taxonomy refinement
    why-deferred: Current free-form tags suffice; revisit after more decisions accumulate
    revisit-trigger: When tag-match returns too many false positives
    rough-size: small
  - ...
```

- `synthesizes` — direction is from the synthesis file TO the decisions it covers.
- `spawns-threads` — topics deferred from the session, each with topic / why-deferred / revisit-trigger / rough-size. These are not decisions; they are explicit deferrals. Surface them when the user asks about open questions, deferred work, or "what didn't we decide?"

---

## Status semantics for filtering

**Default filter: `status: accepted`.**

Most recall queries care only about live decisions. When the user asks "what do we have on X?", "have we decided about Y?", or "what depends on the indexer decision?", they want the current state of the archive, not retired framings.

**Show `superseded` only when:**

- The user asks explicitly: "what's been superseded?", "show me retired decisions", "what did we decide about X before?".
- The query traverses a `supersedes` edge in either direction: "what did the format decision supersede?", "what supersedes the indexer decision?".
- The user references a known-superseded decision directly by slug or ULID — surface it with the superseded status noted, and include a pointer to its successor.

When surfacing superseded decisions in a digest, the line should make the status visible:

```
01JX0Y9Z8AKLMNOPQRSTUVWXYZ decision decision-archive-align-plan-write-files-status-proposed | status=superseded ...
```

So the user knows what they're looking at without having to read the body.

---

## Edge directionality — read carefully

The edges are declared **on the source file** and point **at the target**. So:

- File F has `depends-on: [X]` → **F depends on X.** X is the dependency; F is the dependent.
- File F has `supersedes: [X]` → **F supersedes X.** F is the successor; X is retired.
- File F has `informs: [X]` → **F informs X.** F is the influencing decision; X is the influenced.
- Synthesis S has `synthesizes: [X, Y]` → **S synthesizes X and Y.**

When a user asks the **inverse** question, the sub-agent has to scan for it:

| User asks... | The grep is... |
|---|---|
| "What does F depend on?" | Read F's `depends-on` list. |
| "What depends on X?" | Scan all decisions for `depends-on: [..., X, ...]`. |
| "What does F supersede?" | Read F's `supersedes` list. |
| "What supersedes X?" | Scan all decisions for `supersedes: [..., X, ...]`. |
| "What does F inform?" | Read F's `informs` list. |
| "What informs X?" | Scan all decisions for `informs: [..., X, ...]`. |
| "What does S synthesize?" | Read S's `synthesizes` list. |
| "What synthesizes X?" | Scan all synthesis files for `synthesizes: [..., X, ...]`. |

The 8 directional patterns live in `recall-patterns.md`. The sub-agent picks the one matching the user's phrasing.

---

## Synthesis vs decision distinction

**Decision files**: one closed-off fork. A specific choice between alternatives with rationale. Self-contained.

**Synthesis files**: connective tissue. A narrative integrating multiple decisions into an architectural arc.

When ranking results for a topical query, both kinds can be returned. The digest line marks `kind=decision` or `kind=synthesis` so the user knows what they're looking at.

A user asking "what's the architecture of the decision-archive system?" probably wants synthesis files. A user asking "have we decided how to do X?" probably wants decision files. The sub-agent uses the question's shape to bias ranking, but does not exclude either kind unilaterally — surface both, mark them, let the user choose.

---

## Tag interpretation

Tags are free-form. They are not a closed vocabulary — the tagging discipline at write time is what makes them useful at recall time.

Common tag patterns in the current archive:

- **Namespace tags**: `decision-archive`, `n8n-workflows`. Every decision in the archive has the namespace tag; useful for cross-archive disambiguation but not for narrowing within an archive.
- **Topic tags**: `retrieval`, `schema`, `multi-agent`, `read-path`, `write-path`. The primary axis of topical lookup.
- **Versioning tags**: `v1`, `v2`, `refinement`. Mark which design layer the decision belongs to.
- **Architectural tags**: `skill-architecture`, `sub-agents`, `context-hygiene`. Cross-cutting concerns.

When the user's query is a topic phrase ("retrieval", "context hygiene"), tag-match is the primary signal. When the query is a specific term that might appear in titles or bodies ("Kùzu", "transcript dump"), grep across title and body is the right fallback.

---

## What to surface in a digest

For each candidate decision, the digest line carries:

- Archive basename prefix (`[<archive>]`) — present when more than one archive was selected; omitted otherwise.
- `id` — the ULID.
- `kind` (decision / synthesis)
- `slug`
- `title` (extracted from frontmatter or first H1; not paraphrased)
- `status` (accepted / superseded)
- `tags` (the frontmatter list)
- `match_kind` (`tag:<tag>` / `title:<term>` / `body:<term>` / `<verb>:<id>` for edge traversals / `hops:N` for multi-hop / `unresolved-edge:<id>` when an edge target isn't found within the same archive)
- One-line relevance — a string extracted from the title or the first paragraph of the body. **Do not paraphrase.** Extract.

The line shape is in `recall-patterns.md`'s `digest assembly format` section. ≤50 lines total.

What **not** to surface:

- Full bodies. The user gets a body only by asking main to Read a specific file after seeing the digest.
- Multi-line summaries. One-line relevance only.
- Inferred metadata. If the frontmatter doesn't have a field, the digest doesn't fabricate one — the line says `tags=[]` or omits the field cleanly.
