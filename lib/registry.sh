#!/usr/bin/env bash
# Registry — single source of truth for every installable option.
#
# Record format (pipe-separated, 7 fields):
#   KEY | TYPE | LABEL | INSTALLER | ARGS | TIER | CHECK
#
#   KEY       snake_case English id, unique, stable
#   TYPE      shell | font | cli | runtime | ai | app | macos
#   LABEL     user-facing display string (Korean allowed)
#   INSTALLER installer token → dispatch calls install_<INSTALLER>
#   ARGS      whitespace-separated arguments passed to the installer
#   TIER      essential | recommended | extra
#   CHECK     shell expression evaluated by doctor (empty uses type default)
#
# Design notes:
#   - Records with embedded whitespace in labels are fine (labels are field 3).
#   - ARGS uses whitespace; installers that need multi-word arg (e.g. app
#     name with spaces) consume trailing tokens as a single value.
#   - To add an option: append one record. To remove: delete one record.
#   - No presets; tier drives defaults (essential+recommended).
#   - Catppuccin theme is NOT a registry entry — it is applied unconditionally
#     by lib/configs.sh when config files are deployed.
#
# Forbidden characters:
#   - '|' (pipe) — record separator. Never use in LABEL, ARGS, or CHECK.
#     If a CHECK expression needs a pipe, rewrite without it (e.g. replace
#     `cmd | head -1` with `cmd >/dev/null` or compgen).

