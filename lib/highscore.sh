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
#   Since 0.12.0 the Sprint mode (as much row credit as possible within
#   SPRINT_TIME_MS, see rowhammer.sh) has a list of its own as well, in
#   ${DATA_DIR}/highscore-sprint, built from the HSS_* globals and
#   functions at the end of this file. It ranks by rows like the Marathon
#   list, but three minutes and an open-ended round measure entirely
#   different things, so they must not share a top ten either. Only runs
#   that used their full time are stored, mirroring the Ultra rule - a
#   Sprint attempt that topped out after a minute has fewer rows for a
#   reason that has nothing to do with how well it was played.
#   Since 0.13.0 the Time Attack mode (a countdown the run extends by a
#   second per row of credit, see rowhammer.sh) has the fourth list, in
#   ${DATA_DIR}/highscore-timeattack, built from the HSA_* globals and
#   functions at the end of this file. It ranks by rows like the
#   Marathon and the Sprint list - the rows and the time survived are
#   the same ordering there, so the game's scoring currency wins the tie
#   - but keeps its own file, because a run on a self-earned minute is
#   not the achievement an endless round is. Unlike the other two timed
#   lists it stores every run, finished or topped out: this mode has no
#   incomparable "did not finish" state (see highscore_timeattack_add).
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.14.0  (2026-08-03)

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
# The round hash (round_hash in rowhammer.sh) that every list carries as
# its last field since 0.46.0: eight hex digits, or "-" for an entry
# written before the field existed. It ties an entry to the demo
# recording of the same round, whose file name carries it too - which is
# how the demo pruning knows which recordings still back a highscore and
# must be kept (see demo_prune in lib/demo.sh).
HS_FIELD_HASH_RE='^([0-9a-f]{8}|-)$'

# Field counts accepted for a stored line: the mandatory "rows|lines|
# level|name|date" prefix (5 fields), optionally extended by gold and
# silver together (7), then time (8), then rowhammers (9), then pieces
# (10), then the round hash (11) - exactly the order these fields were
# appended after the 0.4.0
# scoring rebuild made rows the leading field. Any other count (an old
# pre-rebuild line, or something simply broken) is rejected by
# highscore_parse_line before it looks at individual fields.
HS_FIELD_COUNTS=(5 7 8 9 10 11)

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
    # The counters; the eleventh field is the round hash, not a number.
    for ((i = 5; i < n && i < 10; i++)); do
        [[ "${f[i]}" =~ ${HS_FIELD_NUM_RE} ]] || return 0
    done
    if [ "${n}" -ge 11 ]; then
        [[ "${f[10]}" =~ ${HS_FIELD_HASH_RE} ]] || return 0
    fi

    HS_ENTRIES+=("${f[0]}|${f[1]}|${f[2]}|${f[3]}|${f[4]}|${f[5]:-0}|${f[6]:-0}|${f[7]:-0}|${f[8]:-0}|${f[9]:-0}|${f[10]:--}")
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

# highscore_add ROWS LINES LEVEL NAME GOLD SILVER TIME ROWHAMMERS PIECES HASH
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
    local pieces="${9}" hash="${10:--}"
    local entry e placed=0 rank=0
    local -a merged=()
    HS_LAST_RANK=0
    if [ "${rows}" -le 0 ]; then
        return 0
    fi
    entry="${rows}|${lines}|${level}|${name}|$(date +%Y-%m-%d)|${gold}|${silver}|${time}|${hammers}|${pieces}|${hash}"
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

