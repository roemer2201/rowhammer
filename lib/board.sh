#!/usr/bin/env bash
#
# lib/board.sh
#
# Description:
#   Board state and rules for rowhammer: the playfield, collision
#   checking, piece locking and line clearing. Three parallel arrays
#   describe each cell (index y * BOARD_W + x): BOARD holds the piece
#   type letter (or EMPTY_CELL), BOARD_ID the locked piece instance id
#   (0 = none) and BOARD_SQ the square status ("" none, "S" silver,
#   "G" gold). Line clears mark the instances they run through as cut
#   (INSTANCE_CUT), which disqualifies them from forming squares, and
#   report weighted row credit based on the ROWS_* values from
#   lib/squares.sh. The two top rows are hidden spawn rows. In debug
#   mode every cleared row is logged with its credit breakdown.
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.4.0  (2026-07-18)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/board.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# Board geometry: 10 columns, 20 visible rows plus 2 hidden spawn rows on
# top (rows 0 and 1).
BOARD_W=10
BOARD_H=22
HIDDEN_ROWS=2
EMPTY_CELL="."
BOARD=()
BOARD_ID=()
BOARD_SQ=()

# Per-instance state, keyed by instance id. Cut instances were damaged by
# a line clear; squared instances are consumed by a formed square. Both
# are reset per round (game_reset). The id counter itself lives in
# rowhammer.sh (NEXT_INSTANCE_ID) with the other game state globals.
declare -A INSTANCE_CUT=()
declare -A INSTANCE_SQUARED=()

# Reset the whole board to empty cells.
board_init() {
    local i
    BOARD=()
    BOARD_ID=()
    BOARD_SQ=()
    for (( i = 0; i < BOARD_W * BOARD_H; i++ )); do
        BOARD[i]="${EMPTY_CELL}"
        BOARD_ID[i]=0
        BOARD_SQ[i]=""
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
# Write the piece permanently into the board under a fresh instance id,
# so the square detection can identify complete tetrominoes later. The
# caller must have checked the position with can_place first.
lock_piece() {
    local type="${1}" rot="${2}" px="${3}" py="${4}"
    local -a cells
    local cell cx cy idx
    local id="${NEXT_INSTANCE_ID}"
    NEXT_INSTANCE_ID=$(( NEXT_INSTANCE_ID + 1 ))
    IFS=' ' read -ra cells <<< "${PIECE_SHAPE["${type}${rot}"]}"
    for cell in "${cells[@]}"; do
        cx="${cell%,*}"
        cy="${cell#*,}"
        idx=$(( (py + cy) * BOARD_W + (px + cx) ))
        BOARD[idx]="${type}"
        BOARD_ID[idx]="${id}"
    done
}

# clear_lines
# Remove every full row, let the rows above fall down and refill the top
# with empty rows. Reports two globals: CLEARED (physical rows removed,
# drives the level curve) and CLEARED_CREDIT (weighted row credit that
# feeds the wonder progress). Credit per the original's verified rules:
# every row counts ROWS_NORMAL, plus ROWS_GOLD per gold square and
# ROWS_SILVER per silver square the row runs through (additive); a
# Tetris (4 rows at once) adds ROWS_TETRIS once. The number of squares
# in a row is gold/silver cell count divided by 4: line clears only
# remove whole rows, so a square always keeps its full 4-cell width.
# Every instance a cleared row runs through is marked cut; the surviving
# cells keep their id and square marking (a trimmed gold/silver square
# keeps paying bonus credit, like in The New Tetris).
clear_lines() {
    CLEARED=0
    CLEARED_CREDIT=0
    local -a nb nid nsq
    local y x idx write_y row_full gold_cells silver_cells id credit
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
            gold_cells=0
            silver_cells=0
            for (( x = 0; x < BOARD_W; x++ )); do
                idx=$(( y * BOARD_W + x ))
                case "${BOARD_SQ[idx]}" in
                    G) gold_cells=$(( gold_cells + 1 )) ;;
                    S) silver_cells=$(( silver_cells + 1 )) ;;
                esac
                # The cleared row cuts every instance it runs through.
                id="${BOARD_ID[idx]}"
                if [ "${id}" -ne 0 ]; then
                    INSTANCE_CUT["${id}"]=1
                fi
            done
            credit=$(( ROWS_NORMAL \
                + ROWS_GOLD * (gold_cells / 4) \
                + ROWS_SILVER * (silver_cells / 4) ))
            CLEARED_CREDIT=$(( CLEARED_CREDIT + credit ))
            debug_event "clear row y=${y}: gold_cells=${gold_cells} silver_cells=${silver_cells} credit=${credit}"
        else
            for (( x = 0; x < BOARD_W; x++ )); do
                idx=$(( write_y * BOARD_W + x ))
                nb[idx]="${BOARD[y * BOARD_W + x]}"
                nid[idx]="${BOARD_ID[y * BOARD_W + x]}"
                nsq[idx]="${BOARD_SQ[y * BOARD_W + x]}"
            done
            write_y=$(( write_y - 1 ))
        fi
    done
    for (( y = write_y; y >= 0; y-- )); do
        for (( x = 0; x < BOARD_W; x++ )); do
            idx=$(( y * BOARD_W + x ))
            nb[idx]="${EMPTY_CELL}"
            nid[idx]=0
            nsq[idx]=""
        done
    done
    BOARD=("${nb[@]}")
    BOARD_ID=("${nid[@]}")
    BOARD_SQ=("${nsq[@]}")
    # Tetris bonus: clearing four rows in one move adds one extra row of
    # credit, per the original's rules.
    if [ "${CLEARED}" -eq 4 ]; then
        CLEARED_CREDIT=$(( CLEARED_CREDIT + ROWS_TETRIS ))
    fi
}
