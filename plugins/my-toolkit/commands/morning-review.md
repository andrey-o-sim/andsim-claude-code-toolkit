---
description: Morning review - new CS tasks on the board and open PRs without my approval (read-only, retries for 1 hour if VPN is off)
argument-hint: ""
allowed-tools: Bash(sleep:*), mcp__atlassian-jira-dc__jira_searchIssues, mcp__plugin_planet-mcp_atlassian-jira-dc__jira_searchIssues, mcp__atlassian-bitbucket-dc__bitbucket_getInboxPullRequests, mcp__atlassian-bitbucket-dc__bitbucket_getDashboardPullRequests, mcp__atlassian-bitbucket-dc__bitbucket_getPullRequests, mcp__atlassian-bitbucket-dc__bitbucket_getPullRequest, mcp__atlassian-bitbucket-dc__bitbucket_canMergePullRequest, mcp__atlassian-bitbucket-dc__bitbucket_getPullRequestBuilds
---

# Morning review

Made to run as a Desktop scheduled task with the prompt `/morning-review`, and also by hand. Read-only: never comment, approve, transition or change anything.

## Config

Fill these in once:

- CS board filter (JQL): `<JQL>`
- Repositories or Bitbucket project: `<repos>`
- My Bitbucket username: `<my-username>`

## Step 0. Access check (safeguard)

Make one light request to MCP atlassian-jira-dc: a search with the JQL above and maxResults=1.

If the service is not reachable (network error, timeout, VPN is off):

1. Run `sleep 600` in Bash with `run_in_background`, and check again when it finishes.
2. Make at most 6 attempts, which is about one hour.
3. If the service is still not reachable after 6 attempts, write "Review not done: Jira/Bitbucket are not reachable, VPN is probably off" and stop. Do not try anything else.

Never use a foreground `sleep`: it does not move to the background at the Bash timeout and is cut off.

## Step 1. CS tasks

Through MCP atlassian-jira-dc, search: `<JQL> AND created >= -1d`.

The tasks may be assigned to anyone, not only to me. Show all of them: key, title, priority, assignee (or "unassigned").

## Step 2. PRs without my approval

Through MCP atlassian-bitbucket-dc, find open PRs in `<repos>` where `<my-username>` is a reviewer and has not approved yet, and PRs that cannot be merged.

For each PR: link, author, days open, and why it cannot be merged (missing approvals, failed build, conflicts).

## Report

Two sections: "CS tasks" and "PRs". If a section is empty, write one line "nothing new".
