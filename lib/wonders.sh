#!/usr/bin/env bash
#
# lib/wonders.sh
#
# Description:
#   Wonder construction for rowhammer, modeled after the Wonders mode of
#   The New Tetris (N64): the all-time weighted row credit
#   (TOTAL_ROW_CREDIT from lib/save.sh) builds a fixed sequence of seven
#   world wonders, one after the other. Each wonder is stored as one
#   ASCII art file in assets/wonders/; its build stages are derived by
#   revealing the art bottom-up in proportion to the rows invested, so
#   an art file with 12 lines yields 12 build stages without duplicated
#   assets. wonders_update computes the current wonder, stage and
#   percentage into WONDER_* globals (read by the HUD in lib/render.sh);
#   wonder_screen renders the construction site screen shown after every
#   round and from the wonders main menu entry and, since 0.5.0, pages
#   back through the wonders already finished with the left/right keys
#   (wonder_screen_lines builds one such screen); its wait loop
#   repaints on REDRAW_PENDING so a terminal resize (handled in read_key)
#   does not leave it blank (since 0.1.1). Like the menus, the screen is
#   handed to render_menu_frame (lib/render.sh) since 0.2.0, so it appears
#   centered like the play screen and starts on a cleared terminal - the
#   explicit \e[H\e[K it used to carry against a bleeding-through first
#   line is part of that helper now. Wonder names,
#   sequence and row costs live in the tables below; costs double per
#   wonder like the roughly geometric line requirements of the original
#   and are, since 0.3.0, in its order of magnitude as well.
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.5.0  (2026-08-04)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/wonders.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# The wonder sequence; both tables share the same index. Structures
# verified against the original where sources allowed (Mayan temple,
# Stonehenge, Sphinx, Pantheon and St Basil's Cathedral appear in The
# New Tetris); Great Wall and Taj Mahal fill the remaining slots.
# WONDER_COSTS holds the weighted rows needed to finish each single
# wonder (not cumulative); adjust here to tune the pacing.
# CHANGE 2026-08-04: the two name tables that used to sit here (a German
# one for the screen, an English one for the debug log) are gone. A
# wonder's display name is a translated text like every other one now
# (wonder_name below); the file name is what identifies a wonder in the
# code and in the logs, and it is the same in every language.
WONDER_FILES=(mayan-temple stonehenge sphinx pantheon
              great-wall taj-mahal st-basils)
# CHANGE 2026-08-03 (0.44.0, user decision): every cost multiplied by 100
# (100..6400 -> 10000..640000, 12.700 -> 1.270.000 weighted rows in
# total). The old figures were scaled down for single-machine play and
# turned out to be far too cheap - a wonder fell within a few rounds.
# The new ones sit in the order of magnitude of the original (2.500 to
# 500.000 lines per wonder), where a wonder is a long-term goal again.
# The doubling per wonder is untouched; only the scale moved.
WONDER_COSTS=(10000 20000 40000 80000 160000 320000 640000)

# State computed by wonders_update from a row total; only the wonder
# screen reads these. WONDER_PREV_INDEX tracks completions
# across calls so finishing a wonder is logged exactly once.
WONDER_INDEX=0
WONDER_DONE=0
WONDER_COST=0
WONDER_PERCENT=0
WONDER_ALL_DONE=0
WONDER_PREV_INDEX=-1

