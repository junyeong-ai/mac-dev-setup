# Mac Dev Setup

One-command macOS development environment setup — registry-driven, tier-based, Catppuccin Mocha themed.

```bash
bash setup.sh
```

## Features

- **Registry-driven** — every installable option lives in `lib/registry.sh` as a single declarative record. Adding a new tool is one line.
- **Tier-based defaults** — each option has a tier (`essential` / `recommended` / `extra`). Essential + recommended are pre-checked in the UI and installed by `--ci`.
- **7-step interactive selection** via [gum](https://github.com/charmbracelet/gum) with Clack-style trackline UI.
- **Unified Catppuccin Mocha theme** across terminal, prompt, editor, and CLI tools.
- **Idempotent** — safe to re-run; skips already-installed items.
- **User-managed .zshrc block** — customizations between `# >>> user-managed >>>` / `# <<< user-managed <<<` markers are preserved on re-deploy.
- **Auto-backup** — existing dotfiles saved to `~/.dotfiles-backup/` before any changes.
- **CI mode** — `bash setup.sh --ci` installs `essential + recommended` non-interactively.
- **Doctor** — `bash setup.sh doctor` walks the registry and reports what's installed, with theme consistency and git checks.

## Architecture

```
setup.sh                  # Entry point: arg parsing → orchestrator/doctor
lib/
├── registry.sh           # REGISTRY data + accessors (single source of truth)
├── installers.sh         # install_* primitives + dispatch via install_key
├── ui.sh                 # Catppuccin Mocha trackline UI primitives
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

### Registry schema

Each record is a pipe-separated 7-tuple:

```
KEY | TYPE | LABEL | INSTALLER | ARGS | TIER | CHECK
```

| Field | Meaning |
|-------|---------|
| `KEY` | Stable snake_case identifier (`eza`, `claude_code`, `macos_dock`) |
| `TYPE` | `shell` · `font` · `cli` · `runtime` · `ai` · `app` · `macos` |
| `LABEL` | Display string (Korean allowed) |
| `INSTALLER` | Dispatch token → `install_<INSTALLER>` function |
| `ARGS` | Whitespace-separated arguments to the installer |
| `TIER` | `essential` · `recommended` · `extra` |
| `CHECK` | Shell expression for doctor (empty = type default) |

### Installer dispatch

```
install_key <key>
  └─ looks up INSTALLER + ARGS in registry
     └─ calls install_<INSTALLER> <key> <args...>
```

Available installer tokens:

| Token | Function | Purpose |
|-------|----------|---------|
| `brew` | `install_brew` | Homebrew formula |
| `brew_cask` | `install_brew_cask` | Homebrew cask (with app-dir check) |
| `mise` | `install_mise` | mise-managed runtime (self-bootstraps mise) |
| `npm` | `install_npm` | Global npm package (self-bootstraps Node) |
| `zinit` | `install_zinit` | Git-clone Zinit plugin manager |
| `macos_<key>` | `install_macos_<key>` | Dedicated macOS defaults writer |

The Catppuccin Mocha theme is applied by `lib/configs.sh` when config files are deployed — it is not a registry option.

### Naming conventions

| Prefix | Use |
|--------|-----|
| `ensure_*` | Bootstrap primitive (brew, gum) — callable before gum is available |
| `install_*` | Installer primitive called by dispatch (`install_brew`, `install_macos_dock`, …) |
| `reg_*` | Registry accessor (`reg_keys`, `reg_field`, …) |
| `type_*` | Type-to-display helper (`type_ui_title`, `type_log_title`) |
| `ui_*` | UI primitive returning a value to the caller |
| `track_*` | Trackline output (user-visible progress) |
| `run_*` | Subcommand entry point (`run_bootstrap`, `run_install`, `run_doctor`) |
| `deploy_*`, `backup_*` | Config lifecycle (`deploy_configs`, `backup_configs`) |
| `validate_*` | Schema validation (`validate_registry`) |
| `_*` | File-private helper |

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
"my_tool|cli|my_tool (설명)|brew|my-tool|recommended|command -v my-tool"
```

That's it. The option now appears in:

- The interactive selection UI (under its type, pre-checked if `essential`/`recommended`)
- The `--ci` install set (if tier qualifies)
- The doctor output (using the `CHECK` expression)

If your installer isn't one of the built-in tokens, add a new `install_<token>` function to `lib/installers.sh`.

## Adding a new macOS setting

```bash
# Registry record
"macos_dark_mode|macos|다크 모드 고정|macos_dark_mode||recommended|[ \"\$(defaults read -g AppleInterfaceStyle 2>/dev/null)\" = Dark ]"

# Installer function in lib/installers.sh
install_macos_dark_mode() {
  local key=$1
  defaults write NSGlobalDomain AppleInterfaceStyle -string Dark
  track_success "$(reg_field "$key" label)"
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

- macOS (Apple Silicon or Intel)
- Homebrew (auto-installed if missing)
- Bash 3.2+ (macOS default; no associative arrays used)
- [gum](https://github.com/charmbracelet/gum) (auto-installed if missing)

## License

MIT
