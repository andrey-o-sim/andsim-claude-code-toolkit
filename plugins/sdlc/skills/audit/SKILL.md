---
name: audit
description: Audit the documentation trail behind a ticket. Checks the 9 SDLC artifacts — idea-brief, PRD, sad, adr/, data-model, openapi.yaml, api-sync-report, tasks/, CONTEXT — and reports which exist, which are missing, which are stubs, and which are stale because the code moved on without them. Ends with a ranked list of what to fix first. Read-only - it never writes or back-fills an artifact.
argument-hint: "[ticketNumber] [artifactsPath] — both optional. ticketNumber defaults to the id in the current branch; artifactsPath defaults to docs/implementation-artifacts"
disable-model-invocation: true
model: Opus
---

# SDLC artifact audit

This skill inspects the documentation trail behind a ticket. It is a read-only
audit: it reports status and recommends what to fix first. It never creates,
edits or back-fills an artifact, because an audit that quietly writes the thing
it was measuring stops being a measurement.

## Why this exists

A ticket's code outlives the people who wrote it. The artifact set is how the
next person — or the next agent session — recovers the reasoning without reading
every diff. A missing artifact is a gap in that chain. A **stale** artifact is
worse than a missing one: it reads as current and quietly describes a system
that no longer exists. The audit treats both as findings, and ranks stale ahead
of missing when the artifact is one the code is supposed to match.

## Arguments

Two positional arguments, both optional:

| Position | Name | Meaning | Default |
|---|---|---|---|
| 1 | `ticketNumber` | The tracker id to audit, e.g. `ABC-123` | The id in the current branch name |
| 2 | `artifactsPath` | Repo-relative directory holding the ticket's documents | `docs/implementation-artifacts` |

```
/sdlc-audit                               # both from defaults
/sdlc-audit ABC-123                       # explicit ticket, default path
/sdlc-audit ABC-123 docs/specs            # both explicit
```

Order matters only in that the ticket id comes first. If the user supplies one
value and it looks like a path rather than a tracker key, treat it as
`artifactsPath` and resolve the ticket from the branch. Both resolve as below,
and both pass straight through to the scan script in the same order.

## Resolving the ticket

The audit targets one ticket id.

1. Use the id the user gave (`/sdlc-audit <ticketNumber>`).
2. No id given → read the current branch: `git branch --show-current` and take
   the ticket id out of `feature/<ticketNumber>` or `fix/<ticketNumber>`. A
   ticket id is a tracker key: letters, then a hyphen, then digits
   (`[A-Z][A-Z0-9]*-[0-9]+`). Do not assume a particular project prefix.
3. Branch has no ticket id → ask which ticket, do not guess.

## Resolving the artifact root

The artifact root is the directory holding the ticket's documents.

1. Use the path the user gave.
2. Otherwise default to `docs/implementation-artifacts`.
3. If the user gave no path **and** that directory does not exist, **ask the
   user where the artifacts live**. Do not guess at a sibling, and do not
   create the directory — a wrong guess produces an audit of the wrong folder,
   which is worse than no audit.

Inside the root, projects file a ticket's documents one of two ways, and both
are normal: a subdirectory per ticket (`<root>/<ticketNumber>-artifacts/`), or
the files straight in the root, usually with the ticket id as a name prefix.
The script accepts both. `<BASE>` below means whichever one this ticket uses.

## The 9 artifacts

Paths are relative to the repo root.

