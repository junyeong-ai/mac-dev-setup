#!/usr/bin/env bash
export _ZO_DOCTOR=0
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$HOME/.mac-dev-setup.log"
: > "$LOG_FILE"

for lib in ui backup brew shell fonts cli-tools runtime apps macos configs doctor; do
  source "$SCRIPT_DIR/lib/${lib}.sh"
done

# ── gum 확인 ──
ensure_gum() {
  if command -v gum &>/dev/null; then return 0; fi
  echo "Installing gum..."
  brew install gum >> "$LOG_FILE" 2>&1 || { echo "Failed. Install Homebrew first."; exit 1; }
}

# ── 시스템 확인 ──
check_system() {
  local arch macos_ver
  arch=$(uname -m)
  macos_ver=$(sw_vers -productVersion)
  [[ "$arch" != "arm64" && "$arch" != "x86_64" ]] && { track_error "Unsupported: $arch"; exit 1; }
  track_info "macOS $macos_ver  ·  $arch  ·  $(sysctl -n machdep.cpu.brand_string 2>/dev/null | sed 's/  */ /g')"
}

# ── 멀티 선택 래퍼 ──
multi_select() {
  local header=$1 selected_csv=$2; shift 2
  local args=(
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

single_select() {
  local header=$1; shift
  gum choose \
    --header "  │  $header" \
    --header.foreground "$C_SUBTEXT" \
    --cursor.foreground "$C_MAUVE" \
    --selected.foreground "$C_GREEN" \
    --cursor " ● " \
    "$@"
}

join_csv() { local IFS=","; echo "$*"; }
count_lines() { [ -z "$1" ] && echo 0 || echo "$1" | wc -l | tr -d ' '; }

# ══════════════════════════════════════
main() {
  # ── 서브커맨드 ──
  case "${1:-}" in
    doctor|--doctor) ensure_gum; run_doctor; exit 0 ;;
    --ci)
      # 비대화형 모드: Standard 프리셋 자동 설치
      CI_MODE=true
      PRESET="Standard"
      ;;
  esac

  clear
  ensure_gum

  # ── 로고 ──
  show_logo
  check_system
  track_bar

  # ── CI 모드 체크 ──
  if [ "${CI_MODE:-}" = "true" ]; then
    track_info "Running in CI mode (Standard preset)"
    track_bar
  else
    # ── 모드 선택 ──
    local mode
    mode=$(single_select "What would you like to do?" \
      "Install  — 개발 환경 설정" \
      "Doctor   — 현재 환경 진단")

    if [[ "$mode" == *"Doctor"* ]]; then
      run_doctor
      exit 0
    fi

    track_bar

    # ── 프리셋 ──
    track_info "프리셋을 선택하면 권장 항목이 미리 체크됩니다"
    track_bar

    local preset_choice
    preset_choice=$(single_select "Select a preset:" \
      "Minimal   — 쉘 + 필수 CLI만" \
      "Standard  — 권장 구성 (추천)" \
      "Full      — 전체 설치" \
      "Custom    — 직접 선택")
    PRESET="${preset_choice%%  *}"
    track_bar
  fi

  # ══════════════════════════════════
  #  프리셋별 기본값 (CSV)
  # ══════════════════════════════════
  local shell_opts=(
    "Ghostty (터미널)"
    "Oh My Zsh + Zinit (쉘)"
    "Starship (프롬프트)"
    "SCM Breeze (Git 단축)"
    "Catppuccin Mocha (테마)"
  )
  local font_opts=(); while IFS= read -r l; do [ -n "$l" ] && font_opts+=("$l"); done < <(font_labels)
  local cli_opts=(); while IFS= read -r l; do [ -n "$l" ] && cli_opts+=("$l"); done < <(cli_all_labels)
  local runtime_opts=(); while IFS= read -r l; do [ -n "$l" ] && runtime_opts+=("$l"); done < <(runtime_labels)
  local app_opts=(); while IFS= read -r l; do [ -n "$l" ] && app_opts+=("$l"); done < <(app_labels)
  local macos_opts=(); while IFS= read -r l; do [ -n "$l" ] && macos_opts+=("$l"); done < <(macos_labels)

  local shell_csv="" font_csv="" cli_csv="" runtime_csv="" app_csv="" macos_csv=""

  case "$PRESET" in
    Minimal)
      shell_csv=$(join_csv "${shell_opts[0]}" "${shell_opts[1]}" "${shell_opts[2]}" "${shell_opts[4]}")
      font_csv=$(join_csv "${font_opts[0]}" "${font_opts[3]}")
      local ess=(); while IFS= read -r l; do [ -n "$l" ] && ess+=("$l"); done < <(cli_labels_by_tier essential)
      cli_csv=$(join_csv "${ess[@]}")
      runtime_csv="mise (버전 관리자),Node.js LTS,pnpm (Node 패키지)"
      macos_csv="Last login 메시지 제거"
      ;;
    Standard)
      shell_csv=$(join_csv "${shell_opts[@]}")
      font_csv=$(join_csv "${font_opts[0]}" "${font_opts[3]}" "${font_opts[4]}")
      local sr=(); while IFS= read -r l; do [ -n "$l" ] && sr+=("$l"); done < <(cli_labels_by_tier essential; cli_labels_by_tier recommended)
      cli_csv=$(join_csv "${sr[@]}")
      runtime_csv="mise (버전 관리자),Node.js LTS,pnpm (Node 패키지),uv (Python 패키지)"
      app_csv="Raycast (Spotlight 대체),OrbStack (Docker)"
      macos_csv=$(join_csv "${macos_opts[@]}")
      ;;
    Full)
      shell_csv=$(join_csv "${shell_opts[@]}")
      font_csv=$(join_csv "${font_opts[@]}")
      cli_csv=$(join_csv "${cli_opts[@]}")
      runtime_csv=$(join_csv "${runtime_opts[@]}")
      app_csv=$(join_csv "${app_opts[@]}")
      macos_csv=$(join_csv "${macos_opts[@]}")
      ;;
  esac

  # ══════════════════════════════════
  #  6단계 대화형 선택
  # ══════════════════════════════════
  local sel_shell sel_fonts sel_cli sel_runtime sel_apps sel_macos

  if [ "${CI_MODE:-}" = "true" ]; then
    # CI: CSV를 줄바꿈으로 변환
    sel_shell=$(echo "$shell_csv" | tr ',' '\n')
    sel_fonts=$(echo "$font_csv" | tr ',' '\n')
    sel_cli=$(echo "$cli_csv" | tr ',' '\n')
    sel_runtime=$(echo "$runtime_csv" | tr ',' '\n')
    sel_apps=$(echo "$app_csv" | tr ',' '\n')
    sel_macos=$(echo "$macos_csv" | tr ',' '\n')
  else
    ui_step 1 6 "터미널 & 쉘 환경"
    sel_shell=$(multi_select "터미널 & 쉘 구성:" "$shell_csv" "${shell_opts[@]}")
    track_bar

    ui_step 2 6 "코딩 폰트"
    sel_fonts=$(multi_select "코딩 폰트 & 한글 폰트:" "$font_csv" "${font_opts[@]}")
    track_bar

    ui_step 3 6 "모던 CLI 도구"
    sel_cli=$(multi_select "CLI 도구 (위: 필수 / 아래: 선택):" "$cli_csv" "${cli_opts[@]}")
    track_bar

    ui_step 4 6 "개발 런타임"
    sel_runtime=$(multi_select "런타임 & 패키지 매니저:" "$runtime_csv" "${runtime_opts[@]}")
    track_bar

    ui_step 5 6 "앱 & 생산성"
    sel_apps=$(multi_select "앱 선택:" "$app_csv" "${app_opts[@]}")
    track_bar

    ui_step 6 6 "macOS 시스템 설정"
    sel_macos=$(multi_select "macOS 설정:" "$macos_csv" "${macos_opts[@]}")
  fi

  # ── 카운트 ──
  local n1 n2 n3 n4 n5 n6 total
  n1=$(count_lines "$sel_shell")
  n2=$(count_lines "$sel_fonts")
  n3=$(count_lines "$sel_cli")
  n4=$(count_lines "$sel_runtime")
  n5=$(count_lines "$sel_apps")
  n6=$(count_lines "$sel_macos")
  total=$((n1 + n2 + n3 + n4 + n5 + n6))

  # ══════════════════════════════════
  #  설치 요약
  # ══════════════════════════════════
  track_bar
  gum style --foreground "$C_BLUE" --bold "  ◇  Installation Summary"
  track_bar

  # gum table 형식 요약
  printf "%s\n" \
    "Category,Items" \
    "Shell & Terminal,$n1" \
    "Fonts,$n2" \
    "CLI Tools,$n3" \
    "Runtimes,$n4" \
    "Apps,$n5" \
    "macOS Settings,$n6" \
    "────────────────,────" \
    "Total,$total" \
  | gum table -s "," --print \
    --border.foreground "$C_SURFACE" \
    --cell.foreground "$C_TEXT" \
    --header.foreground "$C_BLUE" \
    2>/dev/null || {
    # gum table 실패 시 폴백
    track_info "Shell: $n1 · Fonts: $n2 · CLI: $n3 · Runtime: $n4 · Apps: $n5 · macOS: $n6"
    track_info "Total: $total items"
  }

  [ "$total" -eq 0 ] && { track_cancel "Nothing selected."; exit 0; }

  track_bar

  if [ "${CI_MODE:-}" != "true" ]; then
    if ! ui_confirm "  Proceed with installation? ($total items)"; then
      track_cancel "Cancelled."
      exit 0
    fi
  fi

  # ══════════════════════════════════
  #  설치 실행
  # ══════════════════════════════════
  track_bar
  gum style --foreground "$C_MAUVE" --bold "  ◆  Installing..."
  track_bar

  # 백업
  track_section "Backup"
  backup_configs
  track_bar

  # Homebrew
  track_section "Homebrew"
  ensure_homebrew
  track_bar

  # Shell
  if [ -n "$sel_shell" ]; then
    track_section "Shell Environment"
    while IFS= read -r item; do
      [ -n "$item" ] && setup_shell "$item"
    done <<< "$sel_shell"
    track_bar
  fi

  # Fonts
  if [ -n "$sel_fonts" ]; then
    track_section "Fonts"
    while IFS= read -r item; do
      [ -n "$item" ] && setup_fonts "$item"
    done <<< "$sel_fonts"
    track_bar
  fi

  # CLI
  if [ -n "$sel_cli" ]; then
    track_section "CLI Tools"
    local cli_arr=()
    while IFS= read -r item; do
      [ -n "$item" ] && cli_arr+=("$item")
    done <<< "$sel_cli"
    setup_cli_tools "${cli_arr[@]}"
    track_bar
  fi

  # Runtimes
  if [ -n "$sel_runtime" ]; then
    track_section "Runtimes"
    while IFS= read -r item; do
      [ -n "$item" ] && setup_runtimes "$item"
    done <<< "$sel_runtime"
    track_bar
  fi

  # Apps
  if [ -n "$sel_apps" ]; then
    track_section "Apps"
    while IFS= read -r item; do
      [ -n "$item" ] && setup_apps "$item"
    done <<< "$sel_apps"
    track_bar
  fi

  # Configs
  track_section "Configuration Files"
  setup_configs "$sel_shell"
  track_bar

  # macOS
  if [ -n "$sel_macos" ]; then
    track_section "macOS Settings"
    while IFS= read -r item; do
      [ -n "$item" ] && setup_macos "$item"
    done <<< "$sel_macos"
    track_bar
  fi

  # ══════════════════════════════════
  #  완료
  # ══════════════════════════════════
  track_done "Setup Complete! ($total items installed)"

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

main "$@"
