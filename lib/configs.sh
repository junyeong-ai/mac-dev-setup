#!/usr/bin/env bash
# ── 설정 파일 생성 ──

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

setup_configs() {
  local shell_selections="$*"

  # .zprofile
  if [ ! -f "$HOME/.zprofile" ] || ! grep -q "brew shellenv" "$HOME/.zprofile" 2>/dev/null; then
    cat > "$HOME/.zprofile" << 'EOF'
# Homebrew
eval "$(/opt/homebrew/bin/brew shellenv)"
EOF
    track_success ".zprofile"
  else
    track_success ".zprofile"
  fi

  # .hushlogin
  touch "$HOME/.hushlogin"

  # .zshrc
  cp "$SCRIPT_DIR/configs/zshrc" "$HOME/.zshrc"
  track_success ".zshrc"

  # Ghostty
  if echo "$shell_selections" | grep -q "Ghostty"; then
    mkdir -p "$HOME/.config/ghostty"
    cp "$SCRIPT_DIR/configs/ghostty.config" "$HOME/.config/ghostty/config"
    track_success "Ghostty config"
  fi

  # Starship
  if echo "$shell_selections" | grep -q "Starship"; then
    mkdir -p "$HOME/.config"
    cp "$SCRIPT_DIR/configs/starship.toml" "$HOME/.config/starship.toml"
    track_success "Starship config"
  fi

  # bat
  if command -v bat &>/dev/null; then
    mkdir -p "$HOME/.config/bat"
    cp "$SCRIPT_DIR/configs/bat.config" "$HOME/.config/bat/config"
    track_success "bat config"
  fi

  # lazygit
  if command -v lazygit &>/dev/null; then
    mkdir -p "$HOME/.config/lazygit"
    cp "$SCRIPT_DIR/configs/lazygit.yml" "$HOME/.config/lazygit/config.yml"
    track_success "lazygit config"
  fi

  # Git (delta)
  if ! git config --global core.pager &>/dev/null && command -v delta &>/dev/null; then
    git config --global init.defaultBranch main
    git config --global pull.rebase true
    git config --global fetch.prune true
    git config --global rerere.enabled true
    git config --global core.pager delta
    git config --global interactive.diffFilter "delta --color-only"
    git config --global delta.navigate true
    git config --global delta.side-by-side true
    git config --global delta.syntax-theme "Catppuccin Mocha"
    track_success "Git + delta"
  else
    track_success "Git config"
  fi

  # Neovim (LazyVim)
  if command -v nvim &>/dev/null && [ ! -f "$HOME/.config/nvim/lazy-lock.json" ]; then
    if [ ! -d "$HOME/.config/nvim" ]; then
      git clone https://github.com/LazyVim/starter "$HOME/.config/nvim" >> "$LOG_FILE" 2>&1
      rm -rf "$HOME/.config/nvim/.git"
    fi
    mkdir -p "$HOME/.config/nvim/lua/plugins"
    cat > "$HOME/.config/nvim/lua/plugins/catppuccin.lua" << 'LUA'
return {
  { "catppuccin/nvim", name = "catppuccin", priority = 1000 },
  { "LazyVim/LazyVim", opts = { colorscheme = "catppuccin-mocha" } },
}
LUA
    track_success "Neovim + LazyVim"
  else
    track_success "Neovim config"
  fi
}
