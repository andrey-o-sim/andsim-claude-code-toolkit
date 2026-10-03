# autodoc.ps1 — let the Claude Agent SDK update the document for the subject
# touched by a change set.
#
# Works in Windows PowerShell 5.1+ and PowerShell 7 (pwsh) on any OS, which is
# also what the GitHub Actions workflow in sdk/ci/autodoc-pr.yml runs.
#
# Usage:
#   cd <path>\your-repo
#
#   <path>\sdk\autodoc.ps1                      # last merged PR
#   <path>\sdk\autodoc.ps1 origin/master my-br  # branch vs base (the PR case)
#
# With no arguments the script documents the last merge commit — the post-merge
# CI case. With two refs it documents what the second ref adds on top of the
# first (`git diff base...head`), which is the pre-merge case: run it on an open
# branch and review the doc update inside the PR.
#
# ── How it knows anything about your repository ──────────────────────────────
#
# It does not. The repository describes itself in a fenced `autodoc` block in
# its CLAUDE.md (or .claude/CLAUDE.md):
#
#     ```autodoc
#     profile:        dotnet-rest-api
#     module-root:    src/Billing/Commands
#     tests-root:     tests/Billing.IntegrationTests
#     docs-dir:       docs/api
#     route-prefix:   /api/v1/billing
#     read-paths:     src/** tests/**
#     extra-context:  src/Billing.Entities/Enums
#     ```
#
# Those paths are one example, not a requirement. Which keys matter, and what
# they mean, is the profile's business — see sdk/profiles/.
#
# `profile` names a file in sdk/profiles/. That file holds the knowledge this
# script deliberately does not: what a subject is, how to name the document,
# what the document looks like. Adding support for a new kind of repository
# means writing one profile — this script does not change.
#
# Optional keys: model (default claude-sonnet-5), max-turns (default 20).
# Every key can be overridden by an env var for CI: AUTODOC_PROFILE,
# AUTODOC_MODULE_ROOT, AUTODOC_TESTS_ROOT, AUTODOC_DOCS_DIR,
# AUTODOC_ROUTE_PREFIX, AUTODOC_READ_PATHS, AUTODOC_EXTRA_CONTEXT,
# AUTODOC_MODEL, AUTODOC_MAX_TURNS.
#
# ── Requirements ─────────────────────────────────────────────────────────────
#
#   - cwd is a git repository with an `autodoc` block in its CLAUDE.md
#   - claude CLI in PATH
#   - Authenticated to Claude: either an active OAuth session
#     (`claude auth login`, for local dev with a Max/Pro/Team subscription) or
#     ANTHROPIC_API_KEY (CI/CD)
#
# ── What it demonstrates ─────────────────────────────────────────────────────
#
#   - `claude -p` running headlessly with a longer agent loop (~10-15 turns:
#     git log → git diff --stat → git diff <subject> → Read source → Read types
#     → Read tests → Read existing doc → Write/Edit doc → Read back)
#   - `--allowed-tools` prefix matching across FOUR dimensions: Bash, Read, Edit
#     and Write. The permission set is built from config, so the asymmetry holds
#     in any repo: the agent may Read the whole source tree, but may only ever
#     create files in one documentation folder.
#   - `--max-turns` as a production budget guard
#   - `--output-format json` + `--json-schema` so the run reports structured
#     facts (which subject, created vs updated vs skipped) that CI can branch
#     on, instead of prose somebody has to read
#   - picking the model per task: the default is Sonnet because this is not a
#     rewriting job. The agent reads code and derives a description of it from
#     the source. Haiku drops details on that kind of work — names, types,
#     whole rows of a table. A profile can raise or lower this per repository.
#
# ── Skips are normal ─────────────────────────────────────────────────────────
#
#   Most merged PRs touch tests, docs or infrastructure and no documented
#   subject at all. For those the agent writes nothing and returns
#   `"action": "skipped"` with a reason. A skip is a correct run, not a
#   failure — the script exits 0.
#
# ── Trust model ──────────────────────────────────────────────────────────────
#
#   The agent writes into the docs folder in the working tree as a *suggestion*.
#   This script does NOT commit and does NOT push. After the run, inspect the
#   diff and choose:
#     - `git restore <docs-dir>; git clean -f <docs-dir>` — reject
#     - `git add -p; git commit`                          — accept
#   The CI workflow in sdk/ci/autodoc-pr.yml is what decides to push; keeping
#   that decision out of here is why the same script runs locally and in CI.

