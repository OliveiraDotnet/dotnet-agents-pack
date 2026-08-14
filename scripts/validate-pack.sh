#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
TEMPLATE_ROOT="$PACK_ROOT/repo-template"
MANIFEST="$PACK_ROOT/pack-manifest.txt"
PACK_VERSION_FILE="$PACK_ROOT/pack-version.txt"
ARTIFACT_METADATA="$PACK_ROOT/pack-artifacts.txt"
COMPATIBILITY_ROOT="$PACK_ROOT/compat/releases"
errors=0

fail() { echo "ERROR: $*" >&2; errors=$((errors + 1)); }

[ -f "$MANIFEST" ] || fail "Missing pack manifest."

manifest_components=()
manifest_sources=()
manifest_destinations=()
while IFS='|' read -r component source_relative destination_relative extra; do
  component="${component//[[:space:]]/}"
  source_relative="${source_relative# }"
  destination_relative="${destination_relative# }"
  source_relative="${source_relative%$'\r'}"
  destination_relative="${destination_relative%$'\r'}"
  [ -n "$component" ] || continue
  [[ "$component" = \#* ]] && continue
  [ -z "$extra" ] || { fail "Invalid manifest line with too many fields: $component"; continue; }
  case "$component" in
    core|web|sqlserver|quality|claude-core|claude-web|claude-sqlserver|claude-quality|grok-core|grok-web|grok-sqlserver|grok-quality) ;;
    *) fail "Unknown component in manifest: $component"; continue ;;
  esac
  [ -n "$source_relative" ] || { fail "Empty manifest source."; continue; }
  [ -n "$destination_relative" ] || destination_relative="$source_relative"
  [ -f "$TEMPLATE_ROOT/$source_relative" ] || fail "Manifest source is missing: $source_relative"
  for listed in "${manifest_destinations[@]}"; do
    [ "$listed" != "$destination_relative" ] || fail "Manifest destination appears more than once: $destination_relative"
  done
  manifest_components+=("$component")
  manifest_sources+=("$source_relative")
  manifest_destinations+=("$destination_relative")
done < "$MANIFEST"

if [ ! -f "$PACK_VERSION_FILE" ]; then
  fail "Missing pack version file."
