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
C_LAVENDER="#b4befe"
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

ui_step() {
  track_bar
  track_step_header "$1" "$2" "$3"
  track_bar
}

ui_confirm() {
  gum confirm \
    --prompt.foreground "$C_TEXT" \
    --selected.background "$C_MAUVE" \
    --unselected.background "$C_SURFACE" \
    "$1"
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
