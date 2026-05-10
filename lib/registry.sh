#!/usr/bin/env bash
# Registry — single source of truth for every installable option.
#
# Record format (pipe-separated, 8 fields):
#   KEY | TYPE | LABEL | INSTALLER | ARGS | TIER | DEPS | CHECK
#
#   KEY       snake_case English id, unique, stable
#   TYPE      shell | font | cli | git | runtime | ai | app | macos
#   LABEL     user-facing display string (Korean allowed)
#   INSTALLER installer token → dispatch calls install_<INSTALLER>
#   ARGS      whitespace-separated arguments passed to the installer
#   TIER      essential | recommended | extra
#   DEPS      whitespace-separated registry keys that must install first
#   CHECK     shell expression used by installer and doctor verification
#             (empty uses type default)
#
# Design notes:
#   - Records with embedded whitespace in labels are fine (labels are field 3).
#   - ARGS uses whitespace-separated installer arguments.
#   - To add an option: append one record. To remove: delete one record.
#   - No presets; tier drives defaults (essential+recommended).
#   - Catppuccin theme is NOT a registry entry — it is applied by
#     lib/configs.sh to each selected config file that is deployed.
#
# Forbidden characters:
#   - '|' (pipe) — record separator. Never use in LABEL, ARGS, DEPS, or CHECK.
#     If a CHECK expression needs a pipe, rewrite without it (e.g. replace
#     `cmd | head -1` with `cmd >/dev/null` or compgen).
#   - ',' in LABEL — gum receives default selections as a comma-separated
#     value, so labels must stay comma-free.

