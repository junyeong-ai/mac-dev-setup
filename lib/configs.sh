#!/usr/bin/env bash
# Config deployment with user-managed block preservation.
#
# The .zshrc template contains a marker pair:
#   # >>> user-managed >>>
#   ...content preserved across re-runs...
#   # <<< user-managed <<<
#
# On deploy, any content between those markers in an existing ~/.zshrc is
# extracted and re-injected into the fresh template.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

USER_BLOCK_BEGIN="# >>> user-managed >>>"
USER_BLOCK_END="# <<< user-managed <<<"
ZPROFILE_BLOCK_BEGIN="# >>> mac-dev-setup: homebrew >>>"
ZPROFILE_BLOCK_END="# <<< mac-dev-setup: homebrew <<<"

# ── Public entry ──

# deploy_configs <selected_keys>
# selected_keys is a newline-separated list; selected app/tool configs inspect
# this list so interactive choices remain authoritative.
deploy_configs() {
  local keys=$1

  _deploy_zprofile || return 1
  _deploy_zshrc || return 1

  local key src dst label check
  while IFS='|' read -r key src dst label check; do
    [ -z "$key" ] && continue
    if _has_key "$keys" "$key" && eval "$check" &>/dev/null; then
      _deploy_simple "$src" "$dst" "$label" || return 1
    fi
  done < <(managed_simple_config_deployments)

  if _has_key "$keys" git_delta; then
    _configure_delta || return 1
  fi
  if _has_key "$keys" difftastic; then
    _configure_difftastic || return 1
  fi
  if _has_key "$keys" neovim; then
    _configure_neovim || return 1
  fi
}

managed_simple_config_deployments() {
  cat << EOF
ghostty|configs/ghostty.config|$HOME/.config/ghostty/config|Ghostty config|[ -d /Applications/Ghostty.app ]
starship|configs/starship.toml|$HOME/.config/starship.toml|Starship config|command -v starship
bat|configs/bat.config|$HOME/.config/bat/config|bat config|command -v bat
lazygit|configs/lazygit.yml|$HOME/.config/lazygit/config.yml|lazygit config|command -v lazygit
EOF
}

managed_config_checks() {
  cat << EOF
.zshrc|$HOME/.zshrc||# >>> user-managed >>>
.zprofile|$HOME/.zprofile||# >>> mac-dev-setup: homebrew >>>
Ghostty|$HOME/.config/ghostty/config|[ -d /Applications/Ghostty.app ]|Catppuccin Mocha
Starship|$HOME/.config/starship.toml|command -v starship|catppuccin_mocha
bat|$HOME/.config/bat/config|command -v bat|Catppuccin Mocha
lazygit|$HOME/.config/lazygit/config.yml|command -v lazygit|#313244
.gitconfig|$HOME/.gitconfig||
Neovim|$HOME/.config/nvim/init.lua|command -v nvim|LazyVim
.hushlogin|$HOME/.hushlogin||
EOF
}

managed_theme_checks() {
  cat << EOF
Ghostty|$HOME/.config/ghostty/config|Catppuccin Mocha|[ -d /Applications/Ghostty.app ]
Starship|$HOME/.config/starship.toml|catppuccin_mocha|command -v starship
bat|$HOME/.config/bat/config|Catppuccin Mocha|command -v bat
delta|$HOME/.gitconfig|Catppuccin Mocha|command -v delta
lazygit|$HOME/.config/lazygit/config.yml|#313244|command -v lazygit
Neovim|$HOME/.config/nvim/lua/plugins/catppuccin.lua|catppuccin-mocha|command -v nvim
EOF
}

# ── Internals ──

_has_key() {
  local keys=$1 key=$2
  echo "$keys" | grep -qxF "$key"
}

_deploy_simple() {
  local src=$1 dst=$2 label=$3
  mkdir -p "$(dirname "$dst")" || { track_error "$label"; return 1; }
  cp "$SCRIPT_DIR/$src" "$dst" || { track_error "$label"; return 1; }
  track_success "$label"
}

