---
name: import-skill
description: Import a skill from a GitHub upstream into this repo as a vendored fork. Clones the upstream, copies files into a target plugin (dev/productivity/in-progress/deprecated), writes the canonical attribution footer with the fork-commit SHA, updates marketplace.json, and appends to NOTICES.md. Use when the user wants to vendor a new skill from an external repo, pull in a skill from mattpocock-skills or superpowers or any other GitHub source, or invokes /import-skill.
---

# Import Skill

Vendor a skill from a GitHub upstream into this repo as a curated fork. Interactive — gathers inputs, previews the plan, then runs a deterministic Node script to perform the copy.

Pairs with [refresh-vendored](../refresh-vendored/SKILL.md). The two share a footer-format spec — see [`references/footer-format.md`](references/footer-format.md).

## Process

Create a TodoWrite item per step when invoked.

### 1. Gather inputs (one prompt at a time)

Ask the user:
1. **Upstream repo** in `<owner>/<repo>` form (e.g., `mattpocock/mattpocock-skills`).
2. **Upstream path** within that repo to the skill directory (e.g., `skills/productivity/grill-me`).

If the user is vague ("vendor grill-me from mattpocock"), help disambiguate by running `gh search code` or by cloning and `find … -name SKILL.md`.

### 2. Verify the upstream path

Clone the upstream shallowly into a temp dir:

```bash
tmp=$(mktemp -d)
gh repo clone <owner>/<repo> "$tmp/<repo>" -- --depth=1
```

Confirm `<tmp>/<repo>/<upstream_path>/SKILL.md` exists. If not, error and re-prompt for the path.

### 3. Pick target plugin

Show the four candidate plugins (`dev`, `productivity`, `in-progress`, `deprecated`) with one-line descriptions and the count of existing skills in each. Ask which one. Recommend based on the skill's nature: process-flavored → `productivity`; tooling → `dev`; uncertain or being-drifted → `in-progress`.

### 4. Recommend a target name (always — not only on conflict)

1. List existing skill directory names in `<target_plugin>/skills/`.
2. Identify the local naming convention (verb-first hyphenated? noun-only?).
3. Default to the upstream skill's directory name.
4. If that name conflicts, propose a renamed variant (e.g., `<name>-<upstream-owner>`).
5. If no conflict but the name doesn't match local convention, propose an adjusted variant.
6. Present the recommendation; let the user confirm or override.

Never silently overwrite. If the user insists on overwriting, refuse and instruct them to delete the existing skill manually first.

### 5. Capture upstream metadata

```bash
git -C "$tmp/<repo>" rev-parse HEAD                # fork SHA
head -20 "$tmp/<repo>/LICENSE"                     # license + copyright
```

Parse:
- **License** (e.g., `MIT`, `Apache-2.0`).
- **Copyright holder + year** (e.g., `© 2026 Matt Pocock`).

If no `LICENSE` at upstream repo root, prompt the user for the values manually.

### 6. Preview the plan

Show the user:
- Source files to copy
- Target directory (`<target_plugin>/skills/<target_name>/`)
- Full footer text to be appended to `SKILL.md` (see [`references/footer-format.md`](references/footer-format.md))
- `marketplace.json` entry to insert
- `NOTICES.md` block to add or update

Wait for explicit confirmation before proceeding.

### 7. Run the import script

```bash
node in-progress/skills/import-skill/scripts/import.mjs \
  --upstream <owner>/<repo> \
  --upstream-path <upstream_path> \
  --upstream-sha <sha> \
  --license <license> \
  --copyright '<copyright>' \
  --target-plugin <target_plugin> \
  --target-name <target_name>
```

The script handles file copy, footer write, `marketplace.json` edit, and `NOTICES.md` update deterministically. On non-zero exit, surface the error and stop.

### 8. Report and suggest commit

Show files created, files modified, and a suggested commit message:

```
vendor: import productivity/grill-me from mattpocock-skills
```

Leave the actual `git add` / `git commit` to the user.

## Edge cases

- **Upstream private or gated** — `gh repo clone` prompts for auth; surface errors.
- **No `LICENSE` at upstream root** — prompt user for license + copyright manually.
- **Target plugin not registered in `marketplace.json`** — script fails; instruct user to register first.
- **Upstream directory contains nested skill dirs** — only the top-level SKILL.md and its sibling files (`references/`, `scripts/`, etc.) are copied. Nested skills are not recursed into.
- **Upstream skill has no `SKILL.md`** — verify in Step 2; refuse to proceed.
