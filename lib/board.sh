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
#   lib/squares.sh. A four-row clear also raises the round's rowhammer
#   counter (ROWHAMMER_COUNT in rowhammer.sh), the move the game is
#   named after. board_full_rows reports the full rows before they
#   are removed, so the caller can flash them first (see flash_rows in
#   rowhammer.sh). The two top rows are hidden spawn rows; board_top_out
#   reports whether anything has come to rest in them, which ends the
#   round wherever it is asked.
#   board_flood_row lifts the whole board by one row and lets a row with a
#   single gap in at the bottom, which is what the "Hochwasser" mode is
#   made of. In debug mode every cleared row is logged with its credit
#   breakdown. Every
#   function that changes the board calls render_board_dirty
#   (lib/render.sh) so the renderer's settled-row cache is rebuilt on the
#   next frame.
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.10.0  (2026-08-11)

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

# Cell type of a flood row (the "Hochwasser" mode, see board_flood_row and
# flood_raise in rowhammer.sh). Its own letter rather than a piece type:
# a flood cell is not a piece, it carries the instance id 0 and can
# therefore never take part in a square (square_check_at rejects id 0),
# and the renderer draws it with a look of its own (lib/render.sh).
GARBAGE_CELL="x"

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
    render_board_dirty
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
# so the square detection can identify complete pieces later. The
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
    render_board_dirty
}

# board_top_out
# Return 0 when any cell sits in the hidden spawn rows above the visible
# field, 1 otherwise. Those two rows are where a piece enters the board,
# they are not part of the 20-row field: whatever comes to rest up there
# has left the field, and the round is over. The callers in rowhammer.sh
# are lock_and_next (a piece that settles reaching into them) and
# flood_raise (a rise that pushes the stack into them).
# CHANGE 2026-08-06: before this, a round only ended when the spawn
# position itself was blocked, so a piece could settle sticking out above
# the field and the round went on (user report).
# Asked of the board rather than of the piece that just locked, for two
# reasons: a clear that pulls the stack back down into the field saves
# the round (the check runs after clear_lines), and the rising water of
# the Hochwasser mode is then measured by the very same rule as a locked
# piece instead of one of its own.
board_top_out() {
    local i
    for (( i = 0; i < HIDDEN_ROWS * BOARD_W; i++ )); do
        if [ "${BOARD[i]}" != "${EMPTY_CELL}" ]; then
            return 0
        fi
    done
    return 1
}

# board_flood_row HOLE
# Push the whole board up by one row and let a full row with a single gap
# at column HOLE in at the bottom: the rising water of the "Hochwasser"
# mode (see flood_raise in rowhammer.sh, which owns the timing and the
# gap column). Returns 1 without changing anything when the top row still
# holds a cell - shifting would drop it off the board, and a stack that
# high is a topped-out round, which the caller ends.
# CHANGE 2026-08-06: in a normal round that guard no longer fires, since
# board_top_out ends the round as soon as the stack reaches the hidden
# rows at all - one rise earlier than a cell in the topmost one. It stays
# as the function's own safety net: it is the only thing keeping a cell
# from being shifted off the board, and the multiplayer garbage of phase
# 5 (see CLAUDE.md 5.7) will push several rows at once through here.
# Rows move as a whole across all three arrays, so locked instances keep
# their ids and their gold/silver marking and only their coordinates
# change: a square survives being lifted, exactly as it survives a line
# clear below it. The new row can never complete a line (it always keeps
# its hole), so no clear check follows it.
board_flood_row() {
    local hole="${1}"
    local x y idx src
    for (( x = 0; x < BOARD_W; x++ )); do
        if [ "${BOARD[x]}" != "${EMPTY_CELL}" ]; then
            return 1
        fi
    done
    for (( y = 0; y < BOARD_H - 1; y++ )); do
        for (( x = 0; x < BOARD_W; x++ )); do
            idx=$(( y * BOARD_W + x ))
            src=$(( idx + BOARD_W ))
            BOARD[idx]="${BOARD[src]}"
            BOARD_ID[idx]="${BOARD_ID[src]}"
            BOARD_SQ[idx]="${BOARD_SQ[src]}"
        done
    done
    y=$(( BOARD_H - 1 ))
    for (( x = 0; x < BOARD_W; x++ )); do
        idx=$(( y * BOARD_W + x ))
        if [ "${x}" -eq "${hole}" ]; then
            BOARD[idx]="${EMPTY_CELL}"
        else
            BOARD[idx]="${GARBAGE_CELL}"
        fi
        BOARD_ID[idx]=0
        BOARD_SQ[idx]=""
    done
    render_board_dirty
    return 0
}

# board_full_rows
# Collect the y coordinates of all currently full rows into the global
# array FULL_ROWS (top to bottom, empty when nothing is complete). Runs
# before clear_lines so the caller can flash the rows that are about to
# vanish; the board itself is not touched here.
FULL_ROWS=()
board_full_rows() {
    local y x row_full
    FULL_ROWS=()
    for (( y = 0; y < BOARD_H; y++ )); do
        row_full=1
        for (( x = 0; x < BOARD_W; x++ )); do
            if [ "${BOARD[y * BOARD_W + x]}" = "${EMPTY_CELL}" ]; then
                row_full=0
                break
            fi
        done
        if [ "${row_full}" -eq 1 ]; then
            FULL_ROWS+=( "${y}" )
        fi
    done
    return 0
}

# clear_lines
# Remove every full row, let the rows above fall down and refill the top
# with empty rows. Reports two globals: CLEARED (physical rows removed,
# drives the level curve) and CLEARED_CREDIT (weighted row credit that
# feeds the wonder progress and, since the scoring rebuild, is also the
# round's score). Credit per the original's verified rules:
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
    # How many gold and silver squares the cleared rows ran through, as
    # whole squares rather than cells. The row credit above needs the
    # figure per row, but the multiplayer needs it for the whole clear:
    # it is what a clear is worth as an attack, and the hub computes that
    # from the three numbers the client reports (CLAUDE.md 5.7). Summed
    # here because this is the one place that already counts them.
    CLEARED_GOLD=0
    CLEARED_SILVER=0
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
            CLEARED_GOLD=$(( CLEARED_GOLD + gold_cells / 4 ))
            CLEARED_SILVER=$(( CLEARED_SILVER + silver_cells / 4 ))
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
    # credit, per the original's rules. That very move is what the
    # project is named after, so it also feeds the round's rowhammer
    # counter - kept with the other round state in rowhammer.sh (like
    # NEXT_INSTANCE_ID, which lock_piece advances from here).
    if [ "${CLEARED}" -eq 4 ]; then
        CLEARED_CREDIT=$(( CLEARED_CREDIT + ROWS_TETRIS ))
        ROWHAMMER_COUNT=$(( ROWHAMMER_COUNT + 1 ))
        debug_event "rowhammer (4 rows at once): round_total=${ROWHAMMER_COUNT}"
    fi
    render_board_dirty
}
