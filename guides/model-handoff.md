# Strong model plans, cheaper model executes

How to use the playbook to split iOS work between a top-tier model and a cheaper one, without losing the quality of the first or paying for it on every turn.

## What actually carries over

A playbook does not make a cheaper model as capable as a stronger one. It gives the cheaper model a process: how to size a task, plan it, slice it and check it. That helps, and it is the smaller win.

The bigger win is getting the strong model to write down the things about your repo that take real reasoning to work out: the build and test commands that work, the module layout, the SwiftData and concurrency setup, and the places where a change breaks something the compiler will not flag. A cheaper model follows a good map well. It is much weaker at drawing one.

So spend the strong model in this order:

1. The repo map and risk map, once per repo.
2. A plan for each hard task.
3. A short consult at the few decision points that matter.

Everything else can run on the cheaper model.

## The workflow

### 1. Map each repo with your strongest model

```text
/ios-playbook map
```

One session per repo. It writes `.playbook/repo-map.md` and `.playbook/risk-map.md`, verifies the build and test commands by running them, and adds a short pointer block to your instruction file. Read both files when it finishes. You know things about the codebase the model does not, and five minutes of corrections now pays back on every later task.

### 2. Plan the hard tasks with the strong model

```text
/ios-playbook plan move the Sync module to Swift 6 language mode
```

Good candidates are the tasks where the approach matters more than the typing: a Swift 6 migration, a SwiftData schema change on a shipped store, an offline sync change, a large refactor.

The plan is saved to `.playbook/plans/<name>.md`. It names files and types, quotes the lines each change hangs on, gives the gate for every slice, lists the three things most likely to go wrong, and says when the executor must stop. Read it before anyone executes it. This is the cheapest point to change direction.

### 3. Execute with the cheaper model

```text
/ios-playbook execute .playbook/plans/sync-swift6.md
```

The executor checks that the plan still matches the code, then works one slice at a time, running each slice's gates and recording the evidence in the plan file. It does not redesign. If the plan is wrong it stops and says why.

Use a fresh session per plan. Everything the executor needs is in the plan file and the repo map.

### 4. Everyday tasks

For work that does not need a saved plan:

```text
/ios-playbook add a status filter to the inspection list
```

The cheaper model sizes it, shows the plan, and runs the loop. Most standard tasks never need the strong model at all.

## The advisor in Claude Code

Claude Code can attach a stronger model as an advisor. The working model decides when to consult it. The playbook tells it to do so at exactly three points, and never on trivial or standard tasks:

1. after writing a high-risk plan, before the first edit
2. when the same failure has survived two different fix attempts
3. before the final report on a high-risk task

Setup, with the cheaper model doing the work:

```text
/model fable      only needed once, if your plan asks you to accept usage-credit billing for the top-tier model
/advisor fable    replies "Advisor set to" and the model name
/model opus       switch back, or every turn runs on the top-tier model
```

The order matters on plans where the top-tier model is billed to usage credits: the advisor setting is not saved until you have accepted that billing by selecting the model once, and accepting it makes that model your selected model. Model aliases and accepted pairings change between releases, so run `/advisor` with no argument to see what your version accepts. Details: https://code.claude.com/docs/en/advisor

If you do not want any usage-credit spend, set the advisor to the same tier as the working model. You still get an independent second look at the plan and the finish.

### What it costs and how to keep that down

Three facts from the documentation shape the cost:

- Every consult sends the whole conversation to the advisor again, and that read is not cached. A long session makes every consult more expensive.
- Advisor usage is billed at the advisor model's rates. On some plans a top-tier advisor draws on paid usage credits.
- There is no setting that caps how often the advisor is called. Instructions are the only control.

So:

- **One task per session, then clear it.** This is the biggest saver, because consult cost follows session length.
- **Keep logs out of the conversation.** The playbook already sends build and test output to files and reads only the errors.
- **Let the playbook gate the consults.** Three points, high-risk tasks only.
- **Set a monthly limit** on usage credits in your account settings, and watch `/usage`.
- **Do not leave the top-tier model selected** after accepting the billing prompt, and check any scripts that run the CLI non-interactively.
- **Switch models instead** for a task that is hard on every turn. Many consults cost more than doing that one task on the strong model.

As a rough guide, multiply the session size in tokens by the advisor's input price to get the cost of one consult before output. Check current prices for your plan.

### If the advisor never fires

- It needs the vendor's API directly. It is not available through every cloud provider, and through a gateway it only works if the gateway forwards the request intact.
- It depends on feature flag fetching. If telemetry is disabled by an environment variable, the advisor can stay off.
- If the pairing was refused earlier in a conversation, it stays off until you clear or compact the session.
- An organization allowlist of models can exclude it.
- The working model decides when to call it. On a standard task the playbook tells it not to.

## Other tools

GitHub Copilot has no advisor, but the same split works by hand:

1. Pick your strongest model in the model picker and run `map`, then `plan` for the hard task.
2. Switch to a cheaper model and run `execute` on the plan file.
3. At the three gates, switch back for one turn and ask the question the playbook names, or skip the gate and let the agent do its self-check.

The plan file is plain Markdown in your repo, so it does not care which tool or model wrote it or which one executes it.

## A first evening with a new repo

If you have limited time on a strong model, this is a good order:

1. `/ios-playbook map` in the repo you work in most. Read and correct the two files.
2. `/ios-playbook plan <your hardest pending task>`. Read the plan.
3. The same two steps for your second repo, if there is time.

From then on, a cheaper model with the map, the risk map and the plans is working from the strong model's understanding of your codebase, not from guesses.