param(
    [string]$BaseRef,
    [string]$HeadRef
)

$ErrorActionPreference = 'Stop'

$IsWindowsHost = $env:OS -eq 'Windows_NT'

# Windows PowerShell 5.1 defaults to ASCII/codepage encodings around native
# commands. Force UTF-8 both ways so the prompt's unicode survives the pipe
# and Claude's JSON output decodes correctly.
$OutputEncoding = [System.Text.Encoding]::UTF8
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# Native-command argument passing differs between PowerShell editions. Pin the
# behavior to 'Legacy' where the preference exists (pwsh 7.2+) so the manual
# quote-escaping below works identically on 5.1 and 7.x on Windows.
if ($IsWindowsHost -and (Get-Variable PSNativeCommandArgumentPassing -ErrorAction SilentlyContinue)) {
    $PSNativeCommandArgumentPassing = 'Legacy'
}

function ConvertTo-NativeArg([string]$Value) {
    # On Windows the command line is re-parsed by the native app's runtime;
    # embedded double quotes must be backslash-escaped or they get eaten.
    # On macOS/Linux args reach the process verbatim — no escaping needed.
    if ($IsWindowsHost) { return ($Value -replace '"', '\"') }
    return $Value
}

function Write-Stderr([string]$Message) {
    [Console]::Error.WriteLine($Message)
}

$PromptFile = Join-Path $PSScriptRoot 'prompts/autodoc.md'
$ProfileDir = Join-Path $PSScriptRoot 'profiles'

# ──────────────────────────────────────────────────────────────────
# Pre-flight
# ──────────────────────────────────────────────────────────────────

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Stderr 'ERROR: claude CLI not found in PATH.'
    Write-Stderr '       See https://docs.claude.com for installation.'
    exit 1
}

# Accept either OAuth session (claude auth login) or env var (CI/CD).
# Order matters: in CI the env var is always present, so we check it first and
# avoid invoking `claude auth status` (which may fail without OAuth).
if ($env:ANTHROPIC_API_KEY) {
    # env var present — OK
}
elseif ((claude auth status --json 2>$null | Out-String) -match '"loggedIn":\s*true') {
    # OAuth session active — OK
}
else {
    Write-Stderr 'ERROR: not authenticated to Claude.'
    Write-Stderr '       Choose one:'
    Write-Stderr "         - Run 'claude auth login' (OAuth, recommended for local dev)"
    Write-Stderr '         - Or set ANTHROPIC_API_KEY (CI/CD, GitHub Secrets)'
    exit 1
}

if (-not (Test-Path $PromptFile)) {
    Write-Stderr "ERROR: prompt file missing: $PromptFile"
    exit 1
}

if (-not (Test-Path '.git')) {
    Write-Stderr 'ERROR: cwd is not a git repository.'
    Write-Stderr '       Run this from the root of the repository you want documented.'
    exit 1
}

function Get-AvailableProfiles {
    if (-not (Test-Path $ProfileDir)) { return @() }
    return Get-ChildItem -Path $ProfileDir -Filter '*.md' |
        ForEach-Object { $_.BaseName } |
        Sort-Object
}

function Write-AvailableProfiles {
    Write-Stderr '       Available profiles:'
    foreach ($name in Get-AvailableProfiles) { Write-Stderr "         - $name" }
}

# ──────────────────────────────────────────────────────────────────
# Repository configuration — the fenced `autodoc` block in CLAUDE.md
# ──────────────────────────────────────────────────────────────────
#
# Reads "key: value" lines out of the block. An indented line with no "key:"
# continues the key above it, so a long list of read paths can be spread over
# several lines.

