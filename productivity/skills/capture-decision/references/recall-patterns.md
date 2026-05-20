# Recall patterns — canonical Bash incantations

The 8 directional edge verbs and the three grep modes (tag / title / body), as composable shell pipelines. The sub-agent reads this reference and uses the closest matching pattern; if the user's query doesn't match a canonical pattern exactly, the sub-agent composes a pipeline using the same primitives.

These patterns are the **deterministic anchor** for the no-retriever architecture. A query that matches a canonical pattern returns the same shape every time; queries outside the canonical set are agent-composed but stay close to these shapes.

All patterns below assume `$ARCHIVE` is **one** archive root. When `$DECISION_ARCHIVE_ROOT` lists more than one path (comma-separated) and the user has selected multiple, **fan out** — run each pattern against every selected `$ARCHIVE` independently, then union the results with each line annotated by archive basename. See "Multi-archive fan-out" at the bottom of this reference.

All commands run with `set -euo pipefail` and `shopt -s nullglob` discipline. The nullglob is what keeps empty `decisions/` or `synthesis/` directories from blowing up patterns that glob `*.md` — an empty glob expands to nothing instead of the literal `*.md`.

### ID shape

IDs in this archive are **ULIDs** (26-character Crockford base32 — uppercase `0-9` and `A-Z` excluding `I`, `L`, `O`, `U`). Filenames are `<ULID>-<slug>.md`. Frontmatter `id:` is the ULID string. Edge references (`depends-on`, `supersedes`, `informs`, `synthesizes`) are ULID-valued and **intra-archive only** — never resolved against a different archive.

Pinned regex for an ID: `[0-9A-HJKMNP-TV-Z]{26}` (strict Crockford). Use this form everywhere — anchored or unanchored as the context requires.

---

## Grep modes (topical search)

Three modes, ranked: **tag > title > body**.

### Tag match

Scan the frontmatter only (a bare body-grep would over-match prose mentions):

```bash
for f in "$ARCHIVE/decisions/"*.md "$ARCHIVE/synthesis/"*.md; do
  awk '/^---$/{c++; next} c==1' "$f" | grep -qE "tags:.*\b${TAG}\b" && echo "$f"
done
```

**Use when:** user phrases the query with a clear topical word that's likely a tag (`"retrieval"`, `"multi-agent"`, `"schema"`).

**Caveat:** tag results rank above title and body matches.

### Title match

```bash
grep -l -i "${TERM}" "$ARCHIVE/decisions/"*.md "$ARCHIVE/synthesis/"*.md | \
  while read f; do
    awk '/^---$/{c++; next} c==1 && /^title:/' "$f" | grep -qi "${TERM}" && echo "$f"
  done
```

**Use when:** the query term is likely in the title (a proper noun, a specific concept name).

**Caveat:** title-matches rank above body matches but below tag matches.

### Body match

```bash
grep -rli "${TERM}" "$ARCHIVE/decisions/" "$ARCHIVE/synthesis/"
```

**Use when:** neither tag nor title would match and the term is something likely discussed in a body (a tool name, a vendor, a specific failure mode).

**Caveat:** body-match is the least-ranked tier; large body matches can be noisy. Combine with status filter.

---

## Status filter discipline

**Default: `status: accepted`.**

Apply this filter to every grep mode unless the user explicitly asked about superseded decisions. The pattern below is a snippet: pipe the candidate filenames from your topical/edge grep into this loop. The loop assumes `candidate_files` is whatever the upstream pipeline produced (a newline-separated list of file paths, or shell-glob expansion):

```bash
# Restrict to accepted only — substitute candidate_files with the upstream result
for f in $candidate_files; do
  awk '/^---$/{c++; next} c==1 && /^status: accepted/' "$f" >/dev/null && echo "$f"
done
```

When the query references a `supersedes` edge in either direction, **lift the filter** — superseded decisions are exactly what the user wants:

- "What did the format decision supersede?" → show the target, which is superseded.
- "What supersedes the indexer decision?" → may show both the superseded source and its successor.

When the query is "show me everything" or "what's in the archive about X?", show superseded but mark them clearly in the digest line.

---

## The 8 directional verbs

The 8 patterns from the retired CLI design survive as documented Bash pipelines. Each pattern corresponds to one direction of one edge type.

