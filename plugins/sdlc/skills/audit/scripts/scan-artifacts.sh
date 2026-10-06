#!/usr/bin/env bash
# Scans the 9 SDLC artifacts for one ticket and prints one TSV row per artifact.
#
# usage: scan-artifacts.sh <ticketNumber> [artifact-root]
#
#   ticketNumber   any tracker id, e.g. ABC-123. Used to locate the ticket's
#                  own area inside the artifact root and to match file names.
#   artifact-root  repo-relative directory holding the artifacts.
#                  Defaults to docs/implementation-artifacts.
#
# Output columns:
#   key  status  path  artifact_date  code_date  note
#
# status is one of: PRESENT MISPLACED STUB STALE MISSING
#
# Exit codes:
#   0  scan ran
#   2  bad usage, or not a git repository
#   3  artifact root not found — the caller should ask the user for the path
#      rather than guessing, and must not create the directory
#
# Dates are ISO-8601 from git (committer date). A file that git does not know
# falls back to its filesystem mtime and says so in the note, because mtime is
# rewritten by clone and checkout and cannot be trusted on its own.

set -uo pipefail

TICKET="${1:-}"
if [ -z "$TICKET" ]; then
  echo "usage: scan-artifacts.sh <ticketNumber> [artifact-root]" >&2
  exit 2
fi

ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$ROOT" ]; then
  echo "not a git repository" >&2
  exit 2
fi
cd "$ROOT" || exit 2

ARTIFACT_ROOT="${2:-docs/implementation-artifacts}"
ARTIFACT_ROOT="${ARTIFACT_ROOT%/}"

if [ ! -d "$ARTIFACT_ROOT" ]; then
  echo "artifact root not found: $ARTIFACT_ROOT" >&2
  echo "pass the correct path as the second argument" >&2
  exit 3
fi

# The ticket's own area. Projects differ: some give a ticket a subdirectory,
# others drop the files straight into the artifact root. Accept both, so a
# present artifact is never reported missing over a layout difference.
BASE="$ARTIFACT_ROOT"
for candidate in \
  "$ARTIFACT_ROOT/$TICKET-artifacts" \
  "$ARTIFACT_ROOT/$TICKET" \
  "$ARTIFACT_ROOT/$TICKET-docs"; do
  if [ -d "$candidate" ]; then BASE="$candidate"; break; fi
done

# ---------------------------------------------------------------------------
# Optional per-project watch paths.
#
# Staleness needs to know which code an artifact mirrors, and that mapping is
# project-specific — there is no portable way to guess that a PRD tracks one
# directory and a data model another. So it is configuration, not a constant.
#
# Provide <skill-dir>/watch-paths.conf with one line per artifact:
#     <key><TAB>path,path,path
# Keys are the ones in SPECS below. Lines starting with # are ignored, and an
# absent key simply means "no per-artifact mapping for this one".
#
# Without the file the script falls back to a repo-wide code date: the last
# commit touching anything outside the artifact root, markdown, and agent
# config. That is coarser — any code change can mark an artifact stale — but it
# works in any repository with no setup, and coarse-but-honest beats a mapping
# invented for a repo the script has never seen.
# ---------------------------------------------------------------------------
CONF="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/watch-paths.conf"

watch_for() {
  [ -f "$CONF" ] || return 0
  awk -v k="$1" '$0 !~ /^[[:space:]]*#/ && $1 == k { print $2; exit }' "$CONF"
}

