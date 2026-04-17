---
paths:
  - "setup.sh"
  - "lib/**/*.sh"
---

# Bash style

## Portability (Bash 3.2 target)

macOS default bash is 3.2. Do **not** use:

- `declare -A` / associative arrays
- `declare -n` / namerefs
- `mapfile` / `readarray`
- `${var^^}` / `${var,,}` case modification

Safe to use: indexed arrays, `read -ra`, `local -a`, parameter expansion (`${var%%pat}`, `${var##pat}`, `${var:-default}`), `<<<` here-string, `<()` / `>()` process substitution.

Test expressions: this codebase uses `[ ... ]` (POSIX test) exclusively. `[[ ... ]]` is also bash 3.2+ safe if you need pattern/regex matching, but stay with `[ ... ]` for consistency.

## Quoting

- Always quote variables: `"$var"`, `"${arr[@]}"`.
- Use `"$*"` to join tokens; `"$@"` to preserve separate args.
- Registry `ARGS` tokens: use `argv=($args)` to word-split (intentional); all other variables should stay quoted.

## Scoping

- Declare function-locals with `local`. Globals belong at file scope with a comment explaining why.
- `IFS` changes: always `local IFS=...` so the change doesn't leak.

## Error handling

- `set -eo pipefail` belongs in `setup.sh` only. Library files must work under the caller's settings.
- Installer primitives (`install_<TOKEN>`): `return 0` on success, non-zero on failure. Never `exit` from a primitive.
- Only entry points (`run_install`, `run_doctor`, bootstrap checks) may `exit`.

## Output conventions

- User-visible progress: `track_*` functions (`track_success`, `track_active`, `track_error`, `track_warn`, `track_info`).
- Pre-bootstrap (before `ensure_gum`): plain `echo` only — gum may not exist yet.
- Command output / errors: redirect to `$LOG_FILE` with `>> "$LOG_FILE" 2>&1`.
- Use `&>/dev/null` for pure silence; use `>> "$LOG_FILE" 2>&1` when the output might be needed for debugging.

## Registry records (lib/registry.sh)

- 7 pipe-separated fields: `KEY|TYPE|LABEL|INSTALLER|ARGS|TIER|CHECK`.
- `|` is **forbidden** inside any field (including LABEL and CHECK).
- `CHECK` expressions must not end with `| head` or any pipeline whose last command always returns 0 — this produces false positives. Prefer `cmd &>/dev/null`.
- `KEY` is snake_case English, stable across refactors. Never rename a key casually; the key is the extension point.

## File structure

- Shebang: `#!/usr/bin/env bash`.
- File header comment: one-line purpose + (optional) naming conventions block.
- Section dividers: `# ── Section ──` (box-drawing chars, consistent across files).
- Function docstrings: one line above the function declaration for anything public.
