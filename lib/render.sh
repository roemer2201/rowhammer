#!/usr/bin/env bash
#
# lib/render.sh
#
# Description:
#   Screen rendering for rowhammer. The game screen is one fixed block of
#   LAYOUT_W x LAYOUT_H characters, centered in the terminal (layout_update):
#   the hold piece sits at the top of the left pane with the round
#   counters (lines, rows, level, gold/silver, the rowhammers - four-row
#   clears -, the play time and the pieces placed) below it, the board in the middle and
#   the three upcoming pieces in the top right pane. The wonder progress
#   is not part of the HUD; it is shown on the "Weltwunder" screen
#   instead. In the Ultra game mode (since 0.19.0) two more counters
#   follow below: the run's row target and the rows still missing; the
#   Sprint mode (since 0.20.0) puts its time limit and the time left in
#   the same two slots, the Time Attack mode (since 0.22.0) the play
#   time its rows have bought so far and what is left of it, and the
#   Hochwasser mode (since 0.25.0) the interval between two flood rows
#   and the time until the next one. Pause
#   and game over are drawn as a box over the board, the latter with the
#   achieved highscore rank - or, for a finished Ultra run, with its time
#   and Ultra rank, resp. for a finished Sprint run with its rows and
#   Sprint rank, for an ended Time Attack run with its rows and Time
#   Attack rank and for a drowned Hochwasser round with its rows and
#   Hochwasser rank. During a demo playback (since 0.23.0, lib/demo.sh) the
#   pane carries the replay speed and the same box shows the end of the
#   recording, taking precedence over all of those because it has to
#   carry the keys of the replay.
#   Since 0.12.0 frames are no longer pushed out as a whole: draw_frame
#   builds the block into FRAME_LINES and render_flush emits only the lines
#   that actually changed since the previous frame, each with its own
#   cursor positioning. Settled board rows are cached (BOARD_ROW_CACHE) and
#   only rebuilt after the board really changed (render_board_dirty), so a
#   moving piece costs a handful of rows instead of all 200 cells. Every
#   line is built to exactly LAYOUT_W visible columns, which is what makes
#   the diff safe without per-line erase sequences. RENDER_FULL forces a
#   complete repaint (screen cleared first) after menus, resizes and at
#   round start. RENDER_MODE (--render-mode, since 0.21.0) can switch the
#   line diff off entirely: in "full" mode every frame rewrites all
#   LAYOUT_H lines, the behavior this renderer had before 0.12.0, as a
#   fallback for terminals or multiplexers that show the incremental
#   update incorrectly; "partial" stays the default.
#   Blocks are drawn with per-piece SGR sequences precomputed by
#   render_colors_init from the active color theme (COLOR_THEME,
#   lib/pieces.sh) for the resolved color mode: basic (8/16-color ANSI,
#   reverse video) or extended (xterm 256-color backgrounds); "auto"
#   detection lives in color_mode_resolve. The settings color picker
#   previews each theme via render_theme_swatch. In the no-color mode
#   every piece type instead draws its own two-character glyph
#   (PIECE_GLYPH, lib/pieces.sh) and the gold/silver squares use distinct
#   non-letter glyphs, so blocks stay tellable apart without color; the
#   flood rows of the Hochwasser mode carry their own glyph in both modes
#   (GARBAGE_GLYPH). All terminal output goes
#   through screen_write, which mirrors every update 1:1 into the frame log
#   when the debug mode is active (lib/debug.sh). Menus, info screens and
#   prompts (lib/menu.sh, lib/wonders.sh) hand their lines to
#   render_menu_frame, which places them centered like the game block
#   (since 0.17.0) instead of drawing them into the top left corner.
#   term_too_small_screen
#   draws the compact overlay shown while the terminal is smaller than the
#   fixed layout needs (since 0.10.0, driven by lib/input.sh on resize).
#   Rows about to be cleared can be drawn highlighted (FLASH_ROWS /
#   FLASH_STATE, since 0.11.0), which is what the clear animation in
#   rowhammer.sh toggles to make them blink.
#   render_colors_init also derives a small set of plain-text SGR colors
#   (TXT_GOLD_SGR, TXT_SILVER_SGR, TXT_ACCENT_SGR, TXT_WARN_SGR,
#   TXT_BOLD_SGR, TXT_RESET_SGR, since 0.18.0) from the same active theme,
#   for menu screens that color individual values instead of whole
#   blocks - currently the Highscores and Statistik screens
#   (highscore_screen in lib/highscore.sh, stats_screen in lib/stats.sh).
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.27.0  (2026-08-11)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/render.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# --- Layout geometry ------------------------------------------------------
# The game screen is a fixed block; only its position follows the terminal
# size. Widths add up exactly: pane + gap + board + gap + pane
# (12 + 1 + 22 + 1 + 12 = 48); the height is the board frame alone
# (20 rows plus two borders = 22).
# CHANGE 2026-07-28 (user decision): the two status lines below the
# board are gone - their counters moved into the left pane, where the
# key legend used to be. That shortens the block by two rows, which in
# turn lowers the minimum terminal height (MIN_TERM_* in rowhammer.sh)
# to 22; both dimensions still equal the minimum exactly, so the layout
# fits a bare 48x22 terminal.
LAYOUT_W=48
LAYOUT_H=22
PANE_W=12
# Rows of the block: 0 = board top border, 1..20 = the visible board,
# 21 = bottom border.
BOARD_TOP_ROW=0
BOARD_BOTTOM_ROW=21

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
GARBAGE_SGR=""
FLASH_SGR=""
RESET_SGR=$'\e[0m'
BOX_SGR=""

# Plain (non-block) foreground colors for menu text - the Highscores and
# Statistik screens (highscore_screen/stats_screen). Built from the same
# theme so a "gold"/"silver" reading in those tables always matches what
# the active theme paints gold/silver squares as, and so the colorblind
# theme's red/green avoidance carries over (TXT_WARN_SGR reuses the
# Z-piece color instead of a hardcoded red). Empty in --no-color/NO_COLOR
# mode (TXT_RESET_SGR included), so a colorless run emits no SGR bytes at
# all rather than a no-op reset.
TXT_GOLD_SGR=""
TXT_SILVER_SGR=""
TXT_ACCENT_SGR=""
TXT_WARN_SGR=""
TXT_BOLD_SGR=""
TXT_RESET_SGR=""

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

# Rendering mode (--render-mode / ROWHAMMER_RENDER_MODE, since 0.21.0):
# "partial" is the default and the reason the buffers above exist - only
# the changed lines go out. "full" turns the diff off and rewrites all
# LAYOUT_H lines on every frame, the way this renderer worked before
# 0.12.0. It exists as a compatibility fallback for terminals and
# multiplexers on which the incremental update draws incorrectly, and as
# a debugging aid when a frame log has to show whole frames.
# RENDER_MODE itself is owned by rowhammer.sh (defaults/env/CLI blocks)
# and only read here, exactly like COLOR_MODE. It deliberately gets no
# default of its own: the modules are sourced after the arguments are
# parsed, so an assignment here would overwrite the value the command
# line just set.

