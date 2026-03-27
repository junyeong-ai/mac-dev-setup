#!/usr/bin/env bash
# ── Homebrew 설치 & 패키지 관리 ──

LOG_FILE="${LOG_FILE:-$HOME/.mac-dev-setup.log}"

ensure_homebrew() {
  if command -v brew &>/dev/null; then
    track_success "Homebrew $(brew --version 2>/dev/null | head -1 | cut -d' ' -f2)"
    return 0
  fi

  track_active "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" >> "$LOG_FILE" 2>&1

  if [ -f /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    printf "\033[1A\033[2K"
    track_success "Homebrew installed"
  else
    printf "\033[1A\033[2K"
    track_error "Homebrew installation failed — check $LOG_FILE"
    return 1
  fi
}

_handle_error() {
  local label=$1 retry_func=$2
  shift 2
  if [ ! -t 0 ]; then
    track_warn "Skipped $label (non-interactive)"
    return 0
  fi
  local action
  action=$(ui_error_action "$label")
  case "$action" in
    "Retry") "$retry_func" "$@" ;;
    "Skip")  track_warn "Skipped $label" ;;
    "Abort") track_error "Aborted"; exit 1 ;;
  esac
}

brew_install() {
  local pkg=$1
  local label=${2:-$1}
  local short="${label%% (*}"

  if brew list "$pkg" &>/dev/null 2>&1; then
    track_success "$short"
    return 0
  fi

  track_active "$short..."
  if brew install "$pkg" >> "$LOG_FILE" 2>&1; then
    printf "\033[1A\033[2K"
    track_success "$short"
  else
    printf "\033[1A\033[2K"
    track_error "$short"
    _handle_error "$label" brew_install "$pkg" "$label"
  fi
}

brew_install_cask() {
  local pkg=$1
  local label=${2:-$1}
  local app_name=${3:-}
  local short="${label%% (*}"

  if brew list --cask "$pkg" &>/dev/null 2>&1; then
    track_success "$short"
    return 0
  fi

  if [ -n "$app_name" ] && [ -d "/Applications/${app_name}.app" ]; then
    track_success "$short"
    return 0
  fi

  track_active "$short..."
  if brew install --cask "$pkg" >> "$LOG_FILE" 2>&1; then
    printf "\033[1A\033[2K"
    track_success "$short"
  else
    printf "\033[1A\033[2K"
    track_error "$short"
    _handle_error "$label" brew_install_cask "$pkg" "$label" "$app_name"
  fi
}
