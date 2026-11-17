Goal: No two inspections share a number. Existing duplicates are merged on upgrade.
Risk: high. This is a schema change on a shipped store.
Out of scope: the number format.
Assumptions:
  - Store has shipped: verified (version 2.3 is on the App Store).
  - No VersionedSchema exists yet: verified (Persistence/Container.swift).
Slices:
  1. SchemaV1 as a VersionedSchema that matches the shipped models exactly, plus a SchemaMigrationPlan with that one version.
  2. SchemaV2 with the unique number, a custom migration stage that merges duplicate numbers, and a migration test that opens a store written by the previous schema with duplicate rows in it.
  3. Move call sites to SchemaV2.
Compiler will not catch: the existing store failing to open, and unique upserting over an older row.
Gates: 1, 2, 4, 8, 9.
Waiting for your OK before the first edit.
