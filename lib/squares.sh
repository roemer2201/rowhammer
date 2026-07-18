#!/usr/bin/env bash
#
# lib/squares.sh
#
# Description:
#   The-New-Tetris square mechanics for rowhammer: detection of 4x4
#   squares built from exactly four complete, uncut tetromino instances.
#   Four instances of the same type form a gold (mono) square, mixed
#   types a silver (multi) square. Square cells are marked in BOARD_SQ
#   and make cleared rows worth bonus row credit (see ROWS_* below).
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.2.0  (2026-07-18)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/squares.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# Row credit values for the wonder progress counter, following the
# original's verified rules (CLAUDE.md 3.2): every cleared row counts
# ROWS_NORMAL as its base, plus ROWS_GOLD per gold square and
# ROWS_SILVER per silver square the row runs through (additive when a
# row crosses several squares). Clearing four rows at once (a Tetris)
# adds ROWS_TETRIS once on top. Famous maximum: a Tetris through two
# complete gold squares = 4 + 1 + 8 x 10 = 85. Kept as plain variables
# so playtesting can tune them easily.
ROWS_NORMAL=1
ROWS_SILVER=5
ROWS_GOLD=10
ROWS_TETRIS=1

# Result of the last successful detect_square call: "G" or "S".
SQUARE_RESULT=""

# square_check_at X0 Y0
# Check whether the 4x4 area with top-left corner (X0, Y0) is a valid
# square and mark it on success. Valid means: all 16 cells filled and
# every cell belongs to one of exactly 4 distinct instances, none of
# which is cut (damaged by a line clear) or already part of a square.
# Because every instance owns at most 4 cells, "16 cells from 4 distinct
# instances" already implies each instance lies completely inside the
# area - no separate outside-cells check is needed.
square_check_at() {
    local x0="${1}" y0="${2}"
    local -A ids=()
    local x y idx id
    for (( y = y0; y < y0 + 4; y++ )); do
        for (( x = x0; x < x0 + 4; x++ )); do
            idx=$(( y * BOARD_W + x ))
            if [ "${BOARD[idx]}" = "${EMPTY_CELL}" ]; then
                return 1
            fi
            id="${BOARD_ID[idx]}"
            if [ "${id}" -eq 0 ]; then
                return 1
            fi
            if [ -n "${INSTANCE_CUT[${id}]:-}" ]; then
                return 1
            fi
            if [ -n "${INSTANCE_SQUARED[${id}]:-}" ]; then
                return 1
            fi
            ids["${id}"]=1
            if [ "${#ids[@]}" -gt 4 ]; then
                return 1
            fi
        done
    done
    if [ "${#ids[@]}" -ne 4 ]; then
        return 1
    fi

    # Mono check: all 16 cells share one piece type -> gold, else silver.
    local mark="G"
    local t0="${BOARD[y0 * BOARD_W + x0]}"
    for (( y = y0; y < y0 + 4; y++ )); do
        for (( x = x0; x < x0 + 4; x++ )); do
            if [ "${BOARD[y * BOARD_W + x]}" != "${t0}" ]; then
                mark="S"
            fi
        done
    done

    # Mark the square cells and consume the four instances (an instance
    # can belong to at most one square).
    for (( y = y0; y < y0 + 4; y++ )); do
        for (( x = x0; x < x0 + 4; x++ )); do
            BOARD_SQ[y * BOARD_W + x]="${mark}"
        done
    done
    for id in "${!ids[@]}"; do
        INSTANCE_SQUARED["${id}"]=1
    done
    SQUARE_RESULT="${mark}"
    return 0
}

# detect_square LOCK_X LOCK_Y
# Scan for a new square after a piece locked at (LOCK_X, LOCK_Y). Any new
# square must contain a cell of the just-locked piece (everything else
# was already checked after earlier locks), so only 4x4 origins within
# the piece's 7x7 neighborhood need testing. At most one square can form
# per lock (the new piece joins at most one square), so the scan stops at
# the first hit. Returns 0 with SQUARE_RESULT set, or 1 if none formed.
detect_square() {
    local lx="${1}" ly="${2}"
    local x0 y0 x_min x_max y_min y_max
    x_min=$(( lx - 3 ))
    if [ "${x_min}" -lt 0 ]; then x_min=0; fi
    x_max=$(( lx + 3 ))
    if [ "${x_max}" -gt $(( BOARD_W - 4 )) ]; then x_max=$(( BOARD_W - 4 )); fi
    y_min=$(( ly - 3 ))
    if [ "${y_min}" -lt 0 ]; then y_min=0; fi
    y_max=$(( ly + 3 ))
    if [ "${y_max}" -gt $(( BOARD_H - 4 )) ]; then y_max=$(( BOARD_H - 4 )); fi

    SQUARE_RESULT=""
    for (( y0 = y_min; y0 <= y_max; y0++ )); do
        for (( x0 = x_min; x0 <= x_max; x0++ )); do
            if square_check_at "${x0}" "${y0}"; then
                return 0
            fi
        done
    done
    return 1
}
