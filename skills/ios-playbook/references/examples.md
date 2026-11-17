# Worked examples

Read this when you want to see what a good plan or report looks like at each level. The app is invented: FieldLog, an offline-first iPad inspection app built with SwiftUI and SwiftData.

## Contents

- Trivial: rename a button
- Standard: add a filter to a list
- Standard: a bug fix
- High risk: a schema change on a shipped store
- A finished report

## Trivial: rename a button

Request: "Change the Submit button on the inspection form to say Send."

```
Level: trivial. One string in one view, no behavior change.
Edit: InspectionFormView.swift, the button label key, plus the String Catalog entry.
Gates: 1 (build), 8 (diff audit).
```

Then the edit, the build, and a two-line report. No slices, no advisor. A full plan here would be noise.

## Standard: add a filter to a list

Request: "Let users filter the inspection list by status."

```
Goal: The inspection list can be filtered to Open, Submitted or All, and the choice survives leaving and returning to the screen.
Risk: standard. New UI state and a query change. No schema, isolation or sync change.
Out of scope: sorting, search, and the status values themselves.
Assumptions:
  - InspectionListModel is @MainActor @Observable and owns list state: verified (Features/Inspections/InspectionListModel.swift).
  - Status is an existing enum stored on Inspection: verified (Models/Inspection.swift).
  - Baseline: build passes, 212 tests, SyncQueueTests/retriesAfterTimeout already fails.
Slices:
  1. InspectionListModel.swift, InspectionListModelTests.swift: add `filter: StatusFilter` and apply it in the fetch descriptor. Tests for each filter value and for All. Gates 1, 2, 3.
  2. InspectionListView.swift: a segmented Picker in the toolbar bound to the model. Gates 1, 6, 7.
  3. InspectionListView.swift: empty state text when a filter matches nothing, localized. Gates 1, 6.
Compiler will not catch:
  - Filter resets when the view is re-created: check by navigating into a detail and back.
  - Picker truncates at large text sizes: check at the largest accessibility size.
  - New strings missing from the String Catalog: search the diff for literals.
Gates: 1, 2, 3, 6, 7, 8, 9. Skipping 4 and 5: no schema or isolation change.
```

Notice the pattern match: the filter state goes where list state already lives, not in a new store.

## Standard: a bug fix

Request: "The app crashes sometimes when you delete an inspection."

"Sometimes" is the first problem. The plan starts with reproduction, and the level is provisional until the cause is known.

```
Goal: Deleting an inspection never crashes.
Risk: standard for now. Will become high if the cause is in sync or background writes.
Out of scope: the delete confirmation UI.
Assumptions:
  - Crash log shows EXC_BREAKPOINT in InspectionRow.body reading `inspection.title`: verified (attached report).
  - Hypothesis: the row renders once more after the model object is deleted. Would be disproved if the crash also happens with no row on screen.
  - Baseline: build passes, 212 tests, 1 known failure.
Slices:
  1. Reproduce. A test in InspectionListModelTests that deletes an inspection while it is the selected row and reads the row's display values. Expect a failure. No fix. Gate 2 (expecting red).
  2. Fix according to what slice 1 shows. If the hypothesis holds: the row takes a value snapshot (title, status) instead of the live model. Gates 1, 2, 3.
  3. Check the two other views that read a live Inspection after a possible delete (found by search). List them. Fix in this slice only if the same test pattern fails for them. Gates 1, 2.
Compiler will not catch:
  - The same access from a queued task after delete: check by deleting during a sync flush.
  - Animation glitch on delete if row identity changes with the snapshot: check in the simulator.
Gates: 1, 2, 3, 6, 8, 9.
```

After slice 1, the reproduction showed the crash only when a sync flush was running. The agent stopped and re-sized:

```
Re-sizing: high risk. The reproduction only fails while SyncEngine.flush() is running, so the cause is a background write, not the row. Revised plan saved to .playbook/plans/delete-during-sync-crash.md. Waiting for your OK before editing SyncEngine.
```