REGISTRY=(
  # Shell & terminal
  "ghostty|shell|Ghostty (터미널)|brew_cask|ghostty Ghostty|essential|[ -d /Applications/Ghostty.app ]"
  "zinit|shell|Zinit (쉘 플러그인 매니저)|zinit||essential|[ -d $HOME/.local/share/zinit/zinit.git ]"
  "starship|shell|Starship (프롬프트)|brew|starship|essential|command -v starship"

  # Fonts
  "font_hack|font|Hack Nerd Font Mono|brew_cask|font-hack-nerd-font|essential|ls $HOME/Library/Fonts/HackNerdFont* &>/dev/null"
  "font_jetbrains|font|JetBrains Mono Nerd Font|brew_cask|font-jetbrains-mono-nerd-font|extra|ls $HOME/Library/Fonts/JetBrainsMonoNerdFont* &>/dev/null"
  "font_sarasa|font|Sarasa Gothic (한영 통합)|brew_cask|font-sarasa-gothic|extra|ls $HOME/Library/Fonts/Sarasa* &>/dev/null"
  "font_noto|font|Noto Sans CJK KR (한글)|brew_cask|font-noto-sans-cjk-kr|essential|ls $HOME/Library/Fonts/NotoSansCJKkr* &>/dev/null"
  "font_pretendard|font|Pretendard (한글 UI)|brew_cask|font-pretendard|recommended|ls $HOME/Library/Fonts/Pretendard* &>/dev/null"

  # CLI — essential (Rust-based modern replacements)
  "eza|cli|eza (ls 대체)|brew|eza|essential|command -v eza"
  "bat|cli|bat (cat 대체)|brew|bat|essential|command -v bat"
  "fd|cli|fd (find 대체)|brew|fd|essential|command -v fd"
  "ripgrep|cli|ripgrep (grep 대체)|brew|ripgrep|essential|command -v rg"
  "fzf|cli|fzf (퍼지 검색)|brew|fzf|essential|command -v fzf"

  # CLI — recommended (productivity)
  "gh|cli|gh (GitHub CLI)|brew|gh|recommended|command -v gh"
  "zoxide|cli|zoxide (스마트 cd)|brew|zoxide|recommended|command -v zoxide"
  "lazygit|cli|lazygit (Git TUI)|brew|lazygit|recommended|command -v lazygit"
  "git_delta|cli|delta (git diff 강화)|brew|git-delta|recommended|command -v delta"
  "btop|cli|btop (시스템 모니터)|brew|btop|recommended|command -v btop"
  "dust|cli|dust (du 대체)|brew|dust|recommended|command -v dust"
  "duf|cli|duf (df 대체)|brew|duf|recommended|command -v duf"
  "jq|cli|jq (JSON 처리)|brew|jq|recommended|command -v jq"
  "yq|cli|yq (YAML 처리)|brew|yq|recommended|command -v yq"
  "atuin|cli|atuin (쉘 히스토리 DB)|brew|atuin|recommended|command -v atuin"
  "just|cli|just (명령 러너)|brew|just|recommended|command -v just"

  # CLI — extra
  "lazydocker|cli|lazydocker (Docker TUI)|brew|lazydocker|extra|command -v lazydocker"
  "navi|cli|navi (치트시트 위젯)|brew|navi|extra|command -v navi"
  "glow|cli|glow (마크다운 뷰어)|brew|glow|extra|command -v glow"

  # Runtime — managed by mise except for mise itself and direct package managers
  "mise|runtime|mise (버전 관리자)|brew|mise|essential|command -v mise"
  "node|runtime|Node.js LTS|mise|node@lts|essential|command -v node"
  "pnpm|runtime|pnpm (Node 패키지)|brew|pnpm|essential|command -v pnpm"
  "uv|runtime|uv (Python 패키지)|brew|uv|recommended|command -v uv"
  "python|runtime|Python (최신)|mise|python@latest|recommended|command -v python3"
  "bun|runtime|Bun (JS/TS 런타임)|mise|bun@latest|extra|command -v bun"
  "go|runtime|Go|mise|go@latest|extra|command -v go"
  "rust|runtime|Rust|mise|rust@latest|extra|command -v rustc"

  # AI
  "claude_code|ai|Claude Code (Anthropic CLI)|npm|@anthropic-ai/claude-code|recommended|command -v claude"

  # Apps (brew cask; ARGS = cask then app name tokens)
  "app_raycast|app|Raycast (Spotlight 대체)|brew_cask|raycast Raycast|recommended|[ -d /Applications/Raycast.app ]"
  "app_orbstack|app|OrbStack (Docker)|brew_cask|orbstack OrbStack|recommended|[ -d /Applications/OrbStack.app ]"
  "app_alttab|app|AltTab (윈도우 스위처)|brew_cask|alt-tab AltTab|extra|[ -d /Applications/AltTab.app ]"
  "app_stats|app|Stats (시스템 모니터)|brew_cask|stats Stats|extra|[ -d /Applications/Stats.app ]"
  "app_shottr|app|Shottr (스크린샷 + OCR)|brew_cask|shottr Shottr|extra|[ -d /Applications/Shottr.app ]"
  "app_vscode|app|Visual Studio Code|brew_cask|visual-studio-code Visual Studio Code|extra|[ -d '/Applications/Visual Studio Code.app' ]"

  # macOS — each setting has its own installer function (install_macos_*)
  "macos_keyrepeat|macos|키 반복 속도 최적화|macos_keyrepeat||recommended|[ \"\$(defaults read NSGlobalDomain KeyRepeat 2>/dev/null)\" = 2 ]"
  "macos_finder_hidden|macos|Finder 숨김 파일 표시|macos_finder_hidden||recommended|[ \"\$(defaults read com.apple.finder AppleShowAllFiles 2>/dev/null)\" = YES ]"
  "macos_finder_pathbar|macos|Finder 경로 표시줄|macos_finder_pathbar||recommended|[ \"\$(defaults read com.apple.finder ShowPathbar 2>/dev/null)\" = 1 ]"
  "macos_dock|macos|Dock 자동 숨김 + 빠른 애니메이션|macos_dock||recommended|[ \"\$(defaults read com.apple.dock autohide 2>/dev/null)\" = 1 ]"
  "macos_mission_control|macos|미션 컨트롤 애니메이션 가속|macos_mission_control||recommended|defaults read com.apple.dock expose-animation-duration"
  "macos_screenshots|macos|스크린샷 ~/Screenshots 저장|macos_screenshots||recommended|[ -d $HOME/Screenshots ]"
  "macos_hushlogin|macos|Last login 메시지 제거|macos_hushlogin||essential|[ -f $HOME/.hushlogin ]"
)