_deploy_zprofile() {
  local dst="$HOME/.zprofile"
  local block
  block=$(cat << 'EOF'
# >>> mac-dev-setup: homebrew >>>
eval "$(/opt/homebrew/bin/brew shellenv)"
# <<< mac-dev-setup: homebrew <<<
EOF
)

  if [ ! -f "$dst" ]; then
    printf "%s\n" "$block" > "$dst" || { track_error ".zprofile"; return 1; }
  elif grep -qF "$ZPROFILE_BLOCK_BEGIN" "$dst"; then
    _replace_managed_block "$dst" "$ZPROFILE_BLOCK_BEGIN" "$ZPROFILE_BLOCK_END" "$block" || { track_error ".zprofile"; return 1; }
  else
    _normalize_zprofile_homebrew_block "$dst" "$block" || { track_error ".zprofile"; return 1; }
  fi
  track_success ".zprofile"
}

_normalize_zprofile_homebrew_block() {
  local file=$1 block=$2
  local tmp block_file
  tmp=$(mktemp) || return 1
  block_file=$(mktemp) || { rm -f "$tmp"; return 1; }
  printf "%s\n" "$block" > "$block_file" || { rm -f "$tmp" "$block_file"; return 1; }
  awk -v block_file="$block_file" '
    function flush_pending() {
      if (has_pending) {
        print pending
        has_pending = 0
      }
    }

    function print_block() {
      while ((getline line < block_file) > 0) print line
      close(block_file)
    }

    $0 == "# Homebrew" {
      pending = $0
      has_pending = 1
      next
    }

    index($0, "/opt/homebrew/bin/brew shellenv") > 0 {
      if (!inserted) {
        print_block()
        inserted = 1
      }
      has_pending = 0
      next
    }

    {
      flush_pending()
      print
    }

    END {
      flush_pending()
      if (!inserted) {
        if (NR > 0) print ""
        print_block()
      }
    }
  ' "$file" > "$tmp" || { rm -f "$tmp" "$block_file"; return 1; }
  rm -f "$block_file"
  mv "$tmp" "$file" || { rm -f "$tmp"; return 1; }
}

# Deploy the zshrc template while preserving any user-managed block.
_deploy_zshrc() {
  local src="$SCRIPT_DIR/configs/zshrc"
  local dst="$HOME/.zshrc"
  local preserved=""

  if [ -f "$dst" ] && grep -qF "$USER_BLOCK_BEGIN" "$dst"; then
    preserved=$(_extract_user_block "$dst")
  fi

  cp "$src" "$dst" || { track_error ".zshrc"; return 1; }

  if [ -n "$preserved" ]; then
    _inject_user_block "$dst" "$preserved" || { track_error ".zshrc"; return 1; }
    track_success ".zshrc (user-managed block preserved)"
  else
    track_success ".zshrc"
  fi
}

# Extract lines strictly between the markers (exclusive).
_extract_user_block() {
  local file=$1
  awk -v b="$USER_BLOCK_BEGIN" -v e="$USER_BLOCK_END" '
    $0 == b { inb = 1; next }
    $0 == e { inb = 0; next }
    inb      { print }
  ' "$file"
}

# Replace the body between markers in $file with the provided content.
_inject_user_block() {
  local file=$1 body=$2
  local block
  block=$(printf "%s\n%s\n%s" "$USER_BLOCK_BEGIN" "$body" "$USER_BLOCK_END")
  _replace_managed_block "$file" "$USER_BLOCK_BEGIN" "$USER_BLOCK_END" "$block"
}

