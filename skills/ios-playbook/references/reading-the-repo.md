# Reading the repo

Read this in step 1 when there is no repo map, when the facts script cannot run, or when you need to know where a specific fact lives.

## Contents

- Start with what already exists
- The facts script
- Where each fact lives
- Taking a baseline
- Finding the pattern in use
- Tracing the data path
- Git state

## Start with what already exists

Check these first, in order. Each one saves you a search.

1. `.playbook/repo-map.md` and `.playbook/risk-map.md`: written by `map` mode. Trust them, but if a command fails, fix the map.
2. `CLAUDE.md`, `AGENTS.md`, `.github/copilot-instructions.md`: project instructions for agents.
3. `README.md`, `CONTRIBUTING.md`, `Makefile`, `fastlane/Fastfile`, CI workflows under `.github/workflows/`: these often contain the exact build and test commands the team uses.

If a repo map is missing and the task is more than a one-off, suggest running `map` mode after the task. Do not stop to do it unasked.

## The facts script

```bash
bash <skill-dir>/scripts/project-facts.sh                # current directory
bash <skill-dir>/scripts/project-facts.sh path/to/repo
```

`<skill-dir>` is the folder that contains this skill's `SKILL.md`. The script is read-only and needs only bash, grep, sed, awk and find. It prints Markdown with:

- workspaces, projects and Swift packages found
- deployment targets, `SWIFT_VERSION`, strict concurrency level, default actor isolation and upcoming feature flags, with how many build configurations use each value
- Package.swift tools version, platforms, language modes and feature flags
- shared schemes and test plans
- which frameworks the Swift sources import
- SwiftData usage: models, versioned schemas, migration plans, containers, model actors
- concurrency escape hatches and legacy concurrency already in the code
- tooling present: SwiftLint, SwiftFormat, fastlane, Tuist, XcodeGen, CocoaPods, CI, agent instruction files

Mixed values are a finding, not noise. Two deployment targets or two Swift versions usually mean targets with different settings, and you need to know which target you are changing.

## Where each fact lives

| Fact | Where to look |
|---|---|
| Deployment target | `IPHONEOS_DEPLOYMENT_TARGET` (and `MACOSX_`, `XROS_`, `WATCHOS_`, `TVOS_`) in `*.xcodeproj/project.pbxproj` or `*.xcconfig`. In packages, `platforms:` in `Package.swift`. |
| Swift language mode | `SWIFT_VERSION` in build settings. In packages, `swiftLanguageModes:` or a per-target `.swiftLanguageMode(...)`. The tools version on line 1 of `Package.swift` is not the language mode. |
| Strict concurrency | `SWIFT_STRICT_CONCURRENCY` (`minimal`, `targeted`, `complete`). In Swift 6 language mode it is always complete. |
| Default isolation | `SWIFT_DEFAULT_ACTOR_ISOLATION` in build settings, or `.defaultIsolation(MainActor.self)` in `Package.swift`. If it is `MainActor`, unannotated code is already main actor isolated, and adding `@MainActor` is redundant. |
| Approachable concurrency and feature flags | `SWIFT_APPROACHABLE_CONCURRENCY`, `SWIFT_UPCOMING_FEATURE_*`, and `.enableUpcomingFeature(...)` in `Package.swift`. |
| Schemes | Shared schemes are files under `xcshareddata/xcschemes/*.xcscheme`. `xcodebuild -list` shows all of them, including generated ones. |
| Test plans | `*.xctestplan` files. The scheme's test action names the default plan. |
| Which tests cover a file | Search the test targets for the type name. No hit means no coverage, which is itself a fact for the plan. |
| Persistence | `@Model`, `ModelContainer(`, `VersionedSchema`, `SchemaMigrationPlan`, `@ModelActor`. For Core Data, `*.xcdatamodeld` and `NSPersistentContainer`. |
| Has the store shipped | Release tags, the App Store version in the project settings, a migration plan already present, or ask. Do not guess. |
| Generated projects | `project.yml` (XcodeGen) or `Project.swift` (Tuist) means the `.xcodeproj` is generated. Edit the manifest, not the project file. |

Settings resolve in layers: target settings override project settings, and `.xcconfig` files can sit under either. When it matters, ask the build system instead of reading files:

```bash
xcodebuild -scheme App -showBuildSettings 2>/dev/null \
  | grep -E " (IPHONEOS_DEPLOYMENT_TARGET|SWIFT_VERSION|SWIFT_STRICT_CONCURRENCY|SWIFT_DEFAULT_ACTOR_ISOLATION) ="
```

## Taking a baseline

Do this before the first edit on any standard or high-risk task.

1. Build the scheme you will be changing, for the destination the app really runs on.
2. Run the tests that cover the area. If you do not know which, run the unit test plan.
3. Record: build result, number of tests executed, names of tests that already fail, and warnings already present in the files you plan to touch.

Commands are in [verification-gates.md](verification-gates.md). Put the baseline in the plan under Assumptions, for example "Baseline: build passes, 212 tests, `SyncQueueTests/retriesAfterTimeout` already fails".

If the baseline build fails, stop and tell the user. Building on a broken baseline means every later failure is ambiguous.

If you cannot build at all in this environment, say so in the plan and list every gate you cannot run. Carry on with the gates you can.

## Finding the pattern in use

Before adding anything, find how the codebase already does that kind of thing. Look for two existing examples and copy their shape.

| You are adding | Find |
|---|---|
| A screen | Two existing screens of similar weight: where state lives, how they load data, how they navigate away |
| A model or store | An existing one: value type or class, `@Observable` or `ObservableObject`, who creates it, how it is injected |
| A network call | An existing endpoint: client type, error type, retry and auth handling |
| A test | The nearest test file: Swift Testing or XCTest, fixtures, how dependencies are faked |
| A dependency | How existing ones are wired: environment, initializer injection, a container |

If the two examples disagree, the codebase is mid-migration. Follow the newer one and say so in the plan.

A new pattern is a design decision for the user, not a detail of your change. If you believe one is needed, put it in the plan as a recommendation and wait.

## Tracing the data path

For the thing you are changing, write down each hop and who owns it:

```
Source of truth -> transformation -> owner of UI state -> view
SwiftData store -> InspectionRepository (ModelActor) -> InspectionListModel (@MainActor, @Observable) -> InspectionListView
```

For each hop answer three questions:

1. Who owns this state, and who else can write to it?
2. Which actor or thread does it live on?
3. How does a change here reach the next hop: observation, a callback, an async sequence, a manual refresh?

Most bugs sit at a hop where one of these answers is "not sure". That is where to read more before planning.

## Git state

```bash
git status --short
git log --oneline -5
git branch --show-current
```

- If there are uncommitted changes you did not make, list them in the plan and work around them. Never discard, stash or overwrite them.
- If you are on the default branch, mention it. Do not create branches or commits unless the user asked.
- If the project file (`project.pbxproj`) is already modified, be careful: adding files will touch it again and merges there are painful.
