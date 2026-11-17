# Bug protocol

Read this for any bug, crash, hang, leak or flaky test, before proposing a fix.

## Contents

- The five steps
- Reading a crash report
- By symptom
- When you cannot reproduce it
- What counts as proof

## The five steps

1. **Reproduce.** Get the failure to happen on demand: a failing test, or exact steps in the simulator with the log. If it reproduces one time in five, find the condition that makes it five in five.
2. **Isolate.** Narrow it to the smallest input, the shortest path, the single line or interleaving. Bisect with the debugger, logging or `git bisect` when it used to work.
3. **Explain.** State the cause as a chain of facts: this value is nil here because that write happened after this read. Then state what evidence would prove you wrong, and look for it.
4. **Fix.** The smallest change that removes the cause. If the same flaw exists elsewhere, list the other places. Fix them in a separate slice.
5. **Regress.** The reproduction from step 1 becomes a test that fails before the fix and passes after. Then run the tests around it.

The order matters. A fix written before step 3 is a guess. Guesses that compile get merged, and the bug comes back with a different stack trace.

## Reading a crash report

Read in this order: exception type, the crashed thread, then the first frame that belongs to the app. Frames above it are usually system code reacting to what the app did.

| Exception | What it usually means |
|---|---|
| `EXC_BREAKPOINT (SIGTRAP)` | A Swift runtime trap: force unwrap of nil, index out of range, failed `as!`, `fatalError`, `precondition`, arithmetic overflow. In Swift 6 language mode, also a failed actor isolation check (look for `dispatch_assert_queue` or an executor check in the frames). |
| `EXC_BAD_ACCESS (SIGSEGV or SIGBUS)` | Invalid memory access: an `unowned` reference to a freed object, unsafe pointers, a data race corrupting memory, or stack overflow from runaway recursion (hundreds of repeated frames). |
| `EXC_CRASH (SIGABRT)` | The process aborted itself, usually for an uncaught Objective-C exception. Read "Last Exception Backtrace": inconsistent table or collection updates, an unrecognized selector, a persistence framework assertion. |
| Termination code `0x8badf00d` | The watchdog killed the app because the main thread was blocked too long at launch, resume or in the background. |
| No crash report, the app just disappears | Likely killed for memory. Look for a jetsam event report, and at memory growth. |

Symbolicate before reasoning. An address is not a cause.

## By symptom

### Crash

- Get the report or the console output with the fatal error message. The message is often the whole answer.
- Common SwiftData traps: using a model object after it was deleted or after its context went away, and relating objects from two different contexts.
- For isolation traps, find who called the code off its actor. Usually a delegate, notification or completion handler from a system framework.
- Reproduce in a test where you can. If it needs the UI, write the steps down exactly.

### Hang or slow screen

- Decide first whether the main thread is blocked or busy. A paused debugger or a sample of the process shows what the main thread is doing.
- Usual causes: synchronous file or network work on the main actor, a semaphore or lock wait, a large `body` recomputed on every change, a fetch or sort done in `body` or `init`, heavy work that is on the main actor because of default isolation.
- Measure before and after with the same steps. "Feels faster" is not evidence.

### Data race or state that is sometimes wrong

- Run the tests under Thread Sanitizer (see [verification-gates.md](verification-gates.md)).
- Look for shared mutable state reached from more than one isolation domain, for `@unchecked Sendable` and `nonisolated(unsafe)`, and for state read before an `await` and used after it.
- Reproduce by forcing the interleaving in a test: start both operations, control the order with continuations or an injected clock.

### Wrong or stale UI

- Check identity first: unstable `ForEach` ids, conditional branches that swap view types, and objects re-created on each render.
- Then check observation: does the view read the property that changed, and is the object the same instance the writer has?
- Then check the data path hop by hop (see [reading-the-repo.md](reading-the-repo.md)). The break is at the first hop where the value is already wrong.

### Data loss or duplicates

- Treat as high risk. Find every writer of the affected data.
- Check for a background context that never saves, a queued change applied after a delete, a retry that repeats a write, and unique constraints silently replacing rows.
- Reproduce with the network off and on again, and with the app backgrounded mid-write.

### Memory leak

- Confirm with the memory graph debugger or by checking that `deinit` runs.
- Usual causes: a closure or long-lived task that captures `self` strongly, a `for await` loop over a sequence that never ends, a delegate held strongly, a timer or observer never removed.

### Flaky test

A flaky test is a real bug in the test or in the code. Do not retry until green, and do not disable it.

- Run it alone, then with its suite, then the suite twice. If it passes alone and fails in the suite, tests share state. Swift Testing runs tests in parallel by default.
- Look for real time (`sleep`, timeouts, `Date()`), real network, shared singletons, `UserDefaults`, files on disk, and reliance on test order.
- Fix by injecting a clock, giving each test its own container or directory, or serializing the suite when the shared resource is unavoidable.

## When you cannot reproduce it

Say so plainly, then:

1. List what you tried and what each attempt ruled out.
2. Add targeted diagnostics around the suspected path: structured logging with the values that matter, an assertion at the point where state first goes wrong.
3. Look for the conditions you have not covered: OS version, device class, low storage, bad network, a store migrated from an old version, a long-running session, a second window.
4. Offer a hardening change only if it is clearly labeled as such: "this guards the crash site, the cause is not proven".

Do not present a guard as a fix. A nil check that hides a crash also hides the reason the value was nil.

## What counts as proof

| Claim | Proof |
|---|---|
| "This is the cause" | Removing or changing it makes the reproduction stop, and restoring it brings the failure back. |
| "This is fixed" | The reproduction that failed now passes, with the same steps or test. |
| "This did not break anything nearby" | The surrounding tests ran, with a count, and match the baseline. |
| "It used to work" | A commit where the reproduction passes. |

If you have less than this, report what you have and call the rest unverified.