REGISTRY=(
  # Shell & terminal
  "ghostty|shell|Ghostty (터미널)|brew_cask|ghostty|essential||[ -d /Applications/Ghostty.app ]"
  "zinit|shell|Zinit (쉘 플러그인 매니저)|zinit||essential|git|[ -d \"$HOME/.local/share/zinit/zinit.git\" ]"
  "starship|shell|Starship (프롬프트)|brew|starship|essential||brew list --formula starship && command -v starship"

  # Fonts
  "font_hack|font|Hack Nerd Font Mono|brew_cask|font-hack-nerd-font|essential||if compgen -G \"$HOME/Library/Fonts/HackNerdFont*\" >/dev/null; then true; else compgen -G \"/opt/homebrew/share/fonts/HackNerdFont*\" >/dev/null; fi"
  "font_jetbrains|font|JetBrains Mono Nerd Font|brew_cask|font-jetbrains-mono-nerd-font|extra||if compgen -G \"$HOME/Library/Fonts/JetBrainsMonoNerdFont*\" >/dev/null; then true; else compgen -G \"/opt/homebrew/share/fonts/JetBrainsMonoNerdFont*\" >/dev/null; fi"
  "font_sarasa|font|Sarasa Gothic (한영 통합)|brew_cask|font-sarasa-gothic|extra||if compgen -G \"$HOME/Library/Fonts/Sarasa*\" >/dev/null; then true; else compgen -G \"/opt/homebrew/share/fonts/Sarasa*\" >/dev/null; fi"
  "font_noto|font|Noto Sans CJK KR (한글)|brew_cask|font-noto-sans-cjk-kr|essential||if compgen -G \"$HOME/Library/Fonts/NotoSansCJKkr*\" >/dev/null; then true; else compgen -G \"/opt/homebrew/share/fonts/NotoSansCJKkr*\" >/dev/null; fi"
  "font_pretendard|font|Pretendard (한글 UI)|brew_cask|font-pretendard|recommended||if compgen -G \"$HOME/Library/Fonts/Pretendard*\" >/dev/null; then true; else compgen -G \"/opt/homebrew/share/fonts/Pretendard*\" >/dev/null; fi"

  # CLI — essential (Rust-based modern replacements)
  "gum|cli|gum (UI 툴킷)|brew|gum|essential||brew list --formula gum && command -v gum"
  "eza|cli|eza (ls 대체)|brew|eza|essential||brew list --formula eza && command -v eza"
  "bat|cli|bat (cat 대체)|brew|bat|essential||brew list --formula bat && command -v bat"
  "fd|cli|fd (find 대체)|brew|fd|essential||brew list --formula fd && command -v fd"
  "ripgrep|cli|ripgrep (grep 대체)|brew|ripgrep|essential||brew list --formula ripgrep && command -v rg"
  "fzf|cli|fzf (퍼지 검색)|brew|fzf|essential||brew list --formula fzf && command -v fzf"

  # CLI — recommended (productivity)
  "zoxide|cli|zoxide (스마트 cd)|brew|zoxide|recommended||brew list --formula zoxide && command -v zoxide"
  "btop|cli|btop (시스템 모니터)|brew|btop|recommended||brew list --formula btop && command -v btop"
  "dust|cli|dust (du 대체)|brew|dust|recommended||brew list --formula dust && command -v dust"
  "duf|cli|duf (df 대체)|brew|duf|recommended||brew list --formula duf && command -v duf"
  "jq|cli|jq (JSON 처리)|brew|jq|recommended||brew list --formula jq && command -v jq"
  "yq|cli|yq (YAML 처리)|brew|yq|recommended||brew list --formula yq && command -v yq"
  "atuin|cli|atuin (쉘 히스토리 DB)|brew|atuin|recommended||brew list --formula atuin && command -v atuin"
  "just|cli|just (명령 러너)|brew|just|recommended||brew list --formula just && command -v just"
  "neovim|cli|Neovim (LazyVim 에디터)|brew|neovim|recommended|git|brew list --formula neovim && command -v nvim"
  "direnv|cli|direnv (프로젝트 env)|brew|direnv|recommended||brew list --formula direnv && command -v direnv"
  "shellcheck|cli|ShellCheck (쉘 정적 분석)|brew|shellcheck|recommended||brew list --formula shellcheck && command -v shellcheck"
  "shfmt|cli|shfmt (쉘 포맷터)|brew|shfmt|recommended||brew list --formula shfmt && command -v shfmt"

  # CLI — extra
  "lazydocker|cli|lazydocker (Docker TUI)|brew|lazydocker|extra||brew list --formula lazydocker && command -v lazydocker"
  "glow|cli|glow (마크다운 뷰어)|brew|glow|extra||brew list --formula glow && command -v glow"
  "sd|cli|sd (sed 대체)|brew|sd|extra||brew list --formula sd && command -v sd"
  "tokei|cli|tokei (코드 통계)|brew|tokei|extra||brew list --formula tokei && command -v tokei"
  "hyperfine|cli|hyperfine (벤치마크)|brew|hyperfine|extra||brew list --formula hyperfine && command -v hyperfine"
  "watchexec|cli|watchexec (파일 변경 실행)|brew|watchexec|extra||brew list --formula watchexec && command -v watchexec"
  "procs|cli|procs (ps 대체)|brew|procs|extra||brew list --formula procs && command -v procs"
  "xh|cli|xh (HTTP 클라이언트)|brew|xh|extra||brew list --formula xh && command -v xh"

  # Git
  "git|git|Git|brew|git|essential||brew list --formula git && command -v git"
  "git_defaults|git|Git 기본 설정|git_defaults||recommended|git|git config --global init.defaultBranch && git config --global pull.rebase && git config --global fetch.prune && git config --global rerere.enabled"
  "gh|git|gh (GitHub CLI)|brew|gh|recommended|git|brew list --formula gh && command -v gh"
  "lazygit|git|lazygit (Git TUI)|brew|lazygit|recommended|git|brew list --formula lazygit && command -v lazygit"
  "git_delta|git|delta (git diff 강화)|brew|git-delta|recommended|git|brew list --formula git-delta && command -v delta"
  "git_lfs|git|Git LFS|git_lfs||extra|git|brew list --formula git-lfs && command -v git-lfs && git config --global filter.lfs.clean"

  # Runtime — managed by mise except for mise itself and direct package managers
  "mise|runtime|mise (버전 관리자)|brew|mise|essential||brew list --formula mise && command -v mise"
  "node|runtime|Node.js LTS|mise|node@lts|essential|mise|mise where node && command -v node && command -v npm"
  "pnpm|runtime|pnpm (Node 패키지)|mise|pnpm@latest|essential|mise|mise where pnpm && command -v pnpm"
  "uv|runtime|uv (Python 패키지)|brew|uv|recommended||brew list --formula uv && command -v uv"
  "python|runtime|Python (최신)|mise|python@latest|recommended|mise|mise where python && command -v python3"
  "bun|runtime|Bun (JS/TS 런타임)|mise|bun@latest|extra|mise|mise where bun && command -v bun"
  "go|runtime|Go|mise|go@latest|extra|mise|mise where go && command -v go"
  "rust|runtime|Rust|mise|rust@latest|extra|mise|mise where rust && command -v rustc"

  # AI
  "claude_code|ai|Claude Code (Anthropic CLI)|brew_cask|claude-code|recommended||command -v claude"

  # Apps
  "app_raycast|app|Raycast (Spotlight 대체)|brew_cask|raycast|recommended||[ -d /Applications/Raycast.app ]"
  "app_orbstack|app|OrbStack (Docker)|brew_cask|orbstack|recommended||[ -d /Applications/OrbStack.app ]"
  "app_alttab|app|AltTab (윈도우 스위처)|brew_cask|alt-tab|extra||[ -d /Applications/AltTab.app ]"
  "app_stats|app|Stats (시스템 모니터)|brew_cask|stats|extra||[ -d /Applications/Stats.app ]"
  "app_shottr|app|Shottr (스크린샷 + OCR)|brew_cask|shottr|extra||[ -d /Applications/Shottr.app ]"
  "app_vscode|app|Visual Studio Code|brew_cask|visual-studio-code|extra||[ -d '/Applications/Visual Studio Code.app' ]"

  # macOS — each setting has its own installer function (install_macos_*)
  "macos_keyrepeat|macos|키 반복 속도 최적화|macos_keyrepeat||recommended||[ \"\$(defaults read NSGlobalDomain KeyRepeat 2>/dev/null)\" = 2 ] && [ \"\$(defaults read NSGlobalDomain InitialKeyRepeat 2>/dev/null)\" = 15 ]"
  "macos_finder_hidden|macos|Finder 숨김 파일 표시|macos_finder_hidden||recommended||[ \"\$(defaults read com.apple.finder AppleShowAllFiles 2>/dev/null)\" = YES ]"
  "macos_finder_pathbar|macos|Finder 경로 표시줄|macos_finder_pathbar||recommended||[ \"\$(defaults read com.apple.finder ShowPathbar 2>/dev/null)\" = 1 ]"
  "macos_dock|macos|Dock 자동 숨김 + 빠른 애니메이션|macos_dock||recommended||[ \"\$(defaults read com.apple.dock autohide 2>/dev/null)\" = 1 ] && [ \"\$(defaults read com.apple.dock autohide-delay 2>/dev/null)\" = 0 ] && [ \"\$(defaults read com.apple.dock autohide-time-modifier 2>/dev/null)\" = \"0.3\" ]"
  "macos_mission_control|macos|미션 컨트롤 애니메이션 가속|macos_mission_control||recommended||[ \"\$(defaults read com.apple.dock expose-animation-duration 2>/dev/null)\" = \"0.1\" ]"
  "macos_screenshots|macos|스크린샷 ~/Screenshots 저장|macos_screenshots||recommended||[ \"\$(defaults read com.apple.screencapture location 2>/dev/null)\" = \"$HOME/Screenshots\" ]"
  "macos_hushlogin|macos|Last login 메시지 제거|macos_hushlogin||essential||[ -f \"$HOME/.hushlogin\" ]"
)