# Cache of the settled board rows (index = board y, content = the 20
# visible characters of that row without the active piece). Rebuilt only
# when the board itself changed, which is once per lock instead of once
# per frame.
declare -a BOARD_ROW_CACHE=()
BOARD_CACHE_VALID=0

# Pane buffers, rebuilt per frame by the helpers below.
declare -a PANE_LEFT=()
declare -a PANE_RIGHT=()
declare -A BOX_LINES=()

# Output of render_board_row / render_mini (globals instead of command
# substitution: the game loop must not fork a subshell per row).
RENDER_ROW=""
RENDER_MINI=""

# No-color (--no-color / NO_COLOR) glyphs for the gold/silver squares.
# Non-letter markers so a square never collides with a per-type piece
# glyph (PIECE_GLYPH, lib/pieces.sh) and gold reads denser than silver:
# without color these are the only cue that tells the two square kinds
# and the loose pieces apart.
SQ_GOLD_GLYPH="##"
SQ_SILVER_GLYPH="%%"

# Glyph of a flood row cell (the "Hochwasser" mode, GARBAGE_CELL in
# lib/board.sh). Unlike the pieces, this one is printed in the colored
# mode too: its theme color is grey in every theme (see THEME_COLOR),
# which the mono theme also gives the pieces, and a row that was never
# played but pushed in from below should be recognizable at a glance in
# any case. A non-letter marker like the two square glyphs, and a light
# one - the water is the thing the player did not build.
GARBAGE_GLYPH="::"

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
# Build the block SGR lookup for the active color theme (COLOR_THEME) and
# the resolved color mode. The theme (lib/pieces.sh) maps every piece type
# and the gold/silver squares to a symbolic color name; this turns those
# names into final SGR sequences. Basic mode keeps the classic look
# (reverse video on the 8-color foreground for pieces, black text on the
# matching background for squares); extended mode paints xterm 256-color
# backgrounds. Called at startup and again whenever the settings menu
# switches the theme, so a change takes effect immediately.
render_colors_init() {
    local t name gname sname xname x
    for t in "${PIECE_TYPES[@]}"; do
        name="${THEME_COLOR[${COLOR_THEME}:${t}]}"
        if [ "${COLOR_MODE}" = "extended" ]; then
            PIECE_SGR["${t}"]=$'\e[48;5;'"${COLOR_EXT[${name}]}m"
        else
            PIECE_SGR["${t}"]=$'\e[7;'"${COLOR_BASIC[${name}]}m"
        fi
    done
    gname="${THEME_COLOR[${COLOR_THEME}:GOLD]}"
    sname="${THEME_COLOR[${COLOR_THEME}:SILVER]}"
    # The flood rows of the "Hochwasser" mode are drawn like the squares -
    # dark glyph on the theme color - because they carry a glyph too
    # (GARBAGE_GLYPH, see there).
    xname="${THEME_COLOR[${COLOR_THEME}:GARBAGE]}"
    if [ "${COLOR_MODE}" = "extended" ]; then
        SQ_GOLD_SGR=$'\e[38;5;16;48;5;'"${COLOR_EXT[${gname}]}m"
        SQ_SILVER_SGR=$'\e[38;5;16;48;5;'"${COLOR_EXT[${sname}]}m"
        GARBAGE_SGR=$'\e[38;5;16;48;5;'"${COLOR_EXT[${xname}]}m"
        # Clear flash: the brightest white the palette offers, so a
        # flashing row clearly stands out from every block color.
        FLASH_SGR=$'\e[38;5;16;48;5;231m'
    else
        # Basic squares are black text on the color's background (fg + 10).
        # The array element is expanded before the arithmetic so the name
        # in gname/sname is used as the key, not evaluated as a variable.
        SQ_GOLD_SGR=$'\e[30;'"$(( ${COLOR_BASIC[${gname}]} + 10 ))m"
        SQ_SILVER_SGR=$'\e[30;'"$(( ${COLOR_BASIC[${sname}]} + 10 ))m"
        GARBAGE_SGR=$'\e[30;'"$(( ${COLOR_BASIC[${xname}]} + 10 ))m"
        FLASH_SGR=$'\e[1;30;47m'
    fi
    # The pause/game over box is drawn bold rather than colored, so it
    # stays readable on top of any block color and in --no-color mode.
    if [ "${USE_COLOR}" -eq 1 ]; then
        BOX_SGR=$'\e[1m'
    else
        BOX_SGR=""
    fi
    # Text colors for the Highscores/Statistik screens (see the TXT_*
    # globals above). iname/zname reuse the active theme's I- and
    # Z-piece colors as a neutral accent and a warning tone.
    local iname zname
    iname="${THEME_COLOR[${COLOR_THEME}:I]}"
    zname="${THEME_COLOR[${COLOR_THEME}:Z]}"
    if [ "${USE_COLOR}" -eq 1 ]; then
        if [ "${COLOR_MODE}" = "extended" ]; then
            TXT_GOLD_SGR=$'\e[38;5;'"${COLOR_EXT[${gname}]}m"
            TXT_SILVER_SGR=$'\e[38;5;'"${COLOR_EXT[${sname}]}m"
            TXT_ACCENT_SGR=$'\e[38;5;'"${COLOR_EXT[${iname}]}m"
            TXT_WARN_SGR=$'\e[38;5;'"${COLOR_EXT[${zname}]}m"
        else
            TXT_GOLD_SGR=$'\e['"${COLOR_BASIC[${gname}]}m"
            TXT_SILVER_SGR=$'\e['"${COLOR_BASIC[${sname}]}m"
            TXT_ACCENT_SGR=$'\e['"${COLOR_BASIC[${iname}]}m"
            TXT_WARN_SGR=$'\e['"${COLOR_BASIC[${zname}]}m"
        fi
        TXT_BOLD_SGR=$'\e[1m'
        TXT_RESET_SGR="${RESET_SGR}"
    else
        TXT_GOLD_SGR=""
        TXT_SILVER_SGR=""
        TXT_ACCENT_SGR=""
        TXT_WARN_SGR=""
        TXT_BOLD_SGR=""
        TXT_RESET_SGR=""
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
    # In a multiplayer round with the mini boards of the opponents shown
    # (detail level 2, see render_peer_level) the block is wider by their
    # columns, so the whole thing stays centered rather than the own board
    # sitting in the middle with the opponents hanging off to the right.
    # The menu screens keep centering on the bare LAYOUT_W: they are the
    # same screens the singleplayer shows and they have no peers.
    render_peer_level
    row=$(( (TERM_ROWS - LAYOUT_H) / 2 + 1 ))
    col=$(( (TERM_COLS - LAYOUT_W - MP_PEER_COLS) / 2 + 1 ))
    if [ "${row}" -lt 1 ]; then
        row=1
    fi
    if [ "${col}" -lt 1 ]; then
        col=1
    fi
    LAYOUT_ROW="${row}"
    LAYOUT_COL="${col}"
    RENDER_FULL=1
    # A resize invalidates the coordinates a menu frame was built from,
    # and the callers clear the screen right after this - the next menu
    # frame must start from scratch as well.
    MENU_FULL=1
    return 0
}

