# Mac Dev Setup

Registry-driven Apple Silicon macOS developer environment bootstrapper (bash, Homebrew, gum UI, Catppuccin Mocha).

## Commands

```bash
bash setup.sh              # Interactive install
bash setup.sh --ci         # Non-interactive (essential + recommended)
bash setup.sh doctor       # Diagnose current environment
bash setup.sh --help       # Usage
```

## Architecture

Everything is driven by a single `REGISTRY` array in `lib/registry.sh`. Each record declares what to install, how, and how to verify it. Every other subsystem consumes the registry:

- **Selection UI** pre-checks items with `tier ∈ {essential, recommended}`.
- **`--ci` mode** installs the same default set with no prompt.
- **`install_key <key>`** resolves `INSTALLER` + `ARGS` from the registry and dispatches to `install_<INSTALLER>`.
- **Dependency expansion** installs registry `DEPS` before the selected key.
- **Verification** uses `reg_check_passes`, so installers and `doctor` share each record's `CHECK` expression. `extra` failures are optional, while `essential` and `recommended` failures are baseline drift.
- **Schema is validated at startup** by `validate_registry` — malformed records, duplicate keys, invalid enums, dependency errors, and broken dispatch links abort before any work runs.

Registry record shape (8 pipe-separated fields):

```
KEY | TYPE | LABEL | INSTALLER | ARGS | TIER | DEPS | CHECK
```

See `lib/CLAUDE.md` for installer contracts and `lib/registry.sh` for the canonical field spec.

## Layers

| Layer | File | Runs when | Output vocabulary |
|-------|------|-----------|--------------------|
| Log / I/O | `lib/log.sh` | Always (zero deps) | `say_step`/`say_info`/`say_warn`/`say_error`/`say_debug`; `run_interactive`/`run_with_tee`/`run_silent` |
| Bootstrap | `lib/bootstrap.sh` | First — installs Homebrew + gum | `say_*` only (gum not yet available) |
| Install UI | `lib/ui.sh` + `orchestrator.sh` + `installers.sh` | After bootstrap | `track_*`, `ui_*` (gum-based) |
| Doctor | `lib/doctor.sh` | Independent | own `_doctor_*` helpers |

The split is load-bearing: bootstrap may not use `track_*`/`gum style` because gum is not yet installed. Install primitives (`install_*`) may not use `say_*` for normal flow — they belong to the gum trackline. Both layers share `run_silent` for log capture so the file format stays uniform.

## Output strategy

Pick the runner that matches what the user should see:

- `run_interactive <cmd>` — no redirection, full TTY pass-through. Use for commands that own the terminal (Homebrew first-time install, sudo prompts).
- `run_with_tee <cmd>` — stream stdout+stderr to user *and* append to log. Use for long-running operations where progress matters (`brew update`, `brew install gum`).
- `run_silent <cmd>` — log-only. Use inside an install primitive wrapped by a `track_*` UI step.

All three return the wrapped command's exit code. **Callers must wrap them in `if !` or `||`**; otherwise `set -e` will abort before the error path can run.

## Extending

**Add a new tool** — one record to `REGISTRY` in `lib/registry.sh`:

```
"httpie|cli|httpie (HTTP client)|brew|httpie|extra||brew list --formula httpie && command -v http"
```

Then startup validation catches any typo. Everything else (UI, CI, doctor) picks it up automatically.

**Add a new INSTALLER token** — define `install_<TOKEN>` in `lib/installers.sh` following the installer contract in `lib/CLAUDE.md`. Capture command output via `run_silent`.

**Add a new macOS setting** — add the registry record and a dedicated `install_macos_<key>` function. Use `reg_field "$key" label` for the success message; never hardcode.

**Add a new bootstrap step** — add a `bootstrap_<name>` function to `lib/bootstrap.sh` that returns 0/non-zero (never `exit`), then invoke it from `run_bootstrap`. Use `run_interactive` if the step needs the terminal, otherwise `run_with_tee`.

## Naming conventions

| Prefix | Purpose |
|--------|---------|
| `activate_*` | Environment activation without installation (Homebrew/mise PATH) |
| `bootstrap_*` | Bootstrap primitive (system, Homebrew, gum) — returns 0/non-zero, never exits |
| `install_*` | Installer invoked by dispatch |
| `reg_*` | Registry accessor |
| `type_*` | Type-to-display helper |
| `run_*` | Subcommand entry (`run_bootstrap`, `run_install`, `run_doctor`) and output-strategy primitives (`run_interactive`, `run_with_tee`, `run_silent`) |
| `say_*` | Plain-text output channel (bootstrap-safe) |
| `log_*` | Log-file lifecycle |
| `deploy_*`, `backup_*` | Config lifecycle |
| `validate_*` | Schema validation |
| `track_*`, `ui_*`, `show_*` | gum-based UI primitives (install phase only) |
| `_*` | File-private helper |

## Invariants

- **User-facing strings in Korean**: gum labels, registry `LABEL` field, selection prompts. Everything else (code, comments, log output, section headers, function names) is English.
- **`.zshrc` user-managed block**: the template contains `# >>> user-managed >>>` / `# <<< user-managed <<<` markers. `lib/configs.sh` preserves everything between them across re-runs. Never put managed content inside these markers.
- **`.zprofile` Homebrew block**: `lib/configs.sh` normalizes `/opt/homebrew/bin/brew shellenv` into the managed mac-dev-setup block and preserves unrelated shell initialization.
- **Registry field separator**: `|` is forbidden inside any field. Pipes in CHECK expressions cause false positives (pipeline exit code is the last command's). Use `&>/dev/null` instead of `| head -1`.
- **Registry labels**: `LABEL` must not contain `,` because gum receives selected defaults as a comma-separated value.
- **Catppuccin Mocha** is applied by `lib/configs.sh` to each selected config file that is deployed. It is not a user-selectable option.
- **Bash 3.2 target**: macOS ships bash 3.2. No associative arrays (`declare -A`), no namerefs (`declare -n`), no `mapfile`/`readarray`.

## Anti-patterns

- ❌ Hardcoding display strings in installers — always use `reg_field "$key" label`.
- ❌ Calling retry/error-recovery inside a primitive installer — primitives just `return 1`; `install_key` handles recovery.
- ❌ Using `track_*` or `gum style` before `run_bootstrap` — gum is not yet installed. Bootstrap primitives (`bootstrap_*`) use `say_*`.
- ❌ Redirecting an interactive command to the log file (`cmd >> "$LOG_FILE" 2>&1`) — this hides sudo prompts, "Press RETURN", and Homebrew's progress. Use `run_interactive` so the user can see and answer.
- ❌ Calling a fallible command at top level instead of through a runner — bare `cmd >> "$LOG_FILE" 2>&1` exits the parent under `set -e` before the error branch runs. Always wrap shell-outs in `run_silent` / `run_with_tee` and check the return with `if !`.
- ❌ Calling `exit` from a `bootstrap_*` primitive — only `run_bootstrap` decides termination, so primitives can be composed in any order.
- ❌ Adding a "preset" abstraction — tiers on individual records already drive defaults.
- ❌ Removing or renaming the `# >>> user-managed >>>` / `# <<< user-managed <<<` markers in `configs/zshrc` — `lib/configs.sh` preservation logic matches them literally; without them, user content is silently dropped on re-deploy.

@README.md
