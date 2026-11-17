---
name: ios-playbook
description: 'Planning, slicing and verification playbook for iOS, iPadOS and macOS work in Swift, SwiftUI and SwiftData. Use it at the start of any non-trivial Apple platform task: features, bug fixes, crashes, refactors, Swift 6 concurrency or actor isolation changes, SwiftData schema changes and migrations, navigation or shared state changes, or anything that touches more than one file. Also use it when the user says plan first, be careful, verify this, map this repo, write a handoff plan or execute a plan, and when a stronger model is planning work for a cheaper model to carry out. It sizes the risk, gathers project facts, writes a plan with small slices, runs build, test, migration and UI gates on each slice, and reports with evidence. Skip it for one-line edits and pure questions.'
argument-hint: '[map | plan <task> | execute <plan file> | verify | <task>]'
license: MIT
---

# iOS Playbook

Most failed iOS changes are process failures, not knowledge failures. The agent edits before reading the project settings, fixes a symptom without reproducing the bug, ships one large diff that mixes a refactor with a migration, or says "done" without a build. This playbook is the process that prevents those. It does not teach Swift. For language and framework rules, load a domain skill (last section).

What you owe the user on every task:

1. Before the first edit, show the plan from step 2 and name the gates you will run.
2. Report something as verified only if you ran it and saw the result. Otherwise call it unverified.
3. If you skip a step, say which one and why. Skipping is fine. Skipping silently is not.

## Pick the mode

The words after the skill name are the request. Look at the first one.

| First word | What to do |
|---|---|
| `map` | Build the repo map and risk map for this project. Follow [references/repo-map.md](references/repo-map.md). No source edits. |
| `plan` | Plan only, written to a file so another session or a cheaper model can execute it. Do steps 0 to 2, then follow [references/handoff.md](references/handoff.md). No source edits. |
| `execute` | Carry out an existing plan file one slice at a time. Follow "Executing a plan" in [references/handoff.md](references/handoff.md), then steps 3 to 5. |
| `verify` | Run step 4 against the current working tree and report. No source edits. |
| anything else | It is a task. Run the whole loop below. |

## Step 0: Size the task

Pick a level and say it. The level decides how much process the task gets, so a typo fix stays cheap and a migration gets the care it needs.

| Level | When | What it requires |
|---|---|---|
| **Trivial** | One file, no behavior change beyond the ask | Edit, build, report in two lines. Skip steps 1 to 3. |
| **Standard** | Everything that is neither trivial nor high risk | Steps 1 to 5. Start once the plan is shown. |
| **High risk** | Any trigger below | Steps 1 to 5, the plan saved to a file, the user's OK before the first edit, and the advisor gates. |

High-risk triggers:

- a SwiftData or Core Data schema or migration on a store that has shipped
- actor isolation, `Sendable` conformance, or moving work between actors
- sync, offline queues, conflict resolution or background writes
- auth, Keychain, entitlements, signing, privacy manifests or release configuration
- the public API of a shared package or module
- deleting or rewriting user data
- data a user relies on for an operational or safety decision
- an expected diff of more than about 10 files

Unsure between two levels? Take the higher one. If the task grows past its level while you work, stop and re-size out loud. Examples and edge cases: [references/sizing.md](references/sizing.md).

## Step 1: Read before planning

A plan built on how iOS projects usually look fails on the first build. Collect facts, each with a file path.

1. Read `.playbook/repo-map.md` and `.playbook/risk-map.md` if they exist. They hold the working build commands and the fragile areas of this repo.
2. If there is no repo map, run `bash "${CLAUDE_SKILL_DIR}/scripts/project-facts.sh"` from the repo root. If your tool does not fill in that variable, the script is in `scripts/` inside this skill's folder. It prints deployment targets, Swift language mode, concurrency settings, schemes, test plans and SwiftData usage in one pass.
3. Run `git status`. Note changes that were already there so you never overwrite the user's work.
4. Take a baseline: build, and run the tests that cover the area. Record what already fails. Without a baseline you cannot tell what you broke.
5. Find the pattern in use near the change: who owns the state, how dependencies get in, how navigation is driven. Find two existing examples of the same kind of thing and match them. Do not bring in a new pattern.
6. Trace the data path for what you are changing, end to end: source of truth, store or view model, view. Name the owner and the isolation of each hop.

