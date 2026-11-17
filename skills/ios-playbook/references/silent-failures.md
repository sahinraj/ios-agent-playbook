# Silent failures: what the compiler will not catch

Read this when filling in "Compiler will not catch" in a plan, and again before the diff audit. Pick the rows that apply to your change and write each into the plan with the check you will run. Do not paste the whole table.

A green build proves the types line up. Everything below compiles cleanly and still breaks the app.

## Contents

- Persistence
- Concurrency
- SwiftUI state and identity
- Navigation and lifecycle
- Layout, accessibility and localization
- Networking, offline and sync
- Security and release
- Tests that pass for the wrong reason

## Persistence (SwiftData and Core Data)

| Silent failure | How to check |
|---|---|
| The existing store cannot be opened after a schema change, so the app crashes at launch for current users. Tests that start from an empty store pass. | Migration test that opens a store written by the previous schema version. See [swiftdata-changes.md](swiftdata-changes.md). |
| A renamed property without `@Attribute(originalName:)` is treated as delete plus add. Existing values are gone. | Migration test asserts the old values are present under the new name. |
| A new non-optional property has no default, or the default is wrong for old rows. | Migration test reads a migrated row and asserts the value. |
| `@Attribute(.unique)` makes an insert with an existing key overwrite the old row instead of failing. | Test inserting a duplicate key and assert which row survives and that this is intended. |
| A delete rule change (`.cascade`, `.nullify`) deletes more or less than before. | Test deleting a parent and count the children. |
| A write on a background context never reaches the UI, or the UI context holds stale objects. | Test or simulator walk: write in the background, assert the main context sees it. |
| A background `ModelContext` does not autosave, so changes vanish when it goes away. | Confirm an explicit `save()` and its error handling in every background write path. |
| A model object is passed across actors. It compiles in some configurations and crashes or corrupts at run time. | Search the diff for model types crossing an `await` to another actor. Pass `PersistentIdentifier` instead. |
| A deleted object is still referenced by a view or a queued task, which traps on access. | Delete while the object is on screen and while work for it is queued. |
| CloudKit-backed models gain a unique constraint, a required property or a non-optional relationship. Sync stops without a compile error. | Check every model in a CloudKit container against those three rules. |

## Concurrency

| Silent failure | How to check |
|---|---|
| Actor reentrancy: state read before an `await` is stale after it. | For every `await` inside an actor or main actor method you touched, re-check the invariants after it. |
| A callback from a system framework arrives off the main thread into code that assumes the main actor. In Swift 6 mode this traps at run time. | Run the flows that use delegates, notifications, KVO, Combine sinks or completion handlers. Search for `@preconcurrency import`. |
| Unstructured `Task { }` per event runs out of order. | Find tasks started from repeated events (typing, scrolling, notifications) and check that order does not matter or is enforced. |
| A thrown error inside `Task { }` is dropped. | Search the diff for `Task {` containing `try` without a `do`/`catch` and without the handle being kept. |
| Cancellation does not reach the work, so stale results overwrite fresh ones. | Trigger the work twice quickly and confirm the first result is discarded. Check `.task(id:)` versus `onAppear` plus `Task`. |
| A lock or semaphore held across an `await` deadlocks or starves the thread pool. | Search for `DispatchSemaphore`, `NSLock` and `os_unfair_lock` near `await`. |
| `for await` over a long-lived sequence captures `self` strongly, so the owner never deallocates. | Check for a cancellation path and a weak capture, and confirm `deinit` runs. |
| Heavy work now runs on the main actor because default isolation is `MainActor`. | Check the default isolation, and mark CPU-heavy async functions `@concurrent`. |
| A data race the compiler cannot see because of `@unchecked Sendable` or `nonisolated(unsafe)`. | Run the tests under Thread Sanitizer. |

## SwiftUI state and identity

