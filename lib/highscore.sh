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
#   clears and the trailing pieces field (0.27.0) the pieces it placed.
#   Lines are accepted from any point since the 0.4.0 rebuild onward,
#   even if they predate one or more of these trailing fields (see
#   HS_FIELD_COUNTS and highscore_parse_line): a missing counter is
#   filled in as 0 rather than dropping the whole round (0.8.0, user
#   decision - this is a deliberate exception to the project's usual
#   no-backward-compatibility rule, scoped to this append-only part of
#   the format). Lines from before the rebuild (leading "score" field,
#   "rows" third) are a different column order, not just a shorter
#   version of the current one, and still fail validation.
#   The file is parsed and validated line by line, not sourced: it is
#   list data, not shell code, and a corrupted line must only drop that
#   entry, never break the game. Saving is atomic (temp file + mv).
#   highscore_add records a finished round and reports the achieved rank
#   in HS_LAST_RANK (0 = did not make the list), which the game over
#   sidebar shows. highscore_screen renders the list for the main menu
#   via menu_pages (lib/menu.sh), two lines per entry: rank, name, rows,
#   play time (MM:SS) and date on the first, gold/silver squares,
#   rowhammers, pieces placed and the resulting pieces per minute on the
#   second. Since 0.9.0 the table is colored with the TXT_* SGR globals
#   (lib/render.sh, theme-aware, empty in --no-color/NO_COLOR mode): rank
#   1/2 in gold/silver, the rows column and other ranks in the theme's
#   accent color, the Gold/Silb/RH figures in gold/silver/warn color. An
#   implausibly long line (HS_FIELD_NUM_RE has no digit cap, so a
#   hand-edited file could exceed the 46-char budget) skips coloring and
#   falls back to the plain truncated text instead of risking a cut
#   escape sequence.
#   Since 0.10.0 the Ultra game mode (clear ULTRA_TARGET_ROWS rows as
#   fast as possible, see rowhammer.sh) keeps its own list in
#   ${DATA_DIR}/highscore-ultra, built from the HSU_* globals and
#   functions below: a separate file because a timed attempt ranks by the
#   shortest time, not by the most rows, and must not push endless rounds
#   out of the normal top ten. Only runs that reached the goal are
#   stored, so every entry carries a comparable time.
#   Since 0.11.0 (user decision) that list has its screen as well:
#   highscore_ultra_screen mirrors highscore_screen down to the column
#   widths and the coloring, but ranks by the play time (MM:SS.mmm via
#   fmt_duration_ms) and gives it the accent color the Marathon screen
#   puts on Rows. Both screens hang off the mode picker of the
#   "Highscores" menu entry (menu_highscores, lib/menu.sh), which is why
#   their titles name their mode.
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.11.0  (2026-08-02)

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

# Per-field patterns for loading. The name charset matches the player
# name validation in rowhammer.sh (no "|" possible), so every file this
# game writes round-trips unchanged.
HS_FIELD_NUM_RE='^[0-9]+$'
HS_FIELD_NAME_RE='^[A-Za-z0-9_ -]{1,16}$'
HS_FIELD_DATE_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'

# Field counts accepted for a stored line: the mandatory "rows|lines|
# level|name|date" prefix (5 fields), optionally extended by gold and
# silver together (7), then time (8), then rowhammers (9), then pieces
# (10) - exactly the order these fields were appended after the 0.4.0
# scoring rebuild made rows the leading field. Any other count (an old
# pre-rebuild line, or something simply broken) is rejected by
# highscore_parse_line before it looks at individual fields.
HS_FIELD_COUNTS=(5 7 8 9 10)

