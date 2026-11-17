# Repo map

Written by `ios-playbook map` on <date>. Facts carry a file path. Commands are marked verified only after they ran here.

## Build and verify

| What | Command | Verified |
|---|---|---|
| Build | `xcodebuild build -scheme <Scheme> -destination '<destination>' -quiet` | <date> |
| Unit tests | `xcodebuild test -scheme <Scheme> -destination '<destination>' -testPlan <Plan> -quiet` | <date>, <N> tests, about <duration> |
| One test | `xcodebuild test -scheme <Scheme> -destination '<destination>' -only-testing:<Target>/<Suite>/<test>` | <date> |
| UI tests | <command or "none"> | |

- Workspace or project: <path>
- Default simulator: <name>
- Build tool available to agents: <XcodeBuildMCP | Xcode MCP tools | none>

## Settings

| Target | Deployment target | Swift mode | Strict concurrency | Default isolation | Set in |
|---|---|---|---|---|---|
| <App> | <iOS 18.0> | <6> | <complete> | <MainActor> | <file> |

Feature flags: <list, with file>

## Layout

| Target or package | Purpose | Depends on |
|---|---|---|
| <App> | <app target, composition root> | <Core, Persistence> |

Generated project: <no | XcodeGen (project.yml) | Tuist (Project.swift)>

## Patterns

- **State ownership**: <who owns UI state, with an example file to copy>
- **Dependency injection**: <how, example file>
- **Navigation**: <how, example file>
- **Errors**: <error types, where they are shown to the user>
- **Logging**: <Logger subsystem and categories>

## Persistence

- Container built in: <file>
- Current schema version: <version, file>
- Migration plan: <file or "none">
- Writes happen in: <types, and their actor>
- CloudKit: <yes | no>
- Store has shipped: <yes, since version | no>

## Networking and sync

- Client: <type, file>
- Auth: <how tokens are stored and refreshed>
- Retry and offline: <queue type, file, policy>

## Tests

- Frameworks: <Swift Testing | XCTest | both>
- Location: <paths>
- Fixtures and fakes: <where>
- Slow or flaky: <suites, and why if known>

## Conventions

- Format and lint: <tools and config files>
- Localization: <String Catalog location>
- Review rules worth knowing: <list>

## Not verified

- <what could not be checked, and why>