| Silent failure | How to check |
|---|---|
| Unstable `ForEach` identity (`indices`, `id: \.self` on mutable data, a `UUID()` made in `body`) resets row state and breaks animation. | Insert, delete and reorder rows while one row has in-progress state such as a focused text field. |
| An `if`/`else` that swaps view types destroys the state below it. | Toggle the condition with state entered below it. |
| A `@State` initial value from an `init` parameter is ignored after the first render. | Re-create the parent with a new value and confirm the child updates. |
| `@Observable` object created in a view without `@State`, so it is re-created on every render. | Check ownership of every observable object you added. |
| A view reads more observable state than it shows, so it re-renders on unrelated changes. | Read `body` of touched views for properties that are read but not shown. |
| `onAppear` runs again when a view comes back, repeating loads or side effects. | Navigate away and back, and background and foreground the app. |
| A sheet or alert bound to a Boolean shows stale content because the item changed underneath. | Present, dismiss and present again with a different item. |

## Navigation and lifecycle

| Silent failure | How to check |
|---|---|
| A deep link or restored navigation path points at data that is not loaded yet or no longer exists. | Cold-launch into the deep link. Launch with the target item deleted. |
| State restoration brings back a screen whose dependencies are missing. | Background the app on the new screen, terminate it from Xcode or the simulator, relaunch. |
| Work started in the foreground is cut off in the background. | Background the app mid-operation and return after a minute. |
| A scene on iPad or Mac shares state that assumed one window. | Open a second window and repeat the flow. |

## Layout, accessibility and localization

| Silent failure | How to check |
|---|---|
| Text truncates or overlaps at large text sizes. | Set the largest accessibility content size and walk the screen. |
| A layout that assumes one width breaks in a narrow or resized window on iPad, or in landscape. | Rotate, and resize the window to its narrowest. |
| An icon-only control has no accessibility label. | Check every new `Image`-only button and custom control. |
| A hard-coded string never reaches the String Catalog. | Search the diff for string literals in views. |
| Dates, numbers or measurements formatted by hand are wrong in other locales or time zones. | Check for `FormatStyle` use, and for an explicit time zone where the value is operational. |
| Colors with fixed values are unreadable in dark mode or with increased contrast. | Switch appearance in the simulator. |

## Networking, offline and sync

| Silent failure | How to check |
|---|---|
| A request that fails offline is dropped instead of queued, or queued twice. | Run the flow in airplane mode, then reconnect. |
| A retry sends a non-idempotent request twice. | Read the retry path for each write and check for an idempotency key or a server-side guard. |
| A queued change is applied after the object it refers to was deleted or edited. | Queue a change, delete or edit the object, then let the queue flush. |
| A decoding change breaks on old cached or persisted payloads. | Decode a payload saved by the previous version. |
| Token refresh races when several requests fail at once. | Fire several requests with an expired token. |

## Security and release

| Silent failure | How to check |
|---|---|
| A secret is written to `UserDefaults`, a log or a plain file. | Search the diff for tokens and credentials near `UserDefaults`, `print` and `Logger` without `privacy: .private`. |
| A new API needs a privacy manifest reason or a usage description, and the build still succeeds. | Check new imports against the required reason APIs and `Info.plist` usage strings. |
| A changed entitlement or capability works in debug and fails in a release or TestFlight build. | Build the release configuration. Flag for the user that a device or TestFlight check is needed. |
| An API newer than the deployment target is used without an availability check in a path the compiler does not flag, such as a string selector or a dynamic lookup. | Build for the minimum OS simulator if one is installed, or list it as unverified. |

## Tests that pass for the wrong reason

| Silent failure | How to check |
|---|---|
| A test filter matched nothing, so zero tests ran and the command still succeeded. | Read the executed test count. Zero is a failure. |
| The new test passes without the fix. | Revert the fix (or stash it), run the test, confirm it fails, restore. |
| Tests share state and pass only in one order. Swift Testing runs tests in parallel by default. | Run the suite twice, and check for shared singletons, files or `UserDefaults`. |
| A test waits with a sleep and passes on a fast machine only. | Search the diff for `sleep`. Inject a clock or await the real condition. |
| A mock returns what the code expects, so the test checks the mock. | For each new test, ask what real behavior would have to break for it to fail. |