# highscore_hash_set
# Collect the round hashes of every list into the associative array
# HS_HASH_SET (the hash is the key, the value is always 1). It is what
# the demo pruning asks: a recording whose hash is in here still backs a
# highscore entry and must not be deleted (demo_prune in lib/demo.sh).
# All four formats carry the hash as their last field, so one expansion
# fits them all. Entries written before the field existed carry "-",
# which is filtered out here - it would otherwise protect every old
# recording at once.
declare -A HS_HASH_SET=()
highscore_hash_set() {
    local e h
    local -a lists=()
    HS_HASH_SET=()
    # Expanding an empty array trips set -u on bash < 4.4, so each list
    # is only added when it holds something. Spelled as if-statements
    # rather than "[ ... ] && ..." so no line can end the function with a
    # non-zero status under set -e.
    if [ "${#HS_ENTRIES[@]}" -gt 0 ]; then
        lists+=("${HS_ENTRIES[@]}")
    fi
    if [ "${#HSU_ENTRIES[@]}" -gt 0 ]; then
        lists+=("${HSU_ENTRIES[@]}")
    fi
    if [ "${#HSS_ENTRIES[@]}" -gt 0 ]; then
        lists+=("${HSS_ENTRIES[@]}")
    fi
    if [ "${#HSA_ENTRIES[@]}" -gt 0 ]; then
        lists+=("${HSA_ENTRIES[@]}")
    fi
    if [ "${#lists[@]}" -eq 0 ]; then
        return 0
    fi
    for e in "${lists[@]}"; do
        h="${e##*|}"
        if [[ "${h}" =~ ^[0-9a-f]{8}$ ]]; then
            HS_HASH_SET["${h}"]=1
        fi
    done
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

# Field counts of a stored Ultra line: 11 fields, or 10 for a line
# written before the round hash was appended in 0.46.0. The same
# tolerance the Marathon list has always had (HS_FIELD_COUNTS) and for
# the same reason - an entry must not disappear just because it is older
# than a field. It is a deliberate exception from the project's
# no-backward-compatibility rule, kept narrow: exactly these two counts,
# and the missing hash reads as "-" (no recording tied to this entry).
HSU_FIELDS=11
HSU_FIELDS_HASHLESS=10

# highscore_ultra_parse_line LINE
# Validate one stored Ultra line and, on success, append it to
# HSU_ENTRIES. Field patterns are shared with the normal list; only the
# layout differs (time first, date fifth from the front). A line that
# fails anywhere is dropped silently, so a damaged file costs single
# entries instead of the game.
highscore_ultra_parse_line() {
    local line="${1}"
    local -a f=()
    local i n

    IFS='|' read -r -a f <<< "${line}"
    n="${#f[@]}"
    [ "${n}" -eq "${HSU_FIELDS}" ] || [ "${n}" -eq "${HSU_FIELDS_HASHLESS}" ] \
        || return 0

    # time, rows, lines, level.
    for ((i = 0; i < 4; i++)); do
        [[ "${f[i]}" =~ ${HS_FIELD_NUM_RE} ]] || return 0
    done
    [[ "${f[4]}" =~ ${HS_FIELD_NAME_RE} ]] || return 0
    [[ "${f[5]}" =~ ${HS_FIELD_DATE_RE} ]] || return 0
    # gold, silver, rowhammers, pieces.
    for ((i = 6; i < HSU_FIELDS_HASHLESS; i++)); do
        [[ "${f[i]}" =~ ${HS_FIELD_NUM_RE} ]] || return 0
    done
    if [ "${n}" -eq "${HSU_FIELDS}" ]; then
        [[ "${f[HSU_FIELDS_HASHLESS]}" =~ ${HS_FIELD_HASH_RE} ]] || return 0
    fi
    # A run without a measured time cannot be ranked against the others;
    # it can only come from a hand-edited file, so drop it here rather
    # than let it take the first place forever.
    [ "${f[0]}" -gt 0 ] || return 0

    # Normalized to the full field count, so everything reading an entry
    # can rely on the hash being there (as "-" when the line predates it).
    if [ "${n}" -eq "${HSU_FIELDS_HASHLESS}" ]; then
        HSU_ENTRIES+=("${line}|-")
    else
        HSU_ENTRIES+=("${line}")
    fi
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

# highscore_ultra_add TIME_MS ROWS LINES LEVEL NAME GOLD SILVER ROWHAMMERS
#                     PIECES HASH
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
    local hash="${10:--}"
    local entry e placed=0 rank=0
    local -a merged=()
    HSU_LAST_RANK=0
    if [ "${time}" -le 0 ]; then
        return 0
    fi
    entry="${time}|${rows}|${lines}|${level}|${name}|$(date +%Y-%m-%d)|${gold}|${silver}|${hammers}|${pieces}|${hash}"
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
        # The trailing "_" takes the round hash: the last variable of a
        # read absorbs everything left of the line, so without it the
        # pieces column would read "57|d2949228".
        IFS='|' read -r hs_rows _ _ hs_name hs_date hs_gold hs_silver \
            hs_time hs_hammers hs_pieces _ <<< "${HS_ENTRIES[i]}"
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
            hsu_silver hsu_hammers hsu_pieces _ <<< "${HSU_ENTRIES[i]}"
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

# --- Sprint mode list -----------------------------------------------------
# The Sprint mode (added 0.12.0) is the mirror image of Ultra: score as
# much row credit as possible within SPRINT_TIME_MS - three minutes - of
# play time (see rowhammer.sh). Its results live in their own file for
# the same reason the Ultra ones do, even though this list ranks by rows
# just like the Marathon one: a run cut off after three minutes and an
# endless round that ends only on a top-out are not the same achievement,
# and mixing them would mean the endless list's top ten decides how a
# three minute run "did".
HSS_MAX=10
HSS_FILE_NAME="highscore-sprint"

# In-memory list, one
# "rows|lines|level|name|date|gold|silver|time|rowhammers|pieces" string
# per element, sorted by rows descending. HSS_LAST_RANK is the rank the
# most recently added run reached (1-based, 0 = not on the list).
#
# Deliberately the same field layout as the Marathon list: a Sprint run
# is scored by the same number in the same unit, so a second layout
# would only be a second thing to keep in step. The time field is the
# run's play time in whole seconds - practically always SPRINT_TIME_MS
# divided down, but it is what the PCS/min column is computed from, and
# it is the honest record of how long the run really ran.
HSS_ENTRIES=()
HSS_LAST_RANK=0

# Field counts of a stored Sprint line: 11 fields, or 10 for a line
# written before the round hash was appended in 0.46.0 - the same
# tolerance the Marathon list has always had (HS_FIELD_COUNTS), for the
# same reason: an entry must not disappear just because it is older than
# a field. A missing hash reads as "-" (no recording tied to this entry).
HSS_FIELDS=11
HSS_FIELDS_HASHLESS=10

# highscore_sprint_parse_line LINE
# Validate one stored Sprint line and, on success, append it to
# HSS_ENTRIES. Field patterns are shared with the other two lists; the
# layout is the Marathon one. A line that fails anywhere is dropped
# silently, so a damaged file costs single entries instead of the game.
highscore_sprint_parse_line() {
    local line="${1}"
    local -a f=()
    local i n

    IFS='|' read -r -a f <<< "${line}"
    n="${#f[@]}"
    [ "${n}" -eq "${HSS_FIELDS}" ] || [ "${n}" -eq "${HSS_FIELDS_HASHLESS}" ] \
        || return 0

    # rows, lines, level.
    for ((i = 0; i < 3; i++)); do
        [[ "${f[i]}" =~ ${HS_FIELD_NUM_RE} ]] || return 0
    done
    [[ "${f[3]}" =~ ${HS_FIELD_NAME_RE} ]] || return 0
    [[ "${f[4]}" =~ ${HS_FIELD_DATE_RE} ]] || return 0
    # gold, silver, time, rowhammers, pieces.
    for ((i = 5; i < HSS_FIELDS_HASHLESS; i++)); do
        [[ "${f[i]}" =~ ${HS_FIELD_NUM_RE} ]] || return 0
    done
    if [ "${n}" -eq "${HSS_FIELDS}" ]; then
        [[ "${f[HSS_FIELDS_HASHLESS]}" =~ ${HS_FIELD_HASH_RE} ]] || return 0
    fi

    # Normalized to the full field count, so everything reading an entry
    # can rely on the hash being there (as "-" when the line predates it).
    if [ "${n}" -eq "${HSS_FIELDS_HASHLESS}" ]; then
        HSS_ENTRIES+=("${line}|-")
    else
        HSS_ENTRIES+=("${line}")
    fi
    return 0
}

# highscore_sprint_load
# Read the Sprint list into HSS_ENTRIES. Missing file = empty list,
# malformed lines are skipped (see highscore_sprint_parse_line).
highscore_sprint_load() {
    HSS_ENTRIES=()
    local f="${DATA_DIR}/${HSS_FILE_NAME}" line
    if [ ! -r "${f}" ]; then
        return 0
    fi
    while IFS= read -r line; do
        highscore_sprint_parse_line "${line}"
        if [ "${#HSS_ENTRIES[@]}" -ge "${HSS_MAX}" ]; then
            break
        fi
    done < "${f}"
    debug_event "highscore sprint loaded: ${#HSS_ENTRIES[@]} entries from ${f}"
    return 0
}

# highscore_sprint_save
# Write HSS_ENTRIES atomically (temp file + mv), like highscore_save.
highscore_sprint_save() {
    local f="${DATA_DIR}/${HSS_FILE_NAME}" tmp
    mkdir -p -- "${DATA_DIR}"
    tmp="$(mktemp -- "${DATA_DIR}/.${HSS_FILE_NAME}.XXXXXX")"
    # Expanding an empty array under set -u errors on bash < 4.4, so the
    # empty list writes an empty file explicitly.
    if [ "${#HSS_ENTRIES[@]}" -gt 0 ]; then
        printf '%s\n' "${HSS_ENTRIES[@]}" > "${tmp}"
    else
        : > "${tmp}"
    fi
    mv -f -- "${tmp}" "${f}"
    debug_event "highscore sprint saved: ${f} (${#HSS_ENTRIES[@]} entries)"
    return 0
}

# highscore_sprint_add ROWS LINES LEVEL NAME GOLD SILVER TIME ROWHAMMERS
#                      PIECES HASH
# Insert one finished Sprint run into the sorted list and persist it.
# Arguments and order are the Marathon list's (highscore_add), TIME again
# the play time in whole seconds; equal row credits rank below existing
# ones, so the older entry keeps its place. Runs without a single row are
# ignored, and nothing is written when the run does not make the list;
# HSS_LAST_RANK reports the outcome either way.
#
# Whether a run may be recorded at all is the caller's decision, not this
# function's: record_round (rowhammer.sh) only calls it for a run that
# played its full three minutes, because an attempt that topped out early
# had less time to score in and cannot be compared with the others.
highscore_sprint_add() {
    local rows="${1}" lines="${2}" level="${3}" name="${4}"
    local gold="${5}" silver="${6}" time="${7}" hammers="${8}"
    local pieces="${9}" hash="${10:--}"
    local entry e placed=0 rank=0
    local -a merged=()
    HSS_LAST_RANK=0
    if [ "${rows}" -le 0 ]; then
        return 0
    fi
    entry="${rows}|${lines}|${level}|${name}|$(date +%Y-%m-%d)|${gold}|${silver}|${time}|${hammers}|${pieces}|${hash}"
    if [ "${#HSS_ENTRIES[@]}" -gt 0 ]; then
        for e in "${HSS_ENTRIES[@]}"; do
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
        if [ "${#merged[@]}" -ge "${HSS_MAX}" ]; then
            debug_event "highscore sprint: '${name}' rows=${rows} below the top ${HSS_MAX}"
            return 0
        fi
        merged+=("${entry}")
        rank="${#merged[@]}"
    fi
    HSS_ENTRIES=("${merged[@]:0:HSS_MAX}")
    HSS_LAST_RANK="${rank}"
    debug_event "highscore sprint: '${name}' rows=${rows} enters at rank ${rank}"
    highscore_sprint_save
    return 0
}

# highscore_sprint_screen
# Show the Sprint list the way the other two screens show theirs: paged
# via menu_pages (HS_PAGE_ENTRIES/HS_PAGE_LINES again - identical entry
# height, and a fourth pair of constants could only drift), two lines per
# entry, same column widths and the same coloring rules. Rows rank this
# list and therefore carry the accent color, as on the Marathon screen.
# One column differs: where the Marathon screen shows the round's play
# time, this one shows the physical lines cleared. Every entry here ran
# the same three minutes, so a time column would print the same value ten
# times; the lines are the interesting number next to the weighted rows -
# together they show how much of the score came out of the gold and
# silver squares. The play time stays stored (it is what the PPM column
# on the second line is computed from), it is just not worth a column of
# its own in this mode.
highscore_sprint_screen() {
    local -a body=()
    local i line plain rank rank_sgr hss_rows hss_lines hss_name hss_date
    local hss_gold hss_silver hss_time hss_hammers hss_pieces
    if [ "${#HSS_ENTRIES[@]}" -eq 0 ]; then
        fmt_duration $(( SPRINT_TIME_MS / 1000 ))
        body+=("Noch keine Eintraege.")
        body+=("")
        body+=("Spiele eine Sprint-Runde ueber die vollen")
        body+=("${FMT_DURATION} Minuten, um dich einzutragen. Ein")
        body+=("Versuch, der vorher im Game Over endet, wird")
        body+=("nicht gewertet.")
        debug_event "highscore sprint screen shown (0 entries)"
        menu_message "Highscores - Sprint" "${body[@]}"
        return 0
    fi
    printf -v line '%2s %-12s %6s %5s %10s' \
        "Nr" "Name" "Rows" "Lines" "Datum"
    body+=("${TXT_BOLD_SGR}${line}${TXT_RESET_SGR}")
    for i in "${!HSS_ENTRIES[@]}"; do
        IFS='|' read -r hss_rows hss_lines _ hss_name hss_date hss_gold \
            hss_silver hss_time hss_hammers hss_pieces _ <<< "${HSS_ENTRIES[i]}"
        rank=$(( i + 1 ))
        printf -v plain '%2d %-12.12s %6d %5d %10s' \
            "${rank}" "${hss_name}" "${hss_rows}" "${hss_lines}" \
            "${hss_date}"
        # Same guard as the other two screens: color only while the line
        # stays within the 46-char budget, so a hand-edited file with
        # implausible numbers costs the colors, never a cut escape
        # sequence.
        if [ "${#plain}" -le 46 ]; then
            rank_sgr="${TXT_ACCENT_SGR}"
            case "${rank}" in
                1) rank_sgr="${TXT_GOLD_SGR}" ;;
                2) rank_sgr="${TXT_SILVER_SGR}" ;;
            esac
            printf -v line '%s%2d%s %-12.12s %s%6d%s %5d %10s' \
                "${rank_sgr}" "${rank}" "${TXT_RESET_SGR}" "${hss_name}" \
                "${TXT_ACCENT_SGR}" "${hss_rows}" "${TXT_RESET_SGR}" \
                "${hss_lines}" "${hss_date}"
            body+=("${line}")
        else
            body+=("${plain:0:46}")
        fi
        fmt_ppm "${hss_pieces}" "${hss_time}"
        printf -v plain '  Gold %3d Silb %3d RH %2d PCS %4d PPM %5s' \
            "${hss_gold}" "${hss_silver}" "${hss_hammers}" "${hss_pieces}" \
            "${FMT_PPM}"
        if [ "${#plain}" -le 46 ]; then
            printf -v line '  %sGold %3d%s %sSilb %3d%s %sRH %2d%s PCS %4d PPM %5s' \
                "${TXT_GOLD_SGR}" "${hss_gold}" "${TXT_RESET_SGR}" \
                "${TXT_SILVER_SGR}" "${hss_silver}" "${TXT_RESET_SGR}" \
                "${TXT_WARN_SGR}" "${hss_hammers}" "${TXT_RESET_SGR}" \
                "${hss_pieces}" "${FMT_PPM}"
            body+=("${line}")
        else
            body+=("${plain:0:46}")
        fi
        body+=("")
    done
    debug_event "highscore sprint screen shown (${#HSS_ENTRIES[@]} entries)"
    menu_pages "Highscores - Sprint" 1 "${HS_PAGE_LINES}" "${body[@]}"
    return 0
}

