# Verification gates

Read this in step 4 for the commands behind each gate, how to keep logs out of the conversation, and what to record as evidence.

## Contents

- Choosing the tool
- Find the scheme and destination
- Gate 1: Build
- Gates 2, 3 and 9: Tests
- Gate 4: Migration
- Gate 5: Concurrency
- Gate 6: UI walk
- Gate 7: Previews
- Gate 8: Diff audit
- Evidence
- When a gate cannot run

## Choosing the tool

Use the first that is available:

1. The commands recorded in `.playbook/repo-map.md`. Someone already proved they work here.
2. A connected build tool: XcodeBuildMCP, or the MCP tools that ship with Xcode. They return structured errors and screenshots and keep raw logs out of your context.
3. `xcodebuild` and `xcrun simctl`, as below.
4. `swift build` and `swift test` for a pure Swift package with no UIKit or SwiftUI dependency.

Commands below use shell variables so you can set them once:

```bash
SCHEME="App"
DEST="platform=iOS Simulator,name=iPad Pro 13-inch (M4)"
LOG_DIR="${TMPDIR:-/tmp}/ios-playbook"; mkdir -p "$LOG_DIR"
```

Every command writes its log to a file and prints only the exit code and the lines that matter. Raw `xcodebuild` output is thousands of lines, and pasting it into the conversation pushes the plan out of your context.

## Find the scheme and destination

```bash
xcodebuild -list                              # add -workspace X.xcworkspace or -project X.xcodeproj if there are several
xcodebuild -scheme "$SCHEME" -showdestinations
xcrun simctl list devices available
```

Pick the destination the app actually ships on. An iPad app built only for an iPhone simulator has not been built. If the simulator named in the repo map is not installed, pick the closest installed one and say so in the report.

## Gate 1: Build

```bash
xcodebuild build -scheme "$SCHEME" -destination "$DEST" -quiet \
  > "$LOG_DIR/build.log" 2>&1; echo "build exit=$?"
grep -E "(error|warning):" "$LOG_DIR/build.log" | sort -u | head -n 40
```

Pass means exit 0 and no new warnings in files you touched:

```bash
git diff --name-only HEAD | sed 's|.*/||' > "$LOG_DIR/touched.txt"
grep "warning:" "$LOG_DIR/build.log" | grep -F -f "$LOG_DIR/touched.txt" | sort -u
```

Compare that output with the baseline. A warning that was already there is not yours, but note it. A new one is a failure, concurrency warnings most of all, because many of them become errors in Swift 6 language mode.

If the build fails, read the first error, not the last. Later errors are usually consequences.

## Gates 2, 3 and 9: Tests

Run the tests for the slice:

```bash
RESULT="$LOG_DIR/test-$(date +%s).xcresult"
xcodebuild test -scheme "$SCHEME" -destination "$DEST" \
  -only-testing:"AppTests/SyncEngineTests" \
  -resultBundlePath "$RESULT" -quiet \
  > "$LOG_DIR/test.log" 2>&1; echo "test exit=$?"
xcrun xcresulttool get test-results summary --path "$RESULT" | head -n 40
```

- `-only-testing:` takes `Target`, `Target/Suite` or `Target/Suite/test`. Swift Testing functions are addressed with their parentheses, for example `AppTests/SyncEngineTests/skipsDeletedRows()`.
- A filter that matches nothing runs zero tests and still exits 0. Always read the executed count. Zero is a failure of gate 2.
- The summary subcommand needs a recent Xcode. If it is not recognized, run `xcrun xcresulttool help get`, or fall back to `grep -E "error:|failed|Executed [0-9]+ tests|Test run with" "$LOG_DIR/test.log" | tail -n 40` without `-quiet`.
- Use a fresh result bundle path for each run. `xcodebuild` refuses to overwrite an existing one.

The whole unit test plan, once before the report (gate 9):

```bash
xcodebuild test -scheme "$SCHEME" -destination "$DEST" \
  -resultBundlePath "$LOG_DIR/full-$(date +%s).xcresult" -quiet \
  > "$LOG_DIR/full.log" 2>&1; echo "test exit=$?"
```

Add `-testPlan <name>` when the scheme has several plans, and `-skip-testing:AppUITests` if the user wants unit tests only. Failures that match the baseline are reported as pre-existing. Anything else is yours.

Swift packages:

```bash
swift build 2>&1 | tail -n 30
swift test --filter SyncEngineTests 2>&1 | tail -n 30
```

A package that imports UIKit or SwiftUI for iOS cannot be tested with `swift test` on the Mac host. Use `xcodebuild test -scheme <PackageScheme> -destination "$DEST"` from the package folder instead.

For gate 3, prove a new test can fail. For a bug fix, run the test before applying the fix and record the failure, or temporarily revert the fix, run, and restore. A test that has never failed has not been shown to test anything.

## Gate 4: Migration

A migration is verified only by opening a store that the previous schema wrote. The recipe and the test code are in [swiftdata-changes.md](swiftdata-changes.md). Evidence to record: the test name, the versions it migrates between, and the assertions on migrated data.

