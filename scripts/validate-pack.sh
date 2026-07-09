#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
TEMPLATE_ROOT="$PACK_ROOT/repo-template"
MANIFEST="$PACK_ROOT/pack-manifest.txt"
errors=0

fail() { echo "ERROR: $*" >&2; errors=$((errors + 1)); }

[ -f "$MANIFEST" ] || fail "Missing pack manifest."

manifest_paths=()
while IFS='|' read -r component relative; do
  component="${component//[[:space:]]/}"
  relative="${relative# }"
  [ -n "$component" ] || continue
  [[ "$component" = \#* ]] && continue
  case "$component" in core|web|sqlserver|quality) ;; *) fail "Unknown profile in manifest: $component"; continue ;; esac
  [ -n "$relative" ] || { fail "Empty manifest path."; continue; }
  [ -f "$TEMPLATE_ROOT/$relative" ] || fail "Manifest source is missing: $relative"
  manifest_paths+=("$relative")
done < "$MANIFEST"

while IFS= read -r file; do
  relative="${file#"$TEMPLATE_ROOT"/}"
  found=false
  for listed in "${manifest_paths[@]}"; do [ "$listed" = "$relative" ] && found=true; done
  [ "$found" = true ] || fail "Template file is not listed in manifest: $relative"
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

while IFS= read -r skill; do
  folder="$(basename "$(dirname "$skill")")"
  name="$(sed -n 's/^name:[[:space:]]*//p' "$skill" | head -n 1)"
  description="$(sed -n 's/^description:[[:space:]]*//p' "$skill" | head -n 1)"
  [ -n "$name" ] || fail "Skill $folder is missing name"
  [ -n "$description" ] || fail "Skill $folder is missing description"
  [ "$name" = "$folder" ] || fail "Skill $folder name does not match folder"
  printf '%s' "$name" | grep -qE '^[a-z0-9-]+$' || fail "Skill $name violates naming rules"
done < <(find "$TEMPLATE_ROOT/.agents/skills" -type f -name SKILL.md)

if grep -RInE 'Aptos|M & Y TECH|Portal de Vendas|projetos/' "$TEMPLATE_ROOT" "$PACK_ROOT/README.md" "$PACK_ROOT/INSTRUCOES_DETALHADAS.md" "$PACK_ROOT/FONTES_OFICIAIS_CODEX.md" "$PACK_ROOT/global/AGENTS.md" >/dev/null 2>&1; then
  fail "Obsolete organization-specific references found"
fi

[ "$errors" -eq 0 ] || exit 1
echo "Pack validation passed: manifest, skills, agents and generic-content checks are valid."