# Last committer date across the given paths. Empty when git knows none of them.
git_date() {
  local existing=() p
  for p in "$@"; do
    [ -e "$p" ] && existing+=("$p")
  done
  [ ${#existing[@]} -eq 0 ] && return 0
  git log -1 --format=%cI -- "${existing[@]}" 2>/dev/null
}

# Repo-wide code date: everything except documentation and agent config.
repo_code_date() {
  git log -1 --format=%cI -- . \
    ":(exclude)$ARTIFACT_ROOT" \
    ":(exclude)*.md" \
    ":(exclude).claude" 2>/dev/null
}

mtime_date() {
  date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
}

# A file counts as a stub when almost nothing survives stripping headings,
# blanks, list bullets and TODO markers. A template skeleton is not an artifact.
is_stub() {
  grep -vE '^\s*$|^\s*#|^\s*[-*]\s*$|^\s*(TODO|TBD|FIXME|\.\.\.)\s*$' "$1" 2>/dev/null | wc -l | {
    read -r n; [ "$n" -lt 5 ]
  }
}

emit() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "${4:--}" "${5:--}" "${6:--}"
}

# ---------------------------------------------------------------------------
# Artifact spec: key | kind | canonical | alternates | members
#   kind        file or dir
#   alternates  comma-separated fallback paths (same content, wrong place)
#   members     glob for the files inside a dir artifact
#
# Alternates cover the common spellings plus two layout variants seen in the
# wild: the file sitting directly in the artifact root, and the file carrying
# the ticket id as a name prefix.
# ---------------------------------------------------------------------------
SPECS=(
"idea-brief|file|$BASE/idea-brief.md|$BASE/IdeaBrief.md,$BASE/idea_brief.md,$BASE/brief.md,$ARTIFACT_ROOT/idea-brief.md,$ARTIFACT_ROOT/$TICKET-idea-brief.md|"
"PRD|file|$BASE/PRD.md|$BASE/prd.md,$BASE/requirements.md,$ARTIFACT_ROOT/PRD.md,$ARTIFACT_ROOT/$TICKET-PRD.md,$ARTIFACT_ROOT/$TICKET-requirements.md|"
"sad|file|$BASE/sad.md|$BASE/SAD.md,$BASE/architecture.md,$BASE/solution-architecture.md,$ARTIFACT_ROOT/sad.md,$ARTIFACT_ROOT/$TICKET-sad.md,$ARTIFACT_ROOT/$TICKET-architecture.md|"
"adr|dir|$BASE/adr|$BASE/adrs,$BASE/decisions,$ARTIFACT_ROOT/adr,$ARTIFACT_ROOT/decisions|*.md"
"data-model|file|$BASE/data-model.md|$BASE/datamodel.md,$BASE/data_model.md,$ARTIFACT_ROOT/data-model.md,$ARTIFACT_ROOT/$TICKET-data-model.md|"
"openapi|file|$BASE/openapi.yaml|$BASE/openapi.yml,$BASE/openapi.json,$ARTIFACT_ROOT/openapi.yaml,docs/api/openapi.yaml,$ARTIFACT_ROOT/$TICKET-openapi.yaml|"
"api-sync-report|file|$BASE/api-sync-report.md|$BASE/api_sync_report.md,$BASE/api-sync.md,$ARTIFACT_ROOT/api-sync-report.md,$ARTIFACT_ROOT/$TICKET-api-sync-report.md|"
"tasks|dir|$BASE/tasks|$BASE,$ARTIFACT_ROOT/tasks|Task*.md"
"CONTEXT|file|$BASE/CONTEXT.md|CONTEXT.md,$BASE/context.md,$BASE/glossary.md,$ARTIFACT_ROOT/CONTEXT.md,$ARTIFACT_ROOT/$TICKET-CONTEXT.md|"
)

printf '# ticket\t%s\n' "$TICKET"
printf '# artifact_root\t%s\n' "$ARTIFACT_ROOT"
printf '# ticket_area\t%s\n' "$BASE"
if [ -f "$CONF" ]; then
  printf '# watch_paths\tper-artifact, from %s\n' "${CONF#"$ROOT"/}"
else
  printf '# watch_paths\trepo-wide fallback (no watch-paths.conf)\n'
fi
printf '# key\tstatus\tpath\tartifact_date\tcode_date\tnote\n'

REPO_CODE_DATE=$(repo_code_date)

for spec in "${SPECS[@]}"; do
  IFS='|' read -r key kind canonical alternates members <<< "$spec"

  # --- locate -------------------------------------------------------------
  found=""
  placement="canonical"
  if [ "$kind" = "dir" ]; then
    if [ -d "$canonical" ]; then found="$canonical"; fi
  else
    if [ -f "$canonical" ]; then found="$canonical"; fi
  fi

  if [ -z "$found" ] && [ -n "$alternates" ]; then
    IFS=',' read -ra alts <<< "$alternates"
    for alt in "${alts[@]}"; do
      [ -z "$alt" ] && continue
      if [ "$kind" = "dir" ]; then
        if [ -d "$alt" ] && [ -n "$(find "$alt" -maxdepth 1 -name "$members" -print -quit 2>/dev/null)" ]; then
          found="$alt"; placement="alternate"; break
        fi
      elif [ -f "$alt" ]; then
        found="$alt"; placement="alternate"; break
      fi
    done
  fi

  if [ -z "$found" ]; then
    emit "$key" "MISSING" "$canonical" "" "" "nothing at the expected path or any known alternate"
    continue
  fi

  # --- collect the files that make up the artifact ------------------------
  files=()
  if [ "$kind" = "dir" ]; then
    while IFS= read -r m; do files+=("$m"); done \
      < <(find "$found" -maxdepth 1 -name "$members" -type f 2>/dev/null | sort)
    if [ ${#files[@]} -eq 0 ]; then
      emit "$key" "MISSING" "$canonical" "" "" "directory exists but holds no $members file"
      continue
    fi
  else
    files=("$found")
  fi

  # --- dates --------------------------------------------------------------
  note=""
  adate=$(git_date "${files[@]}")
  if [ -z "$adate" ]; then
    adate=$(mtime_date "${files[0]}")
    note="untracked by git, date is filesystem mtime"
  fi

  # An idea-brief records a moment and is never stale, so it gets no code date.
  cdate=""
  watch_src=""
  if [ "$key" != "idea-brief" ]; then
    watch=$(watch_for "$key")
    if [ -n "$watch" ]; then
      IFS=',' read -ra wps <<< "$watch"
      cdate=$(git_date "${wps[@]}")
      watch_src="code under ${watch//,/ }"
    else
      cdate="$REPO_CODE_DATE"
      watch_src="code anywhere in the repo"
    fi
  fi

  # --- status -------------------------------------------------------------
  status="PRESENT"
  detail=""

  if [ "$kind" = "file" ] && is_stub "$found"; then
    status="STUB"
    detail="fewer than 5 lines of real content"
  fi

  if [ "$status" = "PRESENT" ] && [ -n "$cdate" ] && [[ "$cdate" > "$adate" ]]; then
    status="STALE"
    detail="$watch_src changed after the artifact"
  fi

  if [ "$placement" = "alternate" ] && [ "$status" = "PRESENT" ]; then
    status="MISPLACED"
    detail="expected at $canonical"
  elif [ "$placement" = "alternate" ]; then
    detail="${detail}; found at a non-standard path, expected $canonical"
  fi

  [ "$kind" = "dir" ] && detail="${detail:+$detail; }${#files[@]} file(s)"
  note="${note:+$note; }$detail"

  emit "$key" "$status" "$found" "$adate" "$cdate" "${note:--}"
done
