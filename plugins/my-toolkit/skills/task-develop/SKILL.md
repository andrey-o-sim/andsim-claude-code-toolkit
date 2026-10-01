---
name: task-develop
description: Develop a Jira ticket end to end - read its acceptance criteria and scope of work, plan with an Opus sub-agent, implement with a Sonnet agent, audit the result against the AC, run PrReviewer, then hand over for human review.
argument-hint: "<JIRA-KEY or Jira URL>"
model: opus
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion, TodoWrite, Agent, Skill, EnterPlanMode, ExitPlanMode, mcp__plugin_corp-mcp_atlassian-jira-dc__*, mcp__atlassian-bitbucket-dc__*, mcp__plugin_corp-mcp_atlassian-bitbucket-dc__*, mcp__corp-docs__*, mcp__plugin_corp-mcp_corp-docs__*
---

# Develop a task from a Jira ticket

Drive one Jira ticket from "not started" to "reviewed, committed, and in a PR that PrReviewer
approves". The work is split across models on purpose: Opus plans and judges, Sonnet implements.
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

## Working files

Everything this skill writes for itself goes in one place, keyed by ticket:

```
.claude/task-develop/<TICKET>/plan.md        the approved plan, and the progress record
.claude/task-develop/<TICKET>/ac-audit.md    AC audit findings and PrReviewer disagreements
```

From step 6 on, `plan.md` is not read-only. Tick its `### Progress` boxes as each step finishes,
so the file always says how far the run got.

These are working artifacts, not part of the change. Do not stage them in the commit at step 10,
and name them in the step 9 handoff so the user knows they exist.

---

## Step 1 - Read the ticket

The argument is a Jira key (`SPSD-12345`) or a Jira URL. Pull the key out of a URL.

No argument: ask for the ticket key and stop. Do not start work without one.

Read the issue with `jira_getIssue`. If the Jira MCP is not connected, stop and say so. **Never
reconstruct a ticket from its key** - a guessed ticket produces a confident plan for the wrong
work, which is worse than no plan.

From the issue, take:

- **Acceptance criteria**, copied word for word, itemised as `AC-1`, `AC-2`, ... The wording must
  stay verbatim because the audit at step 7 compares the code against these exact sentences. A
  paraphrase quietly moves the goalposts.
- Summary, description, issue type, component, and the repository the change belongs in.

If the ticket has no acceptance criteria, that is an open question for step 3, not something to
invent.

**Done when:**

- [ ] `jira_getIssue` returned a real issue for the key
- [ ] Every criterion copied word for word as `AC-1 .. AC-n`
- [ ] The target repository is known, not assumed

## Step 2 - Read the Scope of Work

The ticket description carries a **Scope of Work** section. Find it and read it. Heading wording
varies - look for `Scope of Work`, `Scope of work`, `SoW`, or `Scope`.

Scope of Work tells you what is deliberately *in* and what is *out*. It is the main defence
against a plan that grows past the ticket.

If there is no such section, or it contradicts the acceptance criteria, that is an open question
for step 3. Do not fill the gap yourself.

**Done when:**

- [ ] The Scope of Work section was found and read, or its absence recorded as a question
- [ ] What is *out* of scope is written down, not only what is in

## Step 3 - Resolve open questions

Ask the user about anything that would change the plan. Use `AskUserQuestion` and batch up to 4
questions per call, so the user answers in one pass instead of a drip of prompts.

Worth asking about:

- Acceptance criteria missing, or too vague to check
- Scope of Work missing, or in conflict with the AC
- Behaviour that could reasonably go two ways
- Which repository, when the ticket does not say
- UI work with no design attached
- A decision that is not yours to make: data loss, a public contract change, a migration

Not worth asking about: anything you can settle by reading the code or the ticket. Read first,
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

The sub-agent has no memory of this conversation, so the brief must carry everything: ticket key
and title, the AC list verbatim, the Scope of Work verbatim, every answer from step 3, and the
repository path.

Read `references/plan-template.md` and pass the template to the sub-agent. It defines the sections
the plan must have, including the `## Post-approval workflow` block that has to survive the
context clear.

When the sub-agent returns:

1. Write the plan to `.claude/task-develop/<TICKET>/plan.md`.
2. Check the `## Post-approval workflow` section is present and complete. If it is not, fix it
   yourself from the template before going on.
3. Call `EnterPlanMode`, then present the plan with `ExitPlanMode`.

Write the file *before* entering plan mode. Plan mode blocks writes.

**Done when:**

- [ ] The brief carried the AC and Scope of Work verbatim - the sub-agent shares no context
- [ ] Plan written to `.claude/task-develop/<TICKET>/plan.md`, before `EnterPlanMode`
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

- The path to `.claude/task-develop/<TICKET>/plan.md`, and an instruction to read it in full
- The ticket key
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

- **Findings:** write them to `.claude/task-develop/<TICKET>/ac-audit.md`, then fix them. Re-run
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
the finding and your reasoning into `.claude/task-develop/<TICKET>/ac-audit.md`. Step 12 will need
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
6. The working files under `.claude/task-develop/<TICKET>/`

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

Do not stage the `.claude/task-develop/` working files in the commit.

**Done when:**

- [ ] Each offer was made on its own, and a "no" ended the run
- [ ] `.claude/task-develop/` is not in the commit
- [ ] If the PR was declined, the user was told the branch is still local
- [ ] The babysitter got a real PR URL, or was not offered at all
