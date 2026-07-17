#!/usr/bin/env bash
#
# lib/pieces.sh
#
# Description:
#   Tetromino definitions for rowhammer: the seven piece types with their
#   four rotation states, per-piece ANSI colors and the 7-bag randomizer
#   (every piece type appears exactly once per bag of seven).
#   Library file: sourced by tetris.sh, not meant to be executed directly.
#
# Version: 0.1.0  (2026-07-17)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/pieces.sh is a library; source it from tetris.sh\n' >&2
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

# ANSI foreground color (SGR code) per piece type. Rendering combines this
# with reverse video to draw solid colored blocks. Only the basic 8-color
# palette is used so the game works in any color-capable terminal; a nicer
# 256-color mode is planned for a later phase (see CLAUDE.md).
declare -A PIECE_COLOR=(
    [I]="36" [O]="33" [T]="35" [S]="32" [Z]="31" [J]="34" [L]="37"
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
}

# bag_next: pop the next piece type into the global NEXT_TYPE, refilling
# the bag when it runs empty. The result is passed via a global instead of
# command substitution to avoid forking a subshell in the game loop.
bag_next() {
    if [ "${#BAG[@]}" -eq 0 ]; then
        bag_refill
    fi
    NEXT_TYPE="${BAG[0]}"
    BAG=("${BAG[@]:1}")
}