_replace_managed_block() {
  local file=$1 begin=$2 end=$3 body=$4
  local tmp body_file
  tmp=$(mktemp) || return 1
  body_file=$(mktemp) || { rm -f "$tmp"; return 1; }
  printf "%s\n" "$body" > "$body_file" || { rm -f "$tmp" "$body_file"; return 1; }

  awk -v b="$begin" -v e="$end" -v body_file="$body_file" '
    $0 == b {
      while ((getline line < body_file) > 0) print line
      close(body_file)
      inb = 1
      next
    }
    $0 == e { inb = 0; next }
    !inb    { print }
  ' "$file" > "$tmp" || { rm -f "$tmp" "$body_file"; return 1; }
  rm -f "$body_file"
  mv "$tmp" "$file" || { rm -f "$tmp"; return 1; }
}

_configure_delta() {
  command -v delta &>/dev/null || return 0
  _config_default core.pager delta || { track_error "Git + delta"; return 1; }
  _config_default interactive.diffFilter "delta --color-only" || { track_error "Git + delta"; return 1; }
  _config_default delta.navigate true || { track_error "Git + delta"; return 1; }
  _config_default delta.side-by-side true || { track_error "Git + delta"; return 1; }
  _config_default delta.syntax-theme "Catppuccin Mocha" || { track_error "Git + delta"; return 1; }
  track_success "Git + delta"
}

# difftastic is registered as an on-demand difftool rather than as core.pager.
# It does structural (syntax-aware) diffs, which complements delta instead of
# replacing it — and its output is not machine-parseable, so making it the
# default diff would break anything that reads git's output. `git dft` opts in.
_configure_difftastic() {
  command -v difft &>/dev/null || return 0
  # Single quotes are required: git expands $LOCAL/$REMOTE when it runs the
  # difftool, so they must reach the config file unexpanded.
  # shellcheck disable=SC2016
  _config_default difftool.difftastic.cmd 'difft "$LOCAL" "$REMOTE"' || { track_error "Git + difftastic"; return 1; }
  _config_default difftool.prompt false || { track_error "Git + difftastic"; return 1; }
  _config_default alias.dft 'difftool --tool difftastic' || { track_error "Git + difftastic"; return 1; }
  track_success "Git + difftastic"
}

_config_default() {
  local key=$1 value=$2
  if ! git config --global "$key" &>/dev/null; then
    git config --global "$key" "$value"
  fi
}

_configure_neovim() {
  if ! command -v nvim &>/dev/null; then
    return 0
  fi

  local nvim_dir="$HOME/.config/nvim"
  local plugin_file="$nvim_dir/lua/plugins/catppuccin.lua"

  if [ -f "$plugin_file" ]; then
    track_success "Neovim config"
    return 0
  fi

  if [ ! -d "$nvim_dir" ]; then
    if ! run_silent git clone https://github.com/LazyVim/starter "$nvim_dir"; then
      track_error "Neovim + LazyVim"
      return 1
    fi
    rm -rf "$nvim_dir/.git" || { track_error "Neovim + LazyVim"; return 1; }
  elif ! _is_lazyvim_config "$nvim_dir"; then
    track_warn "Neovim config exists"
    return 0
  fi

  mkdir -p "$nvim_dir/lua/plugins" || { track_error "Neovim + LazyVim"; return 1; }
  _write_neovim_catppuccin_plugin "$plugin_file" || { track_error "Neovim + LazyVim"; return 1; }
  track_success "Neovim + LazyVim"
}

_write_neovim_catppuccin_plugin() {
  local plugin_file=$1
  {
    printf "%s\n" "return {"
    printf "%s\n" '  { "catppuccin/nvim", name = "catppuccin", priority = 1000 },'
    printf "%s\n" '  { "LazyVim/LazyVim", opts = { colorscheme = "catppuccin-mocha" } },'
    printf "%s\n" "}"
  } > "$plugin_file"
}

_is_lazyvim_config() {
  local nvim_dir=$1
  [ -f "$nvim_dir/lua/config/lazy.lua" ] && grep -q "LazyVim/LazyVim" "$nvim_dir/lua/config/lazy.lua" 2>/dev/null
}