# --- Menu screen placement ------------------------------------------------
# Menus, info screens and prompts (lib/menu.sh, lib/wonders.sh) are placed
# by render_menu_frame, so they appear centered like the game block instead
# of clinging to the top left corner. Their left edge is the game block's
# left edge (same centering of LAYOUT_W), which is what makes a menu and
# the play screen look like the same screen; vertically each screen is
# centered on its own height, because menus differ in length.
#
# MENU_FULL marks that something other than a menu owns the screen (the
# game block in render_flush, the resize overlay in term_too_small_screen,
# a resize in layout_update - each sets the flag where it takes the screen
# over), so the next menu frame
# has to clear the terminal first. While one menu follows another, only the
# rows the previous block used and the new block no longer covers are
# erased - a full clear per key press would make the menu flicker while
# browsing it.
MENU_FULL=1
MENU_FRAME_ROW=1
MENU_FRAME_LINES=0
RENDER_MENU_FRAME=""

# render_menu_frame LINE...
# Compose a menu/info screen from the given lines and leave the ready made
# frame in RENDER_MENU_FRAME (a global, so no subshell is needed). Every
# line is positioned individually and closed with an erase-to-end-of-line,
# so a shorter line never leaves the tail of its predecessor behind. Lines
# may carry SGR sequences; their visible width is never measured, which is
# why the erase is per line instead of padding to a fixed width.
# Callers rebuild the frame instead of re-emitting a stored one after a
# resize - the coordinates computed here are only valid for the terminal
# size they were computed from.
render_menu_frame() {
    local -a lines=("$@")
    local n="${#lines[@]}"
    local row col i pos frame=""
    col=$(( (TERM_COLS - LAYOUT_W) / 2 + 1 ))
    if [ "${col}" -lt 1 ]; then
        col=1
    fi
    row=$(( (TERM_ROWS - n) / 2 + 1 ))
    if [ "${row}" -lt 1 ]; then
        row=1
    fi
    if [ "${MENU_FULL}" -eq 1 ]; then
        frame=$'\e[2J'
    else
        # Erase what the previous menu block wrote outside the new one;
        # the rows both blocks cover are overwritten below anyway.
        for (( i = MENU_FRAME_ROW; i < MENU_FRAME_ROW + MENU_FRAME_LINES; i++ )); do
            if (( i >= row && i < row + n )); then
                continue
            fi
            printf -v pos '\e[%d;1H' "${i}"
            frame+="${pos}"$'\e[2K'
        done
    fi
    for (( i = 0; i < n; i++ )); do
        printf -v pos '\e[%d;%dH' "$(( row + i ))" "${col}"
        frame+="${pos}${lines[i]}"$'\e[K'
    done
    MENU_FRAME_ROW="${row}"
    MENU_FRAME_LINES="${n}"
    MENU_FULL=0
    RENDER_MENU_FRAME="${frame}"
    return 0
}

# CHANGE 2026-08-03: render_menu_dirty, the helper that set MENU_FULL for
# a caller outside this file, is gone with its last caller. It existed for
# the player name prompt, which let the terminal echo the typed name onto
# the screen and had to declare the frame dirty afterwards; the prompt now
# draws the line itself inside a regular menu frame (menu_text_input,
# lib/menu.sh). The three places inside this file and lib/input.sh that
# take the screen over set MENU_FULL directly, as they always did.

# render_board_dirty
# Invalidate the settled-row cache. Called by every board mutation
# (lib/board.sh) so the next frame rebuilds the rows; the renderer owns
# the cache, the board module only reports that it changed.
render_board_dirty() {
    BOARD_CACHE_VALID=0
    return 0
}

# render_theme_swatch THEME
# Build a one-line color sample into the global RENDER_SWATCH: a two-cell
# block per piece type in that theme's color, then the gold and silver
# square looks. The settings color picker (menu_colors) shows one swatch
# per theme so the player sees each palette while browsing, without
# touching the active PIECE_SGR/SQ_* globals. Honors USE_COLOR and the
# resolved COLOR_MODE exactly like render_colors_init; with colors off it
# degrades to the piece letters.
render_theme_swatch() {
    local theme="${1}" t name gname sname
    if [ "${USE_COLOR}" -eq 0 ]; then
        RENDER_SWATCH="I O T S Z J L"
        return 0
    fi
    RENDER_SWATCH=""
    for t in "${PIECE_TYPES[@]}"; do
        name="${THEME_COLOR[${theme}:${t}]}"
        if [ "${COLOR_MODE}" = "extended" ]; then
            RENDER_SWATCH+=$'\e[48;5;'"${COLOR_EXT[${name}]}m""  ${RESET_SGR}"
        else
            RENDER_SWATCH+=$'\e[7;'"${COLOR_BASIC[${name}]}m""  ${RESET_SGR}"
        fi
    done
    gname="${THEME_COLOR[${theme}:GOLD]}"
    sname="${THEME_COLOR[${theme}:SILVER]}"
    if [ "${COLOR_MODE}" = "extended" ]; then
        RENDER_SWATCH+=$'\e[38;5;16;48;5;'"${COLOR_EXT[${gname}]}m""##${RESET_SGR}"
        RENDER_SWATCH+=$'\e[38;5;16;48;5;'"${COLOR_EXT[${sname}]}m""##${RESET_SGR}"
    else
        RENDER_SWATCH+=$'\e[30;'"$(( ${COLOR_BASIC[${gname}]} + 10 ))m""##${RESET_SGR}"
        RENDER_SWATCH+=$'\e[30;'"$(( ${COLOR_BASIC[${sname}]} + 10 ))m""##${RESET_SGR}"
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
    local need now
    printf -v need "${I18N[resize_need]}" "${MIN_TERM_COLS}" "${MIN_TERM_ROWS}"
    printf -v now "${I18N[resize_now]}" "${TERM_COLS}" "${TERM_ROWS}"
    printf -v frame '\e[2J\e[H%s\r\n%s\r\n%s\r\n%s' \
        "rowhammer" \
        "${I18N[resize_head]}" \
        "${need}" \
        "${now}"
    # The overlay owns the screen now; the menu that was interrupted has
    # to repaint on a cleared terminal once the resize is over.
    MENU_FULL=1
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
                RENDER_MINI+="${PIECE_GLYPH[${type}]}"
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
                s+="${PIECE_GLYPH[${cell}]}"
            fi
            continue
        fi
        idx=$(( y * BOARD_W + x ))
        cell="${BOARD[idx]}"
        if [ "${cell}" = "${EMPTY_CELL}" ]; then
            s+="  "
            continue
        fi
        # A flood row cell of the "Hochwasser" mode: never a piece and
        # never part of a square, so it is settled before the square
        # look is even looked at. It keeps its glyph in both color modes
        # (see GARBAGE_GLYPH).
        if [ "${cell}" = "${GARBAGE_CELL}" ]; then
            if [ "${USE_COLOR}" -eq 1 ]; then
                s+="${GARBAGE_SGR}${GARBAGE_GLYPH}${RESET_SGR}"
            else
                s+="${GARBAGE_GLYPH}"
            fi
            continue
        fi
        # Settled cell: gold/silver squares get their own look so they
        # stand out from normal pieces. With color the "##" glyph also
        # distinguishes gold from the yellow O; without color the squares
        # use distinct non-letter glyphs (## / %%) and every other piece
        # keeps its own per-type glyph (PIECE_GLYPH), so they all stay
        # tellable apart - in particular an S piece never looks like a
        # silver square.
        sq="${BOARD_SQ[idx]}"
        if [ "${sq}" = "G" ]; then
            if [ "${USE_COLOR}" -eq 1 ]; then
                s+="${SQ_GOLD_SGR}##${RESET_SGR}"
            else
                s+="${SQ_GOLD_GLYPH}"
            fi
        elif [ "${sq}" = "S" ]; then
            if [ "${USE_COLOR}" -eq 1 ]; then
                s+="${SQ_SILVER_SGR}##${RESET_SGR}"
            else
                s+="${SQ_SILVER_GLYPH}"
            fi
        elif [ "${USE_COLOR}" -eq 1 ]; then
            s+="${PIECE_SGR[${cell}]}  ${RESET_SGR}"
        else
            s+="${PIECE_GLYPH[${cell}]}"
        fi
    done
    RENDER_ROW="${s}"
    return 0
}

