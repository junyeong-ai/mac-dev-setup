#!/usr/bin/env bash
# ── 앱 & 생산성 도구 설치 ──

APP_OPTIONS=(
  "Raycast (Spotlight 대체)|raycast|Raycast"
  "OrbStack (Docker)|orbstack|OrbStack"
  "AltTab (윈도우 스위처)|alt-tab|AltTab"
  "Stats (시스템 모니터)|stats|Stats"
  "Shottr (스크린샷 + OCR)|shottr|Shottr"
  "Karabiner-Elements (키 리매핑)|karabiner-elements|Karabiner-Elements"
  "Visual Studio Code|visual-studio-code|Visual Studio Code"
  "Cursor (AI 에디터)|cursor|Cursor"
)

app_labels() {
  for entry in "${APP_OPTIONS[@]}"; do
    echo "${entry%%|*}"
  done
}

app_cask_for() {
  local label=$1
  for entry in "${APP_OPTIONS[@]}"; do
    if [ "${entry%%|*}" = "$label" ]; then
      local rest="${entry#*|}"
      echo "${rest%%|*}"
      return
    fi
  done
}

app_name_for() {
  local label=$1
  for entry in "${APP_OPTIONS[@]}"; do
    if [ "${entry%%|*}" = "$label" ]; then
      echo "${entry##*|}"
      return
    fi
  done
}

setup_apps() {
  for label in "$@"; do
    local cask app_name
    cask=$(app_cask_for "$label")
    app_name=$(app_name_for "$label")
    if [ -n "$cask" ]; then
      brew_install_cask "$cask" "$label" "$app_name"
    fi
  done
}
