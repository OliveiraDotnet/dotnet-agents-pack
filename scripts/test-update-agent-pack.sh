#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
UPDATER="$SCRIPT_DIR/update-agent-pack.sh"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/agent-pack-update.XXXXXX")"
FAKE_PACK="$TEMP_ROOT/pack"
REPO="$TEMP_ROOT/repo"
ADOPTION_REPO="$TEMP_ROOT/adoption-repo"

cleanup() {
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

fail() {
  echo "TEST FAILURE: $*" >&2
  exit 1
}

assert_file_content() {
  local file="$1" expected="$2" actual
  [ -f "$file" ] || fail "Expected file: $file"
  actual="$(cat "$file")"
  [ "$actual" = "$expected" ] ||
    fail "Unexpected content in $file. Expected '$expected', got '$actual'."
}

hash_file() {
  local file="$1" output
  if command -v sha256sum >/dev/null 2>&1; then
    output="$(sha256sum "$file")"
  elif command -v shasum >/dev/null 2>&1; then
    output="$(shasum -a 256 "$file")"
  else
    output="$(openssl dgst -sha256 "$file")"
    printf '%s' "${output##* }"
    return
  fi
  printf '%s' "${output%% *}"
}

mkdir -p "$FAKE_PACK/scripts" "$FAKE_PACK/repo-template" "$FAKE_PACK/compat/releases"
mkdir -p "$REPO/.agent-pack" "$ADOPTION_REPO"
cp "$UPDATER" "$FAKE_PACK/scripts/update-agent-pack.sh"

printf '%s\n' "2.0.0" > "$FAKE_PACK/pack-version.txt"

printf '%s\n' "new update" > "$FAKE_PACK/repo-template/update.txt"
printf '%s\n' "new conflict" > "$FAKE_PACK/repo-template/conflict.txt"
printf '%s\n' "new seed template" > "$FAKE_PACK/repo-template/seed.txt"
printf '%s\n' "new addition" > "$FAKE_PACK/repo-template/added.txt"
printf '%s\n' "stable anchor" > "$FAKE_PACK/repo-template/anchor.txt"

cat > "$FAKE_PACK/pack-manifest.txt" <<'EOF'
core|update.txt
core|conflict.txt
core|seed.txt
core|added.txt
core|anchor.txt
EOF

cat > "$FAKE_PACK/pack-artifacts.txt" <<'EOF'
update-file|update.txt|managed
conflict-file|conflict.txt|managed
seed-file|seed.txt|seed
added-file|added.txt|managed
anchor-file|anchor.txt|managed
EOF

BASELINES="$TEMP_ROOT/baselines"
mkdir -p "$BASELINES"
printf '%s\n' "old update" > "$BASELINES/update.txt"
printf '%s\n' "old conflict" > "$BASELINES/conflict.txt"
printf '%s\n' "old seed template" > "$BASELINES/seed.txt"
printf '%s\n' "old removed" > "$BASELINES/removed.txt"
printf '%s\n' "stable anchor" > "$BASELINES/anchor.txt"

update_old_hash="$(hash_file "$BASELINES/update.txt")"
conflict_old_hash="$(hash_file "$BASELINES/conflict.txt")"
seed_old_hash="$(hash_file "$BASELINES/seed.txt")"
removed_old_hash="$(hash_file "$BASELINES/removed.txt")"
anchor_old_hash="$(hash_file "$BASELINES/anchor.txt")"

{
  printf 'update-file|update.txt|%s\n' "$update_old_hash"
  printf 'conflict-file|conflict.txt|%s\n' "$conflict_old_hash"
  printf 'seed-file|seed.txt|%s\n' "$seed_old_hash"
  printf 'removed-file|removed.txt|%s\n' "$removed_old_hash"
  printf 'anchor-file|anchor.txt|%s\n' "$anchor_old_hash"
} > "$FAKE_PACK/compat/releases/1.1.0.txt"

cp "$BASELINES/update.txt" "$REPO/update.txt"
printf '%s\n' "project conflict change" > "$REPO/conflict.txt"
printf '%s\n' "project seed knowledge" > "$REPO/seed.txt"
cp "$BASELINES/removed.txt" "$REPO/removed.txt"
cp "$BASELINES/anchor.txt" "$REPO/anchor.txt"

{
  echo "# agent-pack state v1"
  echo "version|1.1.0"
  echo "profile|core"
  echo "integration|codex"
  printf 'artifact|update-file|update.txt|managed|1.1.0|%s|tracked|-\n' "$update_old_hash"
  printf 'artifact|conflict-file|conflict.txt|managed|1.1.0|%s|tracked|-\n' "$conflict_old_hash"
  printf 'artifact|seed-file|seed.txt|seed|1.1.0|%s|tracked|-\n' "$seed_old_hash"
  printf 'artifact|removed-file|removed.txt|managed|1.1.0|%s|tracked|-\n' "$removed_old_hash"
  printf 'artifact|anchor-file|anchor.txt|managed|1.1.0|%s|tracked|-\n' "$anchor_old_hash"
} > "$REPO/.agent-pack/state.txt"

cp "$REPO/.agent-pack/state.txt" "$TEMP_ROOT/state-before-check.txt"
set +e
check_output="$(bash "$FAKE_PACK/scripts/update-agent-pack.sh" "$REPO" --check 2>&1)"
check_status=$?
set -e
[ "$check_status" -eq 2 ] || fail "Expected conflict exit 2, got $check_status: $check_output"
printf '%s\n' "$check_output" | grep -q "CONFLICT_LOCAL" ||
  fail "Conflict plan did not report CONFLICT_LOCAL."
cmp -s "$REPO/.agent-pack/state.txt" "$TEMP_ROOT/state-before-check.txt" ||
  fail "--check changed the state file."
[ ! -e "$REPO/added.txt" ] || fail "--check created the added artifact."
assert_file_content "$REPO/update.txt" "old update"
assert_file_content "$REPO/removed.txt" "old removed"
assert_file_content "$REPO/seed.txt" "project seed knowledge"
[ ! -e "$REPO/.agent-pack/.runtime" ] || fail "--check created runtime files."

apply_output="$(
  bash "$FAKE_PACK/scripts/update-agent-pack.sh" \
    "$REPO" \
    --apply \
    --accept-pack conflict-file 2>&1
)"
printf '%s\n' "$apply_output" | grep -q "Update applied successfully" ||
  fail "Apply did not report success: $apply_output"