# --- Time Attack mode list ------------------------------------------------
# The Time Attack mode (added 0.13.0, user request) starts with
# TIME_ATTACK_START_MS on a clock running backwards and pays
# TIME_ATTACK_ROW_MS back per row of credit, so a run lasts exactly as
# long as it keeps feeding itself (see rowhammer.sh). Its results live in
# their own file for the reason the other two timed modes have theirs: a
# run on a self-earned minute and an endless round that ends only on a
# top-out are not the same achievement.
#
# What the score is was worth a moment's thought, because two candidates
# offer themselves - the rows scored and the time survived. They are the
# same ordering: a run that ends on the clock has played exactly
# TIME_ATTACK_START_MS plus TIME_ATTACK_ROW_MS per row, so its time is a
# function of its rows and could only ever rank them in the same
# sequence. Rows win as the stored score because they are the game's
# scoring currency everywhere else (see the note in rowhammer.sh), and
# because they stay meaningful for the run that topped out early, where
# the equation no longer holds. The time is kept and shown next to them:
# for a run cut short by the stack it is the one number that says so.
HSA_MAX=10
HSA_FILE_NAME="highscore-timeattack"

# In-memory list, one
# "rows|lines|level|name|date|gold|silver|time|rowhammers|pieces" string
# per element, sorted by rows descending. HSA_LAST_RANK is the rank the
# most recently added run reached (1-based, 0 = not on the list).
#
# The Marathon list's field layout again, for the reason the Sprint list
# reuses it: the same number in the same unit ranks it, so a third layout
# would only be a third thing to keep in step.
HSA_ENTRIES=()
HSA_LAST_RANK=0

