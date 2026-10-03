---
name: task-develop
description: Develop a task end to end, starting from a discussion. Works out what to build with the user, writes it up as docs/tasks/<name>.md, plans with an Opus sub-agent, implements with a Sonnet agent, audits the result against the acceptance criteria, runs PrReviewer, then hands over for human review. Pass a path to reuse a task file that already exists. No issue tracker involved.
argument-hint: "[taskName] - short name for a new task, or a path to an existing task .md file. Omit it to start from a blank discussion"
model: opus
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion, TodoWrite, Agent, Skill, EnterPlanMode, ExitPlanMode
---

# Develop a task, from discussion to PR

Drive one task from "we have not decided what to build yet" to "reviewed, committed, and in a PR
that PrReviewer approves".

There is no issue tracker in this flow. The skill works out the task with the user, writes it to
`docs/tasks/<name>.md`, and that file is the source of truth for the rest of the run. If a task
file already exists, pass its path and the discussion is skipped.

The work is split across models on purpose: Opus plans and judges, Sonnet implements.
Planning and judging need the stronger model because a wrong plan is expensive to undo; writing
code against an approved plan does not.

This file runs on Opus for the same reason - its own job is judgement, not typing. It decides what
is ambiguous enough to ask about, checks the plan is complete, and rules on which PrReviewer findings
are valid. Each sub-agent's model is set on its `Agent` call, so it holds whatever the session
model turns out to be.

## The one thing that can break this flow

**Accepting the plan at step 5 clears the conversation.** The user has
`showClearContextOnPlanAccept: true`. After the clear, this SKILL.md is gone from context. Only
the accepted plan survives.

So the plan is not just a plan - it is the carrier for the rest of the workflow. The planner at
step 4 must end the plan with a `## Post-approval workflow` section that spells out steps 6-12 as
instructions, not as a summary. If that section is missing or vague, the work stops dead right
after implementation and nobody notices. Check it is there before presenting the plan.

That section also holds a `### Progress` checklist, ticked in the plan file itself as each step
finishes. The context clear is not the only way a run stops - the context window fills up, or the
user closes the session and comes back tomorrow. A todo list dies with the session; the file does
not. The plan file is the progress record, so an interrupted run can be picked up from the first
unticked box instead of starting again.

## Files

Two different kinds, and they are treated differently:

```
docs/tasks/<TASK>.md                       the task: what and why. Part of the change.
.claude/task-develop/<TASK>/plan.md        the plan: how. Working file.
.claude/task-develop/<TASK>/ac-audit.md    audit findings and PrReviewer disagreements.
```

`<TASK>` is a short kebab-case name: `add-refunds`. It names the task file and the working folder,
so both are easy to find later.

**The task file is part of the change.** It lives in the repo and is staged with the code at step
10, so the history says what was asked for next to what was built. Everything under
`.claude/task-develop/` is a working artifact: never staged, but named in the step 9 handoff so
the user knows it exists.

The task file and the plan stay separate on purpose. The task file is the only record of the
acceptance criteria that the planner never touched - the audit at step 7 judges the code against
*it*, not against the plan's claims about it.

From step 6 on, `plan.md` is not read-only. Tick its `### Progress` boxes as each step finishes,
so the file always says how far the run got.

---

## Step 1 - Settle the task

The argument is `taskName`, and it is optional. Three forms:

| Argument | What it means |
|----------|---------------|
| A path to an existing `.md` file | The user already wrote the task. **Read it** - go to "Reading an existing task" below. |
| A short name (`add-refunds`) | Check `docs/tasks/<name>.md`. If it exists, read it. If not, this is a new task - **discuss it**. |
| Nothing | A new task with no name yet. Ask what they want to build, then derive a kebab-case name from the answer and confirm it. |

Either way, step 1 ends with the same thing in hand: acceptance criteria, scope of work, and the
target repository.

### Reading an existing task

