#!/usr/bin/env bash
# ── macOS 시스템 설정 ──

MACOS_OPTIONS=(
  "키 반복 속도 최적화 (KeyRepeat)"
  "Finder 숨김 파일 표시"
  "Finder 경로 표시줄"
  "Dock 자동 숨김 + 빠른 애니메이션"
  "미션 컨트롤 애니메이션 가속"
  "스크린샷 ~/Screenshots 저장"
  "Last login 메시지 제거"
)

macos_labels() {
  for entry in "${MACOS_OPTIONS[@]}"; do echo "$entry"; done
}

setup_macos() {
  local needs_killall=false
  for item in "$@"; do
    case "$item" in
      *"KeyRepeat"*)
        defaults write NSGlobalDomain KeyRepeat -int 2
        defaults write NSGlobalDomain InitialKeyRepeat -int 15
        track_success "키 반복 속도 최적화"
        ;;
      *"숨김 파일"*)
        defaults write com.apple.finder AppleShowAllFiles YES
        needs_killall=true
        track_success "Finder 숨김 파일 표시"
        ;;
      *"경로 표시줄"*)
        defaults write com.apple.finder ShowPathbar -bool true
        needs_killall=true
        track_success "Finder 경로 표시줄"
        ;;
      *"Dock"*)
        defaults write com.apple.dock autohide -bool true
        defaults write com.apple.dock autohide-delay -float 0
        defaults write com.apple.dock autohide-time-modifier -float 0.3
        needs_killall=true
        track_success "Dock 자동 숨김"
        ;;
      *"미션 컨트롤"*)
        defaults write com.apple.dock expose-animation-duration -float 0.1
        needs_killall=true
        track_success "미션 컨트롤 가속"
        ;;
      *"스크린샷"*)
        mkdir -p "$HOME/Screenshots"
        defaults write com.apple.screencapture location "$HOME/Screenshots"
        track_success "스크린샷 ~/Screenshots"
        ;;
      *"Last login"*)
        touch "$HOME/.hushlogin"
        track_success "Last login 메시지 제거"
        ;;
    esac
  done
  $needs_killall && killall Finder Dock 2>/dev/null && track_info "Finder & Dock restarted"
}
