#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: bash check-mojibake.sh [--repo PATH] [--all] [--file PATH ...]"
}

repo_input="."
scan_all=false
files=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      [ "$#" -ge 2 ] || { echo "Missing value for --repo" >&2; exit 1; }
      repo_input="$2"
      shift 2
      ;;
    --all) scan_all=true; shift ;;
    --file)
      [ "$#" -ge 2 ] || { echo "Missing value for --file" >&2; exit 1; }
      files+=("$2")
      shift 2
      ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[ -d "$repo_input" ] || { echo "Repository path is not a directory: $repo_input" >&2; exit 1; }
REPO_ROOT="$(cd "$repo_input" && pwd -P)"
command -v iconv >/dev/null 2>&1 || { echo "iconv is required for strict UTF-8 validation." >&2; exit 2; }

is_ignored() {
  case "$1" in
    .git/*|*/.git/*|.agent-pack/*|*/.agent-pack/*|bin/*|*/bin/*|obj/*|*/obj/*|build/*|*/build/*|.dart_tool/*|*/.dart_tool/*|.gradle/*|*/.gradle/*|Pods/*|*/Pods/*|DerivedData/*|*/DerivedData/*|node_modules/*|*/node_modules/*|coverage/*|*/coverage/*) return 0 ;;
    *) return 1 ;;
  esac
}

candidate_file="$(mktemp "${TMPDIR:-/tmp}/agent-pack-encoding.XXXXXX")"
cleanup() { rm -f "$candidate_file" "$candidate_file.findings"; }
trap cleanup EXIT

if [ "${#files[@]}" -gt 0 ]; then
  for file in "${files[@]}"; do printf '%s\n' "$file" >> "$candidate_file"; done
elif command -v git >/dev/null 2>&1 && git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [ "$scan_all" = true ]; then
    git -C "$REPO_ROOT" ls-files --cached --others --exclude-standard > "$candidate_file"
  else
    git -C "$REPO_ROOT" diff --name-only --diff-filter=ACMR HEAD -- 2>/dev/null > "$candidate_file" || git -C "$REPO_ROOT" ls-files --cached > "$candidate_file"
    git -C "$REPO_ROOT" ls-files --others --exclude-standard >> "$candidate_file"
  fi
else
  (cd "$REPO_ROOT" && find . -type f -print | sed 's#^\./##') > "$candidate_file"
fi

prefix_c3="$(printf '\303\203')"
prefix_c2="$(printf '\303\202')"
punctuation_euro="$(printf '\303\242\342\202\254')"
punctuation_dagger="$(printf '\303\242\342\200\240')"
punctuation_oe="$(printf '\303\242\305\223')"
punctuation_c2_98="$(printf '\303\242\302\230')"
punctuation_c2_80="$(printf '\303\242\302\200')"
punctuation_c2_86="$(printf '\303\242\302\206')"
prefix_emoji="$(printf '\303\260\305\270')"
misdecoded_bom="$(printf '\303\257\302\273\302\277')"
misdecoded_replacement="$(printf '\303\257\302\277\302\275')"
replacement="$(printf '\357\277\275')"

scanned=0
findings=0
sort -u "$candidate_file" | while IFS= read -r relative || [ -n "$relative" ]; do
  [ -n "$relative" ] || continue
  is_ignored "$relative" && continue
  case "$relative" in /*) full="$relative" ;; *) full="$REPO_ROOT/$relative" ;; esac
  [ -f "$full" ] || continue
  grep -Iq . "$full" || continue

  if ! iconv -f UTF-8 -t UTF-8 "$full" >/dev/null 2>&1; then
    printf '%s:0:0: invalid-utf8\n' "$relative"
    printf '1\n' >> "$candidate_file.findings"
    continue
  fi

  scanned=$((scanned + 1))
  line_number=0
  while IFS= read -r line || [ -n "$line" ]; do
    line_number=$((line_number + 1))
    case "$line" in *agent-pack:allow-mojibake*) continue ;; esac
    kind=""
    case "$line" in
      *"$replacement"*) kind="replacement-character" ;;
      *"$misdecoded_bom"*) kind="misdecoded-bom" ;;
      *"$misdecoded_replacement"*) kind="misdecoded-replacement" ;;
      *"$prefix_emoji"*) kind="misdecoded-emoji" ;;
      *"$punctuation_euro"*|*"$punctuation_dagger"*|*"$punctuation_oe"*|*"$punctuation_c2_98"*|*"$punctuation_c2_80"*|*"$punctuation_c2_86"*) kind="misdecoded-punctuation" ;;
      *"$prefix_c3"*) kind="misdecoded-utf8-c3" ;;
      *"$prefix_c2"*) kind="misdecoded-utf8-c2" ;;
    esac
    if [ -n "$kind" ]; then
      printf '%s:%s:1: %s\n' "$relative" "$line_number" "$kind"
      printf '1\n' >> "$candidate_file.findings"
    fi
  done < "$full"
done

if [ -f "$candidate_file.findings" ]; then
  findings="$(wc -l < "$candidate_file.findings" | tr -d ' ')"
  rm -f "$candidate_file.findings"
fi

if [ "$findings" -gt 0 ]; then
  echo "Text encoding check failed with $findings finding(s)." >&2
  exit 1
fi

echo "Text encoding check passed."
