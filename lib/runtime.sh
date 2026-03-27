#!/usr/bin/env bash
# ── 런타임 & 패키지 매니저 설치 ──

RUNTIME_OPTIONS=(
  "mise (버전 관리자)|mise"
  "Node.js LTS|node@lts"
  "Python 3.12|python@3.12"
  "Go|go@latest"
  "Rust|rust@latest"
  "pnpm (Node 패키지)|pnpm"
  "uv (Python 패키지)|uv"
)

runtime_labels() {
  for entry in "${RUNTIME_OPTIONS[@]}"; do
    echo "${entry%%|*}"
  done
}

setup_runtimes() {
  local selections=("$@")
  local mise_installed=false

  for label in "${selections[@]}"; do
    case "$label" in
      *"mise"*)
        brew_install mise "mise (버전 관리자)"
        mise_installed=true
        ;;
      *"pnpm"*)
        brew_install pnpm "pnpm"
        ;;
      *"uv"*)
        brew_install uv "uv"
        ;;
      *"Node.js"*)
        if $mise_installed || command -v mise &>/dev/null; then
          ui_spin "Installing Node.js LTS via mise..." \
            bash -c 'eval "$(mise activate bash)" && mise use -g node@lts' >> "$LOG_FILE" 2>&1
          ui_success "Node.js LTS (via mise)"
        else
          ui_warn "Skipped Node.js — mise not selected"
        fi
        ;;
      *"Python"*)
        if $mise_installed || command -v mise &>/dev/null; then
          ui_spin "Installing Python 3.12 via mise..." \
            bash -c 'eval "$(mise activate bash)" && mise use -g python@3.12' >> "$LOG_FILE" 2>&1
          ui_success "Python 3.12 (via mise)"
        else
          ui_warn "Skipped Python — mise not selected"
        fi
        ;;
      *"Go"*)
        if $mise_installed || command -v mise &>/dev/null; then
          ui_spin "Installing Go via mise..." \
            bash -c 'eval "$(mise activate bash)" && mise use -g go@latest' >> "$LOG_FILE" 2>&1
          ui_success "Go (via mise)"
        else
          ui_warn "Skipped Go — mise not selected"
        fi
        ;;
      *"Rust"*)
        if command -v rustup &>/dev/null; then
          ui_success "Rust (already installed)"
        else
          ui_spin "Installing Rust via rustup..." \
            bash -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y' >> "$LOG_FILE" 2>&1
          ui_success "Rust"
        fi
        ;;
    esac
  done
}