# pane_stat ROW LABEL VALUE
# Write one counter line of the left pane: LABEL left, VALUE right
# aligned. The pane's 12 columns are split 1 + 6 + 5 (indent, label,
# value), and the result is clamped to PANE_W afterwards, so even an
# implausibly long value can never push the line past the width the
# frame diff relies on (see render_flush).
pane_stat() {
    local line
    printf -v line ' %-6s%5s' "${2}" "${3}"
    printf -v line '%-*.*s' "${PANE_W}" "${PANE_W}" "${line}"
    PANE_LEFT["${1}"]="${line}"
    return 0
}

# render_pane_left
# Left pane: the hold slot on top, the round counters below it. Every
# entry is exactly PANE_W visible columns wide.
# CHANGE 2026-07-28 (user decision): the key legend gave up this pane to
# the counters, which moved here from the two status lines below the
# board - those lines are gone with them. The player name did not come
# along: names may be 16 characters long and the pane is 12 columns
# wide, so it could only ever have been shown as a stump, and the player
# knows their own name anyway.
render_pane_left() {
    local i line left
    PANE_LEFT=()
    for (( i = 0; i <= BOARD_BOTTOM_ROW; i++ )); do
        PANE_LEFT[i]="${PANE_BLANK}"
    done
    printf -v line '%-*.*s' "${PANE_W}" "${PANE_W}" " ${I18N[hud_hold]}"
    PANE_LEFT[0]="${line}"
    render_mini "${HOLD_TYPE}" 0
    PANE_LEFT[1]=" ${RENDER_MINI}   "
    render_mini "${HOLD_TYPE}" 1
    PANE_LEFT[2]=" ${RENDER_MINI}   "
    # "Lines" counts physical rows (drives the level), "Rows" is the
    # weighted credit (gold/silver bonus) that builds the wonders - and,
    # since the scoring rebuild, the round's score.
    pane_stat 4 "${I18N[hud_lines]}" "${CLEARED_TOTAL}"
    pane_stat 5 "${I18N[hud_rows]}" "${ROW_CREDIT}"
    pane_stat 6 "${I18N[hud_level]}" "${LEVEL}"
    pane_stat 8 "${I18N[hud_gold]}" "${GOLD_COUNT}"
    pane_stat 9 "${I18N[hud_silver]}" "${SILVER_COUNT}"
    # The move the game is named after: four rows cleared in one go.
    # "Hammer" is the label that fits the pane's six label columns.
    pane_stat 10 "${I18N[hud_hammer]}" "${ROWHAMMER_COUNT}"
    # Elapsed play time of the running round (paused time excluded), fed
    # by the game loop's PLAY_MS and formatted MM:SS (fmt_duration).
    fmt_duration $(( PLAY_MS / 1000 ))
    pane_stat 12 "${I18N[hud_time]}" "${FMT_DURATION}"
    # Pieces placed this round, right below the play time: the two
    # together are what the statistics and highscore screens turn into a
    # PCS/min rate. "Pieces" fills the pane's six label columns exactly.
    pane_stat 13 "${I18N[hud_pieces]}" "${PIECE_COUNT}"
    # Ultra mode (2026-07-31): the run's target and how far it still is,
    # so the player never has to do that arithmetic mid-round. Only in
    # that mode - a normal round has no goal, and the free rows below
    # stay free for whatever comes next (see CLAUDE.md 3.4). "Left" is
    # the interesting half and therefore the lower, more visible line;
    # both labels fit the pane's six label columns.
    # Sprint mode (2026-08-03) uses the same two lines for the same two
    # questions, only about its time limit instead of a row target: the
    # goal is the three minutes, "Left" the time still to play. The
    # modes never run at once, so sharing the slots costs nothing and
    # keeps both goal counters in the place a player learns once.
    if [ "${GAME_MODE}" = "ultra" ]; then
        pane_stat 15 "${I18N[hud_goal]}" "${ULTRA_TARGET_ROWS}"
        left=$(( ULTRA_TARGET_ROWS - ROW_CREDIT ))
        if [ "${left}" -lt 0 ]; then
            # The last clear usually overshoots the target; showing a
            # negative remainder would be noise on the finished run.
            left=0
        fi
        pane_stat 16 "${I18N[hud_left]}" "${left}"
    elif [ "${GAME_MODE}" = "sprint" ]; then
        fmt_duration $(( SPRINT_TIME_MS / 1000 ))
        pane_stat 15 "${I18N[hud_goal]}" "${FMT_DURATION}"
        left=$(( SPRINT_TIME_MS - PLAY_MS ))
        if [ "${left}" -lt 0 ]; then
            # The loop notices the timeout a tick late at the most, so
            # the finished run would otherwise show a negative rest.
            left=0
        fi
        # Rounded up to the next whole second: the run is over when the
        # display hits 00:00, and truncating would show that for the
        # last second of play.
        fmt_duration $(( (left + 999) / 1000 ))
        pane_stat 16 "${I18N[hud_left]}" "${FMT_DURATION}"
    elif [ "${GAME_MODE}" = "timeattack" ]; then
        # Time Attack (2026-08-03) reads like Sprint, with one
        # difference that is the whole mode: its "Goal" is not a
        # constant. It is the play time the run has bought itself so far
        # (start time plus a second per row of credit, see
        # time_attack_budget), so the line grows as the round goes and
        # the player can see what a clear was worth in time. "Left" is
        # the countdown against it, rounded up like Sprint's for the
        # same reason. The budget is recomputed here rather than read as
        # the game loop left it: a clear happens after the loop refreshed
        # it, so the frame drawn in that same tick would otherwise show
        # the previous budget for one frame - on the very tick the
        # player is looking to see what the clear bought.
        time_attack_budget
        fmt_duration $(( TIME_ATTACK_BUDGET_MS / 1000 ))
        pane_stat 15 "${I18N[hud_goal]}" "${FMT_DURATION}"
        left=$(( TIME_ATTACK_BUDGET_MS - PLAY_MS ))
        if [ "${left}" -lt 0 ]; then
            left=0
        fi
        fmt_duration $(( (left + 999) / 1000 ))
        pane_stat 16 "${I18N[hud_left]}" "${FMT_DURATION}"
    elif [ "${GAME_MODE}" = "versus" ]; then
        # A multiplayer round shows what its mode is played for, in the
        # same two rows every timed mode uses (they never run at once):
        # the Sprint variant its time limit and the time left, the Ultra
        # variant its row target and the rows still missing. The survival
        # variant has no goal and leaves them empty, exactly as Marathon
        # does.
        if [ "${MP_MODE}" = "sprint" ]; then
            fmt_duration $(( SPRINT_TIME_MS / 1000 ))
            pane_stat 15 "${I18N[hud_goal]}" "${FMT_DURATION}"
            left=$(( SPRINT_TIME_MS - PLAY_MS ))
            if [ "${left}" -lt 0 ]; then
                # The hub's clock is the one that ends the round, and it
                # may be a tick behind this display; a negative rest would
                # only look broken.
                left=0
            fi
            fmt_duration $(( (left + 999) / 1000 ))
            pane_stat 16 "${I18N[hud_left]}" "${FMT_DURATION}"
        elif [ "${MP_MODE}" = "ultra" ]; then
            pane_stat 15 "${I18N[hud_goal]}" "${ULTRA_TARGET_ROWS}"
            left=$(( ULTRA_TARGET_ROWS - ROW_CREDIT ))
            if [ "${left}" -lt 0 ]; then
                left=0
            fi
            pane_stat 16 "${I18N[hud_left]}" "${left}"
        fi
        # The garbage rows on their way in - the one number a player has
        # to plan around - and the players still standing. The garbage row
        # only exists while garbage is switched on: a counter that is
        # permanently zero teaches a player to ignore the place it stands
        # in, which is the place they have to look at in a round where it
        # is on.
        if [ "${MP_GARBAGE}" -eq 1 ]; then
            pane_stat 17 "${I18N[hud_garbage]}" "${MP_PENDING}"
        fi
        mp_alive_count
        pane_stat 18 "${I18N[hud_alive]}" "${MP_ALIVE}"
    elif [ "${GAME_MODE}" = "flood" ]; then
        # Hochwasser (2026-08-04): the same two lines once more, this
        # time about the water. The upper one is the interval between two
        # rises (FLOOD_INTERVAL_MS, a constant like Sprint's limit), the
        # lower one the time until the next row comes in - rounded up
        # like the other countdowns, so 00:00 never stands there while
        # the round still has a moment left. It is not a goal, so it gets
        # a label of its own instead of Ultra's "Ziel"; "Rest" fits the
        # remaining time here as well as it does there.
        fmt_duration $(( FLOOD_INTERVAL_MS / 1000 ))
        pane_stat 15 "${I18N[hud_flood]}" "${FMT_DURATION}"
        left=$(( FLOOD_NEXT_MS - PLAY_MS ))
        if [ "${left}" -lt 0 ]; then
            left=0
        fi
        fmt_duration $(( (left + 999) / 1000 ))
        pane_stat 16 "${I18N[hud_left]}" "${FMT_DURATION}"
    fi
    # Demo playback (2026-08-03): the replay speed, on one of the pane's
    # free rows (see CLAUDE.md 3.4). It is the only thing about a replay
    # that is not visible from the board itself - that it is a replay at
    # all is what the "Demo" label says, and the paused state reuses the
    # box over the board. Row 18, two rows below the goal counters, so a
    # replayed Ultra or Sprint run keeps showing its own two lines.
    if [ "${DEMO_PLAYING}" -eq 1 ]; then
        pane_stat 18 "${I18N[hud_demo]}" "${DEMO_SPEED_LABEL}"
    fi
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
    printf -v line '%-*.*s' "${PANE_W}" "${PANE_W}" " ${I18N[hud_next]}"
    PANE_RIGHT[0]="${line}"
    for (( q = 0; q < PREVIEW_COUNT; q++ )); do
        render_mini "${QUEUE[q]:-}" 0
        PANE_RIGHT[1 + q * 3]=" ${RENDER_MINI}   "
        render_mini "${QUEUE[q]:-}" 1
        PANE_RIGHT[2 + q * 3]=" ${RENDER_MINI}   "
    done
    # In a multiplayer round without room for the mini boards the
    # opponents live in the free rows below the previews (detail level 1
    # and 0, see render_pane_peers). That is what lets a duel run in the
    # bare 48x22 the singleplayer needs.
    if [ "${MP_ACTIVE:-0}" -eq 1 ] && [ "${MP_VIEW_LEVEL}" -lt 2 ]; then
        render_pane_peers
    fi
    return 0
}

