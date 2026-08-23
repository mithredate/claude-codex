# Testing rubric

How tests should be written and judged. Applies when writing tests, changing tests, or reviewing a diff that touches them.

## What a test is for

- Tests verify **behavior, not implementation**. The bar for every test: would it catch a future regression? A test that locks in implementation details fails that bar.
- Prefer integration-style tests with **real round-trips** (real DB, real HTTP layer) over mocking the world. Mock at system boundaries you don't own; don't mock your own layers to make a unit "pure".
- Use mock libraries sparingly. Before reaching for a mock, ask whether a real fixture plus a real call path covers it.
- **DAMP over DRY** in test code: a test should read as a self-contained story. Duplication that aids readability beats an abstraction that hides the scenario.

## Fixtures

- **Reuse before creating.** Never introduce a parallel fixture builder for an entity that already has one — search `tests/fixtures/` first.
- **Placement follows usage scope**: builders used by multiple test files live in `tests/fixtures/` (organized per layer); builders used by a single test file stay local to that file.
- **Compose, don't fork.** Derive variants by transforming an existing builder (`toUserDTO(makeUser(...))`) instead of writing a sibling builder.
- **Name by layer.** A fixture's name states what layer it builds: `makeUser` for a domain entity, `makeUserResponseDto` for the API DTO. "Record", "data", "obj" are not layers.

## Coverage

- Coverage is a **ratchet**: it may only increase. A diff that lowers coverage needs an explicit justification.
- **State machines and transition matrices get exhaustive coverage.** Every cell — including the rejection/4xx cells — is a test. A missing cell is a review finding, not a nice-to-have.
- When the app breaks but the suite is green, treat the suite as the second bug: identify which missing test would have caught it, and add it.

## Flakiness

- Zero tolerance. A flaky test is either fixed or deleted — never retried into submission.
- Time-based assertions must be bounded, not exact: capture `before` and `after` timestamps and assert `before <= result <= after`.
- Timestamp assertions compare named `Date` variables via `.toISOString()` — no inline date construction inside `expect`.