# highscore_parse_line LINE
# Validate one stored line and, on success, append its normalized
# (always ten-field, missing counters filled in as 0) form to
# HS_ENTRIES. See HS_FIELD_COUNTS above for which shorter, older field
# counts are accepted and why a pre-0.4.0 line (different column order,
# not just fewer columns) is not among them.
highscore_parse_line() {
    local line="${1}"
    local -a f=()
    local n c i ok=0

    IFS='|' read -r -a f <<< "${line}"
    n="${#f[@]}"
    for c in "${HS_FIELD_COUNTS[@]}"; do
        if [ "${n}" -eq "${c}" ]; then
            ok=1
            break
        fi
    done
    [ "${ok}" -eq 1 ] || return 0

    [[ "${f[0]}" =~ ${HS_FIELD_NUM_RE} ]] || return 0
    [[ "${f[1]}" =~ ${HS_FIELD_NUM_RE} ]] || return 0
    [[ "${f[2]}" =~ ${HS_FIELD_NUM_RE} ]] || return 0
    [[ "${f[3]}" =~ ${HS_FIELD_NAME_RE} ]] || return 0
    [[ "${f[4]}" =~ ${HS_FIELD_DATE_RE} ]] || return 0
    for ((i = 5; i < n; i++)); do
        [[ "${f[i]}" =~ ${HS_FIELD_NUM_RE} ]] || return 0
    done

    HS_ENTRIES+=("${f[0]}|${f[1]}|${f[2]}|${f[3]}|${f[4]}|${f[5]:-0}|${f[6]:-0}|${f[7]:-0}|${f[8]:-0}|${f[9]:-0}")
    return 0
}

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
        highscore_parse_line "${line}"
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

# --- Ultra mode list ------------------------------------------------------
# The Ultra mode (added 0.10.0) is a race: clear ULTRA_TARGET_ROWS rows
# of credit as fast as possible (see rowhammer.sh). Its results live in
# their own file with their own order - fastest first - for two reasons:
# a timed attempt and an endless round are not comparable by rows, and a
# 150-row sprint must not displace the endless list's top ten.
HSU_MAX=10
HSU_FILE_NAME="highscore-ultra"

# In-memory list, one
# "time|rows|lines|level|name|date|gold|silver|rowhammers|pieces" string
# per element, sorted by time ascending. HSU_LAST_RANK is the rank the
# most recently added run reached (1-based, 0 = not on the list).
#
# The leading time field is the run's play time in MILLISECONDS, not in
# whole seconds like the normal list's: this list is ranked by that very
# number, and two attempts at the same target land in the same second
# often enough that second granularity would decide the ranking by
# arrival order instead of by speed. Formatting for display (later, see
# the header) is fmt_duration_ms's job.
HSU_ENTRIES=()
HSU_LAST_RANK=0

# Field count of a stored Ultra line. A single accepted count on purpose:
# unlike the normal list (HS_FIELD_COUNTS, which tolerates lines written
# before a counter was appended), this format is new and has never
# shipped in a shorter shape, so the project's usual
# no-backward-compatibility rule applies unchanged.
HSU_FIELDS=10

# highscore_ultra_parse_line LINE
# Validate one stored Ultra line and, on success, append it to
# HSU_ENTRIES. Field patterns are shared with the normal list; only the
# layout differs (time first, date fifth from the front). A line that
# fails anywhere is dropped silently, so a damaged file costs single
# entries instead of the game.
highscore_ultra_parse_line() {
    local line="${1}"
    local -a f=()
    local i

    IFS='|' read -r -a f <<< "${line}"
    [ "${#f[@]}" -eq "${HSU_FIELDS}" ] || return 0

    # time, rows, lines, level.
    for ((i = 0; i < 4; i++)); do
        [[ "${f[i]}" =~ ${HS_FIELD_NUM_RE} ]] || return 0
    done
    [[ "${f[4]}" =~ ${HS_FIELD_NAME_RE} ]] || return 0
    [[ "${f[5]}" =~ ${HS_FIELD_DATE_RE} ]] || return 0
    # gold, silver, rowhammers, pieces.
    for ((i = 6; i < HSU_FIELDS; i++)); do
        [[ "${f[i]}" =~ ${HS_FIELD_NUM_RE} ]] || return 0
    done
    # A run without a measured time cannot be ranked against the others;
    # it can only come from a hand-edited file, so drop it here rather
    # than let it take the first place forever.
    [ "${f[0]}" -gt 0 ] || return 0

    HSU_ENTRIES+=("${line}")
    return 0
}

