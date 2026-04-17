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
#   ui         — used by everyone for output
#   registry   — data model (validated after installers.sh loads)
#   backup     — dotfile backup
#   installers — bootstrap + dispatch (depends on registry + ui)
#   configs    — config file deployment (depends on ui)
#   orchestrator — install flow (depends on all above)
#   doctor     — diagnostics (depends on registry + ui)

# ── Preconditions ──

if [ "${BASH_VERSINFO[0]:-0}" -lt 3 ]; then
  echo "Error: Bash 3+ required. Current: ${BASH_VERSION:-unknown}" >&2
  exit 1
fi

export _ZO_DOCTOR=0
set -eo pipefail

# Clean message on Ctrl+C instead of a bare abort trace. Exit 130 is the
# standard "terminated by SIGINT" code.
trap 'echo ""; echo "Interrupted." >&2; exit 130' INT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$HOME/.mac-dev-setup.log"
: > "$LOG_FILE"

for lib in ui registry backup installers configs orchestrator doctor; do
  # shellcheck disable=SC1090
  source "$SCRIPT_DIR/lib/${lib}.sh"
done

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
  CI_MODE=true    Equivalent to --ci

See also: README.md
HELP
}

main() {
  # Pre-subcommand handling (no bootstrap needed for --help)
  case "${1:-}" in
    -h|--help) print_help; exit 0 ;;
  esac

  # Bootstrap is shared by all subcommands that interact with UI.
  run_bootstrap

  case "${1:-}" in
    doctor|--doctor)
      run_doctor
      ;;
    --ci)
      CI_MODE=true
      run_install
      ;;
    ""|install)
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
