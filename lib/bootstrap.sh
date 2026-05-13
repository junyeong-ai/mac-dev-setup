#!/usr/bin/env bash
# Bootstrap — fresh-Mac plumbing (system check, Homebrew, gum).
#
# This is the only layer that runs before the gum-based install UI exists,
# so it speaks plain text via lib/log.sh (say_*, run_*). The install layer
# (installers.sh + orchestrator.sh) takes over once gum is on PATH.
#
# Public API:
#
#   run_bootstrap [install]    Run the full bootstrap chain. Pass "install"
#                              to also refresh package metadata and install
#                              gum. Exits non-zero on any unrecoverable
#                              failure; otherwise returns 0.
#
#   ensure_supported_system    Verify Apple Silicon macOS. Returns 0/1.
#   activate_homebrew          Load /opt/homebrew into PATH. Returns 0/1.
#   activate_mise              Load mise shims into PATH. Returns 0/1.
#
# Each `bootstrap_*` primitive returns 0/non-zero. None of them call `exit`
# — `run_bootstrap` is the single funnel that decides when to terminate.
# Each is idempotent: re-running setup short-circuits already-completed
# steps via cheap state probes.

HOMEBREW_BREW_PATH="/opt/homebrew/bin/brew"
# Overridable for corporate mirrors or pinned commit-SHA installs:
#   HOMEBREW_INSTALLER_URL="https://raw.githubusercontent.com/Homebrew/install/<sha>/install.sh" bash setup.sh
HOMEBREW_INSTALLER_URL="${HOMEBREW_INSTALLER_URL:-https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh}"

# ── System checks ──

ensure_supported_system() {
  if [ "$(uname -s)" != "Darwin" ]; then
    say_error "macOS required (detected: $(uname -s))."
    return 1
  fi
  if [ "$(uname -m)" != "arm64" ]; then
    say_error "Apple Silicon required (detected: $(uname -m))."
    return 1
  fi
  return 0
}

# ── PATH activation (no installation) ──

activate_homebrew() {
  if [ -x "$HOMEBREW_BREW_PATH" ]; then
    eval "$("$HOMEBREW_BREW_PATH" shellenv)"
    return 0
  fi
  return 1
}

activate_mise() {
  if command -v mise >/dev/null 2>&1; then
    local activation
    activation=$(mise activate --shims --quiet bash 2>/dev/null) || return 1
    eval "$activation" || return 1
    return 0
  fi
  return 1
}

# ── Homebrew pre-flight checks ──

# Refuse to run the Homebrew installer under sudo. Homebrew's own installer
# does this check, but failing here is cleaner: the user sees one message
# instead of an opaque half-second abort from within the installer.
_reject_root_invocation() {
  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    say_error "Do not run setup.sh with sudo or as root."
    say_detail "Homebrew refuses to install when invoked as root."
    say_detail "Re-run as your regular user: bash setup.sh"
    return 1
  fi
  return 0
}

# Warn (don't fail) if the user is not in the admin group. The Homebrew
# installer needs sudo to chown /opt/homebrew; a non-admin will be rejected
# by sudo and the installer aborts. Warning early lets the user understand
# the eventual failure instead of guessing.
_warn_if_not_admin() {
  if id -Gn "$USER" 2>/dev/null | tr ' ' '\n' | grep -qx admin; then
    return 0
  fi
  say_warn "User '$USER' is not in the 'admin' group."
  say_detail "Homebrew's installer needs sudo to create /opt/homebrew."
  say_detail "If this is a managed/MDM Mac, ask your administrator first,"
  say_detail "or install Homebrew manually from https://brew.sh."
}

# Verify the installer URL is reachable before we start a user-visible
# install. Better to abort with a clear network error than to hand the user
# a half-installed Homebrew.
_check_installer_reachable() {
  if curl --fail --silent --show-error --location \
       --max-time 10 --head "$HOMEBREW_INSTALLER_URL" >/dev/null 2>&1; then
    return 0
  fi
  say_error "Cannot reach the Homebrew installer at $HOMEBREW_INSTALLER_URL."
  say_detail "Check your network connection (proxy, VPN, DNS) and try again."
  return 1
}

