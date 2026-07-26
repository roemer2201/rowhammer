#!/usr/bin/env bash
#
# lib/render.sh
#
# Description:
#   Screen rendering for rowhammer. The game screen is one fixed block of
#   LAYOUT_W x LAYOUT_H characters, centered in the terminal (layout_update):
#   the hold piece and the key legend sit in the left pane, the board in
#   the middle, the three upcoming pieces in the top right pane and the
#   round counters (name, lines, rows, level, gold/silver, play time and
#   the wonder under construction) on the two bottom status lines. Pause
#   and game over are drawn as a box over the board, the latter with the
#   achieved highscore rank.
#   Since 0.12.0 frames are no longer pushed out as a whole: draw_frame
#   builds the block into FRAME_LINES and render_flush emits only the lines
#   that actually changed since the previous frame, each with its own
#   cursor positioning. Settled board rows are cached (BOARD_ROW_CACHE) and
#   only rebuilt after the board really changed (render_board_dirty), so a
#   moving piece costs a handful of rows instead of all 200 cells. Every
#   line is built to exactly LAYOUT_W visible columns, which is what makes
#   the diff safe without per-line erase sequences. RENDER_FULL forces a
#   complete repaint (screen cleared first) after menus, resizes and at
#   round start.
#   Blocks are drawn with per-piece SGR sequences precomputed for the
#   resolved color mode: basic (8/16-color ANSI, reverse video) or extended
#   (xterm 256-color backgrounds); "auto" detection lives in
#   color_mode_resolve. All terminal output goes through screen_write, which
#   mirrors every update 1:1 into the frame log when the debug mode is
#   active (lib/debug.sh). term_too_small_screen draws the compact overlay
#   shown while the terminal is smaller than the fixed layout needs (since
#   0.10.0, driven by lib/input.sh on resize). Rows about to be cleared can
#   be drawn highlighted (FLASH_ROWS / FLASH_STATE, since 0.11.0), which is
#   what the clear animation in rowhammer.sh toggles to make them blink.
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.12.0  (2026-07-26)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/render.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# --- Layout geometry ------------------------------------------------------
# The game screen is a fixed block; only its position follows the terminal
# size. Widths add up exactly: pane + gap + board + gap + pane
# (12 + 1 + 22 + 1 + 12 = 48), heights likewise: board frame + status
# (22 + 2 = 24). Both equal the minimum terminal size (MIN_TERM_* in
# rowhammer.sh), so the layout still fits a bare 48x24 terminal.
LAYOUT_W=48
LAYOUT_H=24
PANE_W=12
# Rows of the block: 0 = board top border, 1..20 = the visible board,
# 21 = bottom border, 22..23 = the status lines.
BOARD_TOP_ROW=0
BOARD_BOTTOM_ROW=21
STATUS_ROW_1=22
STATUS_ROW_2=23

# Top left corner of the block (1-based terminal coordinates), recomputed
# by layout_update whenever the terminal size changes.
LAYOUT_ROW=1
LAYOUT_COL=1

# Cells of the active piece, keyed "x,y", plus the set of board rows it
# touches. Rebuilt on every frame so the board pass can overlay the falling
# piece without mutating BOARD - and so only those rows have to be composed
# cell by cell instead of coming from the cache.
declare -A OVERLAY=()
declare -A OVERLAY_ROWS=()

# Per-piece block SGR sequences plus the gold/silver square looks,
# precomputed once by render_colors_init so the per-cell render loops
# stay free of mode branches and string assembly.
declare -A PIECE_SGR=()
SQ_GOLD_SGR=""
SQ_SILVER_SGR=""
FLASH_SGR=""
RESET_SGR=$'\e[0m'
BOX_SGR=""

# A fully highlighted board row (10 cells) of the clear animation, built
# once by render_colors_init because every flashing row looks the same.
FLASH_LINE=""

