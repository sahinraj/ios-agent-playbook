# Handoff: plan mode, execute mode and the advisor

Read this in `plan` and `execute` modes, when one model plans for another, and when setting up or using an advisor.

## Contents

- The idea
- Writing a plan someone else will execute
- Executing a plan
- The advisor
- Session hygiene

## The idea

Strong models are best at the parts of a task where judgment decides the outcome: reading an unfamiliar codebase, choosing the approach, seeing what will go wrong. Cheaper models are good at carrying out a clear plan and checking each step. So split the work along that line:

| Stage | Who | Output |
|---|---|---|
| Map the repo | Strongest model available, once | `.playbook/repo-map.md`, `.playbook/risk-map.md` |
| Plan a hard task | Strong model | `.playbook/plans/<name>.md` |
| Execute the plan | Cheaper model, or a fresh session | Code, one verified slice at a time |
| Decision points | Advisor, if set | Short guidance at three gates |

The plan file is the interface. It works across models, across sessions and across tools, because it is only a Markdown file in the repo.

## Writing a plan someone else will execute

In `plan` mode you do steps 0 to 2 as usual, then write the plan to `.playbook/plans/<short-name>.md` using `assets/plan-template.md`. You do not edit source files.

The reader of this plan has none of your context. Assume a capable engineer who has never seen this codebase and cannot ask you questions.

1. **Leave no design decisions open.** If you write "choose an appropriate data structure", you have handed the hard part to the executor. Make the choice and give the reason in one line.
2. **Name things exactly.** File paths, type names, function signatures you expect to add or change. Quote the few lines of existing code that the change hangs on, so the executor can confirm they are looking at the same thing.
3. **One slice, one outcome.** For each slice: files, the change, the gates with exact commands, and what done looks like in observable terms.
4. **Write the traps down.** The three things most likely to go wrong and how each would show up. This is the part a weaker executor cannot produce alone, and it is why you are writing the plan.
5. **Say when to stop.** List the conditions under which the executor must stop and report instead of improvising: a quoted line is not where the plan says, a gate fails twice, a slice needs a file the plan did not name.
6. **Include the baseline.** Build status, test count and known failures at the commit you planned against, and that commit's hash.
7. **Keep it short enough to follow.** If the plan passes about 150 lines, the task wants to be two plans.

Finish by telling the user where the file is and how to run it:

```
Plan saved to .playbook/plans/dedupe-inspection-number.md (5 slices, high risk).
To execute: /ios-playbook execute .playbook/plans/dedupe-inspection-number.md
```

## Executing a plan

In `execute` mode the plan replaces your own steps 0 to 2, but not your judgment.

1. **Read the whole plan first**, then the repo map and risk map if they exist.
2. **Check the plan still matches the code.** Compare the commit hash with `git log -1`. Open each file the first slice names and confirm the quoted lines are there. Re-run the baseline. If anything differs, stop and report the difference. A plan written against different code is not a plan.
3. **Work one slice at a time.** Do the slice, run its gates, record one line of evidence in the plan file, mark it `[x]`, then start the next.
4. **Do not redesign.** If you think the plan is wrong, stop and say why. Do not quietly substitute your own approach, because the planner may have had a reason you cannot see, and the user approved the plan as written.
5. **Do not skip ahead** to "fix it properly" in a later slice. Each slice must pass before the next begins.
6. **Honor the stop conditions** in the plan, and the general ones in the skill.
7. **Finish with the full suite and the report**, as in steps 4 and 5 of the loop. Add what you learned to the plan file under "Changes to the plan".

Small corrections that the plan obviously intended (a typo in a path, a renamed symbol) are fine. Make them and note them. Anything that changes behavior or scope is not small.

## The advisor

Some tools can attach a stronger model that the working model consults at decision points. In Claude Code this is the advisor: set it with `/advisor`, and the working model decides when to call it. Other tools have no equivalent, in which case switch models by hand at the same three gates, or skip them and do the self-check.

Facts that shape how to use it (see the tool's documentation for current details: https://code.claude.com/docs/en/advisor):

- Each call sends the whole conversation to the advisor again, and that read is not cached. Cost grows with session length.
- Advisor usage is billed at the advisor model's rates, and on some plans a top-tier advisor draws on paid usage credits.
- There is no setting that limits how often the advisor is called. Instructions are the only control, which is why this playbook names exactly three gates.

The three gates:

1. **High-risk plan**, after writing it and before the first edit. Ask: "Is there a failure mode this plan does not cover, and is the slice order safe?"
2. **Stuck**, when the same failure has survived two different fix attempts. Ask with the evidence: what you tried, what each attempt proved, what you now believe.
3. **High-risk finish**, before the final report. Ask: "Given the diff and the gate evidence, what is still unverified that matters?"

Asking well:

- State the question in one or two sentences before the call. A vague consult gets a vague answer at full price.
- Put the evidence in the conversation first (the plan, the failing output), because the advisor sees only what is there.
- If the advice conflicts with what a test or the code shows, say so and follow the evidence.

Keeping the bill down:

- One task per session. Clear the session between tasks, since every consult re-reads everything in it.
- Keep logs out of the conversation (the skill already requires this). A session full of build output makes each consult cost more.
- Do not consult on trivial or standard tasks.
- For work that is hard on every turn, switching the main model for that task is usually better value than many consults.

Typical setup in Claude Code, with the cheaper model doing the work:

```text
/model fable      only if your plan needs a one-time consent before a top-tier model can be the advisor
/advisor fable    replies "Advisor set to" and the model name
/model opus       back to the working model
```

Aliases and pairings change between releases. Run `/advisor` with no argument to see what your version accepts.

## Session hygiene

- Before ending a session mid-task, update the plan file: which slices are done, what the next one is, anything you learned. The next session starts from that file, not from your memory.
- After a context reset, re-read the plan file and the last gate evidence before touching code.
- When handing to a person, the report from step 5 plus the plan file is the handoff. Nothing else should be needed.
