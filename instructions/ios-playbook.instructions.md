---
applyTo: "**/*.swift"
description: Process rules for any change to Swift files, from the ios-playbook skill
---
# Process rules for Swift changes

- For anything more than a one-line edit, follow the ios-playbook skill: size the risk, read before planning, show the plan, work in small slices, verify each slice, report with evidence.
- Read `.playbook/repo-map.md` and `.playbook/risk-map.md` first when they exist. They hold the working build and test commands and the fragile areas of this repo.
- Check the deployment target, Swift language mode and default actor isolation before adding annotations or new APIs.
- For a bug, reproduce it before proposing a fix. The reproduction becomes a test that fails before the fix and passes after.
- A change to a persisted model in a shipped app needs a new schema version and a migration test that opens a store written by the previous version.
- Keep refactors and migrations in their own slices with no other change.
- Never silence a diagnostic to get past the compiler: no new `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, `try!` or lint suppressions.
- Never weaken, disable or delete a test to get to green.
- Do not say a change is done without a build you ran. If you could not build or test, say "not verified" and give the command.
- The full playbook is in the ios-playbook skill, in `.github/skills/`, `.claude/skills/`, `~/.copilot/skills/` or `~/.claude/skills/`.
