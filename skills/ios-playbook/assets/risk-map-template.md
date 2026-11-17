# Risk map

Written by `ios-playbook map` on <date>. Ranked: the first entry is where a careless change does the most damage. Add an entry whenever a bug teaches you about a fragile area.

## 1. <Short name>

- **Where**: <file or type>
- **Why it is fragile**: <the specific mechanism, in one or two sentences>
- **Before touching it**: <what to read or reproduce first>
- **After touching it**: <the check that would catch a regression>

## 2. <Short name>

- **Where**:
- **Why it is fragile**:
- **Before touching it**:
- **After touching it**:

## 3. <Short name>

- **Where**:
- **Why it is fragile**:
- **Before touching it**:
- **After touching it**:

## Escape hatches in the code

Every place the compiler has been told to stop checking. Each one needs a reason, or a plan to remove it.

| Where | What | Why it is there |
|---|---|---|
| <file:line> | `@unchecked Sendable` | <reason or "unknown"> |

## Untested code that many files depend on

| Type | Used by | Notes |
|---|---|---|
| <type> | <roughly how many files> | |