# The board's horizontal border, and a blank pane line; both are constant
# and exactly as wide as their column budget.
BOARD_BORDER="+--------------------+"
PANE_BLANK="            "

# Clear animation (2026-07-24): the rows a lock completed blink once
# before they are removed. FLASH_ROWS holds those board rows keyed by
# their y coordinate, FLASH_STATE switches the highlight on (1) and off
# (0); with FLASH_ROWS empty draw_frame renders exactly as before. Both
# are driven by flash_rows in rowhammer.sh.
declare -A FLASH_ROWS=()
FLASH_STATE=0

# --- Frame buffers --------------------------------------------------------
# FRAME_LINES is the block the current frame wants on screen, PREV_LINES
# what the previous frame put there; render_flush emits the difference.
# RENDER_FULL forces the next flush to clear the screen and redraw every
# line (after a menu, a resize or at round start, where the screen holds
# something else entirely).
declare -a FRAME_LINES=()
declare -a PREV_LINES=()
RENDER_FULL=1

# Cache of the settled board rows (index = board y, content = the 20
# visible characters of that row without the active piece). Rebuilt only
# when the board itself changed, which is once per lock instead of once
# per frame.
declare -a BOARD_ROW_CACHE=()
BOARD_CACHE_VALID=0

# Pane and status line buffers, rebuilt per frame by the helpers below.
declare -a PANE_LEFT=()
declare -a PANE_RIGHT=()
declare -A BOX_LINES=()
STATUS_1=""
STATUS_2=""

# Key legend lines of the left pane. Built by hud_keys_build whenever the
# bindings change (startup, rebind) instead of on every frame.
declare -a HUD_KEYS=()

# Output of render_board_row / render_mini (globals instead of command
# substitution: the game loop must not fork a subshell per row).
RENDER_ROW=""
RENDER_MINI=""

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
    local t x
    if [ "${COLOR_MODE}" = "extended" ]; then
        for t in "${PIECE_TYPES[@]}"; do
            PIECE_SGR["${t}"]=$'\e[48;5;'"${PIECE_COLOR_EXT[${t}]}m"
        done
        SQ_GOLD_SGR=$'\e[38;5;16;48;5;178m'
        SQ_SILVER_SGR=$'\e[38;5;16;48;5;250m'
        # Clear flash: the brightest white the palette offers, so a
        # flashing row clearly stands out from every block color.
        FLASH_SGR=$'\e[38;5;16;48;5;231m'
    else
        for t in "${PIECE_TYPES[@]}"; do
            PIECE_SGR["${t}"]=$'\e[7;'"${PIECE_COLOR[${t}]}m"
        done
        SQ_GOLD_SGR=$'\e[30;43m'
        SQ_SILVER_SGR=$'\e[30;47m'
        FLASH_SGR=$'\e[1;30;47m'
    fi
    # The pause/game over box is drawn bold rather than colored, so it
    # stays readable on top of any block color and in --no-color mode.
    if [ "${USE_COLOR}" -eq 1 ]; then
        BOX_SGR=$'\e[1m'
    else
        BOX_SGR=""
    fi
    FLASH_LINE=""
    for (( x = 0; x < BOARD_W; x++ )); do
        if [ "${USE_COLOR}" -eq 1 ]; then
            FLASH_LINE+="${FLASH_SGR}  ${RESET_SGR}"
        else
            FLASH_LINE+="=="
        fi
    done
    return 0
}

# layout_update
# Recompute the top left corner of the centered game block from the
# current terminal size (TERM_ROWS/TERM_COLS, kept up to date by
# term_measure in lib/input.sh) and force a full repaint, because the old
# frame now sits at the wrong place. Called at startup and after every
# resize; a terminal exactly at the minimum simply gets offset 1/1.
layout_update() {
    local row col
    row=$(( (TERM_ROWS - LAYOUT_H) / 2 + 1 ))
    col=$(( (TERM_COLS - LAYOUT_W) / 2 + 1 ))
    if [ "${row}" -lt 1 ]; then
        row=1
    fi
    if [ "${col}" -lt 1 ]; then
        col=1
    fi
    LAYOUT_ROW="${row}"
    LAYOUT_COL="${col}"
    RENDER_FULL=1
    return 0
}

