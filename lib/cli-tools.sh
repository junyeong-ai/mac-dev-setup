#!/usr/bin/env bash
# ── 모던 CLI 도구 설치 (X-of-Y 진행률) ──

CLI_TOOLS=(
  "eza (ls 대체)|eza|essential"
  "bat (cat 대체)|bat|essential"
  "fd (find 대체)|fd|essential"
  "ripgrep (grep 대체)|ripgrep|essential"
  "fzf (퍼지 검색)|fzf|essential"
  "zoxide (스마트 cd)|zoxide|recommended"
  "lazygit (Git TUI)|lazygit|recommended"
  "delta (git diff 강화)|git-delta|recommended"
  "btop (시스템 모니터)|btop|recommended"
  "dust (du 대체)|dust|recommended"
  "duf (df 대체)|duf|recommended"
  "navi (치트시트)|navi|recommended"
  "fastfetch (시스템 정보)|fastfetch|recommended"
  "lazydocker (Docker TUI)|lazydocker|extra"
  "procs (ps 대체)|procs|extra"
  "sd (sed 대체)|sd|extra"
  "tokei (코드 통계)|tokei|extra"
  "hyperfine (벤치마크)|hyperfine|extra"
  "glow (마크다운 뷰어)|glow|extra"
  "jq (JSON 처리)|jq|extra"
  "yq (YAML 처리)|yq|extra"
  "tlrc (명령어 요약)|tlrc|extra"
)

cli_labels_by_tier() {
  local tier=$1
  for entry in "${CLI_TOOLS[@]}"; do
    local label="${entry%%|*}"
    local rest="${entry#*|}"
    local t="${rest#*|}"
    [ "$t" = "$tier" ] && echo "$label"
  done
}

cli_all_labels() {
  for entry in "${CLI_TOOLS[@]}"; do
    echo "${entry%%|*}"
  done
}

cli_pkg_for() {
  local label=$1
  for entry in "${CLI_TOOLS[@]}"; do
    local l="${entry%%|*}"
    if [ "$l" = "$label" ]; then
      local rest="${entry#*|}"
      echo "${rest%%|*}"
      return
    fi
  done
}

# X-of-Y 진행률 + 체크마크 전환
setup_cli_tools() {
  local total=$#
  local i=0
  for label in "$@"; do
    i=$((i + 1))
    local pkg
    pkg=$(cli_pkg_for "$label")
    [ -z "$pkg" ] && continue

    local short_label="${label%% (*}"

    if brew list "$pkg" &>/dev/null 2>&1; then
      track_success "$short_label"
    else
      track_active "$short_label ($i/$total)..."
      if brew install "$pkg" >> "$LOG_FILE" 2>&1; then
        # 커서를 한 줄 위로 올리고 덮어쓰기
        printf "\033[1A\033[2K"
        track_success "$short_label"
      else
        printf "\033[1A\033[2K"
        track_error "$short_label (failed — check $LOG_FILE)"
      fi
    fi
  done
}
