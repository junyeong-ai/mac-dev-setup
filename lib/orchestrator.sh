#!/usr/bin/env bash
# Orchestrator — install flow (selection UI + execution).
#
# Public entry points (mirror run_doctor in doctor.sh):
#   run_bootstrap    — ensure system + brew + gum; must run before any gum-based UI
#   run_install      — full install flow (interactive or --ci)
#
# Private helpers:
#   _collect_selection    walk types and collect user-selected keys
#   _execute_selection    run install_key in dependency-first order
#   _show_summary         render the gum table preview
#   _show_footer          final banner with install count

# ── Bootstrap ──

# Ensure bootstrap prerequisites before any gum-based UI is used. Pass
# "install" to refresh Homebrew metadata before installing selected tools.
run_bootstrap() {
  ensure_supported_system
  ensure_homebrew
  if [ "${1:-}" = "install" ]; then
    ensure_homebrew_metadata
  fi
  ensure_gum
}

# ── Install flow ──

run_install() {
  if [ -t 1 ] && [ -n "${TERM:-}" ]; then
    clear
  fi
  show_logo
  _check_system
  track_bar

  local selected_keys
  if [ "${CI_MODE:-}" = "true" ]; then
    track_info "Running in CI mode (essential + recommended)"
    track_bar
    selected_keys=$(reg_default_keys)
  else
    selected_keys=$(_collect_selection)
  fi

  if [ -z "$selected_keys" ]; then
    track_cancel "Nothing selected."
    exit 0
  fi

  selected_keys=$(_expand_selection_dependencies "$selected_keys")

  local count
  count=$(wc -l <<< "$selected_keys" | tr -d ' ')

  _show_summary "$selected_keys"
  track_bar

  if [ "${CI_MODE:-}" != "true" ]; then
    if ! ui_confirm "  Proceed with installation? ($count items)"; then
      track_cancel "Cancelled."
      exit 0
    fi
  fi

  _execute_selection "$selected_keys"
  _show_footer "$selected_keys" "$count"
}

# ── Selection UI ──

# Walk each type in registry order, present items of that type with
# essential+recommended preselected. Returns newline-separated keys.
_collect_selection() {
  local -a all_selected=()
  local -a types
  while IFS= read -r t; do [ -n "$t" ] && types+=("$t"); done < <(reg_types)
  local total=${#types[@]}

  local i=0 t
  for t in "${types[@]}"; do
    i=$((i + 1))
    local title
    title=$(type_ui_title "$t")
    ui_step "$i" "$total" "$title" 1>&2

    local -a keys=() labels=() defaults=()
    local k lbl tier
    while IFS= read -r k; do [ -n "$k" ] && keys+=("$k"); done < <(reg_keys_by_type "$t")

    [ ${#keys[@]} -eq 0 ] && { track_bar 1>&2; continue; }

    for k in "${keys[@]}"; do
      lbl=$(reg_field "$k" label)
      tier=$(reg_field "$k" tier)
      labels+=("$lbl")
      if [ "$tier" = "essential" ] || [ "$tier" = "recommended" ]; then
        defaults+=("$lbl")
      fi
    done

    local default_csv
    default_csv=$(_join_csv "${defaults[@]}")

    local prompt
    prompt=$(_selection_prompt "$t")

    local selected
    selected=$(_multi_select "$prompt" "$default_csv" "${labels[@]}")

    local selected_count
    selected_count=$(printf "%s\n" "$selected" | sed '/^$/d' | wc -l | tr -d ' ')
    if [ "$selected_count" -gt 0 ]; then
      track_info "Selected: $selected_count" 1>&2
    else
      track_warn "Selected: 0" 1>&2
    fi

    # Map selected labels back to keys
    while IFS= read -r sl; do
      [ -z "$sl" ] && continue
      for k in "${keys[@]}"; do
        lbl=$(reg_field "$k" label)
        if [ "$lbl" = "$sl" ]; then
          all_selected+=("$k")
          break
        fi
      done
    done <<< "$selected"

    track_bar 1>&2
  done

  printf "%s\n" "${all_selected[@]}"
}

_selection_prompt() {
  case "$1" in
    shell)   echo "터미널 & 쉘 구성:" ;;
    font)    echo "코딩 폰트 & 한글 폰트:" ;;
    cli)     echo "CLI 도구 (essential/recommended는 미리 체크됨):" ;;
    git)     echo "Git & 협업 도구:" ;;
    runtime) echo "런타임 & 패키지 매니저:" ;;
    ai)      echo "AI 도구:" ;;
    app)     echo "앱 선택:" ;;
    macos)   echo "macOS 설정:" ;;
    *)       echo "UNMAPPED TYPE '$1' — update _selection_prompt in orchestrator.sh" >&2
             echo "선택:" ;;
  esac
}

