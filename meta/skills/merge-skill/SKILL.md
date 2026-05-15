---
name: merge-skill
description: Reconcile two versions of a skill into one. Reads a "current" version (your local) and an "incoming" version (fresh upstream, refreshed upstream, or another local skill), produces a semantic comparison with three-flag annotations, walks the user through per-item decisions, and applies accepted changes to the current version in place. Use when called by `import-skill` on conflict, by `refresh-vendored` for any refresh comparison, or directly with `/merge-skill <current-path> <incoming-path>` to absorb one skill into another.
---

# Merge Skill

Shared core for reconciling skill versions. `import-skill` delegates to this on naming conflicts; `refresh-vendored` delegates for every refresh. May also be invoked standalone.

## Inputs

- **current** — path to the local skill directory you want to keep editing. Receives all changes in place.
- **incoming** — path to the skill directory to merge from. May be a temp clone, another local skill, or anything readable as a skill directory.
- **incoming-sha** (optional) — when incoming is an upstream version with a known commit SHA, pass it. Used to update the footer's checkpoint SHA after a successful merge.

## Output

- `current` is rewritten in place with accepted changes.
- `incoming` is left untouched (it was a vehicle, not a destination).
- If `incoming-sha` was provided, the footer in `current/SKILL.md` is updated to that SHA; the verb (`Adapted from` / `Inspired by` / `Originally seeded from`) is recomputed based on the new local drift band.
- A summary is printed listing accepted, skipped, and adapted items.

## Process

Create a TodoWrite item per step when invoked.

### 1. Read both versions

Read every file under `current/` and `incoming/` (SKILL.md, references/, scripts/, etc.). Treat the skill as one cohesive unit.

### 2. Build a semantic comparison

Do **not** show a git diff. Read both versions and produce a structured list of items describing what differs. Each item is one logical unit (a section, a paragraph, a script behavior). Items are typically 3–7 per skill.

Annotate each item with one of three flags:

- **`upstream-new`** — content/idea present in incoming but absent in current. No direct overlap. Candidate for adoption.
- **`conflict`** — incoming and current both touch the same concept differently. The user's local drift directly contradicts incoming. Needs judgment.
- **`stale-divergence`** — current has content nowhere in incoming, and the surrounding context suggests it may be an old fork artifact the user forgot about. Surfaced for hygiene.

### 3. Present the comparison

Show all items grouped by flag. Brief summaries (1–2 sentences each), not raw diffs. Cite locations (`SKILL.md § "Process"`, `references/foo.md`, etc.).

### 4. Walk the user through decisions

For each item, ask: **adopt** (integrate into current), **skip** (deliberate divergence, don't touch current), or **adapt** (user describes a custom resolution). Process items one at a time.

`stale-divergence` items get a softer prompt: "this looks like content unique to your local; keep, drop, or adapt?"

### 5. Apply decisions

For each adopted/adapted item, edit the relevant file in `current/` directly. Confirm each edit's exact content before applying. Never silently overwrite. On any edit failure, abort and report.

### 6. Update footer (if applicable)

If `incoming-sha` was provided:
1. Compute the post-merge drift ratio: lines changed in current relative to incoming, summed across all skill files.
2. Map ratio to verb (< 30%: `Adapted from`; 30–80%: `Inspired by`; > 80%: `Originally seeded from`).
3. Rewrite the footer in `current/SKILL.md` with the new verb and new SHA. Preserve license, copyright, and source URL path. Format per [`../import-skill/references/footer-format.md`](../import-skill/references/footer-format.md).

If `incoming-sha` was not provided (merging two local skills), leave the footer alone.

### 7. Validate

Run the official validator against the plugin that owns `current` to confirm post-merge integrity:

```bash
claude plugin validate <plugin-dir-containing-current>
```

(e.g., if `current` is `productivity/skills/tdd/`, the plugin dir is `productivity`.)

On any validation error, surface the message and stop — do not declare merge successful. The user resolves before committing.

### 8. Report

Print:
- Items accepted / skipped / adapted (count + brief titles)
- Files modified
- New footer line if updated
- Suggested commit message

Leave the actual `git add` / `git commit` to the user.

## Edge cases

- **`current` and `incoming` are identical** → report "no changes," exit.
- **`incoming` is missing `SKILL.md`** → abort with a clear error; merge needs a valid skill on both sides.
- **Conflicting items where the user's intent is unclear** → ask follow-up questions before classifying. Don't guess.
- **A single accepted edit fails to apply cleanly** (e.g., the local file has drifted so far that the diff target text doesn't exist) → abort the run, surface the partial state, and let the user resolve manually.
- **No items to surface** (the agent reads both and finds nothing meaningful different) → still report explicitly; don't silently no-op.
