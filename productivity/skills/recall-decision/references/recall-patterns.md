# Recall patterns — canonical Bash incantations

The 8 directional edge verbs and the three grep modes (tag / title / body), as composable shell pipelines. The sub-agent reads this reference and uses the closest matching pattern; if the user's query doesn't match a canonical pattern exactly, the sub-agent composes a pipeline using the same primitives.

These patterns are the **deterministic anchor** for the no-retriever architecture. A query that matches a canonical pattern returns the same shape every time; queries outside the canonical set are agent-composed but stay close to these shapes.

All patterns assume `$ARCHIVE` is the archive root (e.g., `$DECISION_ARCHIVE_ROOT`). All commands run with `set -euo pipefail` discipline.

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

Apply this filter to every grep mode unless the user explicitly asked about superseded decisions:

```bash
# Restrict to accepted only
for f in $RESULTS; do
  awk '/^---$/{c++; next} c==1 && /^status: accepted/' "$f" >/dev/null && echo "$f"
done
```

When the query references a `supersedes` edge in either direction, **lift the filter** — superseded decisions are exactly what the user wants:

- "What did 0007 supersede?" → show the target, which is superseded.
- "What supersedes the indexer decision?" → may show both the superseded source and its successor.

When the query is "show me everything" or "what's in the archive about X?", show superseded but mark them clearly in the digest line.

---

## The 8 directional verbs

The 8 patterns from the retired CLI design survive as documented Bash pipelines. Each pattern corresponds to one direction of one edge type.

### 1. `depends-on:<id>` — "What does F depend on?"

The dependencies of file F. Just read F's frontmatter:

```bash
awk '/^---$/{c++; next} c==1 && /^  depends-on:/' "$ARCHIVE/decisions/${ID}-"*.md
```

**Output shape:** the list of integer IDs from F's `depends-on` frontmatter.

**Caveat:** the IDs in F's list reference other files in `decisions/` (typically; cross-references into `synthesis/` are rare for `depends-on`). Resolve each ID to a filename in a follow-up step.

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

**Caveat:** apply the status filter; usually the user wants `accepted` only.

### 3. `supersedes:<id>` — "What does F supersede?"

Read F's `supersedes` list:

```bash
awk '/^---$/{c++; next} c==1 && /^  supersedes:/' "$ARCHIVE/decisions/${ID}-"*.md
```

**Output shape:** the list of integer IDs from F's `supersedes` frontmatter.

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

**Output shape:** the list of integer IDs from F's `informs` frontmatter.

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

**Output shape:** the list of decision IDs from S's `synthesizes` frontmatter.

**Caveat:** synthesis files are smaller in number; usually one synthesis per batch.

Inverse — "What synthesis covers decision X?":

```bash
for f in "$ARCHIVE/synthesis/"*.md; do
  awk '/^---$/{c++; next} c==1' "$f" | grep -qE "synthesizes:.*\b${ID}\b" && echo "$f"
done
```

### 8. `connected --hops <N>:<id>` — Multi-hop traversal

"What's in the neighborhood of X within N hops?" Walks the edge graph in both directions up to N hops.

```bash
# Pseudo: BFS over edge graph
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
          awk '/^[[:space:]]*(depends-on|supersedes|informs):/{flag=1; line=$0; sub(/^[^:]*:[[:space:]]*/,"",line); if(line!="")print line; next} flag && /^[[:space:]]*-/{sub(/^[[:space:]]*-[[:space:]]*/,""); print; next} {flag=0}' | tr -d '[],"' | tr ' ' '\n' | grep -E '^[0-9]+$')
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
      incoming_id=$(basename "$f" | grep -oE '^[0-9]+')
      if ! printf '%s\n' "${visited[@]}" | grep -qx "$incoming_id"; then
        visited+=("$incoming_id")
        next_frontier+=("$incoming_id")
      fi
    done
  done
  frontier=("${next_frontier[@]}")
done
# visited now holds all IDs within N hops
```

**Output shape:** list of decision IDs reachable from the starting ID within N hops.

**Caveat:** at high N this returns large sets. Default `--hops 1`; offer `--hops 2` only if the user explicitly asks for "the broader neighborhood" or "everything connected."

---

## Combining patterns

Real queries often need multiple patterns chained. Examples:

- "What accepted decisions tag `multi-agent`?" → tag match + status filter.
- "What does 0017 depend on that's still accepted?" → `depends-on:0017` + status filter.
- "What superseded decisions about retrieval are there?" → tag match (`retrieval`) + invert status filter.
- "What's the neighborhood of 0008?" → `connected --hops 1:0008`.

The sub-agent composes the chain on demand. If a chain becomes hard to express, fall back to a single broader search and rank in code.

---

## Digest assembly format

The sub-agent's output is a ranked digest, ≤50 lines. One line per candidate. The line shape:

```
<id> <kind> <slug> | status=<status> tags=[<t1>, <t2>] match=<match-kind> | <one-line-relevance>
```

Concrete example:

```
0014 decision decision-archive-two-skill-split | status=accepted tags=[decision-archive, skill-architecture, v1] match=tag:skill-architecture | Two skills — capture-decision and recall-decision; synthesis lives inside capture-decision
0017 decision decision-archive-multi-agent-capture-flow | status=accepted tags=[decision-archive, write-path, multi-agent, iteration] match=tag:multi-agent | Multi-agent capture flow — recall (one-shot) → iteration loop (3-round cap) → human gate
0003 synthesis decision-archive-skill-design-refresh | status=accepted tags=[decision-archive, design, v2, refinement, multi-agent] match=tag:multi-agent | Decision-archive v2 — skill design refresh
```

### Ranking rule

Within the 50-line cap, order results by match-quality tier:

1. Tag matches (highest).
2. Title matches.
3. Body matches (lowest).
4. Edge traversal results — rank by `accepted` first, `superseded` last, then by ID descending (recent first).

Within a tier, prefer higher ID (recent) over lower (older) unless the user's query has a recency signal pointing the other way.

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

## What `recall-patterns.md` does NOT cover

- Full-text semantic search (retrieval is grep — embeddings are deferred).
- Vector similarity (not in v1).
- Index-backed lookup (no indexer in v1).
- Cross-archive queries (multi-archive support deferred).

If a user asks for any of these, the sub-agent returns a thin digest and a note that the query is outside v1's retrieval surface.