Read the file with `Read`. If nothing is there, stop and say which paths you tried. **Never
reconstruct a task from its file name** - a guessed task produces a confident plan for the wrong
work, which is worse than no plan.

Take from it:

- **Acceptance criteria**, copied word for word, itemised as `AC-1`, `AC-2`, ... The wording must
  stay verbatim because the audit at step 7 compares the code against these exact sentences. A
  paraphrase quietly moves the goalposts.
- The **Scope of Work**: what is deliberately in, and what is out. Heading wording varies - look
  for `Scope of Work`, `Scope of work`, `SoW`, or `Scope`.
- The title, the description, and the repository the change belongs in.

A human wrote this file, so its headings vary. Read the whole thing before deciding something is
missing - the criteria may sit under `Acceptance criteria`, `AC`, `Done when`, or plain prose. If
after reading there really are no acceptance criteria, or no scope, that is an open question for
step 3, not something to invent. Then skip step 2: the file already exists and the user wrote it.

### Discussing a new task

This is a conversation, not a form to fill in. Use `AskUserQuestion`, up to 4 questions per call,
so the user answers in batches instead of a drip of prompts.

**Read the code before asking.** A question you could have answered by opening a file costs the
user a round trip and makes the rest of the questions look careless. Search first, then ask about
what is genuinely undecided.

Cover these, in this order:

1. **What and why.** What should change, and what problem it solves. Without the why, every later
   judgement call gets made blind.
2. **Acceptance criteria.** Turn the answer into numbered, checkable sentences and show them back.
   "Refunds work" is not a criterion. "A refund of more than the original charge is rejected with
   a 422" is. Each one must be something you could point a test at.
3. **Scope of work.** What is in. Then ask specifically what is *out* - users rarely volunteer
   this, and it is the main defence against a plan that grows past the task.
4. **Where.** Which repository, and which part of the code.
5. **Anything that is not yours to decide.** Data loss, a change to a public contract, a
   migration, UI with no design attached.

Keep going until you could write the task file yourself without guessing at any part of it. Do not
pad the criteria with things the user did not ask for - an invented AC is work nobody wanted, and
the audit at step 7 will dutifully enforce it.

**Done when:**

- [ ] Acceptance criteria are checkable sentences the user agreed to - read or agreed, never invented
- [ ] What is *out* of scope is written down, not only what is in
- [ ] The target repository is known, not assumed
- [ ] `<TASK>` fixed as a short kebab-case name

## Step 2 - Write the task file and confirm it

**Skip this step if step 1 read an existing file.** It is already written and already the user's.

Read `references/task-template.md` and write `docs/tasks/<TASK>.md` from it. Create `docs/tasks/`
if it is not there.

Then show it and wait for a yes. This is a plain confirmation in the conversation - not plan mode,
and nothing is cleared.

This gate is here because the criteria are copied verbatim into the plan at step 4 and judged
verbatim at step 7. A criterion that is wrong here is wrong everywhere downstream, and the audit
will confirm the wrong thing with a straight face. One round of reading now is cheaper than a
re-plan later.

**Corrections:** edit the file, show it again, repeat. No cap on rounds, and no reason to push for
approval.

**Done when:**

- [ ] `docs/tasks/<TASK>.md` written, following the template
- [ ] The user approved it - not "did not object"
- [ ] The file on disk matches the version they approved

## Step 3 - Resolve open questions

If step 1 was a discussion, most of this is already done - do not ask the same questions twice.
Re-read the approved task file and check only for what the implementation needs and the task file
does not say. Usually that is a short list, or empty.

If step 1 read an existing file, this is the full gate.

Ask the user about anything that would change the plan. Use `AskUserQuestion` and batch up to 4
questions per call, so the user answers in one pass instead of a drip of prompts.

Worth asking about:

- Acceptance criteria missing, or too vague to check
- Scope of Work missing, or in conflict with the AC
- Behaviour that could reasonably go two ways
- Which repository, when the task file does not say
- UI work with no design attached
- A decision that is not yours to make: data loss, a public contract change, a migration

