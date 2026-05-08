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

## Extending

**Add a new tool** — one record to `REGISTRY` in `lib/registry.sh`:

```
"httpie|cli|httpie (HTTP client)|brew|httpie|extra||brew list --formula httpie && command -v http"
```

Then startup validation catches any typo. Everything else (UI, CI, doctor) picks it up automatically.

**Add a new INSTALLER token** — define `install_<TOKEN>` in `lib/installers.sh` following the installer contract in `lib/CLAUDE.md`.

**Add a new macOS setting** — add the registry record and a dedicated `install_macos_<key>` function. Use `reg_field "$key" label` for the success message; never hardcode.

## Naming conventions

| Prefix | Purpose |
|--------|---------|
| `activate_*` | Environment activation without installation |
| `ensure_*` | Bootstrap primitive (system, brew metadata, gum) — safe before gum is available |
| `install_*` | Installer invoked by dispatch |
| `reg_*` | Registry accessor |
| `type_*` | Type-to-display helper |
| `run_*` | Subcommand entry (`run_bootstrap`, `run_install`, `run_doctor`) |
| `deploy_*`, `backup_*` | Config lifecycle |
| `validate_*` | Schema validation |
| `track_*`, `ui_*`, `show_*` | UI primitives |
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
- ❌ Using `track_*` or `gum style` before `run_bootstrap` — bootstrap installs gum. Bootstrap primitives (`ensure_homebrew`, `ensure_gum`) use plain `echo`.
- ❌ Adding a "preset" abstraction — tiers on individual records already drive defaults.
- ❌ Removing or renaming the `# >>> user-managed >>>` / `# <<< user-managed <<<` markers in `configs/zshrc` — `lib/configs.sh` preservation logic matches them literally; without them, user content is silently dropped on re-deploy.

@README.md
