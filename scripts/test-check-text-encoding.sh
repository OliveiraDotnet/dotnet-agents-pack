#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
CHECKER="$PACK_ROOT/repo-template/.agents/skills/check-text-encoding/scripts/check-mojibake.sh"
TEMP_PARENT="${TMPDIR:-/tmp}"

fail() {
  echo "Text encoding checker test failed: $*" >&2
  exit 1
}

[ -f "$CHECKER" ] || fail "checker is missing: $CHECKER"
command -v iconv >/dev/null 2>&1 || {
  echo "Text encoding checker tests require iconv." >&2
  exit 2
}

TEMP_ROOT="$(mktemp -d "$TEMP_PARENT/agent-pack-encoding-test.XXXXXX")"
cleanup() {
  case "$TEMP_ROOT" in
    "$TEMP_PARENT"/agent-pack-encoding-test.*) rm -rf -- "$TEMP_ROOT" ;;
    *) echo "Refusing to clean unexpected temporary path: $TEMP_ROOT" >&2 ;;
  esac
}
trap cleanup EXIT

run_case() {
  local name="$1" relative_path="$2" expected_exit="$3" expected_output="$4"
  local output exit_code

  set +e
  output="$(bash "$CHECKER" --repo "$TEMP_ROOT" --file "$relative_path" 2>&1)"
  exit_code=$?
  set -e

  if [ "$exit_code" -ne "$expected_exit" ]; then
    printf '%s\n' "$output" >&2
    fail "case '$name' returned exit code $exit_code; expected $expected_exit"
  fi
  case "$output" in
    *"$expected_output"*) ;;
    *)
      printf '%s\n' "$output" >&2
      fail "case '$name' did not report '$expected_output'"
      ;;
  esac
}

printf 'informa\303\247\303\243o \303\272til em \303\242mbito local\n' > "$TEMP_ROOT/correct.txt"
printf 'informa\303\203\302\247\303\203\302\243o\n' > "$TEMP_ROOT/mojibake.txt"
printf 'replacement \357\277\275\n' > "$TEMP_ROOT/replacement.txt"
printf '# agent-pack:allow-mojibake informa\303\203\302\247o\n' > "$TEMP_ROOT/allowed.txt"
printf '\103\303\050\104' > "$TEMP_ROOT/invalid-utf8.txt"

run_case "valid UTF-8 accents" "correct.txt" 0 "Text encoding check passed"
run_case "common mojibake" "mojibake.txt" 1 "misdecoded-utf8-c3"
run_case "replacement character" "replacement.txt" 1 "replacement-character"
run_case "intentional mojibake marker" "allowed.txt" 0 "Text encoding check passed"
run_case "invalid UTF-8 bytes" "invalid-utf8.txt" 1 "invalid-utf8"

rm -f "$TEMP_ROOT/mojibake.txt" "$TEMP_ROOT/replacement.txt" "$TEMP_ROOT/allowed.txt" "$TEMP_ROOT/invalid-utf8.txt"
git -C "$TEMP_ROOT" init -q
git -C "$TEMP_ROOT" -c user.name=agent-pack-test -c user.email=agent-pack@example.invalid add correct.txt 2>/dev/null
git -C "$TEMP_ROOT" -c user.name=agent-pack-test -c user.email=agent-pack@example.invalid commit -qm baseline
printf 'linha alterada\n' >> "$TEMP_ROOT/correct.txt"
default_output="$(bash "$CHECKER" --repo "$TEMP_ROOT" 2>&1)" ||
  fail "default Git changed-file scan failed: $default_output"
case "$default_output" in
  *"Text encoding check passed"*) ;;
  *) fail "default Git changed-file scan did not report success: $default_output" ;;
esac

echo "Text encoding checker tests passed: 6 cases."