# Field counts of a stored Time Attack line: 11 fields, or 10 for a line
# written before the round hash was appended in 0.46.0 - the same
# tolerance the Marathon list has always had (HS_FIELD_COUNTS), for the
# same reason: an entry must not disappear just because it is older than
# a field. A missing hash reads as "-" (no recording tied to this entry).
HSA_FIELDS=11
HSA_FIELDS_HASHLESS=10

# highscore_timeattack_parse_line LINE
# Validate one stored Time Attack line and, on success, append it to
# HSA_ENTRIES. Field patterns and layout are the Marathon list's; a line
# that fails anywhere is dropped silently, so a damaged file costs single
# entries instead of the game.
highscore_timeattack_parse_line() {
    local line="${1}"
    local -a f=()
    local i n

    IFS='|' read -r -a f <<< "${line}"
    n="${#f[@]}"
    [ "${n}" -eq "${HSA_FIELDS}" ] || [ "${n}" -eq "${HSA_FIELDS_HASHLESS}" ] \
        || return 0

    # rows, lines, level.
    for ((i = 0; i < 3; i++)); do
        [[ "${f[i]}" =~ ${HS_FIELD_NUM_RE} ]] || return 0
    done
    [[ "${f[3]}" =~ ${HS_FIELD_NAME_RE} ]] || return 0
    [[ "${f[4]}" =~ ${HS_FIELD_DATE_RE} ]] || return 0
    # gold, silver, time, rowhammers, pieces.
    for ((i = 5; i < HSA_FIELDS_HASHLESS; i++)); do
        [[ "${f[i]}" =~ ${HS_FIELD_NUM_RE} ]] || return 0
    done
    if [ "${n}" -eq "${HSA_FIELDS}" ]; then
        [[ "${f[HSA_FIELDS_HASHLESS]}" =~ ${HS_FIELD_HASH_RE} ]] || return 0
    fi

    # Normalized to the full field count, so everything reading an entry
    # can rely on the hash being there (as "-" when the line predates it).
    if [ "${n}" -eq "${HSA_FIELDS_HASHLESS}" ]; then
        HSA_ENTRIES+=("${line}|-")
    else
        HSA_ENTRIES+=("${line}")
    fi
    return 0
}

