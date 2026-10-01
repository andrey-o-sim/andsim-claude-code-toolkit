---
description: Audit the project CLAUDE.md against 7 quality criteria and report problems
argument-hint: "[path to CLAUDE.md, default: ./CLAUDE.md]"
allowed-tools: Read, Glob, Grep, Bash(git ls-files:*), Bash(wc:*)
---

# Audit CLAUDE.md

Audit the file `$ARGUMENTS`. If no argument is given, audit `./CLAUDE.md` in the project root.

This is a read-only audit. Do not edit any file. Report findings and suggest fixes only.

## Steps

1. Read the target CLAUDE.md completely. Count its lines.
2. Read the files it points to (for example `ARCHITECTURE.md`, `SPEC.md`, `docs/adr/`), but only to check for duplicates and contradictions.
3. Check every claim against the real code. Use Glob, Grep, and Read. Do not trust the text — verify it.
4. Score each of the 7 criteria below. Collect concrete findings with evidence.
5. Write the report in the format at the end.

## Criteria

### 1. Commands are really needed

- Every listed command (build, test, run, migrate, lint, etc.) must exist and work in this repo.
- Check scripts, task runners, `package.json` scripts, `Makefile`, `build.sh`, `*.csproj`, etc.
- Flag commands that do not exist, have wrong names, or wrong arguments.
- Flag commands that Claude will never need (rare, manual-only, or obvious ones like `git status`).
- Flag important commands that are missing (for example, how to run one test or one test project).

### 2. Architecture is up to date

- Compare the described layout, folders, projects, and layers with the real file tree.
- Flag folders or projects that are described but do not exist.
- Flag important folders or projects that exist but are not described.
- Check described dependency rules against real references (for example `ProjectReference`, imports).
- Flag items marked "not started" / "planned" that already exist, and the opposite.

### 3. Patterns are specific (can be checked in the code)

- Every convention must be concrete enough to verify in the code. Example of good: "Enums are stored as strings via `.HasConversion<string>()`". Example of bad: "Use a consistent style".
- For each specific rule, spot-check the code: does the code follow it? Give 1–2 file examples.
- Flag rules that the code clearly breaks. Say which is wrong: the code or the rule.
- Flag rules that are too vague to check.

### 4. Conciseness

- The file must be under 200 lines. Report the exact line count.
- Flag duplicates inside the file (the same rule said twice in different words).
- Flag duplicates with other docs it references (for example the same text copied from `ARCHITECTURE.md`). Suggest a link instead.
- Flag long explanations that can be shortened without losing information.
- Flag content that belongs in another document (ADR, README, `ARCHITECTURE.md`). Rules and skills are covered in criterion 7.

### 5. Up to date (no outdated tools)

- Every tool, library, framework, and version named in the file must match what the project really uses.
- Check package manifests: `*.csproj`, `Directory.Build.props`, `Directory.Packages.props`, `package.json`, lock files, etc.
- Flag wrong versions (for example ".NET 8" when the projects target `net10.0`).
- Flag tools that are mentioned but not installed, and main tools that are used but not mentioned.

### 6. Practical (no generic advice)

- Every line must change Claude's behavior in this specific project.
- Flag generic advice that any model already follows, for example "write clean code", "follow best practices", "write good tests", "use meaningful names".
- Flag rules with no clear action.
- For each flagged line, suggest a concrete replacement or suggest deleting it.

### 7. Can be moved to project rules or skills

CLAUDE.md is loaded into every task. Instructions that are needed only sometimes waste context there.

- First, list what already exists in `.claude/rules/` and `.claude/skills/`. Do not suggest a file that already exists. Flag CLAUDE.md text that duplicates them.
- **Move to a rule** (`.claude/rules/<topic>.md` with `paths:` frontmatter): instructions that apply only to some files or folders. Example: database conventions → `paths: src/**/Persistence/**`. Test conventions → `paths: tests/**`. A rule loads only when Claude works with matching files.
- **Move to a skill** (`.claude/skills/<name>/SKILL.md`): a step-by-step procedure for a task that happens sometimes. Example: "add an EF Core migration", "add a new endpoint", "release a version". A skill loads only when the task needs it.
- **Keep in CLAUDE.md**: facts that are needed in almost every task. For example: layout, dependency rules, main commands, global rules.
- For each candidate, give: the line range, the target (rule or skill), the proposed file path, the `paths:` pattern or the skill description, and what stays in CLAUDE.md (usually nothing, or a one-line pointer).

## Report format

Write the report in this format:

```
# CLAUDE.md audit: <path>

Lines: <N> / 200

| # | Criterion         | Score (1–5) | Findings |
|---|-------------------|-------------|----------|
| 1 | Commands          |             |          |
| 2 | Architecture      |             |          |
| 3 | Specific patterns |             |          |
| 4 | Conciseness       |             |          |
| 5 | Up to date        |             |          |
| 6 | Practical         |             |          |
| 7 | Rules / skills    |             |          |

## Findings

### <Criterion name>
- **[severity]** <problem> — `CLAUDE.md:<line>`
  - Evidence: <file path, grep result, or what is missing>
  - Fix: <exact suggested text, or "delete">

## Top 3 fixes
1. ...
2. ...
3. ...
```

Rules for the report:

- Severity is one of: `high` (wrong or misleading), `medium` (outdated or duplicated), `low` (style, can be shorter).
- Every finding must have evidence from the code or the file tree. No evidence — no finding.
- If a criterion has no problems, write "No issues found" and still give a score.
- Use simple, short sentences.
- At the end, ask whether to apply the fixes. Do not apply them without approval.
