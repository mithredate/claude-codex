---
name: prd
description: "Generate a Product Requirements Document (PRD) for a new feature. Use when planning a feature or starting a new project. Optimized for hand-off to the ralph skill for autonomous execution. Triggers on: create a prd, write prd for, plan this feature, requirements for, spec out."
---

## PRD Generator
Create detailed, technically robust Product Requirements Documents that integrate with existing codebases.

### The Job
1. **Discover** the existing codebase structure and patterns.
2. **Receive** a feature description from the user.
3. **Clarify** using 3-5 essential questions (with lettered options).
4. **Generate** a structured PRD.
5. **Validate** the PRD for completeness and soundness.
6. **Save** to `~/.claude/tasks/prd-[feature-name].md`.
7. **Suggest** running the ralph skill to convert to prd.json for autonomous execution.

> **Workflow:** This skill produces PRDs. To convert a PRD to Ralph Loop JSON format, use the **ralph** skill (e.g., "convert this prd to ralph format"). The ralph skill reads from `~/.claude/tasks/` and writes to `~/.claude/prd/`.

> **Important:** Do NOT start implementing. Focus solely on the requirements.

---

## Step 0: Codebase Discovery (REQUIRED)

Before asking clarifying questions, examine the repository to understand:

- **Tech stack** — Check `package.json`, `composer.json`, `go.mod`, etc.
- **Existing patterns** — Repository pattern? Service layer? DDD?
- **Test infrastructure** — Framework, existing helpers/factories
- **Documentation style** — README structure, API docs format, changelog practices
- **Similar features** — Find reference implementations to follow

**Output a brief "Codebase Context" summary before proceeding.**

---

## Step 1: Clarifying Questions

Ask 3-5 critical questions to eliminate ambiguity:

* **Business Rules:** What logical constraints must never be broken?
* **Invariants:** What technical conditions must remain true at all times?
* **Scope Boundaries:** What should this feature definitely NOT do?
* **State Transitions:** What happens to the data during this action?
* **Integration Points:** Which existing features does this interact with?

---

## Step 2: PRD Structure

### 1. Introduction & Goals
* Brief description and the core problem solved.
* **Goals:** Specific, measurable objectives.

### 2. Codebase Context
* **Tech Stack:** Framework, language version, key dependencies
* **Patterns to Follow:** Existing patterns this feature must adhere to
* **Reference Implementation:** Similar feature in codebase to use as template

### 3. Business Rules & Invariants
* **Business Rules:** Policy-level constraints (e.g., "Only owners can delete projects")
* **Invariants:** Logic-level constants (e.g., "Discount percentage must be between 0 and 100")

### 4. User Stories

**The Golden Rule:** Each story must be small enough to complete in ONE focused session. If a story is too big, split it.

> **Planning Principle:** When writing acceptance criteria, naturally include updates to existing tests, documentation, and related code. Don't treat these as separate concerns—they're part of completing the story.

#### US-XXX: [Title]
**Description:** As a [user], I want [feature] so that [benefit].

**Invariants:**
* [State/Condition that must be preserved]

**Acceptance Criteria:**
* [ ] Specific verifiable criterion
* [ ] Typecheck passes
* [ ] All tests pass (new and existing)
* [ ] **[UI only]** Verify in browser

**Test Scenarios:**
* **Happy Path:** [Standard successful flow]
* **Edge Case:** [Boundary conditions]
* **Negative Test:** [Intentional failure scenarios]

### 5. Functional Requirements
Numbered list of system behaviors (FR-1, FR-2, etc.).

### 6. Dependency Order
Group stories by logical order:
1. Migrations & Schema
2. Server Logic & APIs
3. UI Components
4. Integration & Final Pages

### 7. Non-Goals
Explicitly define boundaries to prevent scope creep.

---

## Step 3: Validation (REQUIRED)

Before finalizing, critically review the PRD:

### Coverage Check
- Do all user stories together fully satisfy the stated goals?
- Are there any requirements mentioned in the introduction not covered by a story?
- Are there implicit requirements (error handling, logging, permissions) missing?

### Solution Assessment
- Is this the simplest solution that meets the requirements?
- Are there alternative approaches worth considering?
- Could any stories be combined or split for better implementation?

### Gap Analysis
- What happens at the boundaries of this feature?
- Are all user types/roles accounted for?
- Are failure modes and recovery paths defined?

### Technical Risk
- Does this change introduce performance concerns (N+1 queries, large payloads)?
- Are there concurrency or race condition risks?
- Does this conflict with or complicate existing functionality?
- Are there scaling limitations to flag?

**Document any concerns or trade-offs in a "Risks & Considerations" section.**

---

## Planning Guidelines

When writing user stories, the implementing agent should:

* **Follow existing patterns** — Use the reference implementation as a template
* **Update affected tests** — If changing behavior, update tests that cover it
* **Update documentation** — If changing APIs or user-facing behavior, update relevant docs
* **Maintain backward compatibility** — Unless explicitly breaking, existing functionality must keep working

These are implicit expectations for every story, not separate checklist items.

---

## Example User Story

### US-001: Add Project Status Field
**Description:** As a developer, I need to track if a project is 'active' or 'archived' in the database.

**Invariants:**
* A project status can only be 'active' or 'archived'.
* Existing projects default to 'active'.

**Acceptance Criteria:**
* [ ] Migration adds status column (string, default: 'active').
* [ ] Schema/validation updated to reflect status enum.
* [ ] Typecheck passes.
* [ ] All tests pass.

**Test Scenarios:**
* **Happy Path:** Create project, verify status is 'active'.
* **Edge Case:** Update status to 'archived', verify persistence.
* **Negative Test:** Attempt to save 'deleted' as status; verify rejection.

---

## Checklist

- [ ] **Discovery:** Did I examine the existing codebase before planning?
- [ ] **Context:** Did I identify patterns and reference implementations?
- [ ] **Clarification:** Did I ask 3-5 clarifying questions?
- [ ] **No Code:** Did I avoid writing implementation code?
- [ ] **Atomicity:** Is every story completable in a single session?
- [ ] **Verifiability:** Does every story have binary (Pass/Fail) criteria?
- [ ] **Coverage:** Does every story include Happy Path, Edge Case, and Negative Test?
- [ ] **Validation:** Did I verify coverage, assess the solution, check for gaps, and flag technical risks?
- [ ] **File saved:** `~/.claude/tasks/prd-[feature-name].md`
- [ ] **Next step suggested:** Offered user to run ralph skill for conversion to prd.json