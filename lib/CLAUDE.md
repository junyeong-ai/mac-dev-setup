# lib/ — module internals

Loaded when Claude reads files in this directory. See `../CLAUDE.md` for project-level architecture.

## File responsibilities

| File | Public API |
|------|------------|
| `log.sh` | `LOG_FILE`, `log_init`, `log_path`, `say_step`/`say_info`/`say_detail`/`say_warn`/`say_error`/`say_debug`, `run_interactive`, `run_with_tee`, `run_silent` |
| `ui.sh` | `show_logo`, `track_*`, `ui_*`, Catppuccin Mocha color constants (`C_MAUVE`, `C_BLUE`, ...) |
| `registry.sh` | `REGISTRY` array, `reg_keys`, `reg_keys_by_type`, `reg_keys_by_tier`, `reg_field`, `reg_check_passes`, `reg_default_keys`, `reg_types`, `type_ui_title`, `type_log_title`, `validate_registry` |
| `bootstrap.sh` | `ensure_supported_system`, `activate_homebrew`, `activate_mise`, `bootstrap_homebrew`, `bootstrap_homebrew_metadata`, `bootstrap_gum`, `run_bootstrap` |
| `installers.sh` | `install_key`, `install_brew`, `install_brew_cask`, `install_mise`, `install_npm`, `install_zinit`, `install_git_defaults`, `install_git_lfs`, `install_macos_*` |
| `orchestrator.sh` | `run_install` |
| `doctor.sh` | `run_doctor` |
| `configs.sh` | `deploy_configs` |
| `backup.sh` | `backup_configs`, `BACKUP_DIR` |

## Output strategy primitives (lib/log.sh)

Every shell-out picks one of three runners based on the user contract:

| Runner | Redirection | When to use |
|--------|-------------|-------------|
| `run_interactive <cmd>` | none (full TTY pass-through) | command owns the terminal — sudo prompts, "Press RETURN", first-time Homebrew install |
| `run_with_tee <cmd>` | `2>&1 | tee -a "$LOG_FILE"` | long operation where progress matters and we also want a copy in the log (`brew update`, `brew install gum`) |
| `run_silent <cmd>` | `>> "$LOG_FILE" 2>&1` | uninteresting output, hidden behind a `track_*` UI step |

All three return the wrapped command's exit code. Callers **must** wrap them in `if !` / `||` so `set -e` does not abort the script before the error path runs. The three runners also emit `CMD` / `EXIT` records to the log so post-mortem diffs are unambiguous.

`say_step` / `say_info` / `say_warn` / `say_error` / `say_debug` are the plain-text channels usable before gum is installed. They mirror their message to the log with the matching level prefix. `say_warn`/`say_error` go to stderr; the others to stdout.

`say_detail` emits an indented line with no leading marker — use it to elaborate after a `say_error`/`say_warn`/`say_step` without repeating the `✗`/`!`/`▶` prefix on every line. It goes to stderr (it most often follows a failure).

## Signal handling in interactive gum prompts

`gum choose` / `gum confirm` exit with code 130 when the user presses Ctrl+C. Inside a command substitution (`selected=$(gum choose …)`), a bare `exit 130` only terminates the subshell — the parent script then sees an empty selection and silently advances to the next step. All interactive gum calls go through `_gum_run` (defined in `ui.sh`), which relays SIGINT to the top-level shell with `kill -INT $$` so `setup.sh`'s INT trap fires and the whole script aborts cleanly. Only the interactive subcommands (`choose`, `confirm`) need the wrapper; `gum style` is rendering-only and runs to completion without prompting.

## Installer contract

Every function whose name matches `install_<TOKEN>` — including `install_macos_*` — must:

1. **Accept `(key, arg1, arg2, ...)`**. The first argument is the registry key.
2. **Be idempotent**. Check for already-installed before doing work; if so, emit `track_success` and return 0.
3. **Resolve labels via registry**: `label=$(reg_field "$key" label)`; never hardcode the display string.
4. **Log long-running package commands to `$LOG_FILE`**: redirect stdout + stderr of Homebrew, mise, npm, git clone, and setup commands with `>> "$LOG_FILE" 2>&1`.
5. **Verify through the registry**: after mutating package/config state, call `_finish_registry_key "$key" "$label"` or a wrapper such as `_finish_macos_setting "$key"` so `reg_check_passes` is the success criterion.
6. **Return discipline**: `return 0` on success, non-zero on failure. Do not call `exit`, do not call `_handle_failure` or any retry logic — `install_key` owns recovery.

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

