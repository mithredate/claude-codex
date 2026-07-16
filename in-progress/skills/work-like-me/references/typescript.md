# TypeScript rubric

Conventions for TypeScript code. Applies when writing TS or reviewing a diff that touches it.

## Types carry the logic

- **Union types over `string`** (and over enums). Anything the type system can enforce moves into the types — invalid states should not compile.
- **One source of truth** for a constant set and its type: define the const object and derive the union from it (`as const satisfies Record<string, T>`, `keyof typeof`), never a const object and a hand-maintained parallel type.
- No `any` without a stated reason at the usage site.

## Constants and naming

- **No magic literals.** String and numeric literals with meaning get extracted to a named constant — and the extraction replaces *every* usage, not just the new one.
- Names are precise and domain-correct. A name that misstates what the thing is (`variables` for a config map, `actor` for a user id) gets renamed on sight.

## Structure

- **Writes are actions, queries are reads** — name and organize them that way (CQRS-flavored). Keep the split consistent across layers, including file and branch naming.
- **No generic `update` operations.** Domain operations get specific, intention-revealing actions (`approve`, `decline`, `reopen`). Shared mechanics get extracted into a composable/helper the specific actions use.
- Business logic does not live in handlers/controllers. State rules (allowed transitions, invariants) belong to the domain layer, not passed in by the caller.
- **Check existing utils before writing new code.** Grep `utils/`, sibling components, and shared modules first; extract copy-pasted logic to a shared home instead of adding a third copy.
- Types used by more than one module move to the shared types location (`shared/`, `app/types/`) — no duplicated type definitions, no types defined inside components.

## API evolution

- Never break an API silently. Deprecate explicitly: rename with a `deprecated` prefix (so usage is visible), stand up the new version in parallel, and migrate clients before deleting.