| # | Artifact | Expected path | What it carries | Code it must stay in sync with |
|---|----------|---------------|-----------------|-------------------------------|
| 1 | **idea-brief** | `<BASE>/idea-brief.md` | The problem, who has it, why now, what is explicitly out of scope | — (point-in-time; never stale) |
| 2 | **PRD** | `<BASE>/PRD.md` | Product requirements and acceptance criteria — the behaviour the service promises | The request handlers, controllers and event handlers that implement the behaviour |
| 3 | **sad** | `<BASE>/sad.md` | Solution architecture: components, integrations, event flows, failure handling | The service source tree and its deployment/infrastructure config |
| 4 | **adr/** | `<BASE>/adr/*.md` | One file per decision: context, options, choice, consequences | The source tree and infrastructure config the decision governs |
| 5 | **data-model** | `<BASE>/data-model.md` | Entities, tables, columns, enum storage, indexes and the reason for each | The data access layer, migrations and entity definitions |
| 6 | **openapi.yaml** | `<BASE>/openapi.yaml` | The HTTP contract this ticket adds or changes | The API entry points — handlers, controllers, route definitions |
| 7 | **api-sync-report** | `<BASE>/api-sync-report.md` | Drift check: contract vs. the handlers and the generated API clients | Generated client code and the API entry points |
| 8 | **tasks/** | `<BASE>/tasks/Task*.md` | The implementation slices and their state | The source tree the slices touch |
| 9 | **CONTEXT** | `<BASE>/CONTEXT.md` | Domain vocabulary — the words the code uses and what each one means | Entity/domain type definitions and the service layer |

Known alternate paths are accepted and reported as `MISPLACED` — see the script
for the full alias list. The point is to avoid calling an artifact missing when
its content exists under a different name; that wastes the reader's time and
invites a duplicate.

### Mapping artifacts to code paths

The last column above is deliberately described in words, not paths. Which
directory holds the data access layer is a fact about one repository, and a
skill that hardcodes one project's layout is a skill that lies in every other
project.

Concrete paths are therefore optional configuration. A project that wants
per-artifact staleness creates `watch-paths.conf` beside this file:

```
# <key>  <comma-separated repo-relative paths>
PRD         src/Thing/Commands,src/Thing/EventHandling
data-model  src/Thing.Data,src/Thing.Data.Migrations
```

Keys are the ones in the table. Without the file the script compares each
artifact against a **repo-wide** code date — the last commit touching anything
outside the artifact root, markdown and agent config. That is coarser: any code
change can mark an artifact stale. Say so in the report when it applies, so a
reader does not mistake coarse for precise.

## Status criteria

| Status | Means |
|--------|-------|
| `PRESENT` | Exists at the expected path, has real content, and is at least as new as the code it covers |
| `EXTERNAL` | The content exists, but in another container — Jira, Confluence, GitHub Issues, Notion, Figma, a Slack thread — not as a file in this repo |
| `MISPLACED` | The content exists as a file, but not at the expected path |
| `STUB` | Exists but fewer than 5 lines survive stripping headings, blanks, bullets and TODO markers — a template, not an artifact |
| `STALE` | Exists, but the system it describes has moved on — by date, or by a divergence found while reading it |
| `MISSING` | Nothing at the expected path, any known alternate, or any other container. A directory artifact with no matching files counts as missing |
| `N/A` | Deliberately not produced, because the team decided this artifact does not apply here |
| `KNOWN` | A real gap the team has already seen and consciously deferred |

Five rules keep this honest:

- **Dates come from git, not from the filesystem.** `mtime` is rewritten by
  clone, checkout and formatting runs, so it would mark half the repo stale
  after a fresh clone. The script falls back to `mtime` only for an untracked
  file, and says so in the note.
- **Same commit means in sync.** When the artifact and the code changed in one
  commit the dates are equal, so the artifact is not stale. Documentation
  updated alongside its code is the behaviour we want, not a finding.
- **A well-written document can still be stale.** The status answers "is this
  still true?", never "is this well written?". An artifact with a clean
  structure, real reasoning and a documented decision is `STALE` the moment
  reading it turns up one thing the code no longer does. Quality belongs in the
  note; it must not soften the status. This is the easiest mistake to make,
  because a good document reads as a current document.
- **Reading outranks dates, in both directions.** A divergence found by reading
  makes an artifact `STALE` even when its commit date is newer than the code's.
  Equally, an artifact whose date is older is not stale if reading shows it
  still describes the system — say so in the note rather than flagging it.
- **The audit never assigns `N/A` or `KNOWN` by itself.** Both record a human
  decision, so both need a human to have stated it — in this conversation, in
  the ticket, or in the artifact set. Absent that, the status is `MISSING` and
  the decision is the user's to make. Once given, carry the reason in the note
  so the next run does not re-raise a settled question. An audit that reprints
  the same closed finding every time stops being read.

## Protocol

### 1. Scan

```bash
bash .claude/skills/sdlc-audit/scripts/scan-artifacts.sh <ticketNumber> [artifactsPath]
```

Pass both arguments through exactly as resolved above. Omit the second only
when the default root is the one being audited.

The script prints a short header (ticket, artifact root, ticket area, whether
per-artifact watch paths were configured) and then one TSV row per artifact:
`key, status, path, artifact_date, code_date, note`. Run it rather than
checking the paths by hand — the git date comparison is fiddly and a
hand-rolled version drifts from the criteria above between runs.

**Exit code 3 means the artifact root was not found.** Ask the user for the
path and re-run. Do not fall back to searching the repo, and do not create it.

If the script fails some other way (no bash, repo root not found), fall back to
`Glob` for the paths and `git log -1 --format=%cI -- <path>` for the dates, and
say in the report that you did so.

Read the artifacts that exist. Status alone cannot tell you whether a present
`data-model.md` actually covers the tables this ticket added — open it and
check. The script finds the files; your reading is what makes the audit worth
more than `ls`.

### 1b. Check the other containers — before calling anything MISSING

**The script reads files and nothing else.** It cannot see Jira, Confluence,
GitHub Issues, Notion, Figma or a Slack thread. So its `MISSING` rows are a
starting question, not an answer: they mean "not a file here", which is a
different claim from "does not exist".

Most teams keep requirements and decisions outside the repo. A run that reports
them missing is not a strict audit — it is a wrong one, and it buries the real
gaps under false ones.

So for every `MISSING` row, before it reaches the report:

1. Read the ticket — description, acceptance criteria, comments, and the fields
   that hold links (useful links, artifacts for review, related issues).
2. Follow its links out to the wiki and to related tickets. A ticket for
   implementation often has a separate earlier ticket holding the research,
   architecture and scope; the artifacts live there, not here.
3. Search the wiki by the feature's name when the ticket links nothing.

Found elsewhere → `EXTERNAL`, naming the container. Still nothing → `MISSING`
stands, and now it is a real finding.

Two cautions. Judge an external artifact by **reading** it, not by its title —
a page named like a decision record may not contain a decision, and one that
does may have drifted. And check its last-modified date against the code the
same way: `EXTERNAL` and `STALE` combine, and an outdated wiki page is the most
dangerous artifact in the set, because it is the one people still trust.

### 2. Report the status table

Use this exact shape, all 9 rows, in the table order above:

```markdown
## SDLC artifact audit — <ticketNumber>

Scanned `<artifact-root>` plus the ticket and its linked pages
<N> covered · <N> stale · <N> missing · <N> settled by decision

| # | Concept | Status | Container | Where it lives | Note |
|---|---|---|---|---|---|
| 1 | idea-brief | ❌ Missing | — | — | — |
| ... | | | | | |
```

**No date columns.** They were tried and removed: six of nine rows had nothing
to put in them, the two that mattered needed a sentence of explanation anyway,
and a column of mostly-dashes makes a report look thorough while saying little.
Dates now appear in the note, only where they carry an argument.

### Internal status → displayed label

The scan and your reasoning use the precise vocabulary from Status criteria.
The report shows a plainer label, because a reader wants "is this covered, and
where?" before they want a taxonomy:

| Internal | Displayed | Why |
|---|---|---|
| `PRESENT` | ✅ Covered | |
| `EXTERNAL` | ✅ Covered | The Container column already says it is not in the repo, so the status need not repeat it |
| `MISPLACED` | ✅ Covered | The content exists; the note says where it actually sits |
| `STUB` | 🧩 Stub | |
| `STALE` | ⚠️ Stale | Add `, split` or similar when the artifact is also spread across containers |
| `MISSING` | ❌ Missing | |
| `N/A` | ➖ Not needed | |
| `KNOWN` | 🕓 Deferred | |

Collapsing three internal statuses into "Covered" is deliberate, and it only
works because `Container` and `Note` carry what was collapsed. Drop either
column and the distinctions have to come back into the status.

**A `Stale` row must carry its evidence in the note** — the artifact's date
against the code's, or the divergence that reading turned up. Without it the
status is an assertion the reader cannot check, and "stale" is the one verdict
most likely to be argued with. Dates as `YYYY-MM-DD`; drop the time unless both
fall on the same day, where the hour is the whole argument.

**Container** names the system holding the artifact — the git repo, Jira,
Confluence, GitHub Issues, Notion, Figma, a Slack thread — and **Where it
lives** the path, page title or ticket field inside it. Name the product, not
your company's instance of it: write `Confluence`, not the hostname or the
internal nickname your team calls it by, so the report reads the same to
someone outside the team. Keep the two columns separate — the container is what
a reader needs in order to know where to look, and collapsing it into a path
hides that half the set lives outside the repo. Use `—` for both when the
status is `Missing` or `Not needed`.

Lead with the counts, not a bare `N/9 present`. A single number cannot carry a
set that mixes covered, stale, missing and settled-by-decision, and rounding
them into one figure is the kind of tidy summary that gets quoted later without
its caveats.

Keep the note short — one clause saying what is wrong, or what the reader needs
in order to trust the status.

### 2b. Record artifacts outside the 9

The 9 are a checklist, not the full set of what a team produces. A real feature
usually leaves behind documents the list has no row for — test cases, a
CHANGELOG, a plan, a runbook, a migration or rollout note.

List them under the table, with their container:

```markdown
### Additional artifacts found

- **Test cases** — tracker + temporary markdown in the repo
- **CHANGELOG** — generated, in the repo
```

Two reasons this matters. Ignoring them makes the audit read as though the team
documented less than it did, which is both unfair and inaccurate. And a
document that recurs across several audits is a candidate for the checklist
itself — the list should follow what teams actually write, not the other way
round.

Do not grade these. They have no expected path and no staleness rule, so the
audit can report that they exist and where, and nothing more.

### 3. Recommend, 3 to 5 lines

Pick the 3–5 most critical gaps and write one line each. Not a list of
everything missing — the table already says that. This section answers "if I
only fix a few things today, which ones?"

Rank by what the gap costs right now, not by the table order:

1. **Stale contract-shaped artifacts first** — `openapi.yaml`, `data-model`,
   `api-sync-report`. These claim to mirror the code. When they are wrong,
   someone builds against them and ships a bug.
2. **Then unrecorded decisions** — `adr/`, `sad`. The reasoning lives only in
   the heads of the people on the ticket and leaves with them. Every week this
   waits, the reconstruction gets more expensive.
3. **Then shared vocabulary** — `CONTEXT`. Cheap to write, and its absence
   makes every later review and every agent session slower.
4. **Last, recoverable-from-elsewhere** — `idea-brief`, `PRD`, `tasks/`. The
   tracker and the commit history still hold most of this.

A stub ranks with missing. A misplaced file ranks below everything else — the
content exists, only the path is wrong. An `EXTERNAL` artifact is not a gap at
all and never earns a line on its own; it earns one only when it is also stale.

**`N/A` and `KNOWN` rows never appear in the recommendations.** The team has
already decided; repeating the finding argues with a closed decision and trains
the reader to skim the section. The one exception is when the audit turned up
something that was not true when the decision was made — then say what is new,
in one sentence, and leave the decision to them.

Each line must name the artifact, the concrete cost, and the smallest next
action. A gap list without a cost gets skimmed and ignored.

```markdown
### Recommendations

1. **data-model.md is missing** — the status column is an int behind a filtered
   index, and nothing records why. Write the entity and index table before the
   next migration touches it.
2. **sad.md is missing** — the integration and event flows are only readable
   from the handlers. One page with the event flow would cut PR review time now.
3. ...
```

### 4. Stop

Report and stop. Do not create the missing artifacts, and do not offer a draft
unless the user asks. They may have decided a given artifact does not apply to
this ticket, and the audit's job is to make that decision visible, not to make
it for them.

If the user answers a finding — "we did not need that one", "that is known, it
is waiting" — record it as `N/A` or `KNOWN` with the reason, so the next run
opens from the settled position rather than re-litigating it. Record the answer
given; do not infer one from silence.

## When the artifact root does not exist

Say so plainly, show the path checked, and ask the user where the artifacts
live. If a plausible parent exists, list its subdirectories so the user can
spot a typo in the ticket id or the path. Do not create the directory.