assert_file_content "$REPO/update.txt" "new update"
assert_file_content "$REPO/conflict.txt" "new conflict"
assert_file_content "$REPO/seed.txt" "project seed knowledge"
assert_file_content "$REPO/added.txt" "new addition"
assert_file_content "$REPO/anchor.txt" "stable anchor"
[ ! -e "$REPO/removed.txt" ] || fail "Obsolete intact managed artifact was not removed."
grep -q '^version|2.0.0$' "$REPO/.agent-pack/state.txt" ||
  fail "State version was not advanced."
grep -q "^artifact|update-file|update.txt|managed|2.0.0|.*|tracked|-$" "$REPO/.agent-pack/state.txt" ||
  fail "Updated managed artifact was not recorded."
project_seed_hash="$(hash_file "$REPO/seed.txt")"
grep -q "^artifact|seed-file|seed.txt|seed|-|-|keep-local|$project_seed_hash$" "$REPO/.agent-pack/state.txt" ||
  fail "Seed should be persisted as repository-owned content."
if grep -q '^artifact|removed-file|' "$REPO/.agent-pack/state.txt"; then
  fail "Removed artifact remained in state."
fi
find "$REPO/.agent-pack/.runtime/backups" "$REPO/.agent-pack/.runtime/retired" -type f | grep -q . ||
  fail "Apply did not retain recoverable backups."
grep -q '^\*$' "$REPO/.agent-pack/.runtime/.gitignore" ||
  fail "Runtime .gitignore does not ignore transaction files."
grep -q '^!.gitignore$' "$REPO/.agent-pack/.runtime/.gitignore" ||
  fail "Runtime .gitignore does not retain itself."
[ ! -e "$REPO/.agent-pack/.runtime/update.lock" ] ||
  fail "Apply left the update lock behind."

cp "$REPO/.agent-pack/state.txt" "$TEMP_ROOT/state-before-noop.txt"
noop_output="$(bash "$FAKE_PACK/scripts/update-agent-pack.sh" "$REPO" --check 2>&1)"
printf '%s\n' "$noop_output" | grep -q "conflicts=0" ||
  fail "Completed update is not conflict-free."
cmp -s "$REPO/.agent-pack/state.txt" "$TEMP_ROOT/state-before-noop.txt" ||
  fail "Second --check changed state."

bash "$FAKE_PACK/scripts/update-agent-pack.sh" "$REPO" --apply --integration codex,grok >/dev/null
grep -q '^integration|codex$' "$REPO/.agent-pack/state.txt" ||
  fail "Codex was not retained in the integration override."
grep -q '^integration|grok$' "$REPO/.agent-pack/state.txt" ||
  fail "Grok integration override was not persisted."
if grep -q '^integration|claude$' "$REPO/.agent-pack/state.txt"; then
  fail "Claude remained selected after a codex,grok override."