function Read-AutodocBlock([string]$Path) {
    $pairs = New-Object System.Collections.Generic.List[object]
    $inBlock = $false
    $current = $null

    foreach ($rawLine in (Get-Content -Encoding UTF8 -Path $Path)) {
        $line = $rawLine -replace "`r", ''    # CRLF checkouts

        if (-not $inBlock) {
            if ($line -match '^\s*```\s*autodoc\s*$') { $inBlock = $true }
            continue
        }
        if ($line -match '^\s*```') { break }

        $line = $line.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }

        if ($line -match '^([A-Za-z][A-Za-z0-9_-]*):\s*(.*)$') {
            $current = $Matches[1].ToLower()
            $value = $Matches[2].Trim()
            if ($value) { $pairs.Add([pscustomobject]@{ Key = $current; Value = $value }) }
        }
        elseif ($current) {
            $pairs.Add([pscustomobject]@{ Key = $current; Value = $line })
        }
    }

    return $pairs
}

$ProfileName       = ''
$ModuleRoot    = ''
$TestsRoot     = ''
$DocsDir       = ''
$RoutePrefix   = ''
$ReadPaths     = ''
$ExtraContext  = ''
$Model         = ''
$MaxTurns      = ''
$ConfigSource  = ''

foreach ($candidate in @('CLAUDE.md', '.claude/CLAUDE.md')) {
    if (-not (Test-Path $candidate)) { continue }
    $pairs = Read-AutodocBlock $candidate
    if ($pairs.Count -eq 0) { continue }

    $ConfigSource = $candidate
    foreach ($pair in $pairs) {
        switch ($pair.Key) {
            'profile'       { $ProfileName = $pair.Value }
            'module-root'   { $ModuleRoot = $pair.Value }
            'tests-root'    { $TestsRoot = $pair.Value }
            'docs-dir'      { $DocsDir = $pair.Value }
            'route-prefix'  { $RoutePrefix = $pair.Value }
            'read-paths'    { $ReadPaths = ("$ReadPaths $($pair.Value)").Trim() }
            'extra-context' { $ExtraContext = ("$ExtraContext $($pair.Value)").Trim() }
            'model'         { $Model = $pair.Value }
            'max-turns'     { $MaxTurns = $pair.Value }
        }
    }
    break
}

# Env wins over the file. CI passes values this way without editing the repo.
function Use-Override($EnvValue, $FileValue, $Default = '') {
    if ($EnvValue)  { return $EnvValue }
    if ($FileValue) { return $FileValue }
    return $Default
}

$ProfileName      = Use-Override $env:AUTODOC_PROFILE       $ProfileName
$ModuleRoot   = Use-Override $env:AUTODOC_MODULE_ROOT   $ModuleRoot
$TestsRoot    = Use-Override $env:AUTODOC_TESTS_ROOT    $TestsRoot
$DocsDir      = Use-Override $env:AUTODOC_DOCS_DIR      $DocsDir
$RoutePrefix  = Use-Override $env:AUTODOC_ROUTE_PREFIX  $RoutePrefix
$ReadPaths    = Use-Override $env:AUTODOC_READ_PATHS    $ReadPaths   'src/** tests/**'
$ExtraContext = Use-Override $env:AUTODOC_EXTRA_CONTEXT $ExtraContext
$Model        = Use-Override $env:AUTODOC_MODEL         $Model       'claude-sonnet-5'
$MaxTurns     = [int](Use-Override $env:AUTODOC_MAX_TURNS $MaxTurns  '20')

$ModuleRoot = $ModuleRoot.TrimEnd('/')
$TestsRoot  = $TestsRoot.TrimEnd('/')
$DocsDir    = $DocsDir.TrimEnd('/')

