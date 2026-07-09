#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
INSTALLER="$SCRIPT_DIR/install-agent-pack.sh"
TEMPLATE="$PACK_ROOT/repo-template"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dotnet-agents-pack.XXXXXX")"
REPO="$TEMP_ROOT/target"

cleanup() { rm -rf "$TEMP_ROOT"; }
trap cleanup EXIT

mkdir -p "$REPO"
git -C "$REPO" init -q

bash "$INSTALLER" "$REPO" --dry-run
[ ! -e "$REPO/AGENTS.md" ]

bash "$INSTALLER" "$REPO"
[ -f "$REPO/AGENTS.md" ]
[ -f "$REPO/.agents/skills/bootstrap-dotnet-repo/SKILL.md" ]
[ ! -e "$REPO/.codex/agents/frontend-web.toml" ]

bash "$INSTALLER" "$REPO"
[ ! -e "$REPO/AGENTS.md.agent-pack.new" ]

bash "$INSTALLER" "$REPO" --profile web,sqlserver,quality
[ -f "$REPO/.codex/agents/frontend-web.toml" ]
[ -f "$REPO/.agents/skills/db-change-sqlserver/SKILL.md" ]
[ -f "$REPO/.agents/skills/security-review-dotnet/SKILL.md" ]

echo "# local change" >> "$REPO/AGENTS.md"
bash "$INSTALLER" "$REPO"
[ -f "$REPO/AGENTS.md.agent-pack.new" ]

bash "$INSTALLER" "$REPO" --force
cmp -s "$REPO/AGENTS.md" "$TEMPLATE/AGENTS.md"
find "$REPO" -maxdepth 1 -type f -name 'AGENTS.md.agent-pack.backup-*' | grep -q .

CODEX_HOME="$TEMP_ROOT/custom-codex-home" bash "$INSTALLER" "$REPO" --install-global
[ -f "$TEMP_ROOT/custom-codex-home/AGENTS.md" ]

echo "Installer smoke test passed."
