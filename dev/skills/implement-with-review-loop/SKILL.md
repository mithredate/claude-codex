---
name: implement-with-review-loop
description: >-
  Implement code changes — fixes, features, refactors, or substantive chores — under a TDD + review loop. Trigger when the user has approved a plan and asked for implementation, or uses phrases like "implement X", "add feature Y", "fix bug Z", "refactor M", "build out the auth flow". Use this skill even when the user does not explicitly ask for review — review is the default for substantive changes. Do NOT trigger for read-only tasks (analysis, exploration, summarization), trivial one-line edits the user explicitly asks to apply directly, or work in a repo with no runnable test command.
---

# Implement with review loop

Deliver a code change using an evaluator-optimizer loop with two specialized subagents (implementer + reviewer) and a hard iteration cap. Read this whole file before spawning the first subagent.

This skill depends on the `tdd` skill being available. If it is not, stop and tell the user.

## The unit of work: `work_item`

This skill applies to any **work item**: a fix, feature, refactor, or substantive chore. A work item is a unit you can describe with:

- `id` — stable label (e.g., `BUG-417`, `FEAT-auth-magic-link`)
- `type` — `fix` | `feature` | `refactor` | `chore`
- `summary` — one-line statement of the change
- `scope` — for `fix`/`refactor`/`chore`: an explicit file/module allow-list. For `feature`: a directive like "new files allowed under `<dir>`".
- `acceptance_criteria` — what the change must produce; observable, not aspirational
- `rationale` — the upstream design context (see below). Required.

If any of these are missing or ambiguous, **stop and ask the user before spawning any subagent**. Do not infer scope or rationale silently.

### `rationale` — what it must contain

The reviewer cannot evaluate design soundness without seeing the upstream thinking. Capture, in 5–15 lines:

- The problem in one sentence (what user-visible symptom or requirement).
- The root cause as currently understood, if applicable.
- Alternatives considered and explicitly rejected (one line each, with the reason).
- The chosen approach in one sentence.
- Residual risks the user has explicitly accepted ("we know X edge case is unhandled; that is intentional").

Without explicit rejection notes, a creative reviewer will manufacture false positives flagging tradeoffs that were already decided.

## Commands you must confirm up front

Before the loop runs, identify and confirm:

- `test` — full-suite command (e.g., `pnpm test`, `pytest -q`, `flutter test`)
- `lint` — e.g., `pnpm lint`, `ruff check .`, `flutter analyze`
- `typecheck` — e.g., `pnpm tsc --noEmit`, `mypy .` (often subsumed by `flutter analyze`)

If a project lacks any of these, say so and either (a) ask the user how to substitute, or (b) skip that DoD criterion and note it in the commit message. Do not invent commands.

## Diff invariant (applies to every subagent every iteration)

The `diff` field, wherever it appears in this skill, is **always produced by `git diff <base_sha>`** (no second ref), where `<base_sha>` is the work item's base commit captured at pre-flight. This single-ref form deliberately captures everything since base — committed, staged, and unstaged — so the diff represents the full cumulative change that would land if we committed right now. It is never the incremental diff since the last iteration.

The intended workflow is **uncommitted accumulation**: the implementer leaves changes in the working tree across rounds, and step D produces the single commit at the end. If the implementer chooses to commit intermediate snapshots during its own work (e.g., for safety), the `git diff <base_sha>` form still captures them, but step D's single-commit-per-work-item rule still holds and may require a squash on the implementer's side before reporting the final diff.

The reviewer must always evaluate the whole change against DoD, never just the delta from the prior round.

## Pre-flight

