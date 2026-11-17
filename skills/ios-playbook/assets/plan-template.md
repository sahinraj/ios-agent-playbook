# Plan: <short title>

- Created: <date> by <model or person>
- Planned against commit: <hash>
- Status: not started | in progress | done

## Goal

<One sentence: the outcome the user will see.>

## Risk

<trivial | standard | high>. <Why. Name the trigger for high risk.>

## Out of scope

- <What you are deliberately not touching.>

## Assumptions

- <Fact the plan depends on>: verified (<file>) | unverified
- Baseline: <build result>, <tests executed>, <known failures>

## Slices

### [ ] 1. <One outcome>

- Files: <paths>
- Change: <what, exactly. Name types and functions. Quote the existing lines the change hangs on.>
- Gates: <numbers, with the exact commands if they differ from the repo map>
- Done when: <observable result>
- Evidence: <filled in when the slice finishes>

### [ ] 2. <One outcome>

- Files:
- Change:
- Gates:
- Done when:
- Evidence:

## Compiler will not catch

- <Silent failure>: <how it will be checked>

## Gates

<Which of the nine apply. Anything skipped, with the reason.>

## Most likely to go wrong

1. <Trap, and how it would show up.>
2. <Trap, and how it would show up.>
3. <Trap, and how it would show up.>

## Stop and report if

- a quoted line is not where this plan says it is
- a gate fails twice for the same reason
- a slice needs a file this plan does not name
- <task-specific condition>

## Changes to the plan

- <date>: <what changed and why>
