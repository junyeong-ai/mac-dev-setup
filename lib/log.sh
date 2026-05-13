#!/usr/bin/env bash
# Logging & command-output strategy.
#
# This module is loaded first and depends on nothing else. It provides the
# vocabulary every other layer uses to talk to the user and to the log file.
#
# Output channels (plain-text, work before gum is installed):
#
#   say_step    bold step header                       → stdout + log
#   say_info    progress / context                     → stdout + log
#   say_detail  indented elaboration (no marker)       → stderr + log
#   say_warn    non-fatal issue                        → stderr + log
#   say_error   fatal issue                            → stderr + log
#   say_debug   visible only when MAC_DEV_SETUP_DEBUG=1
#
# Command runners (encode the *intent* behind a shell-out — pick the one
# that matches what the user should see):
#
#   run_interactive <cmd...>   No redirection. The child inherits the parent's
#                              tty so prompts (sudo password, "Press RETURN")
#                              are visible and answerable. Use for first-time
#                              Homebrew install or any command that owns the
#                              terminal.
#
#   run_with_tee <cmd...>      Stream stdout+stderr to the user AND append to
#                              the log file. Use for long operations where
#                              progress is meaningful and the user should see
#                              what's happening (brew update, brew install).
#
#   run_silent <cmd...>        Capture stdout+stderr to the log file and
#                              close stdin from /dev/null so an accidental
#                              prompt fails fast instead of hanging.
#                              Use for non-interactive commands wrapped
#                              inside a track_* UI step.
#
# Each runner returns the wrapped command's exit code and emits matching
# CMD / EXIT records to the log. They are written defensively so that bare
# `run_foo cmd` calls do not trip the caller's `set -e` before the EXIT
# record is appended.
#
# Honors:
#   NO_COLOR=1                 disable ANSI color in say_*
#   MAC_DEV_SETUP_DEBUG=1      show say_debug output on the terminal

LOG_FILE="${LOG_FILE:-${HOME:-/tmp}/.mac-dev-setup.log}"

# ── ANSI colour setup ──

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  _LOG_C_STEP=$'\033[1;35m'
  _LOG_C_INFO=$'\033[0;37m'
  _LOG_C_WARN=$'\033[1;33m'
  _LOG_C_ERROR=$'\033[1;31m'
  _LOG_C_DIM=$'\033[2m'
  _LOG_C_RESET=$'\033[0m'
else
  _LOG_C_STEP=""
  _LOG_C_INFO=""
  _LOG_C_WARN=""
  _LOG_C_ERROR=""
  _LOG_C_DIM=""
  _LOG_C_RESET=""
fi

# ── Log file lifecycle ──

# Truncate the log and write a header identifying this run. Call once per
# top-level invocation that intends to write to the log. Returns 0 even if
# the log file cannot be opened — logging is best-effort, the user's
# session must keep working.
log_init() {
  if ! : > "$LOG_FILE" 2>/dev/null; then
    printf "warning: cannot write to %s — proceeding without a log file\n" \
      "$LOG_FILE" >&2
    return 0
  fi
  {
    printf -- "─── mac-dev-setup ───\n"
    printf "started : %s\n" "$(date '+%Y-%m-%d %H:%M:%S %z')"
    printf "user    : %s\n" "${USER:-unknown}"
    printf "home    : %s\n" "${HOME:-unknown}"
    printf "shell   : %s\n" "${SHELL:-unknown}"
    printf "uname   : %s %s\n" "$(uname -s)" "$(uname -m)"
    printf "macos   : %s\n" "$(sw_vers -productVersion 2>/dev/null || printf 'unknown')"
    printf "ci_mode : %s\n" "${CI_MODE:-false}"
    printf -- "─────────────────────\n\n"
  } >> "$LOG_FILE" 2>/dev/null || true
}

log_path() { printf "%s\n" "$LOG_FILE"; }

# Append a single structured record to the log. Best-effort; failures are
# swallowed so logging cannot break the surrounding flow.
_log_record() {
  local level=$1; shift
  printf "[%s] %-6s %s\n" "$(date '+%H:%M:%S')" "$level" "$*" \
    >> "$LOG_FILE" 2>/dev/null || true
}

# ── say_* channels ──

say_step() {
  printf "\n%s▶  %s%s\n" "$_LOG_C_STEP" "$*" "$_LOG_C_RESET"
  _log_record STEP "$*"
}

say_info() {
  printf "   %s%s%s\n" "$_LOG_C_INFO" "$*" "$_LOG_C_RESET"
  _log_record INFO "$*"
}

# Indented elaboration line — used to add detail after a say_step / say_warn /
# say_error without repeating the leading symbol. Goes to stderr (most often
# follows an error or warning).
say_detail() {
  printf "%s   %s%s\n" "$_LOG_C_DIM" "$*" "$_LOG_C_RESET" >&2
  _log_record DETAIL "$*"
}

say_warn() {
  printf "%s!  %s%s\n" "$_LOG_C_WARN" "$*" "$_LOG_C_RESET" >&2
  _log_record WARN "$*"
}

say_error() {
  printf "%s✗  %s%s\n" "$_LOG_C_ERROR" "$*" "$_LOG_C_RESET" >&2
  _log_record ERROR "$*"
}

say_debug() {
  if [ "${MAC_DEV_SETUP_DEBUG:-}" = "1" ]; then
    printf "%s   [debug] %s%s\n" "$_LOG_C_DIM" "$*" "$_LOG_C_RESET"
  fi
  _log_record DEBUG "$*"
}

# ── Command runners ──
#
# Implementation note: `cmd || rc=$?` is the canonical idiom for suppressing
# `set -e` around a single command while still capturing the exit code. The
# runners use it (and a subshell for the tee variant) so they remain safe to
# call in both bare and conditional contexts.

run_interactive() {
  _log_record CMD "(interactive) $*"
  local rc=0
  "$@" || rc=$?
  _log_record EXIT "(interactive) rc=$rc"
  return $rc
}

run_with_tee() {
  _log_record CMD "(tee) $*"
  local rc=0
  # The subshell disables set -e/pipefail so a failing command does not
  # short-circuit the pipeline before we record PIPESTATUS[0], which is the
  # only reliable source of the original command's exit code.
  (
    set +e +o pipefail
    "$@" 2>&1 | tee -a "$LOG_FILE"
    exit "${PIPESTATUS[0]}"
  ) || rc=$?
  _log_record EXIT "(tee) rc=$rc"
  return $rc
}

run_silent() {
  _log_record CMD "(silent) $*"
  local rc=0
  "$@" </dev/null >> "$LOG_FILE" 2>&1 || rc=$?
  _log_record EXIT "(silent) rc=$rc"
  return $rc
}
