#!/usr/bin/env bash
set -euo pipefail

repo_path="${1:-.}"
repo_path="$(cd "$repo_path" && pwd -P)"

find_files() {
  find "$repo_path" \
    \( -path '*/.git/*' -o -path '*/bin/*' -o -path '*/obj/*' -o -path '*/node_modules/*' -o -path '*/packages/*' -o -path '*/.vs/*' -o -path '*/.agents/*' -o -path '*/.claude/*' -o -path '*/.grok/*' -o -path '*/.codex/*' -o -path '*/.agent-pack/*' \) -prune -o \
    -type f -print
}

relative() { printf '%s' "${1#"$repo_path"/}"; }

count_pattern() { find_files | grep -E -c "$1" || true; }

list_pattern() {
  find_files | grep -E "$1" | while IFS= read -r file; do
    relative "$file"
    printf '\n'
  done || true
}

git_root=""
if command -v git >/dev/null 2>&1; then
  git_root="$(git -C "$repo_path" rev-parse --show-toplevel 2>/dev/null || true)"
fi

project_files="$(list_pattern '\.(csproj|fsproj|vbproj)$' || true)"
solution_files="$(list_pattern '\.slnx?$' || true)"
tfms="$(find_files | grep -E '\.(csproj|fsproj|vbproj)$' | while IFS= read -r project; do grep -h -E '<TargetFramework(s|Version)?>' "$project" 2>/dev/null || true; done | sed -E 's/.*<TargetFramework(s|Version)?>([^<]+)<.*/\2/' | sort -u || true)"

profiles=()
if [ "$(count_pattern '\.(cshtml|razor|aspx)$|(^|/)Web\.config$|(^|/)wwwroot/')" -gt 0 ]; then profiles+=(web); fi
sql_package_project="$(find_files | grep -E '\.(csproj|fsproj|vbproj)$' | while IFS= read -r project; do grep -l -E '(SqlClient|EntityFramework|Dapper)' "$project" 2>/dev/null || true; done | head -n 1 || true)"
if [ "$(count_pattern '\.sql$')" -gt 0 ] || [ -n "$sql_package_project" ]; then
  profiles+=(sqlserver)
fi

shape="non-git-folder"
if [ -n "$git_root" ]; then shape="git-repository"; fi

printf '# .NET repository fingerprint\n\n'
printf -- '- Shape: %s\n' "$shape"
printf -- '- Git root: %s\n' "${git_root:-[none]}"
printf -- '- Solutions:\n%s\n' "${solution_files:-[none]}"
printf -- '- Projects:\n%s\n' "${project_files:-[none]}"
printf -- '- Target frameworks:\n%s\n' "${tfms:-[unreadable-or-not-found]}"
printf -- '- Suggested profiles: %s\n' "${profiles[*]:-[none]}"
printf -- '- CI or build files:\n'
list_pattern '(^|/)(\.github/workflows/.*\.ya?ml|azure-pipelines.*\.ya?ml|\.gitlab-ci\.ya?ml|(build|test)\.(ps1|sh|cmd|bat))$' || true
