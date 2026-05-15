---
name: refresh-vendored
description: Refresh vendored skills against their upstream sources. For each vendored skill, fetches the current upstream version and delegates the reconciliation to `merge-skill`. Use when the user wants to check what's changed upstream, decide what to incorporate into local versions, and let the attribution verb shift as drift grows. Triggers on requests like "refresh vendored skills", "check upstream changes", "update from mattpocock", "see what's new upstream", or invocations of `/refresh-vendored`.
---

# Refresh Vendored Skills

Survey vendored skills, fetch each upstream's current state, hand off to `merge-skill` for the per-skill reconciliation. On-demand only — never scheduled.

This skill runs in a **dedicated git worktree per session**, never on `main` directly. The worktree is created at the start of the run on a `refresh/<date>` branch; all subsequent file edits happen in it. On success the skill commits and pushes the branch. On validation failure the worktree is left dirty for inspection. See CLAUDE.md § Worktree workflow for the mechanics.

Footer format reference: [`../import-skill/references/footer-format.md`](../import-skill/references/footer-format.md). The SHA in the footer is a **last-reviewed checkpoint**, not the original fork commit — it advances after every successful refresh whether the user adopted or skipped the changes.

## Prerequisites

- `git` and `gh` CLIs available
- Network access to GitHub
- At least one vendored skill (SKILL.md with a footer matching the canonical format)

## Process

Create a TodoWrite item per step when invoked.

### 1. Discover vendored skills

```bash
git grep -nE '^_(Adapted from|Inspired by|Originally seeded from) \[' -- '**/SKILL.md' \
  | grep -v '^deprecated/'
```

Note: `deprecated/skills/**` is **excluded** from refresh. Skills you've stopped using don't need reconciliation.

For each match, parse the footer to extract:
- Local skill directory path
- Upstream `owner/repo`, last-reviewed SHA, upstream skill path (from the `tree/<sha>/<path>` URL)
- Current footer verb

If a footer is malformed or missing the `/tree/<sha>/` component, flag and skip — user must fix manually.

Report the discovered list before proceeding.

### 2. Fetch upstream

Group skills by upstream `owner/repo`. For each unique upstream, clone once into a temp dir:

```bash
tmp=$(mktemp -d)
gh repo clone <owner>/<repo> "$tmp/<repo>" -- --depth=50
```

If the last-reviewed SHA isn't in the shallow history, deepen incrementally (`fetch --deepen=200`, cap ~1000) until it resolves or give up and flag.

### 3. Handle upstream restructure / deletion

For each skill, verify the upstream path still exists at HEAD:

```bash
git -C "$tmp/<repo>" cat-file -e HEAD:<upstream_path>/SKILL.md
```

If it doesn't:

```bash
git -C "$tmp/<repo>" log --follow --diff-filter=R --oneline -- <upstream_path>/SKILL.md
```

- **Rename candidates found** — surface the most plausible (`looks like this moved to <new-path> in commit <sha>; confirm?`). On user confirmation, retarget the upstream path for the rest of the refresh and update the footer URL when merge-skill rewrites it.
- **No candidates (likely deleted upstream)** — offer the user two outcomes:
  - **Keep local as fully forked** — recompute drift band, soften verb (probably `Originally seeded from`), preserve the link to the upstream's last existing commit.
  - **Delete local** — `git rm -r` the local skill, remove from `marketplace.json`, remove from `NOTICES.md`, and remove its bullet from the `## Plugins` section in `README.md` (restore the `_(empty for now)_` suffix on the plugin line if no skills remain).

### 4. Delegate reconciliation to merge-skill

For each vendored skill (whose upstream path is resolved or retargeted), invoke `merge-skill` with:

- **current** = the local skill directory (e.g., `productivity/tdd/`)
- **incoming** = `<tmp>/<repo>/<upstream_path>/` (upstream at HEAD)
- **incoming-sha** = the upstream HEAD SHA

`merge-skill` owns the actual comparison, three-flag annotation (`upstream-new`, `conflict`, `stale-divergence`), per-item decision loop, and footer rewrite. This skill is thin around that handoff.

If `merge-skill` reports "no changes," skip with a one-line note in the final summary.

### 5. NOTICES.md and README.md sync

After all skills are processed:
- If an upstream entry exists in `NOTICES.md` but no skill in the repo references it anymore (e.g., a skill was deleted in step 3), remove that entry.
- If a vendored skill changed upstream owner/repo via rename detection (rare — unrelated to path rename within the same repo), update the entry.
- Cross-check `README.md`'s `## Plugins` section against the actual skill set: every `<plugin>/skills/<name>/` directory should have a bullet under its plugin, and no stale bullets should remain. Restore the `_(empty for now)_` suffix on any plugin whose skills are all gone.

Propose edits; don't apply automatically.

### 6. Report and commit guidance

Print:
- Per-skill: adopted/skipped/adapted counts, footer changes (SHA bump and/or verb change)
- Files modified
- A suggested commit message, e.g.:
  ```
  refresh: pull updates from mattpocock-skills

  - productivity/grill-me: 2 items adopted, SHA bump
  - productivity/tdd: 1 item adopted; verb re-banded to "Inspired by" (52% drift)
  ```

Leave the actual `git add` / `git commit` to the user.

## Output discipline

- Cite SHA-precise upstream links in every claim.
- Never auto-commit, never silently rewrite a SKILL.md.
- Per-skill review is **semantic, not mechanical** — that work lives in `merge-skill`.

## Edge cases

- **Footer missing or malformed** → flag, skip, ask user to fix manually.
- **Last-reviewed SHA can't be resolved even after deepening to depth 1000** → flag; propose using the upstream's earliest available commit as a fallback (any further refresh comparisons will overreport changes once, then normalize).
- **`merge-skill` aborts mid-skill** (e.g., a patch failed to apply cleanly) → surface the partial state, skip remaining skills until the user resolves, don't continue blindly.
- **Multiple vendored skills from the same upstream** → clone once in step 2; reuse the temp dir.
