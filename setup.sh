#!/usr/bin/env bash
# Mac Dev Setup — entry point.
#
# Usage:
#   ./setup.sh                Interactive install (default)
#   ./setup.sh --ci           Non-interactive install of essential+recommended
#   ./setup.sh doctor         Diagnose current environment
#   ./setup.sh --help         Show this help
#
# Bash 3.2 compatible. Library load order satisfies dependencies:
#   log          — output channels & command runners (zero deps)
#   ui           — gum-based tracking UI (used after bootstrap installs gum)
#   registry     — declarative data model (validated after installers.sh loads)
#   bootstrap    — system check + Homebrew + gum (uses log)
#   backup       — dotfile backup
#   installers   — install_* primitives + dispatch
#   configs      — config file deployment
#   orchestrator — install flow (selection UI + execution)
#   doctor       — diagnostics

# ── Preconditions ──

if [ "${BASH_VERSINFO[0]:-0}" -lt 3 ]; then
  echo "Error: Bash 3+ required. Current: ${BASH_VERSION:-unknown}" >&2
  exit 1
fi

export _ZO_DOCTOR=0
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for lib in log ui registry bootstrap backup installers configs orchestrator doctor; do
  # shellcheck disable=SC1090
  source "$SCRIPT_DIR/lib/${lib}.sh"
done

# Trap is installed after sourcing so _handle_sigint (from log.sh) is
# guaranteed to be defined when SIGINT arrives. _handle_sigint prints
# "Interrupted." only from the top-level shell so kill -INT 0 — which
# _abort_if_interrupted uses to propagate Ctrl+C out of command-substitution
# subshells — does not produce one message per subshell.
trap '_handle_sigint' INT

# Validate registry dispatch links now that installers.sh is loaded.
# Fails fast with a clear message on any registry typo.
validate_registry

# ── CLI ──

print_help() {
  cat << 'HELP'
Usage: setup.sh [COMMAND]

Commands:
  (default)       Interactive install via selection UI
  install         Alias for default
  --ci            Non-interactive install (essential + recommended only)
  doctor          Diagnose current environment
  -h, --help      Show this help

Environment:
  CI_MODE=true              Equivalent to --ci
  NO_COLOR=1                Disable ANSI colors in plain-text output
  MAC_DEV_SETUP_DEBUG=1     Show debug messages
  HOMEBREW_INSTALLER_URL    Override the Homebrew installer source (mirror, pinned SHA)

See also: README.md
HELP
}

main() {
  case "${1:-}" in
    -h|--help) print_help; exit 0 ;;
  esac

  case "${1:-}" in
    doctor|--doctor)
      # Doctor is read-only and deliberately does not call log_init so a
      # previous install's log stays intact for post-mortem inspection.
      ensure_supported_system || exit 1
      activate_homebrew || true
      activate_mise || true
      run_doctor
      ;;
    --ci)
      export CI_MODE=true
      log_init
      run_bootstrap install
      run_install
      ;;
    ""|install)
      log_init
      run_bootstrap install
      run_install
      ;;
    *)
      echo "Unknown command: $1" >&2
      print_help >&2
      exit 2
      ;;
  esac
}

main "$@"