For a bug, reproduce it before anything else: a failing test, or exact steps plus the log or crash report. State your hypothesis and what evidence would prove it wrong. A fix without a proven cause is a guess that happens to compile. Protocol by symptom: [references/bug-protocol.md](references/bug-protocol.md).

Where each fact lives and how to take a baseline: [references/reading-the-repo.md](references/reading-the-repo.md).

## Step 2: Write the plan

Show this before the first edit:

```
Goal: one sentence, the outcome the user will see
Risk: trivial | standard | high, and why
Out of scope: what you are deliberately not touching
Assumptions: each marked verified (with file) or unverified
Slices:
  1. files, the change, the gates that prove it
  2. ...
Compiler will not catch: the specific things you will check by hand
Gates: which of the nine apply, and any you are skipping with the reason
```

Rules for the plan:

- Smallest change that meets the goal.
- State the isolation of every new type and function: `@MainActor`, an actor, `nonisolated`, or `@concurrent`.
- For any persisted model change, say whether the store has shipped. If it has, the versioned schema and migration stage are slice 1 and get their own test. Protocol: [references/swiftdata-changes.md](references/swiftdata-changes.md).
- For isolation or `Sendable` changes, follow [references/concurrency-changes.md](references/concurrency-changes.md).
- Fill in "Compiler will not catch" from [references/silent-failures.md](references/silent-failures.md). Pick the rows that apply to this change. An empty line here usually means you have not looked.
- When two approaches are both reasonable, give one recommendation and the one-line reason. Do not hand the user a menu.
- If the plan has more than three slices or the task is high risk, save it to `.playbook/plans/<short-name>.md` and update slice status there as you go. A plan in a file survives a long session, a context reset and a handoff to another model.

Slicing recipes by change type and filled-in examples: [references/planning.md](references/planning.md) and [references/examples.md](references/examples.md).

## Step 3: Slice the work

Small slices keep every failure close to its cause. When a build breaks after 40 changed lines you know where to look. After 600 you do not.

- Each slice builds and passes tests on its own, and leaves the app in a state you could ship.
- One concept per slice. Past about 150 changed lines, split it.
- Order: types and models, then logic with its tests, then UI wiring, then cleanup.
- A mechanical refactor is its own slice with no behavior change. A migration is its own slice. Never mix either with anything else.
- Problems you notice outside the task go on a "Noticed, not fixed" list. Do not fix them on the way past, because unrequested changes hide the one the user asked for.

If the plan turns out to be wrong partway through, stop, say what you learned, and show the revised plan before continuing.

## Step 4: Verify each slice

Run the gates that apply, in order, and stop at the first failure.

| # | Gate | Applies when | Pass means |
|---|---|---|---|
| 1 | Build | always | The real scheme builds for the real destination (an iPad simulator for an iPad app). No new warnings in files you touched. |
| 2 | Targeted tests | tests cover the area | They ran (executed count above zero) and pass. |
| 3 | New logic is tested | logic changed | A test covers the new branch. For a bug, it fails before the fix and passes after. |
| 4 | Migration | a persisted schema changed | A test opens a store written by the previous schema, with rows in it, and the data is right afterwards. |
| 5 | Concurrency | isolation or `Sendable` changed | No new diagnostics, no new silencers, and the tests pass under Thread Sanitizer. |
| 6 | UI walk | anything visible changed | You ran it in the simulator and walked the path: largest Dynamic Type size, both orientations, a narrow window on iPad, dark mode, VoiceOver labels on new controls. |
| 7 | Previews | a view changed | Previews for touched views compile, and render if a tool can render them. |
| 8 | Diff audit | always | You ran `bash "${CLAUDE_SKILL_DIR}/scripts/diff-audit.sh"` and read your own diff top to bottom as a reviewer. |
| 9 | Full suite | once, before the report | The whole unit test plan passes, or its failures match the baseline. |

