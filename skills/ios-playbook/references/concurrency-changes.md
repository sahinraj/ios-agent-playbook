# Concurrency and isolation changes

Read this before changing actor isolation, adding or removing `Sendable`, moving work between actors, or migrating a target to Swift 6 language mode.

This is the process. For language rules, load a concurrency domain skill.

## Contents

- Why this is high risk
- Inventory first
- Decide the isolation, then write code
- Order of work
- The fix ladder
- What the compiler will not tell you
- Gates

## Why this is high risk

The compiler proves a lot about isolation, which makes a clean build feel like proof of correctness. It is not. Reentrancy, task ordering, cancellation and callbacks from system frameworks are either checked at run time or not checked at all. And the fastest way to a clean build is an annotation that turns the checking off.

## Inventory first

Collect these before planning. The facts script prints most of them.

| Fact | Why it matters |
|---|---|
| Swift language mode per target | In mode 6, data race diagnostics are errors. In mode 5 with strict concurrency they are warnings you can still ship with. |
| Strict concurrency level | `minimal`, `targeted` or `complete`. Tells you how much is already checked. |
| Default actor isolation per target | If it is `MainActor`, unannotated code is main actor isolated. Adding `@MainActor` is redundant, and `nonisolated` or `@concurrent` is how code leaves. |
| Approachable concurrency and upcoming feature flags | They change where `nonisolated async` functions run. Read the setting before reasoning about which thread something is on. |
| Existing escape hatches | Count of `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`. Each one is a place the compiler has been told to stop looking. |
| Legacy concurrency | `DispatchQueue`, semaphores, locks, completion handlers. These are the boundaries where the two worlds meet. |
| Baseline warning count | So "zero new warnings" means something. |

## Decide the isolation, then write code

For every type you add or change, decide where it lives before writing it, and put that in the plan.

| Kind of thing | Usual isolation |
|---|---|
| Views, view models, UI-facing stores | `@MainActor` (often already the default) |
| Shared mutable state that is not UI | An `actor` |
| Data passed between isolation domains | A `Sendable` value type |
| Persistence work off the main thread | A model actor, exchanging identifiers, not objects |
| CPU-heavy work | A `@concurrent` async function, or a `nonisolated` one where the settings make that run off the caller's actor |
| Pure functions and constants | `nonisolated`, no state |

If you cannot say where a type lives, you are not ready to write it.

## Order of work

- Leaf modules first: the ones that depend on nothing else in the project. Callers can only be made correct after what they call is.
- One module, or one type, per slice. Each slice ends with zero new warnings.
- For a language mode migration: raise strict concurrency to `complete` in mode 5 first and fix warnings slice by slice. Switch the language mode to 6 last, as its own slice with no other change.
- Do not mix isolation changes with feature work. When something breaks you need to know which of the two caused it.

## The fix ladder

When the compiler reports a data race risk, climb this ladder and stop at the first rung that works.

1. **Do not share it.** Make it a value type, or keep it inside one isolation domain.
2. **Send less.** Pass an identifier or a small `Sendable` snapshot instead of the object.
3. **Isolate it.** Put the state in an actor or on the main actor, and make callers `await`.
4. **Transfer it.** If the value is handed off and never used again by the sender, use the language's transfer mechanism (`sending`) so the compiler can prove it.
5. **Lock it and prove it.** Only as a last resort: `@unchecked Sendable` around state protected by a lock, with a comment that states the invariant and why it holds.

`nonisolated(unsafe)` and `@preconcurrency` are not rungs. They do not fix a race, they hide the report. Adding one needs the user's agreement and a comment explaining why it is safe, and the diff audit will list it.

## What the compiler will not tell you

Write the ones that apply into "Compiler will not catch".

- **Reentrancy.** Every `await` inside an actor method is a point where other calls can run and change state. Re-check invariants after each `await`. Do not hold "I checked it above" across one.
- **Run time isolation traps.** In Swift 6 mode, a closure the compiler believes is main actor isolated will trap if a system framework calls it on another thread. Delegates, notification observers, KVO and completion handlers from older frameworks are the usual sources, and `@preconcurrency import` is where they hide.
- **Ordering.** Separate `Task { }` blocks started from separate events do not run in a guaranteed order. If order matters, use one long-lived task consuming a stream, or make the work idempotent.
- **Dropped errors.** A `try` inside an unstructured task with no `catch` fails silently unless something awaits the task.
- **Cancellation.** Unstructured tasks are not cancelled when their creator goes away. Check that long work tests for cancellation and that the UI uses `.task` so the system cancels for you.
- **Blocking.** A lock or semaphore held across an `await`, or a blocking wait on the cooperative pool, deadlocks or starves other tasks.
- **Lifetime.** A `for await` loop over a stream that never finishes keeps everything it captures alive.
- **Where work runs now.** Changing default isolation or adopting approachable concurrency can move heavy work onto the main actor without any diagnostic. Measure the screens that do real work.

## Gates

On top of the normal gates:

1. Zero new concurrency diagnostics compared with the baseline.
2. The diff audit shows no new `@unchecked Sendable`, `nonisolated(unsafe)` or `@preconcurrency`. Any that remain are explained in the report.
3. The tests pass under Thread Sanitizer.
4. The app flows that receive callbacks from system frameworks were run in the simulator, because isolation traps only show at run time. List which flows you ran.
5. For anything that moved work on or off the main actor, the affected screen was exercised and is still responsive.

Report which paths the sanitizer run covered. A race on a path that never executed was not tested.