# ── bootstrap_* primitives ──

bootstrap_homebrew() {
  if activate_homebrew; then
    say_debug "Homebrew already installed at $HOMEBREW_BREW_PATH"
    return 0
  fi

  _reject_root_invocation || return 1
  _warn_if_not_admin
  _check_installer_reachable || return 1

  say_step "Installing Homebrew (first-time setup)"
  say_info "The Homebrew installer will:"
  say_info "  1. prompt for your macOS password (sudo) — this is normal,"
  say_info "  2. ask you to press RETURN to confirm the installation,"
  say_info "  3. download Xcode Command Line Tools if not already present."
  say_info "Everything Homebrew prints below comes directly from its installer."
  printf "\n"

  local installer
  installer=$(mktemp -t mac-dev-setup-brew-installer) || {
    say_error "Could not create a temporary file for the installer."
    return 1
  }

  if ! curl --fail --silent --show-error --location \
       --output "$installer" "$HOMEBREW_INSTALLER_URL"; then
    say_error "Failed to download the Homebrew installer."
    rm -f "$installer"
    return 1
  fi

  if [ ! -s "$installer" ]; then
    say_error "Downloaded installer is empty — refusing to run."
    rm -f "$installer"
    return 1
  fi

  # `env VAR=value` is the only reliable way to pass an environment variable
  # into a child of a runner function: bash discards variable prefixes given
  # to function calls before they reach the wrapped command.
  local rc=0
  if [ "${CI_MODE:-}" = "true" ]; then
    run_with_tee env NONINTERACTIVE=1 /bin/bash "$installer" || rc=$?
  else
    run_interactive /bin/bash "$installer" || rc=$?
  fi
  rm -f "$installer"

  if [ "$rc" -ne 0 ]; then
    say_error "Homebrew installer exited with code $rc."
    say_detail ""
    say_detail "Common causes on a fresh Mac:"
    say_detail "  • wrong macOS password or sudo prompt cancelled"
    say_detail "  • account not in the 'admin' group (managed device)"
    say_detail "  • answered 'Press RETURN to continue' with another key"
    say_detail "  • network interruption during Xcode CLT download"
    say_detail "  • running setup.sh with sudo (Homebrew refuses)"
    say_detail ""
    say_detail "Resolve the issue and re-run setup.sh, or install manually:"
    say_detail "  https://brew.sh"
    say_detail "Full log: $LOG_FILE"
    return 1
  fi

  if ! activate_homebrew; then
    say_error "Installer reported success but $HOMEBREW_BREW_PATH is missing."
    say_detail "Inspect /opt/homebrew/ and Homebrew's troubleshooting guide:"
    say_detail "  https://docs.brew.sh/Troubleshooting"
    return 1
  fi

  say_info "Homebrew ready ($(brew --version 2>/dev/null | head -1))"
  return 0
}

bootstrap_homebrew_metadata() {
  say_step "Refreshing Homebrew package metadata"
  if ! run_with_tee brew update; then
    say_error "brew update failed (see output above)."
    return 1
  fi
  return 0
}

bootstrap_gum() {
  if command -v gum >/dev/null 2>&1; then
    say_debug "gum already installed"
    return 0
  fi
  say_step "Installing gum (UI toolkit)"
  if ! run_with_tee brew install gum; then
    say_error "Failed to install gum (see output above)."
    return 1
  fi
  return 0
}

# ── Public entry ──

# Run the bootstrap chain. Pass "install" (the default) to also refresh
# Homebrew metadata and install gum so the rest of setup can render its UI.
# Pass any other value for a minimal bootstrap (Homebrew only).
run_bootstrap() {
  local stage=${1:-install}

  ensure_supported_system || exit 1
  bootstrap_homebrew || exit 1

  if [ "$stage" = "install" ]; then
    bootstrap_homebrew_metadata || exit 1
    bootstrap_gum || exit 1
  fi
}
