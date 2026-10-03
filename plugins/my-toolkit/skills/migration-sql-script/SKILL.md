---
name: migration-sql-script
description: Generate the SQL migration script from EF Core migrations in a .NET service repo, plus the matching rollback script. Use this whenever the user asks to generate a migration script, get the SQL for a migration, produce a deploy or release script for database changes, or asks for the rollback/down SQL — and also on short phrasings like "migration sql", "script the migrations", "sql for the db changes", or "what sql goes to ops", even when they name no migration, no project, and no range. Reads the repo's CLAUDE.md to locate the migrations project, and falls back to the project that references Npgsql.EntityFrameworkCore.PostgreSQL.
argument-hint: "[from-migration-id] [to-migration-id] [project] — all optional, defaults to the range this branch adds on top of the base branch"
---

# Migration SQL script

## What this is for

The migration script is SQL that a human runs against a real database, often
production. Generating it is one command. What actually matters is picking the right
`<from>` and `<to>`: too narrow and a table is missing after deploy, too wide and the
script fails halfway on objects that already exist.

So the shape of this work is: detect carefully, show the user what you detected, wait
for a yes, then run.

`dotnet ef migrations script` only reads the code in the repo. It does not connect to
a database and it changes nothing. Applying the result does — that is the user's job,
never yours.

## The command

```bash
dotnet ef migrations script <from> <to> --project <migrations-project>
```

Step 1 finds `<migrations-project>`, step 2 finds the two IDs. Never hardcode them.

That is the whole command in most repos. Some repos need extra arguments after a `--`
separator, which EF passes on to the app that builds the DbContext:

```bash
dotnet ef migrations script <from> <to> \
  --project <migrations-project> \
  -- <design-time-args>
```

Step 1c decides whether this repo needs them and step 3 fills them in. Do not add a
`--` part on a guess — a wrong argument produces a worse error than a missing one.

Run from the repo root. Paths inside the design-time arguments are usually relative to
the migrations project folder, not to where you are standing, so moving around breaks
them. Always `cd` to the root first.

## Arguments

Everything is optional — the common case is no arguments at all, and the skill works
the range out from git.

- Two migration IDs: treat them as `<from>` and `<to>` in that order and skip the git
  detection.
- One migration ID: treat it as `<to>` and infer `<from>`. Say which one you inferred,
  because a single ID is ambiguous and the user may have meant the other end.
- A project name or path: use it instead of searching in step 1.

Anything you cannot make sense of, ask about rather than guess. A wrong range is worse
than one extra question.

## Step 1 — Find the migrations project

Start at the repo root:

```bash
cd "$(git rev-parse --show-toplevel)"
```

### 1a — Read CLAUDE.md first

Look for a project structure section in the repo's `CLAUDE.md`:

```bash
ls CLAUDE.md .claude/CLAUDE.md */CLAUDE.md 2>/dev/null
```

If it names the migrations project, or the arguments its design-time factory needs,
use what it says. The people who own the repo wrote it, so it beats anything you
infer.

Confirm it is still true before relying on it — the folder must exist and hold
migration files:

```bash
find <migrations-project> -name '*.cs' ! -name '*.Designer.cs' \
  | grep -cE '/[0-9]{14}_[^/]*\.cs$'
```

- Non-zero count: that is `<migrations-project>`. Go to 1c.
- Zero, or CLAUDE.md says nothing about structure: go to 1b.
- CLAUDE.md points at a path that does not exist: tell the user the docs are stale,
  then go to 1b.

### 1b — Fallback: find the project by its PostgreSQL package

EF Core migrations against PostgreSQL need `Npgsql.EntityFrameworkCore.PostgreSQL`,
so the project that holds them references it.

```bash
grep -rl --include='*.csproj' 'Npgsql.EntityFrameworkCore.PostgreSQL' .
```

A package reference alone does not settle it — the DbContext often lives in one
project while the migrations live in another. Count the migration files under each
candidate and let the count decide:

