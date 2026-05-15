---
name: import-skill
description: Import a skill from a GitHub upstream into this repo. Clones the upstream, picks a target plugin, and either does a fresh copy (when the target name is free) or delegates to `merge-skill` to reconcile into an existing local skill of the same concept. Never creates a parallel skill alongside an existing one — merge or abort. Use when the user wants to vendor a new skill from an external repo, pull in a skill from mattpocock-skills or superpowers or any other GitHub source, or invokes /import-skill.
---

# Import Skill

Vendor a skill from a GitHub upstream. Interactive — gathers inputs, picks a target, and forks to one of two paths:
- **Fresh import** (no concept conflict): copy files, write footer, register in `marketplace.json` and `NOTICES.md`.
- **Conflict** (a local skill of the same concept already exists): delegate to [`merge-skill`](../merge-skill/SKILL.md) to reconcile incoming into the existing skill. **Never** creates a parallel skill.

Pairs with [`refresh-vendored`](../refresh-vendored/SKILL.md). All three share the canonical footer format in [`references/footer-format.md`](references/footer-format.md).

This skill runs in a **dedicated git worktree per session**, never on `main` directly. The worktree is created after Step 4 (target name resolved); all subsequent file edits happen in it. On success the skill commits and pushes the branch. On validation failure the worktree is left dirty for inspection. See CLAUDE.md § Worktree workflow for the mechanics.

## Process

Create a TodoWrite item per step when invoked.

### 1. Gather inputs (one prompt at a time)

Ask the user:
1. **Upstream repo** in `<owner>/<repo>` form (e.g., `mattpocock/skills`).
2. **Upstream path** within that repo (e.g., `skills/productivity/grill-me`).

If the user is vague ("vendor grill-me from mattpocock"), help disambiguate by running `gh search code` or cloning and `find … -name SKILL.md`.

### 2. Verify the upstream path

```bash
tmp=$(mktemp -d)
gh repo clone <owner>/<repo> "$tmp/<repo>" -- --depth=1
```

Confirm `<tmp>/<repo>/<upstream_path>/SKILL.md` exists. If not, error and re-prompt.

### 3. Pick target plugin

Show the user the registered plugins (`dev`, `productivity`, `meta`, plus any others) with one-line descriptions and the count of existing skills in each. Ask which one. Recommend based on the skill's nature: process-flavored → `productivity`; tooling → `dev`; repo-self-maintenance → `meta`; uncertain or actively-being-drifted → `in-progress`.

`deprecated` is not a valid import target.

### 4. Resolve target name — fresh import or merge?

Default to the upstream skill's directory name (e.g., `grill-me`). The naming rule is **verb-first hyphenated**; never try to "improve" the upstream name linguistically — the user overrides if they want.

Check `<target_plugin>/skills/<name>/`:
- **No conflict** → proceed to **Fresh import** path (Steps 5–8).
- **Conflict** (a skill of that name already exists, possibly itself vendored from a different upstream) → ask the user: **merge** into the existing skill, or **abort** the import. Renamed parallel variants are **not** offered — the duplicate-skills policy forbids running two forks of the same concept side by side.
  - If **merge** → proceed to **Merge path** (Step 9).
  - If **abort** → stop with no changes.

### 5. Capture upstream metadata (fresh import path)

```bash
git -C "$tmp/<repo>" rev-parse HEAD                # checkpoint SHA
head -20 "$tmp/<repo>/LICENSE"                     # license + copyright
```

Parse the **license** (e.g., `MIT`, `Apache-2.0`) and **copyright** (e.g., `© 2026 Matt Pocock`). If no `LICENSE` at upstream root, prompt the user.

### 6. Preview the plan (fresh import path)

Show:
- Source files to copy
- Target directory (`<target_plugin>/skills/<target_name>/`)
- Footer text to be appended to `SKILL.md` (per [`references/footer-format.md`](references/footer-format.md))
- `marketplace.json` entry to insert
- `NOTICES.md` block to add or update

