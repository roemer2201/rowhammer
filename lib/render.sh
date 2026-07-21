#!/usr/bin/env bash
#
# lib/render.sh
#
# Description:
#   Screen rendering for rowhammer. Builds every frame (board, active
#   piece, gold/silver squares, sidebar with the weighted row credit
#   (the game's score since the scoring rebuild), the wonder under
#   construction with its build percentage, piece
#   preview, hold slot, key hints and the achieved highscore rank
#   on the game over screen) into one string and prints it
#   with a single printf - classic double buffering, which keeps the
#   terminal flicker-free. Blocks are drawn with per-piece SGR sequences
#   precomputed for the resolved color mode: basic (8/16-color ANSI,
#   reverse video) or extended (xterm 256-color backgrounds); "auto"
#   detection lives in color_mode_resolve. In the no-color mode every
#   piece type instead draws its own two-character glyph (PIECE_GLYPH,
#   lib/pieces.sh) and the gold/silver squares use distinct non-letter
#   glyphs, so blocks stay tellable apart without color. All terminal
#   output goes
#   through screen_write, which mirrors every update 1:1 into the frame
#   log when the debug mode is active (lib/debug.sh).
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.9.0  (2026-07-21)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/render.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# Cells of the active piece, keyed "x,y", rebuilt on every frame so the
# board pass below can overlay the falling piece without mutating BOARD.
declare -A OVERLAY=()

# Per-piece block SGR sequences plus the gold/silver square looks,
# precomputed once by render_colors_init so the per-cell render loops
# stay free of mode branches and string assembly.
declare -A PIECE_SGR=()
SQ_GOLD_SGR=""
SQ_SILVER_SGR=""
RESET_SGR=$'\e[0m'

# No-color (--no-color / NO_COLOR) glyphs for the gold/silver squares.
# Non-letter markers so a square never collides with a per-type piece
# glyph (PIECE_GLYPH, lib/pieces.sh) and gold reads denser than silver:
# without color these are the only cue that tells the two square kinds
# and the loose pieces apart.
SQ_GOLD_GLYPH="##"
SQ_SILVER_GLYPH="%%"

# color_mode_resolve
# Resolve COLOR_MODE=auto into basic or extended by probing the
# terminal: tput colors when available (tput is optional per the
# conventions), with TERM/COLORTERM as fallback signals. Explicit basic
# or extended requests are left untouched.
color_mode_resolve() {
    if [ "${COLOR_MODE}" != "auto" ]; then
        return 0
    fi
    local n=0
    if command -v tput >/dev/null 2>&1; then
        n="$(tput colors 2>/dev/null)" || n=0
    fi
    if ! [[ "${n}" =~ ^[0-9]+$ ]]; then
        n=0
    fi
    if (( n >= 256 )) || [[ "${TERM:-}" == *256color* ]] \
        || [ "${COLORTERM:-}" = "truecolor" ] || [ "${COLORTERM:-}" = "24bit" ]; then
        COLOR_MODE="extended"
    else
        COLOR_MODE="basic"
    fi
    return 0
}

# render_colors_init
# Build the block SGR lookup for the resolved color mode. Basic mode
# keeps the original look (reverse video on the 8-color foreground);
# extended mode paints xterm 256-color backgrounds and gives the squares
# richer gold/grey tones instead of plain yellow/white.
render_colors_init() {
    local t
    if [ "${COLOR_MODE}" = "extended" ]; then
        for t in "${PIECE_TYPES[@]}"; do
            PIECE_SGR["${t}"]=$'\e[48;5;'"${PIECE_COLOR_EXT[${t}]}m"
        done
        SQ_GOLD_SGR=$'\e[38;5;16;48;5;178m'
        SQ_SILVER_SGR=$'\e[38;5;16;48;5;250m'
    else
        for t in "${PIECE_TYPES[@]}"; do
            PIECE_SGR["${t}"]=$'\e[7;'"${PIECE_COLOR[${t}]}m"
        done
        SQ_GOLD_SGR=$'\e[30;43m'
        SQ_SILVER_SGR=$'\e[30;47m'
    fi
    return 0
}

# screen_write CONTENT
# The single funnel for terminal output: print CONTENT and, in debug
# mode, record it byte for byte in the frame log. Every module that
# draws to the screen (game frames, menus, prompts, terminal setup) must
# use this instead of a direct printf, so the debug trace really is a
# 1:1 copy of what the player saw.
screen_write() {
    printf '%s' "${1}"
    debug_frame "${1}"
}

# render_mini TYPE ROW
# Build one display row (4 cells = 8 chars wide) of a piece preview into
# the global RENDER_MINI, using spawn rotation 0. Rows 0 and 1 cover
# every piece type (the I piece sits in row 1 of its box). An empty TYPE
# yields blanks, so the hold slot can render before anything is held.
render_mini() {
    local type="${1}" row="${2}"
    local shape cx
    RENDER_MINI=""
    if [ -z "${type}" ]; then
        RENDER_MINI="        "
        return 0
    fi
    shape=" ${PIECE_SHAPE["${type}0"]} "
    for (( cx = 0; cx < 4; cx++ )); do
        if [[ "${shape}" == *" ${cx},${row} "* ]]; then
            if [ "${USE_COLOR}" -eq 1 ]; then
                RENDER_MINI+="${PIECE_SGR[${type}]}  ${RESET_SGR}"
            else
                RENDER_MINI+="${PIECE_GLYPH[${type}]}"
            fi
        else
            RENDER_MINI+="  "
        fi
    done
    return 0
}

