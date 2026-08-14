---
name: check-text-encoding
description: Detect invalid UTF-8 and likely mojibake in changed or repository text files. Use after editing source, documentation, prompts, rules, or skills; during review; or whenever text contains corrupted sequences such as replacement characters or misdecoded UTF-8.
---

# Check text encoding

1. Scan changed text files before completing the task:
   - Windows: `powershell -ExecutionPolicy Bypass -File .agents/skills/check-text-encoding/scripts/check-mojibake.ps1`
   - Linux/macOS: `bash .agents/skills/check-text-encoding/scripts/check-mojibake.sh`
2. Use `-All` or `--all` only for a repository-wide audit.
3. For each finding, inspect the file bytes, nearby text and Git history before editing. Do not transcode or rewrite an entire file based only on a heuristic match.
4. Preserve the repository's confirmed encoding and line-ending convention. Never replace accents with ASCII to hide a failure.
5. If a suspicious sequence is intentional test data, add `agent-pack:allow-mojibake` on that line with a short reason.
6. Rerun the same scan after the fix and report unresolved findings.

The scripts do not modify files. Invalid UTF-8 is always an error; mojibake signatures are high-signal heuristics that require contextual confirmation.