In all eight patterns, `${ID}` is a ULID string. Filename globs use `"$ARCHIVE/decisions/${ID}-"*.md` (exact ULID prefix). Body-of-edge scans match the ULID literally — ULIDs are fixed 26-char strings, so a plain substring match against the parsed frontmatter list is unambiguous and a `\b${ID}\b` word-boundary regex also works because ULID characters are all word characters.

### 1. `depends-on:<id>` — "What does F depend on?"

The dependencies of file F. Just read F's frontmatter:

```bash
awk '/^---$/{c++; next} c==1 && /^  depends-on:/' "$ARCHIVE/decisions/${ID}-"*.md
```

**Output shape:** the list of ULIDs from F's `depends-on` frontmatter.

**Caveat:** the IDs in F's list reference other files in `decisions/` within the **same archive** (typically; cross-references into `synthesis/` are rare for `depends-on`). Resolve each ULID to a filename in a follow-up step within F's archive — never cross-archive.

### 2. `depended-on-by:<id>` — "What depends on X?"

Scan all decisions for `depends-on: [..., X, ...]`:

```bash
grep -l -E "depends-on:.*\b${ID}\b" "$ARCHIVE/decisions/"*.md
```

More precisely (multi-line yaml list aware):

```bash
for f in "$ARCHIVE/decisions/"*.md; do
  awk '/^---$/{c++; next} c==1' "$f" | \
    yq -r '.edges."depends-on"[]' 2>/dev/null | grep -qx "${ID}" && echo "$f"
done
```

(yq is convenient; if not available, fall back to awk parsing the frontmatter block.)

**Output shape:** list of decision filenames that declare `depends-on: [X]`.

**Caveat:** apply the status filter; usually the user wants `accepted` only. Scan is single-archive — if the user selected multiple archives, repeat per archive via the fan-out pattern.

### 3. `supersedes:<id>` — "What does F supersede?"

Read F's `supersedes` list:

```bash
awk '/^---$/{c++; next} c==1 && /^  supersedes:/' "$ARCHIVE/decisions/${ID}-"*.md
```

**Output shape:** the list of ULIDs from F's `supersedes` frontmatter.

**Caveat:** the targets are by definition `superseded`. Don't filter to `accepted` here.

### 4. `superseded-by:<id>` — "What supersedes X?"

Scan all decisions for `supersedes: [..., X, ...]`:

```bash
for f in "$ARCHIVE/decisions/"*.md; do
  awk '/^---$/{c++; next} c==1' "$f" | grep -qE "supersedes:.*\b${ID}\b" && echo "$f"
done
```

**Output shape:** typically one file (the live successor). If empty, the target is `accepted` and not yet superseded.

**Caveat:** if X is `accepted` and this query returns nothing, that's expected — no one has superseded X yet.

### 5. `informs:<id>` — "What does F inform?"

Read F's `informs` list:

```bash
awk '/^---$/{c++; next} c==1 && /^  informs:/' "$ARCHIVE/decisions/${ID}-"*.md
```

**Output shape:** the list of ULIDs from F's `informs` frontmatter.

**Caveat:** informs is the weaker edge; results may be smaller and less load-bearing than depends-on.

### 6. `informed-by:<id>` — "What informs X?"

Scan all decisions for `informs: [..., X, ...]`:

```bash
for f in "$ARCHIVE/decisions/"*.md; do
  awk '/^---$/{c++; next} c==1' "$f" | grep -qE "informs:.*\b${ID}\b" && echo "$f"
done
```

**Output shape:** list of decision filenames that influence X.

**Caveat:** informs is a softer signal; results may need cross-checking against body content.

### 7. `synthesizes:<id>` — "What does synthesis S synthesize?"

Read S's `synthesizes` list:

```bash
awk '/^---$/{c++; next} c==1 && /^  synthesizes:/' "$ARCHIVE/synthesis/${ID}-"*.md
```

**Output shape:** the list of decision ULIDs from S's `synthesizes` frontmatter.

**Caveat:** synthesis files are smaller in number; usually one synthesis per batch.

Inverse — "What synthesis covers decision X?":

```bash
for f in "$ARCHIVE/synthesis/"*.md; do
  awk '/^---$/{c++; next} c==1' "$f" | grep -qE "synthesizes:.*\b${ID}\b" && echo "$f"
done
```

### 8. `connected --hops <N>:<id>` — Multi-hop traversal

"What's in the neighborhood of X within N hops?" Walks the edge graph in both directions up to N hops.

