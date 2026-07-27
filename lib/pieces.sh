#!/usr/bin/env bash
#
# lib/pieces.sh
#
# Description:
#   Tetromino definitions for rowhammer: the seven piece types with their
#   four rotation states, the configurable color schemes (symbolic color
#   names with a basic 8/16-color ANSI and an extended xterm 256-color
#   meaning, mapped to pieces and gold/silver squares by the selectable
#   theme), the 7-bag randomizer (every piece type appears exactly once
#   per bag of seven) and the upcoming-piece queue that feeds the HUD
#   preview. In debug mode every bag refill is logged with the shuffled
#   piece order.
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.5.0  (2026-07-26)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/pieces.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# Piece shapes follow the SRS (Super Rotation System) cell layout: for each
# piece type (I O T S Z J L) and rotation state (0-3, clockwise) the four
# occupied cells are listed as "x,y" offsets inside a 4x4 bounding box.
declare -A PIECE_SHAPE=(
    [I0]="0,1 1,1 2,1 3,1"  [I1]="2,0 2,1 2,2 2,3"
    [I2]="0,2 1,2 2,2 3,2"  [I3]="1,0 1,1 1,2 1,3"
    [O0]="1,0 2,0 1,1 2,1"  [O1]="1,0 2,0 1,1 2,1"
    [O2]="1,0 2,0 1,1 2,1"  [O3]="1,0 2,0 1,1 2,1"
    [T0]="1,0 0,1 1,1 2,1"  [T1]="1,0 1,1 2,1 1,2"
    [T2]="0,1 1,1 2,1 1,2"  [T3]="1,0 0,1 1,1 1,2"
    [S0]="1,0 2,0 0,1 1,1"  [S1]="1,0 1,1 2,1 2,2"
    [S2]="1,1 2,1 0,2 1,2"  [S3]="0,0 0,1 1,1 1,2"
    [Z0]="0,0 1,0 1,1 2,1"  [Z1]="2,0 1,1 2,1 1,2"
    [Z2]="0,1 1,1 1,2 2,2"  [Z3]="1,0 0,1 1,1 0,2"
    [J0]="0,0 0,1 1,1 2,1"  [J1]="1,0 2,0 1,1 1,2"
    [J2]="0,1 1,1 2,1 2,2"  [J3]="1,0 1,1 0,2 1,2"
    [L0]="2,0 0,1 1,1 2,1"  [L1]="1,0 1,1 1,2 2,2"
    [L2]="0,1 1,1 2,1 0,2"  [L3]="0,0 1,0 1,1 1,2"
)

# Configurable colors (since 0.19.0): instead of hard-wiring one palette
# per piece, colors are addressed by symbolic name (cyan, orange, ...)
# and a color scheme ("theme") maps every piece type and the gold/silver
# squares to such a name. This solves the two-palette problem cleanly: a
# raw SGR number only works in one mode, whereas a name carries both a
# basic (8/16-color ANSI) and an extended (xterm 256-color) meaning. The
# renderer (render_colors_init, lib/render.sh) turns the active theme's
# names into the final SGR sequences for the resolved COLOR_MODE.

# Basic color mode: ANSI foreground SGR code per color name. Rendering
# draws pieces as reverse-video blocks of this foreground, and gold/silver
# squares as black text on the matching background (foreground + 10). The
# basic 8-color palette has no true orange/purple/etc.; those names fall
# back to the closest of the eight base colors.
declare -A COLOR_BASIC=(
    [cyan]="36"  [yellow]="33" [magenta]="35" [green]="32" [red]="31"
    [blue]="34"  [white]="37"  [orange]="37"  [gold]="33"  [silver]="37"
    [grey]="37"  [purple]="35" [sky]="36"     [amber]="33"
)

# Extended color mode: xterm 256-color index per color name. Rendering
# paints these as backgrounds (48;5;N) for pieces and squares, so the
# extended palette can express real orange (208), purple (129) and richer
# gold/silver tones the basic palette cannot.
declare -A COLOR_EXT=(
    [cyan]="51"  [yellow]="220" [magenta]="135" [green]="40" [red]="196"
    [blue]="33"  [white]="252"  [orange]="208"  [gold]="178" [silver]="250"
    [grey]="245" [purple]="129" [sky]="39"       [amber]="214"
)