# highscore_ultra_load
# Read the Ultra list into HSU_ENTRIES. Missing file = empty list,
# malformed lines are skipped (see highscore_ultra_parse_line).
highscore_ultra_load() {
    HSU_ENTRIES=()
    local f="${DATA_DIR}/${HSU_FILE_NAME}" line
    if [ ! -r "${f}" ]; then
        return 0
    fi
    while IFS= read -r line; do
        highscore_ultra_parse_line "${line}"
        if [ "${#HSU_ENTRIES[@]}" -ge "${HSU_MAX}" ]; then
            break
        fi
    done < "${f}"
    debug_event "highscore ultra loaded: ${#HSU_ENTRIES[@]} entries from ${f}"
    return 0
}

# highscore_ultra_save
# Write HSU_ENTRIES atomically (temp file + mv), like highscore_save.
highscore_ultra_save() {
    local f="${DATA_DIR}/${HSU_FILE_NAME}" tmp
    mkdir -p -- "${DATA_DIR}"
    tmp="$(mktemp -- "${DATA_DIR}/.${HSU_FILE_NAME}.XXXXXX")"
    # Expanding an empty array under set -u errors on bash < 4.4, so the
    # empty list writes an empty file explicitly.
    if [ "${#HSU_ENTRIES[@]}" -gt 0 ]; then
        printf '%s\n' "${HSU_ENTRIES[@]}" > "${tmp}"
    else
        : > "${tmp}"
    fi
    mv -f -- "${tmp}" "${f}"
    debug_event "highscore ultra saved: ${f} (${#HSU_ENTRIES[@]} entries)"
    return 0
}