Traversal stays inside a single `$ARCHIVE` — edges are intra-archive only.

```bash
# Pseudo: BFS over edge graph within one archive
ULID_RE='[0-9A-HJKMNP-TV-Z]{26}'
visited=("${ID}")
frontier=("${ID}")
for hop in $(seq 1 ${N}); do
  next_frontier=()
  for id in "${frontier[@]}"; do
    # outgoing edges from this id
    for f in "$ARCHIVE/decisions/${id}-"*.md; do
      [ -f "$f" ] || continue
      # extract depends-on, supersedes, informs targets (yq if available; awk fallback otherwise)
      if command -v yq >/dev/null 2>&1; then
        targets=$(awk '/^---$/{c++; next} c==1' "$f" | \
          yq -r '.edges | (."depends-on" // []) + (."supersedes" // []) + (.informs // []) | .[]')
      else
        targets=$(awk '/^---$/{c++; next} c==1' "$f" | \
          awk '/^[[:space:]]*(depends-on|supersedes|informs):/{flag=1; line=$0; sub(/^[^:]*:[[:space:]]*/,"",line); if(line!="")print line; next} flag && /^[[:space:]]*-/{sub(/^[[:space:]]*-[[:space:]]*/,""); print; next} {flag=0}' | tr -d '[],"' | tr ' ' '\n' | grep -E "^${ULID_RE}\$")
      fi
      for t in $targets; do
        if ! printf '%s\n' "${visited[@]}" | grep -qx "$t"; then
          visited+=("$t")
          next_frontier+=("$t")
        fi
      done
    done
    # incoming edges to this id (depended-on-by, superseded-by, informed-by)
    for f in "$ARCHIVE/decisions/"*.md "$ARCHIVE/synthesis/"*.md; do
      awk '/^---$/{c++; next} c==1' "$f" | grep -qE "(depends-on|supersedes|informs|synthesizes):.*\b${id}\b" || continue
      incoming_id=$(basename "$f" | grep -oE "^${ULID_RE}")
      if ! printf '%s\n' "${visited[@]}" | grep -qx "$incoming_id"; then
        visited+=("$incoming_id")
        next_frontier+=("$incoming_id")
      fi
    done
  done
  frontier=("${next_frontier[@]}")
done
# visited now holds all ULIDs within N hops in this archive
```

**Output shape:** list of decision ULIDs reachable from the starting ULID within N hops, **within a single archive**. If any extracted target ULID cannot be resolved to a file in this archive's `decisions/` or `synthesis/`, surface it as `match=unresolved-edge:<id>` rather than chasing it elsewhere.

**Caveat:** at high N this returns large sets. Default `--hops 1`; offer `--hops 2` only if the user explicitly asks for "the broader neighborhood" or "everything connected."

---

## Combining patterns

Real queries often need multiple patterns chained. Examples:

- "What accepted decisions tag `multi-agent`?" → tag match + status filter.
- "What does the multi-agent capture decision depend on that's still accepted?" → resolve the slug or known ULID first, then `depends-on:<ULID>` + status filter.
- "What superseded decisions about retrieval are there?" → tag match (`retrieval`) + invert status filter.
- "What's the neighborhood of the indexer decision?" → resolve to ULID, then `connected --hops 1:<ULID>`.

The sub-agent composes the chain on demand. If a chain becomes hard to express, fall back to a single broader search and rank in code.

---

## Digest assembly format

The sub-agent's output is a ranked digest, ≤50 lines. One line per candidate. The line shape:

```
[<archive>] <id> <kind> <slug> | status=<status> tags=[<t1>, <t2>] match=<match-kind> | <one-line-relevance>
```

The `[<archive>]` prefix is **present when more than one archive was selected**, **omitted otherwise**. `<id>` is the full ULID.

Concrete example (multi-archive selection):

```
[decision-archive] 01JX4F8K2MABCDEFGHIJKLMNOP decision decision-archive-two-skill-split | status=accepted tags=[decision-archive, skill-architecture, v1] match=tag:skill-architecture | Two skills — capture-decision and recall-decision; synthesis lives inside capture-decision
[decision-archive] 01JX4F8K3NBBCDEFGHIJKLMNOP decision decision-archive-multi-agent-capture-flow | status=accepted tags=[decision-archive, write-path, multi-agent, iteration] match=tag:multi-agent | Multi-agent capture flow — recall (one-shot) → iteration loop (3-round cap) → human gate
[team-a-archive] 01JX2P4Q5R6S7T8U9V0W1X2Y3Z synthesis team-a-skill-design-refresh | status=accepted tags=[team-a, design, v2, refinement, multi-agent] match=tag:multi-agent | Team-a skill-design refresh
```