# highscore_timeattack_load
# Read the Time Attack list into HSA_ENTRIES. Missing file = empty list,
# malformed lines are skipped (highscore_timeattack_parse_line).
highscore_timeattack_load() {
    HSA_ENTRIES=()
    local f="${DATA_DIR}/${HSA_FILE_NAME}" line
    if [ ! -r "${f}" ]; then
        return 0
    fi
    while IFS= read -r line; do
        highscore_timeattack_parse_line "${line}"
        if [ "${#HSA_ENTRIES[@]}" -ge "${HSA_MAX}" ]; then
            break
        fi
    done < "${f}"
    debug_event "highscore timeattack loaded: ${#HSA_ENTRIES[@]} entries from ${f}"
    return 0
}

# highscore_timeattack_save
# Write HSA_ENTRIES atomically (temp file + mv), like highscore_save.
highscore_timeattack_save() {
    local f="${DATA_DIR}/${HSA_FILE_NAME}" tmp
    mkdir -p -- "${DATA_DIR}"
    tmp="$(mktemp -- "${DATA_DIR}/.${HSA_FILE_NAME}.XXXXXX")"
    # Expanding an empty array under set -u errors on bash < 4.4, so the
    # empty list writes an empty file explicitly.
    if [ "${#HSA_ENTRIES[@]}" -gt 0 ]; then
        printf '%s\n' "${HSA_ENTRIES[@]}" > "${tmp}"
    else
        : > "${tmp}"
    fi
    mv -f -- "${tmp}" "${f}"
    debug_event "highscore timeattack saved: ${f} (${#HSA_ENTRIES[@]} entries)"
    return 0
}

