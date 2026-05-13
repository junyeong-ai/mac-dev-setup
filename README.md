# Mac Dev Setup

One-command Apple Silicon macOS development environment bootstrap — registry-driven, tier-based, Catppuccin Mocha themed.

```bash
bash setup.sh
```

## Features

- **Registry-driven** — every installable option lives in `lib/registry.sh` as a single declarative record. Adding a new tool is one line.
- **Tier-based defaults** — each option has a tier (`essential` / `recommended` / `extra`). Essential + recommended are pre-checked in the UI and installed by `--ci`.
- **Category-based interactive selection** via [gum](https://github.com/charmbracelet/gum) with Clack-style trackline UI.
- **Unified Catppuccin Mocha theme** across terminal, prompt, editor, and CLI tools.
- **Idempotent repair** — safe to re-run; skips healthy items and repairs selected Homebrew-managed installs when their registry check fails.
- **User-managed .zshrc block** — customizations between `# >>> user-managed >>>` / `# <<< user-managed <<<` markers are preserved on re-deploy.
- **Auto-backup** — existing dotfiles saved to `~/.dotfiles-backup/` before any changes.
- **CI mode** — `bash setup.sh --ci` installs `essential + recommended` non-interactively and fails on install errors.
- **Doctor** — `bash setup.sh doctor` walks the registry without changing package state, reports baseline drift as missing, and marks uninstalled `extra` tools as optional.
- **Bootstrap scope** — refreshes Homebrew package metadata once, then installs missing selected tools from current Homebrew, mise, and npm stable/LTS channels. Registry dependencies are added automatically so first-run setup order is deterministic.

## Architecture

```
setup.sh                  # Entry point: arg parsing → bootstrap → orchestrator/doctor
lib/
├── log.sh                # say_* channels + run_interactive/run_with_tee/run_silent
├── ui.sh                 # Catppuccin Mocha trackline UI primitives (gum)
├── registry.sh           # REGISTRY data + accessors (single source of truth)
├── bootstrap.sh          # System check + Homebrew + gum bootstrap (uses log.sh)
├── installers.sh         # install_* primitives + dispatch via install_key
├── orchestrator.sh       # Selection UI + install execution loop
├── doctor.sh             # Registry-driven diagnostics
├── backup.sh             # Dotfile backup
└── configs.sh            # Config deployment with user-block preservation
configs/
├── zshrc                 # Zsh (Zinit + Starship + modern aliases)
├── ghostty.config
├── starship.toml
├── bat.config
└── lazygit.yml
```

Re-running the setup is idempotent and repairs managed package/configuration state while preserving user-managed shell customizations.

### Registry schema

Each record is a pipe-separated 8-tuple:

```
KEY | TYPE | LABEL | INSTALLER | ARGS | TIER | DEPS | CHECK
```

| Field | Meaning |
|-------|---------|
| `KEY` | Stable snake_case identifier (`eza`, `claude_code`, `macos_dock`) |
| `TYPE` | `shell` · `font` · `cli` · `git` · `runtime` · `ai` · `app` · `macos` |
| `LABEL` | Display string (Korean allowed) |
| `INSTALLER` | Dispatch token → `install_<INSTALLER>` function |
| `ARGS` | Whitespace-separated arguments to the installer |
| `TIER` | `essential` · `recommended` · `extra` |
| `DEPS` | Whitespace-separated registry keys that must install first |
| `CHECK` | Shell expression for installer and doctor verification (empty = type default) |

`LABEL` must not contain `,`; the interactive selector passes default labels to gum as a comma-separated value and `validate_registry` enforces that contract.

### Installer dispatch

```
install_key <key>
  └─ runs after selected keys are expanded through DEPS
     └─ looks up INSTALLER + ARGS in registry
        └─ calls install_<INSTALLER> <key> <args...>
```

Available installer tokens:

| Token | Function | Purpose |
|-------|----------|---------|
| `brew` | `install_brew` | Homebrew formula |
| `brew_cask` | `install_brew_cask` | Homebrew cask |
| `mise` | `install_mise` | mise-managed runtime (self-bootstraps mise) |
| `npm` | `install_npm` | Global npm package (self-bootstraps Node) |
| `zinit` | `install_zinit` | Git-clone Zinit plugin manager |
| `git_lfs` | `install_git_lfs` | Git LFS binary + global filter setup |
| `macos_<key>` | `install_macos_<key>` | Dedicated macOS defaults writer |

The Catppuccin Mocha theme is applied by `lib/configs.sh` to selected config files as they are deployed — it is not a registry option.

### Naming conventions

| Prefix | Use |
|--------|-----|
| `activate_*` | Environment activation without installation (`activate_homebrew`, `activate_mise`) |
| `bootstrap_*` | Bootstrap primitive (Homebrew, gum, metadata) — returns 0/non-zero, never exits |
| `install_*` | Installer primitive called by dispatch (`install_brew`, `install_macos_dock`, …) |
| `reg_*` | Registry accessor (`reg_keys`, `reg_field`, …) |
| `type_*` | Type-to-display helper (`type_ui_title`, `type_log_title`) |
| `ui_*` | UI primitive returning a value to the caller |
| `track_*` | Trackline output (user-visible progress) |
| `say_*` | Plain-text output channel (bootstrap-safe; mirrors to log) |
| `log_*` | Log-file lifecycle (`log_init`, `log_path`) |
| `run_*` | Subcommand entry (`run_bootstrap`, `run_install`, `run_doctor`) and output-strategy primitives (`run_interactive`, `run_with_tee`, `run_silent`) |
| `deploy_*`, `backup_*` | Config lifecycle (`deploy_configs`, `backup_configs`) |
| `validate_*` | Schema validation (`validate_registry`) |
| `_*` | File-private helper |

### Output strategy primitives

Every shell-out picks one of three runners (defined in `lib/log.sh`) based on what the user should see:

| Runner | Redirection | Use for |
|--------|-------------|---------|
| `run_interactive <cmd>` | none (full TTY) | commands that own the terminal — sudo prompts, Homebrew first-time install |
| `run_with_tee <cmd>` | stdout+stderr to user *and* log | long operations with meaningful progress (`brew update`, `brew install gum`) |
| `run_silent <cmd>` | log-only | uninteresting output hidden behind a `track_*` UI step |

All three return the wrapped command's exit code. Wrap them with `if !` / `||` so `set -e` does not abort before the error path runs.

## Usage

```bash
# Interactive install
bash setup.sh

# Non-interactive install (essential + recommended)
bash setup.sh --ci

# Diagnose current environment
bash setup.sh doctor
```

## Adding a new option

To add a new tool, append one record to `REGISTRY` in `lib/registry.sh`:

```bash
"my_tool|cli|my_tool (설명)|brew|my-tool|recommended||brew list --formula my-tool && command -v my-tool"
```

That's it. The option now appears in:

- The interactive selection UI (under its type, pre-checked if `essential`/`recommended`)
- The `--ci` install set (if tier qualifies)
- Dependency expansion (if another selected key lists it in `DEPS`)
- The doctor output (using the `CHECK` expression)

Doctor treats `essential` and `recommended` failures as missing baseline items. `extra` failures are shown as optional so unselected tools do not look like setup failures.

If your installer isn't one of the built-in tokens, add a new `install_<token>` function to `lib/installers.sh`.

## Adding a new macOS setting

```bash
# Registry record
"macos_dark_mode|macos|다크 모드 고정|macos_dark_mode||recommended||[ \"\$(defaults read -g AppleInterfaceStyle 2>/dev/null)\" = Dark ]"

# Installer function in lib/installers.sh
install_macos_dark_mode() {
  local key=$1
  defaults write NSGlobalDomain AppleInterfaceStyle -string Dark || return 1
  _finish_macos_setting "$key"
}
```

## Preserving user .zshrc customizations

The deployed `~/.zshrc` contains a user-managed block:

```zsh
# >>> user-managed >>>
# Add your custom env vars, aliases, functions here.
export MY_ENV=value
# <<< user-managed <<<
```

On re-run, the installer extracts the content between these markers from the existing `~/.zshrc` and re-injects it into the freshly deployed template. You can safely run `setup.sh` repeatedly without losing personal customizations.

## Requirements

- Apple Silicon Mac
- Homebrew (auto-installed if missing)
- Bash 3.2+ (macOS default; no associative arrays used)
- [gum](https://github.com/charmbracelet/gum) (auto-installed if missing)

## License

MIT
