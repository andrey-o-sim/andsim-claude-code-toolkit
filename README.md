# andsim-claude-code-toolkit

A small Claude Code plugin marketplace built for the Agentic Engineering course.

## What this is

This repo is a **marketplace**: a catalog of Claude Code plugins that a team can install from one
place. Claude Code reads `.claude-plugin/marketplace.json`, shows the plugins listed there, and
installs the ones you pick.

Layout:

```
.claude-plugin/marketplace.json   catalog: marketplace name, owner, list of plugins
plugins/<plugin-name>/            one folder per plugin
  .claude-plugin/plugin.json      plugin manifest (name, version, description, author)
  commands/                       slash commands
  skills/                         skills
  hooks/hooks.json                hook definitions, plus the scripts they run
```

This is a learning repo. The plugins here are examples, not production tooling.

## How to add it to Claude Code

1. Add the marketplace:

   ```
   /plugin marketplace add <your-org>/andsim-claude-code-toolkit
   ```

   A local path works too, which is useful while you develop:

   ```
   /plugin marketplace add /path/to/andsim-claude-code-toolkit
   ```

2. Install a plugin from it:

   ```
   /plugin install my-toolkit@andsim-claude-code-toolkit
   ```

3. Restart Claude Code, or run `/plugin` to check the plugin is enabled.

4. To get later updates:

   ```
   /plugin marketplace update andsim-claude-code-toolkit
   ```

You can also browse everything interactively with `/plugin`.

## Plugin list

| Plugin | Version | What it gives you |
| --- | --- | --- |
| `my-toolkit` | 1.2.0 | Toolkits created in context of the Agentic Engineering course. Contains one command, two skills and one hook (see below). |

### `my-toolkit` contents

- **Command `/claude-audit`** — audits a project `CLAUDE.md` against 7 quality criteria and reports
  problems. Read-only: it verifies every claim against the real code and suggests fixes, but edits
  nothing. Takes an optional path, defaults to `./CLAUDE.md`.
- **Skill `task-develop`** — drives one task end to end, starting from a discussion. It works out
  with you what to build, writes it up as `docs/tasks/<name>.md` and waits for your yes, then plans
  with an Opus sub-agent, implements with a Sonnet agent, audits the result against the acceptance
  criteria, runs the PR reviewer, and hands over for human review. Pass a path to reuse a task file
  that already exists.
- **Skill `migration-sql-script`** — generates the forward and rollback SQL for a range of EF Core
  migrations in a .NET repo, and rewrites index creation to `CREATE INDEX CONCURRENTLY`. It shows
  the detected range and waits for a yes before running anything, and never applies SQL itself.
- **Hook `pre-commit`** — a `PreToolUse` hook on `git commit` that runs build, `dotnet format style`
  and the tests, and blocks the commit with the reason when a step fails. See below.

#### The `pre-commit` hook

One hook entry, one script, three steps in order: build → format → tests. The build runs once and
the steps after it use `--no-build`, which is why this is one hook and not several.

It works out the repo layout on its own: the first `*.slnx` or `*.sln` in the root, test projects by
their `Microsoft.NET.Test.Sdk` reference, and which of those need Docker by their `Testcontainers`
reference. To say it explicitly instead, put a fenced `precommit` block in the repo's `CLAUDE.md`:

````markdown
```precommit
solution:      MyApp.slnx
unit-tests:    tests/MyApp.Domain.UnitTests
               tests/MyApp.Application.UnitTests
needs-docker:  tests/MyApp.Integration.Tests
```
````

Every key is optional — anything you leave out is discovered. A path can be the `.csproj` or the
folder holding it. When no .NET layout can be found at all, the hook does nothing and lets the
commit through; it never blocks a commit because it failed to understand the repo.

Escape hatches for one commit:

```
PRECOMMIT_TESTS=unit git commit -m "..."     skip the tests that need Docker
PRECOMMIT_TESTS=none git commit -m "..."     skip the tests entirely
PRECOMMIT_TIMEOUT=600 git commit -m "..."    raise the per-step time limit (default 180s)
```

## Maintainers

| Name | Role | Contact |
| --- | --- | --- |
| Andrii Symonenko | Owner, maintainer of `my-toolkit` | see [Contacts](#contacts) |

The owner is also recorded in `.claude-plugin/marketplace.json`.

## How to contribute

1. Fork the repo and create a branch: `feature/<short-name>`.
2. Add or change a plugin:
   - New plugin → create `plugins/<plugin-name>/.claude-plugin/plugin.json` with `name`, `version`,
     `description`, `author`.
   - Put commands in `commands/`, skills in `skills/<skill-name>/SKILL.md`, agents in `agents/`.
   - Every command and skill needs frontmatter with a clear `description`. The description is how
     Claude decides when to use it — write it for triggering, not for marketing.
3. Register the plugin in `.claude-plugin/marketplace.json` under `plugins`. The entry needs at
   least `name` and `source` (for example `"source": "./plugins/my-toolkit"`).
4. Bump the plugin `version` when you change behaviour. Keep the version in `plugin.json` and in
   `marketplace.json` the same.
5. Test locally before you open a PR:
   - `/plugin marketplace add /path/to/this/repo`
   - `/plugin install <plugin>@andsim-claude-code-toolkit`
   - run the command or skill at least once and check it does what the description says.
6. Open a pull request. In the description say what you added, why, and how you tested it.

CI runs `.github/workflows/validate-plugins.yml` on every pull request:

- `marketplace-validate` — checks `.claude-plugin/marketplace.json` with
  `claude plugin validate . --strict` and builds the plugin matrix from `plugins/`.
- `plugin-validate` — one matrix leg per plugin: `claude plugin validate ./plugins/<name> --strict`,
  plus a check that the version in `plugin.json` matches the marketplace entry.
- `smoke-install` — adds the marketplace from the checkout, installs every plugin, and starts one
  real session with `claude --print`. This job needs the `ANTHROPIC_API_KEY` secret.

You can run the same checks locally:

```
claude plugin validate . --strict
claude plugin validate ./plugins/my-toolkit --strict
```

Rules of thumb:

- One plugin = one clear job. Do not put unrelated commands in the same plugin.
- Keep `allowed-tools` as narrow as the task allows.
- Use `${CLAUDE_PLUGIN_ROOT}` for paths inside a plugin — never hardcoded absolute paths.
- Do not commit secrets, tokens, or `.env` files.

## Contacts

- Questions, bugs, ideas → open a GitHub issue in this repo.
- Owner: Andrii Symonenko — email listed in `.claude-plugin/marketplace.json`.
- Course discussion: use the Agentic Engineering course channel.
