---
description: Watch a Bitbucket PR on an interval (default every 3 minutes) for new comments, build status and approvals until it is ready to merge or closed
argument-hint: "<PR URL> [interval, e.g. 3m, 10m, 1h; default 3m]"
allowed-tools: CronCreate, CronList, CronDelete, mcp__atlassian-bitbucket-dc__bitbucket_getPullRequest, mcp__atlassian-bitbucket-dc__bitbucket_getPR_CommentsAndAction, mcp__atlassian-bitbucket-dc__bitbucket_canMergePullRequest, mcp__atlassian-bitbucket-dc__bitbucket_getPullRequestBuilds
---

# PR watch

- PR: $1
- Interval: $2

If the PR URL is missing, ask for it and stop.

## Interval

If the interval is missing, use `3m`. Accept minutes (`Nm`, 1 to 59) or hours (`Nh`, 1 to 23), and turn it into a cron expression:

- minutes: `*/N * * * *`
- hours: `0 */N * * *`

Cron has one-minute granularity, so anything below 1 minute is not possible. If N does not divide 60 evenly for minutes, or 24 for hours, the gap at the end of each hour or day would be shorter. Round to the nearest value that divides evenly (for example `7m` becomes `6m`) and tell the user what you picked. If the value cannot be read, ask for it and stop.

## Start

Call `CronCreate` with the cron expression, recurring, and the check prompt below with the PR URL filled in. Then run the first check right now, without waiting for the first fire. Tell the user the job ID, the interval, and that `cancel the PR watch` stops it.

## Check prompt

```text
PR watch check for <PR URL>.
Use MCP atlassian-bitbucket-dc for the PR and MCP <jenkins-mcp> for the PR build.
1) New comments since the previous check: author, file, short summary. Do not fix anything without my reply.
2) Build status of the PR. If it failed: the failed step and the reason from the log, at most 5 lines.
3) Approvals, and whether anything blocks the merge.
If the PR is approved, the build is green and no comment is left without a reply: write "PR is ready to be merged", then find this job with CronList and cancel it with CronDelete.
If the PR is merged or declined: say so, then cancel this job the same way.
Otherwise answer with one line "PR: no changes" and wait for the next check.
Never merge, push or start a deploy yourself.
```

Rules for the whole watch:

- Read-only. Merge, push and deploy stay with the user.
- Keep a quiet check to one line: every fire sends the whole session context, so a short interval costs more.
- A fixed-interval job does not stop with `Esc`. It stops when the stop condition is met, when the user asks to cancel it, or after 7 days.
