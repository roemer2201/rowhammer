#!/usr/bin/env bash
#
# lib/stats.sh
#
# Description:
#   Persistent all-time game statistics for rowhammer: cleared rows
#   (physical lines), earned bonus rows (the weighted row credit beyond
#   the physical lines, i.e. gold/silver/Tetris bonuses) and the number
#   of gold and silver squares built - plus the results of the last
#   three rounds (score, lines, bonus rows, gold/silver squares; newest
#   first). Everything is kept in ${DATA_DIR}/stats (default
#   ~/rowhammer/stats) as "key=value" lines
#   plus comment lines. The file is parsed and validated, not sourced:
#   a corrupted line only loses that one counter or round entry (falls
#   back to 0 / drops the entry), it
#   never breaks the game. Saving is atomic (temp file + mv). A round is
#   banked into the counters and the recent list exactly once per
#   finished round
#   (record_round_score in rowhammer.sh calls stats_add_round).
#   stats_screen renders the statistics for the "Statistik" main menu
#   entry via menu_message (lib/menu.sh).
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.2.0  (2026-07-19)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/stats.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# File name below DATA_DIR and the accepted line formats. The digit
# caps keep the arithmetic clear of bash integer overflow (same guard
# as the savegame in lib/save.sh). A "recent" line stores one round as
# "recent=score|lines|bonus|gold|silver"; the file keeps the newest
# round first.
STATS_FILE_NAME="stats"
STATS_LINE_RE='^(lines|bonus_rows|gold_squares|silver_squares)=([0-9]{1,15})$'
STATS_RECENT_RE='^recent=([0-9]{1,15}(\|[0-9]{1,15}){4})$'

# How many recent rounds are kept and shown.
STATS_RECENT_MAX=3

# All-time counters across every round ever played, plus the recent
# round list ("score|lines|bonus|gold|silver" per element, newest
# first). Loaded on startup, extended by stats_add_round, read by
# stats_screen.
STATS_LINES=0
STATS_BONUS_ROWS=0
STATS_GOLD=0
STATS_SILVER=0
STATS_RECENT=()

# stats_load
# Read the statistics file into the STATS_* counters and the recent
# round list. A missing file
# means a fresh start; a file without a single valid counter line
# (manual edit, corruption) falls back to all zeros and is reported,
# mirroring the savegame behaviour in lib/save.sh. Recent-round lines
# beyond STATS_RECENT_MAX are dropped.
stats_load() {
    STATS_LINES=0
    STATS_BONUS_ROWS=0
    STATS_GOLD=0
    STATS_SILVER=0
    STATS_RECENT=()
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
        elif [[ "${line}" =~ ${STATS_RECENT_RE} ]]; then
            found=1
            if [ "${#STATS_RECENT[@]}" -lt "${STATS_RECENT_MAX}" ]; then
                STATS_RECENT+=("${BASH_REMATCH[1]}")
            fi
        fi
    done < "${f}"
    if [ "${found}" -eq 0 ]; then
        printf '%s: statistics file has no valid counter line, starting at 0: %s\n' \
            "${SCRIPT_NAME}" "${f}" >&2
    fi
    debug_event "stats: loaded lines=${STATS_LINES} bonus=${STATS_BONUS_ROWS} gold=${STATS_GOLD} silver=${STATS_SILVER} recent=${#STATS_RECENT[@]} from ${f}"
    return 0
}