fi
cp "$REPO/.agent-pack/state.txt" "$TEMP_ROOT/state-with-grok.txt"
bash "$FAKE_PACK/scripts/update-agent-pack.sh" "$REPO" --apply >/dev/null
cmp -s "$REPO/.agent-pack/state.txt" "$TEMP_ROOT/state-with-grok.txt" ||
  fail "A later update did not preserve the codex,grok selection."
set +e
bash "$FAKE_PACK/scripts/update-agent-pack.sh" "$REPO" --check --integration grok >/dev/null 2>&1
invalid_integration_status=$?
set -e
[ "$invalid_integration_status" -ne 0 ] ||
  fail "An integration override without mandatory Codex was accepted."

# Once a seed has a receipt, a deliberate local deletion is repository-owned
# and must not cause the updater to recreate it.
rm -f "$REPO/seed.txt"
deleted_seed_check="$(bash "$FAKE_PACK/scripts/update-agent-pack.sh" "$REPO" --check 2>&1)"
printf '%s\n' "$deleted_seed_check" | grep -q "RETAIN_SEED_DELETED" ||
  fail "Deleted seed was not recognized as a local deletion."
[ ! -e "$REPO/seed.txt" ] || fail "Seed --check recreated a deleted seed."
bash "$FAKE_PACK/scripts/update-agent-pack.sh" "$REPO" --apply >/dev/null
[ ! -e "$REPO/seed.txt" ] || fail "Seed --apply recreated a deleted seed."
grep -q '^artifact|seed-file|seed.txt|seed|-|-|deleted-local|-$' "$REPO/.agent-pack/state.txt" ||
  fail "Deleted seed was not persisted as deleted-local."

# Legacy adoption: CRLF content must match the LF-normalized historical hash.
printf 'old update\r\n' > "$ADOPTION_REPO/update.txt"
printf '%s\n' "project seed knowledge" > "$ADOPTION_REPO/seed.txt"

adoption_check="$(
  bash "$FAKE_PACK/scripts/update-agent-pack.sh" \
    "$ADOPTION_REPO" \
    --check 2>&1
)"
printf '%s\n' "$adoption_check" | grep -q "legacy -> 2.0.0" ||
  fail "Legacy adoption was not detected."
[ ! -e "$ADOPTION_REPO/.agent-pack" ] ||
  fail "Legacy --check created state or runtime files."
[ ! -e "$ADOPTION_REPO/added.txt" ] ||
  fail "Legacy --check created an artifact."
assert_file_content "$ADOPTION_REPO/seed.txt" "project seed knowledge"

bash "$FAKE_PACK/scripts/update-agent-pack.sh" "$ADOPTION_REPO" --apply >/dev/null
assert_file_content "$ADOPTION_REPO/update.txt" "new update"
assert_file_content "$ADOPTION_REPO/added.txt" "new addition"
assert_file_content "$ADOPTION_REPO/seed.txt" "project seed knowledge"
[ -f "$ADOPTION_REPO/.agent-pack/state.txt" ] ||
  fail "Legacy adoption did not create state."
grep -q '^profile|core$' "$ADOPTION_REPO/.agent-pack/state.txt" ||
  fail "Legacy adoption did not infer the core profile."
adopted_seed_hash="$(hash_file "$ADOPTION_REPO/seed.txt")"
grep -q "^artifact|seed-file|seed.txt|seed|-|-|keep-local|$adopted_seed_hash$" "$ADOPTION_REPO/.agent-pack/state.txt" ||
  fail "Project-owned seed was not preserved in state."

# Stable-id rename: a clean tracked source moves to the new destination and is
# updated without leaving the old path behind.
update_new_hash="$(hash_file "$FAKE_PACK/repo-template/update.txt")"
conflict_new_hash="$(hash_file "$FAKE_PACK/repo-template/conflict.txt")"
added_new_hash="$(hash_file "$FAKE_PACK/repo-template/added.txt")"
anchor_new_hash="$(hash_file "$FAKE_PACK/repo-template/anchor.txt")"
{
  printf 'update-file|update.txt|%s\n' "$update_new_hash"
  printf 'conflict-file|conflict.txt|%s\n' "$conflict_new_hash"
  printf 'added-file|added.txt|%s\n' "$added_new_hash"
  printf 'anchor-file|anchor.txt|%s\n' "$anchor_new_hash"
} > "$FAKE_PACK/compat/releases/2.0.0.txt"
printf '%s\n' "2.1.0" > "$FAKE_PACK/pack-version.txt"
cat > "$FAKE_PACK/pack-manifest.txt" <<'EOF'
core|update.txt
core|conflict.txt
core|seed.txt
core|added.txt
core|anchor.txt|moved/anchor-renamed.txt
EOF
cat > "$FAKE_PACK/pack-artifacts.txt" <<'EOF'
update-file|update.txt|managed
conflict-file|conflict.txt|managed
seed-file|seed.txt|seed
added-file|added.txt|managed
anchor-file|moved/anchor-renamed.txt|managed
EOF

