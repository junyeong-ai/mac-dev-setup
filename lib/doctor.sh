#!/usr/bin/env bash
# ── Doctor: 개발 환경 진단 도구 ──

doctor_check() {
  local label=$1
  local check=$2
  if eval "$check" &>/dev/null; then
    local ver_out
    ver_out=$(eval "$3" 2>/dev/null | head -1 | cut -c1-35 || echo "OK")
    printf "  \033[32m✓\033[0m  %-35s %s\n" "$label" "$ver_out"
  else
    printf "  \033[31m✗\033[0m  %-35s %s\n" "$label" "not installed"
  fi
}

doctor_config() {
  local label=$1
  local path=$2
  if [ -f "$path" ]; then
    local sz
    sz=$(wc -c < "$path" | tr -d ' ')
    printf "  \033[32m✓\033[0m  %-35s %s bytes\n" "$label" "$sz"
  else
    printf "  \033[31m✗\033[0m  %-35s %s\n" "$label" "missing"
  fi
}

run_doctor() {
  export _ZO_DOCTOR=0
  echo ""
  gum style --border double --border-foreground "#cba6f7" --padding "1 4" --foreground "#cdd6f4" --bold \
    "Mac Dev Setup — Doctor"
  echo ""

  # ── System ──
  gum style --foreground "#fab387" --bold "  System"
  printf "  %-38s %s\n" "macOS" "$(sw_vers -productVersion) ($(uname -m))"
  printf "  %-38s %s\n" "Shell" "$(zsh --version 2>/dev/null || echo 'N/A')"
  printf "  %-38s %s\n" "Homebrew" "$(brew --version 2>/dev/null | head -1 || echo 'not installed')"
  echo ""

  # ── Shell Environment ──
  gum style --foreground "#fab387" --bold "  Shell Environment"
  doctor_check "Oh My Zsh"        "[ -d ~/.oh-my-zsh ]"                    "echo 'installed'"
  doctor_check "Zinit"            "[ -d ~/.local/share/zinit/zinit.git ]"  "echo 'installed'"
  doctor_check "Starship"         "command -v starship"                    "starship --version"
  doctor_check "SCM Breeze"       "[ -d ~/.scm_breeze ]"                  "echo 'installed'"
  echo ""

  # ── Fonts ──
  gum style --foreground "#fab387" --bold "  Fonts"
  doctor_check "Hack Nerd Font"    "ls ~/Library/Fonts/HackNerdFont* 2>/dev/null | head -1" "echo 'installed'"
  doctor_check "Noto Sans CJK KR"  "ls ~/Library/Fonts/NotoSansCJKkr* 2>/dev/null | head -1" "echo 'installed'"
  doctor_check "Pretendard"        "ls ~/Library/Fonts/Pretendard* 2>/dev/null | head -1" "echo 'installed'"
  doctor_check "JetBrains Mono NF" "ls ~/Library/Fonts/JetBrainsMonoNerdFont* 2>/dev/null | head -1" "echo 'installed'"
  doctor_check "Sarasa Gothic"     "ls ~/Library/Fonts/Sarasa* 2>/dev/null | head -1" "echo 'installed'"
  echo ""

  # ── CLI Tools ──
  gum style --foreground "#fab387" --bold "  CLI Tools"
  local tools="eza bat fzf fd rg delta btop dust duf fastfetch nvim zoxide lazygit lazydocker navi jq yq glow procs sd tokei hyperfine tldr gh pnpm uv mise gum"
  local installed=0 missing=0
  for cmd in $tools; do
    if command -v "$cmd" &>/dev/null; then
      local ver
      ver=$("$cmd" --version 2>/dev/null | head -1 | cut -c1-40)
      printf "  \033[32m✓\033[0m  %-35s %s\n" "$cmd" "$ver"
      installed=$((installed + 1))
    else
      printf "  \033[31m✗\033[0m  %-35s %s\n" "$cmd" "not installed"
      missing=$((missing + 1))
    fi
  done
  echo ""
  printf "     Installed: %d / Missing: %d\n" "$installed" "$missing"
  echo ""

  # ── Runtimes ──
  gum style --foreground "#fab387" --bold "  Runtimes"
  doctor_check "mise"     "command -v mise"    "mise --version | head -1"
  doctor_check "Node.js"  "command -v node"    "node --version"
  doctor_check "Python"   "command -v python3" "python3 --version"
  doctor_check "Go"       "command -v go"      "go version"
  # Rust: PATH 또는 mise 둘 다 체크
  if command -v rustc &>/dev/null; then
    printf "  \033[32m✓\033[0m  %-35s %s\n" "Rust" "$(rustc --version 2>/dev/null | head -1 | cut -c1-35)"
  elif mise ls rust &>/dev/null 2>&1; then
    printf "  \033[33m~\033[0m  %-35s %s\n" "Rust" "installed via mise (not in PATH)"
  else
    printf "  \033[31m✗\033[0m  %-35s %s\n" "Rust" "not installed"
  fi
  echo ""

  # ── Apps ──
  gum style --foreground "#fab387" --bold "  Apps"
  for app in Ghostty OrbStack Raycast AltTab Stats Shottr "Visual Studio Code" Cursor; do
    if [ -d "/Applications/${app}.app" ]; then
      printf "  \033[32m✓\033[0m  %s\n" "$app"
    else
      printf "  \033[33m-\033[0m  %s (not installed)\n" "$app"
    fi
  done
  echo ""

  # ── Config Files ──
  gum style --foreground "#fab387" --bold "  Configuration Files"
  doctor_config ".zshrc"            "$HOME/.zshrc"
  doctor_config ".zprofile"         "$HOME/.zprofile"
  doctor_config "Ghostty"           "$HOME/.config/ghostty/config"
  doctor_config "Starship"          "$HOME/.config/starship.toml"
  doctor_config "bat"               "$HOME/.config/bat/config"
  doctor_config "lazygit"           "$HOME/.config/lazygit/config.yml"
  doctor_config ".gitconfig"        "$HOME/.gitconfig"
  doctor_config "Neovim"            "$HOME/.config/nvim/init.lua"
  doctor_config ".hushlogin"        "$HOME/.hushlogin"
  echo ""

  # ── Catppuccin Theme Consistency ──
  gum style --foreground "#fab387" --bold "  Theme Consistency (Catppuccin Mocha)"
  local theme_ok=0 theme_total=0
  for pair in \
    "Ghostty|$HOME/.config/ghostty/config|Catppuccin Mocha" \
    "Starship|$HOME/.config/starship.toml|catppuccin_mocha" \
    "bat|$HOME/.config/bat/config|Catppuccin Mocha" \
    "delta|$HOME/.gitconfig|Catppuccin Mocha" \
    "lazygit|$HOME/.config/lazygit/config.yml|#313244" \
    "Neovim|$HOME/.config/nvim/lua/plugins/catppuccin.lua|catppuccin-mocha"; do
    local name="${pair%%|*}"
    local rest="${pair#*|}"
    local file="${rest%%|*}"
    local pattern="${rest#*|}"
    theme_total=$((theme_total + 1))
    if [ -f "$file" ] && grep -q "$pattern" "$file" 2>/dev/null; then
      printf "  \033[32m✓\033[0m  %s\n" "$name"
      theme_ok=$((theme_ok + 1))
    else
      printf "  \033[31m✗\033[0m  %s (theme not applied)\n" "$name"
    fi
  done
  echo ""
  printf "     Theme: %d/%d consistent\n" "$theme_ok" "$theme_total"
  echo ""

  # ── Git Config ──
  gum style --foreground "#fab387" --bold "  Git"
  local git_name git_email
  git_name=$(git config --global user.name 2>/dev/null || echo "")
  git_email=$(git config --global user.email 2>/dev/null || echo "")
  if [ -n "$git_name" ]; then
    printf "  \033[32m✓\033[0m  user.name: %s\n" "$git_name"
  else
    printf "  \033[31m✗\033[0m  user.name: not set\n"
  fi
  if [ -n "$git_email" ]; then
    printf "  \033[32m✓\033[0m  user.email: %s\n" "$git_email"
  else
    printf "  \033[31m✗\033[0m  user.email: not set\n"
  fi
  doctor_check "GitHub CLI" "gh auth status" "echo 'authenticated'"
  echo ""

  # ── macOS Settings ──
  gum style --foreground "#fab387" --bold "  macOS Settings"
  printf "  KeyRepeat:        %s\n" "$(defaults read NSGlobalDomain KeyRepeat 2>/dev/null || echo 'default')"
  printf "  InitialKeyRepeat: %s\n" "$(defaults read NSGlobalDomain InitialKeyRepeat 2>/dev/null || echo 'default')"
  printf "  Dock autohide:    %s\n" "$(defaults read com.apple.dock autohide 2>/dev/null || echo 'default')"
  printf "  Show all files:   %s\n" "$(defaults read com.apple.finder AppleShowAllFiles 2>/dev/null || echo 'default')"
  printf "  Screenshots:      %s\n" "$(defaults read com.apple.screencapture location 2>/dev/null || echo 'default')"
  echo ""
}
