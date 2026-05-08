#!/usr/bin/env bash
# Backup existing dotfiles before modification

BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d_%H%M%S)"

backup_configs() {
  local files=(
    "$HOME/.zshrc"
    "$HOME/.zprofile"
    "$HOME/.gitconfig"
    "$HOME/.hushlogin"
    "$HOME/.config/ghostty/config"
    "$HOME/.config/starship.toml"
    "$HOME/.config/bat/config"
    "$HOME/.config/lazygit/config.yml"
    "$HOME/.config/nvim/init.lua"
    "$HOME/.config/nvim/lua/plugins/catppuccin.lua"
  )

  local count=0
  for f in "${files[@]}"; do
    if [ -f "$f" ]; then
      local rel dir
      rel="${f#"$HOME"/}"
      dir="$BACKUP_DIR/$(dirname "$rel")"
      mkdir -p "$dir" || { track_error "Backup failed: $f"; return 1; }
      cp "$f" "$BACKUP_DIR/$rel" || { track_error "Backup failed: $f"; return 1; }
      count=$((count + 1))
    fi
  done

  if [ $count -gt 0 ]; then
    track_success "Backed up $count files → $BACKUP_DIR"
  else
    track_info "No existing configs to back up"
  fi
}