if (-not $ProfileName -or -not $DocsDir) {
    Write-Stderr 'ERROR: no autodoc configuration found.'
    Write-Stderr '       Add a fenced block to CLAUDE.md in this repository:'
    Write-Stderr ''
    Write-Stderr '           ```autodoc'
    Write-Stderr '           profile:      dotnet-rest-api'
    Write-Stderr '           module-root:  src/<Service>/Commands'
    Write-Stderr '           tests-root:   tests/<Service>.IntegrationTests'
    Write-Stderr '           docs-dir:     docs/api'
    Write-Stderr '           route-prefix: /api/v1/<service>'
    Write-Stderr '           ```'
    Write-Stderr ''
    Write-AvailableProfiles
    exit 1
}

$ProfileFile = Join-Path $ProfileDir "$ProfileName.md"
if (-not (Test-Path $ProfileFile)) {
    Write-Stderr "ERROR: unknown profile '$ProfileName' — no such file: $ProfileFile"
    Write-AvailableProfiles
    exit 1
}

# Fail loudly rather than burning turns on a repo the config does not describe.
if ($ModuleRoot -and -not (Test-Path $ModuleRoot)) {
    Write-Stderr "ERROR: module-root does not exist: $ModuleRoot"
    $where = if ($ConfigSource) { $ConfigSource } else { 'CLAUDE.md' }
    Write-Stderr "       Fix the autodoc block in $where."
    exit 1
}

# ──────────────────────────────────────────────────────────────────
# Resolve the change set — merge mode (no args) or branch mode (two refs)
# ──────────────────────────────────────────────────────────────────
#
# The agent must not pick the refs itself: in branch mode there is no way for it
# to guess which base you meant. The script resolves them here and states them
# in a `## This run` block appended to the prompt. One source of truth, visible
# in the console before any money is spent.

if (-not $BaseRef -and -not $HeadRef) {
    $MergeSha = (git log --merges -1 --format=%H 2>$null | Out-String).Trim()
    if (-not $MergeSha) {
        Write-Stderr 'ERROR: no merge commits in history — nothing to document.'
        Write-Stderr '       Pass two refs instead: autodoc.ps1 <base-ref> <head-ref>'
        exit 1
    }
    $DiffCmd    = "git diff $MergeSha^1 $MergeSha"
    $Label      = (git log -1 --format=%s $MergeSha | Out-String).Trim()
    $ShortSha   = (git rev-parse --short $MergeSha | Out-String).Trim()
    $SourceLine = "merge commit $ShortSha"
    $RunDate    = (git log -1 --format=%ad --date=short $MergeSha | Out-String).Trim()
}
elseif ($BaseRef -and $HeadRef) {
    foreach ($Ref in @($BaseRef, $HeadRef)) {
        git rev-parse --verify --quiet $Ref *> $null
        if ($LASTEXITCODE -ne 0) {
            Write-Stderr "ERROR: unknown git ref: $Ref"
            exit 1
        }
    }
    # Three dots: what HeadRef adds since the two refs diverged. Two dots would
    # also report everything BaseRef gained in the meantime — commits the branch
    # author never touched.
    $DiffCmd    = "git diff $BaseRef...$HeadRef"
    $Label      = "branch $HeadRef compared to $BaseRef"
    $ShortSha   = (git rev-parse --short $HeadRef | Out-String).Trim()
    $SourceLine = "branch $HeadRef ($ShortSha) vs $BaseRef"
    $RunDate    = (git log -1 --format=%ad --date=short $HeadRef | Out-String).Trim()
}
else {
    Write-Stderr 'ERROR: expected 0 or 2 arguments.'
    Write-Stderr '       autodoc.ps1                        # last merged PR'
    Write-Stderr '       autodoc.ps1 <base-ref> <head-ref>  # branch vs base'
    exit 1
}

# Show the viewer what is about to be processed, before spending money.
$ConfigOrigin = if ($ConfigSource) { $ConfigSource } else { 'env' }
Write-Stderr "[autodoc] profile:    $ProfileName  (from $ConfigOrigin)"
Write-Stderr "[autodoc] change set: $DiffCmd"
Write-Stderr "[autodoc] label:      $Label"

