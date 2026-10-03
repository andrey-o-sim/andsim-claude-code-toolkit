#!/usr/bin/env bash
# Pre-commit checks for a .NET repo.
#
# Started by the PreToolUse hook in hooks.json, which fires on `git commit`. The steps,
# in order: build, dotnet format style, tests. One build, reused by the steps after it.
#
# Exit 0 lets the commit through. Exit 2 blocks it and sends the reason back to Claude,
# so it can fix the problem instead of just seeing "command failed".
#
# ## What it runs against
#
# The repo's CLAUDE.md comes first. Put a fenced `precommit` block in it:
#
#     ```precommit
#     solution:      MyApp.slnx
#     unit-tests:    tests/MyApp.Domain.UnitTests
#                    tests/MyApp.Application.UnitTests
#     needs-docker:  tests/MyApp.Integration.Tests
#     ```
#
# Every key is optional. Whatever is missing is worked out from the repo:
#
#   solution      first *.slnx in the repo root, then *.sln
#   test projects *.csproj that reference Microsoft.NET.Test.Sdk or set IsTestProject
#   needs-docker  those test projects that reference Testcontainers
#
# Values can be a .csproj path or the folder holding one. Several paths go on one line
# or on continuation lines, as above.
#
# When no .NET layout can be found, the hook does nothing and lets the commit through.
# It never blocks a commit because it failed to understand the repo.
#
# ## Escape hatches
#
#   PRECOMMIT_TESTS=unit git commit -m "..."    skip the tests that need Docker
#   PRECOMMIT_TESTS=none git commit -m "..."    skip the tests entirely
#   PRECOMMIT_TIMEOUT=600 git commit -m "..."   raise the per-step time limit

set -uo pipefail

# "all" runs every test project. "unit" skips the ones that need Docker. "none" skips tests.
TEST_SCOPE="${PRECOMMIT_TESTS:-all}"

# Time limit in seconds for one step: build, format, or one test project. Per step, not
# for the whole hook.
#
# The hook entry in hooks.json has no "timeout" on purpose. A hook killed from the outside
# dies without a message, so the commit just fails with no reason. Stopping the step here
# instead lets us say what hung and how long it got.
STEP_TIMEOUT="${PRECOMMIT_TIMEOUT:-180}"

repo="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "$repo" ] && [ -d "$repo" ] || exit 0
cd "$repo" || exit 0

fail() {
  printf '%s\n' "$1" >&2
  exit 2
}

# Something the user should know that is not worth blocking a commit over.
note() {
  printf '%s\n' "$1" >&2
}

# GNU coreutils timeout. Git Bash and Linux ship it. On macOS it is gtimeout, and only when
# coreutils is installed. With neither, run without a limit: the checks still matter more
# than the limit.
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD=(timeout --kill-after=10s "$STEP_TIMEOUT")
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD=(gtimeout --kill-after=10s "$STEP_TIMEOUT")
else
  TIMEOUT_CMD=()
fi

step_output=$(mktemp) || fail "Cannot create a temp file for the pre-commit log, commit blocked."
trap 'rm -f "$step_output"' EXIT

# Runs one step under the time limit. Puts the last 40 lines of its output in $step_log and
# its exit code in $step_status. Read the code from $step_status, not from $?: after
# `if ! run_step ...` the shell reports the negated result, so $? is always 0 there.
#
# The output goes to a file, not to a pipe. A dotnet child process can outlive the timeout,
# and while it holds a pipe open the shell keeps waiting for it. That is exactly the hang we
# are trying to stop, so we never read through a pipe here.
run_step() {
  step_status=0
  "${TIMEOUT_CMD[@]}" "$@" >"$step_output" 2>&1 || step_status=$?
  step_log=$(tail -n 40 "$step_output")
  return "$step_status"
}

# Call right after a failed run_step, before the normal error message.
# Exits when the step ran out of time. Returns when it failed for a real reason.
#
# timeout exits with 124 after SIGTERM, and with 137 when --kill-after had to use SIGKILL.
check_timeout() {
  local status=$1 name=$2 command=$3

  case "$status" in
    124 | 137) ;;
    *) return 0 ;;
  esac

  fail "$name did not finish in ${STEP_TIMEOUT}s and was stopped, commit blocked:
$step_log

The step was cut off, so we do not know whether it would have passed. Run it yourself to
see what is slow:
  $command

To give it more time for one commit:
  PRECOMMIT_TIMEOUT=600 git commit -m \"...\""
}

# --- What changed -------------------------------------------------------------------