```bash
for proj in $(grep -rl --include='*.csproj' 'Npgsql.EntityFrameworkCore.PostgreSQL' .); do
  dir=$(dirname "$proj")
  n=$(find "$dir" -name '*.cs' ! -name '*.Designer.cs' \
        | grep -cE '/[0-9]{14}_[^/]*\.cs$')
  echo "$n  $dir"
done
```

- Exactly one candidate with a non-zero count: use it as `<migrations-project>`.
- Several: list the paths with their counts and ask which one. Do not pick for the
  user — a monorepo with two services has two different databases.
- All zero, or no `.csproj` references the package: stop. Either this repo has no EF
  Core migrations, or it uses a different database provider. Say which of the two you
  saw. A different provider also means step 6 does not apply, because `CONCURRENTLY`
  is PostgreSQL syntax.

With central package management the version sits in `Directory.Packages.props`, but
`PackageReference Include="..."` is still in the `.csproj`, so the search works.

### Raise a red flag whenever 1b was used

Print this to the user, even when the search found one obvious answer:

```
🚩 RED FLAG — CLAUDE.md does not describe the project structure.

I had to guess the migrations project by searching for the
Npgsql.EntityFrameworkCore.PostgreSQL package reference:

  src/Billing.Data/

Guessing is fragile — it breaks as soon as a second project
references the package. Please add a project structure section to
CLAUDE.md naming the migrations project and any arguments its
design-time factory needs.
```

The point is not this run, which you can finish anyway. It is that without the
section every future run guesses again.

### 1c — Does this project need design-time arguments?

The default is no. `--project <migrations-project>` on its own is the normal EF
command, and most repos configure the DbContext from `appsettings.json` or a factory
that takes no arguments.

Two things say otherwise:

- **CLAUDE.md documents them.** Use what it says.
- **The project has a design-time factory that reads `args`.** Find it:

  ```bash
  grep -rln 'IDesignTimeDbContextFactory' --include='*.cs' <migrations-project>
  ```

  Read that file. It shows exactly what the arguments are and in what order — often a
  config file path and a database name, but do not assume that shape. The code is the
  specification; nothing else is.

If a factory exists and reads `args`, go to step 3 to find the values. Otherwise skip
step 3 and run without a `--` part.

Unsure? Run without the `--` part first. EF's error names what is missing, which is a
faster answer than guessing, and nothing was changed by trying.

## Step 2 — Work out `<from>` and `<to>`

If the user gave you both, use them and skip to step 3. If they gave only one, infer
the other the same way and say which one you inferred. Otherwise the default range is
**everything this branch adds on top of the base branch**: `<from>` is the newest
migration that already exists on the base branch, `<to>` is the newest migration in
the working tree.

Find the base branch:

```bash
BASE=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD)
```

If that is empty, try `origin/master`, then `origin/main`, then the local `master` or
`main`. If `origin` may be stale, `git fetch origin` first — it is read-only.

Newest migration on the base branch (this is `<from>`):

```bash
git ls-tree -r --name-only "$BASE" -- <migrations-project> \
  | grep -E '/[0-9]{14}_[^/]*\.cs$' | grep -v '\.Designer\.cs$' \
  | sed 's#.*/##; s#\.cs$##' | sort | tail -1
```

Newest migration in the working tree (this is `<to>`):

```bash
find <migrations-project> -name '*.cs' ! -name '*.Designer.cs' \
  | grep -E '/[0-9]{14}_[^/]*\.cs$' \
  | sed 's#.*/##; s#\.cs$##' | sort | tail -1
```

Drop `tail -1` to see the whole ordered list — you need it anyway to show the
migrations in between and to run the interleaving check below. The 14-digit timestamp
prefix sorts chronologically as plain text, so the last line is the newest.

`find` rather than `git ls-files`, because a migration the user just scaffolded is
often still untracked, and that is exactly the one they want scripted.

