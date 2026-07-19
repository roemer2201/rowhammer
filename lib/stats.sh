#!/usr/bin/env bash
#
# lib/stats.sh
#
# Description:
#   Persistent all-time game statistics for rowhammer: cleared rows
#   (physical lines), earned bonus rows (the weighted row credit beyond
#   the physical lines, i.e. gold/silver/Tetris bonuses) and the number
#   of gold and silver squares built. The counters are kept in
#   ${DATA_DIR}/stats (default ~/rowhammer/stats) as "key=value" lines
#   plus comment lines. The file is parsed and validated, not sourced:
#   a corrupted line only loses that one counter (falls back to 0), it
#   never breaks the game. Saving is atomic (temp file + mv). A round is
#   banked into the counters exactly once per finished round
#   (record_round_score in rowhammer.sh calls stats_add_round).
#   stats_screen renders the statistics for the "Statistik" main menu
#   entry via menu_message (lib/menu.sh).
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.1.0  (2026-07-19)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/stats.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# File name below DATA_DIR and the accepted counter line format. The
# digit cap keeps the arithmetic clear of bash integer overflow (same
# guard as the savegame in lib/save.sh).
STATS_FILE_NAME="stats"
STATS_LINE_RE='^(lines|bonus_rows|gold_squares|silver_squares)=([0-9]{1,15})$'

# All-time counters across every round ever played. Loaded on startup,
# extended by stats_add_round, read by stats_screen.
STATS_LINES=0
STATS_BONUS_ROWS=0
STATS_GOLD=0
STATS_SILVER=0

# stats_load
# Read the statistics file into the STATS_* counters. A missing file
# means a fresh start; a file without a single valid counter line
# (manual edit, corruption) falls back to all zeros and is reported,
# mirroring the savegame behaviour in lib/save.sh.
stats_load() {
    STATS_LINES=0
    STATS_BONUS_ROWS=0
    STATS_GOLD=0
    STATS_SILVER=0
    local f="${DATA_DIR}/${STATS_FILE_NAME}" line found=0
    if [ ! -e "${f}" ]; then
        debug_event "stats: no statistics file at ${f}, starting at 0"
        return 0
    fi
    if [ ! -r "${f}" ]; then
        printf '%s: statistics file is not readable, starting at 0: %s\n' \
            "${SCRIPT_NAME}" "${f}" >&2
        return 0
    fi
    while IFS= read -r line; do
        if [[ "${line}" =~ ${STATS_LINE_RE} ]]; then
            found=1
            case "${BASH_REMATCH[1]}" in
                lines)          STATS_LINES=$(( 10#${BASH_REMATCH[2]} )) ;;
                bonus_rows)     STATS_BONUS_ROWS=$(( 10#${BASH_REMATCH[2]} )) ;;
                gold_squares)   STATS_GOLD=$(( 10#${BASH_REMATCH[2]} )) ;;
                silver_squares) STATS_SILVER=$(( 10#${BASH_REMATCH[2]} )) ;;
            esac
        fi
    done < "${f}"
    if [ "${found}" -eq 0 ]; then
        printf '%s: statistics file has no valid counter line, starting at 0: %s\n' \
            "${SCRIPT_NAME}" "${f}" >&2
    fi
    debug_event "stats: loaded lines=${STATS_LINES} bonus=${STATS_BONUS_ROWS} gold=${STATS_GOLD} silver=${STATS_SILVER} from ${f}"
    return 0
}

# stats_write
# Write the STATS_* counters atomically: into a temp file in the target
# directory, then mv over the real file, so a crash can never leave a
# half-written statistics file behind.
stats_write() {
    local f="${DATA_DIR}/${STATS_FILE_NAME}" tmp
    mkdir -p -- "${DATA_DIR}"
    tmp="$(mktemp -- "${DATA_DIR}/.${STATS_FILE_NAME}.XXXXXX")"
    {
        printf '# rowhammer statistics: all-time counters.\n'
        printf '# Written after every finished round; edits are validated on load.\n'
        printf 'lines=%d\n' "${STATS_LINES}"
        printf 'bonus_rows=%d\n' "${STATS_BONUS_ROWS}"
        printf 'gold_squares=%d\n' "${STATS_GOLD}"
        printf 'silver_squares=%d\n' "${STATS_SILVER}"
    } > "${tmp}"
    mv -f -- "${tmp}" "${f}"
    debug_event "stats: wrote lines=${STATS_LINES} bonus=${STATS_BONUS_ROWS} gold=${STATS_GOLD} silver=${STATS_SILVER} to ${f}"
    return 0
}

# stats_add_round LINES BONUS GOLD SILVER
# Bank one finished round into the all-time counters and persist them.
# A round without any progress leaves the counters and the file
# untouched, so idle rounds cause no disk writes.
stats_add_round() {
    local lines="${1}" bonus="${2}" gold="${3}" silver="${4}"
    if (( lines == 0 && bonus == 0 && gold == 0 && silver == 0 )); then
        return 0
    fi
    STATS_LINES=$(( STATS_LINES + lines ))
    STATS_BONUS_ROWS=$(( STATS_BONUS_ROWS + bonus ))
    STATS_GOLD=$(( STATS_GOLD + gold ))
    STATS_SILVER=$(( STATS_SILVER + silver ))
    debug_event "stats: round banked +${lines} lines +${bonus} bonus +${gold} gold +${silver} silver"
    stats_write
    return 0
}

# stats_screen
# Show the all-time statistics as a menu-style info screen and wait for
# any key. Labels are German like the menus (ASCII, no umlauts per the
# conventions). The weighted total (lines + bonus rows) is shown as a
# summary line because it is the number that builds the wonders.
stats_screen() {
    local -a body=()
    local line
    printf -v line '%-26s %10d' "Abgebaute Reihen:" "${STATS_LINES}"
    body+=("${line}")
    printf -v line '%-26s %10d' "Bonusreihen:" "${STATS_BONUS_ROWS}"
    body+=("${line}")
    printf -v line '%-26s %10d' "Reihen gesamt (gewertet):" \
        "$(( STATS_LINES + STATS_BONUS_ROWS ))"
    body+=("${line}")
    body+=("")
    printf -v line '%-26s %10d' "Goldbloecke:" "${STATS_GOLD}"
    body+=("${line}")
    printf -v line '%-26s %10d' "Silberbloecke:" "${STATS_SILVER}"
    body+=("${line}")
    debug_event "stats screen shown"
    menu_message "Statistik" "${body[@]}"
    return 0
}
