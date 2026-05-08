# lib/ — module internals

Loaded when Claude reads files in this directory. See `../CLAUDE.md` for project-level architecture.

## File responsibilities

| File | Public API |
|------|------------|
| `registry.sh` | `REGISTRY` array, `reg_keys`, `reg_keys_by_type`, `reg_keys_by_tier`, `reg_field`, `reg_default_keys`, `reg_types`, `type_ui_title`, `type_log_title`, `validate_registry` |
| `installers.sh` | `ensure_supported_system`, `activate_homebrew`, `activate_mise`, `ensure_homebrew`, `ensure_homebrew_metadata`, `ensure_gum`, `install_key`, `install_brew`, `install_brew_cask`, `install_mise`, `install_npm`, `install_zinit`, `install_git_lfs`, `install_macos_*` |
| `orchestrator.sh` | `run_bootstrap`, `run_install` |
| `doctor.sh` | `run_doctor` |
| `configs.sh` | `deploy_configs` |
| `backup.sh` | `backup_configs`, `BACKUP_DIR` |
| `ui.sh` | `show_logo`, `track_*`, `ui_*`, Catppuccin Mocha color constants (`C_MAUVE`, `C_BLUE`, ...) |

## Installer contract

Every function whose name matches `install_<TOKEN>` — including `install_macos_*` — must:

1. **Accept `(key, arg1, arg2, ...)`**. The first argument is the registry key.
2. **Be idempotent**. Check for already-installed before doing work; if so, emit `track_success` and return 0.
3. **Resolve labels via registry**: `label=$(reg_field "$key" label)`; never hardcode the display string.
4. **Log to `$LOG_FILE`**: redirect stdout + stderr of install commands with `>> "$LOG_FILE" 2>&1`.
5. **Return discipline**: `return 0` on success, non-zero on failure. Do not call `exit`, do not call `_handle_failure` or any retry logic — `install_key` owns recovery.

## Dispatch mechanics

`install_key <key>`:

1. Looks up `INSTALLER` and `ARGS` via `reg_field`.
2. Word-splits `ARGS` into an array.
3. Invokes `install_<INSTALLER> "$key" "${argv[@]}"`.
4. On non-zero return, runs an iterative `while true` loop:
   - Interactive TTY: prompts `Retry / Skip / Abort` via `ui_error_action`.
   - Non-interactive or `CI_MODE=true`: returns non-zero so partial setup is visible.
5. Returns 0 once the installer succeeds or the interactive user skips.

Before execution, `orchestrator.sh` expands the selected key set through each
record's `DEPS` field and installs in dependency-first order. This keeps setup
order explicit in the registry instead of baking dependency assumptions into
category order.

## Bootstrap caveat

`run_bootstrap install` runs `ensure_supported_system`, `ensure_homebrew`, `ensure_homebrew_metadata`, then `ensure_gum` before the install UI. These functions and anything they may reach must use **plain `echo`** — `track_*` and `gum style` require gum to be present. `doctor` calls `ensure_supported_system`, `activate_homebrew`, and `activate_mise` directly; it may load existing tool shims into PATH but must not install Homebrew, mise, or gum. `activate_mise` uses shims-only activation so doctor does not install shell hooks or emit mise hook noise.

After `run_bootstrap`, the rest of the script is free to use the full UI vocabulary.

## macOS finalization

macOS installers may set globals (`_macos_needs_finder_restart`, `_macos_needs_dock_restart`). After all macOS-type installers complete, the orchestrator calls `_macos_finalize` once to `killall Finder` / `killall Dock` as needed.

## Configs deployment

`deploy_configs <keys>` runs after tool installation. Key behaviors:

- **`.zshrc`**: extracts content between `# >>> user-managed >>>` / `# <<< user-managed <<<` from the existing file, copies the template, re-injects the preserved block. Never overwrites user customizations in that region.
- **Ghostty / Starship / bat / lazygit**: deployed only if the corresponding key was selected and the binary/app is available.
- **Git**: baseline defaults are handled by the `git_defaults` registry key. Delta-specific settings are added only when `git_delta` was selected and `delta` is installed. Git LFS has its own installer because it requires global filter initialization after the binary is installed.
- **Neovim**: managed only when the `neovim` key is selected. A fresh config gets LazyVim starter; an existing non-LazyVim config is left untouched.

## Doctor

`run_doctor` walks the registry and evaluates each `CHECK` expression with `eval`. Empty CHECK falls back to `command -v $key` for types `cli | git | runtime | ai`. Types without a command-equivalent (shell, font, app, macos) must provide an explicit CHECK. `DEPS` affects install order only; doctor reports the state of each registry key independently. Config diagnostics check managed markers/theme patterns, so a file can be present but reported as outdated.

## When adding a new installer token

1. Add `install_<TOKEN>` to `installers.sh` following the contract above.
2. Add a registry record pointing to it.
3. On next run, `validate_registry` confirms schema validity, dependency graph validity, and the dispatch link at startup.
