# Repo map and risk map

Read this in `map` mode, and whenever you learn a fact about the repo that the map does not have yet.

## Contents

- What map mode produces and why
- Rules
- Procedure
- The repo map
- The risk map
- The pointer block
- Keeping it current

## What map mode produces and why

Two files in `.playbook/` at the repo root:

- `.playbook/repo-map.md`: the build and test commands that work, the project settings, the module layout, the patterns in use.
- `.playbook/risk-map.md`: the places where a change is most likely to cause a bug the compiler will not catch.

Working these out takes real reading and reasoning, and without a map every session pays for it again. With a map, a cheaper model or a fresh session starts from facts instead of guesses. This is the best use of a strong model on a codebase: write the map once, let every later task read it.

## Rules

- Do not change source files. `map` mode writes only inside `.playbook/` and adds one pointer block to the agent instruction file.
- Every fact gets a file path. A map without paths cannot be checked and will not be trusted.
- Record a command only after you ran it and saw it succeed. If you could not run it, record it under "Not verified" with the reason.
- Describe what is there, not what you would prefer. Opinions about the architecture go in a short "Observations" section at the end, or not at all.
- Keep each file under about 200 lines. A map nobody reads is worth nothing.

## Procedure

1. Run the facts script from the repo root and read its whole output: `bash <skill-dir>/scripts/project-facts.sh`, where `<skill-dir>` is the folder that contains this skill's `SKILL.md`.
2. Read the existing instruction files, `README.md`, CI workflows, `Makefile` and `fastlane` for the commands the team already uses.
3. Find the scheme and destination, then run a build and the unit tests. Record the exact commands, how long they took, and the test count. See [verification-gates.md](verification-gates.md).
4. Read the app entry point, the composition root (where the container and dependencies are created), and two representative features end to end.
5. Read the persistence layer: models, container setup, schema versions, migration plan, who writes and on which actor.
6. Read the networking and sync layer if there is one: client, auth, retry, offline queue.
7. Write `.playbook/repo-map.md` from `assets/repo-map-template.md`.
8. Find the fragile areas (next section) and write `.playbook/risk-map.md` from `assets/risk-map-template.md`.
9. Add the pointer block.
10. Report: files written, commands verified, anything not verified, and the three risks you consider most serious.

For a large repo, do the app target and its two most active modules first, and list the modules you did not read. A partial map that says what it covers is better than a shallow map of everything.

## The repo map

Sections, in this order:

1. **Build and verify.** Scheme, destination, the build command, the test command, how to run one test, the test plans, typical durations. Mark each as verified with the date.
2. **Settings.** Deployment targets, Swift language mode, strict concurrency level, default actor isolation, feature flags, per target, with the file where each is set.
3. **Layout.** Targets and packages, what each is for, what depends on what. Note generated projects (XcodeGen, Tuist).
4. **Patterns.** State ownership, dependency injection, navigation, error handling, logging. One short paragraph each, with one example file to copy from.
5. **Persistence.** Where the container is built, current schema version, migration plan location, write paths and their actors, CloudKit yes or no, whether the store has shipped.
6. **Networking and sync.** Client, auth, retry, offline behavior.
7. **Tests.** Frameworks in use, where tests live, fixtures and fakes, known slow or flaky suites.
8. **Conventions.** Formatting and lint tools, naming, localization, anything the team enforces in review.
9. **Not verified.** What you could not check and why.

## The risk map

Rank the ten places where a change is most likely to cause a silent failure. Fewer if the repo is small. For each:

- **Where**: file or type.
- **Why it is fragile**: the specific mechanism, in one or two sentences.
- **Before touching it**: what to read or reproduce first.
- **After touching it**: the check that would catch a regression.

Where to look:

- isolation boundaries: where data crosses between the main actor, other actors and legacy queues
- every `@unchecked Sendable`, `nonisolated(unsafe)` and `@preconcurrency`
- unstructured tasks started from UI events or notifications
- SwiftData writes off the main actor, and code that passes model objects around
- schema versions and migration stages
- lists with editable rows, reordering or in-row state
- offline queues, retries, conflict handling
- anything that feeds a value a user relies on for an operational or safety decision
- code with no tests that many other files depend on
- places with comments like "do not change", "hack", "workaround", "temporary"

Use [silent-failures.md](silent-failures.md) as the checklist of mechanisms. A risk entry that says "complex code" is not useful. One that says "the sync queue applies changes by row index, and deletes during a flush shift the indexes" is.

## The pointer block

Add this to the instruction file the project uses (`CLAUDE.md`, `AGENTS.md` or `.github/copilot-instructions.md`). Create `AGENTS.md` only if none exists and the user agrees. The text is in `assets/agents-block.md`. If the block is already there, leave it.

Keep build commands in the repo map, not in the instruction file. One source of truth, and the instruction file stays short.

## Keeping it current

The map is only useful while it is true.

- When a recorded command fails, fix the map in the same session and say so in the report.
- When a task changes something the map describes (a new schema version, a new module, a changed scheme), update the map as the last slice.
- When you find a fragile area the hard way, add it to the risk map.
- Put the date next to anything you re-verify.

Whether `.playbook/` is committed is the team's decision. To keep it local without touching `.gitignore`, the user can add `.playbook/` to `.git/info/exclude`.