# `git commit -a` stages files only at commit time, so unstaged changes count too.
changed_files() {
  {
    git diff --cached --name-only --diff-filter=ACMR -- "$@"
    git diff --name-only --diff-filter=ACMR -- "$@"
  } | sort -u
}

# Keep only paths that still exist. A rename leaves the old path in the list.
keep_existing() {
  local file
  while IFS= read -r file; do
    [ -f "$file" ] && printf '%s\n' "$file"
  done
}

mapfile -t cs_files < <(changed_files '*.cs' | keep_existing)

# A change to any of these can alter the result of the build or of dotnet format for files
# that were not touched in this commit.
mapfile -t config_files < <(
  changed_files '.editorconfig' '*.csproj' '*.slnx' '*.sln' '*.props' '*.targets' | keep_existing
)

# Nothing here can break the build or the tests.
if [ ${#cs_files[@]} -eq 0 ] && [ ${#config_files[@]} -eq 0 ]; then
  exit 0
fi

# --- Where things are ---------------------------------------------------------------

# Reads the fenced `precommit` block out of a markdown file and prints "key<TAB>value",
# one value per line. An indented line with no "key:" continues the key above it.
read_precommit_block() {
  awk '
    /^[[:space:]]*```[[:space:]]*precommit[[:space:]]*$/ { inblock = 1; next }
    inblock && /^[[:space:]]*```/ { inblock = 0; next }
    !inblock { next }
    {
      line = $0
      gsub(/\r/, "", line)                 # CRLF checkouts
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line == "" || line ~ /^#/) next
      if (match(line, /^[A-Za-z][A-Za-z0-9_-]*:/)) {
        cur = tolower(substr(line, 1, RLENGTH - 1))
        val = substr(line, RLENGTH + 1)
        sub(/^[[:space:]]+/, "", val)
        if (val != "") print cur "\t" val
      } else if (cur != "") {
        print cur "\t" line
      }
    }
  ' "$1"
}

SOLUTION=""
CONFIG_SOURCE=""
declare -a cfg_unit=() cfg_docker=()

for candidate in "CLAUDE.md" ".claude/CLAUDE.md"; do
  [ -f "$candidate" ] || continue
  grep -q '^[[:space:]]*```[[:space:]]*precommit[[:space:]]*$' "$candidate" 2>/dev/null || continue
  CONFIG_SOURCE="$candidate"
  while IFS=$'\t' read -r key value; do
    read -ra parts <<<"${value//,/ }"
    case "$key" in
      solution) [ -z "$SOLUTION" ] && SOLUTION="${parts[0]}" ;;
      unit-tests | unit) cfg_unit+=("${parts[@]}") ;;
      needs-docker | integration-tests) cfg_docker+=("${parts[@]}") ;;
    esac
  done < <(read_precommit_block "$candidate")
  break
done

# A configured path can be the .csproj itself or the folder holding it.
resolve_project() {
  local path=$1 proj
  if [ -d "$path" ]; then
    proj=$(find "$path" -maxdepth 1 -name '*.csproj' 2>/dev/null | head -1)
    [ -n "$proj" ] && printf '%s\n' "${proj#./}"
    return
  fi
  [ -f "$path" ] && printf '%s\n' "${path#./}"
}

# Turns configured paths into real .csproj paths in $resolved_projects, and collects the
# ones that are gone in $stale_paths.
#
# Both arrays are filled in this shell on purpose. Reading the result through a pipe or a
# process substitution would run the loop in a subshell, and $stale_paths would come back
# empty every time.
declare -a stale_paths=() resolved_projects=()
resolve_all() {
  local path resolved
  resolved_projects=()
  for path in "$@"; do
    resolved=$(resolve_project "$path")
    if [ -n "$resolved" ]; then
      resolved_projects+=("$resolved")
    else
      stale_paths+=("$path")
    fi
  done
}

if [ -n "$SOLUTION" ] && [ ! -f "$SOLUTION" ]; then
  stale_paths+=("$SOLUTION")
  SOLUTION=""
fi

