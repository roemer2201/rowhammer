#!/usr/bin/env bash
#
# lib/board.sh
#
# Description:
#   Board state and rules for rowhammer: the playfield array, collision
#   checking, piece locking and line clearing. The board is stored as a
#   one-dimensional array indexed y * BOARD_W + x; the two top rows are
#   hidden spawn rows above the visible 10x20 area.
#   Library file: sourced by tetris.sh, not meant to be executed directly.
#
# Version: 0.1.0  (2026-07-17)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/board.sh is a library; source it from tetris.sh\n' >&2
    exit 2
fi

# Board geometry: 10 columns, 20 visible rows plus 2 hidden spawn rows on
# top (rows 0 and 1). Cells hold a piece type letter or EMPTY_CELL.
BOARD_W=10
BOARD_H=22
HIDDEN_ROWS=2
EMPTY_CELL="."
BOARD=()

# Reset the whole board to empty cells.
board_init() {
    local i
    BOARD=()
    for (( i = 0; i < BOARD_W * BOARD_H; i++ )); do
        BOARD[i]="${EMPTY_CELL}"
    done
}

# can_place TYPE ROT X Y
# Return 0 when the piece fits at that position (all four cells inside the
# board and empty), 1 otherwise. Used for movement, rotation and spawning.
can_place() {
    local type="${1}" rot="${2}" px="${3}" py="${4}"
    local -a cells
    local cell cx cy x y
    IFS=' ' read -ra cells <<< "${PIECE_SHAPE["${type}${rot}"]}"
    for cell in "${cells[@]}"; do
        cx="${cell%,*}"
        cy="${cell#*,}"
        x=$(( px + cx ))
        y=$(( py + cy ))
        if (( x < 0 || x >= BOARD_W || y < 0 || y >= BOARD_H )); then
            return 1
        fi
        if [ "${BOARD[y * BOARD_W + x]}" != "${EMPTY_CELL}" ]; then
            return 1
        fi
    done
    return 0
}

# lock_piece TYPE ROT X Y
# Write the piece permanently into the board. The caller must have checked
# the position with can_place first.
lock_piece() {
    local type="${1}" rot="${2}" px="${3}" py="${4}"
    local -a cells
    local cell cx cy
    IFS=' ' read -ra cells <<< "${PIECE_SHAPE["${type}${rot}"]}"
    for cell in "${cells[@]}"; do
        cx="${cell%,*}"
        cy="${cell#*,}"
        BOARD[(py + cy) * BOARD_W + (px + cx)]="${type}"
    done
}

# clear_lines
# Remove every full row, let the rows above fall down and refill the top
# with empty rows. The number of cleared rows is reported in the global
# CLEARED. Rows are compacted bottom-up into a fresh array so multiple
# simultaneous clears are handled in one pass.
clear_lines() {
    CLEARED=0
    local -a nb
    local y x write_y row_full
    write_y=$(( BOARD_H - 1 ))
    for (( y = BOARD_H - 1; y >= 0; y-- )); do
        row_full=1
        for (( x = 0; x < BOARD_W; x++ )); do
            if [ "${BOARD[y * BOARD_W + x]}" = "${EMPTY_CELL}" ]; then
                row_full=0
                break
            fi
        done
        if [ "${row_full}" -eq 1 ]; then
            CLEARED=$(( CLEARED + 1 ))
        else
            for (( x = 0; x < BOARD_W; x++ )); do
                nb[write_y * BOARD_W + x]="${BOARD[y * BOARD_W + x]}"
            done
            write_y=$(( write_y - 1 ))
        fi
    done
    for (( y = write_y; y >= 0; y-- )); do
        for (( x = 0; x < BOARD_W; x++ )); do
            nb[y * BOARD_W + x]="${EMPTY_CELL}"
        done
    done
    BOARD=("${nb[@]}")
}