else
  pack_version="$(tr -d '\r\n' < "$PACK_VERSION_FILE")"
  [[ "$pack_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Invalid semantic version in pack-version.txt: $pack_version"
  IFS= read -r manifest_header < "$MANIFEST" || true
  manifest_header="${manifest_header%$'\r'}"
  [ "$manifest_header" = "# .NET Agents Pack manifest v$pack_version" ] || fail "Manifest header version does not match pack-version.txt"
fi

artifact_ids=()
artifact_destinations=()
artifact_destinations_lower=()
artifact_ownership=()
if [ ! -f "$ARTIFACT_METADATA" ]; then
  fail "Missing artifact metadata."
else
  while IFS='|' read -r artifact_id destination ownership extra; do
    artifact_id="${artifact_id%$'\r'}"
    destination="${destination%$'\r'}"
    ownership="${ownership%$'\r'}"
    [ -n "$artifact_id" ] || continue
    [[ "$artifact_id" = \#* ]] && continue
    [ -z "${extra:-}" ] || { fail "Invalid artifact metadata line for $artifact_id"; continue; }
    [[ "$artifact_id" =~ ^[a-z0-9][a-z0-9.-]*$ ]] || fail "Invalid artifact id: $artifact_id"
    case "$destination" in ""|/*|*\\*|..|../*|*/..|*/../*) fail "Invalid artifact destination: $destination" ;; esac
    case "$ownership" in managed|merge|seed) ;; *) fail "Invalid ownership '$ownership' for '$artifact_id'" ;; esac
    for existing in "${artifact_ids[@]}"; do [ "$existing" != "$artifact_id" ] || fail "Artifact id appears more than once: $artifact_id"; done
    destination_lower="$(printf '%s' "$destination" | tr '[:upper:]' '[:lower:]')"
    for existing_lower in "${artifact_destinations_lower[@]}"; do
      [ "$existing_lower" != "$destination_lower" ] || fail "Artifact destination appears more than once: $destination"
    done
    artifact_ids+=("$artifact_id")
    artifact_destinations+=("$destination")
    artifact_destinations_lower+=("$destination_lower")
    artifact_ownership+=("$ownership")
  done < "$ARTIFACT_METADATA"
fi

for destination in "${manifest_destinations[@]}"; do
  count=0
  for candidate in "${artifact_destinations[@]}"; do [ "$candidate" != "$destination" ] || count=$((count + 1)); done
  [ "$count" -eq 1 ] || fail "Manifest destination must have exactly one artifact metadata entry: $destination"
done
for destination in "${artifact_destinations[@]}"; do
  count=0
  for candidate in "${manifest_destinations[@]}"; do [ "$candidate" != "$destination" ] || count=$((count + 1)); done
  [ "$count" -eq 1 ] || fail "Artifact metadata destination is not present once in the manifest: $destination"
done
for index in "${!artifact_destinations[@]}"; do
  destination="${artifact_destinations[$index]}"
  ownership="${artifact_ownership[$index]}"
  case "$destination" in
    AGENTS.md|CLAUDE.md|.grok/config.toml) [ "$ownership" = merge ] || fail "$destination must use merge ownership" ;;
    docs/ai/*) [ "$ownership" = seed ] || fail "Repository memory must use seed ownership: $destination" ;;
  esac
done

if [ ! -d "$COMPATIBILITY_ROOT" ]; then
  fail "Missing compatibility catalog directory."
else
  for catalog in "$COMPATIBILITY_ROOT"/*.txt; do
    [ -f "$catalog" ] || continue
    catalog_ids=()
    while IFS='|' read -r artifact_id destination hash extra; do
      artifact_id="${artifact_id%$'\r'}"
      destination="${destination%$'\r'}"
      hash="${hash%$'\r'}"
      [ -n "$artifact_id" ] || continue
      [[ "$artifact_id" = \#* ]] && continue
      [ -z "${extra:-}" ] || { fail "Invalid compatibility line in $(basename "$catalog")"; continue; }
      [[ "$artifact_id" =~ ^[a-z0-9][a-z0-9.-]*$ ]] || fail "Invalid compatibility artifact id: $artifact_id"
      case "$destination" in ""|/*|*\\*|..|../*|*/..|*/../*) fail "Invalid compatibility destination: $destination" ;; esac
      [[ "$hash" =~ ^[a-f0-9]{64}$ ]] || fail "Invalid compatibility hash for $artifact_id"
      for existing in "${catalog_ids[@]}"; do [ "$existing" != "$artifact_id" ] || fail "Compatibility catalog repeats artifact id: $artifact_id"; done
      catalog_ids+=("$artifact_id")
    done < "$catalog"
  done
fi

agents_governance="$TEMPLATE_ROOT/AGENTS.md"
delegation_contract="$TEMPLATE_ROOT/.agents/skills/delegate-to-grok-build/SKILL.md"
execution_contract="$TEMPLATE_ROOT/.grok/skills/execute-codex-work-order/SKILL.md"
for governance_file in "$agents_governance" "$delegation_contract" "$execution_contract"; do
  [ -f "$governance_file" ] || fail "Missing Grok governance artifact: $governance_file"
done
if [ -f "$agents_governance" ] && [ -f "$delegation_contract" ] && [ -f "$execution_contract" ]; then
  for required in "sole decision authority" "Gate 1" "execution envelope" "Gate 2" "BLOCKED_BY_DECISION"; do
    grep -Fq "$required" "$agents_governance" || fail "AGENTS.md is missing governance marker '$required'"
  done
  for required in "Human-approved scope" "Allowed read areas" "Allowed modification areas" "Decision boundaries" "Escalation conditions" "READY_FOR_MANUAL_VALIDATION" "USER_DECISION_REQUIRED"; do
    grep -Fq "$required" "$delegation_contract" || fail "Codex-to-Grok delegation contract is missing '$required'"
  done
  for required in "COMPLETED" "COMPLETED_WITH_CONCERNS" "BLOCKED_BY_DECISION" "UNABLE_TO_VALIDATE" "material change was not performed"; do
    grep -Fq "$required" "$execution_contract" || fail "Grok execution contract is missing '$required'"
  done
fi

while IFS= read -r file; do
  relative="${file#"$TEMPLATE_ROOT"/}"
  found=false
  for listed in "${manifest_sources[@]}"; do [ "$listed" = "$relative" ] && found=true; done
  [ "$found" = true ] || fail "Template file is not listed as a manifest source: $relative"
done < <(find "$TEMPLATE_ROOT" -type f)

while IFS= read -r agent; do
  content="$(cat "$agent")"
  for key in name description developer_instructions; do
    printf '%s\n' "$content" | grep -q "^$key[[:space:]]*=" || fail "Agent $(basename "$agent") is missing $key"
  done
  nicknames="$(printf '%s\n' "$content" | grep '^nickname_candidates' || true)"
  if [ -n "$nicknames" ] && printf '%s\n' "$nicknames" | grep -oE '"[^"]+"' | grep -qvE '^"[A-Za-z0-9 _-]+"$'; then
    fail "Agent $(basename "$agent") has a non-ASCII nickname"
  fi
done < <(find "$TEMPLATE_ROOT/.codex/agents" -type f -name '*.toml')

while IFS= read -r agent; do
  name="$(sed -n 's/^name:[[:space:]]*//p' "$agent" | head -n 1 | tr -d '\"' | tr -d "'")"
  description="$(sed -n 's/^description:[[:space:]]*//p' "$agent" | head -n 1)"
  filename="$(basename "$agent" .md)"
  [ -n "$name" ] || fail "Claude agent $filename is missing name"
  [ -n "$description" ] || fail "Claude agent $filename is missing description"
  [[ "$name" =~ ^[a-z0-9-]+$ ]] || fail "Claude agent $filename has invalid name: $name"
  [ "$name" = "$filename" ] || fail "Claude agent name $name does not match file $filename.md"
done < <(find "$TEMPLATE_ROOT/.claude/agents" -type f -name '*.md')

while IFS= read -r agent; do
  codex_name="$(sed -n 's/^name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$agent" | head -n 1)"
  [ -n "$codex_name" ] || continue
  claude_name="${codex_name//_/-}"
  [ -f "$TEMPLATE_ROOT/.claude/agents/$claude_name.md" ] || fail "Codex agent $(basename "$agent") has no Claude counterpart $claude_name.md"

  grok_source=".claude/agents/$claude_name.md"
  grok_destination=".grok/agents/$claude_name.md"
  match_count=0
  for index in "${!manifest_destinations[@]}"; do
    if [[ "${manifest_components[$index]}" = grok-* ]] &&
       [ "${manifest_sources[$index]}" = "$grok_source" ] &&
       [ "${manifest_destinations[$index]}" = "$grok_destination" ]; then
      match_count=$((match_count + 1))
    fi
  done
  [ "$match_count" -eq 1 ] || fail "Codex agent $(basename "$agent") must map once to Grok agent $grok_destination"
done < <(find "$TEMPLATE_ROOT/.codex/agents" -type f -name '*.toml')

[ -f "$TEMPLATE_ROOT/CLAUDE.md" ] || fail "Missing Claude guidance bridge: CLAUDE.md"
if [ -f "$TEMPLATE_ROOT/CLAUDE.md" ] && ! grep -qE '^@AGENTS\.md[[:space:]]*$' "$TEMPLATE_ROOT/CLAUDE.md"; then
  fail "CLAUDE.md must import @AGENTS.md"
fi

grok_config="$TEMPLATE_ROOT/.grok/config.toml"
if [ ! -f "$grok_config" ]; then
  fail "Missing Grok Build project configuration: .grok/config.toml"
else
  for command in "git commit" "git push"; do
    required_rule="{ action = \"deny\", tool = \"bash\", pattern = \"$command *\" }"
    if ! grep -Fq "$required_rule" "$grok_config"; then
      fail ".grok/config.toml must deny '$command'"
    fi
  done
fi

while IFS= read -r skill; do
  folder="$(basename "$(dirname "$skill")")"
  name="$(sed -n 's/^name:[[:space:]]*//p' "$skill" | head -n 1)"
  description="$(sed -n 's/^description:[[:space:]]*//p' "$skill" | head -n 1)"
  [ -n "$name" ] || fail "Skill $folder is missing name"
  [ -n "$description" ] || fail "Skill $folder is missing description"
  [ "$name" = "$folder" ] || fail "Skill $folder name does not match folder"
  [[ "$name" =~ ^[a-z0-9-]+$ ]] || fail "Skill $name violates naming rules"
done < <(find "$TEMPLATE_ROOT/.agents/skills" -type f -name SKILL.md)

for index in "${!manifest_destinations[@]}"; do
  canonical_destination="${manifest_destinations[$index]}"
  [[ "$canonical_destination" = .agents/skills/* ]] || continue
  case "${manifest_components[$index]}" in
    core|web|sqlserver|quality) ;;
    *) continue ;;
  esac
  expected_component="claude-${manifest_components[$index]}"
  expected_destination=".claude/skills/${canonical_destination#.agents/skills/}"
  match_count=0
  for mirror_index in "${!manifest_destinations[@]}"; do
    if [ "${manifest_components[$mirror_index]}" = "$expected_component" ] &&
       [ "${manifest_sources[$mirror_index]}" = "${manifest_sources[$index]}" ] &&
       [ "${manifest_destinations[$mirror_index]}" = "$expected_destination" ]; then
      match_count=$((match_count + 1))
    fi
  done
  [ "$match_count" -eq 1 ] || fail "Skill ${manifest_sources[$index]} must map once to $expected_destination in $expected_component"

  if [[ "$canonical_destination" != */agents/openai.yaml ]]; then
    grok_component="grok-${manifest_components[$index]}"
    grok_destination=".grok/skills/${canonical_destination#.agents/skills/}"
    match_count=0
    for mirror_index in "${!manifest_destinations[@]}"; do
      if [ "${manifest_components[$mirror_index]}" = "$grok_component" ] &&
         [ "${manifest_sources[$mirror_index]}" = "${manifest_sources[$index]}" ] &&
         [ "${manifest_destinations[$mirror_index]}" = "$grok_destination" ]; then
        match_count=$((match_count + 1))
      fi
    done
    [ "$match_count" -eq 1 ] || fail "Skill ${manifest_sources[$index]} must map once to $grok_destination in $grok_component"
  fi
done

if grep -RInE 'Aptos|M & Y TECH|Portal de Vendas|projetos/' "$TEMPLATE_ROOT" "$PACK_ROOT/README.md" "$PACK_ROOT/MANUAL_DE_USO.md" "$PACK_ROOT/INSTRUCOES_DETALHADAS.md" "$PACK_ROOT/FONTES_OFICIAIS_CODEX.md" "$PACK_ROOT/FONTES_OFICIAIS_CLAUDE.md" "$PACK_ROOT/FONTES_OFICIAIS_GROK_BUILD.md" "$PACK_ROOT/global/AGENTS.md" >/dev/null 2>&1; then
  fail "Obsolete organization-specific references found"
fi

encoding_checker="$TEMPLATE_ROOT/.agents/skills/check-text-encoding/scripts/check-mojibake.sh"
if [ -f "$encoding_checker" ]; then
  bash "$encoding_checker" --repo "$PACK_ROOT" --all || fail "Text encoding validation failed"
else
  fail "Missing shell text encoding checker"
fi

[ "$errors" -eq 0 ] || exit 1
echo "Pack validation passed: manifest, shared skills, Codex/Claude/Grok agents and generic-content checks are valid."
