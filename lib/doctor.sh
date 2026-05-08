#!/usr/bin/env bash
# Doctor — registry-driven environment diagnostics.
#
# Walks every key in the registry, evaluates its CHECK expression, and prints
# installed/missing/optional status grouped by type.

run_doctor() {
  export _ZO_DOCTOR=0
  echo ""
  _doctor_title "Mac Dev Setup — Doctor"
  echo ""

  _doctor_system
  _doctor_registry
  _doctor_configs
  _doctor_theme_consistency
  _doctor_git
}

# ── System ──

_doctor_system() {
  _doctor_section "System"
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
    _doctor_section "$(type_log_title "$t")"
    local installed=0 missing=0 optional=0
    local -a rows=()
    local k label tier
    while IFS= read -r k; do
      [ -z "$k" ] && continue
      label=$(reg_field "$k" label)
      tier=$(reg_field "$k" tier)
      if reg_check_passes "$k"; then
        rows+=("✓|$label")
        installed=$((installed + 1))
      elif [ "$tier" = "extra" ]; then
        rows+=("-|$label")
        optional=$((optional + 1))
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
      elif [ "$mark" = "-" ]; then
        printf "  \033[33m-\033[0m  %s (optional)\n" "$lbl"
      else
        printf "  \033[31m✗\033[0m  %s\n" "$lbl"
      fi
    done
    printf "     Installed: %d / Missing: %d / Optional: %d\n" "$installed" "$missing" "$optional"
    echo ""
  done
}

# ── Config files ──

_doctor_configs() {
  _doctor_section "Configuration Files"
  local label path check pattern
  while IFS='|' read -r label path check pattern; do
    [ -z "$label" ] && continue
    if [ -n "$check" ] && ! eval "$check" &>/dev/null; then
      printf "  \033[33m-\033[0m  %-35s %s\n" "$label" "not applicable"
      continue
    fi
    if [ ! -f "$path" ]; then
      printf "  \033[31m✗\033[0m  %-35s %s\n" "$label" "missing"
    elif [ -n "$pattern" ] && ! grep -qF "$pattern" "$path" 2>/dev/null; then
      printf "  \033[31m✗\033[0m  %-35s %s\n" "$label" "outdated"
    else
      local sz
      sz=$(wc -c < "$path" | tr -d ' ')
      printf "  \033[32m✓\033[0m  %-35s %s bytes\n" "$label" "$sz"
    fi
  done < <(managed_config_checks)
  echo ""
}

# ── Theme consistency ──

_doctor_theme_consistency() {
  _doctor_section "Theme Consistency (Catppuccin Mocha)"
  local ok=0 total=0
  local name file pattern check
  while IFS='|' read -r name file pattern check; do
    [ -z "$name" ] && continue
    if [ -n "$check" ] && ! eval "$check" &>/dev/null; then
      printf "  \033[33m-\033[0m  %s (not applicable)\n" "$name"
      continue
    fi
    total=$((total + 1))
    if [ -f "$file" ] && grep -q "$pattern" "$file" 2>/dev/null; then
      printf "  \033[32m✓\033[0m  %s\n" "$name"
      ok=$((ok + 1))
    else
      printf "  \033[31m✗\033[0m  %s (theme not applied)\n" "$name"
    fi
  done < <(managed_theme_checks)
  echo ""
  printf "     Theme: %d/%d consistent\n" "$ok" "$total"
  echo ""
}

# ── Git ──

_doctor_git() {
  _doctor_section "Git"
  local gn ge
  if ! command -v git &>/dev/null; then
    printf "  \033[33m-\033[0m  git: not available\n"
    printf "  \033[33m-\033[0m  GitHub CLI: not applicable\n"
    echo ""
    return 0
  fi

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
  if ! command -v gh &>/dev/null; then
    printf "  \033[33m-\033[0m  GitHub CLI: not installed\n"
  elif gh auth status &>/dev/null; then
    printf "  \033[32m✓\033[0m  GitHub CLI: authenticated\n"
  else
    printf "  \033[33m-\033[0m  GitHub CLI: not authenticated\n"
  fi
  echo ""
}

_doctor_title() {
  local title=$1
  if command -v gum &>/dev/null; then
    gum style --border double --border-foreground "#cba6f7" --padding "1 4" \
      --foreground "#cdd6f4" --bold "$title"
  else
    printf "== %s ==\n" "$title"
  fi
}

_doctor_section() {
  local title=$1
  if command -v gum &>/dev/null; then
    gum style --foreground "#fab387" --bold "  $title"
  else
    printf "  %s\n" "$title"
  fi
}
