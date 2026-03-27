#!/usr/bin/env bash
# ── 기존 설정 백업 ──

BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d_%H%M%S)"

backup_configs() {
  local files=(
    "$HOME/.zshrc"
    "$HOME/.zprofile"
    "$HOME/.gitconfig"
    "$HOME/.config/ghostty/config"
    "$HOME/.config/starship.toml"
    "$HOME/.config/bat/config"
    "$HOME/.config/lazygit/config.yml"
  )

  local count=0
  for f in "${files[@]}"; do
    if [ -f "$f" ]; then
      local rel="${f#$HOME/}"
      local dir="$BACKUP_DIR/$(dirname "$rel")"
      mkdir -p "$dir"
      cp "$f" "$BACKUP_DIR/$rel"
      count=$((count + 1))
    fi
  done

  if [ $count -gt 0 ]; then
    track_success "Backed up $count files → $BACKUP_DIR"
  else
    track_info "No existing configs to back up"
  fi
}
