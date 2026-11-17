# Sizing and risk

Read this when the level of a task is not obvious, or when a task changes shape while you work on it.

## Why size at all

The same process for every task fails in both directions. A full plan for a typo wastes the user's time and teaches them to ignore your plans. No plan for a schema change loses their users' data. Sizing is how the process stays proportional.

## The three levels

| Level | Plan | User OK before edits | Gates | Advisor |
|---|---|---|---|---|
| Trivial | One line stating the edit | No | 1 (build) and 8 (diff audit) | No |
| Standard | Full plan, shown in the reply | No, start after showing it | All that apply | No |
| High risk | Full plan, saved to `.playbook/plans/` | Yes | All that apply, plus the protocol for the trigger | At the three gates |

## Examples

| Task | Level | Why |
|---|---|---|
| Change a button title | Trivial | One file, no logic. Localized strings still go through the String Catalog. |
| Fix an off-by-one in a date formatter helper | Standard | Logic changed, so it needs a test that fails first. |
| Add a filter to an existing list screen | Standard | Several files, new state, but no persistence or isolation change. |
| Rename a type across the module | Standard | Mechanical, but wide. Its own slice, no behavior change. |
| Add an optional property to a `@Model` in an app that is on the App Store | High | Shipped schema. Even a lightweight change needs a versioned schema and a migration test. |
| Add a property to a `@Model` in an app that has never shipped | Standard | No store in the wild. Say that you verified it has not shipped. |
| Make a view model an actor | High | Isolation change. Every caller is affected. |
| Fix a crash that only happens during sync | High | Sync and background writes. Reproduce first. |
| Bump a package dependency a major version | High | Public API of a dependency. Expect silent behavior changes. |
| Change the retry policy of an offline queue | High | Sync, and data loss is possible without a crash. |
| Add an entitlement or change the bundle identifier | High | Signing and release configuration. |
| Adjust padding on one screen | Trivial or standard | Trivial if one view. Standard if it is a shared component used on many screens. |
| Convert one view from `ObservableObject` to `@Observable` | Standard | State ownership changes. Check every view that reads it. |
| Migrate a target to Swift 6 language mode | High | Isolation across the whole target. One module per slice. |

## Why each trigger is high risk

- **Shipped schema or migration.** A store that cannot be opened crashes the app at launch for every existing user, and tests that start from an empty store pass anyway.
- **Isolation and `Sendable`.** The compiler checks what it can see. Callbacks from system frameworks, reentrancy across `await`, and task ordering are checked at run time or not at all.
- **Sync, offline queues, background writes.** Failures here lose or duplicate data without crashing, often only under poor connectivity.
- **Auth, Keychain, entitlements, signing, release configuration.** A mistake locks users out or fails at App Store submission, long after the change looked fine in the simulator.
- **Public API of a shared module.** You cannot see every caller, and some may be in other repositories.
- **Deleting or rewriting user data.** There is no undo.
- **Operational or safety data.** A wrong number that looks plausible is worse than a crash, because nobody notices.
- **More than about 10 files.** Past this size the chance of an unintended change is high, and review quality drops.

## Changing level mid-task

Re-size out loud when:

- a trivial edit turns out to touch a second file or change behavior: it is standard now, so write the plan
- a standard task reaches a high-risk trigger, for example a "small model tweak" in an app that has shipped: stop, save the plan, get the user's OK
- a high-risk assumption turns out false, for example the store has never shipped: say so and drop to standard

Never size down to avoid the process. If you are tempted to call a schema change "trivial", that is the signal it is not.

## When the user sets the level

If the user says "just do it" on a high-risk task, follow them, state the risk in one sentence, and keep the gates. Dropping the user's approval step is their call. Dropping verification is not something they asked for.
