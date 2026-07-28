#!/usr/bin/env bash
#
# lib/highscore.sh
#
# Description:
#   Persistent highscore list for rowhammer. The best HS_MAX (10) rounds
#   are kept in ${DATA_DIR}/highscore (default
#   ~/.config/rowhammer/highscore),
#   one entry per line in the field format
#   "rows|lines|level|name|date|gold|silver|time|rowhammers|pieces", sorted by rows (the
#   weighted row credit) descending. Since the scoring rebuild (0.4.0,
#   user decision) the row credit is the game's only score, so the old
#   leading score field is gone and the rows field ranks the list. The
#   time field (0.17.0) is the round's play time in whole seconds, the
#   rowhammers field (0.25.0) the round's number of four-row
#   clears and the trailing pieces field (0.27.0) the pieces it placed;
#   lines that do not match the ten-field format simply fail
#   validation and are dropped (project rule: no backward compatibility).
#   The file is parsed and validated line by line, not sourced: it is
#   list data, not shell code, and a corrupted line must only drop that
#   entry, never break the game. Saving is atomic (temp file + mv).
#   highscore_add records a finished round and reports the achieved rank
#   in HS_LAST_RANK (0 = did not make the list), which the game over
#   sidebar shows. highscore_screen renders the list for the main menu
#   via menu_pages (lib/menu.sh), two lines per entry: rank, name, rows,
#   play time (MM:SS) and date on the first, gold/silver squares,
#   rowhammers, pieces placed and the resulting pieces per minute on the
#   second.
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.7.0  (2026-07-28)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/highscore.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# Maximum number of entries kept, and the file name below DATA_DIR.
HS_MAX=10
HS_FILE_NAME="highscore"

# In-memory list: one
# "rows|lines|level|name|date|gold|silver|time|rowhammers|pieces" string
# per element, sorted by rows descending. HS_LAST_RANK is the rank the
# most recently added round reached (1-based, 0 = not on the list). The
# time field is the round's play time in whole seconds, the last two
# fields its number of four-row clears and the pieces it placed.
HS_ENTRIES=()
HS_LAST_RANK=0

# Accepted line format for loading. The name charset matches the player
# name validation in rowhammer.sh (no "|" possible), so every file this
# game writes round-trips unchanged. All ten fields are mandatory:
# the scoring rebuild dropped the old leading score field, play time,
# rowhammers and pieces were appended last, and per the
# no-backward-compatibility rule old-format lines are simply invalid.
HS_LINE_RE='^[0-9]+\|[0-9]+\|[0-9]+\|[A-Za-z0-9_ -]{1,16}\|[0-9]{4}-[0-9]{2}-[0-9]{2}\|[0-9]+\|[0-9]+\|[0-9]+\|[0-9]+\|[0-9]+$'