If the app has shipped and you can get a store file from a real previous build, running the new build against it in the simulator is stronger evidence than a synthetic store. Ask the user if one exists.

## Gate 5: Concurrency

1. Gate 1 output shows no new concurrency diagnostics.
2. The diff adds no silencers. Gate 8 flags them.
3. Tests pass under Thread Sanitizer:

```bash
xcodebuild test -scheme "$SCHEME" -destination "$DEST" \
  -only-testing:"AppTests/SyncEngineTests" -enableThreadSanitizer YES \
  -resultBundlePath "$LOG_DIR/tsan-$(date +%s).xcresult" -quiet \
  > "$LOG_DIR/tsan.log" 2>&1; echo "tsan exit=$?"
grep -n "ThreadSanitizer" "$LOG_DIR/tsan.log" | head -n 20
```

4. Run the app flows that receive callbacks from system frameworks (delegates, notifications, Combine sinks). Isolation assertions in Swift 6 mode trap at run time only, so a test suite that never drives those callbacks proves nothing about them.

Thread Sanitizer only sees races on code paths that execute. Say which paths the tests covered.

## Gate 6: UI walk

Build, install and launch in the simulator, then walk the path you changed.

```bash
xcrun simctl boot "iPad Pro 13-inch (M4)" 2>/dev/null || true
APP_PATH="$(xcodebuild -scheme "$SCHEME" -destination "$DEST" -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ TARGET_BUILD_DIR =/{d=$2} / WRAPPER_NAME =/{w=$2} END{print d "/" w}')"
xcrun simctl install booted "$APP_PATH"
xcrun simctl launch booted com.example.app          # the bundle identifier
xcrun simctl io booted screenshot "$LOG_DIR/after.png"
```

Vary the conditions without leaving the terminal:

```bash
xcrun simctl ui booted appearance dark
xcrun simctl ui booted content_size accessibility-extra-extra-extra-large
xcrun simctl openurl booted "myapp://inspection/42"   # deep links
```

Checklist for anything visible:

- the changed path works from a cold launch
- largest accessibility text size: nothing truncated or overlapping
- portrait and landscape
- on iPad, a narrow window (the app is resizable, so an assumed width will break)
- dark mode
- every new control has a VoiceOver label, and decorative images are hidden from it
- empty, loading and error states, not only the happy path
- navigate away and back, and background and foreground the app

Look at the screenshot yourself if your tool can read images. If you can run the app but cannot see it, say "launched without crashing, not visually checked".

## Gate 7: Previews

`#Preview` blocks compile with the target, so a passing debug build shows they compile. It does not show they render. If a tool can render previews (Xcode's MCP tools can), render the ones for views you touched. Otherwise report "previews compile, not rendered".

A preview that needs a model container or environment object must build its own in-memory data. A preview that crashes costs the next person time, so treat a broken preview as a failed gate.

## Gate 8: Diff audit

```bash
bash <skill-dir>/scripts/diff-audit.sh            # working tree against HEAD
bash <skill-dir>/scripts/diff-audit.sh main       # everything since the branch left main
```

`<skill-dir>` is the folder that contains this skill's `SKILL.md`. The script lists, with file and line: force unwraps and `try!`/`as!`, new concurrency silencers, legacy concurrency (`DispatchQueue`, `Task.detached`), leftover `print` and `TODO`, lint suppressions, tests that were removed or disabled, changes to files that hold `@Model` types, and changes to sensitive files (project file, entitlements, `Info.plist`, privacy manifest, package manifests). It is a list of things to look at, not a verdict. Explain each hit in the report or fix it.

Then read the whole diff yourself as a reviewer who did not write it:

- Does every changed line serve the goal? Anything else goes back or onto "Noticed, not fixed".
- Are files changed that the plan did not name?
- Is access control wider than before?
- Is there an error path that is swallowed or only logged?
- Did the project file change in ways you did not intend?

## Evidence

Record for each gate what ran and what came back, in one line:

```
1 Build: xcodebuild build, scheme App, iPad Pro 13-inch (M4): exit 0, no new warnings in touched files
2 Tests: SyncEngineTests: 14 executed, 0 failed
3 New test: skipsDeletedRows() failed before the fix ("index out of range"), passes after
9 Full suite: 213 executed, 1 failed (retriesAfterTimeout, same as baseline)
```

Counts and exit codes are evidence. "Tests pass" with no count is not.

## When a gate cannot run

| Situation | What to do |
|---|---|
| No Xcode or simulator in this environment | Run what you can (`swift build`, the diff audit, reading the diff). List every gate you could not run under "Not verified", with the exact command for the user to run. |
| The simulator in the repo map is missing | Use the closest installed device of the same idiom and say which one. |
| Tests need credentials or a network you do not have | Run the rest. Name the skipped tests. |
| The full suite takes too long | Ask the user whether to run it. Do not skip it silently, and do not run it on every slice. |
| A UI change with no way to see the screen | Launch it to prove it does not crash, and say it was not visually checked. |

Never convert "could not run" into "passed".