$DiffArgs = $DiffCmd.Split(' ')[1..($DiffCmd.Split(' ').Length - 1)]

if ($ModuleRoot) {
    $prefix = "$ModuleRoot/"
    $ChangedSubjects = (& git @DiffArgs --name-only -- $ModuleRoot 2>$null |
        Where-Object { $_.StartsWith($prefix) } |
        ForEach-Object { ($_.Substring($prefix.Length) -split '/')[0] } |
        Sort-Object -Unique) -join ' '
    if (-not $ChangedSubjects) { $ChangedSubjects = '<none — agent will skip>' }
    Write-Stderr "[autodoc] subjects touched: $ChangedSubjects"
}

# ──────────────────────────────────────────────────────────────────
# Assemble the prompt: contract + profile + configuration + this run
# ──────────────────────────────────────────────────────────────────
#
# String.Replace, not -replace: these are literal placeholders, and every value
# is a path. The regex operator would treat a path separator or a dot in a
# folder name as syntax.

$ProfileText = Get-Content -Raw -Encoding UTF8 $ProfileFile
$ProfileText = $ProfileText.Replace('{{MODULE_ROOT}}',   $(if ($ModuleRoot)   { $ModuleRoot }   else { '<not configured>' }))
$ProfileText = $ProfileText.Replace('{{TESTS_ROOT}}',    $(if ($TestsRoot)    { $TestsRoot }    else { '<not configured>' }))
$ProfileText = $ProfileText.Replace('{{DOCS_DIR}}',      $DocsDir)
$ProfileText = $ProfileText.Replace('{{ROUTE_PREFIX}}',  $(if ($RoutePrefix)  { $RoutePrefix }  else { '<not configured>' }))
$ProfileText = $ProfileText.Replace('{{EXTRA_CONTEXT}}', $(if ($ExtraContext) { $ExtraContext } else { '<none>' }))

$ModuleRootDisplay  = if ($ModuleRoot)  { $ModuleRoot }  else { '<not configured>' }
$TestsRootDisplay   = if ($TestsRoot)   { $TestsRoot }   else { '<not configured>' }
$RoutePrefixDisplay = if ($RoutePrefix) { $RoutePrefix } else { '<not configured>' }
$ReadPathsDisplay   = ("$ReadPaths $ExtraContext $DocsDir" -replace '\s+', ' ').Trim()

$Prompt = (Get-Content -Raw -Encoding UTF8 $PromptFile) + @"

## Repository profile

$ProfileText

## Repository configuration

- Subject root: $ModuleRootDisplay
- Tests root: $TestsRootDisplay
- Documentation folder: $DocsDir  (you may Write and Edit only here)
- Readable paths: $ReadPathsDisplay
- Route prefix: $RoutePrefixDisplay

## This run

- Diff command: ``$DiffCmd``
- Label: $Label
- Source: $SourceLine
- Date: $RunDate
"@

# ──────────────────────────────────────────────────────────────────
# JSON schema — validated against Claude's final response
# ──────────────────────────────────────────────────────────────────
#
# Mirrors the "Final output" section of prompts/autodoc.md. Keep the two in sync.
#
# `action` is the field CI branches on:
#   created / updated → there is a doc diff to review
#   skipped           → the change set touched no subject, nothing to review
#
# `subject` and `items` are deliberately profile-neutral. A REST profile fills
# items with endpoints; a CLI profile would fill them with commands. The schema
# does not need to know which.

$Schema = @'
{
  "type": "object",
  "properties": {
    "pr_number":   {"type": "string"},
    "head_commit": {"type": "string"},
    "pr_title":    {"type": "string"},
    "subject":     {"type": "string"},
    "doc_path":    {"type": "string"},
    "action":      {"type": "string", "enum": ["created", "updated", "skipped"]},
    "items": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "kind":   {"type": "string"},
          "name":   {"type": "string"},
          "change": {"type": "string", "enum": ["added", "changed", "removed", "unchanged"]}
        },
        "required": ["kind", "name", "change"]
      }
    },
    "summary": {"type": "string"},
    "notes":   {"type": "array", "items": {"type": "string"}}
  },
  "required": ["pr_number", "head_commit", "pr_title", "subject", "doc_path", "action", "items", "summary", "notes"]
}
'@

