#!/usr/bin/env bash
# Doctor — registry-driven environment diagnostics.
#
# Walks every key in the registry, evaluates its CHECK expression, and prints
# a pass/fail badge. Grouped by type. No hardcoded tool list.

run_doctor() {
  export _ZO_DOCTOR=0
  echo ""
  gum style --border double --border-foreground "#cba6f7" --padding "1 4" \
    --foreground "#cdd6f4" --bold "Mac Dev Setup — Doctor"
  echo ""

  _doctor_system
  _doctor_registry
  _doctor_configs
  _doctor_theme_consistency
  _doctor_git
}

# ── System ──

_doctor_system() {
  gum style --foreground "#fab387" --bold "  System"
  printf "  %-38s %s\n" "macOS"     "$(sw_vers -productVersion) ($(uname -m))"
  printf "  %-38s %s\n" "Shell"     "$(zsh --version 2>/dev/null || echo 'N/A')"
  printf "  %-38s %s\n" "Homebrew"  "$(brew --version 2>/dev/null | head -1 || echo 'not installed')"
  echo ""
}

# ── Registry walk (grouped by type) ──

_doctor_registry() {
  local -a types
  while IFS= read -r t; do [ -n "$t" ] && types+=("$t"); done < <(reg_types)

  local t
  for t in "${types[@]}"; do
    gum style --foreground "#fab387" --bold "  $(type_log_title "$t")"
    local installed=0 missing=0
    local -a rows=()
    local k label check
    while IFS= read -r k; do
      [ -z "$k" ] && continue
      label=$(reg_field "$k" label)
      check=$(reg_field "$k" check)
      if _doctor_eval "$check" "$k" "$(reg_field "$k" type)"; then
        rows+=("✓|$label")
        installed=$((installed + 1))
      else
        rows+=("✗|$label")
        missing=$((missing + 1))
      fi
    done < <(reg_keys_by_type "$t")

    local r
    for r in "${rows[@]}"; do
      local mark="${r%%|*}"
      local lbl="${r#*|}"
      if [ "$mark" = "✓" ]; then
        printf "  \033[32m✓\033[0m  %s\n" "$lbl"
      else
        printf "  \033[31m✗\033[0m  %s\n" "$lbl"
      fi
    done
    printf "     Installed: %d / Missing: %d\n" "$installed" "$missing"
    echo ""
  done
}

# Evaluate a check expression. If empty, fall back to the command-name
# default for tool-like types.
_doctor_eval() {
  local check=$1 key=$2 type=$3
  if [ -n "$check" ]; then
    eval "$check" &>/dev/null
    return $?
  fi
  case "$type" in
    cli|runtime|ai) command -v "$key" &>/dev/null ;;
    *)              return 1 ;;
  esac
}

# ── Config files ──

_doctor_configs() {
  gum style --foreground "#fab387" --bold "  Configuration Files"
  local pair label path
  local pairs=(
    ".zshrc|$HOME/.zshrc"
    ".zprofile|$HOME/.zprofile"
    "Ghostty|$HOME/.config/ghostty/config"
    "Starship|$HOME/.config/starship.toml"
    "bat|$HOME/.config/bat/config"
    "lazygit|$HOME/.config/lazygit/config.yml"
    ".gitconfig|$HOME/.gitconfig"
    "Neovim|$HOME/.config/nvim/init.lua"
    ".hushlogin|$HOME/.hushlogin"
  )
  for pair in "${pairs[@]}"; do
    label="${pair%%|*}"
    path="${pair#*|}"
    if [ -f "$path" ]; then
      local sz
      sz=$(wc -c < "$path" | tr -d ' ')
      printf "  \033[32m✓\033[0m  %-35s %s bytes\n" "$label" "$sz"
    else
      printf "  \033[31m✗\033[0m  %-35s %s\n" "$label" "missing"
    fi
  done
  echo ""
}

# ── Theme consistency ──

_doctor_theme_consistency() {
  gum style --foreground "#fab387" --bold "  Theme Consistency (Catppuccin Mocha)"
  local ok=0 total=0
  local entry name file pattern
  local entries=(
    "Ghostty|$HOME/.config/ghostty/config|Catppuccin Mocha"
    "Starship|$HOME/.config/starship.toml|catppuccin_mocha"
    "bat|$HOME/.config/bat/config|Catppuccin Mocha"
    "delta|$HOME/.gitconfig|Catppuccin Mocha"
    "lazygit|$HOME/.config/lazygit/config.yml|#313244"
    "Neovim|$HOME/.config/nvim/lua/plugins/catppuccin.lua|catppuccin-mocha"
  )
  for entry in "${entries[@]}"; do
    name="${entry%%|*}"
    local rest="${entry#*|}"
    file="${rest%%|*}"
    pattern="${rest#*|}"
    total=$((total + 1))
    if [ -f "$file" ] && grep -q "$pattern" "$file" 2>/dev/null; then
      printf "  \033[32m✓\033[0m  %s\n" "$name"
      ok=$((ok + 1))
    else
      printf "  \033[31m✗\033[0m  %s (theme not applied)\n" "$name"
    fi
  done
  echo ""
  printf "     Theme: %d/%d consistent\n" "$ok" "$total"
  echo ""
}

# ── Git ──

_doctor_git() {
  gum style --foreground "#fab387" --bold "  Git"
  local gn ge
  gn=$(git config --global user.name  2>/dev/null || echo "")
  ge=$(git config --global user.email 2>/dev/null || echo "")
  if [ -n "$gn" ]; then
    printf "  \033[32m✓\033[0m  user.name: %s\n" "$gn"
  else
    printf "  \033[31m✗\033[0m  user.name: not set\n"
  fi
  if [ -n "$ge" ]; then
    printf "  \033[32m✓\033[0m  user.email: %s\n" "$ge"
  else
    printf "  \033[31m✗\033[0m  user.email: not set\n"
  fi
  if gh auth status &>/dev/null; then
    printf "  \033[32m✓\033[0m  GitHub CLI: authenticated\n"
  else
    printf "  \033[33m-\033[0m  GitHub CLI: not authenticated\n"
  fi
  echo ""
}