# Expand selected keys into dependency-first execution order. Dependencies
# are declared in the registry so installers don't need hidden ordering rules.
_expand_selection_dependencies() {
  local selected_keys_text=$1
  local k
  _dep_seen=""
  _dep_visiting=""
  _dep_order=""

  while IFS= read -r k; do
    [ -n "$k" ] && _append_key_with_dependencies "$k"
  done <<< "$selected_keys_text"

  printf "%s" "$_dep_order"
  unset _dep_seen _dep_visiting _dep_order
}

_append_key_with_dependencies() {
  local key=$1
  case "$_dep_seen" in
    *"|$key|"*) return 0 ;;
  esac
  case "$_dep_visiting" in
    *"|$key|"*)
      track_error "Dependency cycle at registry key: $key"
      exit 1
      ;;
  esac

  if ! reg_field "$key" key >/dev/null 2>&1; then
    track_error "Unknown dependency key: $key"
    exit 1
  fi

  _dep_visiting="${_dep_visiting}|$key|"

  local deps dep
  deps=$(reg_field "$key" deps)
  for dep in $deps; do
    _append_key_with_dependencies "$dep"
  done

  _dep_visiting="${_dep_visiting//|$key|/|}"
  _dep_seen="${_dep_seen}|$key|"
  _dep_order="${_dep_order}${key}"$'\n'
}

# ── Summary ──

_show_summary() {
  local selected_keys_text=$1
  track_bar
  gum style --foreground "$C_BLUE" --bold "  ◇  Installation Summary"
  track_bar

  local -a types
  while IFS= read -r t; do [ -n "$t" ] && types+=("$t"); done < <(reg_types)

  local total=0
  local t count
  for t in "${types[@]}"; do
    count=$(echo "$selected_keys_text" | while IFS= read -r k; do
      [ -n "$k" ] && [ "$(reg_field "$k" type)" = "$t" ] && echo "$k"
    done | wc -l | tr -d ' ')
    total=$((total + count))
    [ "$count" -gt 0 ] && track_info "$(type_log_title "$t"): $count"
  done
  track_bar
  track_info "Total: $total"
}

# ── Execution ──

# Install all selected keys in dependency-first order with a section header
# whenever the current key type changes. Assumes bootstrap has already run.
_execute_selection() {
  local selected_keys_text=$1
  track_bar
  gum style --foreground "$C_MAUVE" --bold "  ◆  Installing..."
  track_bar

  track_section "Backup"
  backup_configs
  track_bar

  local current_type="" ran_macos=false
  local k t
  while IFS= read -r k; do
    [ -z "$k" ] && continue
    t=$(reg_field "$k" type)
    if [ "$t" != "$current_type" ]; then
      [ -n "$current_type" ] && track_bar
      track_section "$(type_log_title "$t")"
      current_type=$t
    fi
    install_key "$k"
    [ "$t" = "macos" ] && ran_macos=true
  done <<< "$selected_keys_text"

  # Finalize macOS changes once after all macOS installers have run.
  if [ "$ran_macos" = true ]; then
    _macos_finalize
    track_bar
  elif [ -n "$current_type" ]; then
    track_bar
  fi

  track_section "Configuration Files"
  deploy_configs "$selected_keys_text"
  track_bar
}

# ── Footer ──

_show_footer() {
  local selected_keys_text=$1 count=$2
  track_done "Setup Complete! ($count items)"

  track_info "Log: $LOG_FILE"
  track_info "Backup: $BACKUP_DIR"
  echo ""

  local -a next_steps=(
    "  Next steps:"
    ""
    "  1. Restart your terminal"
  )
  local step=2
  if echo "$selected_keys_text" | grep -qxF neovim; then
    next_steps+=("  $step. Run 'nvim' once to install plugins")
    step=$((step + 1))
  fi
  next_steps+=("  $step. Run './setup.sh doctor' to verify")

  gum style \
    --border rounded \
    --border-foreground "$C_YELLOW" \
    --padding "1 3" \
    --margin "0 4" \
    --foreground "$C_YELLOW" \
    "${next_steps[@]}"
  echo ""
}

# ── Private helpers ──

_check_system() {
  local arch macos_ver
  arch=$(uname -m)
  macos_ver=$(sw_vers -productVersion)
  if [ "$arch" != "arm64" ]; then
    track_error "Apple Silicon Mac required: $arch"
    exit 1
  fi
  track_info "macOS $macos_ver  ·  $arch  ·  $(sysctl -n machdep.cpu.brand_string 2>/dev/null | sed 's/  */ /g')"
}

_join_csv() {
  local IFS=","
  echo "$*"
}

_multi_select() {
  local header=$1 selected_csv=$2
  shift 2
  local -a args=(
    --no-limit
    --header "  │  $header"
    --header.foreground "$C_SUBTEXT"
    --cursor.foreground "$C_MAUVE"
    --selected.foreground "$C_GREEN"
    --selected-prefix "  │  ✓ "
    --unselected-prefix "  │    "
    --cursor "  │  ✓ "
    --height 18
  )
  [ -n "$selected_csv" ] && args+=(--selected "$selected_csv")
  gum choose "${args[@]}" "$@"
}