# stats_write
# Write the STATS_* counters and the recent round list atomically: into
# a temp file in the target
# directory, then mv over the real file, so a crash can never leave a
# half-written statistics file behind.
stats_write() {
    local f="${DATA_DIR}/${STATS_FILE_NAME}" tmp
    mkdir -p -- "${DATA_DIR}"
    tmp="$(mktemp -- "${DATA_DIR}/.${STATS_FILE_NAME}.XXXXXX")"
    {
        printf '# rowhammer statistics: all-time counters and recent rounds.\n'
        printf '# Written after every finished round; edits are validated on load.\n'
        printf 'lines=%d\n' "${STATS_LINES}"
        printf 'bonus_rows=%d\n' "${STATS_BONUS_ROWS}"
        printf 'gold_squares=%d\n' "${STATS_GOLD}"
        printf 'silver_squares=%d\n' "${STATS_SILVER}"
        # Newest round first; format score|lines|bonus|gold|silver. The
        # length guard keeps bash < 4.4 happy under set -u.
        if [ "${#STATS_RECENT[@]}" -gt 0 ]; then
            printf 'recent=%s\n' "${STATS_RECENT[@]}"
        fi
    } > "${tmp}"
    mv -f -- "${tmp}" "${f}"
    debug_event "stats: wrote lines=${STATS_LINES} bonus=${STATS_BONUS_ROWS} gold=${STATS_GOLD} silver=${STATS_SILVER} recent=${#STATS_RECENT[@]} to ${f}"
    return 0
}

# stats_add_round SCORE LINES BONUS GOLD SILVER
# Bank one finished round into the all-time counters, prepend it to the
# recent round list (capped at STATS_RECENT_MAX) and persist both. A
# round without any progress at all (no score, no lines, no squares)
# leaves the counters, the list and the file
# untouched, so idle rounds cause no disk writes.
stats_add_round() {
    local score="${1}" lines="${2}" bonus="${3}" gold="${4}" silver="${5}"
    if (( score == 0 && lines == 0 && bonus == 0 && gold == 0 && silver == 0 )); then
        return 0
    fi
    STATS_LINES=$(( STATS_LINES + lines ))
    STATS_BONUS_ROWS=$(( STATS_BONUS_ROWS + bonus ))
    STATS_GOLD=$(( STATS_GOLD + gold ))
    STATS_SILVER=$(( STATS_SILVER + silver ))
    # Prepend the round; slicing an empty array errors under set -u on
    # bash < 4.4, hence the guard.
    if [ "${#STATS_RECENT[@]}" -gt 0 ]; then
        STATS_RECENT=("${score}|${lines}|${bonus}|${gold}|${silver}" \
            "${STATS_RECENT[@]:0:STATS_RECENT_MAX-1}")
    else
        STATS_RECENT=("${score}|${lines}|${bonus}|${gold}|${silver}")
    fi
    debug_event "stats: round banked score=${score} +${lines} lines +${bonus} bonus +${gold} gold +${silver} silver"
    stats_write
    return 0
}

# stats_screen
# Show the all-time statistics as a menu-style info screen and wait for
# any key. Labels are German like the menus (ASCII, no umlauts per the
# conventions). The weighted total (lines + bonus rows) is shown as a
# summary line because it is the number that builds the wonders. Below
# the counters the results of the last STATS_RECENT_MAX rounds are
# listed, newest first; the column layout stays within the 48-column
# minimum terminal width.
stats_screen() {
    local -a body=()
    local line entry r_score r_lines r_bonus r_gold r_silver
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
    body+=("")
    body+=("Letzte Spiele (neueste zuerst):")
    if [ "${#STATS_RECENT[@]}" -eq 0 ]; then
        body+=("Noch keine Spiele.")
    else
        printf -v line '%8s %7s %6s %5s %7s' \
            "Score" "Reihen" "Bonus" "Gold" "Silber"
        body+=("${line}")
        for entry in "${STATS_RECENT[@]}"; do
            IFS='|' read -r r_score r_lines r_bonus r_gold r_silver <<< "${entry}"
            printf -v line '%8d %7d %6d %5d %7d' \
                "${r_score}" "${r_lines}" "${r_bonus}" "${r_gold}" "${r_silver}"
            body+=("${line}")
        done
    fi
    debug_event "stats screen shown (${#STATS_RECENT[@]} recent rounds)"
    menu_message "Statistik" "${body[@]}"
    return 0
}
