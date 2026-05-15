---
name: refresh-vendored
description: Refresh vendored skills against their upstream sources. Use when the user wants to check if upstream repositories have new commits since the fork point, decide whether to incorporate them, and update attribution wording as local drift grows. Triggers on requests like "refresh vendored skills", "check upstream changes", "update from mattpocock", "see what's new upstream", or invocations of `/refresh-vendored`.
---

# Refresh Vendored Skills

Check vendored skills against their upstream sources. Surface upstream changes since the fork point. Help the user decide what to incorporate. Adjust attribution wording when local drift grows.

## When to use

Invoke when the user asks to check upstream updates, refresh vendored skills, or reconcile drift. On-demand only — this skill is never scheduled.

## Prerequisites

- `git` and `gh` CLIs available
- Network access to GitHub
- At least one vendored skill in the repo (SKILL.md with a footer link pointing to a commit URL)

## Footer format the skill parses

Every vendored skill carries one of these one-line footers at the bottom of its `SKILL.md`:

```
_Adapted from [<upstream-name>/<skill-path>](<url>/tree/<sha>/<path>) — <license> © <year> <holder>._
_Inspired by [<upstream-name>/<skill-path>](<url>/tree/<sha>/<path>) — ..._
_Originally seeded from [<upstream-name>/<skill-path>](<url>/tree/<sha>/<path>) — ..._
```

The verb encodes the current drift band. The SHA inside `/tree/<sha>/` is the **fork commit** and the anchor for all upstream comparisons.

## Process

Create a TodoWrite item per step below when invoked.

### 1. Discover vendored skills

```bash
git grep -nE '^_(Adapted from|Inspired by|Originally seeded from) \[' -- '**/SKILL.md'
```

For each hit, extract:
- Local file path
- Upstream `owner/repo`, fork SHA, upstream skill path (parse from the `tree/<sha>/<path>` URL)
- Current footer verb

If a footer is malformed or missing the `/tree/<sha>/` component, flag it and skip — the user must fix it manually before refresh can compare anything.

Report the discovered list before proceeding.

### 2. Fetch upstream

For each unique upstream `owner/repo`, clone shallowly into a temp dir:

```bash
tmp=$(mktemp -d)
gh repo clone <owner>/<repo> "$tmp/<repo>" -- --depth=50
```

If the fork SHA isn't in the shallow history, deepen:

```bash
git -C "$tmp/<repo>" fetch --deepen=200 origin
```

Keep deepening (cap ~1000) until the fork SHA resolves or give up and flag.

### 3. Compute γ (upstream changes since fork)

For each vendored skill:

```bash
git -C "$tmp/<repo>" diff --stat <fork_sha>..HEAD -- <upstream_path>
```

Two outcomes:
- Empty diff → upstream unchanged at this path. Mark "up-to-date".
- Non-empty → mark as a γ candidate for review.

### 4. Compute β (local drift since fork)

For each vendored skill:

```bash
git -C "$tmp/<repo>" show <fork_sha>:<upstream_path>/SKILL.md > "$tmp/original.md"
git diff --no-index --shortstat "$tmp/original.md" <local_skill_md>
```

Drift ratio = `(insertions + deletions) / original_line_count`.

Bucket:
- `< 30%`  → low → footer verb should be **"Adapted from"**
- `30–80%` → medium → **"Inspired by"**
- `> 80%`  → high → **"Originally seeded from"**

If a skill has sub-files (`references/`, `scripts/`, etc.), include them in the line counts. The drift band reflects the whole skill, not just `SKILL.md`.

### 5. Survey summary

Present a table:

```
Skill                          | γ (upstream) | β (your drift) | Current verb        | Suggested verb
-------------------------------|--------------|----------------|---------------------|--------------------
productivity/grill-me          | 3 commits    | 12% (low)      | Adapted from        | (unchanged)
productivity/tdd               | none         | 45% (medium)   | Adapted from        | Inspired by
in-progress/foo                | 2 commits    | 85% (high)     | Adapted from        | Originally seeded from
```

Highlight:
- **γ updates** → candidates for review (Step 6)
- **Verb mismatch** between current and suggested → attribution language is stale (Step 7)

Ask the user where to start. Default order: γ candidates first (substantive), then verb fixes (cosmetic).

### 6. Interactive review per γ candidate

For each γ candidate:

1. Run `git -C "$tmp/<repo>" log --oneline <fork_sha>..HEAD -- <upstream_path>` and summarize commit messages.
2. Run `git -C "$tmp/<repo>" diff <fork_sha>..HEAD -- <upstream_path>` and walk the hunks with the user.
3. For each meaningful upstream change, ask: **adopt, skip, or adapt?**
   - **Adopt** — patch the local file with the upstream change.
   - **Skip** — note the deliberate divergence; do nothing.
   - **Adapt** — let the user dictate the local version inline.
4. After all hunks are processed, update the fork SHA in the footer to the new upstream HEAD SHA so the next refresh diff is bounded.

Never silently overwrite. Every patch goes through user confirmation.

### 7. License language check (β)

For each skill where current verb ≠ suggested verb (per Step 4 bucket):

1. Show the current footer line.
2. Show the proposed new footer line — same URL, same copyright, only the verb changes.
3. Ask the user to confirm or override.
4. **Always preserve the upstream link** even at >80% drift. The link is the MIT-compliance anchor and honest lineage.

The skill suggests; the user decides.

### 8. NOTICES.md sync

After processing, check whether any upstream entry in `NOTICES.md` needs updating (new upstream introduced, or a previously-vendored upstream now has zero vendored skills). Propose edits; don't apply automatically.

### 9. Commit guidance

Print a suggested commit message summarizing the run, e.g.:

```
refresh: pull updates from mattpocock-skills

- productivity/grill-me: adopt 2 upstream commits, bump fork SHA
- productivity/tdd: re-band to "Inspired by" (45% drift)
```

Leave the actual `git add` / `git commit` to the user.

## Output discipline

- Terse summary tables; raw diff output when reviewing hunks.
- Cite SHA-precise upstream links in every claim ("upstream commit `abc1234` changed …").
- Never auto-commit. Never silently rewrite a SKILL.md.

## Edge cases

- **Footer missing or malformed** → flag and skip; user must fix manually.
- **Fork SHA can't be resolved even after deepening** → flag, propose using the merge-base of `main` and the closest annotated tag as a fallback anchor.
- **Upstream repo renamed/deleted** → flag, ask the user to update the URL.
- **Local skill rewritten from blank page (no inherited content)** → β shortstat will dominate; band is "high", verb becomes "Originally seeded from". If the user objects ("there's nothing of theirs left"), tell them to drop the footer manually — the skill won't propose dropping the link.
- **Multiple vendored skills from the same upstream** → clone once, reuse the temp dir for all of them.
