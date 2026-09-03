#!/usr/bin/env bash
set -euo pipefail

LC_ALL=C
export LC_ALL

usage() {
  cat <<'EOF'
Usage:
  bash ./scripts/update-agent-pack.sh REPO_PATH --check [resolutions]
  bash ./scripts/update-agent-pack.sh REPO_PATH --apply [resolutions]

Modes:
  --check                 Print the complete plan without writing.
  --apply                 Apply the plan transactionally.

Selection:
  --integration LIST      Override integrations with codex,claude,grok (comma-separated).

Per-artifact resolutions (repeatable; comma-separated ids are accepted):
  --accept-pack ID        Accept pack replacement or retirement for this artifact.
  --accept-merge ID       Accept an already reviewed manual merge for this artifact.
  --keep-local ID         Preserve a conflicting local artifact and detach it.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

is_semver() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]
}

valid_id() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9._-]*$ ]]
}

valid_relative_path() {
  local path="$1"
  [ -n "$path" ] || return 1
  case "$path" in
    /*|\\*|*\\*|[A-Za-z]:*|.|./*|..|../*|*/.|*/..|*/../*|*'|'*|*$'\t'*|*$'\r'*|*$'\n'*)
      return 1
      ;;
    .git|.git/*|.agent-pack|.agent-pack/*)
      return 1
      ;;
  esac
  return 0
}

casefold_path() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

contains_value() {
  local needle="$1"
  shift
  local value
  for value in "$@"; do
    [ "$value" = "$needle" ] && return 0
  done
  return 1
}

append_unique_profile() {
  local value="$1"
  contains_value "$value" "${selected_profiles[@]}" || selected_profiles+=("$value")
}

append_unique_integration() {
  local value="$1"
  contains_value "$value" "${selected_integrations[@]}" || selected_integrations+=("$value")
}

append_resolution_values() {
  local kind="$1" input="$2" value
  local parsed=()
  IFS=',' read -r -a parsed <<< "$input"
  for value in "${parsed[@]}"; do
    value="$(trim "$value")"
    valid_id "$value" || fail "Invalid artifact id for $kind: $value"
    case "$kind" in
      accept-pack) accept_pack_ids+=("$value") ;;
      accept-merge) accept_merge_ids+=("$value") ;;
      keep-local) keep_local_ids+=("$value") ;;
    esac
  done
}

repo_input=""
mode=""
requested_integrations=()
accept_pack_ids=()
accept_merge_ids=()
keep_local_ids=()

[ "$#" -ge 2 ] || { usage; exit 1; }
repo_input="$1"
shift

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check|--apply)
      [ -z "$mode" ] || fail "Choose exactly one mode: --check or --apply."
      mode="${1#--}"
      shift
      ;;
    --integration)
      [ "$#" -ge 2 ] || fail "Missing value for --integration."
      IFS=',' read -r -a requested <<< "$2"
      for integration in "${requested[@]}"; do
        integration="$(trim "$integration")"
        [ -n "$integration" ] && requested_integrations+=("$integration")
      done
      shift 2
      ;;
    --accept-pack|--accept-merge|--keep-local)
      [ "$#" -ge 2 ] || fail "Missing artifact id for $1."
      append_resolution_values "${1#--}" "$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

if [ "${#requested_integrations[@]}" -gt 0 ]; then
  normalized_integrations=()
  for integration in "${requested_integrations[@]}"; do
    case "$integration" in
      codex|claude|grok) ;;
      *) fail "Unknown integration: $integration. Valid integrations: codex, claude, grok." ;;
    esac
    contains_value "$integration" "${normalized_integrations[@]}" ||
      normalized_integrations+=("$integration")
  done
  requested_integrations=("${normalized_integrations[@]}")
  contains_value "codex" "${requested_integrations[@]}" ||
    fail "The Codex integration is mandatory. Include codex when overriding integrations."
fi

[ -n "$mode" ] || fail "Choose exactly one mode: --check or --apply."
[ -d "$repo_input" ] || fail "Repo path is not a directory: $repo_input"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
TEMPLATE_ROOT="$PACK_ROOT/repo-template"
VERSION_FILE="$PACK_ROOT/pack-version.txt"
MANIFEST_FILE="$PACK_ROOT/pack-manifest.txt"
ARTIFACTS_FILE="$PACK_ROOT/pack-artifacts.txt"
COMPAT_ROOT="$PACK_ROOT/compat/releases"
REPO_ROOT="$(cd "$repo_input" && pwd -P)"
STATE_DIR="$REPO_ROOT/.agent-pack"
STATE_FILE="$STATE_DIR/state.txt"
RUNTIME_DIR="$STATE_DIR/.runtime"

is_within() {
  local parent="$1" child="$2"
  [ "$child" != "$parent" ] && [[ "$child" == "$parent/"* ]]
}

if [ "$REPO_ROOT" = "$TEMPLATE_ROOT" ] ||
   is_within "$TEMPLATE_ROOT" "$REPO_ROOT" ||
   is_within "$REPO_ROOT" "$TEMPLATE_ROOT"; then
  fail "Repo path must not overlap the pack template."
fi

[ -d "$TEMPLATE_ROOT" ] || fail "Template root is missing: $TEMPLATE_ROOT"
[ -f "$VERSION_FILE" ] || fail "Pack version file is missing: $VERSION_FILE"
[ -f "$MANIFEST_FILE" ] || fail "Pack manifest is missing: $MANIFEST_FILE"
[ -f "$ARTIFACTS_FILE" ] || fail "Pack artifacts file is missing: $ARTIFACTS_FILE"
[ ! -L "$VERSION_FILE" ] || fail "Pack version file must not be a symlink."
[ ! -L "$MANIFEST_FILE" ] || fail "Pack manifest must not be a symlink."
[ ! -L "$ARTIFACTS_FILE" ] || fail "Pack artifacts file must not be a symlink."

if [ -e "$STATE_DIR" ] || [ -L "$STATE_DIR" ]; then
  [ -d "$STATE_DIR" ] && [ ! -L "$STATE_DIR" ] ||
    fail "State path must be a regular directory, not a symlink: $STATE_DIR"
fi
if [ -e "$STATE_FILE" ] || [ -L "$STATE_FILE" ]; then
  [ -f "$STATE_FILE" ] && [ ! -L "$STATE_FILE" ] ||
    fail "State file must be a regular file, not a symlink: $STATE_FILE"
fi
if [ -e "$RUNTIME_DIR" ] || [ -L "$RUNTIME_DIR" ]; then
  [ -d "$RUNTIME_DIR" ] && [ ! -L "$RUNTIME_DIR" ] ||
    fail "Runtime path must be a regular directory, not a symlink: $RUNTIME_DIR"
fi
if [ -e "$RUNTIME_DIR/.gitignore" ] || [ -L "$RUNTIME_DIR/.gitignore" ]; then
  [ -f "$RUNTIME_DIR/.gitignore" ] && [ ! -L "$RUNTIME_DIR/.gitignore" ] ||
    fail "Runtime .gitignore must be a regular file, not a symlink."
  runtime_ignore_content="$(sed $'s/\r$//' "$RUNTIME_DIR/.gitignore")"
  [ "$runtime_ignore_content" = $'*\n!.gitignore' ] ||
    fail "Runtime .gitignore has unexpected local content: $RUNTIME_DIR/.gitignore"
fi

HASH_TOOL=""
if command -v sha256sum >/dev/null 2>&1; then
  HASH_TOOL="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
  HASH_TOOL="shasum"
elif command -v openssl >/dev/null 2>&1; then
  HASH_TOOL="openssl"
else
  fail "SHA-256 support is required (sha256sum, shasum, or openssl)."
fi

normalized_stream() {
  local file="$1" prefix
  prefix="$(dd if="$file" bs=1 count=3 2>/dev/null | od -An -tx1 | tr -d ' \r\n')"
  if [ "$prefix" = "efbbbf" ]; then
    dd if="$file" bs=1 skip=3 2>/dev/null
  else
    cat "$file"
  fi | sed $'s/\r$//' | tr '\r' '\n'
}

HASH_VALUE=""
hash_file() {
  local file="$1" output
  [ -f "$file" ] && [ ! -L "$file" ] || fail "Cannot hash a non-regular file: $file"
  case "$HASH_TOOL" in
    sha256sum)
      output="$(normalized_stream "$file" | sha256sum)"
      HASH_VALUE="${output%% *}"
      ;;
    shasum)
      output="$(normalized_stream "$file" | shasum -a 256)"
      HASH_VALUE="${output%% *}"
      ;;
    openssl)
      output="$(normalized_stream "$file" | openssl dgst -sha256)"
      HASH_VALUE="${output##* }"
      ;;
  esac
  HASH_VALUE="$(printf '%s' "$HASH_VALUE" | tr '[:upper:]' '[:lower:]')"
  [[ "$HASH_VALUE" =~ ^[0-9a-f]{64}$ ]] || fail "Invalid SHA-256 result for: $file"
}

validate_target_path() {
  local relative="$1" current="$REPO_ROOT" part parent physical
  local parts=()
  valid_relative_path "$relative" || fail "Unsafe repository-relative path: $relative"
  IFS='/' read -r -a parts <<< "$relative"
  for part in "${parts[@]}"; do
    current="$current/$part"
    [ ! -L "$current" ] || fail "Managed path crosses a symlink: $relative"
  done
  parent="$(dirname "$REPO_ROOT/$relative")"
  while [ ! -d "$parent" ]; do
    [ "$parent" != "$REPO_ROOT" ] || break
    parent="$(dirname "$parent")"
  done
  physical="$(cd "$parent" && pwd -P)"
  if [ "$physical" != "$REPO_ROOT" ] && ! is_within "$REPO_ROOT" "$physical"; then
    fail "Managed path escapes the repository through a link or junction: $relative"
  fi
  if [ -e "$REPO_ROOT/$relative" ]; then
    [ -f "$REPO_ROOT/$relative" ] || fail "Managed destination is not a regular file: $relative"
  fi
}

validate_source_path() {
  local relative="$1" source parent physical
  valid_relative_path "$relative" || fail "Unsafe template-relative path: $relative"
  source="$TEMPLATE_ROOT/$relative"
  [ -f "$source" ] && [ ! -L "$source" ] || fail "Manifest source is missing or not regular: $relative"
  parent="$(cd "$(dirname "$source")" && pwd -P)"
  physical="$(cd "$parent" && pwd -P)"
  if [ "$physical" != "$TEMPLATE_ROOT" ] && ! is_within "$TEMPLATE_ROOT" "$physical"; then
    fail "Manifest source escapes the template: $relative"
  fi
}

PACK_VERSION=""
useful_versions=0
while IFS= read -r line || [ -n "$line" ]; do
  line="$(trim "$line")"
  [ -n "$line" ] || continue
  [[ "$line" = \#* ]] && continue
  PACK_VERSION="$line"
  useful_versions=$((useful_versions + 1))
done < "$VERSION_FILE"
[ "$useful_versions" -eq 1 ] || fail "pack-version.txt must contain exactly one useful line."
is_semver "$PACK_VERSION" || fail "Invalid pack version: $PACK_VERSION"

manifest_components=()
manifest_sources=()
manifest_destinations=()
manifest_destination_keys=()
while IFS= read -r line || [ -n "$line" ]; do
  line="$(trim "$line")"
  [ -n "$line" ] || continue
  [[ "$line" = \#* ]] && continue
  separators="${line//[^|]/}"
  [ "${#separators}" -ge 1 ] && [ "${#separators}" -le 2 ] ||
    fail "Invalid manifest line: $line"
  component=""
  source_relative=""
  destination_relative=""
  IFS='|' read -r component source_relative destination_relative <<< "$line"
  component="$(trim "$component")"
  source_relative="$(trim "$source_relative")"
  destination_relative="$(trim "${destination_relative:-}")"
  [ "${#separators}" -eq 2 ] || destination_relative="$source_relative"
  valid_id "$component" || fail "Invalid manifest component: $component"
  validate_source_path "$source_relative"
  validate_target_path "$destination_relative"
  destination_key="$(casefold_path "$destination_relative")"
  contains_value "$destination_key" "${manifest_destination_keys[@]}" &&
    fail "Manifest destination is duplicated or collides by case: $destination_relative"
  manifest_components+=("$component")
  manifest_sources+=("$source_relative")
  manifest_destinations+=("$destination_relative")
  manifest_destination_keys+=("$destination_key")
done < "$MANIFEST_FILE"

artifact_ids=()
artifact_destinations=()
artifact_destination_keys=()
artifact_ownerships=()
artifact_components=()
artifact_sources=()
artifact_hashes=()

find_manifest_destination() {
  local needle="$1" index
  FOUND_INDEX=-1
  for index in "${!manifest_destinations[@]}"; do
    if [ "${manifest_destinations[$index]}" = "$needle" ]; then
      FOUND_INDEX="$index"
      return
    fi
  done
}

while IFS= read -r line || [ -n "$line" ]; do
  line="$(trim "$line")"
  [ -n "$line" ] || continue
  [[ "$line" = \#* ]] && continue
  separators="${line//[^|]/}"
  [ "${#separators}" -eq 2 ] || fail "Invalid artifact line: $line"
  artifact_id=""
  destination_relative=""
  ownership=""
  IFS='|' read -r artifact_id destination_relative ownership <<< "$line"
  artifact_id="$(trim "$artifact_id")"
  destination_relative="$(trim "$destination_relative")"
  ownership="$(trim "$ownership")"
  valid_id "$artifact_id" || fail "Invalid artifact id: $artifact_id"
  validate_target_path "$destination_relative"
  case "$ownership" in managed|merge|seed) ;; *) fail "Invalid ownership for $artifact_id: $ownership" ;; esac
  contains_value "$artifact_id" "${artifact_ids[@]}" && fail "Duplicate artifact id: $artifact_id"
  destination_key="$(casefold_path "$destination_relative")"
  contains_value "$destination_key" "${artifact_destination_keys[@]}" &&
    fail "Artifact destination is duplicated or collides by case: $destination_relative"
  find_manifest_destination "$destination_relative"
  [ "$FOUND_INDEX" -ge 0 ] || fail "Artifact destination is not present in pack-manifest.txt: $destination_relative"
  source_relative="${manifest_sources[$FOUND_INDEX]}"
  hash_file "$TEMPLATE_ROOT/$source_relative"
  artifact_ids+=("$artifact_id")
  artifact_destinations+=("$destination_relative")
  artifact_destination_keys+=("$destination_key")
  artifact_ownerships+=("$ownership")
  artifact_components+=("${manifest_components[$FOUND_INDEX]}")
  artifact_sources+=("$source_relative")
  artifact_hashes+=("$HASH_VALUE")
done < "$ARTIFACTS_FILE"

for destination_relative in "${manifest_destinations[@]}"; do
  destination_key="$(casefold_path "$destination_relative")"
  contains_value "$destination_key" "${artifact_destination_keys[@]}" ||
    fail "Manifest destination is missing from pack-artifacts.txt: $destination_relative"
done

compat_versions=()
compat_ids=()
compat_destinations=()
compat_hashes=()
if [ -d "$COMPAT_ROOT" ]; then
  for compat_file in "$COMPAT_ROOT"/*.txt; do
    [ -f "$compat_file" ] || continue
    [ ! -L "$compat_file" ] || fail "Compatibility catalog must not be a symlink: $compat_file"
    compat_version="$(basename "$compat_file" .txt)"
    is_semver "$compat_version" || fail "Invalid compatibility catalog version: $compat_version"
    while IFS= read -r line || [ -n "$line" ]; do
      line="$(trim "$line")"
      [ -n "$line" ] || continue
      [[ "$line" = \#* ]] && continue
      separators="${line//[^|]/}"
      [ "${#separators}" -eq 2 ] || fail "Invalid compatibility line in $compat_file: $line"
      artifact_id=""
      destination_relative=""
      baseline_hash=""
      IFS='|' read -r artifact_id destination_relative baseline_hash <<< "$line"
      artifact_id="$(trim "$artifact_id")"
      destination_relative="$(trim "$destination_relative")"
      baseline_hash="$(trim "$baseline_hash")"
      valid_id "$artifact_id" || fail "Invalid compatibility artifact id: $artifact_id"
      validate_target_path "$destination_relative"
      baseline_hash="$(printf '%s' "$baseline_hash" | tr '[:upper:]' '[:lower:]')"
      [[ "$baseline_hash" =~ ^[0-9a-f]{64}$ ]] ||
        fail "Invalid compatibility hash for $artifact_id in $compat_file"
      duplicate=false
      for index in "${!compat_ids[@]}"; do
        if [ "${compat_versions[$index]}" = "$compat_version" ] &&
           [ "${compat_ids[$index]}" = "$artifact_id" ] &&
           [ "${compat_destinations[$index]}" = "$destination_relative" ]; then
          duplicate=true
        fi
      done
      [ "$duplicate" = false ] ||
        fail "Duplicate compatibility artifact $artifact_id for version $compat_version"
      compat_versions+=("$compat_version")
      compat_ids+=("$artifact_id")
      compat_destinations+=("$destination_relative")
      compat_hashes+=("$baseline_hash")
    done < "$compat_file"
  done
fi

find_current_artifact() {
  local needle_id="$1" needle_destination="$2" index
  FOUND_INDEX=-1
  for index in "${!artifact_ids[@]}"; do
    if [ "${artifact_ids[$index]}" = "$needle_id" ] &&
       [ "${artifact_destinations[$index]}" = "$needle_destination" ]; then
      FOUND_INDEX="$index"
      return
    fi
  done
}

KNOWN_VERSION=""
find_known_hash_version() {
  local needle_id="$1" needle_destination="$2" needle_hash="$3" index
  KNOWN_VERSION=""
  find_current_artifact "$needle_id" "$needle_destination"
  if [ "$FOUND_INDEX" -ge 0 ] && [ "${artifact_hashes[$FOUND_INDEX]}" = "$needle_hash" ]; then
    KNOWN_VERSION="$PACK_VERSION"
    return
  fi
  for index in "${!compat_ids[@]}"; do
    if [ "${compat_ids[$index]}" = "$needle_id" ] &&
       [ "${compat_destinations[$index]}" = "$needle_destination" ] &&
       [ "${compat_hashes[$index]}" = "$needle_hash" ]; then
      KNOWN_VERSION="${compat_versions[$index]}"
      return
    fi
  done
}

trusted_baseline() {
  local version="$1" needle_id="$2" needle_destination="$3" needle_hash="$4" index
  if [ "$version" = "$PACK_VERSION" ]; then
    find_current_artifact "$needle_id" "$needle_destination"
    [ "$FOUND_INDEX" -ge 0 ] &&
      [ "${artifact_hashes[$FOUND_INDEX]}" = "$needle_hash" ] && return 0
  fi
  for index in "${!compat_ids[@]}"; do
    if [ "${compat_versions[$index]}" = "$version" ] &&
       [ "${compat_ids[$index]}" = "$needle_id" ] &&
       [ "${compat_destinations[$index]}" = "$needle_destination" ] &&
       [ "${compat_hashes[$index]}" = "$needle_hash" ]; then
      return 0
    fi
  done
  return 1
}

state_exists=false
state_version=""
state_profiles=()
state_integrations=()
state_ids=()
state_destinations=()
state_ownerships=()
state_baseline_versions=()
state_baseline_hashes=()
state_modes=()
state_local_hashes=()

if [ -f "$STATE_FILE" ]; then
  state_exists=true
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(trim "$line")"
    [ -n "$line" ] || continue
    [[ "$line" = \#* ]] && continue
    record_type="${line%%|*}"
    case "$record_type" in
      version)
        separators="${line//[^|]/}"
        [ "${#separators}" -eq 1 ] || fail "Invalid state version line: $line"
        value="${line#*|}"
        value="$(trim "$value")"
        [ -z "$state_version" ] || fail "State contains more than one version line."
        is_semver "$value" || fail "Invalid state version: $value"
        state_version="$value"
        ;;
      profile)
        separators="${line//[^|]/}"
        [ "${#separators}" -eq 1 ] || fail "Invalid state profile line: $line"
        value="$(trim "${line#*|}")"
        valid_id "$value" || fail "Invalid state profile: $value"
        contains_value "$value" "${state_profiles[@]}" && fail "Duplicate state profile: $value"
        state_profiles+=("$value")
        ;;
      integration)
        separators="${line//[^|]/}"
        [ "${#separators}" -eq 1 ] || fail "Invalid state integration line: $line"
        value="$(trim "${line#*|}")"
        case "$value" in codex|claude|grok) ;; *) fail "Invalid state integration: $value" ;; esac
        contains_value "$value" "${state_integrations[@]}" && fail "Duplicate state integration: $value"
        state_integrations+=("$value")
        ;;
      artifact)
        separators="${line//[^|]/}"
        [ "${#separators}" -eq 7 ] || fail "Invalid state artifact line: $line"
        artifact_id=""
        destination_relative=""
        ownership=""
        baseline_version=""
        baseline_hash=""
        artifact_mode=""
        local_hash=""
        IFS='|' read -r _ artifact_id destination_relative ownership baseline_version baseline_hash artifact_mode local_hash <<< "$line"
        artifact_id="$(trim "$artifact_id")"
        destination_relative="$(trim "$destination_relative")"
        ownership="$(trim "$ownership")"
        baseline_version="$(trim "$baseline_version")"
        baseline_hash="$(trim "$baseline_hash")"
        artifact_mode="$(trim "$artifact_mode")"
        local_hash="$(trim "$local_hash")"
        valid_id "$artifact_id" || fail "Invalid state artifact id: $artifact_id"
        validate_target_path "$destination_relative"
        case "$ownership" in managed|merge|seed) ;; *) fail "Invalid state ownership: $ownership" ;; esac
        case "$artifact_mode" in
          tracked)
            is_semver "$baseline_version" || fail "Invalid baseline version for $artifact_id: $baseline_version"
            baseline_hash="$(printf '%s' "$baseline_hash" | tr '[:upper:]' '[:lower:]')"
            [[ "$baseline_hash" =~ ^[0-9a-f]{64}$ ]] || fail "Invalid baseline hash for $artifact_id"
            [ "$local_hash" = "-" ] || fail "Tracked artifact must not contain a local hash: $artifact_id"
            trusted_baseline "$baseline_version" "$artifact_id" "$destination_relative" "$baseline_hash" ||
              fail "State baseline is not trusted by the current or compatibility catalogs: $artifact_id"
            ;;
          merged)
            [ "$ownership" = "merge" ] || fail "Only merge artifacts may use merged mode: $artifact_id"
            is_semver "$baseline_version" || fail "Invalid merged baseline version for $artifact_id: $baseline_version"
            baseline_hash="$(printf '%s' "$baseline_hash" | tr '[:upper:]' '[:lower:]')"
            local_hash="$(printf '%s' "$local_hash" | tr '[:upper:]' '[:lower:]')"
            [[ "$baseline_hash" =~ ^[0-9a-f]{64}$ ]] || fail "Invalid merged baseline hash for $artifact_id"
            [[ "$local_hash" =~ ^[0-9a-f]{64}$ ]] || fail "Invalid merged local hash for $artifact_id"
            trusted_baseline "$baseline_version" "$artifact_id" "$destination_relative" "$baseline_hash" ||
              fail "Merged baseline is not trusted by the current or compatibility catalogs: $artifact_id"
            ;;
          keep-local|deleted-local)
            [ "$baseline_version" = "-" ] && [ "$baseline_hash" = "-" ] ||
              fail "Detached artifact must use '-' for baseline version and hash: $artifact_id"
            if [ "$artifact_mode" = "deleted-local" ]; then
              [ "$local_hash" = "-" ] || fail "Deleted-local artifact must not contain a local hash: $artifact_id"
            elif [ "$local_hash" != "-" ]; then
              local_hash="$(printf '%s' "$local_hash" | tr '[:upper:]' '[:lower:]')"
              [[ "$local_hash" =~ ^[0-9a-f]{64}$ ]] ||
                fail "Invalid keep-local hash for $artifact_id"
            fi
            ;;
          *)
            fail "Invalid state mode for $artifact_id: $artifact_mode"
            ;;
        esac
        contains_value "$artifact_id" "${state_ids[@]}" && fail "Duplicate state artifact id: $artifact_id"
        known_path=false
        find_current_artifact "$artifact_id" "$destination_relative"
        [ "$FOUND_INDEX" -lt 0 ] || known_path=true
        if [ "$known_path" = false ]; then
          for known_index in "${!compat_ids[@]}"; do
            if [ "${compat_ids[$known_index]}" = "$artifact_id" ] &&
               [ "${compat_destinations[$known_index]}" = "$destination_relative" ]; then
              known_path=true
            fi
          done
        fi
        [ "$known_path" = true ] ||
          fail "State artifact is not present in current or historical trusted metadata: $artifact_id"
        find_current_artifact "$artifact_id" "$destination_relative"
        state_ids+=("$artifact_id")
        state_destinations+=("$destination_relative")
        state_ownerships+=("$ownership")
        state_baseline_versions+=("$baseline_version")
        state_baseline_hashes+=("$baseline_hash")
        state_modes+=("$artifact_mode")
        state_local_hashes+=("$local_hash")
        ;;
      *)
        fail "Unknown state record: $record_type"
        ;;
    esac
  done < "$STATE_FILE"
  [ -n "$state_version" ] || fail "State is missing the pack version."
  [ "${#state_profiles[@]}" -gt 0 ] || fail "State is missing selected profiles."
  [ "${#state_integrations[@]}" -gt 0 ] || fail "State is missing selected integrations."
fi

selected_profiles=()
selected_integrations=()
if [ "$state_exists" = true ]; then
  selected_profiles=("${state_profiles[@]}")
  selected_integrations=("${state_integrations[@]}")
else
  for index in "${!artifact_ids[@]}"; do
    destination="$REPO_ROOT/${artifact_destinations[$index]}"
    if [ -f "$destination" ] && [ ! -L "$destination" ]; then
      hash_file "$destination"
      find_known_hash_version "${artifact_ids[$index]}" "${artifact_destinations[$index]}" "$HASH_VALUE"
      if [ -n "$KNOWN_VERSION" ]; then
        component="${artifact_components[$index]}"
        if [[ "$component" = claude-* ]]; then
          append_unique_profile "${component#claude-}"
          append_unique_integration "codex"
          append_unique_integration "claude"
        elif [[ "$component" = grok-* ]]; then
          append_unique_profile "${component#grok-}"
          append_unique_integration "codex"
          append_unique_integration "grok"
        else
          append_unique_profile "$component"
          append_unique_integration "codex"
        fi
      fi
    fi
  done
  if [ "${#selected_profiles[@]}" -eq 0 ]; then
    echo "No trusted legacy Agent Pack installation could be inferred." >&2
    echo "Use the regular installer for a fresh installation." >&2
    exit 3
  fi
fi

if [ "${#requested_integrations[@]}" -gt 0 ]; then
  selected_integrations=("${requested_integrations[@]}")
fi

artifact_is_selected() {
  local component="$1" profile
  if [[ "$component" = claude-* ]]; then
    profile="${component#claude-}"
    contains_value "claude" "${selected_integrations[@]}" &&
      contains_value "$profile" "${selected_profiles[@]}"
  elif [[ "$component" = grok-* ]]; then
    profile="${component#grok-}"
    contains_value "grok" "${selected_integrations[@]}" &&
      contains_value "$profile" "${selected_profiles[@]}"
  else
    contains_value "codex" "${selected_integrations[@]}" &&
      contains_value "$component" "${selected_profiles[@]}"
  fi
}

find_state_artifact() {
  local needle_id="$1" needle_destination="$2" index
  FOUND_INDEX=-1
  for index in "${!state_ids[@]}"; do
    if [ "${state_ids[$index]}" = "$needle_id" ] &&
       [ "${state_destinations[$index]}" = "$needle_destination" ]; then
      FOUND_INDEX="$index"
      return
    fi
  done
}

find_state_artifact_by_id() {
  local needle_id="$1" index
  FOUND_INDEX=-1
  for index in "${!state_ids[@]}"; do
    if [ "${state_ids[$index]}" = "$needle_id" ]; then
      FOUND_INDEX="$index"
      return
    fi
  done
}

resolution_for() {
  local artifact_id="$1" ownership="$2" count=0
  RESOLUTION=""
  contains_value "$artifact_id" "${accept_pack_ids[@]}" && count=$((count + 1))
  contains_value "$artifact_id" "${accept_merge_ids[@]}" && count=$((count + 1))
  contains_value "$artifact_id" "${keep_local_ids[@]}" && count=$((count + 1))
  [ "$count" -le 1 ] || fail "Artifact has conflicting resolutions: $artifact_id"
  if contains_value "$artifact_id" "${keep_local_ids[@]}"; then
    RESOLUTION="keep"
    used_keep_local_ids+=("$artifact_id")
  elif contains_value "$artifact_id" "${accept_pack_ids[@]}"; then
    [ "$ownership" != "seed" ] || fail "--accept-pack is invalid for seed artifacts: $artifact_id"
    RESOLUTION="write-pack"
    used_accept_pack_ids+=("$artifact_id")
  elif contains_value "$artifact_id" "${accept_merge_ids[@]}"; then
    [ "$ownership" = "merge" ] || fail "--accept-merge is only valid for merge artifacts: $artifact_id"
    RESOLUTION="accept-merge"
    used_accept_merge_ids+=("$artifact_id")
  fi
}

removal_resolution_for() {
  local artifact_id="$1" count=0
  RESOLUTION=""
  contains_value "$artifact_id" "${accept_pack_ids[@]}" && count=$((count + 1))
  contains_value "$artifact_id" "${accept_merge_ids[@]}" && count=$((count + 1))
  contains_value "$artifact_id" "${keep_local_ids[@]}" && count=$((count + 1))
  [ "$count" -le 1 ] || fail "Artifact has conflicting resolutions: $artifact_id"
  if contains_value "$artifact_id" "${accept_merge_ids[@]}"; then
    fail "--accept-merge is invalid after an artifact was removed upstream: $artifact_id"
  elif contains_value "$artifact_id" "${accept_pack_ids[@]}"; then
    RESOLUTION="pack"
    used_accept_pack_ids+=("$artifact_id")
  elif contains_value "$artifact_id" "${keep_local_ids[@]}"; then
    RESOLUTION="keep"
    used_keep_local_ids+=("$artifact_id")
  fi
}

action_ids=()
action_kinds=()
action_destinations=()
action_sources=()
action_ownerships=()
action_expected_hashes=()
receipt_ids=()
receipt_destinations=()
receipt_ownerships=()
receipt_versions=()
receipt_hashes=()
receipt_modes=()
receipt_local_hashes=()
used_accept_pack_ids=()
used_accept_merge_ids=()
used_keep_local_ids=()
conflict_count=0

add_action() {
  action_ids+=("$1")
  action_kinds+=("$2")
  action_destinations+=("$3")
  action_sources+=("$4")
  action_ownerships+=("$5")
  action_expected_hashes+=("$6")
}

add_receipt() {
  local receipt_index
  for receipt_index in "${!receipt_ids[@]}"; do
    if [ "${receipt_ids[$receipt_index]}" = "$1" ]; then
      receipt_destinations[$receipt_index]="$2"
      receipt_ownerships[$receipt_index]="$3"
      receipt_versions[$receipt_index]="$4"
      receipt_hashes[$receipt_index]="$5"
      receipt_modes[$receipt_index]="${6:-tracked}"
      receipt_local_hashes[$receipt_index]="${7:--}"
      return
    fi
  done
  receipt_ids+=("$1")
  receipt_destinations+=("$2")
  receipt_ownerships+=("$3")
  receipt_versions+=("$4")
  receipt_hashes+=("$5")
  receipt_modes+=("${6:-tracked}")
  receipt_local_hashes+=("${7:--}")
}

for index in "${!artifact_ids[@]}"; do
  component="${artifact_components[$index]}"
  artifact_is_selected "$component" || continue
  artifact_id="${artifact_ids[$index]}"
  destination_relative="${artifact_destinations[$index]}"
  ownership="${artifact_ownerships[$index]}"
  source_relative="${artifact_sources[$index]}"
  new_hash="${artifact_hashes[$index]}"
  destination="$REPO_ROOT/$destination_relative"
  validate_target_path "$destination_relative"
  find_state_artifact_by_id "$artifact_id"
  state_index="$FOUND_INDEX"
  current_exists=false
  current_hash="ABSENT"
  if [ -f "$destination" ]; then
    current_exists=true
    hash_file "$destination"
    current_hash="$HASH_VALUE"
  fi

  if [ "$state_index" -ge 0 ] &&
     [ "${state_destinations[$state_index]}" != "$destination_relative" ]; then
    old_destination_relative="${state_destinations[$state_index]}"
    old_destination="$REPO_ROOT/$old_destination_relative"
    old_ownership="${state_ownerships[$state_index]}"
    old_mode="${state_modes[$state_index]}"
    old_baseline_hash="${state_baseline_hashes[$state_index]}"
    validate_target_path "$old_destination_relative"
    if [ "$(casefold_path "$old_destination_relative")" = "$(casefold_path "$destination_relative")" ]; then
      fail "Case-only artifact rename requires a platform-specific manual migration: $artifact_id"
    fi
    old_exists=false
    old_hash="ABSENT"
    if [ -f "$old_destination" ]; then
      old_exists=true
      hash_file "$old_destination"
      old_hash="$HASH_VALUE"
    fi

    resolution_for "$artifact_id" "$ownership"
    case "$RESOLUTION" in
      write-pack)
        if [ "$old_exists" = true ]; then
          add_action "$artifact_id" "RETIRE_RENAMED" "$old_destination_relative" "" "$old_ownership" "$old_hash"
        fi
        if [ "$current_exists" = false ]; then
          add_action "$artifact_id" "ADD_MOVED" "$destination_relative" "$source_relative" "$ownership" "ABSENT"
        elif [ "$current_hash" = "$new_hash" ]; then
          add_action "$artifact_id" "ADOPT_MOVED" "$destination_relative" "" "$ownership" "$current_hash"
        else
          add_action "$artifact_id" "WRITE_PACK" "$destination_relative" "$source_relative" "$ownership" "$current_hash"
        fi
        add_receipt "$artifact_id" "$destination_relative" "$ownership" "$PACK_VERSION" "$new_hash"
        continue
        ;;
      accept-merge)
        [ "$current_exists" = true ] ||
          fail "--accept-merge for a rename requires a manually merged file at the new destination: $artifact_id"
        if [ "$old_exists" = true ]; then
          add_action "$artifact_id" "RETIRE_RENAMED" "$old_destination_relative" "" "$old_ownership" "$old_hash"
        fi
        add_action "$artifact_id" "ACCEPT_MERGE" "$destination_relative" "" "$ownership" "$current_hash"
        add_receipt "$artifact_id" "$destination_relative" "$ownership" "$PACK_VERSION" "$new_hash" "merged" "$current_hash"
        continue
        ;;
      keep)
        if [ "$old_exists" = true ]; then
          add_action "$artifact_id" "KEEP_LOCAL_RENAME" "$old_destination_relative" "" "$old_ownership" "$old_hash"
          add_receipt "$artifact_id" "$old_destination_relative" "$old_ownership" "-" "-" "keep-local" "$old_hash"
        else
          add_action "$artifact_id" "KEEP_LOCAL_RENAME" "$old_destination_relative" "" "$old_ownership" "ABSENT"
          add_receipt "$artifact_id" "$old_destination_relative" "$old_ownership" "-" "-" "deleted-local" "-"
        fi
        continue
        ;;
    esac

    if [ "$ownership" = "seed" ] ||
       [ "$old_mode" = "keep-local" ] ||
       [ "$old_mode" = "deleted-local" ]; then
      if [ "$old_exists" = true ]; then
        add_action "$artifact_id" "KEEP_LOCAL_RENAME" "$old_destination_relative" "" "$old_ownership" "$old_hash"
        add_receipt "$artifact_id" "$old_destination_relative" "$old_ownership" "-" "-" "keep-local" "$old_hash"
      else
        add_action "$artifact_id" "KEEP_LOCAL_RENAME" "$old_destination_relative" "" "$old_ownership" "ABSENT"
        add_receipt "$artifact_id" "$old_destination_relative" "$old_ownership" "-" "-" "deleted-local" "-"
      fi
      continue
    fi

    if [ "$old_mode" = "tracked" ] &&
       [ "$old_exists" = true ] &&
       [ "$old_hash" = "$old_baseline_hash" ] &&
       [ "$current_exists" = false ]; then
      add_action "$artifact_id" "RETIRE_RENAMED" "$old_destination_relative" "" "$old_ownership" "$old_hash"
      add_action "$artifact_id" "ADD_MOVED" "$destination_relative" "$source_relative" "$ownership" "ABSENT"
      add_receipt "$artifact_id" "$destination_relative" "$ownership" "$PACK_VERSION" "$new_hash"
    elif [ "$old_mode" = "tracked" ] &&
         [ "$old_exists" = true ] &&
         [ "$old_hash" = "$old_baseline_hash" ] &&
         [ "$current_exists" = true ] &&
         [ "$current_hash" = "$new_hash" ]; then
      add_action "$artifact_id" "RETIRE_RENAMED" "$old_destination_relative" "" "$old_ownership" "$old_hash"
      add_action "$artifact_id" "ADOPT_MOVED" "$destination_relative" "" "$ownership" "$current_hash"
      add_receipt "$artifact_id" "$destination_relative" "$ownership" "$PACK_VERSION" "$new_hash"
    elif [ "$old_exists" = false ] &&
         [ "$current_exists" = true ] &&
         [ "$current_hash" = "$new_hash" ]; then
      add_action "$artifact_id" "ADOPT_MOVED" "$destination_relative" "" "$ownership" "$current_hash"
      add_receipt "$artifact_id" "$destination_relative" "$ownership" "$PACK_VERSION" "$new_hash"
    else
      add_action "$artifact_id" "CONFLICT_RENAME" "$old_destination_relative -> $destination_relative" "" "$ownership" "$current_hash"
      conflict_count=$((conflict_count + 1))
    fi
    continue
  fi

  if [ "$ownership" = "seed" ]; then
    resolution_for "$artifact_id" "$ownership"
    if [ "$current_exists" = false ]; then
      if [ "$state_index" -ge 0 ]; then
        add_action "$artifact_id" "RETAIN_SEED_DELETED" "$destination_relative" "" "$ownership" "ABSENT"
        add_receipt "$artifact_id" "$destination_relative" "$ownership" "-" "-" "deleted-local" "-"
      else
        add_action "$artifact_id" "ADD_SEED" "$destination_relative" "$source_relative" "$ownership" "ABSENT"
        add_receipt "$artifact_id" "$destination_relative" "$ownership" "-" "-" "keep-local" "$new_hash"
      fi
    else
      add_action "$artifact_id" "RETAIN_SEED" "$destination_relative" "" "$ownership" "$current_hash"
      add_receipt "$artifact_id" "$destination_relative" "$ownership" "-" "-" "keep-local" "$current_hash"
    fi
    continue
  fi

  resolution_for "$artifact_id" "$ownership"
  case "$RESOLUTION" in
    keep)
      if [ "$current_exists" = true ]; then
        add_action "$artifact_id" "KEEP_LOCAL" "$destination_relative" "" "$ownership" "$current_hash"
        add_receipt "$artifact_id" "$destination_relative" "$ownership" "-" "-" "keep-local" "$current_hash"
      else
        add_action "$artifact_id" "KEEP_LOCAL" "$destination_relative" "" "$ownership" "ABSENT"
        add_receipt "$artifact_id" "$destination_relative" "$ownership" "-" "-" "deleted-local" "-"
      fi
      continue
      ;;
    accept-merge)
      [ "$current_exists" = true ] ||
        fail "--accept-merge requires an existing manually reviewed file: $artifact_id"
      add_action "$artifact_id" "ACCEPT_MERGE" "$destination_relative" "" "$ownership" "$current_hash"
      add_receipt "$artifact_id" "$destination_relative" "$ownership" "$PACK_VERSION" "$new_hash" "merged" "$current_hash"
      continue
      ;;
    write-pack)
      if [ "$current_exists" = false ]; then
        add_action "$artifact_id" "RESTORE" "$destination_relative" "$source_relative" "$ownership" "ABSENT"
      elif [ "$current_hash" = "$new_hash" ]; then
        add_action "$artifact_id" "ADOPT_EXACT" "$destination_relative" "" "$ownership" "$current_hash"
      else
        add_action "$artifact_id" "WRITE_PACK" "$destination_relative" "$source_relative" "$ownership" "$current_hash"
      fi
      add_receipt "$artifact_id" "$destination_relative" "$ownership" "$PACK_VERSION" "$new_hash"
      continue
      ;;
  esac

  if [ "$state_index" -ge 0 ]; then
    baseline_version="${state_baseline_versions[$state_index]}"
    baseline_hash="${state_baseline_hashes[$state_index]}"
    state_mode="${state_modes[$state_index]}"
    state_local_hash="${state_local_hashes[$state_index]}"

    if [ "$state_mode" = "keep-local" ] || [ "$state_mode" = "deleted-local" ]; then
      resolution_for "$artifact_id" "$ownership"
      if [ "$RESOLUTION" = "pack" ]; then
        if [ "$ownership" = "merge" ]; then
          [ "$current_exists" = true ] ||
            fail "--accept-merge requires an existing manually reviewed file: $artifact_id"
          add_action "$artifact_id" "ACCEPT_MERGE" "$destination_relative" "" "$ownership" "$current_hash"
          add_receipt "$artifact_id" "$destination_relative" "$ownership" "$PACK_VERSION" "$new_hash" "merged" "$current_hash"
        elif [ "$current_exists" = false ]; then
          add_action "$artifact_id" "RESTORE" "$destination_relative" "$source_relative" "$ownership" "ABSENT"
          add_receipt "$artifact_id" "$destination_relative" "$ownership" "$PACK_VERSION" "$new_hash"
        elif [ "$current_hash" = "$new_hash" ]; then
          add_action "$artifact_id" "ADOPT_EXACT" "$destination_relative" "" "$ownership" "$current_hash"
          add_receipt "$artifact_id" "$destination_relative" "$ownership" "$PACK_VERSION" "$new_hash"
        else
          add_action "$artifact_id" "REPLACE_ACCEPTED" "$destination_relative" "$source_relative" "$ownership" "$current_hash"
          add_receipt "$artifact_id" "$destination_relative" "$ownership" "$PACK_VERSION" "$new_hash"
        fi
      else
        if [ "$current_exists" = true ]; then
          add_action "$artifact_id" "KEEP_LOCAL_OVERRIDE" "$destination_relative" "" "$ownership" "$current_hash"
          add_receipt "$artifact_id" "$destination_relative" "$ownership" "-" "-" "keep-local" "$current_hash"
        else
          add_action "$artifact_id" "KEEP_DELETED_OVERRIDE" "$destination_relative" "" "$ownership" "ABSENT"
          add_receipt "$artifact_id" "$destination_relative" "$ownership" "-" "-" "deleted-local" "-"
        fi
      fi
      continue
    fi

    if [ "$state_mode" = "merged" ]; then
      if [ "$current_exists" = true ] &&
         [ "$current_hash" = "$state_local_hash" ] &&
         [ "$new_hash" = "$baseline_hash" ]; then
        add_action "$artifact_id" "RETAIN_MERGED" "$destination_relative" "" "$ownership" "$current_hash"
        add_receipt "$artifact_id" "$destination_relative" "$ownership" "$baseline_version" "$baseline_hash" "merged" "$state_local_hash"
      else
        add_action "$artifact_id" "CONFLICT_MERGE_REQUIRED" "$destination_relative" "$source_relative" "$ownership" "$current_hash"
        conflict_count=$((conflict_count + 1))
      fi
      continue
    fi

    if [ "$current_exists" = false ]; then
      resolution_for "$artifact_id" "$ownership"
      case "$RESOLUTION" in
        pack)
          if [ "$ownership" = "merge" ]; then
            fail "--accept-merge requires an existing manually reviewed file: $artifact_id"
          else
            add_action "$artifact_id" "RESTORE" "$destination_relative" "$source_relative" "$ownership" "ABSENT"
            add_receipt "$artifact_id" "$destination_relative" "$ownership" "$PACK_VERSION" "$new_hash"
          fi
          ;;
        keep)
          add_action "$artifact_id" "KEEP_LOCAL" "$destination_relative" "" "$ownership" "ABSENT"
          add_receipt "$artifact_id" "$destination_relative" "$ownership" "-" "-" "deleted-local" "-"
          ;;
        *)
          add_action "$artifact_id" "CONFLICT_DELETED" "$destination_relative" "$source_relative" "$ownership" "ABSENT"
          conflict_count=$((conflict_count + 1))
          ;;
      esac
    elif [ "$current_hash" = "$new_hash" ]; then
      add_action "$artifact_id" "UNCHANGED" "$destination_relative" "" "$ownership" "$current_hash"
      add_receipt "$artifact_id" "$destination_relative" "$ownership" "$PACK_VERSION" "$new_hash"
    elif [ "$current_hash" = "$baseline_hash" ]; then
      add_action "$artifact_id" "UPDATE" "$destination_relative" "$source_relative" "$ownership" "$current_hash"
      add_receipt "$artifact_id" "$destination_relative" "$ownership" "$PACK_VERSION" "$new_hash"
    else
      resolution_for "$artifact_id" "$ownership"
      case "$RESOLUTION" in
        pack)
          if [ "$ownership" = "merge" ]; then
            add_action "$artifact_id" "ACCEPT_MERGE" "$destination_relative" "" "$ownership" "$current_hash"
            add_receipt "$artifact_id" "$destination_relative" "$ownership" "$PACK_VERSION" "$new_hash" "merged" "$current_hash"
          else
            add_action "$artifact_id" "REPLACE_ACCEPTED" "$destination_relative" "$source_relative" "$ownership" "$current_hash"
            add_receipt "$artifact_id" "$destination_relative" "$ownership" "$PACK_VERSION" "$new_hash"
          fi
          ;;
        keep)
          add_action "$artifact_id" "KEEP_LOCAL" "$destination_relative" "" "$ownership" "$current_hash"
          add_receipt "$artifact_id" "$destination_relative" "$ownership" "-" "-" "keep-local" "-"
          ;;
        *)
          add_action "$artifact_id" "CONFLICT_LOCAL" "$destination_relative" "$source_relative" "$ownership" "$current_hash"
          conflict_count=$((conflict_count + 1))
          ;;
      esac
    fi
  else
    if [ "$current_exists" = false ]; then
      add_action "$artifact_id" "ADD" "$destination_relative" "$source_relative" "$ownership" "ABSENT"
      add_receipt "$artifact_id" "$destination_relative" "$ownership" "$PACK_VERSION" "$new_hash"
    elif [ "$current_hash" = "$new_hash" ]; then
      add_action "$artifact_id" "ADOPT_EXACT" "$destination_relative" "" "$ownership" "$current_hash"
      add_receipt "$artifact_id" "$destination_relative" "$ownership" "$PACK_VERSION" "$new_hash"
    else
      find_known_hash_version "$artifact_id" "$destination_relative" "$current_hash"
      if [ -n "$KNOWN_VERSION" ]; then
        if [ "$ownership" = "seed" ]; then
          add_action "$artifact_id" "RETAIN_SEED" "$destination_relative" "" "$ownership" "$current_hash"
          add_receipt "$artifact_id" "$destination_relative" "$ownership" "$KNOWN_VERSION" "$current_hash"
        else
          add_action "$artifact_id" "UPDATE_ADOPTED" "$destination_relative" "$source_relative" "$ownership" "$current_hash"
          add_receipt "$artifact_id" "$destination_relative" "$ownership" "$PACK_VERSION" "$new_hash"
        fi
      elif [ "$ownership" = "seed" ]; then
        add_action "$artifact_id" "RETAIN_SEED_UNMANAGED" "$destination_relative" "" "$ownership" "$current_hash"
      else
        resolution_for "$artifact_id" "$ownership"
        case "$RESOLUTION" in
          pack)
            if [ "$ownership" = "merge" ]; then
              add_action "$artifact_id" "ACCEPT_MERGE" "$destination_relative" "" "$ownership" "$current_hash"
              add_receipt "$artifact_id" "$destination_relative" "$ownership" "$PACK_VERSION" "$new_hash" "merged" "$current_hash"
            else
              add_action "$artifact_id" "REPLACE_ACCEPTED" "$destination_relative" "$source_relative" "$ownership" "$current_hash"
              add_receipt "$artifact_id" "$destination_relative" "$ownership" "$PACK_VERSION" "$new_hash"
            fi
            ;;
          keep)
            add_action "$artifact_id" "KEEP_LOCAL" "$destination_relative" "" "$ownership" "$current_hash"
            add_receipt "$artifact_id" "$destination_relative" "$ownership" "-" "-" "keep-local" "-"
            ;;
          *)
            add_action "$artifact_id" "CONFLICT_UNMANAGED" "$destination_relative" "$source_relative" "$ownership" "$current_hash"
            conflict_count=$((conflict_count + 1))
            ;;
        esac
      fi
    fi
  fi
done

for state_index in "${!state_ids[@]}"; do
  artifact_id="${state_ids[$state_index]}"
  destination_relative="${state_destinations[$state_index]}"
  ownership="${state_ownerships[$state_index]}"
  baseline_hash="${state_baseline_hashes[$state_index]}"
  baseline_version="${state_baseline_versions[$state_index]}"
  state_mode="${state_modes[$state_index]}"
  still_desired=false
  for current_index in "${!artifact_ids[@]}"; do
    if [ "${artifact_ids[$current_index]}" = "$artifact_id" ] &&
       artifact_is_selected "${artifact_components[$current_index]}"; then
      still_desired=true
    fi
  done
  [ "$still_desired" = false ] || continue

  destination="$REPO_ROOT/$destination_relative"
  validate_target_path "$destination_relative"
  if [ "$ownership" = "seed" ]; then
    if contains_value "$artifact_id" "${accept_pack_ids[@]}" ||
       contains_value "$artifact_id" "${accept_merge_ids[@]}"; then
      fail "Seed artifacts never accept pack replacement or removal: $artifact_id"
    fi
    if contains_value "$artifact_id" "${keep_local_ids[@]}"; then
      used_keep_local_ids+=("$artifact_id")
    fi
    if [ -f "$destination" ]; then
      hash_file "$destination"
      current_hash="$HASH_VALUE"
      add_action "$artifact_id" "RETAIN_SEED_REMOVED" "$destination_relative" "" "$ownership" "$current_hash"
      add_receipt "$artifact_id" "$destination_relative" "$ownership" "-" "-" "keep-local" "$current_hash"
    else
      add_action "$artifact_id" "KEEP_DELETED_OVERRIDE" "$destination_relative" "" "$ownership" "ABSENT"
      add_receipt "$artifact_id" "$destination_relative" "$ownership" "-" "-" "deleted-local" "-"
    fi
    continue
  fi
  if [ ! -f "$destination" ]; then
    if [ "$state_mode" = "keep-local" ] || [ "$state_mode" = "deleted-local" ]; then
      removal_resolution_for "$artifact_id"
      if [ "$RESOLUTION" = "pack" ]; then
        add_action "$artifact_id" "FORGET_REMOVED" "$destination_relative" "" "$ownership" "ABSENT"
      else
        add_action "$artifact_id" "KEEP_DELETED_OVERRIDE" "$destination_relative" "" "$ownership" "ABSENT"
        add_receipt "$artifact_id" "$destination_relative" "$ownership" "-" "-" "deleted-local" "-"
      fi
    else
      add_action "$artifact_id" "FORGET_REMOVED" "$destination_relative" "" "$ownership" "ABSENT"
    fi
    continue
  fi
  hash_file "$destination"
  current_hash="$HASH_VALUE"
  if [ "$state_mode" = "keep-local" ] || [ "$state_mode" = "deleted-local" ]; then
    removal_resolution_for "$artifact_id"
    if [ "$RESOLUTION" = "pack" ]; then
      add_action "$artifact_id" "REMOVE_ACCEPTED" "$destination_relative" "" "$ownership" "$current_hash"
    else
      add_action "$artifact_id" "KEEP_LOCAL_REMOVED" "$destination_relative" "" "$ownership" "$current_hash"
      add_receipt "$artifact_id" "$destination_relative" "$ownership" "-" "-" "keep-local" "$current_hash"
    fi
    continue
  fi

  if [ "$ownership" = "managed" ] &&
     [ "$state_mode" = "tracked" ] &&
     [ "$current_hash" = "$baseline_hash" ]; then
    add_action "$artifact_id" "REMOVE" "$destination_relative" "" "$ownership" "$current_hash"
    continue
  fi

  removal_resolution_for "$artifact_id"
  case "$RESOLUTION" in
    pack)
      add_action "$artifact_id" "REMOVE_ACCEPTED" "$destination_relative" "" "$ownership" "$current_hash"
      ;;
    keep)
      add_action "$artifact_id" "KEEP_LOCAL_REMOVED" "$destination_relative" "" "$ownership" "$current_hash"
      add_receipt "$artifact_id" "$destination_relative" "$ownership" "-" "-" "keep-local" "$current_hash"
      ;;
    *)
      add_action "$artifact_id" "CONFLICT_REMOVE" "$destination_relative" "" "$ownership" "$current_hash"
      conflict_count=$((conflict_count + 1))
      ;;
  esac
done

if [ "$state_exists" = false ]; then
  historical_ids=()
  for compat_index in "${!compat_ids[@]}"; do
    artifact_id="${compat_ids[$compat_index]}"
    contains_value "$artifact_id" "${historical_ids[@]}" && continue
    historical_ids+=("$artifact_id")
    current_id_exists=false
    for current_index in "${!artifact_ids[@]}"; do
      [ "${artifact_ids[$current_index]}" != "$artifact_id" ] || current_id_exists=true
    done
    [ "$current_id_exists" = false ] || continue
    destination_relative="${compat_destinations[$compat_index]}"
    destination="$REPO_ROOT/$destination_relative"
    validate_target_path "$destination_relative"
    [ -f "$destination" ] || continue
    hash_file "$destination"
    current_hash="$HASH_VALUE"
    removal_resolution_for "$artifact_id"
    case "$RESOLUTION" in
      pack)
        add_action "$artifact_id" "REMOVE_ACCEPTED" "$destination_relative" "" "managed" "$current_hash"
        ;;
      keep)
        add_action "$artifact_id" "KEEP_LOCAL_REMOVED" "$destination_relative" "" "seed" "$current_hash"
        add_receipt "$artifact_id" "$destination_relative" "seed" "-" "-" "keep-local" "$current_hash"
        ;;
      *)
        find_known_hash_version "$artifact_id" "$destination_relative" "$current_hash"
        if [ -n "$KNOWN_VERSION" ]; then
          add_action "$artifact_id" "REMOVE_ACCEPTED" "$destination_relative" "" "managed" "$current_hash"
        else
          add_action "$artifact_id" "CONFLICT_LEGACY_REMOVED" "$destination_relative" "" "managed" "$current_hash"
          conflict_count=$((conflict_count + 1))
        fi
        ;;
    esac
  done
fi

for requested_id in "${accept_pack_ids[@]}"; do
  contains_value "$requested_id" "${used_accept_pack_ids[@]}" ||
    fail "--accept-pack did not match a reconciled artifact: $requested_id"
done
for requested_id in "${accept_merge_ids[@]}"; do
  contains_value "$requested_id" "${used_accept_merge_ids[@]}" ||
    fail "--accept-merge did not match a merge artifact: $requested_id"
done
for requested_id in "${keep_local_ids[@]}"; do
  contains_value "$requested_id" "${used_keep_local_ids[@]}" ||
    fail "--keep-local did not match a reconciled artifact: $requested_id"
done

echo "Agent Pack update: ${state_version:-legacy} -> $PACK_VERSION"
echo "Repository: $REPO_ROOT"
echo "Profiles: ${selected_profiles[*]}"
echo "Integrations: ${selected_integrations[*]}"
for index in "${!action_ids[@]}"; do
  printf '%-24s %-36s %s\n' \
    "${action_kinds[$index]}" \
    "${action_ids[$index]}" \
    "${action_destinations[$index]}"
done
echo "Summary: actions=${#action_ids[@]} conflicts=$conflict_count mode=$mode"

if [ "$conflict_count" -gt 0 ]; then
  echo "No files were written because unresolved conflicts exist." >&2
  exit 2
fi

[ "$mode" = "apply" ] || exit 0

run_id="$(date -u +%Y%m%d%H%M%S)-$$"
lock_dir="$RUNTIME_DIR/update.lock"
staging_dir="$RUNTIME_DIR/.staging-$run_id"
backup_dir="$RUNTIME_DIR/backups/$PACK_VERSION/$run_id"
retired_dir="$RUNTIME_DIR/retired/$PACK_VERSION/$run_id"
staged_state="$staging_dir/state.txt"
transaction_active=false
state_touched=false
state_had_original=false
runtime_gitignore_created=false
applied_indices=()

cleanup_staging() {
  if [ -d "$staging_dir" ]; then
    rm -rf "$staging_dir"
  fi
}

release_lock() {
  [ -d "$lock_dir" ] && rmdir "$lock_dir" 2>/dev/null || true
}

rollback() {
  local position index kind destination backup
  set +e
  if [ "$state_touched" = true ]; then
    if [ -f "$STATE_FILE" ]; then
      rm -f "$STATE_FILE"
    fi
    if [ "$state_had_original" = true ] && [ -f "$backup_dir/state.txt" ]; then
      mv "$backup_dir/state.txt" "$STATE_FILE"
    fi
  fi
  position=$((${#applied_indices[@]} - 1))
  while [ "$position" -ge 0 ]; do
    index="${applied_indices[$position]}"
    kind="${action_kinds[$index]}"
    destination="$REPO_ROOT/${action_destinations[$index]}"
    case "$kind" in
      ADD|ADD_SEED|ADD_MOVED|RESTORE)
        [ -f "$destination" ] && rm -f "$destination"
        ;;
      UPDATE|UPDATE_ADOPTED|REPLACE_ACCEPTED|WRITE_PACK)
        backup="$backup_dir/files/$index"
        [ -f "$destination" ] && rm -f "$destination"
        if [ -f "$backup" ]; then
          mkdir -p "$(dirname "$destination")"
          mv "$backup" "$destination"
        fi
        ;;
      REMOVE|REMOVE_ACCEPTED|RETIRE_RENAMED)
        backup="$retired_dir/files/$index"
        [ -f "$destination" ] && rm -f "$destination"
        if [ -f "$backup" ]; then
          mkdir -p "$(dirname "$destination")"
          mv "$backup" "$destination"
        fi
        ;;
    esac
    position=$((position - 1))
  done
  cleanup_staging
  release_lock
  if [ "$runtime_gitignore_created" = true ] && [ -f "$RUNTIME_DIR/.gitignore" ]; then
    rm -f "$RUNTIME_DIR/.gitignore"
  fi
  transaction_active=false
  set -e
}

on_interrupt() {
  echo "Update interrupted; rolling back." >&2
  [ "$transaction_active" = false ] || rollback
  exit 130
}

on_exit() {
  local status=$?
  if [ "$status" -ne 0 ] && [ "$transaction_active" = true ]; then
    echo "Update failed unexpectedly; rolling back." >&2
    rollback
  fi
  return "$status"
}

trap on_interrupt INT TERM HUP
trap on_exit EXIT

mkdir -p "$RUNTIME_DIR"
if ! mkdir "$lock_dir" 2>/dev/null; then
  fail "Another update is active or a stale lock exists: $lock_dir"
fi
transaction_active=true

if [ ! -f "$RUNTIME_DIR/.gitignore" ]; then
  runtime_gitignore_created=true
  {
    echo "*"
    echo "!.gitignore"
  } > "$RUNTIME_DIR/.gitignore"
fi

mkdir -p "$staging_dir/files" "$backup_dir/files" "$retired_dir/files"

for index in "${!action_ids[@]}"; do
  kind="${action_kinds[$index]}"
  case "$kind" in
    ADD|ADD_SEED|ADD_MOVED|RESTORE|UPDATE|UPDATE_ADOPTED|REPLACE_ACCEPTED|WRITE_PACK)
      cp "$TEMPLATE_ROOT/${action_sources[$index]}" "$staging_dir/files/$index"
      hash_file "$staging_dir/files/$index"
      find_current_artifact "${action_ids[$index]}" "${action_destinations[$index]}"
      if [ "$FOUND_INDEX" -lt 0 ] || [ "$HASH_VALUE" != "${artifact_hashes[$FOUND_INDEX]}" ]; then
        fail "Agent Pack source changed after planning: ${action_sources[$index]}"
      fi
      ;;
  esac
done

{
  printf 'version|%s\n' "$PACK_VERSION"
  {
    for value in "${selected_profiles[@]}"; do
      printf 'profile|%s\n' "$value"
    done
  } | sort -t '|' -k2,2
  {
    for value in "${selected_integrations[@]}"; do
      printf 'integration|%s\n' "$value"
    done
  } | sort -t '|' -k2,2
  {
    for index in "${!receipt_ids[@]}"; do
      printf 'artifact|%s|%s|%s|%s|%s|%s|%s\n' \
        "${receipt_ids[$index]}" \
        "${receipt_destinations[$index]}" \
        "${receipt_ownerships[$index]}" \
        "${receipt_versions[$index]}" \
        "${receipt_hashes[$index]}" \
        "${receipt_modes[$index]}" \
        "${receipt_local_hashes[$index]}"
    done
  } | sort -t '|' -k2,2
} > "$staged_state"

apply_failed=false
for index in "${!action_ids[@]}"; do
  kind="${action_kinds[$index]}"
  destination="$REPO_ROOT/${action_destinations[$index]}"
  expected_hash="${action_expected_hashes[$index]}"
  current_hash="ABSENT"
  if [ -f "$destination" ]; then
    hash_file "$destination"
    current_hash="$HASH_VALUE"
  fi
  if [ "$current_hash" != "$expected_hash" ]; then
    echo "Precondition changed before apply: ${action_destinations[$index]}" >&2
    apply_failed=true
    break
  fi

  case "$kind" in
    ADD|ADD_SEED|ADD_MOVED|RESTORE)
      applied_indices+=("$index")
      if ! mkdir -p "$(dirname "$destination")" ||
         ! mv "$staging_dir/files/$index" "$destination"; then
        apply_failed=true
        break
      fi
      ;;
    UPDATE|UPDATE_ADOPTED|REPLACE_ACCEPTED|WRITE_PACK)
      applied_indices+=("$index")
      if ! mkdir -p "$(dirname "$backup_dir/files/$index")" ||
         ! mv "$destination" "$backup_dir/files/$index" ||
         ! mv "$staging_dir/files/$index" "$destination"; then
        apply_failed=true
        break
      fi
      ;;
    REMOVE|REMOVE_ACCEPTED|RETIRE_RENAMED)
      applied_indices+=("$index")
      if ! mkdir -p "$(dirname "$retired_dir/files/$index")" ||
         ! mv "$destination" "$retired_dir/files/$index"; then
        apply_failed=true
        break
      fi
      ;;
  esac
done

if [ "$apply_failed" = true ]; then
  echo "Apply failed; rolling back." >&2
  rollback
  exit 1
fi

if [ -f "$STATE_FILE" ]; then
  state_had_original=true
  if ! cp "$STATE_FILE" "$backup_dir/state.txt"; then
    echo "Could not back up the previous state; rolling back." >&2
    rollback
    exit 1
  fi
fi
state_touched=true
if ! mv -f "$staged_state" "$STATE_FILE"; then
  echo "Could not commit the new state; rolling back." >&2
  rollback
  exit 1
fi

cleanup_staging
release_lock
transaction_active=false
trap - INT TERM HUP EXIT

echo "Update applied successfully. Backups: $backup_dir Retired: $retired_dir"
