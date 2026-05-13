#!/usr/bin/env bash
# Installers — registry dispatch + install primitives.
#
# Architecture:
#   install_key <key>
#     ├─ looks up INSTALLER + ARGS in registry
#     ├─ calls install_<INSTALLER> "$key" <args...>
#     └─ on non-zero return, iterative retry/skip/abort prompt
#                            (interactive only; fail in CI/non-TTY)
#
# Naming convention:
#   install_*       installer primitive (public; called by dispatch)
#   install_macos_* dedicated per-key installer for a macOS setting
#   _*              file-private helper
#
# Contract for every install_* primitive:
#   1. Be idempotent — short-circuit with track_success on already-installed.
#   2. Emit track_success on success, track_error on failure.
#   3. Return 0 on success, non-zero on failure. No retry logic here;
#      install_key handles recovery uniformly.
#   4. Capture command output via run_silent so each shell-out leaves a
#      structured CMD/EXIT pair in the log.

# ── Dispatch ──
#
# Outcome accounting: install_key isolates failures per key so one bad
# install never cascades into the rest. Failed and user-skipped keys are
# appended to _INSTALL_FAILED_KEYS / _INSTALL_SKIPPED_KEYS (newline-
# separated, bash 3.2-safe). The orchestrator resets both at the start of
# every run and reads them in the footer so the user can see exactly what
# fell out — and re-run setup.sh to retry only the misses.
_INSTALL_FAILED_KEYS=""
_INSTALL_SKIPPED_KEYS=""

# Install a single key. Looks up installer + args, invokes the primitive,
# and on failure either prompts (interactive) or records-and-continues
# (CI / non-TTY). The only paths that exit the script are user-chosen
# Abort and an unexpected prompt value — everything else returns 0 so the
# orchestrator keeps installing the rest of the selection.
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

    # Non-interactive: record the failure and continue with the next item.
    # A failed font download or one unreachable cask should not strand the
    # remaining tools — the user will see the failed list in the footer
    # and re-run setup.sh to retry just the misses.
    if [ ! -t 0 ] || [ "${CI_MODE:-}" = "true" ]; then
      track_error "Failed $short — continuing with remaining items"
      _INSTALL_FAILED_KEYS="${_INSTALL_FAILED_KEYS}${key}"$'\n'
      return 0
    fi

    local action
    action=$(ui_error_action "$short")
    case "$action" in
      Retry)
        continue
        ;;
      Skip)
        track_warn "Skipped $short"
        _INSTALL_SKIPPED_KEYS="${_INSTALL_SKIPPED_KEYS}${key}"$'\n'
        return 0
        ;;
      Abort)
        track_error "Aborted"
        exit 1
        ;;
      *)
        # Empty / unrecognised action means the prompt itself misbehaved
        # (gum died, terminal lost, …). Abort instead of silently
        # advancing — the previous "skip on unknown" behaviour was how
        # partial installs ended up reporting "Setup Complete!".
        track_error "Prompt returned unexpected value '$action' — aborting"
        exit 1
        ;;
    esac
  done
}

# ── Primitives ──

# Brew formula: install_brew <key> <pkg>
install_brew() {
  local key=$1 pkg=$2
  local label short action
  label=$(reg_field "$key" label)
  short="${label%% (*}"

  if reg_check_passes "$key"; then
    track_success "$short"
    return 0
  fi

  if brew list --formula "$pkg" &>/dev/null; then
    action=reinstall
  else
    action=install
  fi

  track_active "$short..."
  if run_silent brew "$action" "$pkg"; then
    _clear_active_line
    _finish_registry_key "$key" "$short"
    return $?
  fi
  _clear_active_line
  track_error "$short"
  return 1
}