# Compact to a single line without spaces: a space-free argument never gets
# re-quoted by PowerShell, which sidesteps most Windows quoting traps.
$SchemaArg = ConvertTo-NativeArg ($Schema | ConvertFrom-Json | ConvertTo-Json -Depth 10 -Compress)

# ──────────────────────────────────────────────────────────────────
# Invoke Claude — agent loop with four-dimensional permissions
# ──────────────────────────────────────────────────────────────────
#
# Permissions cheat-sheet:
#   Bash(git log *)      — find the merge commit
#   Bash(git show *)     — inspect it
#   Bash(git diff *)     — what the change set changed
#                          (`git commit`, `git push`, `rm`, any build or test
#                           command — all blocked, whatever the stack)
#   Read(<read-paths>)   — source, types, tests: whatever the config lists
#   Read(<docs-dir>/**)  — the existing document, if any
#   Write(<docs-dir>/**) — create the document on the first run
#   Edit(<docs-dir>/**)  — update it on later runs
#
# Read is wide, Write is narrow, and both come from config. That asymmetry is
# the point: the agent needs the source tree to understand the code, but can
# only ever produce files in one documentation folder.
#
# The prompt is piped via stdin instead of being passed as an argument:
# multi-line markdown with quotes and backticks does not survive the Windows
# command-line re-parsing reliably, stdin always does.

$AllowedTools = @('Bash(git log *)', 'Bash(git show *)', 'Bash(git diff *)')
foreach ($path in ("$ReadPaths $ExtraContext" -split '\s+' | Where-Object { $_ })) {
    # A bare folder means everything under it.
    $pattern = if ($path.Contains('*')) { $path } else { $path.TrimEnd('/') + '/**' }
    $AllowedTools += "Read($pattern)"
}
$AllowedTools += @("Read($DocsDir/**)", "Write($DocsDir/**)", "Edit($DocsDir/**)")

Write-Stderr "[autodoc] model: $Model, max-turns: $MaxTurns"
Write-Stderr "[autodoc] tools: $($AllowedTools -join ' ')"

# Splatting, because the tool list is built at run time and its length varies.
$ClaudeArgs = @('-p', '--allowed-tools') + $AllowedTools + @(
    '--model', $Model,
    '--output-format', 'json',
    '--json-schema', $SchemaArg,
    '--max-turns', $MaxTurns
)

$RawResponse = $Prompt | & claude @ClaudeArgs
$ClaudeExit = $LASTEXITCODE
$ResponseText = (@($RawResponse) -join "`n").Trim()

if ($ClaudeExit -ne 0) {
    Write-Stderr "[claude] exited with code $ClaudeExit — raw response below"
    Write-Stderr $ResponseText
    exit $ClaudeExit
}

# ──────────────────────────────────────────────────────────────────
# Normalize response shape across claude CLI versions
# ──────────────────────────────────────────────────────────────────
#
# Older claude (< 2.x): --output-format json returns a single object with
# `.result`, `.total_cost_usd`, `.is_error`, etc. at the top level.
# Newer claude (2.x+): same flag returns a JSON array of messages; the final
# element has `type: "result"` and carries those same fields.
# Pull the result-typed payload regardless of which shape we got.

try {
    $Parsed = ConvertFrom-Json -InputObject $ResponseText
}
catch {
    Write-Stderr '[claude] response is not valid JSON — raw response below'
    Write-Stderr $ResponseText
    exit 1
}

$Items = @($Parsed)
$ResultObj = $Items |
    Where-Object { $_.PSObject.Properties['type'] -and $_.type -eq 'result' } |
    Select-Object -Last 1
if ($null -eq $ResultObj) { $ResultObj = $Items[0] }

