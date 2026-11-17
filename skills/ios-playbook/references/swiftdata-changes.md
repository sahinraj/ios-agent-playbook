# Persisted model changes (SwiftData)

Read this before any change to a `@Model` type, a relationship, an attribute option, or the way a `ModelContainer` is built. The same process applies to Core Data with its own model versions and mapping.

This is the process. For API detail, load a SwiftData domain skill and confirm the code compiles on the project's SDK.

## Contents

- First question: has the store shipped
- What counts as a schema change
- The slices
- The migration test
- Background writes
- CloudKit
- What to tell the user

## First question: has the store shipped

Everything else depends on this, so verify it and write the evidence into the plan.

| Evidence | Meaning |
|---|---|
| A release tag, an App Store or TestFlight build, or the user says so | Shipped. Existing stores are in the wild. Full protocol below. |
| A `SchemaMigrationPlan` already in the code | Shipped at some point. Add a new version, never edit an old one. |
| No release, internal development only | Not shipped. You may change the model directly. Say that you verified this, and remind the user that development devices will need the app deleted or their store reset. |
| You cannot tell | Ask. Do not assume "not shipped" because it is convenient. |

## What counts as a schema change

All of these change the stored schema, even when the diff is one line:

- adding, removing or renaming a property or a model
- changing a property's type or optionality
- adding or removing `@Attribute` options such as `.unique` or `.externalStorage`
- adding, removing or changing a relationship, its inverse or its delete rule
- adding indexes or uniqueness constraints

| Change | Usually needs |
|---|---|
| Add an optional property, or one with a default | Lightweight stage |
| Remove a property | Lightweight stage |
| Rename a property | Lightweight stage plus `@Attribute(originalName:)`. Without it the data is dropped. |
| Add a new model | Lightweight stage |
| Make a property unique when duplicates may exist | Custom stage that removes duplicates first |
| Change a type, split or merge properties, backfill computed values | Custom stage |

When unsure whether lightweight is enough, write the migration test first. It will tell you.

## The slices

1. **Capture the shipped shape.** If the app has no versioned schema yet, add one that matches the shipped models exactly, and a migration plan with that single version. Take the shipped shape from the release tag, not from memory. If version 1 does not match what is on users' devices, the store is reported as an unknown version and will not open.
2. **Add the new version and the stage.** New schema version, the migration stage, and the migration test below. Nothing else in this slice.
3. **Move the app to the new version.** Point the container at the latest schema and the plan. Update typealiases so the rest of the code uses the current models.
4. **Use the new shape.** Logic, then UI, as normal slices.

Never edit a schema version that has shipped. Add the next one.

## The migration test

The only real proof is opening a store that the previous version wrote. A test with a fresh in-memory container exercises none of the migration.

```swift
import Foundation
import SwiftData
import Testing

@Suite struct InspectionMigrationTests {
    @Test func migratesV1ToV2AndRemovesDuplicateNumbers() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "migration-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }

        // 1. Write a store with the previous schema and realistic rows,
        //    including the awkward ones (duplicates, nils, empty strings).
        do {
            let schema = Schema(versionedSchema: SchemaV1.self)
            let config = ModelConfiguration(schema: schema, url: url)
            let container = try ModelContainer(for: schema, configurations: config)
            let context = ModelContext(container)
            context.insert(SchemaV1.Inspection(number: "A-100", title: "First"))
            context.insert(SchemaV1.Inspection(number: "A-100", title: "Duplicate"))
            context.insert(SchemaV1.Inspection(number: "A-200", title: "Other"))
            try context.save()
        }

        // 2. Open the same file with the current schema and the migration plan.
        let schema = Schema(versionedSchema: SchemaV2.self)
        let config = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: config
        )

        // 3. Assert on the migrated data, not only that it opened.
        let rows = try ModelContext(container)
            .fetch(FetchDescriptor<SchemaV2.Inspection>(sortBy: [SortDescriptor(\.number)]))
        #expect(rows.map(\.number) == ["A-100", "A-200"])
    }
}
```

Adapt the names to the project. What matters:

- the old container is released (the `do` block) before the new one opens the file
- the rows include the cases the migration exists to handle
- the assertions check values, counts and relationships after migration
- one test per stage, plus one that walks from the oldest supported version to the newest

If a store file from a real shipped build is available, add it as a test resource and migrate a copy of it. That catches differences between what you think version 1 was and what actually shipped.

## Background writes

- `ModelContext` and model objects are not `Sendable`. Pass `PersistentIdentifier` between actors and fetch on the other side.
- Use a model actor for background work. Contexts you create yourself do not autosave, so call `save()` and handle its error.
- After a background save, confirm the UI context sees the change. Write the check into gate 6.
- Deleting on one context while another holds the object is the classic crash. Decide who owns deletes.

## CloudKit

For a container that syncs with CloudKit, the compiler accepts models that sync will reject. Check every model against these rules:

- no unique constraints
- every property optional or with a default value
- every relationship optional, with an inverse

A CloudKit schema that has been promoted to production cannot have fields removed or retyped. Treat any change there as high risk and tell the user it needs a check in the CloudKit dashboard.

## What to tell the user

Put these in the plan for a shipped store:

- Migrations are one way. Once a user opens the new version, an older build cannot open their store. This matters for rollbacks and for TestFlight users who switch between builds.
- The migration test covers the cases you thought of. Ask whether real data has shapes you have not seen: very old versions, very large stores, half-synced records.
- A large store can take long enough to migrate at launch to trip the watchdog. If the store can be large, say so and ask whether the migration needs to run off the launch path.