Use the **full migration ID** — the file name without `.cs`, timestamp included, like
`20260814120000_AddInvoiceIndex`. Bare names work in EF only while they are unique,
and two branches that both added `AddIndex` will bite later.

### Two situations worth stopping for

**No new migrations.** `<from>` equals `<to>`. The branch adds nothing, so there is no
range to script. Say that plainly, list the recent migrations, and ask which `<from>`
and `<to>` they want — they may be scripting an older release rather than their own
branch.

**Interleaved timestamps.** If any migration that is in the working tree but not on
the base branch has a timestamp *older* than `<from>`, the range silently skips it.
This means the base branch moved on and the branch was not rebased. Warn clearly, name
the skipped migrations, and recommend merging or rebasing the base branch and
re-running. Generating a quietly incomplete script is the worst outcome this skill can
produce.

## Step 3 — Fill in the design-time arguments

Skip this step unless step 1c found a factory that reads `args`.

The factory you read in 1c says what each argument is. Work them out one at a time, in
the order the factory expects:

- **A config file path.** It is relative to the migrations project folder. CLAUDE.md
  may name it; otherwise search for the shape the factory reads, for example
  `ls services/*/*.config.json` or `ls **/appsettings*.json`. Report the real names you
  found rather than guessing at a path.
- **A database or context name.** Read it out of that config file. It is often the
  project name plus `Db`, but the config is what the app actually reads, so it wins. If
  several entries look plausible, show the names and ask.

If any argument stays unclear after reading the factory, ask the user. One question
costs less than an EF error nobody can read.

Read config files, do not print them. They often carry connection strings or
credentials, and you need one identifier out of them — so quote only that identifier.
If a file turns out to hold plaintext secrets, mention it to the user as a heads-up and
move on.

## Step 4 — Show the plan and wait

Print this before running anything, then stop and wait for a yes:

```
Migrations project:  src/Billing.Data/        (from CLAUDE.md)
Base branch:         origin/master
Design-time args:    Billing.config.json, BillingDb
                     (BillingDbContextFactory reads config path, then database)

  on base:   20260814120000_AddInvoiceIndex   <- from
  new here:  20260902093000_AddRefundTable
             20260915140000_AddRefundStatus   <- to

Forward:
  dotnet ef migrations script 20260814120000_AddInvoiceIndex 20260915140000_AddRefundStatus \
    --project src/Billing.Data \
    -- ../../services/Billing.Service/Billing.config.json BillingDb

Rollback:
  dotnet ef migrations script 20260915140000_AddRefundStatus 20260814120000_AddInvoiceIndex \
    --project src/Billing.Data \
    -- ../../services/Billing.Service/Billing.config.json BillingDb

Run these?
```

The confirmation is the point of the whole skill. The user knows which release this is
for and you do not, so give them everything they need to spot a wrong range in one
glance: the two IDs, the migrations in between, and the exact commands.

Always say where the project came from — `(from CLAUDE.md)` or
`(guessed by Npgsql reference)`. The example above is a repo that needs design-time
arguments; when step 1c found no factory, print
`Design-time args: none` and show the plain `--project` command.

## Step 5 — Run both

Forward first, then rollback with the two IDs swapped. Same project, same design-time
arguments — only the order of the two IDs changes.

If the forward script fails, stop and report. Do not run the rollback to "see if that
works" — the same problem produces the same failure, and a second wall of errors helps
nobody.

## Step 6 — Make index creation concurrent

Every `CREATE INDEX` and `CREATE UNIQUE INDEX` in the generated SQL becomes
`CREATE INDEX CONCURRENTLY`. Do this to both scripts before showing them.

```sql
-- EF generates
CREATE INDEX "IX_refunds_status" ON refunds ("status");

-- the script must say
CREATE INDEX CONCURRENTLY "IX_refunds_status" ON refunds ("status");
```

