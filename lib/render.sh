#!/usr/bin/env bash
#
# lib/render.sh
#
# Description:
#   Screen rendering for rowhammer. Builds every frame (board, active
#   piece, sidebar with score and controls) into one string and prints it
#   with a single printf - classic double buffering, which keeps the
#   terminal flicker-free.
#   Library file: sourced by tetris.sh, not meant to be executed directly.
#
# Version: 0.1.0  (2026-07-17)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/render.sh is a library; source it from tetris.sh\n' >&2
    exit 2
fi

# Cells of the active piece, keyed "x,y", rebuilt on every frame so the
# board pass below can overlay the falling piece without mutating BOARD.
declare -A OVERLAY=()

# draw_frame
# Render the complete screen. Reads the game state globals (BOARD, CUR_*,
# SCORE, CLEARED_TOTAL, LEVEL, PAUSED, GAME_OVER) and the USE_COLOR flag.
# Every line ends with ESC[K so shorter new content fully replaces longer
# old content (for example when the PAUSED marker disappears).
draw_frame() {
    local frame="" line cell color y x
    local border="+--------------------+"

    # Overlay the active piece; on the game over screen the piece that
    # failed to spawn is intentionally not drawn.
    OVERLAY=()
    if [ "${GAME_OVER}" -eq 0 ]; then
        local -a cells
        local c cx cy
        IFS=' ' read -ra cells <<< "${PIECE_SHAPE["${CUR_TYPE}${CUR_ROT}"]}"
        for c in "${cells[@]}"; do
            cx="${c%,*}"
            cy="${c#*,}"
            OVERLAY["$(( CUR_X + cx )),$(( CUR_Y + cy ))"]="${CUR_TYPE}"
        done
    fi

    # Sidebar text, one entry per visible board row.
    local -a side=()
    side[1]="Score: ${SCORE}"
    side[2]="Lines: ${CLEARED_TOTAL}"
    side[3]="Level: ${LEVEL}"
    side[5]="Controls"
    side[6]="  a/d, arrows  move"
    side[7]="  w/up   rotate cw"
    side[8]="  q      rotate ccw"
    side[9]="  s/down soft drop"
    side[10]="  space  hard drop"
    side[11]="  p      pause"
    side[12]="  x/ESC  quit"
    if [ "${PAUSED}" -eq 1 ]; then
        side[14]="** PAUSED **"
    fi
    if [ "${GAME_OVER}" -eq 1 ]; then
        side[14]="** GAME OVER **"
        side[15]="r = restart, x = quit"
    fi

    frame+=$'\e[H'
    frame+="  R O W H A M M E R"$'\e[K\n'
    frame+="${border}"$'\e[K\n'
    for (( y = HIDDEN_ROWS; y < BOARD_H; y++ )); do
        line="|"
        for (( x = 0; x < BOARD_W; x++ )); do
            cell="${OVERLAY["${x},${y}"]:-}"
            if [ -z "${cell}" ]; then
                cell="${BOARD[y * BOARD_W + x]}"
            fi
            if [ "${cell}" = "${EMPTY_CELL}" ]; then
                line+="  "
            elif [ "${USE_COLOR}" -eq 1 ]; then
                # Reverse video with the piece color paints a solid block.
                color="${PIECE_COLOR[${cell}]}"
                line+=$'\e[7;'"${color}m  "$'\e[0m'
            else
                line+="[]"
            fi
        done
        line+="|  ${side[y - HIDDEN_ROWS]:-}"
        frame+="${line}"$'\e[K\n'
    done
    frame+="${border}"$'\e[K'
    printf '%s' "${frame}"
}
