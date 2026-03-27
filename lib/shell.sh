#!/usr/bin/env bash
# ── 쉘 환경 설치 ──

install_omz() {
  if [ -d "$HOME/.oh-my-zsh" ]; then
    track_success "Oh My Zsh"; return 0
  fi
  track_active "Oh My Zsh..."
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended >> "$LOG_FILE" 2>&1
  printf "\033[1A\033[2K"
  track_success "Oh My Zsh"
}

install_zinit() {
  if [ -d "$HOME/.local/share/zinit/zinit.git" ]; then
    track_success "Zinit"; return 0
  fi
  track_active "Zinit..."
  mkdir -p "$HOME/.local/share/zinit"
  git clone https://github.com/zdharma-continuum/zinit "$HOME/.local/share/zinit/zinit.git" >> "$LOG_FILE" 2>&1
  printf "\033[1A\033[2K"
  track_success "Zinit"
}

install_starship() {
  brew_install starship "Starship (프롬프트)"
}

install_scm_breeze() {
  if [ -d "$HOME/.scm_breeze" ]; then
    track_success "SCM Breeze"; return 0
  fi
  track_active "SCM Breeze..."
  git clone https://github.com/scmbreeze/scm_breeze.git "$HOME/.scm_breeze" >> "$LOG_FILE" 2>&1
  "$HOME/.scm_breeze/install.sh" >> "$LOG_FILE" 2>&1
  printf "\033[1A\033[2K"
  track_success "SCM Breeze"
}

setup_shell() {
  for item in "$@"; do
    case "$item" in
      *"Oh My Zsh"*|*"Zinit"*) install_omz; install_zinit ;;
      *"Starship"*)    install_starship ;;
      *"SCM Breeze"*)  install_scm_breeze ;;
      *"Ghostty"*)     brew_install_cask ghostty "Ghostty (터미널)" "Ghostty" ;;
    esac
  done
}
