# Decision format — authoring spec (normative)

How to write a decision file or a synthesis file in the archive. Use this when drafting, not when parsing.

The recall-decision skill ships a sibling `decision-format.md` written from the parsing perspective — same fields, different angle. The two references differ deliberately: this one says "always include X"; the parsing one says "when you see X, it means Y."

---

## File layout in the archive

```
$ARCHIVE_ROOT/
├── decisions/
│   └── <ULID>-<namespace>-<slug>.md
├── synthesis/
│   └── <ULID>-<namespace>-<slug>.md
└── transcripts/
    └── transcript-<YYYYMMDD-HHMMSS>-<slug>.md
```

`$ARCHIVE_ROOT` is the single archive selected for this capture session (Pre-flight resolves it from the comma-separated `$DECISION_ARCHIVE_ROOT` list). Decision and synthesis files share the ULID namespace — ULIDs are globally unique, so there is no risk of collision between the two directories or across archives. Transcripts are timestamp-prefixed, not ULID-prefixed.

---

## Slug convention

**Format:** `<namespace>-<topic-words>` in lowercase kebab-case.

The namespace prefix is uniform within one archive. The current archive's namespace is `decision-archive`. A different archive (e.g., one capturing n8n workflow decisions) would use a different prefix (`n8n-workflows`).

The namespace appears in the slug because filenames travel outside content-scope (shared links, file pickers, autocompletion, grep across the whole machine). Tags and directories carry namespace at content-scope; filenames need it too. Yes, this produces redundant-looking filenames like `01JX4F8K2MABCDEFGHIJKLMNOP-decision-archive-decision-as-closed-off-fork.md` — the uniformity is the value.

**Examples:**
- `01JX4F8K2MABCDEFGHIJKLMNOP-decision-archive-two-skill-split`
- `01JX4F9N3QABCDEFGHIJKLMNOP-decision-archive-file-format-and-synthesis-layer`

The filename mirrors the slug exactly: `<ULID>-<slug>.md`.

---

## ID assignment

Decisions and synthesis files use **ULIDs** (26-character Crockford base32, lexicographically sortable by creation time). The capture agent generates a fresh ULID per new file at draft time.

Use this stdlib-only Python one-liner as the canonical producer:

```bash
python3 -c '
import secrets, time
A = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
def b32(n, w): return "".join(A[(n >> (5*i)) & 31] for i in range(w-1, -1, -1))
t = time.time_ns() // 1_000_000
r = int.from_bytes(secrets.token_bytes(10), "big")
print(b32(t, 10) + b32(r, 16))
'
```

It emits a 26-character string: a 10-character millisecond-timestamp prefix plus 16 characters of randomness, all in Crockford base32 (alphabet `0123456789ABCDEFGHJKMNPQRSTVWXYZ` — excludes `I`, `L`, `O`, `U`). No external dependencies, no network calls, no installation.

ULIDs are globally unique by construction, so there is no scan-for-max-and-increment step and no risk of collision between the `decisions/` and `synthesis/` namespaces or across archives. Within a batch, ULIDs sort by creation order naturally — assign them in the order the decisions logically build on each other (foundational first, dependent later) and the lexicographic sort will mirror that. This is a soft convention that aids legibility; no validator enforces it.

Edges always reference targets by **ULID string**, never by slug. Renaming a slug is therefore zero-risk for graph integrity.

---

## Frontmatter schema

```yaml
---
id: <ULID string>
slug: <kebab-case, includes namespace prefix>
title: <one-line human-readable title; sentence case>
status: accepted | superseded
tags: [<tag1>, <tag2>, ...]
edges:
  depends-on: [<ULID>, <ULID>, ...]
  supersedes: [<ULID>, ...]
  informs: [<ULID>, ...]
---
```

### Field semantics

| Field | Required | Type | Notes |
|---|---|---|---|
| `id` | yes | string (ULID) | 26-char Crockford base32. Matches filename prefix. Globally unique. |
| `slug` | yes | string | Namespaced kebab-case. Matches filename (minus `.md`). |
| `title` | yes | string | One line, sentence case. Mirrored as the H1 in the body. |
| `status` | yes | enum | `accepted` for new decisions. `superseded` only when a successor exists. **Never `proposed` — that state does not exist in the two-state lifecycle.** |
| `tags` | yes | list[string] | The key is required; 3–6 entries recommended. Empty list or fewer than 3 entries surfaces as `nit` (not blocking). Lowercase kebab-case. Free-form; used by grep at recall time. |
| `edges.depends-on` | yes (`[]` if none) | list[ULID] | Decisions whose substance this one builds on. |
| `edges.supersedes` | yes (`[]` if none) | list[ULID] | Decisions this one retires. Authors flip the target's status to `superseded` in the same batch. |
| `edges.informs` | yes (`[]` if none) | list[ULID] | Decisions this one influences but does not directly depend on. |

