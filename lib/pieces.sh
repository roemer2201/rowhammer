#!/usr/bin/env bash
#
# lib/pieces.sh
#
# Description:
#   Tetromino definitions for rowhammer: the seven piece types with their
#   four rotation states, per-piece colors for both the basic (8/16
#   color ANSI) and the extended (xterm 256-color) palette, the 7-bag
#   randomizer (every piece type appears exactly once per bag of seven)
#   and the upcoming-piece queue that feeds the HUD preview. In debug
#   mode every bag refill is logged with the shuffled piece order. A
#   per-type two-character glyph (PIECE_GLYPH) keeps pieces
#   distinguishable in the no-color mode.
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.5.0  (2026-07-21)

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

# ANSI foreground color (SGR code) per piece type for the basic color
# mode. Rendering combines this with reverse video to draw solid colored
# blocks. The basic 8-color palette works in any color-capable terminal;
# terminals with 256-color support get the extended palette below
# (COLOR_MODE, resolved in rowhammer.sh / lib/render.sh).
declare -A PIECE_COLOR=(
    [I]="36" [O]="33" [T]="35" [S]="32" [Z]="31" [J]="34" [L]="37"
)

# xterm 256-color index per piece type for the extended color mode.
# Rendering uses these as background colors (48;5;N). The picks follow
# the common Tetris guideline colors; the L piece finally gets a real
# orange (208), which the basic 8-color palette cannot express (there it
# falls back to white).
declare -A PIECE_COLOR_EXT=(
    [I]="51" [O]="220" [T]="135" [S]="40" [Z]="196" [J]="33" [L]="208"
)

# Two-character fallback glyph per piece type for the no-color mode
# (--no-color / NO_COLOR). Without color every settled block used to look
# the same ("[]"), so pieces became indistinguishable once they locked
# and planning gold (mono) / silver (mixed) squares was impossible. Each
# type now keeps its own marker - the doubled type letter, which makes
# the mapping self-evident. The gold/silver squares use non-letter glyphs
# (SQ_*_GLYPH in lib/render.sh) so a square never collides with a piece.
declare -A PIECE_GLYPH=(
    [I]="II" [O]="OO" [T]="TT" [S]="SS" [Z]="ZZ" [J]="JJ" [L]="LL"
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