# highscore_ultra_add TIME_MS ROWS LINES LEVEL NAME GOLD SILVER ROWHAMMERS PIECES
# Insert one finished Ultra run into the sorted list and persist it.
# TIME_MS is the run's play time in milliseconds and ranks the list,
# fastest first; equal times rank below existing ones, so the older entry
# keeps its place (same tie rule as the normal list). Runs without a
# measured time are ignored, and nothing is written when the run does not
# make the list; HSU_LAST_RANK reports the outcome either way.
#
# Whether a run may be recorded at all is the caller's decision, not this
# function's: record_round (rowhammer.sh) only calls it for a run that
# actually reached the goal, because a timed-out attempt has no time that
# could be compared with the others.
highscore_ultra_add() {
    local time="${1}" rows="${2}" lines="${3}" level="${4}" name="${5}"
    local gold="${6}" silver="${7}" hammers="${8}" pieces="${9}"
    local entry e placed=0 rank=0
    local -a merged=()
    HSU_LAST_RANK=0
    if [ "${time}" -le 0 ]; then
        return 0
    fi
    entry="${time}|${rows}|${lines}|${level}|${name}|$(date +%Y-%m-%d)|${gold}|${silver}|${hammers}|${pieces}"
    if [ "${#HSU_ENTRIES[@]}" -gt 0 ]; then
        for e in "${HSU_ENTRIES[@]}"; do
            if [ "${placed}" -eq 0 ] && [ "${time}" -lt "${e%%|*}" ]; then
                merged+=("${entry}")
                rank="${#merged[@]}"
                placed=1
            fi
            merged+=("${e}")
        done
    fi
    # Slower than every existing entry: append only while there is room.
    if [ "${placed}" -eq 0 ]; then
        if [ "${#merged[@]}" -ge "${HSU_MAX}" ]; then
            debug_event "highscore ultra: '${name}' time=${time}ms outside the top ${HSU_MAX}"
            return 0
        fi
        merged+=("${entry}")
        rank="${#merged[@]}"
    fi
    HSU_ENTRIES=("${merged[@]:0:HSU_MAX}")
    HSU_LAST_RANK="${rank}"
    debug_event "highscore ultra: '${name}' time=${time}ms rows=${rows} enters at rank ${rank}"
    highscore_ultra_save
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
# CHANGE 2026-08-02 (0.11.0): the title says "Marathon" now. The Ultra
# mode has a list of its own (highscore_ultra_screen below), and both are
# reached through the mode picker of the "Highscores" menu entry
# (menu_highscores, lib/menu.sh), so an untitled "Highscores" would no
# longer say which of the two is on screen.
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
    local i line plain rank rank_sgr hs_rows hs_name hs_date hs_gold
    local hs_silver hs_time hs_hammers hs_pieces
    if [ "${#HS_ENTRIES[@]}" -eq 0 ]; then
        body+=("Noch keine Eintraege.")
        body+=("")
        body+=("Spiele eine Runde, um dich einzutragen.")
        debug_event "highscore screen shown (0 entries)"
        menu_message "Highscores - Marathon" "${body[@]}"
        return 0
    fi
    printf -v line '%2s %-12s %6s %5s %10s' \
        "Nr" "Name" "Rows" "Zeit" "Datum"
    body+=("${TXT_BOLD_SGR}${line}${TXT_RESET_SGR}")
    for i in "${!HS_ENTRIES[@]}"; do
        IFS='|' read -r hs_rows _ _ hs_name hs_date hs_gold hs_silver \
            hs_time hs_hammers hs_pieces <<< "${HS_ENTRIES[i]}"
        fmt_duration "${hs_time}"
        rank=$(( i + 1 ))
        printf -v plain '%2d %-12.12s %6d %5s %10s' \
            "${rank}" "${hs_name}" "${hs_rows}" "${FMT_DURATION}" \
            "${hs_date}"
        # Color only the common case (plausible values, still within the
        # 46-char budget); an implausibly long line (a hand-edited file -
        # HS_FIELD_NUM_RE has no digit cap) falls back to the plain
        # truncated text instead of risking a cut escape sequence.
        if [ "${#plain}" -le 46 ]; then
            rank_sgr="${TXT_ACCENT_SGR}"
            case "${rank}" in
                1) rank_sgr="${TXT_GOLD_SGR}" ;;
                2) rank_sgr="${TXT_SILVER_SGR}" ;;
            esac
            printf -v line '%s%2d%s %-12.12s %s%6d%s %5s %10s' \
                "${rank_sgr}" "${rank}" "${TXT_RESET_SGR}" "${hs_name}" \
                "${TXT_ACCENT_SGR}" "${hs_rows}" "${TXT_RESET_SGR}" \
                "${FMT_DURATION}" "${hs_date}"
            body+=("${line}")
        else
            body+=("${plain:0:46}")
        fi
        fmt_ppm "${hs_pieces}" "${hs_time}"
        printf -v plain '  Gold %3d Silb %3d RH %2d PCS %4d PPM %5s' \
            "${hs_gold}" "${hs_silver}" "${hs_hammers}" "${hs_pieces}" \
            "${FMT_PPM}"
        if [ "${#plain}" -le 46 ]; then
            printf -v line '  %sGold %3d%s %sSilb %3d%s %sRH %2d%s PCS %4d PPM %5s' \
                "${TXT_GOLD_SGR}" "${hs_gold}" "${TXT_RESET_SGR}" \
                "${TXT_SILVER_SGR}" "${hs_silver}" "${TXT_RESET_SGR}" \
                "${TXT_WARN_SGR}" "${hs_hammers}" "${TXT_RESET_SGR}" \
                "${hs_pieces}" "${FMT_PPM}"
            body+=("${line}")
        else
            body+=("${plain:0:46}")
        fi
        body+=("")
    done
    debug_event "highscore screen shown (${#HS_ENTRIES[@]} entries)"
    menu_pages "Highscores - Marathon" 1 "${HS_PAGE_LINES}" "${body[@]}"
    return 0
}