# wonders_update TOTAL
# Map an all-time row total onto the wonder sequence: walk the cost
# table, subtracting each finished wonder, until the wonder still under
# construction is found. Sets WONDER_INDEX (0-based), WONDER_DONE (rows
# invested into it), WONDER_COST and WONDER_PERCENT;
# after the last wonder WONDER_ALL_DONE is 1 and the last wonder stays
# selected at 100 percent.
wonders_update() {
    local total="${1}" i last
    last=$(( ${#WONDER_COSTS[@]} - 1 ))
    WONDER_ALL_DONE=0
    for (( i = 0; i <= last; i++ )); do
        if (( total < WONDER_COSTS[i] )); then
            break
        fi
        total=$(( total - WONDER_COSTS[i] ))
    done
    if (( i > last )); then
        WONDER_ALL_DONE=1
        i="${last}"
        total="${WONDER_COSTS[last]}"
    fi
    WONDER_INDEX="${i}"
    WONDER_DONE="${total}"
    WONDER_COST="${WONDER_COSTS[i]}"
    WONDER_PERCENT=$(( WONDER_DONE * 100 / WONDER_COST ))
    # Log the transition to a new construction site once. The very first
    # call (previous index -1) only initializes the tracking. The file
    # names go into the log rather than the display names: a log has to
    # read the same whatever language the session ran in.
    if [ "${WONDER_PREV_INDEX}" -ge 0 ] && [ "${WONDER_INDEX}" -ne "${WONDER_PREV_INDEX}" ]; then
        debug_event "wonder completed: ${WONDER_FILES[WONDER_PREV_INDEX]}, now building ${WONDER_FILES[i]}"
    fi
    WONDER_PREV_INDEX="${WONDER_INDEX}"
    return 0
}

# wonder_name INDEX
# The display name of a wonder in the active language, in the global
# WONDER_NAME. The translation key is built from the art file name
# (mayan-temple -> wonder_mayan_temple), so a wonder is identified by the
# one string that is the same in every language and no second table has
# to be kept in the order of WONDER_FILES.
WONDER_NAME=""
wonder_name() {
    local key="${WONDER_FILES[${1}]//-/_}"
    WONDER_NAME="${I18N[wonder_${key}]}"
    return 0
}

# wonder_art_load INDEX
# Read the wonder's ASCII art into the WONDER_ART array (one element per
# line). A missing art file is an installation defect and therefore a
# fatal error with the offending path in the message.
wonder_art_load() {
    local f="${SCRIPT_DIR}/assets/wonders/${WONDER_FILES[${1}]}.txt"
    WONDER_ART=()
    if [ ! -r "${f}" ]; then
        die "Missing wonder art file: ${f}"
    fi
    mapfile -t WONDER_ART < "${f}"
    return 0
}

# wonder_screen_lines VIEW TOTAL BROWSABLE
# Build the screen of one wonder into WONDER_SCREEN_LINES: title, the
# art revealed bottom-up by build progress, the stage/row numbers and
# the all-time total. Revealed lines grow with WONDER_DONE but the top
# line only appears at 100 percent, so a wonder never looks finished
# early; hidden lines stay blank to keep the layout stable. Requires
# wonders_update to have run for TOTAL: VIEW below WONDER_INDEX is a
# wonder already finished and is therefore shown complete and paid in
# full, VIEW at WONDER_INDEX is the construction site itself. BROWSABLE
# picks the footer (see wonder_screen).
WONDER_SCREEN_LINES=()
wonder_screen_lines() {
    local view="${1}" total="${2}" browsable="${3}"
    local stages reveal rows_done cost percent i line
    wonder_art_load "${view}"
    wonder_name "${view}"
    stages="${#WONDER_ART[@]}"
    if [ "${view}" -lt "${WONDER_INDEX}" ]; then
        # A finished wonder: fully revealed, its cost paid off. The
        # numbers are the cost table's, not the round counters' - the
        # rows that built it are long spent on the ones after it.
        reveal="${stages}"
        rows_done="${WONDER_COSTS[view]}"
        cost="${rows_done}"
        percent=100
    else
        rows_done="${WONDER_DONE}"
        cost="${WONDER_COST}"
        percent="${WONDER_PERCENT}"
        reveal=$(( rows_done * stages / cost ))
    fi
    if [ "${WONDER_ALL_DONE}" -eq 1 ] && [ "${view}" -eq "${WONDER_INDEX}" ]; then
        WONDER_SCREEN_LINES=("  ${I18N[wonder_all_done]}" "")
    else
        printf -v line "${I18N[wonder_building]}" \
            "$(( view + 1 ))" "${#WONDER_FILES[@]}" "${WONDER_NAME}"
        WONDER_SCREEN_LINES=("  ${line}" "")
    fi
    for (( i = 0; i < stages; i++ )); do
        if (( i >= stages - reveal )); then
            WONDER_SCREEN_LINES+=("  ${WONDER_ART[i]}")
        else
            WONDER_SCREEN_LINES+=("")
        fi
    done
    WONDER_SCREEN_LINES+=("")
    if [ "${WONDER_ALL_DONE}" -eq 1 ] && [ "${view}" -eq "${WONDER_INDEX}" ]; then
        printf -v line "${I18N[wonder_finished]}" "${WONDER_NAME}"
    else
        printf -v line "${I18N[wonder_stage]}" "${reveal}" "${stages}" \
            "${rows_done}" "${cost}" "${percent}"
    fi
    WONDER_SCREEN_LINES+=("  ${line}")
    printf -v line "${I18N[wonder_total]}" "${total}"
    WONDER_SCREEN_LINES+=("  ${line}" "")
    if [ "${browsable}" -eq 1 ]; then
        WONDER_SCREEN_LINES+=("  ${I18N[wonder_nav]}")
    else
        WONDER_SCREEN_LINES+=("  ${I18N[menu_any_key]}")
    fi
    return 0
}

# wonder_screen TOTAL
# Show the construction site the given row total is working on and let
# the left/right keys page back through the wonders already finished
# (CHANGE 2026-08-04, game 0.54.0, user request). The browsable range
# is 0..WONDER_INDEX: a wonder not yet started is not shown, it would
# only be an empty frame and spoil what is still ahead. Paging wraps
# like every other list of the game.
# With nothing finished yet there is nothing to page through, so the
# screen stays what it was before - any key closes it, which is also
# what the flow after a round expects. Once it is a browser, the keys
# that close it are the explicit ones of the manual screens
# (Enter/Space/ESC/x), because the arrows now mean something else.
wonder_screen() {
    local total="${1}"
    local view last browsable dirty=1
    wonders_update "${total}"
    view="${WONDER_INDEX}"
    last="${WONDER_INDEX}"
    browsable=0
    if [ "${last}" -gt 0 ]; then
        browsable=1
    fi
    debug_event "wonder screen shown: index=${WONDER_INDEX} done=${WONDER_DONE}/${WONDER_COST} total=${total} browsable=${browsable}"
    while :; do
        if [ "${dirty}" -eq 1 ]; then
            wonder_screen_lines "${view}" "${total}" "${browsable}"
            render_menu_frame "${WONDER_SCREEN_LINES[@]}"
            screen_write "${RENDER_MENU_FRAME}"
            dirty=0
        fi
        read_key
        # Repaint after a terminal resize (read_key cleared the screen).
        # The frame is rebuilt, not re-emitted: it carries absolute cursor
        # positions computed for the terminal size before the resize.
        if [ "${REDRAW_PENDING}" -eq 1 ]; then
            REDRAW_PENDING=0
            dirty=1
            continue
        fi
        if [ "${browsable}" -eq 0 ]; then
            if [ -n "${KEY}" ]; then
                return 0
            fi
            continue
        fi
        case "${KEY}" in
            LEFT)
                view=$(( (view + last) % (last + 1) ))
                dirty=1
                debug_event "wonder screen: viewing ${WONDER_FILES[view]}"
                ;;
            RIGHT)
                view=$(( (view + 1) % (last + 1) ))
                dirty=1
                debug_event "wonder screen: viewing ${WONDER_FILES[view]}"
                ;;
            ENTER|SPACE|ESC|x)
                return 0
                ;;
        esac
    done
}
