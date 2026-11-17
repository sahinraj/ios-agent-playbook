# Planning and slicing

Read this in step 2 when you need a slicing recipe for the kind of change in front of you, or when you are saving a plan to a file.

## Contents

- The plan, field by field
- Slicing recipes by change type
- Good and bad slices
- Plan files

## The plan, field by field

**Goal.** One sentence about the outcome the user will see, not the code you will write. "Deleting an inspection while sync is running no longer crashes" is a goal. "Refactor SyncEngine" is not.

**Risk.** The level from step 0 and the reason. Name the trigger for high risk.

**Out of scope.** What a reasonable person might expect you to touch that you are deliberately leaving alone. This is where you prevent scope creep before it starts.

**Assumptions.** Every fact the plan depends on, each marked `verified (file)` or `unverified`. Include the baseline. An unverified assumption on a high-risk plan is a question for the user.

**Slices.** Ordered. Each one names the files, the change, and the gates that prove it. If you cannot name the gate, the slice is not defined well enough yet.

**Compiler will not catch.** The specific silent failures this change could cause, taken from [silent-failures.md](silent-failures.md), each with how you will check it.

**Gates.** Which of the nine apply. Anything skipped gets a reason.

## Slicing recipes by change type

### Feature

Vertical, thin first. Get one path working end to end before widening it.

1. Types and model changes the feature needs (and migration first, if a shipped store is involved).
2. Logic behind a small API, with tests. No UI yet.
3. UI wired to the logic, happy path only.
4. Empty, loading and error states.
5. Accessibility, localization, previews.
6. Cleanup of anything the feature made obsolete.

### Bug fix

1. A failing test or scripted reproduction that shows the bug. No fix yet.
2. The smallest fix that makes it pass.
3. Only if needed: hardening nearby code that had the same flaw, as a separate slice.

Never fold a refactor into slice 2. If the fix is impossible without restructuring, do the restructuring first as its own no-behavior-change slice, prove the bug still reproduces, then fix.

### Refactor

1. Confirm tests cover the behavior you are about to move. If they do not, add characterization tests first.
2. Mechanical moves and renames, one kind per slice, no behavior change. The test suite is identical before and after.
3. Behavior changes, if any, come after and are not called refactoring.

### Persisted model change

Follow [swiftdata-changes.md](swiftdata-changes.md). In short:

1. Versioned schema for the current shipped shape, if it does not exist yet.
2. New schema version plus the migration stage, with a migration test.
3. Code that uses the new shape.
4. UI.

### Concurrency or isolation change

Follow [concurrency-changes.md](concurrency-changes.md). In short: one module or one type per slice, leaf modules first, zero new warnings at the end of each slice.

### Dependency update

1. Update the one dependency, nothing else. Build and run the full suite.
2. Fix compile errors with the smallest changes.
3. Adopt new APIs in later slices, never in the update slice.

Read the release notes for behavior changes before slice 1. They are the "Compiler will not catch" list for this task.

### UI-only change

1. Structure: the view hierarchy change.
2. Styling.
3. Accessibility and Dynamic Type pass.

Check every screen that uses a shared component you touched, not only the screen in the request.

## Good and bad slices

| Bad slice | Why | Better |
|---|---|---|
| "Update the sync engine" | No files, no gate, no size | "Make `SyncEngine.flush()` skip rows deleted since they were queued. `SyncEngine.swift`, `SyncEngineTests.swift`. Gates 1, 2, 3." |
| "Add model property and show it in the list and migrate" | Three concepts, and the migration is mixed in | Three slices, migration first |
| "Refactor and fix the crash" | If it still crashes you cannot tell which half is wrong | Refactor slice with no behavior change, then the fix |
| "Fix warnings" | Unbounded | "Remove the 4 concurrency warnings in `InspectionRepository.swift`" |
| A slice that only compiles after the next one | Breaks the "each slice builds" rule, so failures stop being local | Reorder, or add the new code beside the old and switch over in a later slice |

Signs a slice is too big: more than about 150 changed lines, more than one "and" in its description, or more than one reason it could fail.

## Plan files

Save the plan to a file when it has more than three slices, when the task is high risk, or in `plan` mode.

- Location: `.playbook/plans/<short-name>.md`, lowercase with hyphens, for example `.playbook/plans/dedupe-inspection-number.md`.
- Use the template in `assets/plan-template.md`.
- Track status on each slice with `[ ]`, `[~]` (in progress) or `[x]`, and add one line of evidence when a slice finishes.
- When you learn something that changes the plan, edit the file and add a dated line under "Changes to the plan". Do not silently diverge from it.
- After a context reset or at the start of a new session, re-read the plan file before doing anything else.

A plan file is working state, not documentation. Whether to commit it is the user's call. Mention it in the report so they can decide.