# ── Accessors ──

# Ordered list of all keys
reg_keys() {
  local entry
  for entry in "${REGISTRY[@]}"; do
    echo "${entry%%|*}"
  done
  return 0
}

# All types in registry order (deduplicated)
reg_types() {
  local entry seen=""
  for entry in "${REGISTRY[@]}"; do
    local IFS='|'
    local -a arr
    read -ra arr <<< "$entry"
    local t="${arr[1]}"
    case "$seen" in
      *"|$t|"*) ;;
      *) echo "$t"; seen="${seen}|$t|" ;;
    esac
  done
  return 0
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
  return 0
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
  return 0
}

# Lookup a single field (key | type | label | installer | args | tier | deps | check)
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
      deps)      echo "${arr[6]}" ;;
      check)     echo "${arr[7]}" ;;
      *)         return 1 ;;
    esac
    return 0
  done
  return 1
}

reg_check_passes() {
  local key=$1 check type
  check=$(reg_field "$key" check)
  if [ -n "$check" ]; then
    eval "$check" &>/dev/null
    return $?
  fi

  type=$(reg_field "$key" type)
  case "$type" in
    cli|git|runtime|ai) command -v "$key" &>/dev/null ;;
    *)                  return 1 ;;
  esac
}

# Default-tier keys (essential + recommended) in registry order. Used by
# --ci mode; the interactive UI computes per-category defaults separately.
reg_default_keys() {
  local entry tier
  for entry in "${REGISTRY[@]}"; do
    local IFS='|'
    local -a arr
    read -ra arr <<< "$entry"
    tier="${arr[5]}"
    if [ "$tier" = "essential" ] || [ "$tier" = "recommended" ]; then
      echo "${arr[0]}"
    fi
  done
  return 0
}

