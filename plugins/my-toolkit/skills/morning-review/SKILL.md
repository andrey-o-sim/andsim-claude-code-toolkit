---
name: morning-review
description: Morning review - new CS tasks on the board and open PRs without my approval. Read-only, retries for 1 hour if VPN is off. Use when a Desktop scheduled task or the user asks for the morning review, a review of new board tasks and PRs waiting for approval, or calls morning-review with jql, repos and user arguments.
argument-hint: 'jql="<JQL>" repos="<repos>" user="<my-username>"'
allowed-tools: Bash(sleep:*), mcp__atlassian-jira-dc__jira_searchIssues, mcp__plugin_planet-mcp_atlassian-jira-dc__jira_searchIssues, mcp__atlassian-bitbucket-dc__bitbucket_getInboxPullRequests, mcp__atlassian-bitbucket-dc__bitbucket_getDashboardPullRequests, mcp__atlassian-bitbucket-dc__bitbucket_getPullRequests, mcp__atlassian-bitbucket-dc__bitbucket_getPullRequest, mcp__atlassian-bitbucket-dc__bitbucket_canMergePullRequest, mcp__atlassian-bitbucket-dc__bitbucket_getPullRequestBuilds
---

# Morning review

Made to run as a Desktop scheduled task, and also by hand. Read-only: never comment, approve, transition or change anything.

Example prompt for the scheduled task:

```text
/my-toolkit:morning-review jql="project = CS AND status = Open" repos="PROJ/repo-a,PROJ/repo-b" user="my.username"
```

## Arguments

Arguments: $ARGUMENTS

Read three named arguments. Values are in double quotes, because a JQL usually has spaces.

- `jql` — the board filter in JQL
- `repos` — Bitbucket repositories (`PROJECT/repo`) or a project key, comma-separated
- `user` — my Bitbucket username

If any argument is missing or empty, write "Review not done: missing argument <name>" and stop. Do not ask: a scheduled run has nobody to answer.

## Step 0. Access check (safeguard)

Make two light requests, one to each service:

- MCP atlassian-jira-dc: a search with `jql` and maxResults=1.
- MCP atlassian-bitbucket-dc: `bitbucket_getInboxPullRequests`.

If either service is not reachable (network error, timeout, VPN is off):

1. Run `sleep 600` in Bash with `run_in_background`, and check both services again when it finishes.
2. Make at most 6 attempts, which is about one hour.
3. If either service is still not reachable after 6 attempts, write "Review not done: Jira/Bitbucket are not reachable, VPN is probably off" and stop. Do not try anything else.

Never use a foreground `sleep`: it does not move to the background at the Bash timeout and is cut off.

## Step 1. CS tasks

Through MCP atlassian-jira-dc, search `(<jql>) AND created >= -1d`. On Monday use `-3d` instead of `-1d`: there is no run on the weekend, so tasks created on Friday, Saturday and Sunday must be included. If `jql` has an `ORDER BY` part, keep it at the end, after the added condition.

The tasks may be assigned to anyone, not only to me. Show all of them: key, title, priority, assignee (or "unassigned").

## Step 2. PRs without my approval

Through MCP atlassian-bitbucket-dc, find open PRs in `repos` where `user` is a reviewer and has not approved yet, and PRs that cannot be merged.

For each PR: link, author, days open, and why it cannot be merged (missing approvals, failed build, conflicts).

## Report

Two sections: "CS tasks" and "PRs". If a section is empty, write one line "nothing new".