`CONCURRENTLY` goes right after `INDEX`, before any `IF NOT EXISTS` and before the
index name.

### Why this matters

A plain `CREATE INDEX` holds a lock that blocks writes to the table until the index is
built. On a large table that runs long enough to hit the database timeout, and the
statement fails. The script is applied statement by statement with no transaction
around the whole thing, so everything before that point is already committed: the
migration is half applied, with no automatic way back.

`CONCURRENTLY` builds the index without blocking writes. EF Core has no setting for
it, so the rewrite belongs here rather than in the migration code.

### It cannot run inside a transaction

PostgreSQL rejects `CREATE INDEX CONCURRENTLY` inside a transaction block outright.
Check the script for `START TRANSACTION` / `BEGIN` … `COMMIT`. If an index statement
sits inside one, move it after the matching `COMMIT`. If there is no transaction
wrapper, leave it in place.

### What to leave alone

- **`ALTER TABLE … ADD CONSTRAINT … PRIMARY KEY` or `… UNIQUE`.** These build an index
  too, but there is no concurrent form. Do not rewrite them. Say in your summary that
  this one still takes a blocking lock, so the user can decide whether to split it out
  by hand.
- **An index on a table created in the same script.** The table is new and empty, so
  there is nothing to lock. Leave it as EF wrote it and keep the diff small.
- **Non-PostgreSQL output.** `CONCURRENTLY` is PostgreSQL syntax. If the script is SQL
  Server or anything else, skip this step and say why — the equivalent there is
  `WITH (ONLINE = ON)`, which is a different decision.

### Say what you changed

You are handing over SQL that is no longer byte-for-byte what `dotnet ef` printed.
List the index statements you rewrote and any you moved out of a transaction block, so
nobody is surprised when the file does not match a regenerated one.

Two things worth putting in the script itself:

- A failed `CONCURRENTLY` build leaves an invalid index behind. It has to be dropped
  before the statement can be retried.
- The rollback script drops these indexes. `DROP INDEX CONCURRENTLY` exists and
  follows the same no-transaction rule. Offer it and let the user choose — dropping an
  index is fast, so it is less often a problem.

## Step 7 — Present the result

Print both scripts in the chat in full, forward first, each in a `sql` fenced block
with a one-line summary above it, for example "3 migrations, adds `refunds` table and
`status` column". Do not write files unless asked — being able to read the SQL is the
reason it goes to the chat.

If a script is thousands of lines and would swamp the conversation, say so, show the
summary and the first part, and offer `--output` to a file instead.

Point out anything else that deserves a second look before someone runs it on a live
database: a `DROP`, a column type change, a `NOT NULL` added to an existing table.
Indexes are already covered by step 6. You are not blocking anything, just making sure
it is not a surprise at 3am.

## When it fails

- **`Unable to create an object of type '...DbContext'`** — three common causes, in
  the order worth checking. The working directory is wrong, so a relative path in the
  design-time arguments does not resolve: confirm you are at the repo root. The
  arguments themselves are wrong or missing: re-read the factory from 1c. Or the
  DbContext is built by a different project, which is likely when you found the
  project through 1b: try `--startup-project <path>` pointing at the service or API
  project.
- **`The migration '...' was not found`** — wrong ID. List the real ones with the same
  arguments you built in step 1:
  `dotnet ef migrations list --project <migrations-project>`
- **Build errors** — EF builds the project first. Fix the build, or report it; there is
  no script to generate from code that does not compile.
- **`dotnet ef` not found** — `dotnet tool install --global dotnet-ef`, or
  `dotnet tool restore` if the repo pins it in `.config/dotnet-tools.json`.

## Limits

Stay inside script generation. Do not run `dotnet ef database update`, do not apply SQL
to any database, and do not put a connection string, password, or key into a command
line. This skill produces text for a human to review and run; that review step is the
safety mechanism, so leave it in place.