# Brew cask: install_brew_cask <key> <cask>
# Registry CHECK owns the app/font health test; brew ownership decides
# whether repair uses install or reinstall.
install_brew_cask() {
  local key=$1 cask=$2
  local label short action
  label=$(reg_field "$key" label)
  short="${label%% (*}"

  if reg_check_passes "$key"; then
    track_success "$short"
    return 0
  fi

  if brew list --cask "$cask" &>/dev/null; then
    action=reinstall
  else
    action=install
  fi

  track_active "$short..."
  if run_silent brew "$action" --cask "$cask"; then
    _clear_active_line
    _finish_registry_key "$key" "$short"
    return $?
  fi
  _clear_active_line
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
    if run_silent brew install mise; then
      _clear_active_line
      track_success "mise (bootstrap)"
    else
      _clear_active_line
      track_error "mise bootstrap failed — skipping $short"
      return 1
    fi
  fi

  activate_mise || true

  if reg_check_passes "$key"; then
    track_success "$short"
    return 0
  fi

  track_active "$short (via mise)..."
  # Single quotes are intentional: $(...) and $1 are evaluated by the spawned
  # bash with mise activation just applied. Passing $spec as a positional arg
  # (after the `_` $0 placeholder) keeps it out of the shell parser entirely.
  # shellcheck disable=SC2016
  if run_silent bash -c 'eval "$(mise activate --shims --quiet bash)" && mise use -g "$1"' _ "$spec"; then
    activate_mise || true
    _clear_active_line
    _finish_registry_key "$key" "$short (via mise)"
    return $?
  fi
  _clear_active_line
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

  if reg_check_passes "$key"; then
    track_success "$short"
    return 0
  fi

  if ! command -v npm &>/dev/null; then
    track_warn "npm not found — bootstrapping Node.js via mise"
    install_mise node node@lts || return 1
    activate_mise || true
  fi

  if ! command -v npm &>/dev/null; then
    track_error "$short — npm still unavailable after bootstrap"
    return 1
  fi

  track_active "$short (npm -g)..."
  if run_silent npm install -g "$pkg"; then
    _clear_active_line
    _finish_registry_key "$key" "$short"
    return $?
  fi
  _clear_active_line
  track_error "$short"
  return 1
}