# render_board_dirty
# Invalidate the settled-row cache. Called by every board mutation
# (lib/board.sh) so the next frame rebuilds the rows; the renderer owns
# the cache, the board module only reports that it changed.
render_board_dirty() {
    BOARD_CACHE_VALID=0
    return 0
}

# hud_keys_build
# Compose the key legend of the left pane from the current bindings. Only
# needs rebuilding when a binding changes (startup, prompt_rebind), not
# per frame. Each line is padded/truncated to the pane's usable width.
hud_keys_build() {
    local -a raw=()
    local line i
    printf -v line '%-4s %s' "${KEY_LEFT}/${KEY_RIGHT}" "move"
    raw+=("${line}")
    printf -v line '%-4s %s' "${KEY_ROT_CCW}/${KEY_ROT_CW}" "turn"
    raw+=("${line}")
    printf -v line '%-4s %s' "${KEY_SOFT}" "soft"
    raw+=("${line}")
    printf -v line '%-4s %s' "${KEY_HARD}" "hard"
    raw+=("${line}")
    printf -v line '%-4s %s' "${KEY_HOLD}" "hold"
    raw+=("${line}")
    printf -v line '%-4s %s' "${KEY_PAUSE}" "pause"
    raw+=("${line}")
    printf -v line '%-4s %s' "${KEY_QUIT}" "menu"
    raw+=("${line}")
    HUD_KEYS=()
    for (( i = 0; i < ${#raw[@]}; i++ )); do
        printf -v line '%-*.*s' "${PANE_W}" "${PANE_W}" " ${raw[i]}"
        HUD_KEYS+=("${line}")
    done
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

# term_too_small_screen
# Draw the overlay shown while the terminal is smaller than the fixed
# board+sidebar layout needs (MIN_TERM_* in rowhammer.sh). Called in a
# loop by term_resize_apply (lib/input.sh) until the terminal grows back.
# Kept deliberately tiny - short, colorless ASCII lines - so the message
# still fits and reads correctly in a cramped terminal; \r\n resets the
# column because the terminal is in raw mode here, where a bare \n would
# only move down. The live "now WxH" figure gives feedback while the user
# drags the border.
term_too_small_screen() {
    local frame
    printf -v frame '\e[2J\e[H%s\r\n%s\r\n%s\r\n%s' \
        "rowhammer" \
        "resize:" \
        "need ${MIN_TERM_COLS}x${MIN_TERM_ROWS}" \
        "now ${TERM_COLS}x${TERM_ROWS}"
    screen_write "${frame}"
    return 0
}

# render_mini TYPE ROW
# Build one display row (4 cells = 8 chars wide) of a piece preview into
# the global RENDER_MINI, using spawn rotation 0. Rows 0 and 1 cover
# every piece type (the I piece sits in row 1 of its box). An empty TYPE
# yields blanks, so the hold slot can render before anything is held.
# The result is always 8 visible columns wide, which is what lets the
# pane builders pad around it without measuring escape sequences.
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
                RENDER_MINI+="[]"
            fi
        else
            RENDER_MINI+="  "
        fi
    done
    return 0
}

# render_board_row Y WITH_PIECE
# Build the 20 visible characters of board row Y into RENDER_ROW.
# WITH_PIECE=1 overlays the active piece (OVERLAY), 0 renders the settled
# board only - that is the form the row cache stores, so a frame in which
# nothing but the falling piece moved rebuilds at most four rows.
render_board_row() {
    local y="${1}" with_piece="${2}"
    local x idx cell sq s=""
    for (( x = 0; x < BOARD_W; x++ )); do
        cell=""
        if [ "${with_piece}" -eq 1 ]; then
            cell="${OVERLAY["${x},${y}"]:-}"
        fi
        if [ -n "${cell}" ]; then
            # Active piece cell.
            if [ "${USE_COLOR}" -eq 1 ]; then
                s+="${PIECE_SGR[${cell}]}  ${RESET_SGR}"
            else
                s+="[]"
            fi
            continue
        fi
        idx=$(( y * BOARD_W + x ))
        cell="${BOARD[idx]}"
        if [ "${cell}" = "${EMPTY_CELL}" ]; then
            s+="  "
            continue
        fi
        # Settled cell: gold/silver squares get their own look so they
        # stand out from normal pieces (the "##" glyph also distinguishes
        # gold from the yellow O).
        sq="${BOARD_SQ[idx]}"
        if [ "${sq}" = "G" ]; then
            if [ "${USE_COLOR}" -eq 1 ]; then
                s+="${SQ_GOLD_SGR}##${RESET_SGR}"
            else
                s+="GG"
            fi
        elif [ "${sq}" = "S" ]; then
            if [ "${USE_COLOR}" -eq 1 ]; then
                s+="${SQ_SILVER_SGR}##${RESET_SGR}"
            else
                s+="SS"
            fi
        elif [ "${USE_COLOR}" -eq 1 ]; then
            s+="${PIECE_SGR[${cell}]}  ${RESET_SGR}"
        else
            s+="[]"
        fi
    done
    RENDER_ROW="${s}"
    return 0
}

# render_pane_left
# Left pane: the hold slot on top, the key legend below it. Every entry
# is exactly PANE_W visible columns wide.
render_pane_left() {
    local i line
    PANE_LEFT=()
    for (( i = 0; i <= BOARD_BOTTOM_ROW; i++ )); do
        PANE_LEFT[i]="${PANE_BLANK}"
    done
    printf -v line '%-*.*s' "${PANE_W}" "${PANE_W}" " Hold"
    PANE_LEFT[0]="${line}"
    render_mini "${HOLD_TYPE}" 0
    PANE_LEFT[1]=" ${RENDER_MINI}   "
    render_mini "${HOLD_TYPE}" 1
    PANE_LEFT[2]=" ${RENDER_MINI}   "
    printf -v line '%-*.*s' "${PANE_W}" "${PANE_W}" " Keys"
    PANE_LEFT[4]="${line}"
    for (( i = 0; i < ${#HUD_KEYS[@]}; i++ )); do
        PANE_LEFT[5 + i]="${HUD_KEYS[i]}"
    done
    return 0
}

# render_pane_right
# Right pane: the three upcoming pieces, top-aligned with the board, one
# blank line between them. Entries are PANE_W visible columns wide.
render_pane_right() {
    local i q line
    PANE_RIGHT=()
    for (( i = 0; i <= BOARD_BOTTOM_ROW; i++ )); do
        PANE_RIGHT[i]="${PANE_BLANK}"
    done
    printf -v line '%-*.*s' "${PANE_W}" "${PANE_W}" " Next"
    PANE_RIGHT[0]="${line}"
    for (( q = 0; q < PREVIEW_COUNT; q++ )); do
        render_mini "${QUEUE[q]:-}" 0
        PANE_RIGHT[1 + q * 3]=" ${RENDER_MINI}   "
        render_mini "${QUEUE[q]:-}" 1
        PANE_RIGHT[2 + q * 3]=" ${RENDER_MINI}   "
    done
    return 0
}

# render_status
# The two bottom lines: round counters and the wonder under construction.
# Both are printf-built to exactly LAYOUT_W columns, so they can never
# leave stale characters behind when a number gets shorter.
render_status() {
    local wonder
    if [ "${WONDER_ALL_DONE}" -eq 1 ]; then
        wonder="All wonders built"
    else
        wonder="${WONDER_HUD_NAME} ${WONDER_PERCENT}%"
    fi
    # "Lines" counts physical rows (drives the level), "Rows" is the
    # weighted credit (gold/silver bonus) that builds the wonders - and,
    # since the scoring rebuild, the round's score.
    printf -v STATUS_1 '%-16.16s %-11.11s %-12.12s %-6.6s' \
        "${PLAYER_NAME}" "Lines ${CLEARED_TOTAL}" "Rows ${ROW_CREDIT}" \
        "Lvl ${LEVEL}"
    # Elapsed play time of the running round (paused time excluded), fed
    # by the game loop's PLAY_MS and formatted MM:SS (fmt_duration).
    fmt_duration $(( PLAY_MS / 1000 ))
    printf -v STATUS_2 '%-8.8s %-10.10s %-10.10s %-17.17s' \
        "Gold ${GOLD_COUNT}" "Silver ${SILVER_COUNT}" \
        "Time ${FMT_DURATION}" "${wonder}"
    return 0
}

# render_status_box
# Build the pause / game over box drawn over the board, keyed by visible
# board row (0..19). Empty when the round is running. Putting it on the
# board instead of into a sidebar keeps the message where the player is
# looking, and the two bottom status lines stay free for the counters.
# Interior lines are 18 characters wide between the borders, so every
# entry is exactly the board's 20 visible columns.
render_status_box() {
    local i line
    BOX_LINES=()
    if [ "${GAME_OVER}" -eq 1 ]; then
        local -a body=()
        body+=("")
        body+=("    GAME OVER")
        body+=("")
        # The finished round was recorded when the game over triggered
        # (record_round), so HS_LAST_RANK is this round's rank.
        if [ "${HS_LAST_RANK}" -gt 0 ]; then
            body+=("  Highscore #${HS_LAST_RANK}")
        else
            body+=("")
        fi
        body+=("")
        body+=("  r = restart")
        body+=("  ${KEY_QUIT} = menu")
        body+=("")
        # BOX_LINES is an associative array, so its subscripts are plain
        # strings: the row index has to be computed explicitly, otherwise
        # the key would literally read "7 + i".
        BOX_LINES[6]="${BOX_SGR}+------------------+${RESET_SGR}"
        for (( i = 0; i < ${#body[@]}; i++ )); do
            printf -v line '|%-18.18s|' "${body[i]}"
            BOX_LINES["$(( 7 + i ))"]="${BOX_SGR}${line}${RESET_SGR}"
        done
        BOX_LINES[15]="${BOX_SGR}+------------------+${RESET_SGR}"
    elif [ "${PAUSED}" -eq 1 ]; then
        BOX_LINES[9]="${BOX_SGR}+------------------+${RESET_SGR}"
        BOX_LINES[10]="${BOX_SGR}|      PAUSED      |${RESET_SGR}"
        BOX_LINES[11]="${BOX_SGR}+------------------+${RESET_SGR}"
    fi
    return 0
}

# render_flush
# Push FRAME_LINES to the terminal: on a full repaint clear the screen and
# write every line, otherwise only the lines that differ from the previous
# frame, each preceded by its own cursor positioning. Because every line is
# built to exactly LAYOUT_W visible columns, a changed line always fully
# covers its predecessor - no erase sequences needed. Nothing is written at
# all when the frame is identical to the last one.
render_flush() {
    local out="" i pos
    if [ "${RENDER_FULL}" -eq 1 ]; then
        out=$'\e[2J'
        PREV_LINES=()
    fi
    for (( i = 0; i < LAYOUT_H; i++ )); do
        if [ "${RENDER_FULL}" -eq 0 ] \
            && [ "${FRAME_LINES[i]}" = "${PREV_LINES[i]:-}" ]; then
            continue
        fi
        printf -v pos '\e[%d;%dH' "$(( LAYOUT_ROW + i ))" "${LAYOUT_COL}"
        out+="${pos}${FRAME_LINES[i]}"
    done
    PREV_LINES=("${FRAME_LINES[@]}")
    RENDER_FULL=0
    if [ -n "${out}" ]; then
        screen_write "${out}"
    fi
    return 0
}

# draw_frame
# Render the complete game screen. Reads the game state globals (BOARD,
# BOARD_SQ, CUR_*, QUEUE, HOLD_TYPE, CLEARED_TOTAL, ROW_CREDIT, LEVEL,
# GOLD_COUNT, SILVER_COUNT, PLAY_MS, PAUSED, GAME_OVER, the WONDER_* state
# from lib/wonders.sh) and the USE_COLOR flag, assembles the block into
# FRAME_LINES and lets render_flush emit the difference.
draw_frame() {
    local i y vis line

    # Overlay the active piece; on the game over screen the piece that
    # failed to spawn is intentionally not drawn.
    OVERLAY=()
    OVERLAY_ROWS=()
    if [ "${GAME_OVER}" -eq 0 ]; then
        local -a cells
        local c cx cy
        IFS=' ' read -ra cells <<< "${PIECE_SHAPE["${CUR_TYPE}${CUR_ROT}"]}"
        for c in "${cells[@]}"; do
            cx="${c%,*}"
            cy="${c#*,}"
            OVERLAY["$(( CUR_X + cx )),$(( CUR_Y + cy ))"]="${CUR_TYPE}"
            OVERLAY_ROWS["$(( CUR_Y + cy ))"]=1
        done
    fi

    # Refill the settled-row cache after a board change (lock, line clear,
    # new round); otherwise every untouched row is reused as is.
    if [ "${BOARD_CACHE_VALID}" -eq 0 ]; then
        for (( y = HIDDEN_ROWS; y < BOARD_H; y++ )); do
            render_board_row "${y}" 0
            BOARD_ROW_CACHE[y]="${RENDER_ROW}"
        done
        BOARD_CACHE_VALID=1
    fi

    render_pane_left
    render_pane_right
    render_status_box
    render_status

    FRAME_LINES=()
    FRAME_LINES[BOARD_TOP_ROW]="${PANE_LEFT[0]} ${BOARD_BORDER} ${PANE_RIGHT[0]}"
    for (( i = 1; i <= BOARD_BOTTOM_ROW - 1; i++ )); do
        vis=$(( i - 1 ))
        y=$(( HIDDEN_ROWS + vis ))
        if [ -n "${BOX_LINES[${vis}]:-}" ]; then
            # Pause / game over box, drawn over the board.
            line="|${BOX_LINES[${vis}]}|"
        elif [ "${FLASH_STATE}" -eq 1 ] && [ -n "${FLASH_ROWS[${y}]:-}" ]; then
            # A row of the running clear animation, drawn fully
            # highlighted in the "on" half of the blink. Checked before
            # the active-piece overlay, so the piece that just completed
            # the row cannot paint over the highlight.
            line="|${FLASH_LINE}|"
        elif [ -n "${OVERLAY_ROWS[${y}]:-}" ]; then
            render_board_row "${y}" 1
            line="|${RENDER_ROW}|"
        else
            line="|${BOARD_ROW_CACHE[y]}|"
        fi
        FRAME_LINES[i]="${PANE_LEFT[i]} ${line} ${PANE_RIGHT[i]}"
    done
    FRAME_LINES[BOARD_BOTTOM_ROW]="${PANE_LEFT[BOARD_BOTTOM_ROW]} ${BOARD_BORDER} ${PANE_RIGHT[BOARD_BOTTOM_ROW]}"
    FRAME_LINES[STATUS_ROW_1]="${STATUS_1}"
    FRAME_LINES[STATUS_ROW_2]="${STATUS_2}"

    render_flush
    return 0
}