That stop is the playbook working. The first hypothesis was reasonable and wrong, and a guard in the row would have hidden the real bug.

## High risk: a schema change on a shipped store

Request: "Inspection numbers must be unique."

```
Goal: No two inspections share a number. Existing duplicates are merged on upgrade without losing findings.
Risk: high. Schema change on a shipped store (v2.3 is on the App Store), and it rewrites user data.
Out of scope: server-side uniqueness, and the number format.
Assumptions:
  - Store has shipped: verified (tag v2.3.0, App Store).
  - No VersionedSchema exists yet: verified (search, and Persistence/Container.swift builds the container from bare model types).
  - Duplicates exist in real data: unverified. Asking the user. The migration handles them either way.
  - Merge rule for duplicates (keep the newest, move findings from the others): unverified. Needs the user's decision.
  - Baseline: build passes, 212 tests, 1 known failure. Commit 4f2a9c1.
Slices:
  1. Persistence/SchemaV1.swift, Persistence/MigrationPlan.swift: SchemaV1 matching the models at tag v2.3.0 exactly, and a plan with that single version. Container uses the plan. No model change. Gates 1, 2, 9.
  2. Persistence/SchemaV2.swift, MigrationPlan.swift, InspectionMigrationTests.swift: SchemaV2 with the unique number, a custom stage that merges duplicates before the constraint applies, and a migration test with duplicate, nil and empty numbers. Gates 1, 4.
  3. Typealiases and call sites move to SchemaV2 models. Gates 1, 2, 9.
  4. InspectionFormModel.swift and tests: creating an inspection with an existing number shows an error instead of silently replacing the old row. Gates 1, 2, 3.
  5. InspectionFormView.swift: the error message, localized. Gates 1, 6.
Compiler will not catch:
  - Store fails to open for existing users: the migration test in slice 2.
  - A unique attribute upserts on conflict and overwrites the older inspection: slice 4 and its test.
  - Findings orphaned or cascaded away during the merge: assert finding counts in the migration test.
  - Migration time on a large store at launch: flag for the user, ask about store sizes.
  - Older builds cannot open a migrated store: tell the user before release.
Gates: 1, 2, 3, 4, 6, 8, 9. Skipping 5: no isolation change.
Advisor: after this plan, and before the final report.
Waiting for your OK and the merge rule before the first edit.
```

Two assumptions are honestly marked unverified and turned into questions. That is what the Assumptions field is for.

## A finished report

For the filter example above:

```
Changed:
  1. InspectionListModel: `filter` property applied in the fetch descriptor, 4 new tests.
  2. InspectionListView: segmented picker in the toolbar.
  3. InspectionListView: localized empty state per filter.
Evidence:
  1 Build: scheme FieldLog, iPad Pro 13-inch (M4): exit 0, no new warnings in touched files.
  2 Tests: InspectionListModelTests: 11 executed, 0 failed.
  3 New tests: filtersByStatus(_:) failed before slice 1 was implemented (3 of 3 arguments), passes after.
  6 UI walk: filter survives detail and back. Largest text size, landscape and narrow window checked. Screenshots in the log folder.
  7 Previews: compile, rendered for InspectionListView.
  8 Diff audit: 0 flags. 3 files changed, all named in the plan.
  9 Full suite: 216 executed, 1 failed (retriesAfterTimeout, same as baseline).
Not verified:
  - VoiceOver was checked by reading the accessibility labels in code, not by running VoiceOver.
Noticed, not fixed:
  - InspectionListView sorts in `body` on every render (line 48). Worth moving into the model.
  - SyncQueueTests/retriesAfterTimeout fails on main.
Follow-ups:
  - Should the filter choice persist across app launches? It currently lasts for the session.
```

Every claim has a number or an observation behind it, and the one thing not actually run is labeled.
