# Mac Dev Setup

One-command macOS development environment setup with interactive preset selection, Catppuccin Mocha theming, and post-install diagnostics.

```bash
bash setup.sh
```

## Features

- **4 presets** — Minimal, Standard, Full, Custom
- **6-step interactive selection** using [gum](https://github.com/charmbracelet/gum) with Clack-style trackline UI
- **Unified Catppuccin Mocha theme** across terminal, prompt, editor, and CLI tools
- **Idempotent** — safe to re-run; skips already-installed items
- **Auto-backup** — existing dotfiles saved to `~/.dotfiles-backup/` before any changes
- **CI mode** — non-interactive Standard preset install via `bash setup.sh --ci`
- **Doctor** — post-install environment diagnostic via `bash setup.sh doctor`

## What Gets Installed

### Shell & Terminal

| Option | Description |
|--------|-------------|
| [Ghostty](https://ghostty.org) | GPU-accelerated terminal (semi-transparent + blur) |
| [Oh My Zsh](https://ohmyz.sh) + [Zinit](https://github.com/zdharma-continuum/zinit) | Zsh framework + plugin manager (fast-syntax-highlighting, autosuggestions, completions) |
| [Starship](https://starship.rs) | Minimal two-segment prompt |
| [SCM Breeze](https://github.com/scmbreeze/scm_breeze) | Git shortcut aliases |
| Catppuccin Mocha | Unified color theme across tools |

### Fonts (5)

| Font | Type |
|------|------|
| Hack Nerd Font Mono | Coding + icons |
| JetBrains Mono Nerd Font | Coding + icons |
| Sarasa Gothic | CJK unified |
| Noto Sans CJK KR | Korean |
| Pretendard | Korean UI |

### CLI Tools (22)

Three tiers: **essential**, **recommended**, **extra**.

| Tier | Tools |
|------|-------|
| Essential | eza, bat, fd, ripgrep, fzf |
| Recommended | zoxide, lazygit, delta, btop, dust, duf, navi, fastfetch |
| Extra | lazydocker, procs, sd, tokei, hyperfine, glow, jq, yq, tlrc |

### Runtimes & Package Managers

| Tool | Description |
|------|-------------|
| [mise](https://mise.jdx.dev) | Version manager (replaces nvm/asdf) |
| Node.js LTS | Installed via mise |
| Python 3.12 | Installed via mise |
| Go | Installed via mise |
| Rust | Installed via rustup |
| pnpm | Node package manager |
| uv | Python package manager |

### Apps (8)

| App | Description |
|------|-------------|
| Raycast | Spotlight replacement |
| OrbStack | Docker desktop alternative |
| AltTab | Window switcher |
| Stats | System monitor |
| Shottr | Screenshot + OCR |
| Karabiner-Elements | Key remapping |
| Visual Studio Code | Editor |
| Cursor | AI editor |

### macOS Settings (7)

- Key repeat speed optimization (KeyRepeat: 2, InitialKeyRepeat: 15)
- Finder: show hidden files
- Finder: show path bar
- Dock: auto-hide + fast animation
- Mission Control: accelerated animation
- Screenshots saved to `~/Screenshots`
- Remove "Last login" terminal message

## Config Files

All configs use **Catppuccin Mocha** color palette:

```
configs/
  zshrc            # Aliases, plugins, fzf colors, zoxide, navi, mise
  ghostty.config   # Transparency, blur, Hack Nerd Font, split keybinds
  starship.toml    # Two-segment prompt with full palette
  bat.config       # Theme + line numbers
  lazygit.yml      # Catppuccin border/highlight colors
```

Deployed to `$HOME` by `lib/configs.sh`, which also configures:
- **Git** — default branch `main`, rebase pull, delta side-by-side diff
- **Neovim** — LazyVim starter with Catppuccin plugin

## Project Structure

```
setup.sh              # Entry point (presets, 6-step installer, CI mode)
lib/
  ui.sh               # Clack-style trackline UI + Catppuccin colors
  brew.sh             # Homebrew install + brew_install/brew_install_cask
  backup.sh           # Dotfile backup to ~/.dotfiles-backup/
  shell.sh            # Ghostty, Oh My Zsh, Zinit, Starship, SCM Breeze
  fonts.sh            # 5 coding/CJK fonts via Homebrew Cask
  cli-tools.sh        # 22 CLI tools with X-of-Y progress
  runtime.sh          # mise + Node/Python/Go/Rust + pnpm/uv
  apps.sh             # 8 productivity apps via Homebrew Cask
  macos.sh            # 7 macOS system preference tweaks
  configs.sh          # Config deployment + git/delta + LazyVim
  doctor.sh           # Full environment diagnostic
configs/
  zshrc               # Zsh configuration
  ghostty.config      # Ghostty terminal configuration
  starship.toml       # Starship prompt configuration
  bat.config          # bat configuration
  lazygit.yml         # lazygit configuration
```

## Usage

```bash
# Interactive install (recommended)
bash setup.sh

# Non-interactive CI mode (Standard preset)
bash setup.sh --ci

# Diagnose current environment
bash setup.sh doctor
```

## Presets

| Preset | Shell | Fonts | CLI | Runtimes | Apps | macOS |
|--------|-------|-------|-----|----------|------|-------|
| Minimal | Ghostty, OMZ+Zinit, Starship, Theme (4/5) | Hack, Noto Sans | Essential (5) | mise, Node, pnpm | — | hushlogin |
| Standard | All 5 | Hack, Noto Sans, Pretendard | Essential + Recommended (13) | mise, Node, pnpm, uv | Raycast, OrbStack | All 7 |
| Full | All 5 | All 5 | All 22 | All 7 | All 8 | All 7 |
| Custom | Pick | Pick | Pick | Pick | Pick | Pick |

## Requirements

- macOS (Apple Silicon or Intel)
- Homebrew (auto-installed if missing)
- [gum](https://github.com/charmbracelet/gum) (auto-installed if missing)

## License

MIT
