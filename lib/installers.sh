#!/usr/bin/env bash
# Installers — registry dispatch, primitive installers, bootstrap.
#
# Architecture:
#   install_key <key>
#     ├─ looks up INSTALLER + ARGS in registry
#     ├─ calls install_<INSTALLER> "$key" <args...>
#     └─ on non-zero exit, iterative retry/skip/abort prompt
#                          (interactive only; auto-skip in CI/non-TTY)
#
# Naming convention:
#   ensure_*        bootstrap primitive (public; used before gum is available)
#   install_*       installer primitive (public; called by dispatch)
#   install_macos_* dedicated per-key installer for macOS settings
#   _*              file-private helper
#
# Contract for every install_* primitive:
#   1. Be idempotent — short-circuit with track_success on already-installed.
#   2. Emit track_success on success, track_error on failure.
#   3. Return 0 on success, non-zero on failure. No retry logic inside
#      primitives; dispatch handles recovery uniformly.

LOG_FILE="${LOG_FILE:-$HOME/.mac-dev-setup.log}"

# ── Bootstrap (runs before gum is available) ──

# Ensure Homebrew exists. Uses plain echo because gum/tracking UI may not
# be installed yet. Idempotent.
ensure_homebrew() {
  if command -v brew &>/dev/null; then
    return 0
  fi
  echo "Installing Homebrew (first-time setup)..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" >> "$LOG_FILE" 2>&1
  if [ -f /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    echo "Homebrew installed."
  else
    echo "Homebrew installation failed — check $LOG_FILE" >&2
    exit 1
  fi
}

# Ensure gum exists. Requires Homebrew. Uses plain echo until gum is ready.
ensure_gum() {
  if command -v gum &>/dev/null; then
    return 0
  fi
  echo "Installing gum (UI toolkit)..."
  if brew install gum >> "$LOG_FILE" 2>&1; then
    echo "gum installed."
  else
    echo "gum installation failed — check $LOG_FILE" >&2
    exit 1
  fi
}

# ── Dispatch ──

# Install a single key. Looks up installer + args, invokes the primitive,
# and on failure offers retry/skip/abort in an *iterative* loop so repeated
# retries don't grow the call stack.
install_key() {
  local key=$1
  local installer args
  installer=$(reg_field "$key" installer) || { track_error "Unknown key: $key"; return 1; }
  args=$(reg_field "$key" args)

  local -a argv=()
  if [ -n "$args" ]; then
    # shellcheck disable=SC2206
    argv=($args)
  fi

  local fn="install_${installer}"
  # Registry validation guarantees this function exists, but guard for
  # direct install_key callers that bypass validation.
  if ! declare -F "$fn" >/dev/null; then
    track_error "Dispatch miss: $fn (key: $key)"
    return 1
  fi

  local label short
  label=$(reg_field "$key" label)
  short="${label%% (*}"

  while true; do
    if "$fn" "$key" "${argv[@]}"; then
      return 0
    fi

    # Non-interactive: auto-skip on failure
    if [ ! -t 0 ] || [ "${CI_MODE:-}" = "true" ]; then
      track_warn "Skipped $short (non-interactive)"
      return 0
    fi

    local action
    action=$(ui_error_action "$short")
    case "$action" in
      Retry) continue ;;
      Skip)  track_warn "Skipped $short"; return 0 ;;
      Abort) track_error "Aborted"; exit 1 ;;
      *)     track_warn "Unknown action '$action' — skipping $short"; return 0 ;;
    esac
  done
}

# ── Primitives ──

# Brew formula: install_brew <key> <pkg>
install_brew() {
  local key=$1 pkg=$2
  local label short
  label=$(reg_field "$key" label)
  short="${label%% (*}"

  if brew list "$pkg" &>/dev/null 2>&1; then
    track_success "$short"
    return 0
  fi
  track_active "$short..."
  if brew install "$pkg" >> "$LOG_FILE" 2>&1; then
    printf "\033[1A\033[2K"
    track_success "$short"
    return 0
  fi
  printf "\033[1A\033[2K"
  track_error "$short"
  return 1
}

# Brew cask: install_brew_cask <key> <cask> [app_name tokens...]
# App name with spaces is reassembled from trailing tokens.
install_brew_cask() {
  local key=$1 cask=$2
  shift 2
  local app_name="$*"
  local label short
  label=$(reg_field "$key" label)
  short="${label%% (*}"

  if brew list --cask "$cask" &>/dev/null 2>&1; then
    track_success "$short"
    return 0
  fi
  if [ -n "$app_name" ] && [ -d "/Applications/${app_name}.app" ]; then
    track_success "$short"
    return 0
  fi

  track_active "$short..."
  if brew install --cask "$cask" >> "$LOG_FILE" 2>&1; then
    printf "\033[1A\033[2K"
    track_success "$short"
    return 0
  fi
  printf "\033[1A\033[2K"
  track_error "$short"
  return 1
}