# render_status_box
# Build the pause / game over box drawn over the board, keyed by visible
# board row (0..19). Empty when the round is running. Putting it on the
# board instead of into a sidebar keeps the message where the player is
# looking and costs no permanent screen space.
# Interior lines are 18 characters wide between the borders, so every
# entry is exactly the board's 20 visible columns.
render_status_box() {
    local i line played
    BOX_LINES=()
    # A finished demo takes the box before anything else, even when the
    # replayed round ended in a real top-out (which sets GAME_OVER while
    # the replay runs): the box has to carry the keys of the replay, and
    # "r = restart" would otherwise read as restarting the round. It uses
    # the same eight body lines as the game over box below, so the
    # borders sit in the same place either way.
    if [ "${DEMO_PLAYING}" -eq 1 ] && [ "${DEMO_ENDED}" -eq 1 ]; then
        local -a demo_body=("")
        demo_body+=("${I18N[box_demo_end]}")
        printf -v line "${I18N[box_rows]}" "${ROW_CREDIT}"
        demo_body+=("${line}")
        fmt_duration $(( PLAY_MS / 1000 ))
        printf -v line "${I18N[box_time]}" "${FMT_DURATION}"
        demo_body+=("${line}")
        # How the recorded round ended, which the counters alone do not
        # say: a top-out, a reached goal or a round left from the menu.
        case "${DEMO_HDR_END}" in
            over) demo_body+=("${I18N[box_end_over]}") ;;
            goal) demo_body+=("${I18N[box_end_goal]}") ;;
            *)    demo_body+=("${I18N[box_end_quit]}") ;;
        esac
        demo_body+=("${I18N[box_demo_again]}")
        printf -v line "${I18N[box_demo_back]}" "${KEY_QUIT}"
        demo_body+=("${line}")
        demo_body+=("")
        BOX_LINES[6]="${BOX_SGR}+------------------+${RESET_SGR}"
        for (( i = 0; i < ${#demo_body[@]}; i++ )); do
            printf -v line '|%-18.18s|' "${demo_body[i]}"
            BOX_LINES["$(( 7 + i ))"]="${BOX_SGR}${line}${RESET_SGR}"
        done
        BOX_LINES[15]="${BOX_SGR}+------------------+${RESET_SGR}"
        return 0
    fi
    # A multiplayer round has two endings of its own and they come one
    # after the other: this player is knocked out and watches on, and then
    # the round is decided for everybody. Both take the box before the
    # singleplayer endings below, because the round is not over when this
    # player's board is full - it is over when the hub says so.
    if [ "${MP_ACTIVE:-0}" -eq 1 ] \
        && { [ "${MP_ENDED}" -eq 1 ] || [ "${GAME_OVER}" -eq 1 ]; }; then
        local -a mp_body=("")
        if [ "${MP_ENDED}" -eq 1 ]; then
            if [ "${MP_PLACE}" -eq 1 ]; then
                mp_body+=("${I18N[box_mp_win]}")
            else
                mp_body+=("${I18N[box_mp_over]}")
            fi
            printf -v line "${I18N[box_mp_place]}" "${MP_PLACE}"
            mp_body+=("${line}")
            printf -v line "${I18N[box_rows]}" "${ROW_CREDIT}"
            mp_body+=("${line}")
            if [ "${HSV_LAST_RANK}" -gt 0 ]; then
                printf -v line "${I18N[box_rank]}" \
                    "${I18N[mode_versus]}" "${HSV_LAST_RANK}"
                mp_body+=("${line}")
            else
                mp_body+=("")
            fi
        else
            # Knocked out while the others play on: a spectator, not a
            # finished round. No restart key here - a new round means a
            # new session (see mp_round in lib/mp.sh).
            mp_body+=("${I18N[box_mp_ko]}")
            printf -v line "${I18N[box_mp_place]}" "${MP_PLACE}"
            mp_body+=("${line}")
            printf -v line "${I18N[box_rows]}" "${ROW_CREDIT}"
            mp_body+=("${line}")
            mp_body+=("${I18N[box_mp_watch]}")
        fi
        mp_body+=("")
        printf -v line "${I18N[box_menu]}" "${KEY_QUIT}"
        mp_body+=("${line}")
        mp_body+=("")
        BOX_LINES[6]="${BOX_SGR}+------------------+${RESET_SGR}"
        for (( i = 0; i < ${#mp_body[@]}; i++ )); do
            printf -v line '|%-18.18s|' "${mp_body[i]}"
            BOX_LINES["$(( 7 + i ))"]="${BOX_SGR}${line}${RESET_SGR}"
        done
        BOX_LINES[15]="${BOX_SGR}+------------------+${RESET_SGR}"
        return 0
    fi
    if [ "${GAME_OVER}" -eq 1 ]; then
        local -a body=()
        body+=("")
        # Several endings share this box, and all of them fill the same
        # eight body lines so the borders stay put: the timed modes
        # each have a finished and a failed variant (the result takes the
        # headline's neighbouring line; a failed Ultra or Sprint run gets
        # no rank - it is not recorded, so it shows how far it got
        # instead), while the endless round and Hochwasser have their
        # classic game over.
        case "${GAME_MODE}" in
            ultra)
                if [ "${GOAL_REACHED}" -eq 1 ]; then
                    body+=("${I18N[box_ultra_clear]}")
                    fmt_duration_ms "${PLAY_MS}"
                    printf -v line "${I18N[box_time]}" "${FMT_DURATION_MS}"
                    body+=("${line}")
                    # The run was recorded when the goal triggered
                    # (record_round), so HSU_LAST_RANK is its rank in the
                    # Ultra list.
                    if [ "${HSU_LAST_RANK}" -gt 0 ]; then
                        printf -v line "${I18N[box_rank]}" \
                            "${I18N[mode_ultra]}" "${HSU_LAST_RANK}"
                        body+=("${line}")
                    else
                        body+=("")
                    fi
                else
                    body+=("${I18N[box_game_over]}")
                    body+=("")
                    printf -v line "${I18N[box_rows_goal]}" \
                        "${ROW_CREDIT}" "${ULTRA_TARGET_ROWS}"
                    body+=("${line}")
                fi
                ;;
            sprint)
                if [ "${GOAL_REACHED}" -eq 1 ]; then
                    # Time is up: here the row credit is the result, the
                    # mirror image of the Ultra box above.
                    body+=("${I18N[box_sprint_end]}")
                    printf -v line "${I18N[box_rows]}" "${ROW_CREDIT}"
                    body+=("${line}")
                    if [ "${HSS_LAST_RANK}" -gt 0 ]; then
                        printf -v line "${I18N[box_rank]}" \
                            "${I18N[mode_sprint]}" "${HSS_LAST_RANK}"
                        body+=("${line}")
                    else
                        body+=("")
                    fi
                else
                    # Topped out before the time was up: the rows are on
                    # screen anyway, so the line that matters is how much
                    # of the three minutes the run got to use.
                    body+=("${I18N[box_game_over]}")
                    body+=("")
                    fmt_duration $(( PLAY_MS / 1000 ))
                    played="${FMT_DURATION}"
                    fmt_duration $(( SPRINT_TIME_MS / 1000 ))
                    printf -v line "${I18N[box_time_goal]}" \
                        "${played}" "${FMT_DURATION}"
                    body+=("${line}")
                fi
                ;;
            timeattack)
                # Both endings of a Time Attack run are recorded (see
                # record_round), so both carry a rank; the headline is
                # what tells them apart - the clock ran out, or the
                # stack did. The result is the rows in either case.
                if [ "${GOAL_REACHED}" -eq 1 ]; then
                    body+=("${I18N[box_time_up]}")
                else
                    body+=("${I18N[box_game_over]}")
                fi
                printf -v line "${I18N[box_rows]}" "${ROW_CREDIT}"
                body+=("${line}")
                if [ "${HSA_LAST_RANK}" -gt 0 ]; then
                    printf -v line "${I18N[box_rank]}" \
                        "${I18N[mode_timeattack]}" "${HSA_LAST_RANK}"
                    body+=("${line}")
                else
                    body+=("")
                fi
                ;;
            flood)
                # Hochwasser has the single ending Marathon has - the
                # water always wins in the end, and there is nothing to
                # reach - but a list of its own, so the rank names it.
                # The rows take the line a failed timed run uses for its
                # progress: they are what a round under a rising floor
                # is measured by, and unlike Marathon this mode is short
                # enough that the number is the story of the round.
                body+=("${I18N[box_game_over]}")
                printf -v line "${I18N[box_rows]}" "${ROW_CREDIT}"
                body+=("${line}")
                if [ "${HSF_LAST_RANK}" -gt 0 ]; then
                    printf -v line "${I18N[box_rank]}" \
                        "${I18N[mode_flood]}" "${HSF_LAST_RANK}"
                    body+=("${line}")
                else
                    body+=("")
                fi
                ;;
            *)
                body+=("${I18N[box_game_over]}")
                body+=("")
                # The finished round was recorded when the game over
                # triggered (record_round), so HS_LAST_RANK is this
                # round's rank.
                if [ "${HS_LAST_RANK}" -gt 0 ]; then
                    printf -v line "${I18N[box_rank_marathon]}" \
                        "${HS_LAST_RANK}"
                    body+=("${line}")
                else
                    body+=("")
                fi
                ;;
        esac
        body+=("")
        body+=("${I18N[box_restart]}")
        printf -v line "${I18N[box_menu]}" "${KEY_QUIT}"
        body+=("${line}")
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
        BOX_LINES[10]="${BOX_SGR}|${I18N[box_paused]}|${RESET_SGR}"
        BOX_LINES[11]="${BOX_SGR}+------------------+${RESET_SGR}"
    fi
    return 0
}

