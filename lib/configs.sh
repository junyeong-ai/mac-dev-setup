#!/usr/bin/env bash
# Config deployment with user-managed block preservation.
#
# The .zshrc template contains a marker pair:
#   # >>> user-managed >>>
#   ...content preserved across re-runs...
#   # <<< user-managed <<<
#
# On deploy, any content between those markers in an existing ~/.zshrc is
# extracted and re-injected into the fresh template.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

USER_BLOCK_BEGIN="# >>> user-managed >>>"
USER_BLOCK_END="# <<< user-managed <<<"

# ── Public entry ──

# deploy_configs <selected_keys>
# selected_keys is a newline-separated list; gating for optional configs
# (Ghostty, Starship, bat, lazygit) inspects this list.
deploy_configs() {
  local keys=$1

  _deploy_zprofile
  touch "$HOME/.hushlogin"
  _deploy_zshrc

  _has_key "$keys" ghostty  && _deploy_simple configs/ghostty.config   "$HOME/.config/ghostty/config"         "Ghostty config"
  _has_key "$keys" starship && _deploy_simple configs/starship.toml    "$HOME/.config/starship.toml"          "Starship config"
  command -v bat &>/dev/null      && _deploy_simple configs/bat.config      "$HOME/.config/bat/config"             "bat config"
  command -v lazygit &>/dev/null  && _deploy_simple configs/lazygit.yml     "$HOME/.config/lazygit/config.yml"     "lazygit config"

  _configure_git
  _configure_neovim
}

# ── Internals ──

_has_key() {
  local keys=$1 key=$2
  echo "$keys" | grep -qxF "$key"
}

_deploy_simple() {
  local src=$1 dst=$2 label=$3
  mkdir -p "$(dirname "$dst")"
  cp "$SCRIPT_DIR/$src" "$dst"
  track_success "$label"
}

_deploy_zprofile() {
  if [ ! -f "$HOME/.zprofile" ] || ! grep -q "brew shellenv" "$HOME/.zprofile" 2>/dev/null; then
    cat > "$HOME/.zprofile" << 'EOF'
# Homebrew
eval "$(/opt/homebrew/bin/brew shellenv)"
EOF
  fi
  track_success ".zprofile"
}

# Deploy the zshrc template while preserving any user-managed block.
_deploy_zshrc() {
  local src="$SCRIPT_DIR/configs/zshrc"
  local dst="$HOME/.zshrc"
  local preserved=""

  if [ -f "$dst" ] && grep -qF "$USER_BLOCK_BEGIN" "$dst"; then
    preserved=$(_extract_user_block "$dst")
  fi

  cp "$src" "$dst"

  if [ -n "$preserved" ]; then
    _inject_user_block "$dst" "$preserved"
    track_success ".zshrc (user-managed block preserved)"
  else
    track_success ".zshrc"
  fi
}

# Extract lines strictly between the markers (exclusive).
_extract_user_block() {
  local file=$1
  awk -v b="$USER_BLOCK_BEGIN" -v e="$USER_BLOCK_END" '
    $0 == b { inb = 1; next }
    $0 == e { inb = 0; next }
    inb      { print }
  ' "$file"
}

# Replace the body between markers in $file with the provided content.
_inject_user_block() {
  local file=$1 body=$2
  local tmp
  tmp=$(mktemp)
  awk -v b="$USER_BLOCK_BEGIN" -v e="$USER_BLOCK_END" -v body="$body" '
    $0 == b { print; print body; inb = 1; next }
    $0 == e { inb = 0; print; next }
    !inb    { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

_configure_git() {
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
}

_configure_neovim() {
  if ! command -v nvim &>/dev/null; then
    return 0
  fi
  if [ -f "$HOME/.config/nvim/lazy-lock.json" ]; then
    track_success "Neovim config"
    return 0
  fi
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
}
