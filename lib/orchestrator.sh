#!/usr/bin/env bash
# Orchestrator — install flow (selection UI + execution).
#
# Public entry points (mirror run_doctor in doctor.sh):
#   run_bootstrap    — ensure brew + gum; must run before any gum-based UI
#   run_install      — full install flow (interactive or --ci)
#
# Private helpers:
#   _collect_selection    walk types and collect user-selected keys
#   _execute_selection    run install_key for each selected key, grouped by type
#   _show_summary         render the gum table preview
#   _show_footer          final banner with install count

# ── Bootstrap ──

# Ensure brew + gum exist before any gum-based UI is used. Idempotent.
run_bootstrap() {
  ensure_homebrew
  ensure_gum
}

# ── Install flow ──

run_install() {
  clear
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
  _show_footer "$count"
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
    runtime) echo "런타임 & 패키지 매니저:" ;;
    ai)      echo "AI 도구:" ;;
    app)     echo "앱 선택:" ;;
    macos)   echo "macOS 설정:" ;;
    *)       echo "UNMAPPED TYPE '$1' — update _selection_prompt in orchestrator.sh" >&2
             echo "선택:" ;;
  esac
}

# ── Summary ──

_show_summary() {
  local keys=$1
  track_bar
  gum style --foreground "$C_BLUE" --bold "  ◇  Installation Summary"
  track_bar

  local -a types
  while IFS= read -r t; do [ -n "$t" ] && types+=("$t"); done < <(reg_types)

  local rows="Category,Items"
  local total=0
  local t count
  for t in "${types[@]}"; do
    count=$(echo "$keys" | while IFS= read -r k; do
      [ -n "$k" ] && [ "$(reg_field "$k" type)" = "$t" ] && echo "$k"
    done | wc -l | tr -d ' ')
    rows="${rows}"$'\n'"$(type_log_title "$t"),$count"
    total=$((total + count))
  done
  rows="${rows}"$'\n'"────────────────,────"$'\n'"Total,$total"

  printf "%s\n" "$rows" \
    | gum table -s "," --print \
      --border.foreground "$C_SURFACE" \
      --cell.foreground "$C_TEXT" \
      --header.foreground "$C_BLUE" \
      2>/dev/null \
    || track_info "Total: $total items"
}

# ── Execution ──

# Install all selected keys in registry order, grouped by type with a
# section header per type. Assumes bootstrap has already run.
_execute_selection() {
  local keys=$1
  track_bar
  gum style --foreground "$C_MAUVE" --bold "  ◆  Installing..."
  track_bar

  track_section "Backup"
  backup_configs
  track_bar

  local -a types
  while IFS= read -r t; do [ -n "$t" ] && types+=("$t"); done < <(reg_types)

  local t
  for t in "${types[@]}"; do
    local -a ordered_keys=()
    local rk
    while IFS= read -r rk; do
      if [ "$(reg_field "$rk" type)" = "$t" ]; then
        if echo "$keys" | grep -qxF "$rk"; then
          ordered_keys+=("$rk")
        fi
      fi
    done < <(reg_keys)

    [ ${#ordered_keys[@]} -eq 0 ] && continue

    track_section "$(type_log_title "$t")"
    local k
    for k in "${ordered_keys[@]}"; do
      install_key "$k"
    done

    # Finalize macOS changes after all macOS installers have run
    if [ "$t" = "macos" ]; then
      _macos_finalize
    fi

    track_bar
  done

  track_section "Configuration Files"
  deploy_configs "$keys"
  track_bar
}

# ── Footer ──

_show_footer() {
  local count=$1
  track_done "Setup Complete! ($count items)"

  track_info "Log: $LOG_FILE"
  track_info "Backup: $BACKUP_DIR"
  echo ""

  gum style \
    --border rounded \
    --border-foreground "$C_YELLOW" \
    --padding "1 3" \
    --margin "0 4" \
    --foreground "$C_YELLOW" \
    "  Next steps:" \
    "" \
    "  1. Restart your terminal" \
    "  2. Run 'nvim' once to install plugins" \
    "  3. Run './setup.sh doctor' to verify"
  echo ""
}

# ── Private helpers ──

_check_system() {
  local arch macos_ver
  arch=$(uname -m)
  macos_ver=$(sw_vers -productVersion)
  if [ "$arch" != "arm64" ] && [ "$arch" != "x86_64" ]; then
    track_error "Unsupported architecture: $arch"
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
