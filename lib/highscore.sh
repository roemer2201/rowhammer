#!/usr/bin/env bash
#
# lib/highscore.sh
#
# Description:
#   Persistent highscore list for rowhammer. The best HS_MAX (10) rounds
#   are kept in ${DATA_DIR}/highscore (default
#   ~/.config/rowhammer/highscore),
#   one entry per line in the field format
#   "score|lines|rows|level|name|date|gold|silver", sorted by score
#   descending. The trailing gold/silver square counters were added in
#   0.3.0; entries without them load with a default of 0 (per the
#   roadmap spec for this extension).
#   The file is parsed and validated line by line, not sourced: it is
#   list data, not shell code, and a corrupted line must only drop that
#   entry, never break the game. Saving is atomic (temp file + mv).
#   highscore_add records a finished round and reports the achieved rank
#   in HS_LAST_RANK (0 = did not make the list), which the game over
#   sidebar shows. highscore_screen renders the list for the main menu
#   via menu_message (lib/menu.sh): rank, name, rows, gold/silver
#   squares and date. The score still decides the ranking and stays
#   stored, but is no longer displayed (user decision, 0.3.0).
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.3.0  (2026-07-20)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/highscore.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# Maximum number of entries kept, and the file name below DATA_DIR.
HS_MAX=10
HS_FILE_NAME="highscore"

# In-memory list: one "score|lines|rows|level|name|date|gold|silver"
# string per
# element, sorted by score descending. HS_LAST_RANK is the rank the most
# recently added round reached (1-based, 0 = not on the list).
HS_ENTRIES=()
HS_LAST_RANK=0

# Accepted line format for loading. The name charset matches the player
# name validation in rowhammer.sh (no "|" possible), so every file this
# game writes round-trips unchanged. The gold/silver suffix is optional
# on purpose: the roadmap spec for this extension says entries without
# the two counters load with a default of 0 (highscore_load fills them
# in), unlike the usual "formats may just break" rule.
HS_LINE_RE='^[0-9]+\|[0-9]+\|[0-9]+\|[0-9]+\|[A-Za-z0-9_ -]{1,16}\|[0-9]{4}-[0-9]{2}-[0-9]{2}(\|[0-9]+\|[0-9]+)?$'

# highscore_load
# Read the highscore file into HS_ENTRIES. A missing file simply means
# an empty list; malformed lines are skipped so a damaged file costs
# single entries, not the whole game. Entries without the gold/silver
# suffix are normalized to "|0|0" so the rest of the module only ever
# sees the full 8-field format.
highscore_load() {
    HS_ENTRIES=()
    local f="${DATA_DIR}/${HS_FILE_NAME}" line
    if [ ! -r "${f}" ]; then
        return 0
    fi
    while IFS= read -r line; do
        if [[ "${line}" =~ ${HS_LINE_RE} ]]; then
            if [ -z "${BASH_REMATCH[1]}" ]; then
                line+="|0|0"
            fi
            HS_ENTRIES+=("${line}")
        fi
        if [ "${#HS_ENTRIES[@]}" -ge "${HS_MAX}" ]; then
            break
        fi
    done < "${f}"
    debug_event "highscore loaded: ${#HS_ENTRIES[@]} entries from ${f}"
    return 0
}

# highscore_save
# Write HS_ENTRIES atomically: into a temp file in the target directory,
# then mv over the real file, so a crash can never leave a half-written
# list behind.
highscore_save() {
    local f="${DATA_DIR}/${HS_FILE_NAME}" tmp
    mkdir -p -- "${DATA_DIR}"
    tmp="$(mktemp -- "${DATA_DIR}/.${HS_FILE_NAME}.XXXXXX")"
    # Expanding an empty array under set -u errors on bash < 4.4, so the
    # empty list writes an empty file explicitly.
    if [ "${#HS_ENTRIES[@]}" -gt 0 ]; then
        printf '%s\n' "${HS_ENTRIES[@]}" > "${tmp}"
    else
        : > "${tmp}"
    fi
    mv -f -- "${tmp}" "${f}"
    debug_event "highscore saved: ${f} (${#HS_ENTRIES[@]} entries)"
    return 0
}

# highscore_add SCORE LINES ROWS LEVEL NAME GOLD SILVER
# Insert a finished round into the sorted list and persist it. Equal
# scores rank below existing ones (the older entry keeps its place).
# Rounds with score 0 are ignored, and nothing is written when the score
# does not make the list; HS_LAST_RANK reports the outcome either way.
highscore_add() {
    local score="${1}" lines="${2}" rows="${3}" level="${4}" name="${5}"
    local gold="${6}" silver="${7}"
    local entry e placed=0 rank=0
    local -a merged=()
    HS_LAST_RANK=0
    if [ "${score}" -le 0 ]; then
        return 0
    fi
    entry="${score}|${lines}|${rows}|${level}|${name}|$(date +%Y-%m-%d)|${gold}|${silver}"
    if [ "${#HS_ENTRIES[@]}" -gt 0 ]; then
        for e in "${HS_ENTRIES[@]}"; do
            if [ "${placed}" -eq 0 ] && [ "${score}" -gt "${e%%|*}" ]; then
                merged+=("${entry}")
                rank="${#merged[@]}"
                placed=1
            fi
            merged+=("${e}")
        done
    fi
    # Not better than any existing entry: append only while there is room.
    if [ "${placed}" -eq 0 ]; then
        if [ "${#merged[@]}" -ge "${HS_MAX}" ]; then
            debug_event "highscore: '${name}' score=${score} below the top ${HS_MAX}"
            return 0
        fi
        merged+=("${entry}")
        rank="${#merged[@]}"
    fi
    HS_ENTRIES=("${merged[@]:0:HS_MAX}")
    HS_LAST_RANK="${rank}"
    debug_event "highscore: '${name}' score=${score} enters at rank ${rank}"
    highscore_save
    return 0
}

# highscore_screen
# Show the list as a menu-style info screen and wait for any key. Labels
# are German like the menus; the Rows column reuses the English HUD
# term. Shown per entry: rank, name, rows, gold/silver squares and the
# date. Score, lines and level stay stored (the score keeps driving the
# ranking and the game over rank) but are not displayed - the score
# column was dropped on user request when the gold/silver columns came
# in (0.3.0). To keep the layout within the 48-column minimum the name
# column is capped at 13 characters (longer names are truncated for
# display only).
highscore_screen() {
    local -a body=()
    local i line hs_rows hs_name hs_date hs_gold hs_silver
    if [ "${#HS_ENTRIES[@]}" -eq 0 ]; then
        body+=("Noch keine Eintraege.")
        body+=("")
        body+=("Spiele eine Runde, um dich einzutragen.")
    else
        printf -v line '%2s %-13s %5s %4s %6s %10s' \
            "Nr" "Name" "Rows" "Gold" "Silber" "Datum"
        body+=("${line}")
        for i in "${!HS_ENTRIES[@]}"; do
            IFS='|' read -r _ _ hs_rows _ hs_name hs_date hs_gold hs_silver \
                <<< "${HS_ENTRIES[i]}"
            printf -v line '%2d %-13.13s %5d %4d %6d %10s' \
                "$(( i + 1 ))" "${hs_name}" "${hs_rows}" \
                "${hs_gold}" "${hs_silver}" "${hs_date}"
            body+=("${line}")
        done
    fi
    debug_event "highscore screen shown (${#HS_ENTRIES[@]} entries)"
    menu_message "Highscores" "${body[@]}"
    return 0
}