# highscore_timeattack_add ROWS LINES LEVEL NAME GOLD SILVER TIME ROWHAMMERS
#                      PIECES HASH
# Insert one finished Time Attack run into the sorted list and persist
# it. Arguments and order are the Marathon list's (highscore_add), TIME
# the play time in whole seconds - here the time the run survived, which
# is what it bought itself. Equal row credits rank below existing ones,
# so the older entry keeps its place. Runs without a single row are
# ignored, and nothing is written when the run does not make the list;
# HSA_LAST_RANK reports the outcome either way.
#
# Unlike the Ultra and the Sprint list this one takes every run its
# caller hands it, finished or topped out (see record_round in
# rowhammer.sh): this mode has no incomparable "did not finish" state -
# the rows are the same achievement either way, and a run that ended
# early simply has fewer of them.
highscore_timeattack_add() {
    local rows="${1}" lines="${2}" level="${3}" name="${4}"
    local gold="${5}" silver="${6}" time="${7}" hammers="${8}"
    local pieces="${9}" hash="${10:--}"
    local entry e placed=0 rank=0
    local -a merged=()
    HSA_LAST_RANK=0
    if [ "${rows}" -le 0 ]; then
        return 0
    fi
    entry="${rows}|${lines}|${level}|${name}|$(date +%Y-%m-%d)|${gold}|${silver}|${time}|${hammers}|${pieces}|${hash}"
    if [ "${#HSA_ENTRIES[@]}" -gt 0 ]; then
        for e in "${HSA_ENTRIES[@]}"; do
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
        if [ "${#merged[@]}" -ge "${HSA_MAX}" ]; then
            debug_event "highscore timeattack: '${name}' rows=${rows} below the top ${HSA_MAX}"
            return 0
        fi
        merged+=("${entry}")
        rank="${#merged[@]}"
    fi
    HSA_ENTRIES=("${merged[@]:0:HSA_MAX}")
    HSA_LAST_RANK="${rank}"
    debug_event "highscore timeattack: '${name}' rows=${rows} time=${time}s enters at rank ${rank}"
    highscore_timeattack_save
    return 0
}

