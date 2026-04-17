#!/usr/bin/env bash
# UI system (Clack-style trackline + Catppuccin Mocha palette)

# Catppuccin Mocha colors
C_MAUVE="#cba6f7"
C_BLUE="#89b4fa"
C_GREEN="#a6e3a1"
C_RED="#f38ba8"
C_YELLOW="#f9e2af"
C_PEACH="#fab387"
C_TEXT="#cdd6f4"
C_SUBTEXT="#a6adc8"
C_SURFACE="#313244"
C_BASE="#1e1e2e"
C_CRUST="#11111b"
C_LAVENDER="#b4befe"
C_PINK="#f5c2e7"
C_TEAL="#94e2d5"

# Gradient ASCII logo
show_logo() {
  # Catppuccin gradient (mauve → blue → teal)
  local colors=("$C_MAUVE" "$C_MAUVE" "$C_LAVENDER" "$C_BLUE" "$C_BLUE" "$C_TEAL")
  local lines=(
    '  ███╗   ███╗ █████╗  ██████╗   ██████╗ ███████╗██╗   ██╗'
    '  ████╗ ████║██╔══██╗██╔════╝   ██╔══██╗██╔════╝██║   ██║'
    '  ██╔████╔██║███████║██║        ██║  ██║█████╗  ██║   ██║'
    '  ██║╚██╔╝██║██╔══██║██║        ██║  ██║██╔══╝  ╚██╗ ██╔╝'
    '  ██║ ╚═╝ ██║██║  ██║╚██████╗   ██████╔╝███████╗ ╚████╔╝ '
    '  ╚═╝     ╚═╝╚═╝  ╚═╝ ╚═════╝   ╚═════╝ ╚══════╝  ╚═══╝ '
  )
  echo ""
  for i in "${!lines[@]}"; do
    gum style --foreground "${colors[$i]}" "${lines[$i]}"
  done
  gum style --foreground "$C_SUBTEXT" --faint --italic "                          2026 Edition"
  echo ""
}

# Clack-style trackline
# Symbols: ◆ active, ◇ done, │ connector, ■ end

track_bar() {
  gum style --foreground "$C_SURFACE" "  │"
}

track_intro() {
  gum style --foreground "$C_MAUVE" --bold "  ◆  $1"
  track_bar
}

track_step_header() {
  local step=$1 total=$2 title=$3
  gum style --foreground "$C_BLUE" --bold "  ◆  Step $step/$total — $title"
}

track_section() {
  echo ""
  gum style --foreground "$C_PEACH" --bold "  ◆  $1"
  track_bar
}

track_success() {
  gum style --foreground "$C_GREEN" "  │  ✓ $1"
}

track_warn() {
  gum style --foreground "$C_YELLOW" "  │  ~ $1"
}

track_error() {
  gum style --foreground "$C_RED" "  │  ✗ $1"
}

track_info() {
  gum style --foreground "$C_SUBTEXT" "  │  $1"
}

track_pending() {
  gum style --foreground "$C_SURFACE" "  │  ○ $1"
}

track_active() {
  gum style --foreground "$C_MAUVE" "  │  ● $1"
}

track_done() {
  echo ""
  gum style --foreground "$C_GREEN" --bold "  ■  $1"
  echo ""
}

track_cancel() {
  echo ""
  gum style --foreground "$C_YELLOW" --bold "  ■  $1"
  echo ""
}

# Backward-compatible aliases
ui_header() {
  echo ""
  gum style --foreground "$C_MAUVE" --bold "  ◆  $1"
  track_bar
}

ui_step() {
  track_bar
  track_step_header "$1" "$2" "$3"
  track_bar
}

ui_success()  { track_success "$1"; }
ui_warn()     { track_warn "$1"; }
ui_error()    { track_error "$1"; }
ui_info()     { track_info "$1"; }
ui_divider()  { track_bar; }

ui_choose() {
  local header=$1; shift
  gum choose --no-limit \
    --header "  │  $header" \
    --header.foreground "$C_SUBTEXT" \
    --cursor.foreground "$C_MAUVE" \
    --selected.foreground "$C_GREEN" \
    --selected-prefix "  │  ✓ " \
    --unselected-prefix "  │    " \
    --cursor "  │  ✓ " \
    --height 20 \
    "$@"
}

ui_choose_one() {
  local header=$1; shift
  gum choose \
    --header "  │  $header" \
    --header.foreground "$C_SUBTEXT" \
    --cursor.foreground "$C_MAUVE" \
    --selected.foreground "$C_GREEN" \
    --cursor " ● " \
    "$@"
}

ui_confirm() {
  gum confirm \
    --prompt.foreground "$C_TEXT" \
    --selected.background "$C_MAUVE" \
    --unselected.background "$C_SURFACE" \
    "$1"
}

ui_spin() {
  local title=$1; shift
  gum spin \
    --spinner dot \
    --spinner.foreground "$C_MAUVE" \
    --title "  │  ● $title" \
    --title.foreground "$C_TEXT" \
    -- "$@"
}

ui_summary_box() {
  gum style \
    --border rounded \
    --border-foreground "$C_BLUE" \
    --padding "1 3" \
    --margin "0 4" \
    --foreground "$C_TEXT" \
    "$@"
}

ui_error_action() {
  local pkg=$1
  # Side effects (error banner) go to stderr so the caller's
  # `action=$(ui_error_action "$pkg")` captures only the user's choice.
  track_error "Failed: $pkg" 1>&2
  gum choose --header "  │  What to do?" \
    --header.foreground "$C_YELLOW" \
    --cursor.foreground "$C_MAUVE" \
    --cursor " ● " \
    "Retry" "Skip" "Abort"
}