rename_check="$(bash "$FAKE_PACK/scripts/update-agent-pack.sh" "$REPO" --check 2>&1)"
printf '%s\n' "$rename_check" | grep -q "RETIRE_RENAMED" ||
  fail "Clean rename did not retire the previous destination."
printf '%s\n' "$rename_check" | grep -q "ADD_MOVED" ||
  fail "Clean rename did not plan the new destination."
assert_file_content "$REPO/anchor.txt" "stable anchor"
[ ! -e "$REPO/moved/anchor-renamed.txt" ] ||
  fail "Rename --check wrote the new destination."

bash "$FAKE_PACK/scripts/update-agent-pack.sh" "$REPO" --apply >/dev/null
[ ! -e "$REPO/anchor.txt" ] ||
  fail "Rename left the old managed destination behind."
assert_file_content "$REPO/moved/anchor-renamed.txt" "stable anchor"
grep -q "^artifact|anchor-file|moved/anchor-renamed.txt|managed|2.1.0|$anchor_new_hash|tracked|-$" \
  "$REPO/.agent-pack/state.txt" ||
  fail "Rename did not advance the receipt to the new destination."

# A later rename with a locally modified old path and an occupied new path must
# conflict without writes. Explicit AcceptPack archives both and installs the
# new pack artifact.
{
  printf 'update-file|update.txt|%s\n' "$update_new_hash"
  printf 'conflict-file|conflict.txt|%s\n' "$conflict_new_hash"
  printf 'added-file|added.txt|%s\n' "$added_new_hash"
  printf 'anchor-file|moved/anchor-renamed.txt|%s\n' "$anchor_new_hash"
} > "$FAKE_PACK/compat/releases/2.1.0.txt"
printf '%s\n' "2.2.0" > "$FAKE_PACK/pack-version.txt"
cat > "$FAKE_PACK/pack-manifest.txt" <<'EOF'
core|update.txt
core|conflict.txt
core|seed.txt
core|added.txt
core|anchor.txt|moved/anchor-v2.txt
EOF
cat > "$FAKE_PACK/pack-artifacts.txt" <<'EOF'
update-file|update.txt|managed
conflict-file|conflict.txt|managed
seed-file|seed.txt|seed
added-file|added.txt|managed
anchor-file|moved/anchor-v2.txt|managed
EOF
printf '%s\n' "local anchor customization" > "$REPO/moved/anchor-renamed.txt"
printf '%s\n' "occupied destination" > "$REPO/moved/anchor-v2.txt"
cp "$REPO/.agent-pack/state.txt" "$TEMP_ROOT/state-before-rename-conflict.txt"

set +e
rename_conflict="$(
  bash "$FAKE_PACK/scripts/update-agent-pack.sh" "$REPO" --check 2>&1
)"
rename_conflict_status=$?
set -e
[ "$rename_conflict_status" -eq 2 ] ||
  fail "Modified/occupied rename should conflict: $rename_conflict"
printf '%s\n' "$rename_conflict" | grep -q "CONFLICT_RENAME" ||
  fail "Modified/occupied rename did not report CONFLICT_RENAME."
assert_file_content "$REPO/moved/anchor-renamed.txt" "local anchor customization"
assert_file_content "$REPO/moved/anchor-v2.txt" "occupied destination"
cmp -s "$REPO/.agent-pack/state.txt" "$TEMP_ROOT/state-before-rename-conflict.txt" ||
  fail "Rename conflict changed state."

bash "$FAKE_PACK/scripts/update-agent-pack.sh" \
  "$REPO" \
  --apply \
  --accept-pack anchor-file >/dev/null
[ ! -e "$REPO/moved/anchor-renamed.txt" ] ||
  fail "Accepted rename left the old customized destination behind."
assert_file_content "$REPO/moved/anchor-v2.txt" "stable anchor"
grep -R -q "local anchor customization" "$REPO/.agent-pack/.runtime/retired" ||
  fail "Accepted rename did not retire the customized old destination."
grep -R -q "occupied destination" "$REPO/.agent-pack/.runtime/backups" ||
  fail "Accepted rename did not back up the occupied new destination."

echo "Agent Pack updater tests passed."
