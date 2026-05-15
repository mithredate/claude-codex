# Vendored-Skill Footer Format

Canonical spec for the attribution footer at the bottom of every vendored `SKILL.md`. Both [`import-skill`](../SKILL.md) (writer) and [`refresh-vendored`](../../refresh-vendored/SKILL.md) (reader) depend on this format.

## Format

```
---
_<Verb> [<owner>/<repo>/<upstream-path>](https://github.com/<owner>/<repo>/tree/<sha>/<upstream-path>) — <license> <copyright>._
```

### Components

- **Verb** — encodes the current drift band:
  - `Adapted from` — local drift < 30%
  - `Inspired by` — local drift 30–80%
  - `Originally seeded from` — local drift > 80%
- **owner/repo/upstream-path** — human-readable identifier of the source skill.
- **URL** — must include `/tree/<sha>/<path>`. `<sha>` is the **fork commit**: the upstream SHA at which the skill was last reviewed/refreshed. Initially set by `import-skill` at vendor time, then updated by `refresh-vendored` whenever the user adopts upstream changes.
- **license** — SPDX identifier (e.g., `MIT`, `Apache-2.0`).
- **copyright** — `© <year> <holder>` (e.g., `© 2026 Matt Pocock`).

### Examples

```
---
_Adapted from [mattpocock/skills/skills/productivity/grill-me](https://github.com/mattpocock/skills/tree/b39bb0b27867/skills/productivity/grill-me) — MIT © 2026 Matt Pocock._
```

```
---
_Inspired by [mattpocock/skills/skills/engineering/tdd](https://github.com/mattpocock/skills/tree/abc1234/skills/engineering/tdd) — MIT © 2026 Matt Pocock._
```

## Parsing rules

The leading `---` is a markdown horizontal rule, on its own line, immediately before the italic footer line. The footer line MUST match this anchored regex:

```
^_(?<verb>Adapted from|Inspired by|Originally seeded from) \[(?<label>[^\]]+)\]\((?<url>https://github\.com/(?<owner>[^/]+)/(?<repo>[^/]+)/tree/(?<sha>[a-f0-9]+)/(?<path>[^)]+))\) — (?<license>\S+) (?<copyright>©[^.]+)\._$
```

Skills whose footer doesn't match are flagged by `refresh-vendored` as malformed and skipped until fixed manually.