Not worth asking about: anything you can settle by reading the code or the task file. Read first,
then ask about what is left.

If an answer opens a new question, ask again. Move to step 4 only when nothing is open. This is
the point of the whole gate - a question answered now costs one message, the same question found
at step 9 costs a rewrite.

**Done when:**

- [ ] Every gap in the AC or the Scope of Work was asked about, not guessed
- [ ] No answer opened a new question
- [ ] Every answer is written down, ready to go into the planner brief

## Step 4 - Plan, with an Opus sub-agent

Spawn one sub-agent to write the plan:

```
Agent(subagent_type: "Plan", model: "opus", prompt: <brief>)
```

The sub-agent has no memory of this conversation, so the brief must carry everything: the task
name and title, the path `docs/tasks/<TASK>.md`, the AC list verbatim, the Scope of Work verbatim,
every answer from step 3, and the repository path.

Pass the AC and the Scope of Work as text in the brief. Do not tell the sub-agent to go and read
the task file itself - it would read the same file you already have, and a second reading is a
second chance to paraphrase a criterion. The path is for the record, not for the sub-agent to
work from.

Read `references/plan-template.md` and pass the template to the sub-agent. It defines the sections
the plan must have, including the `## Post-approval workflow` block that has to survive the
context clear.

When the sub-agent returns:

1. Write the plan to `.claude/task-develop/<TASK>/plan.md`.
2. Check the `## Post-approval workflow` section is present and complete. If it is not, fix it
   yourself from the template before going on.
3. Call `EnterPlanMode`, then present the plan with `ExitPlanMode`.

Write the file *before* entering plan mode. Plan mode blocks writes.

**Done when:**

- [ ] The brief carried the AC and Scope of Work verbatim - the sub-agent shares no context
- [ ] Plan written to `.claude/task-develop/<TASK>/plan.md`, before `EnterPlanMode`
- [ ] `## Post-approval workflow` is present and states steps 6-12 as instructions, not a summary
- [ ] It carries the `### Progress` checklist and the resume instructions, copied in full
- [ ] Every AC row names at least one task

## Step 5 - The user reviews the plan

The user either approves or comments.

**Comments:** update the plan. For a small correction, edit it directly. For a change that shifts
the approach, send the feedback back to the Opus planner and take a fresh plan. Rewrite the file,
then present again. Repeat until approved - there is no cap on rounds here, and no reason to push
for approval.

**Approved:** go to step 6.

**Done when:**

- [ ] The user approved - not "did not object"
- [ ] The file on disk matches the version the user approved

## Step 6 - Implement, with a Sonnet agent

On approval the harness clears the context and switches to auto mode. Both already happen through
the user's settings. Do not try to trigger them.

Before the first edit, check the current branch. If it is the repo's default branch, create a
task branch with `Skill(skill: "corp-dev:create-branch")`. If you are already on a feature
branch, stay on it.

Then spawn the implementer:

```
Agent(subagent_type: "general-purpose", model: "sonnet", prompt: <brief>)
```

The brief must contain:

- The path to `.claude/task-develop/<TASK>/plan.md`, and an instruction to read it in full
- The task name, and the path `docs/tasks/<TASK>.md`
- An instruction **not** to edit the task file. It records what was asked for, so changing it to
  match the code would erase the only thing the audit at step 7 can check against
- An instruction to follow the repo's own `CLAUDE.md` conventions
- An instruction to write the tests named in the plan's Test Plan, in the same change
- An instruction to build and run the test suite, and to report the real output - a failing suite
  reported as green is the one failure mode that wastes the whole rest of the flow

**Done when:**

- [ ] Not sitting on the repo's default branch
- [ ] The implementer was given the plan path and read the plan in full
- [ ] The tests named in the Test Plan exist in the same change
- [ ] Build and test output reported as it actually was
- [ ] The Step 6 box ticked in `plan.md` - and every later step's box ticked the same way

