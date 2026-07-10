# Skills

Opinionated, curated Claude Code skills — vendored from upstream sources (mattpocock-skills, superpowers, etc.) and drifted toward a personal style.

## Plugins

- **dev** — general development tooling
  - `manage-claude-md` — create, review, and improve `CLAUDE.md` files
  - `install-claude-sidecar` — install the Claude sidecar viewer
  - `tdd` — test-driven development with a red-green-refactor loop
  - `systematic-debugging` — finding root cause before applying a fix
  - `ponytail` — force the laziest solution that actually works — YAGNI, stdlib first, shortest diff
- **meta** — skills for maintaining this marketplace itself
  - `import-skill` — vendor a new skill from a GitHub upstream
  - `refresh-vendored` — reconcile vendored skills against upstream changes
  - `merge-skill` — shared core that reconciles two skill versions into one (used by the above)
- **productivity** — process and workflow skills
  - `grill-me` — stress-test a plan or design by interrogation
  - `write-a-skill` — author new skills with proper structure and progressive disclosure
  - `handoff` — compact the current conversation into a handoff doc for the next session
  - `capture-decision` — end-of-session capture into a decision archive via multi-agent review loop
  - `recall-decision` — mid-session lookup against a decision archive via a sub-agent digest
- **in-progress** — skills being actively authored or rewritten _(empty for now)_
- **deprecated** — skills phased out, kept installable during transitions _(empty for now)_

## Installation

1. Run `claude` inside any repo
2. `/plugin marketplace add mithredate/skills`
3. `/plugin install <plugin-name>@skills`

## Vendoring and maintenance

Most skills here are forks of upstream open-source work. Lifecycle:

- **Add a new vendored skill** — invoke `/import-skill`. Interactive: gathers upstream coords, clones, copies files into a target plugin, writes the canonical attribution footer with the fork-commit SHA, and updates `marketplace.json` and `NOTICES.md`.
- **Refresh existing vendored skills** — invoke `/refresh-vendored`. Surfaces upstream changes since the fork commit, lets you adopt or skip each change, and adjusts the attribution verb if local drift has shifted bands (`Adapted from` → `Inspired by` → `Originally seeded from`).

## Attribution

Each vendored `SKILL.md` carries a one-line footer at the bottom with the source URL (including the fork-commit SHA) and license. The repo-level summary lives in [`NOTICES.md`](NOTICES.md). Canonical footer format: [`meta/skills/import-skill/references/footer-format.md`](meta/skills/import-skill/references/footer-format.md).