# highscore_ultra_screen
# Show the Ultra list the same way highscore_screen shows the Marathon
# one: paged via menu_pages, two lines per entry, same column widths and
# the same coloring rules, so switching between the two screens in the
# mode picker (menu_highscores, lib/menu.sh) is a change of numbers, not
# of layout. Reuses HS_PAGE_ENTRIES/HS_PAGE_LINES for that reason - the
# entry height is identical, so a separate pair of constants could only
# ever drift apart from them.
# Two things differ, both because this list ranks by time:
#   - the time column is the score here, so it carries the accent color
#     the Marathon screen puts on Rows, and it is printed by
#     fmt_duration_ms as MM:SS.mmm (the stored value is milliseconds, see
#     HSU_ENTRIES above) rather than by fmt_duration as MM:SS. Rows stay
#     visible next to it: an Ultra run ends at or beyond
#     ULTRA_TARGET_ROWS, and by how far it overshot is worth seeing.
#   - PPM is computed from the milliseconds divided down to whole
#     seconds, the unit fmt_ppm takes (and the unit the Marathon list
#     stores in the first place).
# Added 0.11.0 (user decision): 0.10.0 deliberately shipped the storage
# without a screen, this is the screen.
highscore_ultra_screen() {
    local -a body=()
    local i line plain rank rank_sgr hsu_time hsu_rows hsu_name hsu_date
    local hsu_gold hsu_silver hsu_hammers hsu_pieces
    if [ "${#HSU_ENTRIES[@]}" -eq 0 ]; then
        body+=("Noch keine Eintraege.")
        body+=("")
        body+=("Erreiche das Ziel von ${ULTRA_TARGET_ROWS} Rows in einer")
        body+=("Ultra-Runde, um dich einzutragen. Ein Versuch,")
        body+=("der vorher im Game Over endet, wird nicht")
        body+=("gewertet.")
        debug_event "highscore ultra screen shown (0 entries)"
        menu_message "Highscores - Ultra" "${body[@]}"
        return 0
    fi
    printf -v line '%2s %-12s %6s %9s %10s' \
        "Nr" "Name" "Rows" "Zeit" "Datum"
    body+=("${TXT_BOLD_SGR}${line}${TXT_RESET_SGR}")
    for i in "${!HSU_ENTRIES[@]}"; do
        IFS='|' read -r hsu_time hsu_rows _ _ hsu_name hsu_date hsu_gold \
            hsu_silver hsu_hammers hsu_pieces <<< "${HSU_ENTRIES[i]}"
        fmt_duration_ms "${hsu_time}"
        rank=$(( i + 1 ))
        printf -v plain '%2d %-12.12s %6d %9s %10s' \
            "${rank}" "${hsu_name}" "${hsu_rows}" "${FMT_DURATION_MS}" \
            "${hsu_date}"
        # Same guard as the Marathon screen: color only while the line
        # stays within the 46-char budget, so a hand-edited file with
        # implausible numbers costs the colors, never a cut escape
        # sequence.
        if [ "${#plain}" -le 46 ]; then
            rank_sgr="${TXT_ACCENT_SGR}"
            case "${rank}" in
                1) rank_sgr="${TXT_GOLD_SGR}" ;;
                2) rank_sgr="${TXT_SILVER_SGR}" ;;
            esac
            printf -v line '%s%2d%s %-12.12s %6d %s%9s%s %10s' \
                "${rank_sgr}" "${rank}" "${TXT_RESET_SGR}" "${hsu_name}" \
                "${hsu_rows}" "${TXT_ACCENT_SGR}" "${FMT_DURATION_MS}" \
                "${TXT_RESET_SGR}" "${hsu_date}"
            body+=("${line}")
        else
            body+=("${plain:0:46}")
        fi
        fmt_ppm "${hsu_pieces}" "$(( hsu_time / 1000 ))"
        printf -v plain '  Gold %3d Silb %3d RH %2d PCS %4d PPM %5s' \
            "${hsu_gold}" "${hsu_silver}" "${hsu_hammers}" "${hsu_pieces}" \
            "${FMT_PPM}"
        if [ "${#plain}" -le 46 ]; then
            printf -v line '  %sGold %3d%s %sSilb %3d%s %sRH %2d%s PCS %4d PPM %5s' \
                "${TXT_GOLD_SGR}" "${hsu_gold}" "${TXT_RESET_SGR}" \
                "${TXT_SILVER_SGR}" "${hsu_silver}" "${TXT_RESET_SGR}" \
                "${TXT_WARN_SGR}" "${hsu_hammers}" "${TXT_RESET_SGR}" \
                "${hsu_pieces}" "${FMT_PPM}"
            body+=("${line}")
        else
            body+=("${plain:0:46}")
        fi
        body+=("")
    done
    debug_event "highscore ultra screen shown (${#HSU_ENTRIES[@]} entries)"
    menu_pages "Highscores - Ultra" 1 "${HS_PAGE_LINES}" "${body[@]}"
    return 0
}
