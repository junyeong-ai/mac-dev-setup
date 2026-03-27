#!/usr/bin/env bash
# ── 폰트 설치 ──

FONT_MAP=(
  "Hack Nerd Font Mono|font-hack-nerd-font"
  "JetBrains Mono Nerd Font|font-jetbrains-mono-nerd-font"
  "Sarasa Gothic (한영 통합)|font-sarasa-gothic"
  "Noto Sans CJK KR (한글)|font-noto-sans-cjk-kr"
  "Pretendard (한글 UI)|font-pretendard"
)

font_labels() {
  for entry in "${FONT_MAP[@]}"; do
    echo "${entry%%|*}"
  done
}

font_cask_for() {
  local label=$1
  for entry in "${FONT_MAP[@]}"; do
    if [ "${entry%%|*}" = "$label" ]; then
      echo "${entry##*|}"
      return
    fi
  done
}

setup_fonts() {
  local selections=("$@")
  for label in "${selections[@]}"; do
    local cask
    cask=$(font_cask_for "$label")
    if [ -n "$cask" ]; then
      brew_install_cask "$cask" "$label"
    fi
  done
}