## Bootstrap layer

`run_bootstrap install` (defined in `bootstrap.sh`) runs:

1. `ensure_supported_system` — Apple Silicon + Darwin check.
2. `bootstrap_homebrew` — pre-flight (admin group warning, installer reachability), download installer to a temp file, run it via `run_interactive` (or `run_with_tee` + `NONINTERACTIVE=1` under `CI_MODE`), then verify `/opt/homebrew/bin/brew` exists.
3. `bootstrap_homebrew_metadata` — `brew update` via `run_with_tee` so the user can watch progress.
4. `bootstrap_gum` — `brew install gum` via `run_with_tee`.

Bootstrap primitives **must not** use `track_*` / `gum style` (gum isn't installed yet) and **must not** call `exit` — only `run_bootstrap` exits on failure. They emit progress via `say_*`. The Homebrew installer is invoked with `run_interactive` so its sudo prompt, "Press RETURN to continue", and Xcode CLT progress reach the user's terminal. Redirecting that command to a log file is a bug: it hides interactive prompts, triggers Homebrew's NONINTERACTIVE-mode fallbacks, and leaves the user staring at a dead-looking terminal.

`doctor` calls `ensure_supported_system`, `activate_homebrew`, and `activate_mise` directly; it may load existing tool shims into PATH but must not install Homebrew, mise, or gum. `activate_mise` uses shims-only activation so doctor does not install shell hooks or emit mise hook noise.

After `run_bootstrap`, the rest of the script is free to use the full UI vocabulary (`track_*`, `ui_*`, `gum style`).

## macOS finalization

macOS installers may set globals (`_macos_needs_finder_restart`, `_macos_needs_dock_restart`). After all macOS-type installers complete, the orchestrator calls `_macos_finalize` once to `killall Finder` / `killall Dock` as needed.

## Configs deployment

`deploy_configs <keys>` runs after tool installation. Key behaviors:

- **`.zshrc`**: extracts content between `# >>> user-managed >>>` / `# <<< user-managed <<<` from the existing file, copies the template, re-injects the preserved block. Never overwrites user customizations in that region.
- **`.zprofile`**: owns only the Homebrew shellenv block between `# >>> mac-dev-setup: homebrew >>>` / `# <<< mac-dev-setup: homebrew <<<`. Existing unmarked `/opt/homebrew/bin/brew shellenv` lines are normalized into that block while unrelated lines are preserved.
- **Ghostty / Starship / bat / lazygit**: deployed only if the corresponding key was selected and the binary/app is available.
- **Git**: baseline defaults are handled by the `git_defaults` registry key. Delta-specific settings are added only when `git_delta` was selected and `delta` is installed. Git LFS has its own installer because it requires global filter initialization after the binary is installed.
- **Neovim**: managed only when the `neovim` key is selected. A fresh config gets LazyVim starter; an existing non-LazyVim config is left untouched.

## Doctor

`run_doctor` walks the registry through `reg_check_passes`. Empty CHECK falls back to `command -v $key` for types `cli | git | runtime | ai`. Types without a command-equivalent (shell, font, app, macos) must provide an explicit CHECK. `DEPS` affects install order only. Doctor reports `essential` and `recommended` failures as missing baseline items; failed `extra` checks are neutral optional rows. Config diagnostics check managed markers/theme patterns, so a file can be present but reported as outdated.

## When adding a new installer token

1. Add `install_<TOKEN>` to `installers.sh` following the contract above.
2. Add a registry record pointing to it.
3. On next run, `validate_registry` confirms schema validity, dependency graph validity, and the dispatch link at startup.

Keep registry labels comma-free. The interactive selector passes default labels to gum as one comma-separated value, and `validate_registry` enforces this UI contract.
