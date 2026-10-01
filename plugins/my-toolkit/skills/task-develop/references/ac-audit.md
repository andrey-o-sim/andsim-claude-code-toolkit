# Acceptance criteria audit

The brief for the step 7 sub-agent, and the format of the findings file.

## Why a separate agent

The implementer just spent a long run convincing itself the work is done. Asking it whether the
work meets the criteria gets you the same conviction back. A fresh agent that has never seen the
implementation reasoning reads the diff as a reviewer would.

Use Opus. This is a judgement call, not a mechanical check.

## What to pass it

The sub-agent starts with no context. Give it:

- Path to `.claude/task-develop/<TICKET>/plan.md`
- The Acceptance Criteria table, verbatim
- The diff: `git diff <target-branch>...HEAD`
- The repo path and the test commands from the plan's Verification section

## What it must do

Judge the **code and the tests**, never the plan's claims. A plan row saying "AC-3 satisfied" is a
statement of intent from before the code existed. The question is what the code does now.

For each criterion, one of three verdicts:

- **met** - name the file and line that delivers it, and the test that proves it
- **not met** - say what the criterion asks for and what the code does instead
- **unclear** - the criterion cannot be checked as written. Say why. This is a real verdict, not
  a way to avoid deciding, and it usually means the criterion was too vague to implement against.

Two checks beyond the table:

- **Untested behaviour.** New logic with no test covering it is a finding, even when the
  criterion is met. The plan promised tests in the same change.
- **Work beyond the criteria.** Code that no AC asked for and the Scope of Work does not cover.
  Scope growth is easier to remove now than after review.

The auditor reports. It does not fix anything - fixing is the caller's job, so the judgement and
the change stay separate.

## Findings file

Write to `.claude/task-develop/<TICKET>/ac-audit.md`. Append each round rather than overwriting,
so the history of what was found and fixed stays readable.

```markdown
# <TICKET> - AC audit

## Round 1 - <date>

| AC | Verdict | Evidence |
|----|---------|----------|
| AC-1 | met | `src/Foo.cs:42`, covered by `FooTests.Creates_Bar` |
| AC-2 | not met | Criterion asks for a 409 on a duplicate name; the endpoint returns 500 |

### Findings

1. **AC-2 returns the wrong status.** `src/Endpoints/Accounts.cs:31` lets the unique-constraint
   exception escape. Expected 409.
   - Fixed in round 2 / Open

### Untested behaviour

- `AccountBalance.Recalculate` has no test.

### Beyond scope

- none

## PrReviewer disputes

Findings from step 8 that were not fixed, with the reasoning. Step 12 replies to the same
comments on the PR and needs this.

| Finding | Why not fixed |
|---------|---------------|
| ... | ... |
```
