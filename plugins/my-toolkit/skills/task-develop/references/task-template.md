# Task file template

Used at step 2 of `task-develop`, after the discussion in step 1. Write the result to
`docs/tasks/<TASK>.md`.

## What this file is for

It records **what was asked for and why**, before any code exists. Two different readers depend
on it:

- The planner at step 4 turns its acceptance criteria into tasks.
- The auditor at step 7 judges the finished code against those same criteria, word for word.

So the criteria have to be checkable sentences, and they have to stay fixed. This file is written
once, confirmed by the user, and then left alone for the rest of the run. If the work turns out to
need a different criterion, that is a conversation with the user, not a quiet edit.

It says nothing about *how*. No file names, no class names, no implementation steps - those belong
in the plan. A reader who knows nothing about the codebase should still understand what is being
asked for.

## Rules for the content

- **Only what the user agreed to.** Do not add a criterion because it seems sensible. An invented
  AC is work nobody asked for, and the audit at step 7 will enforce it anyway.
- **One criterion, one check.** If a sentence needs an "and" to hold two different outcomes, split
  it into two.
- **No criterion you cannot point a test at.** "Refunds work" is not checkable. "A refund larger
  than the original charge is rejected with a 422" is.
- **Out of scope is not optional.** An empty "Out of scope" section means the question was never
  asked. Ask it.
- Plain words, short sentences. The reader may be a person or a sub-agent with no other context.

---

## Template

````markdown
# <Title in plain words>

Status: draft
Created: <YYYY-MM-DD>
Repository: <repo name>

## Why

Two or three sentences. The problem this solves, and who has it. Not the solution.

## What should change

A short description of the wanted behaviour, in plain words. Enough that someone who has never
seen this code understands what is being asked for.

## Acceptance criteria

| ID | Criterion |
|----|-----------|
| AC-1 | ... |
| AC-2 | ... |

Each row is one checkable outcome. These sentences are copied verbatim into the plan and judged
verbatim after the work is done, so word them carefully now.

## Scope of work

What is included. List the areas of behaviour this task covers.

### Out of scope

What is deliberately excluded, plus anything nearby that a reader might reasonably assume is
included. This section is what stops the change growing past the task.

## Decisions taken

Answers from the discussion that the implementer must not reopen. One line each, with the reason.

- <decision> - <why>

## Open questions

Anything still undecided at the time of writing, and who needs to answer it. Empty is the normal
case - the discussion at step 1 exists to empty it.
````