The edges block is mandatory; empty lists are explicit (`supersedes: []`), not omitted.

**Edges are intra-archive only.** Every ULID in an edge field must refer to a file inside the current archive (`$ARCHIVE_ROOT`). If a decision conceptually relates to a decision in another archive, that reference stays as prose in `Rationale` or `Note` — never as a structured edge. The Archive Auditor flags any cross-archive ULID in an edge field as `blocking`.

### Synthesis-only edge

Synthesis files use an additional edge type. They typically have no `informs` targets, but the field is still **explicit, not omitted** — symmetric with the decision-edges rule above. Empty lists in synthesis frontmatter take the form `informs: []`, never just leaving the key out:

```yaml
edges:
  synthesizes: [<ULID>, <ULID>, ...]
  informs: []
```

The Validator enforces this symmetry on synthesis files just as it does on decision files.

Plus an optional top-level `spawns-threads` list:

```yaml
spawns-threads:
  - topic: <one-line description>
    why-deferred: <one paragraph>
    revisit-trigger: <condition under which to grill this>
    rough-size: small | medium | large
  - ...
```

The four-field shape of each thread (topic, why-deferred, revisit-trigger, rough-size) is required for any entry. Empty `spawns-threads` is omitted entirely, not declared as `[]`.

---

## Edge vocabulary

Four edge types are recognised. New types may be added only after a real case has appeared **twice** where none fit (the "twice before adding" discipline).

### `depends-on`

"This decision builds on the substance of decision X. If X were retracted, this decision would need re-evaluation."

Directionality: from this decision **to** the dependency. If decision A declares `depends-on: [<ULID-of-B>]`, then A's substance depends on B's substance.

Use when the new decision's `Chosen` or `Rationale` materially relies on a prior decision's substance.

### `supersedes`

"This decision retires decision X. X's `Chosen` no longer holds; this decision's `Chosen` replaces it."

Directionality: from the successor **to** the retired decision.

When a draft declares `supersedes: [X]`, the capture agent must in the same round:

1. Set X's `status` from `accepted` to `superseded`.
2. Optionally add a "Note" section at the end of X's body explaining what supersedes it (path-by-id, e.g., "Superseded by `<ULID-of-successor>`").

Do not edit X's `Chosen` or `Rationale` in place — that destroys history. The supersession edge plus the status flip is the entire mechanism.

### `informs`

"This decision influences decision X but X does not directly depend on it. Removing this would not invalidate X; it would change context."

Directionality: from the influencing decision **to** the influenced one.

`informs` is the weaker cousin of `depends-on`. Use when the relationship is real but not load-bearing. (Note: syntheses use `synthesizes`, not `informs`, to relate to the decisions they cover — see below.)

### `synthesizes` (synthesis files only)

"This synthesis integrates decisions X, Y, Z into a single narrative."

Directionality: from the synthesis file **to** the decisions it covers.

Synthesis files SHOULD include every decision from the batch they cover. Missing coverage is a Quality reviewer finding.

---

## Body structure

```markdown
# <Title — mirrors frontmatter `title`>

## Question
<One paragraph stating the fork. What was the choice? Why was it open?>

## Alternatives considered
- <Alternative 1> — <one-line gloss + why considered>
- <Alternative 2> — ...
- <Alternative 3> — ...
- <The Chosen option — list it here too with the others; the next section names which won>

## Chosen
<One or two paragraphs naming the chosen option and the shape of its implementation. Direct, declarative.>

## Rationale
<Two to five paragraphs explaining *why* this option won over the others. Address each non-chosen alternative explicitly: what it would have cost, what it would have prevented. This section is load-bearing — a thin `Rationale` is a Quality reviewer finding.>

## Assumptions
- <Assumption 1 — a belief this decision is contingent on>
- <Assumption 2>
- ...

## Note (optional)
<Use for ancillary information: links to related decisions, anticipated rewinds, archive-archaeology helpers. Omit if empty.>
```

### Section discipline

- **`Question`** — frames the fork. Should be answerable with the alternatives in the next section.
- **`Alternatives considered`** — at least two, typically three to five. Alternatives are mandatory; an empty list invalidates the decision. The chosen option appears here too (it's an alternative until it's selected).
- **`Chosen`** — declarative. No hedging. "We will use X" or "X is the choice", not "X might be a good option."
- **`Rationale`** — must address why non-chosen alternatives lost. Without explicit rejection notes, a future reader will not know whether the rejected options were considered or merely overlooked.
- **`Assumptions`** — the beliefs this decision rests on. Surfacing assumptions makes rewinds tractable: when an assumption turns out wrong, the decision is a candidate for supersession.
- **`Note`** — escape hatch for context that doesn't fit elsewhere. Optional, frequently omitted.