# Available color schemes, in menu order, plus their German display
# labels (menu language is German, section 6 of CLAUDE.md). COLOR_THEME
# (a validated user setting in rowhammer.sh) picks one of these names.
COLOR_THEMES=(guideline classic mono colorblind)
declare -A COLOR_THEME_LABEL=(
    [guideline]="Guideline"
    [classic]="Classic"
    [mono]="Monochrom"
    [colorblind]="Farbenblind"
)

# Theme table: for every theme and slot (the seven piece types plus the
# GOLD and SILVER square looks) the color name to use. Keys are
# "theme:slot"; a flat map keeps it a single associative array (bash has
# no nested arrays). "guideline" reproduces the pre-0.19.0 default look
# exactly. "colorblind" avoids the red/green pair (deuteranopia) and
# leans on the blue-yellow axis plus lightness differences.
declare -A THEME_COLOR=(
    [guideline:I]="cyan"  [guideline:O]="yellow" [guideline:T]="magenta"
    [guideline:S]="green" [guideline:Z]="red"    [guideline:J]="blue"
    [guideline:L]="orange" [guideline:GOLD]="gold" [guideline:SILVER]="silver"

    [classic:I]="cyan"  [classic:O]="yellow" [classic:T]="white"
    [classic:S]="green" [classic:Z]="red"    [classic:J]="blue"
    [classic:L]="magenta" [classic:GOLD]="gold" [classic:SILVER]="silver"

    [mono:I]="grey"  [mono:O]="grey" [mono:T]="grey"
    [mono:S]="grey"  [mono:Z]="grey" [mono:J]="grey"
    [mono:L]="grey"  [mono:GOLD]="gold" [mono:SILVER]="silver"

    [colorblind:I]="sky"  [colorblind:O]="yellow" [colorblind:T]="purple"
    [colorblind:S]="white" [colorblind:Z]="amber" [colorblind:J]="blue"
    [colorblind:L]="orange" [colorblind:GOLD]="gold" [colorblind:SILVER]="silver"
)

# The bag of upcoming pieces (7-bag randomizer state).
PIECE_TYPES=(I O T S Z J L)
BAG=()

# Refill the bag with all seven piece types and shuffle it in place
# (Fisher-Yates). RANDOM drives the shuffle, so seeding RANDOM makes the
# whole piece sequence reproducible (used by --seed).
bag_refill() {
    BAG=("${PIECE_TYPES[@]}")
    local i j tmp
    for (( i = ${#BAG[@]} - 1; i > 0; i-- )); do
        j=$(( RANDOM % (i + 1) ))
        tmp="${BAG[i]}"
        BAG[i]="${BAG[j]}"
        BAG[j]="${tmp}"
    done
    debug_event "bag refill: ${BAG[*]}"
}

# Queue of upcoming pieces drawn from the bag. It always holds at least
# PREVIEW_COUNT + 1 entries so the HUD can show three previews plus the
# piece that spawns next.
QUEUE=()
PREVIEW_COUNT=3

# queue_fill: top the queue up from the bag (refilling the bag as needed).
queue_fill() {
    while [ "${#QUEUE[@]}" -lt $(( PREVIEW_COUNT + 1 )) ]; do
        if [ "${#BAG[@]}" -eq 0 ]; then
            bag_refill
        fi
        QUEUE+=("${BAG[0]}")
        BAG=("${BAG[@]:1}")
    done
}

# bag_next: pop the next piece type into the global NEXT_TYPE and keep the
# preview queue topped up. The result is passed via a global instead of
# command substitution to avoid forking a subshell in the game loop.
bag_next() {
    queue_fill
    NEXT_TYPE="${QUEUE[0]}"
    QUEUE=("${QUEUE[@]:1}")
    queue_fill
}
