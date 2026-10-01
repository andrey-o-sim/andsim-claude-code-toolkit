# Plan template

Pass this to the Opus planner at step 4. The plan it returns must have every section below, in
this order.

Two sections carry more weight than the rest:

- `## Acceptance Criteria` holds the criteria **verbatim**. Every later step traces back to this
  table. A paraphrase here moves the goalposts without anyone deciding to.
- `## Post-approval workflow` is what keeps the run alive. Accepting the plan clears the
  conversation, so the skill's instructions disappear. This section is the only copy of steps 6-12
  that survives. It also carries the `### Progress` checklist, which is ticked in the plan file as
  the work goes - that is what lets an interrupted run resume in a new session instead of starting
  over. Copy the section exactly as written at the bottom of this file, substituting the ticket
  key. Do not summarise it, do not shorten it.

---

## Template

````markdown
# <TICKET>: <ticket summary>

Jira: <ticket URL>
Repository: <repo name and local path>
Target branch: <branch this merges into>

## Task Summary

Two or three sentences. What the change does and why it is wanted. Written so someone who has not
read the ticket can follow the rest of the plan.

## Acceptance Criteria

| ID | Criterion (verbatim from the ticket) | Delivered by |
|----|--------------------------------------|--------------|
| AC-1 | ... | Task 1, Task 3 |
| AC-2 | ... | Task 2 |

Every AC must name at least one task. An AC with no task is a hole in the plan - say so out loud
rather than leaving the cell empty.

## Scope of Work

Copied from the ticket's Scope of Work section.

### Out of scope

What the ticket deliberately excludes, plus anything nearby that a reader might assume is
included. Being explicit here is what stops the change growing past the ticket.

## Decisions taken

Answers from the question round, and anything the planner settled on its own. One line each,
with the reason. This exists so the implementer does not reopen a settled question, and so a
reviewer can see what was chosen rather than guessing.

## Implementation tasks

Ordered. Each task:

**Task N - <short name>**
- Files: the paths to create or change
- Change: what happens, concretely enough to act on without re-deriving the design
- Satisfies: AC ids, or `none` for pure groundwork
- Done when: a check someone else could run

## Test Plan

| Test | Layer | Covers | Why this layer |
|------|-------|--------|----------------|
| ... | unit / integration / e2e | AC-1 | ... |

Every AC needs at least one test row, or an explicit line saying why it cannot be tested
automatically. Tests are written in the same change as the code, not afterwards.

## Verification

The exact commands that prove the change works, taken from the repo's own `CLAUDE.md` or build
scripts - not invented. Build, then tests, then anything manual.

## Risks

Things that could go wrong, and what to do about each. Migrations, contract changes, anything
touching data. Skip the section if there is nothing real to say - padding here hides the one risk
that mattered.

## Post-approval workflow

<copy the block below verbatim>
````

---

## The Post-approval workflow block

Copy this into the plan exactly, replacing `<TICKET>` with the ticket key. It is written as
instructions to whoever reads the plan after the context clear, because that reader will have
nothing else.

````markdown
## Post-approval workflow

This plan is the only thing that survived the context clear. Working files live in
`.claude/task-develop/<TICKET>/`.

### Progress

- [ ] Step 6 - implement (Sonnet agent)
- [ ] Step 7 - AC audit (fresh Opus agent)
- [ ] Step 8 - PrReviewer
- [ ] Step 9 - hand over for human review
- [ ] Step 10 - offer commit
- [ ] Step 11 - offer PR
- [ ] Step 12 - offer PrReviewer Babysitter

Tick a box **in this file** the moment that step's `Done when` is satisfied. Not at the end, not
in batch. A run can stop at any point - the context fills up, the session is closed, the context
is cleared again - and when that happens this list is the only record of how far the work got.
Ticking late is the same as not ticking at all.

If a step is half done, leave its box empty and write one line under it saying where it stopped
and what is left. An empty box with no note means "never started", and the next session will redo
finished work.

**Resuming in a fresh session.** Do not start at the top. Find the first unticked box and start
there. Before editing anything:

- Read `ac-audit.md` in the same folder - earlier rounds may have already found and fixed things
- Run `git status` and `git log` - a previous session may have committed, or left work in the tree
- Check which branch you are on before assuming a new one is needed

Mirror this list into `TodoWrite` as well, so the user can watch progress live. The file is the
source of truth; the todo list is only a view of it and disappears with the session.

**Step 6 - Implement.** If the current branch is the repo's default branch, first run
`Skill(skill: "corp-dev:create-branch")`. Then spawn one implementer:
`Agent(subagent_type: "general-purpose", model: "sonnet", ...)`. Tell it to read
`.claude/task-develop/<TICKET>/plan.md` in full, follow the repo's `CLAUDE.md` conventions, write
the tests in the Test Plan as part of the same change, and run the Verification commands. It must
report the real build and test output. A failing suite reported as passing wastes every step
after this one.

Done when: not on the default branch; the implementer read the plan in full; the Test Plan tests
exist in the same change; build and test output reported as it actually was.

**Step 7 - Audit against the AC.** Spawn a fresh `Agent(model: "opus", ...)` - not the
implementer, which is a poor judge of its own work. Give it the plan path, the Acceptance Criteria
table, and `git diff` against the target branch. It checks the code and tests against each
criterion, and returns `AC-n: met | not met | unclear` with evidence. Write findings to
`.claude/task-develop/<TICKET>/ac-audit.md`, fix them, then re-run the audit to confirm. After 3
rounds with findings still open, stop and hand them to the user - that means the plan is wrong,
not the code.

Done when: the auditor was a fresh agent; every `AC-n` has a verdict backed by a file and a test,
not by the plan's claim; findings written and fixed; the audit re-run afterwards.

**Step 8 - PrReviewer.** Run `Skill(skill: "corp-dev:PrReviewer")` on the local changes. Fix every
valid finding. For a finding you dispute, record it and your reasoning in
`ac-audit.md` - the PR reply at step 12 needs it. If PrReviewer is unavailable here, say so and move
on rather than claiming a review happened.

Done when: PrReviewer ran or its absence was stated plainly; every valid finding fixed; every disputed
finding recorded with reasoning.

**Step 9 - Human review.** Report: what changed, the real build and test output, each `AC-n` met
or not, PrReviewer findings fixed and disputed, anything left out and why, and the working files under
`.claude/task-develop/<TICKET>/`. Then stop and wait. If the user comments, address the comments
and **return to step 7** - a fix made at review time is exactly the kind of change that quietly
breaks an AC.

Done when: all six points reported including what was left out; anything that failed reported as
failed; stopped and waited instead of rolling on into a commit.

**Steps 10-12 - Offer one at a time.** Ask, wait, and take "no" as the end of the run.

| Step | Offer | How |
|------|-------|-----|
| 10 | Commit | `Skill(skill: "corp-dev:create-commit")` |
| 11 | Open a PR | `Skill(skill: "corp-dev:create-pr")` - pushes the branch itself |
| 12 | Babysit PrReviewer | `Skill(skill: "corp-dev:babysit-PrReviewer-pr")` with the PR URL |

There is no separate push step - `create-pr` pushes the branch as part of its own work. If the
user commits but declines the PR, the branch stays local; say so, or they may assume it is on the
remote. Step 12 needs the PR URL from step 11; with no PR there is nothing to babysit.

Do not stage `.claude/task-develop/` in the commit - those are working files, not the change.

Done when: each offer was made on its own and a "no" ended the run; the working files are not in
the commit; the user was told if the branch is still local; the babysitter got a real PR URL or
was not offered at all.
````
