#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
INSPECTOR="$PACK_ROOT/repo-template/.agents/skills/bootstrap-dotnet-repo/scripts/inspect-dotnet-repo.sh"

modern_output="$(bash "$INSPECTOR" "$PACK_ROOT/tests/fixtures/modern-web")"
printf '%s\n' "$modern_output" | grep -q 'net8.0'
printf '%s\n' "$modern_output" | grep -q 'Suggested profiles: web sqlserver'

legacy_output="$(bash "$INSPECTOR" "$PACK_ROOT/tests/fixtures/legacy-framework")"
printf '%s\n' "$legacy_output" | grep -q 'v4.8'
printf '%s\n' "$legacy_output" | grep -q 'Suggested profiles: web'
printf '%s\n' "$legacy_output" | grep -qv 'legacy-framework'

echo "Repository inspector smoke test passed."
