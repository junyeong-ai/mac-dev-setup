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

Safe to use: indexed arrays, `read -ra`, `local -a`, parameter expansion (`${var%%pat}`, `${var##pat}`, `${var:-default}`), `<<<` here-string, `<()` / `>()` process substitution, `${PIPESTATUS[@]}`.

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
- Bootstrap primitives (`bootstrap_<NAME>`): same contract. Only `run_bootstrap` may `exit`.
- Only entry points (`run_install`, `run_doctor`, `run_bootstrap`) may `exit`.
- Suppress `set -e` around a single command with `cmd || rc=$?` so the exit code is captured cleanly. For pipelines whose original exit code matters, wrap in `( set +e +o pipefail; cmd | filter; exit "${PIPESTATUS[0]}" )`.

## Output conventions

- User-visible install progress: `track_*` functions in `lib/ui.sh` (`track_success`, `track_active`, `track_error`, `track_warn`, `track_info`). Only callable after `bootstrap_gum` has installed gum.
- Pre-bootstrap (before gum is installed): `say_*` from `lib/log.sh` (`say_step`, `say_info`, `say_detail`, `say_warn`, `say_error`, `say_debug`).
- Command shell-outs: pick a runner from `lib/log.sh` instead of writing redirections inline.
  - `run_interactive <cmd>` — full TTY pass-through (sudo prompts, Homebrew install).
  - `run_with_tee <cmd>` — stream to user *and* append to log (long ops with meaningful progress).
  - `run_silent <cmd>` — log-only (uninteresting verbose output behind a `track_*` step).
- Never use `>> "$LOG_FILE" 2>&1` directly — always go through a runner so every shell-out leaves a `CMD` / `EXIT` pair in the log.
- `&>/dev/null` is reserved for trivial probes (e.g. `command -v foo &>/dev/null`).

## Registry records (lib/registry.sh)

- 8 pipe-separated fields: `KEY|TYPE|LABEL|INSTALLER|ARGS|TIER|DEPS|CHECK`.
- `|` is **forbidden** inside any field (including LABEL, ARGS, DEPS, and CHECK).
- `CHECK` expressions must not end with `| head` or any pipeline whose last command always returns 0 — this produces false positives. Prefer `cmd &>/dev/null` / `compgen -G`.
- `LABEL` must not contain `,` — the interactive selector passes default labels to gum as a comma-separated value, and `validate_registry` enforces this.
- `KEY` is snake_case English, stable across refactors. Never rename a key casually; the key is the extension point.

## Library layering

```
log.sh        →  ui.sh  →  registry.sh  →  bootstrap.sh
                                         ↘
                                           installers.sh / configs.sh
                                                ↘
                                                  orchestrator.sh / doctor.sh
```

- `log.sh` has zero dependencies and provides the vocabulary every other layer uses to talk.
- `bootstrap.sh` may use `say_*` / `run_*` but not `track_*` / `gum style` (gum is not yet installed).
- `installers.sh` / `configs.sh` may use both because they only run after `run_bootstrap` installs gum.

## File structure

- Shebang: `#!/usr/bin/env bash`.
- File header comment: one-line purpose + (optional) naming conventions block + public API list.
- Section dividers: `# ── Section ──` (box-drawing chars, consistent across files).
- Function docstrings: one line above the function declaration for anything public.