## Step 7 - Audit against the acceptance criteria

Spawn an Opus sub-agent to check the finished work against the AC. This is a separate agent from
the implementer on purpose: an agent that just wrote the code is a poor judge of whether the code
meets the criteria.

Read `references/ac-audit.md` for the auditor brief.

The auditor judges the **code and the tests**, not the plan's claims. A plan row saying "AC-3
satisfied" proves nothing.

- **Findings:** write them to `.claude/task-develop/<TASK>/ac-audit.md`, then fix them. Re-run
  the audit afterwards to confirm the fix landed. Stop after 3 rounds and hand the remaining
  findings to the user - three failed attempts means something is wrong with the plan, not with
  the code.
- **No findings:** go to step 8.

**Done when:**

- [ ] The auditor was a fresh agent, not the implementer
- [ ] Every `AC-n` has a verdict backed by a file and a test, not by the plan's claim
- [ ] Findings written to `ac-audit.md` and fixed
- [ ] The audit was re-run after fixing, or 3 rounds were reached and handed to the user

## Step 8 - Run PrReviewer

Invoke `Skill(skill: "corp-dev:PrReviewer")` on the local changes.

Fix every finding that is valid. For a finding you disagree with, do not silently drop it: write
the finding and your reasoning into `.claude/task-develop/<TASK>/ac-audit.md`. Step 12 will need
that reasoning to reply to the same comment on the PR.

If PrReviewer is not available in this repo, say so and go on. Do not fake a review pass.

**Done when:**

- [ ] PrReviewer ran, or its absence was stated plainly
- [ ] Every valid finding is fixed
- [ ] Every disputed finding is in `ac-audit.md` with the reasoning

## Step 9 - Hand over for human review

Report, in this order:

1. What changed - files grouped by what they do, not a raw diff dump
2. Build and test output, as it actually was
3. AC audit result - each `AC-n`, met or not
4. PrReviewer result - fixed, and disputed with reasoning
5. Anything left out, and why
6. `docs/tasks/<TASK>.md`, which goes into the commit, and the working files under
   `.claude/task-develop/<TASK>/`, which do not

Then stop and wait.

**Comments from the user:** address them, then **return to step 7**. Re-auditing after a change
is the point - a fix made at review time is exactly the kind of change that quietly breaks an AC.

**No comments:** go to step 10.

**Done when:**

- [ ] All six points reported, including what was left out
- [ ] Anything that failed is reported as failed
- [ ] Stopped and waited - did not roll on into a commit

## Steps 10-12 - Offer, one at a time

Each of these is an offer. Ask, wait, and accept "no" as the end of the run. The user may want to
inspect something between any two of them.

| Step | Offer | How |
|------|-------|-----|
| 10 | Commit | `Skill(skill: "corp-dev:create-commit")` - keeps the message within the VCS guidelines |
| 11 | Open a PR | `Skill(skill: "corp-dev:create-pr")` - pushes the branch itself |
| 12 | Babysit PrReviewer | `Skill(skill: "corp-dev:babysit-PrReviewer-pr")` with the PR URL from step 11 |

There is no separate push step. `create-pr` pushes the branch as part of its own work, so pushing
first only duplicates it. If the user commits but declines the PR, the branch stays local - say
that plainly, so nobody assumes the work is on the remote.

Step 12 needs the PR URL from step 11. With no PR there is nothing to babysit, so do not offer it.

**What goes in the commit:** the code, the tests, and `docs/tasks/<TASK>.md`. The task file is
part of the change - it is why the rest of the diff exists. Never stage anything under
`.claude/task-develop/`.

**Done when:**

- [ ] Each offer was made on its own, and a "no" ended the run
- [ ] `docs/tasks/<TASK>.md` is in the commit
- [ ] `.claude/task-develop/` is not in the commit
- [ ] If the PR was declined, the user was told the branch is still local
- [ ] The babysitter got a real PR URL, or was not offered at all