# draw_frame
# Render the complete screen. Reads the game state globals (BOARD,
# BOARD_SQ, CUR_*, QUEUE, HOLD_TYPE, CLEARED_TOTAL, ROW_CREDIT,
# LEVEL, GOLD_COUNT, SILVER_COUNT, PAUSED, GAME_OVER, the WONDER_*
# state from lib/wonders.sh) and the USE_COLOR flag. Every line ends with ESC[K so shorter new content fully replaces
# longer old content; the frame ends with ESC[0J to wipe leftovers from
# taller menu screens.
draw_frame() {
    local frame="" line cell sq idx y x
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

    # Sidebar text, one entry per visible board row. "Lines" counts
    # physical rows (drives the level), "Rows" is the weighted credit
    # (gold/silver bonus) that builds the wonders - and, since the
    # scoring rebuild, the round's score; the old separate score line
    # is gone.
    local -a side=()
    side[0]="Player: ${PLAYER_NAME}"
    side[1]="Lines: ${CLEARED_TOTAL}"
    side[2]="Rows:  ${ROW_CREDIT}"
    side[3]="Level: ${LEVEL}"
    side[4]="Gold: ${GOLD_COUNT}   Silver: ${SILVER_COUNT}"
    # Wonder progress, kept live by wonders_update on every line clear
    # (banked total plus this round's credit). No "Wonder:" label so the
    # longest name still fits the 24-column sidebar budget.
    if [ "${WONDER_ALL_DONE}" -eq 1 ]; then
        side[5]="All wonders built"
    else
        side[5]="${WONDER_HUD_NAME} ${WONDER_PERCENT}%"
    fi
    side[7]="Next        Hold"
    render_mini "${QUEUE[0]:-}" 0
    local n1a="${RENDER_MINI}"
    render_mini "${QUEUE[0]:-}" 1
    local n1b="${RENDER_MINI}"
    render_mini "${HOLD_TYPE}" 0
    local h0="${RENDER_MINI}"
    render_mini "${HOLD_TYPE}" 1
    local h1="${RENDER_MINI}"
    side[8]="${n1a}    ${h0}"
    side[9]="${n1b}    ${h1}"
    render_mini "${QUEUE[1]:-}" 0
    side[11]="${RENDER_MINI}"
    render_mini "${QUEUE[1]:-}" 1
    side[12]="${RENDER_MINI}"
    render_mini "${QUEUE[2]:-}" 0
    side[14]="${RENDER_MINI}"
    render_mini "${QUEUE[2]:-}" 1
    side[15]="${RENDER_MINI}"
    side[17]="${KEY_HOLD} hold   ${KEY_PAUSE} pause   ${KEY_QUIT}/ESC menu"
    if [ "${PAUSED}" -eq 1 ]; then
        side[19]="** PAUSED **"
    fi
    if [ "${GAME_OVER}" -eq 1 ]; then
        # The finished round was recorded when the game over triggered
        # (record_round), so HS_LAST_RANK is this round's rank.
        if [ "${HS_LAST_RANK}" -gt 0 ]; then
            side[16]="New highscore: rank ${HS_LAST_RANK}"
        fi
        side[18]="** GAME OVER **"
        side[19]="r = restart, ${KEY_QUIT} = menu"
    fi

    frame+=$'\e[H'
    frame+="  R O W H A M M E R"$'\e[K\n'
    frame+="${border}"$'\e[K\n'
    for (( y = HIDDEN_ROWS; y < BOARD_H; y++ )); do
        line="|"
        for (( x = 0; x < BOARD_W; x++ )); do
            cell="${OVERLAY["${x},${y}"]:-}"
            if [ -n "${cell}" ]; then
                # Active piece cell.
                if [ "${USE_COLOR}" -eq 1 ]; then
                    line+="${PIECE_SGR[${cell}]}  ${RESET_SGR}"
                else
                    line+="${PIECE_GLYPH[${cell}]}"
                fi
            else
                idx=$(( y * BOARD_W + x ))
                cell="${BOARD[idx]}"
                if [ "${cell}" = "${EMPTY_CELL}" ]; then
                    line+="  "
                else
                    # Settled cell: gold/silver squares get their own
                    # look so they stand out from normal pieces. With
                    # color the "##" glyph also distinguishes gold from
                    # the yellow O; without color the squares use distinct
                    # non-letter glyphs (## / %%) and every other piece
                    # keeps its own per-type glyph so they all stay
                    # tellable apart.
                    sq="${BOARD_SQ[idx]}"
                    if [ "${sq}" = "G" ]; then
                        if [ "${USE_COLOR}" -eq 1 ]; then
                            line+="${SQ_GOLD_SGR}##${RESET_SGR}"
                        else
                            line+="${SQ_GOLD_GLYPH}"
                        fi
                    elif [ "${sq}" = "S" ]; then
                        if [ "${USE_COLOR}" -eq 1 ]; then
                            line+="${SQ_SILVER_SGR}##${RESET_SGR}"
                        else
                            line+="${SQ_SILVER_GLYPH}"
                        fi
                    elif [ "${USE_COLOR}" -eq 1 ]; then
                        line+="${PIECE_SGR[${cell}]}  ${RESET_SGR}"
                    else
                        line+="${PIECE_GLYPH[${cell}]}"
                    fi
                fi
            fi
        done
        line+="|  ${side[y - HIDDEN_ROWS]:-}"
        frame+="${line}"$'\e[K\n'
    done
    # Clear everything below the board so leftovers from a previously
    # drawn (taller) menu screen cannot linger.
    frame+="${border}"$'\e[K\e[0J'
    screen_write "${frame}"
}