function Get-Field($Object, [string]$Name, $Default) {
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name] -and $null -ne $Object.$Name) {
        return $Object.$Name
    }
    return $Default
}

# ──────────────────────────────────────────────────────────────────
# Summary on stderr — cost, duration, turns, error status
# ──────────────────────────────────────────────────────────────────
#
# `num_turns` is NOT the counter `--max-turns` enforces. Observed on claude
# 2.1.x with the budget at 20: successful runs reported 22 and 31 and did not
# fail, while the run that did hit the budget reported 21 plus
# `subtype: error_max_turns`. So print the field under its own name and show the
# budget next to it — labelling it plain `turns` made every normal run look like
# the guard was broken. The authoritative signal for "ran out of budget" is
# `subtype` / `terminal_reason`, not this number.

$Cost     = Get-Field $ResultObj 'total_cost_usd' 'n/a'
$Duration = Get-Field $ResultObj 'duration_ms'    'n/a'
$Turns    = Get-Field $ResultObj 'num_turns'      'n/a'
$IsError  = Get-Field $ResultObj 'is_error'       $false

Write-Stderr "[claude] cost=`$$Cost duration=${Duration}ms num_turns=$Turns (--max-turns $MaxTurns) is_error=$IsError"

if ($IsError -eq $true) {
    Write-Stderr '[claude] agent reported an error — raw response below'
    Write-Stderr $ResponseText
    exit 1
}

# ──────────────────────────────────────────────────────────────────
# Schema-validated JSON payload → stdout
# ──────────────────────────────────────────────────────────────────
#
# Where the structured output lives depends on CLI version:
#   - claude 2.x+: `.structured_output` is a native JSON object built from the
#     response and validated against --json-schema.
#   - claude < 2.x: `.result` is a JSON string (also validated).
# Fall back to raw `.result` if neither shape parses — at least the viewer still
# sees what the agent said.

$Payload = Get-Field $ResultObj 'structured_output' $null
if ($null -eq $Payload) {
    $RawResult = Get-Field $ResultObj 'result' $null
    if ($RawResult -is [string]) {
        try { $Payload = ConvertFrom-Json -InputObject $RawResult }
        catch { $Payload = $RawResult }
    }
    else {
        $Payload = $RawResult
    }
}

if ($Payload -is [string]) {
    Write-Output $Payload
}
else {
    $Payload | ConvertTo-Json -Depth 10
}

# ──────────────────────────────────────────────────────────────────
# Trust-but-verify: show what the agent actually did on disk, separate from the
# JSON it claims to have produced.
# ──────────────────────────────────────────────────────────────────
#
# A first run creates a new file, and `git diff` does not show untracked files —
# so print `git status` for the docs folder as well. Otherwise the most
# interesting run of the demo looks like it changed nothing.

$Action = 'unknown'
if ($Payload -isnot [string]) { $Action = Get-Field $Payload 'action' 'unknown' }

Write-Stderr ''
if ($Action -eq 'skipped') {
    $SkipReason = Get-Field $Payload 'summary' 'no reason given'
    Write-Stderr "[autodoc] skipped — $SkipReason"
    Write-Stderr '[autodoc] the change set touched no documented subject. Nothing was written.'
    exit 0
}

Write-Stderr "--- $DocsDir status (what agent created or changed) ---"
git status --short -- "$DocsDir/" 2>&1 | ForEach-Object { Write-Stderr "$_" }
Write-Stderr '--- tracked-file diff ---'
git diff -- "$DocsDir/" 2>&1 | ForEach-Object { Write-Stderr "$_" }
Write-Stderr '--- end ---'
Write-Stderr ''
Write-Stderr "[hint] new files show as '??' above and have no diff yet."
Write-Stderr "[hint] to review them as a diff:   git add -N $DocsDir/; git diff -- $DocsDir/"
Write-Stderr '[hint] to accept:                  git add -p; git commit'
Write-Stderr "[hint] to reject:                  git restore $DocsDir/; git clean -f $DocsDir/"