# --- Multiplayer: the opponents -------------------------------------------
# Three detail levels (CLAUDE.md 5.6), picked from the terminal size and
# the number of opponents and recomputed on every resize:
#   2 "full"    - a mini board per opponent, one character per cell, in
#                 columns to the right of the play screen.
#   1 "compact" - two lines per opponent in the right pane: name and rows,
#                 and a bar for the height of their stack.
#   0 "score"   - one line per opponent: place, name, rows.
# Levels 1 and 0 cost no width at all - they use the rows the right pane
# has free below the three previews - which is what makes them the answer
# for a 48x22 terminal with five opponents.
# A mini board is 10 cells wide plus its two borders plus one column of
# air, i.e. 13 columns per opponent; MP_PEER_COLS is what that adds up to
# and is 0 in every other case, including the whole singleplayer.
MP_PEER_COL_W=13
MP_PEER_COLS=0
MP_VIEW_LEVEL=0
declare -a PEER_LINES=()
# The first pane row the opponents may use: below the three previews of
# the "Next" pane, with one blank row between.
PEER_PANE_ROW=11

# render_peer_level
# Decide the detail level for the current terminal and opponent count and
# leave it in MP_VIEW_LEVEL, with the extra width in MP_PEER_COLS. Called
# from layout_update (i.e. at every resize) and once per frame, so the
# level follows the terminal while the round runs.
# --mp-view forces a level; "auto" takes the widest one that fits.
render_peer_level() {
    local want
    MP_PEER_COLS=0
    MP_VIEW_LEVEL=0
    if [ "${MP_ACTIVE:-0}" -ne 1 ]; then
        return 0
    fi
    mp_peer_count
    if [ "${MP_PEER_COUNT}" -eq 0 ]; then
        return 0
    fi
    case "${MP_VIEW}" in
        full)    want=2 ;;
        compact) want=1 ;;
        score)   want=0 ;;
        *)
            want=0
            if (( TERM_COLS >= LAYOUT_W + MP_PEER_COUNT * MP_PEER_COL_W )); then
                want=2
            elif (( PEER_PANE_ROW + 2 * MP_PEER_COUNT <= BOARD_BOTTOM_ROW + 1 )); then
                want=1
            fi
            ;;
    esac
    # A forced level that does not fit is not honored: a mini board that
    # runs off the screen would tear the frame diff apart, which is the
    # one thing the fixed line width may never do.
    if [ "${want}" -eq 2 ] \
        && (( TERM_COLS < LAYOUT_W + MP_PEER_COUNT * MP_PEER_COL_W )); then
        want=1
    fi
    if [ "${want}" -eq 1 ] \
        && (( PEER_PANE_ROW + 2 * MP_PEER_COUNT > BOARD_BOTTOM_ROW + 1 )); then
        want=0
    fi
    MP_VIEW_LEVEL="${want}"
    if [ "${want}" -eq 2 ]; then
        MP_PEER_COLS=$(( MP_PEER_COUNT * MP_PEER_COL_W ))
    fi
    # The hub has to know whether anybody is looking at the boards: it
    # only asks for snapshots while somebody is (CLAUDE.md 5.6). Reported
    # from here because this is where the answer is decided, and only
    # when it changed - mp_send_view keeps that check.
    mp_send_view "${want}"
    return 0
}

