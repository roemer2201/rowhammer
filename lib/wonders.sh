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
#   round and from the "Weltwunder" main menu entry; its wait loop
#   repaints on REDRAW_PENDING so a terminal resize (handled in read_key)
#   does not leave it blank (since 0.1.1). Wonder names,
#   sequence and row costs live in the tables below; costs double per
#   wonder like the roughly geometric line requirements of the original,
#   but are scaled down to fit single-machine play.
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.1.1  (2026-07-23)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/wonders.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# The wonder sequence; all four tables share the same index. Structures
# verified against the original where sources allowed (Mayan temple,
# Stonehenge, Sphinx, Pantheon and St Basil's Cathedral appear in The
# New Tetris); Great Wall and Taj Mahal fill the remaining slots. The
# German display names are used on the wonder screen (menu language),
# the shorter English names in the in-game HUD. WONDER_COSTS holds the
# weighted rows needed to finish each single wonder (not cumulative);
# adjust here to tune the pacing.
WONDER_FILES=(mayan-temple stonehenge sphinx pantheon
              great-wall taj-mahal st-basils)
WONDER_NAMES_DE=("Maya-Tempel (Chichen Itza)" "Stonehenge"
                 "Sphinx von Gizeh" "Pantheon (Rom)"
                 "Chinesische Mauer" "Taj Mahal"
                 "Basilius-Kathedrale (Moskau)")
WONDER_NAMES_HUD=("Mayan Temple" "Stonehenge" "Sphinx" "Pantheon"
                  "Great Wall" "Taj Mahal" "St Basils")
WONDER_COSTS=(100 200 400 800 1600 3200 6400)

# State computed by wonders_update from a row total; the HUD and the
# wonder screen only read these. WONDER_PREV_INDEX tracks completions
# across calls so finishing a wonder is logged exactly once.
WONDER_INDEX=0
WONDER_DONE=0
WONDER_COST=0
WONDER_PERCENT=0
WONDER_ALL_DONE=0
WONDER_HUD_NAME=""
WONDER_PREV_INDEX=-1

# wonders_update TOTAL
# Map an all-time row total onto the wonder sequence: walk the cost
# table, subtracting each finished wonder, until the wonder still under
# construction is found. Sets WONDER_INDEX (0-based), WONDER_DONE (rows
# invested into it), WONDER_COST, WONDER_PERCENT and WONDER_HUD_NAME;
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
    WONDER_HUD_NAME="${WONDER_NAMES_HUD[i]}"
    # Log the transition to a new construction site once. The very first
    # call (previous index -1) only initializes the tracking.
    if [ "${WONDER_PREV_INDEX}" -ge 0 ] && [ "${WONDER_INDEX}" -ne "${WONDER_PREV_INDEX}" ]; then
        debug_event "wonder completed: ${WONDER_NAMES_HUD[WONDER_PREV_INDEX]}, now building ${WONDER_HUD_NAME}"
    fi
    WONDER_PREV_INDEX="${WONDER_INDEX}"
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

# wonder_screen TOTAL
# Show the construction site of the wonder the given row total is
# working on: title, the art revealed bottom-up by build progress, the
# stage/row numbers and the all-time total. Revealed lines grow with
# WONDER_DONE but the top line only appears at 100 percent, so a wonder
# never looks finished early; hidden lines stay blank to keep the layout
# stable. Waits for any key, like menu_message.
wonder_screen() {
    local total="${1}"
    local frame line stages reveal i
    wonders_update "${total}"
    wonder_art_load "${WONDER_INDEX}"
    stages="${#WONDER_ART[@]}"
    reveal=$(( WONDER_DONE * stages / WONDER_COST ))
    frame=$'\e[H\n'
    if [ "${WONDER_ALL_DONE}" -eq 1 ]; then
        frame+="  Alle Weltwunder sind errichtet!"$'\e[K\n\e[K\n'
    else
        frame+="  Weltwunder $(( WONDER_INDEX + 1 ))/${#WONDER_FILES[@]}: ${WONDER_NAMES_DE[WONDER_INDEX]}"$'\e[K\n\e[K\n'
    fi
    for (( i = 0; i < stages; i++ )); do
        if (( i >= stages - reveal )); then
            frame+="  ${WONDER_ART[i]}"$'\e[K\n'
        else
            frame+=$'\e[K\n'
        fi
    done
    frame+=$'\e[K\n'
    if [ "${WONDER_ALL_DONE}" -eq 1 ]; then
        frame+="  ${WONDER_NAMES_DE[WONDER_INDEX]} ist fertig."$'\e[K\n'
    else
        frame+="  Baustufe ${reveal}/${stages} - ${WONDER_DONE}/${WONDER_COST} Reihen (${WONDER_PERCENT}%)"$'\e[K\n'
    fi
    frame+="  Reihen gesamt: ${total}"$'\e[K\n\e[K\n'
    frame+="  Beliebige Taste druecken..."$'\e[K\n\e[J'
    screen_write "${frame}"
    debug_event "wonder screen shown: index=${WONDER_INDEX} stage=${reveal}/${stages} done=${WONDER_DONE}/${WONDER_COST} total=${total}"
    KEY=""
    while [ -z "${KEY}" ]; do
        read_key
        # Repaint after a terminal resize (read_key cleared the screen);
        # the frame is still in scope, so re-emitting it restores it.
        if [ "${REDRAW_PENDING}" -eq 1 ]; then
            REDRAW_PENDING=0
            screen_write "${frame}"
        fi
    done
    return 0
}