---

## Triple-filter

A fork merits a decision file only if **all three** of these hold:

1. **Hard to reverse.** Reversing the choice later will be expensive or destructive. Trivial preferences and easily-flipped settings do not qualify.
2. **Surprising without context.** Someone reading the codebase / archive cold would not arrive at this choice obviously. The decision encodes hidden knowledge.
3. **Real trade-off.** Genuinely-considered alternatives existed. A decision with no real alternatives (every option was equivalent, or only one was viable) is not a fork — it is just an implementation detail.

The Quality reviewer enforces this gate. If any of the three fails, the draft does not become a file; the discussion belongs in a synthesis or in code comments instead.

---

## Supersede mechanics

When the batch retires an existing decision:

1. **In the successor's frontmatter:** `supersedes: [<ULID-of-X>]`
2. **In X's frontmatter:** flip `status: accepted` → `status: superseded`
3. **In X's body (optional but recommended):** add a footer `## Note — Superseded by <successor-ULID>` with one or two sentences describing what changed.
4. **In the successor's `Rationale`:** explicitly name X and explain what its `Chosen` got wrong (or what changed underneath it).

Common patterns:
- "A supersedes B → A depends-on B" is **legitimate**: a successor often builds on its predecessor's framing even while retiring its `Chosen`. The `depends-on` plus `supersedes` combination is normal.
- "C depends-on B (where B is superseded by D, C is not the supersession)" is **suspect**: C likely depends on D's live principle, not B's retired framing. Re-target C's `depends-on` to D. The Auditor reviewer catches this and forces a redraft.

A draft cannot supersede a decision that is already superseded. The Auditor catches "supersedes-of-superseded" as a structural error.

---

## Synthesis structure

Synthesis files are optional, written at most once per batch. They cover the connective tissue decisions alone lose.

```markdown
---
id: <ULID string>
slug: <namespaced kebab-case>
title: <one line>
status: accepted
tags: [..., synthesis, ...]
edges:
  depends-on: []
  supersedes: []
  informs: []
  synthesizes: [<ULID>, <ULID>, ...]
spawns-threads:
  - topic: ...
    why-deferred: ...
    revisit-trigger: ...
    rough-size: ...
---

# <Title>

## What this is
<One paragraph: what session produced this synthesis, what arc it covers, where it sits in the archive (refresh of an earlier synthesis? new tree?).>

## The pivot — <or whatever frames this batch>
<The architectural narrative. Three to five paragraphs. Integrates the batch decisions into a coherent thesis — not a list-with-prose.>

## The supersede chain (when applicable)
<Table or list of what was retired and what replaced it.>

## Architecture restated (when applicable)
<Diagram or ascii flow if the batch reshaped how a system fits together.>

## What's deferred
<Pointer to the `spawns-threads` block in the frontmatter; one paragraph framing.>

## How the design will be validated
<Optional but valuable: how the user will know if this design is right.>
```

### Synthesis-specific quality bar (Quality reviewer enforces)

- `synthesizes` edges cover **every** decision in the batch. Missing coverage is `discrepancy`-grade.
- Each `spawns-threads` entry has all four fields (`topic`, `why-deferred`, `revisit-trigger`, `rough-size`). Empty/skeletal entries are `blocking`.
- The narrative is a **thesis**, not a list-with-prose. A synthesis that just re-states the decisions in order without integrating them adds nothing and the Quality reviewer flags it as a `discrepancy`.
- `spawns-threads` entries are substantive — topics worth grilling later, not "we should think about X someday." A thread with no concrete revisit-trigger is a `quality_note` (advisory) — push the author to sharpen it but don't gate the batch.

---

## When to write a decision vs a synthesis vs a thread

| Use a... | When... |
|---|---|
| **Decision** | The triple-filter holds. A real fork was closed off. The `Chosen` is specific and has a body's worth of rationale. |
| **Synthesis** | The session produced multiple decisions and there is connective tissue (an architectural reframe, a supersede chain, a diagram, follow-up topics) that does not fit inside any one decision. |
| **Thread** (`spawns-threads` entry) | A topic worth grilling later, deliberately deferred from this session. Not a decision because it hasn't been grilled. Not a synthesis section because there is no batch covering it yet. |

A single closed-off fork without a synthesis is fine. A synthesis without decisions is **not** fine — synthesis is connective tissue and needs at least one decision to connect.

Threads sometimes graduate to decisions (when they get grilled). Most do not — that is expected.
