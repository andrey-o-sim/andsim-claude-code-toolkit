---
description: Watch a deploy every 10 minutes (deploy job, e2e tests, errors in logs) until it is healthy for 30 minutes or fails
argument-hint: "<service> <env> <deploy-job> <e2e-job>"
allowed-tools: CronCreate, CronList, CronDelete, mcp__opensearch__SearchIndexTool, mcp__opensearch__CountTool, mcp__opensearch__ListIndexTool, mcp__opensearch__IndexMappingTool
---

# Deploy watch

- Service: $1
- Environment: $2
- Deploy job: $3
- E2E job: $4

If any of the four arguments is missing, ask for it and stop.

Start a recurring check: call `CronCreate` with cron `*/10 * * * *`, recurring, and the check prompt below with the arguments filled in. Then run the first check right now. Tell the user the job ID and that `cancel the deploy watch` stops it.

## Check prompt

```text
Deploy watch check for <service> in <env>.
1) Through MCP <jenkins-mcp>: status of the latest run of <deploy-job> — running, succeeded or failed. If failed: the step and the reason from the log, at most 5 lines.
2) Through MCP <jenkins-mcp>: the latest run of <e2e-job> after this deploy — how many tests failed and which ones (at most 10 names).
3) Through MCP opensearch: errors (level ERROR and above) of <service> in <env> since the deploy finished — the count and the 3 most frequent messages.
If the deploy succeeded, e2e is green and there are no new errors for 30 minutes after the deploy: write "Deploy OK", then find this job with CronList and cancel it with CronDelete.
If the deploy failed or e2e failed: write a short report and cancel this job the same way. The user decides what to do next.
If the deploy is still running: answer with one line "Deploy: in progress" and wait for the next check.
Never restart, roll back or change anything yourself.
```

Rules for the whole watch:

- Read-only. Restart, rollback and fixes stay with the user.
- The 30 minutes without new errors is an observation window: errors under real traffic often appear after the deploy turns green.
- A failure also stops the watch: the report is needed once, not every 10 minutes.