# GitHub-hosted bootstrap script: install_github_script <key> [VAR=value...] <repo> [-- <post-install argv...>]
#
# Runs an upstream `scripts/install.sh` exposed at:
#   https://raw.githubusercontent.com/<repo>/main/scripts/install.sh
#
# ARGS grammar (whitespace-tokenized within the registry record):
#   1. Leading `VAR=value` tokens are exported into the environment of the
#      upstream installer. They drive per-project knobs (e.g. an installer
#      that auto-launches a post-install walkthrough when run from a TTY can
#      be told to skip it via `<PROJECT>_NO_SETUP=1`).
#   2. The next token is the GitHub repo (`<owner>/<name>`).
#   3. Optional `--` separator introduces a post-install command (typically
#      `<binary> setup skill --yes`) that runs with $HOME/.local/bin on PATH
#      so the freshly installed binary is resolvable.
#
# Each upstream `install.sh` owns its release artefact contract (tarball
# layout, sha256 verification, codesign, platform detection). This installer
# stays mechanical so adding a new tool is a one-line registry record.
install_github_script() {
  local key=$1
  shift

  local -a env_vars=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      [A-Z]*=*) env_vars+=("$1"); shift ;;
      *)        break ;;
    esac
  done

  local repo=${1:-}
  [ "$#" -gt 0 ] && shift

  local -a post_install=()
  if [ "$#" -gt 0 ] && [ "$1" = "--" ]; then
    shift
    post_install=("$@")
  fi

  local label short
  label=$(reg_field "$key" label)
  short="${label%% (*}"

  if [[ ! "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
    track_error "$short — invalid repo '$repo'"
    return 1
  fi

  if reg_check_passes "$key"; then
    track_success "$short"
    return 0
  fi

  if ! command -v curl &>/dev/null; then
    track_error "$short — curl is required"
    return 1
  fi

  local url="https://raw.githubusercontent.com/${repo}/main/scripts/install.sh"

  track_active "$short (binary)..."
  if ! run_silent env "${env_vars[@]}" bash -c "curl -fsSL '$url' | bash"; then
    _clear_active_line
    track_error "$short (binary)"
    return 1
  fi
  _clear_active_line

  if [ "${#post_install[@]}" -gt 0 ]; then
    track_active "$short (skill)..."
    if ! run_silent env PATH="$HOME/.local/bin:$PATH" "${post_install[@]}"; then
      _clear_active_line
      track_error "$short (skill)"
      return 1
    fi
    _clear_active_line
  fi

  _finish_registry_key "$key" "$short"
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
  mkdir -p "$HOME/.local/share/zinit" || { _clear_active_line; track_error "$short"; return 1; }
  if run_silent git clone https://github.com/zdharma-continuum/zinit "$target"; then
    _clear_active_line
    _finish_registry_key "$key" "$short"
    return $?
  fi
  _clear_active_line
  track_error "$short"
  return 1
}

install_git_defaults() {
  local key=$1
  _git_config_default init.defaultBranch main || return 1
  _git_config_default pull.rebase true || return 1
  _git_config_default fetch.prune true || return 1
  _git_config_default rerere.enabled true || return 1
  _finish_registry_key "$key" "$(reg_field "$key" label)"
}

install_git_lfs() {
  local key=$1
  local label short action
  label=$(reg_field "$key" label)
  short="${label%% (*}"

  if reg_check_passes "$key"; then
    track_success "$short"
    return 0
  fi

  if ! brew list --formula git-lfs &>/dev/null || ! command -v git-lfs &>/dev/null; then
    if brew list --formula git-lfs &>/dev/null; then
      action=reinstall
    else
      action=install
    fi

    track_active "$short..."
    if run_silent brew "$action" git-lfs; then
      _clear_active_line
      track_success "$short"
    else
      _clear_active_line
      track_error "$short"
      return 1
    fi
  fi

  track_active "$short setup..."
  if run_silent git lfs install --skip-repo; then
    _clear_active_line
    _finish_registry_key "$key" "$short setup"
    return $?
  fi
  _clear_active_line
  track_error "$short setup"
  return 1
}

# ── macOS settings (one function per key) ──
# Each reads its label from the registry so a label change in registry.sh
# automatically propagates to success messages.

install_macos_keyrepeat() {
  local key=$1
  defaults write NSGlobalDomain KeyRepeat -int 2 || return 1
  defaults write NSGlobalDomain InitialKeyRepeat -int 15 || return 1
  _finish_macos_setting "$key"
}

install_macos_finder_hidden() {
  local key=$1
  defaults write com.apple.finder AppleShowAllFiles YES || return 1
  _macos_needs_finder_restart=true
  _finish_macos_setting "$key"
}

install_macos_finder_pathbar() {
  local key=$1
  defaults write com.apple.finder ShowPathbar -bool true || return 1
  _macos_needs_finder_restart=true
  _finish_macos_setting "$key"
}

install_macos_dock() {
  local key=$1
  defaults write com.apple.dock autohide -bool true || return 1
  defaults write com.apple.dock autohide-delay -float 0 || return 1
  defaults write com.apple.dock autohide-time-modifier -float 0.3 || return 1
  _macos_needs_dock_restart=true
  _finish_macos_setting "$key"
}

install_macos_mission_control() {
  local key=$1
  defaults write com.apple.dock expose-animation-duration -float 0.1 || return 1
  _macos_needs_dock_restart=true
  _finish_macos_setting "$key"
}

install_macos_screenshots() {
  local key=$1
  mkdir -p "$HOME/Screenshots" || return 1
  defaults write com.apple.screencapture location "$HOME/Screenshots" || return 1
  _finish_macos_setting "$key"
}

install_macos_hushlogin() {
  local key=$1
  touch "$HOME/.hushlogin" || return 1
  _finish_macos_setting "$key"
}

# ── Private helpers ──

_clear_active_line() {
  [ -t 1 ] && printf "\033[1A\033[2K"
}

_git_config_default() {
  local key=$1 value=$2
  if ! git config --global "$key" &>/dev/null; then
    git config --global "$key" "$value"
  fi
}

_finish_registry_key() {
  local key=$1 label=$2
  if reg_check_passes "$key"; then
    track_success "$label"
    return 0
  fi
  track_error "$label"
  return 1
}

_finish_macos_setting() {
  local key=$1 label
  label=$(reg_field "$key" label)
  _finish_registry_key "$key" "$label"
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