# render_peer_cell CHAR
# One cell of an opponent's board as a single character, into
# RENDER_PEER_CELL. The snapshot alphabet is the protocol's (lib/proto.sh):
# "." empty, a piece type letter, "g"/"s" for a gold/silver square cell,
# "x" for garbage. With color a square keeps its own glyph as well, so the
# two square kinds stay apart at a glance on a board this small.
RENDER_PEER_CELL=" "
render_peer_cell() {
    local c="${1}"
    case "${c}" in
        g)
            if [ "${USE_COLOR}" -eq 1 ]; then
                RENDER_PEER_CELL="${SQ_GOLD_SGR}#${RESET_SGR}"
            else
                RENDER_PEER_CELL="#"
            fi
            ;;
        s)
            if [ "${USE_COLOR}" -eq 1 ]; then
                RENDER_PEER_CELL="${SQ_SILVER_SGR}%${RESET_SGR}"
            else
                RENDER_PEER_CELL="%"
            fi
            ;;
        x)
            if [ "${USE_COLOR}" -eq 1 ]; then
                RENDER_PEER_CELL="${GARBAGE_SGR}:${RESET_SGR}"
            else
                RENDER_PEER_CELL=":"
            fi
            ;;
        I|O|T|S|Z|J|L)
            if [ "${USE_COLOR}" -eq 1 ]; then
                RENDER_PEER_CELL="${PIECE_SGR[${c}]} ${RESET_SGR}"
            else
                RENDER_PEER_CELL="${c}"
            fi
            ;;
        *)
            RENDER_PEER_CELL=" "
            ;;
    esac
    return 0
}

# render_peers
# Build the mini board columns of detail level 2 into PEER_LINES, one
# entry per row of the block (0..LAYOUT_H-1), each exactly MP_PEER_COLS
# visible columns wide. Row 0 carries the name, rows 1..20 the board,
# row 21 the rows scored and the garbage on its way in.
# Every value is clamped here a second time although it came through the
# protocol parser: the hub is not trusted either - it could be a program
# somebody else wrote (CLAUDE.md 5.5).
render_peers() {
    local i r slot board line cell name row_line head foot
    for (( r = 0; r < LAYOUT_H; r++ )); do
        PEER_LINES[r]=""
    done
    for (( i = 0; i < MP_PEER_COUNT; i++ )); do
        slot="${MP_PEER_SLOTS[i]}"
        board="${MP_PEER_BOARD[slot]}"
        name="${MP_PEER_NAME[slot]:0:12}"
        printf -v head '%-12.12s' "${name}"
        PEER_LINES[0]+=" ${TXT_ACCENT_SGR}${head}${TXT_RESET_SGR}"
        for (( r = 0; r < 20; r++ )); do
            line=""
            for (( cell = 0; cell < BOARD_W; cell++ )); do
                if [ "${#board}" -eq 200 ]; then
                    render_peer_cell "${board:r * BOARD_W + cell:1}"
                else
                    RENDER_PEER_CELL=" "
                fi
                line+="${RENDER_PEER_CELL}"
            done
            PEER_LINES[r + 1]+=" |${line}|"
        done
        # A player who is out is named by their place instead of by the
        # garbage on its way to them: that is what became of them, and it
        # is what the final screen ranks them by.
        case "${MP_PEER_STATE[slot]}" in
            ko|gone)
                printf -v foot '%s %d' "${I18N[hud_peer_ko]}" \
                    "${MP_PEER_PLACE[slot]:-0}"
                ;;
            *)
                if [ "${MP_PEER_PENDING[slot]}" -gt 0 ]; then
                    printf -v foot 'R%-4s %s%d' "${MP_PEER_ROWS[slot]}" \
                        "${I18N[hud_peer_warn]}" "${MP_PEER_PENDING[slot]}"
                else
                    printf -v foot 'R%-4s' "${MP_PEER_ROWS[slot]}"
                fi
                ;;
        esac
        # Hard clamp: the frame diff relies on every line being exactly
        # as wide as it says it is.
        printf -v foot '%-12.12s' "${foot}"
        PEER_LINES[BOARD_BOTTOM_ROW]+=" ${foot}"
    done
    # Rows the loop above did not touch (there are none in level 2, since
    # every row of the block carries something) still have to exist as
    # blanks of the right width.
    for (( r = 0; r < LAYOUT_H; r++ )); do
        if [ -z "${PEER_LINES[r]}" ]; then
            printf -v row_line '%*s' "${MP_PEER_COLS}" ""
            PEER_LINES[r]="${row_line}"
        fi
    done
    return 0
}