# ── Type display helpers ──
# Two intents: UI label (shown in interactive selection) and log label
# (shown during install execution). Name by purpose, not locale.

type_ui_title() {
  case "$1" in
    shell)   echo "터미널 & 쉘 환경" ;;
    font)    echo "코딩 폰트" ;;
    cli)     echo "모던 CLI 도구" ;;
    git)     echo "Git & 협업 도구" ;;
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
    git)     echo "Git Tools" ;;
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
# Fails fast on malformed records, duplicate keys, invalid enums, dependency
# errors, or broken dispatch links.

validate_registry() {
  local entry seen_keys="" seen_labels="" errors=0
  for entry in "${REGISTRY[@]}"; do
    local pipe_count
    pipe_count=$(printf "%s" "$entry" | tr -cd '|' | wc -c | tr -d ' ')
    if [ "$pipe_count" -ne 7 ]; then
      echo "REGISTRY ERROR: expected 8 fields, got $((pipe_count + 1)): $entry" >&2
      errors=$((errors + 1))
      continue
    fi

    local IFS='|'
    local -a arr
    read -ra arr <<< "$entry"

    local k type label installer args tier deps check
    k="${arr[0]}"
    type="${arr[1]}"
    label="${arr[2]}"
    installer="${arr[3]}"
    args="${arr[4]}"
    tier="${arr[5]}"
    deps="${arr[6]}"
    check="${arr[7]}"

    if [ -z "$k" ] || [ -z "$type" ] || [ -z "$label" ] || [ -z "$installer" ] || [ -z "$tier" ]; then
      echo "REGISTRY ERROR: key, type, label, installer, and tier are required: $entry" >&2
      errors=$((errors + 1))
      continue
    fi

    if [[ ! "$k" =~ ^[a-z0-9_]+$ ]]; then
      echo "REGISTRY ERROR: invalid key '$k' (snake_case lowercase required)" >&2
      errors=$((errors + 1))
    fi

    case "$seen_keys" in
      *"|$k|"*)
        echo "REGISTRY ERROR: duplicate key '$k'" >&2
        errors=$((errors + 1))
        ;;
      *) seen_keys="${seen_keys}|$k|" ;;
    esac

    case "$seen_labels" in
      *"|$label|"*)
        echo "REGISTRY ERROR: duplicate label '$label' (key: $k)" >&2
        errors=$((errors + 1))
        ;;
      *) seen_labels="${seen_labels}|$label|" ;;
    esac

    if [[ "$label" == *,* ]]; then
      echo "REGISTRY ERROR: label cannot contain ',' because gum selected defaults are comma-separated (key: $k)" >&2
      errors=$((errors + 1))
    fi

    case "$type" in
      shell|font|cli|git|runtime|ai|app|macos) ;;
      *)
        echo "REGISTRY ERROR: invalid type '$type' (key: $k)" >&2
        errors=$((errors + 1))
        ;;
    esac

    case "$tier" in
      essential|recommended|extra) ;;
      *)
        echo "REGISTRY ERROR: invalid tier '$tier' (key: $k)" >&2
        errors=$((errors + 1))
        ;;
    esac

    case "$type" in
      cli|git|runtime|ai) ;;
      *)
        if [ -z "$check" ]; then
          echo "REGISTRY ERROR: type '$type' requires explicit CHECK (key: $k)" >&2
          errors=$((errors + 1))
        fi
        ;;
    esac

    local arg_count
    arg_count=$(_registry_word_count "$args")
    case "$installer" in
      brew|brew_cask|mise|npm)
        if [ "$arg_count" -ne 1 ]; then
          echo "REGISTRY ERROR: installer '$installer' requires exactly 1 arg (key: $k)" >&2
          errors=$((errors + 1))
        fi
        ;;
      zinit|git_defaults|git_lfs|macos_*)
        if [ "$arg_count" -ne 0 ]; then
          echo "REGISTRY ERROR: installer '$installer' does not accept args (key: $k)" >&2
          errors=$((errors + 1))
        fi
        ;;
    esac

    local dep
    for dep in $deps; do
      if [[ ! "$dep" =~ ^[a-z0-9_]+$ ]]; then
        echo "REGISTRY ERROR: invalid dependency '$dep' (key: $k)" >&2
        errors=$((errors + 1))
        continue
      fi
      if [ "$dep" = "$k" ]; then
        echo "REGISTRY ERROR: key '$k' cannot depend on itself" >&2
        errors=$((errors + 1))
      elif ! reg_field "$dep" key >/dev/null 2>&1; then
        echo "REGISTRY ERROR: unknown dependency '$dep' (key: $k)" >&2
        errors=$((errors + 1))
      fi
    done

    if ! declare -F "install_${installer}" >/dev/null 2>&1; then
      echo "REGISTRY ERROR: install_${installer} not defined (key: $k)" >&2
      errors=$((errors + 1))
    fi
  done

  if [ "$errors" -eq 0 ]; then
    _validate_dependency_graph || errors=$((errors + 1))
  fi

  if [ "$errors" -gt 0 ]; then
    echo "REGISTRY ERROR: $errors schema issue(s). Aborting." >&2
    exit 1
  fi
}

_registry_word_count() {
  local text=$1
  printf "%s\n" "$text" | wc -w | tr -d ' '
}

_validate_dependency_graph() {
  _reg_dep_seen=""
  _reg_dep_errors=0

  local entry key
  for entry in "${REGISTRY[@]}"; do
    key="${entry%%|*}"
    _visit_dependency_key "$key" ""
  done

  local errors=$_reg_dep_errors
  unset _reg_dep_seen _reg_dep_errors
  [ "$errors" -eq 0 ]
}

_visit_dependency_key() {
  local key=$1 stack=$2
  case "|$stack|" in
    *"|$key|"*)
      echo "REGISTRY ERROR: dependency cycle detected: ${stack}|${key}" >&2
      _reg_dep_errors=$((_reg_dep_errors + 1))
      return 0
      ;;
  esac
  case "$_reg_dep_seen" in
    *"|$key|"*) return 0 ;;
  esac

  local deps dep next_stack
  deps=$(reg_field "$key" deps)
  if [ -n "$stack" ]; then
    next_stack="${stack}|${key}"
  else
    next_stack="$key"
  fi

  for dep in $deps; do
    _visit_dependency_key "$dep" "$next_stack"
  done

  _reg_dep_seen="${_reg_dep_seen}|$key|"
}
