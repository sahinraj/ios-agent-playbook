# Benchmark

A small, honest way to check whether the playbook changes how your coding agent behaves.

The playbook is about process, so the tasks test process: does the agent size the risk correctly, reproduce before fixing, separate a refactor from a feature, stop after two failed attempts, and admit what it could not verify. Each task is self-contained. No project is needed, because the prompt carries the context and asks for a plan, a next step or a report.

Each folder in `tasks/` has:

- `prompt.md`: the exact prompt to paste into the agent.
- `checks.txt`: what a good answer contains (`+`) and must avoid (`-`), as extended regexes with a tab and a reason after each.

| Task | What it tests |
|---|---|
| 01-shipped-schema-change | High-risk sizing, versioned schema, migration test against the shipped store |
| 02-crash-without-repro | Reproduce and hypothesize before fixing |
| 03-trivial-rename | Staying light on a one-line edit |
| 04-actor-isolation | Isolation change as high risk, reentrancy, Thread Sanitizer |
| 05-refactor-plus-feature | Keeping a refactor separate from a behavior change |
| 06-same-error-twice | Stopping after two failed attempts |
| 07-cannot-build | Reporting honestly when nothing could be run |
| 08-list-reorder | Silent failures in UI work: identity, text size, accessibility |
| 09-offline-queue | Sync change as high risk, duplicates on retry |
| 10-handoff-plan | Plan mode: a plan another model can execute |

## Running it

1. Start a fresh chat **without** the skill (uninstall it or use a plain agent). Paste each `prompt.md` and save the full reply as `evals/results/baseline/<task-id>.md`.
2. Install the skill, start a fresh chat for each task, prefix the prompt with `/ios-playbook` (task 10 already has it) or pick the **iOS Playbook** agent, and save the replies into `evals/results/with-skill/`.
3. Score both:

```bash
evals/score.sh evals/results/baseline evals/results/with-skill
VERBOSE=1 evals/score.sh evals/results/with-skill   # print each missed check
```

You get a Markdown table you can paste into a README, a pull request or a post. Use the same model for both runs and say which one, so the comparison is fair. Results differ between models and versions, which is why this repo ships the tasks and not a headline number.

A useful second comparison is model against model: a strong model without the skill, and a cheaper model with it. That shows how much of the gap the process closes.

## Adding a task

Create `tasks/NN-short-name/` with `prompt.md` and `checks.txt`. Keep checks about behavior that is clearly right or wrong for the scenario, not style. Write negative checks narrowly, because an answer that says "I will not claim it works" should not be penalized for containing the words. Then run `bash tests/evals_test.sh` to check the format.

Pattern checks are a floor, not a full grade. They catch a missing reproduction step or an unearned "all tests pass", but they cannot tell a thoughtful plan from one that only uses the right words. Read the answers too.