# ── Accessors ──

# Ordered list of all keys
reg_keys() {
  local entry
  for entry in "${REGISTRY[@]}"; do
    echo "${entry%%|*}"
  done
}

# All types in registry order (deduplicated)
reg_types() {
  local entry last=""
  for entry in "${REGISTRY[@]}"; do
    local IFS='|'
    local -a arr
    read -ra arr <<< "$entry"
    local t="${arr[1]}"
    if [ "$t" != "$last" ]; then
      echo "$t"
      last="$t"
    fi
  done
}

# Keys filtered by type
reg_keys_by_type() {
  local want=$1 entry
  for entry in "${REGISTRY[@]}"; do
    local IFS='|'
    local -a arr
    read -ra arr <<< "$entry"
    [ "${arr[1]}" = "$want" ] && echo "${arr[0]}"
  done
}

# Keys filtered by tier
reg_keys_by_tier() {
  local want=$1 entry
  for entry in "${REGISTRY[@]}"; do
    local IFS='|'
    local -a arr
    read -ra arr <<< "$entry"
    [ "${arr[5]}" = "$want" ] && echo "${arr[0]}"
  done
}

# Lookup a single field (key | type | label | installer | args | tier | check)
reg_field() {
  local key=$1 field=$2 entry
  for entry in "${REGISTRY[@]}"; do
    local k="${entry%%|*}"
    [ "$k" = "$key" ] || continue
    local IFS='|'
    local -a arr
    read -ra arr <<< "$entry"
    case "$field" in
      key)       echo "${arr[0]}" ;;
      type)      echo "${arr[1]}" ;;
      label)     echo "${arr[2]}" ;;
      installer) echo "${arr[3]}" ;;
      args)      echo "${arr[4]}" ;;
      tier)      echo "${arr[5]}" ;;
      check)     echo "${arr[6]}" ;;
      *)         return 1 ;;
    esac
    return 0
  done
  return 1
}

# Default-tier keys (essential + recommended). Used by --ci mode and UI preselect.
reg_default_keys() {
  reg_keys_by_tier essential
  reg_keys_by_tier recommended
}

# ── Type display helpers ──
# Two intents: UI label (shown in interactive selection) and log label
# (shown during install execution). Name by purpose, not locale.

type_ui_title() {
  case "$1" in
    shell)   echo "터미널 & 쉘 환경" ;;
    font)    echo "코딩 폰트" ;;
    cli)     echo "모던 CLI 도구" ;;
    runtime) echo "개발 런타임" ;;
    ai)      echo "AI 개발 도구" ;;
    app)     echo "앱 & 생산성" ;;
    macos)   echo "macOS 시스템 설정" ;;
    *)       echo "UNMAPPED TYPE '$1' — update type_ui_title in registry.sh" >&2
             echo "$1" ;;
  esac
}

type_log_title() {
  case "$1" in
    shell)   echo "Shell Environment" ;;
    font)    echo "Fonts" ;;
    cli)     echo "CLI Tools" ;;
    runtime) echo "Runtimes" ;;
    ai)      echo "AI Tools" ;;
    app)     echo "Apps" ;;
    macos)   echo "macOS Settings" ;;
    *)       echo "UNMAPPED TYPE '$1' — update type_log_title in registry.sh" >&2
             echo "$1" ;;
  esac
}

# ── Schema validation ──
# Public API — called from setup.sh after installers.sh is sourced.
# Fails fast on any broken dispatch link.

validate_registry() {
  local k installer missing=0
  while IFS= read -r k; do
    installer=$(reg_field "$k" installer)
    if ! declare -F "install_${installer}" >/dev/null 2>&1; then
      echo "REGISTRY ERROR: install_${installer} not defined (key: $k)" >&2
      missing=$((missing + 1))
    fi
  done < <(reg_keys)
  if [ "$missing" -gt 0 ]; then
    echo "REGISTRY ERROR: $missing dispatch link(s) broken. Aborting." >&2
    exit 1
  fi
}