# highscore_timeattack_screen
# Show the Time Attack list the way the other three screens show theirs:
# paged via menu_pages (HS_PAGE_ENTRIES/HS_PAGE_LINES again), two lines
# per entry, same column widths and the same coloring rules. Rows rank
# this list and therefore carry the accent color, as on the Marathon and
# the Sprint screen.
# The columns are the Marathon ones down to the play time, which is the
# column that earns its place here: it is the time the run survived, and
# because a finished run survives exactly the start time plus a second
# per row, an entry whose time falls short of that is one the stack
# ended early - the single number that tells the two apart.
highscore_timeattack_screen() {
    local -a body=()
    local i line plain rank rank_sgr hsa_rows hsa_name hsa_date hsa_gold
    local hsa_silver hsa_time hsa_hammers hsa_pieces
    if [ "${#HSA_ENTRIES[@]}" -eq 0 ]; then
        fmt_duration $(( TIME_ATTACK_START_MS / 1000 ))
        body+=("Noch keine Eintraege.")
        body+=("")
        body+=("Spiele eine Time-Attack-Runde: sie startet")
        body+=("mit ${FMT_DURATION} Minuten Restzeit, und jede Row")
        body+=("bringt eine Sekunde dazu. Gewertet wird")
        body+=("jeder Lauf - auch ein vorzeitiges Game Over.")
        debug_event "highscore timeattack screen shown (0 entries)"
        menu_message "Highscores - Time Attack" "${body[@]}"
        return 0
    fi
    printf -v line '%2s %-12s %6s %5s %10s' \
        "Nr" "Name" "Rows" "Zeit" "Datum"
    body+=("${TXT_BOLD_SGR}${line}${TXT_RESET_SGR}")
    for i in "${!HSA_ENTRIES[@]}"; do
        IFS='|' read -r hsa_rows _ _ hsa_name hsa_date hsa_gold \
            hsa_silver hsa_time hsa_hammers hsa_pieces _ <<< "${HSA_ENTRIES[i]}"
        fmt_duration "${hsa_time}"
        rank=$(( i + 1 ))
        printf -v plain '%2d %-12.12s %6d %5s %10s' \
            "${rank}" "${hsa_name}" "${hsa_rows}" "${FMT_DURATION}" \
            "${hsa_date}"
        # Same guard as the other three screens: color only while the
        # line stays within the 46-char budget, so a hand-edited file
        # with implausible numbers costs the colors, never a cut escape
        # sequence.
        if [ "${#plain}" -le 46 ]; then
            rank_sgr="${TXT_ACCENT_SGR}"
            case "${rank}" in
                1) rank_sgr="${TXT_GOLD_SGR}" ;;
                2) rank_sgr="${TXT_SILVER_SGR}" ;;
            esac
            printf -v line '%s%2d%s %-12.12s %s%6d%s %5s %10s' \
                "${rank_sgr}" "${rank}" "${TXT_RESET_SGR}" "${hsa_name}" \
                "${TXT_ACCENT_SGR}" "${hsa_rows}" "${TXT_RESET_SGR}" \
                "${FMT_DURATION}" "${hsa_date}"
            body+=("${line}")
        else
            body+=("${plain:0:46}")
        fi
        fmt_ppm "${hsa_pieces}" "${hsa_time}"
        printf -v plain '  Gold %3d Silb %3d RH %2d PCS %4d PPM %5s' \
            "${hsa_gold}" "${hsa_silver}" "${hsa_hammers}" "${hsa_pieces}" \
            "${FMT_PPM}"
        if [ "${#plain}" -le 46 ]; then
            printf -v line '  %sGold %3d%s %sSilb %3d%s %sRH %2d%s PCS %4d PPM %5s' \
                "${TXT_GOLD_SGR}" "${hsa_gold}" "${TXT_RESET_SGR}" \
                "${TXT_SILVER_SGR}" "${hsa_silver}" "${TXT_RESET_SGR}" \
                "${TXT_WARN_SGR}" "${hsa_hammers}" "${TXT_RESET_SGR}" \
                "${hsa_pieces}" "${FMT_PPM}"
            body+=("${line}")
        else
            body+=("${plain:0:46}")
        fi
        body+=("")
    done
    debug_event "highscore timeattack screen shown (${#HSA_ENTRIES[@]} entries)"
    menu_pages "Highscores - Time Attack" 1 "${HS_PAGE_LINES}" "${body[@]}"
    return 0
}