# Mise-managed runtime: install_mise <key> <spec>
# Self-bootstraps mise if missing so selection order doesn't matter.
install_mise() {
  local key=$1 spec=$2
  local label short
  label=$(reg_field "$key" label)
  short="${label%% (*}"

  if ! command -v mise &>/dev/null; then
    track_active "mise (bootstrap)..."
    if brew install mise >> "$LOG_FILE" 2>&1; then
      printf "\033[1A\033[2K"
      track_success "mise (bootstrap)"
    else
      printf "\033[1A\033[2K"
      track_error "mise bootstrap failed — skipping $short"
      return 1
    fi
  fi

  track_active "$short (via mise)..."
  # Pass spec as positional arg to bash -c so it can't be re-interpreted as
  # a shell command even if the registry is ever extended with untrusted data.
  if bash -c 'eval "$(mise activate bash)" && mise use -g "$1"' _ "$spec" >> "$LOG_FILE" 2>&1; then
    printf "\033[1A\033[2K"
    track_success "$short (via mise)"
    return 0
  fi
  printf "\033[1A\033[2K"
  track_error "$short (via mise)"
  return 1
}

# Global npm package: install_npm <key> <pkg>
# Self-bootstraps Node via mise if npm is missing.
install_npm() {
  local key=$1 pkg=$2
  local label short
  label=$(reg_field "$key" label)
  short="${label%% (*}"

  if ! command -v npm &>/dev/null; then
    track_warn "npm not found — bootstrapping Node.js via mise"
    install_mise node node@lts || return 1
    # Activate mise in current shell so npm becomes findable
    command -v mise &>/dev/null && eval "$(mise activate bash)" 2>/dev/null || true
  fi

  if ! command -v npm &>/dev/null; then
    track_error "$short — npm still unavailable after bootstrap"
    return 1
  fi

  track_active "$short (npm -g)..."
  if npm install -g "$pkg" >> "$LOG_FILE" 2>&1; then
    printf "\033[1A\033[2K"
    track_success "$short"
    return 0
  fi
  printf "\033[1A\033[2K"
  track_error "$short"
  return 1
}

# Zinit: git-clone the plugin manager into its expected location.
# install_zinit <key>  (no args used)
install_zinit() {
  local key=$1
  local label short
  label=$(reg_field "$key" label)
  short="${label%% (*}"
  local target="$HOME/.local/share/zinit/zinit.git"

  if [ -d "$target" ]; then
    track_success "$short"
    return 0
  fi
  track_active "$short..."
  mkdir -p "$HOME/.local/share/zinit"
  if git clone https://github.com/zdharma-continuum/zinit "$target" >> "$LOG_FILE" 2>&1; then
    printf "\033[1A\033[2K"
    track_success "$short"
    return 0
  fi
  printf "\033[1A\033[2K"
  track_error "$short"
  return 1
}

# ── macOS settings (one function per key) ──
# Each reads its label from the registry so a label change in registry.sh
# automatically propagates to success messages.

install_macos_keyrepeat() {
  local key=$1
  defaults write NSGlobalDomain KeyRepeat -int 2
  defaults write NSGlobalDomain InitialKeyRepeat -int 15
  track_success "$(reg_field "$key" label)"
}

install_macos_finder_hidden() {
  local key=$1
  defaults write com.apple.finder AppleShowAllFiles YES
  _macos_needs_finder_restart=true
  track_success "$(reg_field "$key" label)"
}

install_macos_finder_pathbar() {
  local key=$1
  defaults write com.apple.finder ShowPathbar -bool true
  _macos_needs_finder_restart=true
  track_success "$(reg_field "$key" label)"
}

install_macos_dock() {
  local key=$1
  defaults write com.apple.dock autohide -bool true
  defaults write com.apple.dock autohide-delay -float 0
  defaults write com.apple.dock autohide-time-modifier -float 0.3
  _macos_needs_dock_restart=true
  track_success "$(reg_field "$key" label)"
}

install_macos_mission_control() {
  local key=$1
  defaults write com.apple.dock expose-animation-duration -float 0.1
  _macos_needs_dock_restart=true
  track_success "$(reg_field "$key" label)"
}

install_macos_screenshots() {
  local key=$1
  mkdir -p "$HOME/Screenshots"
  defaults write com.apple.screencapture location "$HOME/Screenshots"
  track_success "$(reg_field "$key" label)"
}

install_macos_hushlogin() {
  local key=$1
  touch "$HOME/.hushlogin"
  track_success "$(reg_field "$key" label)"
}

# Restart Finder/Dock after macOS defaults changes. Orchestrator calls this
# after all macOS installers have run. Private — called only by orchestrator.
_macos_finalize() {
  if [ "${_macos_needs_finder_restart:-false}" = true ]; then
    killall Finder 2>/dev/null || true
  fi
  if [ "${_macos_needs_dock_restart:-false}" = true ]; then
    killall Dock 2>/dev/null || true
  fi
  if [ "${_macos_needs_finder_restart:-false}" = true ] || [ "${_macos_needs_dock_restart:-false}" = true ]; then
    track_info "Finder & Dock restarted"
  fi
}