# render_pane_peers
# Detail levels 1 and 0: the opponents in the free rows of the right pane,
# which costs no width at all. Level 1 gives each of them two lines - name
# with rows, and a bar for the height of their stack with the garbage on
# its way in - level 0 one line with place, name and rows.
render_pane_peers() {
    local i slot row line name bar filled b
    row="${PEER_PANE_ROW}"
    for (( i = 0; i < MP_PEER_COUNT; i++ )); do
        slot="${MP_PEER_SLOTS[i]}"
        name="${MP_PEER_NAME[slot]:0:7}"
        if [ "${MP_VIEW_LEVEL}" -eq 0 ]; then
            printf -v line '%d.%-7s%3s' "${MP_PEER_PLACE[slot]:-0}" \
                "${name}" "${MP_PEER_ROWS[slot]}"
            printf -v line '%-*.*s' "${PANE_W}" "${PANE_W}" "${line}"
            PANE_RIGHT[row]="${line}"
            row=$(( row + 1 ))
            continue
        fi
        printf -v line '%-8s%4s' "${name}" "${MP_PEER_ROWS[slot]}"
        printf -v line '%-*.*s' "${PANE_W}" "${PANE_W}" "${line}"
        PANE_RIGHT[row]="${line}"
        case "${MP_PEER_STATE[slot]}" in
            ko|gone)
                printf -v line ' %-11s' "${I18N[hud_peer_ko]}"
                ;;
            *)
                # Ten characters of bar for twenty rows of board, so one
                # character is two rows of stack - rounded up, so a stack
                # that exists at all is visible.
                filled=$(( ( ${MP_PEER_HEIGHT[slot]} + 1 ) / 2 ))
                if [ "${filled}" -gt 10 ]; then
                    filled=10
                fi
                bar=""
                for (( b = 0; b < 10; b++ )); do
                    if [ "${b}" -lt "${filled}" ]; then
                        bar+="#"
                    else
                        bar+="."
                    fi
                done
                if [ "${MP_PEER_PENDING[slot]}" -gt 0 ]; then
                    # The warning that matters most on an opponent line:
                    # rows are on their way to them.
                    printf -v line ' %s%s' "${bar}" \
                        "${I18N[hud_peer_warn]}"
                else
                    printf -v line ' %s ' "${bar}"
                fi
                ;;
        esac
        printf -v line '%-*.*s' "${PANE_W}" "${PANE_W}" "${line}"
        PANE_RIGHT[row + 1]="${line}"
        row=$(( row + 2 ))
    done
    return 0
}

# render_flush
# Push FRAME_LINES to the terminal: on a full repaint clear the screen and
# write every line, otherwise only the lines that differ from the previous
# frame, each preceded by its own cursor positioning. Because every line is
# built to exactly LAYOUT_W visible columns, a changed line always fully
# covers its predecessor - no erase sequences needed. Nothing is written at
# all when the frame is identical to the last one.
# In RENDER_MODE=full the diff is skipped and every line is written on
# every frame. The two conditions are deliberately kept apart: the screen
# is still cleared only when RENDER_FULL says so (menu, resize, round
# start), not once per frame. Holding RENDER_FULL at 1 permanently - the
# shorter route the roadmap sketched - would send \e[2J with every frame
# and make the fallback mode flicker, which is the opposite of what a
# compatibility fallback is for.
render_flush() {
    local out="" i pos write_all
    write_all="${RENDER_FULL}"
    if [ "${RENDER_MODE}" = "full" ]; then
        write_all=1
    fi
    if [ "${RENDER_FULL}" -eq 1 ]; then
        out=$'\e[2J'
        PREV_LINES=()
    fi
    for (( i = 0; i < LAYOUT_H; i++ )); do
        if [ "${write_all}" -eq 0 ] \
            && [ "${FRAME_LINES[i]}" = "${PREV_LINES[i]:-}" ]; then
            continue
        fi
        printf -v pos '\e[%d;%dH' "$(( LAYOUT_ROW + i ))" "${LAYOUT_COL}"
        out+="${pos}${FRAME_LINES[i]}"
    done
    PREV_LINES=("${FRAME_LINES[@]}")
    RENDER_FULL=0
    if [ -n "${out}" ]; then
        # The game block now owns the screen: a menu opened from here
        # (pause menu, game over follow-ups) has to clear it first.
        MENU_FULL=1
        screen_write "${out}"
    fi
    return 0
}

# draw_frame
# Render the complete game screen. Reads the game state globals (BOARD,
# BOARD_SQ, CUR_*, QUEUE, HOLD_TYPE, CLEARED_TOTAL, ROW_CREDIT, LEVEL,
# GOLD_COUNT, SILVER_COUNT, ROWHAMMER_COUNT, PIECE_COUNT, PLAY_MS,
# PAUSED, GAME_OVER, GAME_MODE, GOAL_REACHED)
# and the USE_COLOR flag, assembles the block into
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

    # The detail level of the opponents follows the terminal, so it is
    # decided per frame and not only on a resize; it also decides how wide
    # every line of this frame is going to be, which is why it comes
    # before the panes are built.
    render_peer_level
    if [ "${MP_ACTIVE:-0}" -eq 1 ] && [ "${MP_VIEW_LEVEL}" -eq 2 ]; then
        render_peers
    fi

    render_pane_left
    render_pane_right
    render_status_box

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

    # The opponents' mini boards are appended to every line of the block,
    # each of them exactly MP_PEER_COLS visible columns wide - which is
    # what keeps the line diff in render_flush safe.
    if [ "${MP_PEER_COLS}" -gt 0 ]; then
        for (( i = 0; i < LAYOUT_H; i++ )); do
            FRAME_LINES[i]+="${PEER_LINES[i]}"
        done
    fi

    render_flush
    return 0
}