# highscore_load
# Read the highscore file into HS_ENTRIES. A missing file simply means
# an empty list; malformed lines are skipped so a damaged file costs
# single entries, not the whole game.
highscore_load() {
    HS_ENTRIES=()
    local f="${DATA_DIR}/${HS_FILE_NAME}" line
    if [ ! -r "${f}" ]; then
        return 0
    fi
    while IFS= read -r line; do
        if [[ "${line}" =~ ${HS_LINE_RE} ]]; then
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

# highscore_add ROWS LINES LEVEL NAME GOLD SILVER TIME ROWHAMMERS PIECES
# Insert a finished round into the sorted list and persist it. TIME is
# the round's play time in whole seconds, ROWHAMMERS the number of
# four-row clears and PIECES the number of pieces placed (TIME and
# PIECES are what the list's PCS/min column is derived from). Equal
# row credits rank below existing ones (the older entry keeps its
# place). Rounds with 0 rows are ignored, and nothing is written when
# the round does not make the list; HS_LAST_RANK reports the outcome
# either way.
highscore_add() {
    local rows="${1}" lines="${2}" level="${3}" name="${4}"
    local gold="${5}" silver="${6}" time="${7}" hammers="${8}"
    local pieces="${9}"
    local entry e placed=0 rank=0
    local -a merged=()
    HS_LAST_RANK=0
    if [ "${rows}" -le 0 ]; then
        return 0
    fi
    entry="${rows}|${lines}|${level}|${name}|$(date +%Y-%m-%d)|${gold}|${silver}|${time}|${hammers}|${pieces}"
    if [ "${#HS_ENTRIES[@]}" -gt 0 ]; then
        for e in "${HS_ENTRIES[@]}"; do
            if [ "${placed}" -eq 0 ] && [ "${rows}" -gt "${e%%|*}" ]; then
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
            debug_event "highscore: '${name}' rows=${rows} below the top ${HS_MAX}"
            return 0
        fi
        merged+=("${entry}")
        rank="${#merged[@]}"
    fi
    HS_ENTRIES=("${merged[@]:0:HS_MAX}")
    HS_LAST_RANK="${rank}"
    debug_event "highscore: '${name}' rows=${rows} enters at rank ${rank}"
    highscore_save
    return 0
}

# How many entries one page of the highscore screen shows, and the
# number of body lines that takes: each entry is a three-line block (two
# data lines plus a separating blank), and the table head costs one more.
# 1 + 5 * 3 = 16 body lines stay within MENU_BODY_MAX (lib/menu.sh), so
# a full list of ten needs exactly two pages.
HS_PAGE_ENTRIES=5
HS_PAGE_LINES=$(( HS_PAGE_ENTRIES * 3 ))

# highscore_screen
# Show the list as a menu-style info screen (paged via menu_pages) and
# wait for any key per page. Labels
# are German like the menus; the Rows column reuses the English HUD
# term. Shown per entry, on two lines: rank, name, rows, the round's
# play time (MM:SS) and the date on the first, then the gold/silver
# squares, the rowhammers ("RH", four rows at once), the pieces placed
# ("PCS") and the resulting pieces per minute ("PPM", pieces divided by
# play time, see fmt_ppm) on the second. Lines and level stay stored
# but are not displayed; the rows column is the score and drives the
# ranking (scoring rebuild, 0.4.0).
# CHANGE 2026-07-28 (user decision, 0.27.0): the entry became two lines.
# One line has 46 usable characters (the 48-column minimum minus the
# two-space menu indent), and the pieces and PCS/min columns no longer
# fit next to the existing ones - the user explicitly allowed the list
# to grow taller for them. The split pays back the space the RH column
# had taken from the name in 0.25.0: names show with 12 characters
# again instead of 6. The second line carries its own labels, so it
# needs no column head, and the numbers are printed with widths that fit
# any realistic round; the line is clamped to 46 characters afterwards
# so implausible values cannot wrap the screen.
highscore_screen() {
    local -a body=()
    local i line hs_rows hs_name hs_date hs_gold hs_silver hs_time
    local hs_hammers hs_pieces
    if [ "${#HS_ENTRIES[@]}" -eq 0 ]; then
        body+=("Noch keine Eintraege.")
        body+=("")
        body+=("Spiele eine Runde, um dich einzutragen.")
        debug_event "highscore screen shown (0 entries)"
        menu_message "Highscores" "${body[@]}"
        return 0
    fi
    printf -v line '%2s %-12s %6s %5s %10s' \
        "Nr" "Name" "Rows" "Zeit" "Datum"
    body+=("${line}")
    for i in "${!HS_ENTRIES[@]}"; do
        IFS='|' read -r hs_rows _ _ hs_name hs_date hs_gold hs_silver \
            hs_time hs_hammers hs_pieces <<< "${HS_ENTRIES[i]}"
        fmt_duration "${hs_time}"
        printf -v line '%2d %-12.12s %6d %5s %10s' \
            "$(( i + 1 ))" "${hs_name}" "${hs_rows}" "${FMT_DURATION}" \
            "${hs_date}"
        body+=("${line:0:46}")
        fmt_ppm "${hs_pieces}" "${hs_time}"
        printf -v line '  Gold %3d Silb %3d RH %2d PCS %4d PPM %5s' \
            "${hs_gold}" "${hs_silver}" "${hs_hammers}" "${hs_pieces}" \
            "${FMT_PPM}"
        body+=("${line:0:46}")
        body+=("")
    done
    debug_event "highscore screen shown (${#HS_ENTRIES[@]} entries)"
    menu_pages "Highscores" 1 "${HS_PAGE_LINES}" "${body[@]}"
    return 0
}
