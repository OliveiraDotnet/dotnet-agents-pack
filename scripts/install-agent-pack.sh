#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: bash ./scripts/install-agent-pack.sh REPO_PATH [--profile core,web,sqlserver,quality] [--install-global] [--allow-non-git] [--force] [--dry-run]"
}

if [ "$#" -lt 1 ]; then
  usage
  exit 1
fi

repo_input="$1"
shift
profiles=(core)
install_global=false
allow_non_git=false
force=false
dry_run=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile)
      [ "$#" -ge 2 ] || { echo "Missing value for --profile" >&2; exit 1; }
      IFS=',' read -r -a requested <<< "$2"
      for profile in "${requested[@]}"; do
        [ -n "$profile" ] && profiles+=("$profile")
      done
      shift 2
      ;;
    --install-global) install_global=true; shift ;;
    --allow-non-git) allow_non_git=true; shift ;;
    --force) force=true; shift ;;
    --dry-run) dry_run=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
TEMPLATE_ROOT="$PACK_ROOT/repo-template"
MANIFEST="$PACK_ROOT/pack-manifest.txt"
GLOBAL_GUIDANCE="$PACK_ROOT/global/AGENTS.md"

[ -d "$repo_input" ] || { echo "Repo path is not a directory: $repo_input" >&2; exit 1; }
[ -d "$TEMPLATE_ROOT" ] || { echo "Template root is missing: $TEMPLATE_ROOT" >&2; exit 1; }
[ -f "$MANIFEST" ] || { echo "Manifest is missing: $MANIFEST" >&2; exit 1; }

REPO_ROOT="$(cd "$repo_input" && pwd -P)"

is_within() {
  local parent="$1" child="$2"
  [ "$child" != "$parent" ] && [[ "$child" == "$parent/"* ]]
}

if is_within "$TEMPLATE_ROOT" "$REPO_ROOT" || is_within "$REPO_ROOT" "$TEMPLATE_ROOT" || [ "$REPO_ROOT" = "$TEMPLATE_ROOT" ]; then
  echo "Repo path must not overlap the pack template." >&2
  exit 1
fi

if [ "$allow_non_git" != true ]; then
  command -v git >/dev/null 2>&1 || { echo "Git is required; use --allow-non-git explicitly when intentional." >&2; exit 1; }
  git_root="$(git -C "$REPO_ROOT" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$git_root" ] || { echo "Repo path is not a Git repository root; use --allow-non-git explicitly when intentional." >&2; exit 1; }
  git_root="$(cd "$git_root" && pwd -P)"
  [ "$git_root" = "$REPO_ROOT" ] || { echo "Repo path must be the Git root, not a subdirectory: $git_root" >&2; exit 1; }
fi

valid_profile() {
  case "$1" in core|web|sqlserver|quality) return 0 ;; *) return 1 ;; esac
}

contains_profile() {
  local needle="$1"
  for profile in "${profiles[@]}"; do
    [ "$profile" = "$needle" ] && return 0
  done
  return 1
}

unique_profiles=()
for profile in "${profiles[@]}"; do
  valid_profile "$profile" || { echo "Unknown profile: $profile" >&2; exit 1; }
  seen=false
  for existing in "${unique_profiles[@]}"; do [ "$existing" = "$profile" ] && seen=true; done
  [ "$seen" = true ] || unique_profiles+=("$profile")
done
profiles=("${unique_profiles[@]}")

same_content() { cmp -s "$1" "$2"; }
backup_path() {
  local path="$1" timestamp candidate index
  timestamp="$(date +%Y%m%d%H%M%S)"
  candidate="$path.agent-pack.backup-$timestamp"
  index=1
  while [ -e "$candidate" ]; do
    candidate="$path.agent-pack.backup-$timestamp-$index"
    index=$((index + 1))
  done
  printf '%s' "$candidate"
}

action_state=()
action_source=()
action_destination=()
action_original=()

add_action() {
  local source="$1" destination="$2" state="COPY" effective="$2" sidecar
  [ -f "$source" ] || { echo "Manifest source is missing: $source" >&2; exit 1; }

  if [ -e "$destination" ]; then
    if same_content "$source" "$destination"; then
      state="SKIP"
    elif [ "$force" = true ]; then
      state="REPLACE"
    else
      sidecar="$destination.agent-pack.new"
      if [ -e "$sidecar" ]; then
        if same_content "$source" "$sidecar"; then
          state="SKIP"
          effective="$sidecar"
        else
          state="CONFLICT"
          effective="$sidecar"
        fi
      else
        state="SIDECAR"
        effective="$sidecar"
      fi
    fi
  fi

  action_state+=("$state")
  action_source+=("$source")
  action_destination+=("$effective")
  action_original+=("$destination")
}

while IFS='|' read -r component relative; do
  component="${component//[[:space:]]/}"
  relative="${relative# }"
  [ -n "$component" ] || continue
  [[ "$component" = \#* ]] && continue
  contains_profile "$component" || continue
  source="$TEMPLATE_ROOT/$relative"
  destination="$REPO_ROOT/$relative"
  is_within "$TEMPLATE_ROOT" "$source" || { echo "Manifest source escapes template: $relative" >&2; exit 1; }
  is_within "$REPO_ROOT" "$destination" || { echo "Manifest destination escapes repository: $relative" >&2; exit 1; }
  add_action "$source" "$destination"
done < "$MANIFEST"

if [ "$install_global" = true ]; then
  CODEX_HOME_RESOLVED="${CODEX_HOME:-$HOME/.codex}"
  add_action "$GLOBAL_GUIDANCE" "$CODEX_HOME_RESOLVED/AGENTS.md"
fi

echo "Installing .NET Agents Pack profiles: ${profiles[*]}"
[ "$dry_run" = true ] && echo "Dry-run enabled: no files will be written."

copy_count=0
skip_count=0
conflict_count=0
for index in "${!action_state[@]}"; do
  state="${action_state[$index]}"
  source="${action_source[$index]}"
  destination="${action_destination[$index]}"
  original="${action_original[$index]}"
  printf '%-9s %s\n' "$state" "$destination"

  case "$state" in
    SKIP) skip_count=$((skip_count + 1)); continue ;;
    CONFLICT) conflict_count=$((conflict_count + 1)); continue ;;
  esac
  [ "$dry_run" = true ] && continue

  mkdir -p "$(dirname "$destination")"
  if [ "$state" = REPLACE ]; then
    backup="$(backup_path "$original")"
    cp "$original" "$backup"
    printf '%-9s %s\n' "BACKUP" "$backup"
  fi
  cp "$source" "$destination"
  copy_count=$((copy_count + 1))
done

echo "Summary: copied=$copy_count skipped=$skip_count conflicts=$conflict_count"
[ "$conflict_count" -eq 0 ] || echo "Warning: conflicting .agent-pack.new files were preserved; review them before retrying." >&2