Commands, log filtering and what to record as evidence: [references/verification-gates.md](references/verification-gates.md). Prefer a connected build tool (XcodeBuildMCP or Xcode's own MCP tools) over raw `xcodebuild` when one is available.

If the same failure survives two different fix attempts, stop editing. Write down what you tried and what each attempt proved, then re-read the code path from the top. A third guess costs more than the re-read and is right less often.

## Step 5: Report

```
Changed: slice by slice, one line each
Evidence: each gate, the command or tool you ran, and the result
Not verified: what you could not check, and why
Noticed, not fixed: problems outside the task
Follow-ups: anything the user should decide or schedule
```

## Hard rules

- Never say a task is done without a build you actually ran.
- Never weaken, skip, disable or delete a test to get to green. If the test is wrong, say so and fix it in its own slice.
- Never silence a diagnostic to get past the compiler: no new `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, `try!` or lint suppressions. The diagnostic describes a real problem, so fix the design.
- Never write "should work". Say what you ran and what you saw, or say it is unverified.
- Do not commit, push, stash, reset or rewrite history unless the user asked. If they want commits, make one per slice.
- Keep build and test logs out of the conversation. Send them to a file and read only the errors.

## Stop and ask

Carry on by default. Stop and ask the user when:

- what you found in the code contradicts the plan or the request
- a requirement is ambiguous in a way that changes the design of a high-risk task
- the work needs something outside the plan: a new dependency, a data deletion, a signing, entitlement or CI change
- the baseline is broken before you touch anything
- the same failure survived two attempts and there is no advisor to consult

If a gate cannot be run at all (no simulator, no build tool), keep going and list it under "Not verified". Do not pretend, and do not stall.

## Advisor gates

Some tools let a cheaper model consult a stronger one mid-task (in Claude Code, `/advisor`). Each call re-reads the whole session and is billed at the stronger model's rate, so it is for decisions, not routine turns. If an advisor is set, consult it only here:

1. **High-risk plan**: after writing the plan, before the first edit.
2. **Stuck**: the same failure after two different fix attempts.
3. **High-risk finish**: before the final report.

Do not consult on trivial or standard tasks unless the user asks. Before each call, state the specific question in one or two sentences so the advice is targeted. If the advice conflicts with what the code or a test shows, say so and go with the evidence. With no advisor set, do the same three checks yourself: re-read the plan against the diff and say that you did. Setup and cost control: [references/handoff.md](references/handoff.md).

## References

| Read this | When |
|---|---|
| [references/sizing.md](references/sizing.md) | The level is not obvious |
| [references/reading-the-repo.md](references/reading-the-repo.md) | Finding settings, schemes, patterns, taking a baseline |
| [references/planning.md](references/planning.md) | Slicing recipes by change type, plan file conventions |
| [references/silent-failures.md](references/silent-failures.md) | Filling in "Compiler will not catch" |
| [references/verification-gates.md](references/verification-gates.md) | Commands and evidence for each gate |
| [references/bug-protocol.md](references/bug-protocol.md) | Any bug, crash, hang, leak or flaky test |
| [references/swiftdata-changes.md](references/swiftdata-changes.md) | Any change to a persisted model |
| [references/concurrency-changes.md](references/concurrency-changes.md) | Isolation, `Sendable`, Swift 6 migration |
| [references/repo-map.md](references/repo-map.md) | `map` mode, or keeping the repo map current |
| [references/handoff.md](references/handoff.md) | `plan` and `execute` modes, advisor setup, model pairing |
| [references/examples.md](references/examples.md) | You want to see a filled-in plan or report |

Templates for the plan, report, repo map and risk map are in `assets/`.

## Domain skills

This playbook is process only. For Swift, SwiftUI and SwiftData knowledge, load a domain skill if one is installed, for example `ios-swift-master`, or separate concurrency, SwiftUI, SwiftData, testing and debugging skills. If none is installed, rely on the project's own conventions and verify API availability against the deployment target before using anything new.