Single-archive selection — omit the prefix:

```
01JX4F8K2MABCDEFGHIJKLMNOP decision decision-archive-two-skill-split | status=accepted tags=[decision-archive, skill-architecture, v1] match=tag:skill-architecture | Two skills — capture-decision and recall-decision; synthesis lives inside capture-decision
```

### Ranking rule

Within the 50-line cap, order results by match-quality tier:

1. Tag matches (highest).
2. Title matches.
3. Body matches (lowest).
4. Edge traversal results — rank by `accepted` first, `superseded` last, then by ULID descending (recent first; later ULID sorts higher because ULIDs are lexicographically sortable by creation time).

Within a tier, prefer recent (later ULID, which sorts higher) over older unless the user's query has a recency signal pointing the other way. Ranking is global across the union of archives — archive identity does not affect rank.

### Truncation handling

If more than ~40 candidates match, surface the top 40 and add a final line:

```
... 12 more matches (try refining with tag <X> or status=accepted to narrow)
```

The user gets to refine. The sub-agent does **not** silently drop matches.

### What never goes in the digest

- Full decision bodies (those are read by main on request).
- Multi-line summaries (one line per candidate, period).
- Inferred content (extract from the file; don't paraphrase or generate).
- Frontmatter that isn't part of the line shape (e.g., don't surface the full `edges` block — that's body-of-decision territory).

The digest is metadata about candidates, not content from them.

---

## Composing for uncommon queries

When the user's question doesn't match a canonical pattern (e.g., "find decisions that have an empty Assumptions section", "find decisions written more than 30 days ago", "find decisions with more than 5 tags"), compose a pipeline using the same primitives:

```bash
# Example: decisions with empty Assumptions
for f in "$ARCHIVE/decisions/"*.md; do
  awk '/^## Assumptions$/{flag=1; next} /^## /{flag=0} flag' "$f" | grep -qE '\S' || echo "$f"
done
```

Stay close to the canonical patterns' shape — they are the deterministic anchor. The agent's job is to compose, not to invent new retrieval verbs.

---

## Multi-archive fan-out

When the user has selected more than one archive root, run **each** of the patterns above against **each** selected archive independently, then union the per-archive results before ranking. Each result line carries an `[<archive-basename>]` prefix so the source is unambiguous.

The shape is:

```bash
# ARCHIVE_ROOTS is the selected list (space-separated absolute paths)
for ARCHIVE in $ARCHIVE_ROOTS; do
  archive_name=$(basename "$ARCHIVE")
  # Run the pattern; prefix each result line with [<archive_name>]
  <pattern-pipeline> | while read -r f; do
    printf '[%s] %s\n' "$archive_name" "$f"
  done
done | <ranking-and-digest-assembly>
```

Three discipline rules apply:

1. **No cross-archive edge traversal.** Edges are intra-archive. When traversing from a decision in archive A, only resolve target ULIDs against archive A's `decisions/` and `synthesis/`. If a target is unresolved within A, emit `match=unresolved-edge:<id>` for that decision — do **not** scan archive B for the missing ID.

2. **Ranking is global, archive identity is presentational.** After the union, rank purely by match-quality tier and ULID recency. Don't bias toward "home" archive or interleave artificially. Truncation to ≤50 lines applies to the unioned result.

3. **Single-archive selection** (whether `DECISION_ARCHIVE_ROOT` lists one path, or the user picked exactly one from a multi-archive config) **omits the `[<archive>]` prefix** for cleanliness. The fan-out loop still works — it just produces one set with the prefix dropped at assembly time.

---

## What `recall-patterns.md` does NOT cover

- Full-text semantic search (retrieval is grep — embeddings are deferred).
- Vector similarity (not in v1).
- Index-backed lookup (no indexer in v1).
- **Cross-archive edge traversal.** Multi-archive *search* is supported via fan-out, but edges within a decision are strictly intra-archive and never resolved across archive boundaries.

If a user asks for any of these, the sub-agent returns a thin digest and a note that the query is outside v1's retrieval surface.