Wait for explicit confirmation.

### 7. Run the import script (fresh import path)

```bash
node meta/skills/import-skill/scripts/import.mjs \
  --upstream <owner>/<repo> \
  --upstream-path <upstream_path> \
  --upstream-sha <sha> \
  --license <license> \
  --copyright '<copyright>' \
  --target-plugin <target_plugin> \
  --target-name <target_name>
```

Surface and stop on any non-zero exit.

### 8. Structural review (fresh import path)

The script copies upstream files verbatim, preserving whatever layout the upstream author used. That keeps the post-import state an exact mirror of upstream (so any later edits are unambiguously *your* drift) but it may not match local conventions.

Inspect the freshly imported skill directory. Surface structural mismatches to the user **as suggestions, one at a time**. Common cases:

- **Doc-like files alongside `SKILL.md`** (e.g., `REFERENCE.md`, `EXAMPLES.md`, `FORMS.md`) → propose moving into `references/`. Local convention is doc files live in `references/`, not at skill root.
- **Loose scripts at skill root** → propose moving into `scripts/`.
- **Asset-like files** (`.png`, `.svg`, templates) → propose moving into `assets/`.
- **`SKILL.md` body in unusual order** (e.g., missing the `## When to use` section common to local skills) → flag only; don't auto-rewrite content.

For each suggestion: show the move/edit, ask **yes / skip**, apply only on yes. Never silently rewrite. After the review, if any moves were applied, update any in-`SKILL.md` references (e.g., `[REFERENCE.md](REFERENCE.md)` → `[references/REFERENCE.md](references/REFERENCE.md)`).

If the user accepts no suggestions, the skill stays an exact upstream mirror — that's fine.

### 9. Validate (fresh import path)

Run the official validator against the target plugin to confirm the freshly imported (and possibly restructured) skill is well-formed:

```bash
claude plugin validate <target_plugin>
```

On any validation error, surface the message and stop — do not declare the import successful. The user resolves the issue (typically a footer or frontmatter problem) before committing.

### 10. Report (fresh import path)

Show files created, files modified, and a suggested commit message:

```
vendor: import productivity/grill-me from mattpocock-skills
```

Leave the actual `git add` / `git commit` to the user.

### 11. Merge path: delegate to merge-skill

When the user chose **merge** in Step 4:

1. Resolve upstream SHA: `git -C "$tmp/<repo>" rev-parse HEAD`.
2. Invoke [`merge-skill`](../merge-skill/SKILL.md) with:
   - **current** = the existing local skill directory (`<target_plugin>/skills/<target_name>/`)
   - **incoming** = `<tmp>/<repo>/<upstream_path>/`
   - **incoming-sha** = the upstream HEAD SHA captured above
3. `merge-skill` handles the comparison, decision loop, file edits, and footer rewrite. This skill is done — surface its output verbatim.
4. If the existing local skill has its own footer pointing to a *different* upstream than the one being merged in, flag this as ambiguous and ask the user how to record provenance after the merge (typically: keep the existing footer's upstream as primary; mention the merged-in source in `NOTICES.md` as an additional contributor).

After merge-skill returns, suggest a commit message like:

```
merge: absorb superpowers/tdd into productivity/tdd
```

## Edge cases

- **Upstream private or gated** — `gh repo clone` prompts for auth; surface errors.
- **No `LICENSE` at upstream root** — prompt user for license + copyright manually.
- **Target plugin not registered in `marketplace.json`** — fail; instruct user to register first.
- **Upstream directory contains nested skill dirs** — only the top-level SKILL.md and its sibling files (`references/`, `scripts/`, etc.) are copied (fresh import) or compared (merge). Nested skills are not recursed into.
- **Upstream skill has no `SKILL.md`** — verify in Step 2; refuse to proceed.
- **Merge path with a non-vendored local skill** (the existing skill is fully authored by the user, no footer) — proceed with merge anyway; the footer is *added* during merge-skill's Step 6 since `incoming-sha` is provided.