Before spawning anything, capture `<base_sha> = git rev-parse HEAD` for the diff invariant, run the **doc-scope check** (if `acceptance_criteria` involves user-visible behavior or a public-API change, `scope` must include the doc files that need updating — README, CHANGELOG, relevant docstring paths — or DoD #7 cannot be satisfied), and pause to ask the user if any input is ambiguous (an undefined `scope` or an unclear `rationale`). If the inputs name more than one work item, process them **strictly sequentially** — the diff invariant assumes a single linear writer on the working tree, so parallel execution is not supported.

## Per-work-item loop

Each subagent spawn is a fresh context. State is carried by what **you** pass in, not by subagent memory.

### A. Implementer subagent (round 1, and every retry)

Spawn one implementer with:

- **Objective**: deliver the work item satisfying `acceptance_criteria` and the DoD below.
- **Inputs (always — same on every round)**:
  - `id`, `type`, `summary`, `scope`, `acceptance_criteria`, `rationale`
  - The full Definition of Done (verbatim — see below)
  - The work item's base commit SHA
- **Inputs (retries only — additions, not substitutions)**:
  - The previous full cumulative diff (`git diff <base_sha>` at the end of the prior round)
  - The reviewer's verdict JSON from the prior round
  - Mode directive: **"Surgical fix mode — you operate on the same worktree across retries. The prior diff is shown to you as context for what is already in place, not as a patch to apply. Address every `blocking` item from the verdict without regressing unchanged regions. Do not rewrite working code or expand scope. If you believe a blocker requires a larger restructure than the prior approach supports, return `plan_broken` with evidence rather than silently expanding."**
- **Method**: use the `tdd` skill for the red-green-refactor discipline. The failing test must exercise `acceptance_criteria`. Two type-specific notes: for `refactor`, existing tests must stay green; if coverage of the touched area is thin, add characterization tests first to pin current behavior. For `chore` with no behavior change (doc-only, config-only, dep-bump), TDD relaxes to "the relevant smoke test or build still passes" — state the relaxation in `rationale_out`.
- **Boundaries**:
  - Do not modify files outside `scope`.
  - Do not touch unrelated tests.
  - Do not add new runtime dependencies without flagging in `rationale_out`.
- **Escape hatch — `plan_broken` / `setup_blocked`**: if while implementing the plan you discover the plan itself is wrong (the approach won't compile, the root cause diagnosis is incorrect, a hidden constraint contradicts the approach, the test you write to demonstrate the bug doesn't actually fail), **stop and return `status: "plan_broken"`** with evidence. Similarly, if the test harness cannot pump the relevant widget/module in isolation despite reasonable effort, return `status: "setup_blocked"` rather than mocking the world. Do not paper over a broken plan to produce a passing diff.
- **Required output** (exact shape):
  ```json
  {
    "status": "complete" | "plan_broken" | "setup_blocked",
    "diff": "<output of `git diff <base_sha>` — full cumulative change since base, committed or uncommitted; empty if status != complete>",
    "new_or_modified_tests": ["<test identifier in your runner's format — e.g., 'src/foo.test.ts > describe > it' (jest/vitest), 'package/file_test.go::TestName' (go), 'Tests\\FooTest::testBar' (phpunit), 'test/foo_test.dart::test description' (flutter)>", "..."],
    "commands_run": ["<test cmd>", "<lint cmd>", "<typecheck cmd>"],
    "rationale_out": "<≤10 lines: what changed and why; flag deps, scope notes, TDD relaxations>",
    "blocker_evidence": "<only when status != complete: what you tried, what failed, why it shows the plan/setup is broken>"
  }
  ```

If implementer returns `plan_broken` or `setup_blocked`, **do not iterate** — escalate to the user with the evidence. The implementer cannot fix a broken plan by retrying.

### B. Reviewer subagent

**The reviewer's invocation is identical on every iteration.** No "this is round N" framing, no awareness of the prior verdict, no list of "blockers we asked you to recheck." The reviewer always re-derives the verdict from scratch against the full cumulative diff. Carrying state across rounds would bias the reviewer toward confirming its prior position and would let regressions in previously-clean regions slip through.

Spawn one reviewer (separate context — no shared state with implementer). Pass:

- `id`, `type`, `summary`, `acceptance_criteria`, **`rationale`** (so the reviewer can reason about design soundness, not just compliance)
- The full Definition of Done
- The implementer's output JSON (which contains the full cumulative diff per the invariant above)
- The rubric below
- **Evidence filter: every entry in `blocking`, `design_blockers`, or `design_notes` must cite at least one concrete `file:line` location and state what the cited code shows. The cited location may be anywhere in the repository — it is not restricted to lines in the diff. (Cross-cutting design concerns about platform version, downstream consumers, security, or accessibility often need to anchor on unchanged files that interact with the diff.) Hunches and stylistic preferences without code-anchored evidence do not qualify and must be dropped, not downgraded to `non_blocking`.**

The reviewer **must independently re-run** `test`, `lint`, and `typecheck` against the applied diff using its own shell access. The implementer's claim that commands passed is not sufficient evidence. The reviewer must not substitute reading the diff or reasoning about likely outcomes for actually executing the commands. If the reviewer believes it cannot run shell tools in its environment, it must return `status: "fail"` with a single blocking item: `"reviewer lacks shell access — cannot verify"`. This is a hard rule, not a stylistic preference.

**Required output** (exact shape):
```json
{
  "status": "pass" | "fail" | "escalate",
  "commands_run": ["<test cmd>", "<lint cmd>", "<typecheck cmd>"],
  "verification_evidence": {
    "test":      {"exit_code": 0, "excerpt": "<last 5–10 lines of output>"},
    "lint":      {"exit_code": 0, "excerpt": "<relevant lines or 'clean'>"},
    "typecheck": {"exit_code": 0, "excerpt": "<relevant lines or 'clean'>"}
  },
  "axes": {
    "correctness":       {"ok": true, "notes": "..."},
    "tests":             {"ok": true, "notes": "..."},
    "test_quality":      {"ok": true, "notes": "..."},
    "code_quality":      {"ok": true, "notes": "..."},
    "architectural_fit": {"ok": true, "notes": "..."}
  },
  "blocking":        ["<DoD violation or defect in changed code, with file:line evidence>", "..."],
  "design_blockers": ["<concern that rises to 'the plan itself is wrong', with file:line evidence>", "..."],
  "design_notes":    ["<weakness in the plan worth flagging but not blocking, with file:line evidence>", "..."],
  "non_blocking":    ["<nit, with file:line>", "..."],
  "summary": "<≤5 lines>"
}
```

`commands_run` and `verification_evidence` are mandatory. A verdict with empty `commands_run` or missing `verification_evidence` for any of the three checks is **invalid** — see verdict validation in step C.

Field placement is strict:

- A concrete defect found in changed code → `blocking` (drives `fail`).
- An objection to the plan that the implementer cannot fix by re-coding to it → `design_blockers` (drives `escalate`).
- A weakness in the plan that is worth flagging but does not rise to "the plan is wrong" → `design_notes` (compatible with `pass`).
- A style nit → `non_blocking` (never gates).

The verdict `status` must be consistent with the arrays: `blocking` non-empty ⇒ `fail`; `design_blockers` non-empty ⇒ `escalate` (takes precedence over `fail` when both are non-empty — escalation pauses for human arbitration before any retry); both empty ⇒ `pass`.

### C. Iterate

Before acting on the verdict, **validate that the reviewer actually verified**. A verdict is treated as a **verification failure** if any of:

- `commands_run` does not include all three commands.
- `verification_evidence` is missing an entry for any of `test`, `lint`, `typecheck`.
- Any entry in `verification_evidence` has a null/missing `exit_code` or an `excerpt` indicating the command was not actually run (e.g., `"shell unavailable"`, `"could not execute"`).
- `blocking` contains a "reviewer cannot verify" sentinel (any wording that asserts the reviewer was unable to run the checks).

On verification failure: re-spawn the reviewer **once**, with a stricter invocation that quotes the verification rule and the four conditions above. If the second attempt is also a verification failure, **escalate to the user** — surface the verdict(s), the current diff, and the implementer's `rationale_out`. Do not invoke the implementer for verification failures: the reviewer is the broken component, not the change. This re-spawn does not count against the `fail` round cap.

Once the verdict is verified, act on `status`:

- `pass` → step D (commit).
- `fail` → spawn a new implementer (step A) with the full inputs **plus** the prior full cumulative diff, the prior verdict JSON, and the surgical-fix mode directive. The implementer must address every `blocking` item, still under TDD. Then spawn a new reviewer (with the standard invocation — no awareness of round number).
- `escalate` → **stop the loop for this work item**. Surface the reviewer's `design_blockers` (and `design_notes` if present), the `verification_evidence`, the current diff, and the implementer's `rationale_out` to the user. The user decides next steps. Do not commit.
- **Hard cap: 3 `fail` rounds per work item.** Escalation terminates the loop immediately and does not count against the cap. Verification-failure re-spawns also do not count against the cap.

### D. Commit

Commit when reviewer returned `pass` OR when 3 `fail` rounds have completed.

- One commit per work item.
- Message (conventional commits — blank lines between subject, body, and trailers are required for `git interpret-trailers` and downstream tooling to parse correctly):

  ```
  <type>(<scope-short>): <summary>

  - <bullet of change>
  - <bullet of change>

  Refs: <id>
  ```

  where `<type>` maps from `work_item.type`: `fix` → `fix`, `feature` → `feat`, `refactor` → `refactor`, `chore` → `chore`.
- If the final verdict was `fail` after round 3, append the trailer block (preceded by a blank line):

  ```
  Review-Status: unresolved (<n> blocking issues remain)
  ```

- If the reviewer surfaced `design_notes` but the verdict was `pass`, append (preceded by a blank line):

  ```
  Design-Notes: <n> note(s) flagged — see review log
  ```

Do not abandon the run on a single unresolved or note-bearing item. Move to the next work item.

## Definition of Done (passed verbatim to both subagents)

A work item is Done when **all** hold:

1. **TDD evidence.** A test exists that fails on the pre-change tree and passes on the post-change tree. (Relaxed for behavior-free chores — see implementer method. Relaxed with explicit justification for `setup_blocked` cases.)
2. **Tests green.** Full suite passes: `<test>`.
3. **Static checks green.** Lint clean: `<lint>`. Typecheck clean: `<typecheck>`. Pre-existing warnings on unrelated lines are not this work item's problem — verify with git blame if borderline.
4. **Scope respected.** No files or symbols modified outside the declared `scope`.
5. **No silent deps.** New runtime dependencies, env vars, or migrations are explicitly listed in `rationale_out`.
6. **Hygiene.** No commented-out code, debug prints, or new TODOs introduced.
7. **Surface documented.** Public API or user-visible behavior changes are reflected in the appropriate docstring / README / changelog entry.

## Reviewer rubric (all five axes mandatory, plus design layer)

1. **Correctness** — does the change actually deliver `acceptance_criteria`? For fixes, does it address the root cause given in `rationale`? If the reviewer believes a *different* root cause is in play, that belongs in `design_blockers`, not `blocking`.
2. **Tests** — is the TDD evidence real (test failed before, passes now)? Is the suite green when the reviewer runs it independently?
3. **Test quality** — assertions exercise the failure mode or new behavior, not just paths; no over-mocking; no tests that lock in implementation details rather than behavior; the test would actually catch a future regression that re-introduces the bug.
4. **Code quality** — readable, names carry intent, no duplication, follows surrounding conventions; for features, the public API is minimal and consistent with existing patterns.
5. **Architectural fit** — change sits at the right layer; no leaky abstractions; no inappropriate coupling across module boundaries; for features, new code is placed where comparable code already lives.

**Design layer (uses `rationale`, produces `design_blockers` or `design_notes`):**

- Is the chosen approach in `rationale` actually well-suited to the problem, given what the diff reveals about the surrounding code?
- Are any of the rejected alternatives now looking better in light of what was discovered during implementation?
- Are there constraints or interactions the upstream design clearly did not consider (platform version, downstream consumers, related flows, accessibility, security)?
- Does the fix address the root cause or only mask the symptom?
- Are residual risks listed in `rationale` actually still acceptable in light of what the diff exposes?

A design observation is a `design_blocker` (forces `escalate`) when it asserts "the plan itself is wrong, re-coding to this plan will not fix it" — wrong root cause, hidden constraint that defeats the approach, materially better alternative now visible. It is a `design_note` (compatible with `pass`) when it asserts "the plan has a weakness worth flagging at commit time, but the change as written is still acceptable."

Every design entry — blocker or note — must cite concrete `file:line` evidence, and the cited file may be anywhere in the repository (often outside the diff, since the most important design concerns hinge on how unchanged code interacts with the change). Vibes do not qualify. "I think there might be a better way" is not a valid entry. "The chosen `visiblePassword` keyboard type at `lib/auth/login_form.dart:42` disables iOS 17+ password-manager autofill — see `lib/auth/autofill.dart:11` (unchanged by this diff) where autofill is wired and depends on the default keyboard. `rationale` did not flag this as accepted." → this is a `design_blocker` (the fix is wrong given the cited interaction). "The new helper at `src/util/format.ts:88` duplicates logic already in `src/format/locale.ts:30`; not blocking because the call sites are different, but worth consolidating later." → this is a `design_note`.

## Final report (after all work items in a batch)

Emit a table:

| id | type | rounds_used | final_status | commit_sha | design_notes |
|----|------|-------------|--------------|------------|--------------|

Where `final_status` ∈ `passed` / `unresolved` / `escalated` / `plan_broken` / `setup_blocked`. Call out any non-`passed` rows prominently so the user knows where to look.