if [ -z "$SOLUTION" ]; then
  SOLUTION=$(ls -1 ./*.slnx 2>/dev/null | head -1)
  [ -z "$SOLUTION" ] && SOLUTION=$(ls -1 ./*.sln 2>/dev/null | head -1)
  SOLUTION="${SOLUTION#./}"
fi

# What build, format and the full test run point at. A solution when there is one, the
# single root project when there is not.
declare -a TARGET=()
if [ -n "$SOLUTION" ]; then
  TARGET=("$SOLUTION")
else
  mapfile -t root_projects < <(ls -1 ./*.csproj 2>/dev/null)
  if [ ${#root_projects[@]} -eq 1 ]; then
    TARGET=("${root_projects[0]#./}")
  else
    note "Pre-commit hook: no .slnx or .sln in $repo, and no single project to fall back on.
Nothing was checked and the commit was allowed through.

Name the solution in CLAUDE.md to turn the checks on:

  \`\`\`precommit
  solution: <name>.slnx
  \`\`\`"
    exit 0
  fi
fi

# Every test project in the repo. Cheap, and it is what the unit/docker split works from.
mapfile -t all_tests < <(
  grep -rl --include='*.csproj' -E 'Microsoft\.NET\.Test\.Sdk|<IsTestProject>[[:space:]]*true' . 2>/dev/null \
    | sed 's#^\./##' | sort
)

declare -a docker_tests=() unit_tests=()

if [ ${#cfg_docker[@]} -gt 0 ]; then
  resolve_all "${cfg_docker[@]}"
  docker_tests=("${resolved_projects[@]}")
else
  for proj in "${all_tests[@]}"; do
    grep -qi 'Testcontainers' "$proj" && docker_tests+=("$proj")
  done
fi

if [ ${#cfg_unit[@]} -gt 0 ]; then
  resolve_all "${cfg_unit[@]}"
  unit_tests=("${resolved_projects[@]}")
else
  for proj in "${all_tests[@]}"; do
    is_docker=0
    for docker_proj in "${docker_tests[@]}"; do
      [ "$proj" = "$docker_proj" ] && is_docker=1 && break
    done
    [ "$is_docker" -eq 0 ] && unit_tests+=("$proj")
  done
fi

if [ ${#stale_paths[@]} -gt 0 ]; then
  note "Pre-commit hook: $CONFIG_SOURCE points at paths that do not exist: ${stale_paths[*]}
Those were ignored and the rest was worked out from the repo. Worth fixing the block."
fi

# --- Build --------------------------------------------------------------------------

if ! run_step dotnet build "${TARGET[@]}" --nologo -v q; then
  check_timeout "$step_status" "The build" "dotnet build ${TARGET[*]}"
  fail "Build failed, commit blocked:
$step_log"
fi

# --- Format -------------------------------------------------------------------------

# A changed .editorconfig or build file can reformat code this commit did not touch, so
# check everything. Otherwise only the changed C# files, which is much faster.
if [ ${#config_files[@]} -gt 0 ]; then
  if ! run_step dotnet format style "${TARGET[@]}" --verify-no-changes --no-restore; then
    check_timeout "$step_status" "dotnet format style" "dotnet format style ${TARGET[*]} --verify-no-changes"
    fail "dotnet format style found unformatted code, commit blocked:
$step_log

Everything was checked because a build or style file changed:
  ${config_files[*]}

Run: dotnet format style ${TARGET[*]}"
  fi
elif [ ${#cs_files[@]} -gt 0 ]; then
  if ! run_step dotnet format style "${TARGET[@]}" --verify-no-changes --no-restore --include "${cs_files[@]}"; then
    check_timeout "$step_status" "dotnet format style" "dotnet format style ${TARGET[*]} --verify-no-changes --include ${cs_files[*]}"
    fail "dotnet format style found unformatted code, commit blocked:
$step_log

Run: dotnet format style ${TARGET[*]} --include ${cs_files[*]}"
  fi
fi

# --- Tests --------------------------------------------------------------------------

[ "$TEST_SCOPE" = "none" ] && exit 0
[ ${#all_tests[@]} -eq 0 ] && [ ${#unit_tests[@]} -eq 0 ] && exit 0

# One project per run. `dotnet test` takes a single project or solution, so a list of
# paths in one call is not reliable across SDK versions.
run_test_projects() {
  local label=$1 proj
  shift
  for proj in "$@"; do
    if ! run_step dotnet test "$proj" --no-build --nologo -v q; then
      check_timeout "$step_status" "$label ($proj)" "dotnet test $proj --no-build"
      fail "$label failed in $proj, commit blocked:
$step_log"
    fi
  done
}

if [ "$TEST_SCOPE" = "unit" ]; then
  run_test_projects "Unit tests" "${unit_tests[@]}"
  exit 0
fi

if [ ${#docker_tests[@]} -gt 0 ] && ! docker info >/dev/null 2>&1; then
  fail "These test projects need Docker, and Docker is not responding:
  ${docker_tests[*]}

Start Docker Desktop, then commit again.

To commit without them:
  PRECOMMIT_TESTS=unit git commit -m \"...\""
fi

if ! run_step dotnet test "${TARGET[@]}" --no-build --nologo -v q; then
  check_timeout "$step_status" "The tests" "dotnet test ${TARGET[*]} --no-build"
  fail "Tests failed, commit blocked:
$step_log"
fi
