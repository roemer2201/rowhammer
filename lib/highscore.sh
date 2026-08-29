#!/usr/bin/env bash
#
# lib/highscore.sh
#
# Description:
#   Persistent highscore list for rowhammer. The best HS_MAX (10) rounds
#   of the Marathon mode are kept in ${DATA_DIR}/highscore-marathon
#   (default ~/.config/rowhammer/highscore-marathon; the file was called
#   plain "highscore" up to 0.50.0 and is renamed once by
#   highscore_migrate_legacy, see there),
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
#   sidebar shows. highscore_screen renders the list for the main menu,
#   two lines per entry: rank, name, rows,
#   play time (MM:SS) and date on the first, gold/silver squares,
#   rowhammers, pieces placed and the resulting pieces per minute on the
#   second.
#   Since 0.19.0 (user request) all five lists are shown by one browser
#   (highscore_browse): a cursor walks the entries with the up/down keys
#   and turns the page when it runs past the edge, left/right turn the
#   page directly, and Enter watches the demo recording of the entry the
#   cursor stands on - marked with a "*" in the list. Which entry has a
#   recording is answered by the round hash both the entry and the
#   recording's file name carry (demo_hash_map, lib/demo.sh), so the
#   lookup costs one directory glob and no file read. Before that the
#   lists were read-only info screens dealt out one page per key press
#   (menu_pages, lib/menu.sh, since removed) with no way back to the page
#   before.
#   Since 0.9.0 the table is colored with the TXT_* SGR globals
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
#   Since 0.16.0 the Hochwasser mode (Marathon under a floor that rises
#   by one row with a single gap every FLOOD_INTERVAL_MS, see
#   rowhammer.sh) has the fifth list, in ${DATA_DIR}/highscore-flood,
#   built from the HSF_* globals and functions at the end of this file.
#   It ranks by rows like the Marathon list and stores every round like
#   the Time Attack one - every round of this mode ends in a top-out,
#   that is the mode - but keeps its own file: rounds that last minutes
#   would never reach the top ten of the endless list.
#   Since 0.17.0 highscore_rank_preview (end of this file) answers which
#   place a round would take in the list of its mode without inserting
#   it, which is what lets the name prompt at the end of a round show
#   that place while it still asks for the name (prompt_round_name,
#   lib/menu.sh).
#   Since 0.18.0 (user decision) the Marathon file carries its mode in
#   its name like the other four: "highscore" became
#   "highscore-marathon", and highscore_migrate_legacy renames an
#   existing file once at startup so no top ten is lost over it.
#   Since 1.1.0 there is a sixth list, highscore-versus, for the
#   multiplayer rounds: the Marathon layout and the Marathon ranking
#   (rows, descending), every round recorded whether it was won or lost,
#   and deliberately without the place achieved - the list ranks what one
#   player did, which compares across sessions of two and of five, while
#   who won a given evening does not (see CLAUDE.md 4.5).
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.20.0  (2026-08-11)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/highscore.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# Maximum number of entries kept, and the file name below DATA_DIR.
# CHANGE 2026-08-04 (user decision): the Marathon list moved from
# "highscore" to "highscore-marathon". It was the only list without a
# mode suffix - a leftover from the time when it was the only list there
# was - and the four modes that came after it all name their mode, so
# the plain name was the odd one out. HS_LEGACY_FILE_NAME is the old
# name, kept for the one-time rename in highscore_migrate_legacy below
# and nowhere else.
HS_MAX=10
HS_FILE_NAME="highscore-marathon"
HS_LEGACY_FILE_NAME="highscore"

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

# highscore_migrate_legacy
# Rename a leftover "highscore" file to the current
# "highscore-marathon" (see HS_FILE_NAME above for the why). This is a
# deliberate exception to the project's no-backward-compatibility rule
# (CLAUDE.md, section 6) and was asked for explicitly: nothing about the
# file's content changes, only its name, so dropping a top ten over it
# would be a loss for no reason at all.
# Called from rowhammer.sh before the reset block, so --reset highscore
# already sees the file under its current name - which is what keeps the
# old name known to this one function instead of to every list of file
# names in the game.
# A target file that is already there means the rename happened before
# and the old name is something that was put back by hand: it is never
# overwritten, the leftover stays where it is and says so on STDERR. A
# failing mv is fatal instead - the data directory is unwritable then,
# the game could not save a list into it either, and carrying on would
# quietly start with an empty Marathon list.
highscore_migrate_legacy() {
    local old="${DATA_DIR}/${HS_LEGACY_FILE_NAME}"
    local new="${DATA_DIR}/${HS_FILE_NAME}"

    if [ ! -e "${old}" ]; then
        return 0
    fi
    if [ -e "${new}" ]; then
        printf 'Keeping %s: %s exists already\n' "${old}" "${new}" >&2
        return 0
    fi
    if ! mv -- "${old}" "${new}"; then
        die "Failed to rename ${old} to ${new}"
    fi
    # A user-facing note, so a renamed file is never a surprise. It is
    # printed before the alternate screen goes up, which is also where it
    # is readable again after the session ends.
    printf "${I18N[highscore_renamed]}\n" "${old}" "${new}"
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
# All five formats carry the hash as their last field, so one expansion
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
    if [ "${#HSF_ENTRIES[@]}" -gt 0 ]; then
        lists+=("${HSF_ENTRIES[@]}")
    fi
    if [ "${#HSV_ENTRIES[@]}" -gt 0 ]; then
        lists+=("${HSV_ENTRIES[@]}")
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

# How many entries one page of a highscore screen shows. Each entry is
# two data lines, the entries are separated by a blank line and the table
# head costs one more, so a page is 1 + 5 * 2 + 4 = 15 body lines - well
# within the MENU_BODY_MAX (lib/menu.sh) an info screen has, and a full
# list of ten needs exactly two pages.
HS_PAGE_ENTRIES=5

# How wide one line of an entry may get. A menu line has 46 characters
# (the 48-column minimum minus the two-column menu indent) and the
# browser spends two of them on the cursor and the demo marker in front
# of every entry, which leaves 44 for the text itself. A line that would
# exceed that - only reachable with a hand-edited file, since
# HS_FIELD_NUM_RE caps no digit count - is shown truncated and without
# colors rather than risking a cut escape sequence.
HS_LINE_MAX=44

# --- List browser ---------------------------------------------------------
# All five lists are shown by one browser (highscore_browse below). The
# screens fill these globals and hand it the title: the table head, the
# two lines of every entry and, per entry, the demo recording belonging
# to it ("" when there is none).
HSB_HEAD=""
HSB_L1=()
HSB_L2=()
HSB_DEMO=()

# highscore_rank_sgr RANK
# The color of a rank number, into the global HS_RANK_SGR: gold for the
# first place, silver for the second and the theme's accent color for the
# rest - the medal look all five screens share, in one place so they
# cannot drift apart.
HS_RANK_SGR=""
highscore_rank_sgr() {
    case "${1}" in
        1) HS_RANK_SGR="${TXT_GOLD_SGR}" ;;
        2) HS_RANK_SGR="${TXT_SILVER_SGR}" ;;
        *) HS_RANK_SGR="${TXT_ACCENT_SGR}" ;;
    esac
    return 0
}

# highscore_row2 GOLD SILVER ROWHAMMERS PIECES SECONDS
# The second line of an entry, into the global HS_ROW2: the gold and
# silver squares, the rowhammers ("RH", four rows at once), the pieces
# placed ("PCS") and the rate that follows from those and the play time
# ("PPM", pieces per minute, see fmt_ppm). Identical on all five screens,
# so it is built once here; SECONDS is whole seconds, which is what
# fmt_ppm takes (the Ultra list stores milliseconds and divides them down
# before calling).
# Its own two-space indent sets the line off against the first one; with
# the browser's two cursor columns in front, a full line ends at exactly
# the 46 characters a menu line has (see HS_LINE_MAX).
HS_ROW2=""
highscore_row2() {
    local gold="${1}" silver="${2}" hammers="${3}" pieces="${4}" secs="${5}"
    local plain
    fmt_ppm "${pieces}" "${secs}"
    printf -v plain "  ${I18N[hs_lbl_gold]} %3d ${I18N[hs_lbl_silver]} %3d RH %2d PCS %4d PPM %5s" \
        "${gold}" "${silver}" "${hammers}" "${pieces}" "${FMT_PPM}"
    if [ "${#plain}" -gt "${HS_LINE_MAX}" ]; then
        HS_ROW2="${plain:0:HS_LINE_MAX}"
        return 0
    fi
    printf -v HS_ROW2 "  %s${I18N[hs_lbl_gold]} %3d%s %s${I18N[hs_lbl_silver]} %3d%s %sRH %2d%s PCS %4d PPM %5s" \
        "${TXT_GOLD_SGR}" "${gold}" "${TXT_RESET_SGR}" \
        "${TXT_SILVER_SGR}" "${silver}" "${TXT_RESET_SGR}" \
        "${TXT_WARN_SGR}" "${hammers}" "${TXT_RESET_SGR}" \
        "${pieces}" "${FMT_PPM}"
    return 0
}

# highscore_demo_open FILE
# Watch the recording of the entry under the cursor. An entry without one
# says so instead of doing nothing: the marker in the list only tells
# which entries have a recording, not why the others do not.
# A replay is refused while a round is suspended in the main menu, for
# the reason menu_demos (lib/menu.sh) refuses it there: the replay runs
# through the very game state that round is parked in and would silently
# throw it away.
highscore_demo_open() {
    local file="${1}"
    if [ -z "${file}" ]; then
        i18n_lines hs_no_demo
        menu_message "${I18N[demo_title]}" "${I18N_LINES[@]}"
        return 0
    fi
    if [ "${GAME_SUSPENDED}" -eq 1 ]; then
        i18n_lines demo_busy
        menu_message "${I18N[demo_title]}" "${I18N_LINES[@]}"
        return 0
    fi
    debug_event "highscore: playing the demo of the selected entry (${file})"
    demo_play "${file}"
    # The replay owned the whole screen; the next menu frame has to clear
    # it before drawing (the three places in lib/render.sh and
    # lib/input.sh that take the screen over set this flag the same way).
    MENU_FULL=1
    return 0
}

# highscore_browse TITLE
# Show the list held in the HSB_* globals and let the player walk it:
# up/down move the cursor from entry to entry - turning the page when it
# runs past the edge - left/right turn the page directly, Enter watches
# the recording of the entry under the cursor and ESC or x leaves. Both
# directions wrap around, like every other list in this game. The title
# carries a "Seite p/n" marker as soon as there is more than one page.
# The cursor is a ">" in front of the entry's first line rather than the
# reverse video menu_run uses for its entries: an entry line is built
# from SGR sequences that end in a reset, which would cut a reverse video
# span in the middle.
# Added 0.19.0 (user request). Before that the lists were read-only info
# screens dealt out one page per key press (menu_pages, lib/menu.sh) with
# no way back to the page before - and no way to point at an entry, which
# is what watching its recording needs.
highscore_browse() {
    local title="${1}"
    local n sel=0 page pages first i dirty=1 cur mark head any=0
    local -a lines
    n="${#HSB_L1[@]}"
    if [ "${n}" -eq 0 ]; then
        return 0
    fi
    pages=$(( (n + HS_PAGE_ENTRIES - 1) / HS_PAGE_ENTRIES ))
    # The marker legend only appears when there is a marker to explain.
    for (( i = 0; i < n; i++ )); do
        if [ -n "${HSB_DEMO[i]}" ]; then
            any=1
            break
        fi
    done
    while :; do
        if [ "${dirty}" -eq 1 ]; then
            page=$(( sel / HS_PAGE_ENTRIES ))
            if [ "${pages}" -gt 1 ]; then
                printf -v head "${I18N[menu_page]}" "${title}" \
                    "$(( page + 1 ))" "${pages}"
            else
                head="${title}"
            fi
            # Two spaces in front of the head as well, so the column
            # titles stay above their columns despite the cursor columns.
            lines=("  ${head}" "" "    ${HSB_HEAD}")
            first=$(( page * HS_PAGE_ENTRIES ))
            for (( i = first; i < first + HS_PAGE_ENTRIES && i < n; i++ )); do
                if [ "${i}" -gt "${first}" ]; then
                    lines+=("")
                fi
                if [ "${i}" -eq "${sel}" ]; then
                    cur=">"
                else
                    cur=" "
                fi
                if [ -n "${HSB_DEMO[i]}" ]; then
                    mark="*"
                else
                    mark=" "
                fi
                lines+=("  ${cur}${mark}${HSB_L1[i]}")
                # The second line keeps the cursor columns blank: the
                # block is one entry, and a second ">" would read like a
                # second selection.
                lines+=("    ${HSB_L2[i]}")
            done
            lines+=("")
            if [ "${any}" -eq 1 ]; then
                lines+=("  ${I18N[hs_legend_demo]}")
            fi
            lines+=("  ${I18N[hs_nav]}")
            render_menu_frame "${lines[@]}"
            screen_write "${RENDER_MENU_FRAME}"
            dirty=0
        fi
        read_key
        # A terminal resize handled inside read_key clears the screen and
        # raises REDRAW_PENDING; repaint so the list does not vanish.
        if [ "${REDRAW_PENDING}" -eq 1 ]; then
            REDRAW_PENDING=0
            dirty=1
        fi
        case "${KEY}" in
            UP|w)   sel=$(( (sel + n - 1) % n )); dirty=1 ;;
            DOWN|s) sel=$(( (sel + 1) % n )); dirty=1 ;;
            LEFT)
                # Paging puts the cursor on the first entry of the page it
                # lands on, so the selection is always visible.
                sel=$(( ((page + pages - 1) % pages) * HS_PAGE_ENTRIES ))
                dirty=1
                ;;
            RIGHT)
                sel=$(( ((page + 1) % pages) * HS_PAGE_ENTRIES ))
                dirty=1
                ;;
            ENTER|SPACE)
                highscore_demo_open "${HSB_DEMO[sel]}"
                dirty=1
                ;;
            ESC|x)
                debug_event "highscore browse '${title}': left at entry $(( sel + 1 ))"
                return 0
                ;;
        esac
    done
}

# highscore_screen
# Show the list as a browsable menu screen (highscore_browse). Labels
# come from the translation table like every other text; the Rows column
# reuses the HUD
# term. Shown per entry, on two lines: rank, name, rows, the round's
# play time (MM:SS) and the date on the first, then the gold/silver
# squares, the rowhammers ("RH", four rows at once), the pieces placed
# ("PCS") and the resulting pieces per minute ("PPM", pieces divided by
# play time, see fmt_ppm) on the second (highscore_row2). Lines and level
# stay stored but are not displayed; the rows column is the score and
# drives the ranking (scoring rebuild, 0.4.0).
# CHANGE 2026-08-04 (0.19.0, user request): the screen is a browser with
# a cursor now instead of a sequence of read-only pages - see
# highscore_browse. Which entry has a recording is answered by its round
# hash: the entry's last field and the demo's file name carry the same
# one (demo_hash_map, lib/demo.sh).
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
# any realistic round; the line is clamped to HS_LINE_MAX characters
# afterwards so implausible values cannot wrap the screen.
highscore_screen() {
    local -a body=()
    local i line plain rank hs_rows hs_name hs_date hs_gold
    local hs_silver hs_time hs_hammers hs_pieces hs_hash title
    # Title and mode name are composed rather than stored as one string,
    # so a mode is named the same way here as in every picker.
    title="${I18N[hs_title]} - ${I18N[mode_marathon]}"
    if [ "${#HS_ENTRIES[@]}" -eq 0 ]; then
        body+=("${I18N[hs_empty]}")
        body+=("")
        i18n_lines hs_empty_marathon
        body+=("${I18N_LINES[@]}")
        debug_event "highscore screen shown (0 entries)"
        menu_message "${title}" "${body[@]}"
        return 0
    fi
    printf -v line '%2s %-12s %6s %5s %10s' \
        "${I18N[hs_col_no]}" "${I18N[hs_col_name]}" "${I18N[hs_col_rows]}" \
        "${I18N[hs_col_time]}" "${I18N[hs_col_date]}"
    HSB_HEAD="${TXT_BOLD_SGR}${line}${TXT_RESET_SGR}"
    HSB_L1=()
    HSB_L2=()
    HSB_DEMO=()
    # Read fresh on every open rather than kept around: a round played or
    # a recording deleted in between changes which entries have one.
    demo_hash_map
    for i in "${!HS_ENTRIES[@]}"; do
        IFS='|' read -r hs_rows _ _ hs_name hs_date hs_gold hs_silver \
            hs_time hs_hammers hs_pieces hs_hash <<< "${HS_ENTRIES[i]}"
        fmt_duration "${hs_time}"
        rank=$(( i + 1 ))
        printf -v plain '%2d %-12.12s %6d %5s %10s' \
            "${rank}" "${hs_name}" "${hs_rows}" "${FMT_DURATION}" \
            "${hs_date}"
        # Color only the common case (plausible values, still within the
        # HS_LINE_MAX budget); an implausibly long line (a hand-edited
        # file - HS_FIELD_NUM_RE has no digit cap) falls back to the plain
        # truncated text instead of risking a cut escape sequence.
        if [ "${#plain}" -le "${HS_LINE_MAX}" ]; then
            highscore_rank_sgr "${rank}"
            printf -v line '%s%2d%s %-12.12s %s%6d%s %5s %10s' \
                "${HS_RANK_SGR}" "${rank}" "${TXT_RESET_SGR}" "${hs_name}" \
                "${TXT_ACCENT_SGR}" "${hs_rows}" "${TXT_RESET_SGR}" \
                "${FMT_DURATION}" "${hs_date}"
            HSB_L1+=("${line}")
        else
            HSB_L1+=("${plain:0:HS_LINE_MAX}")
        fi
        highscore_row2 "${hs_gold}" "${hs_silver}" "${hs_hammers}" \
            "${hs_pieces}" "${hs_time}"
        HSB_L2+=("${HS_ROW2}")
        # An entry from before the hash field carries "-", which is never
        # a key of the map, so it simply has no recording.
        HSB_DEMO+=("${DEMO_HASH_FILE[${hs_hash}]:-}")
    done
    debug_event "highscore screen shown (${#HS_ENTRIES[@]} entries)"
    highscore_browse "${title}"
    return 0
}

# highscore_ultra_screen
# Show the Ultra list the same way highscore_screen shows the Marathon
# one: browsed via highscore_browse, two lines per entry, same column
# widths and
# the same coloring rules, so switching between the two screens in the
# mode picker (menu_highscores, lib/menu.sh) is a change of numbers, not
# of layout. Reuses HS_PAGE_ENTRIES for that reason - the entry height is
# identical, so a separate constant could only ever drift apart from it.
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
    local i line plain rank hsu_time hsu_rows hsu_name hsu_date
    local hsu_gold hsu_silver hsu_hammers hsu_pieces hsu_hash title
    title="${I18N[hs_title]} - ${I18N[mode_ultra]}"
    if [ "${#HSU_ENTRIES[@]}" -eq 0 ]; then
        body+=("${I18N[hs_empty]}")
        body+=("")
        printf -v line "${I18N[hs_empty_ultra]}" "${ULTRA_TARGET_ROWS}"
        mapfile -t -O "${#body[@]}" body <<< "${line}"
        debug_event "highscore ultra screen shown (0 entries)"
        menu_message "${title}" "${body[@]}"
        return 0
    fi
    printf -v line '%2s %-12s %6s %9s %10s' \
        "${I18N[hs_col_no]}" "${I18N[hs_col_name]}" "${I18N[hs_col_rows]}" \
        "${I18N[hs_col_time]}" "${I18N[hs_col_date]}"
    HSB_HEAD="${TXT_BOLD_SGR}${line}${TXT_RESET_SGR}"
    HSB_L1=()
    HSB_L2=()
    HSB_DEMO=()
    demo_hash_map
    for i in "${!HSU_ENTRIES[@]}"; do
        IFS='|' read -r hsu_time hsu_rows _ _ hsu_name hsu_date hsu_gold \
            hsu_silver hsu_hammers hsu_pieces hsu_hash <<< "${HSU_ENTRIES[i]}"
        fmt_duration_ms "${hsu_time}"
        rank=$(( i + 1 ))
        printf -v plain '%2d %-12.12s %6d %9s %10s' \
            "${rank}" "${hsu_name}" "${hsu_rows}" "${FMT_DURATION_MS}" \
            "${hsu_date}"
        # Same guard as the Marathon screen: color only while the line
        # stays within the HS_LINE_MAX budget, so a hand-edited file with
        # implausible numbers costs the colors, never a cut escape
        # sequence.
        if [ "${#plain}" -le "${HS_LINE_MAX}" ]; then
            highscore_rank_sgr "${rank}"
            printf -v line '%s%2d%s %-12.12s %6d %s%9s%s %10s' \
                "${HS_RANK_SGR}" "${rank}" "${TXT_RESET_SGR}" "${hsu_name}" \
                "${hsu_rows}" "${TXT_ACCENT_SGR}" "${FMT_DURATION_MS}" \
                "${TXT_RESET_SGR}" "${hsu_date}"
            HSB_L1+=("${line}")
        else
            HSB_L1+=("${plain:0:HS_LINE_MAX}")
        fi
        highscore_row2 "${hsu_gold}" "${hsu_silver}" "${hsu_hammers}" \
            "${hsu_pieces}" "$(( hsu_time / 1000 ))"
        HSB_L2+=("${HS_ROW2}")
        HSB_DEMO+=("${DEMO_HASH_FILE[${hsu_hash}]:-}")
    done
    debug_event "highscore ultra screen shown (${#HSU_ENTRIES[@]} entries)"
    highscore_browse "${title}"
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
# via highscore_browse (HS_PAGE_ENTRIES again - identical entry height,
# and a fourth constant could only drift), two lines per entry, same
# column widths and the same coloring rules. Rows rank this
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
    local i line plain rank hss_rows hss_lines hss_name hss_date
    local hss_gold hss_silver hss_time hss_hammers hss_pieces hss_hash title
    title="${I18N[hs_title]} - ${I18N[mode_sprint]}"
    if [ "${#HSS_ENTRIES[@]}" -eq 0 ]; then
        fmt_duration $(( SPRINT_TIME_MS / 1000 ))
        body+=("${I18N[hs_empty]}")
        body+=("")
        printf -v line "${I18N[hs_empty_sprint]}" "${FMT_DURATION}"
        mapfile -t -O "${#body[@]}" body <<< "${line}"
        debug_event "highscore sprint screen shown (0 entries)"
        menu_message "${title}" "${body[@]}"
        return 0
    fi
    printf -v line '%2s %-12s %6s %5s %10s' \
        "${I18N[hs_col_no]}" "${I18N[hs_col_name]}" "${I18N[hs_col_rows]}" \
        "${I18N[hs_col_lines]}" "${I18N[hs_col_date]}"
    HSB_HEAD="${TXT_BOLD_SGR}${line}${TXT_RESET_SGR}"
    HSB_L1=()
    HSB_L2=()
    HSB_DEMO=()
    demo_hash_map
    for i in "${!HSS_ENTRIES[@]}"; do
        IFS='|' read -r hss_rows hss_lines _ hss_name hss_date hss_gold \
            hss_silver hss_time hss_hammers hss_pieces hss_hash \
            <<< "${HSS_ENTRIES[i]}"
        rank=$(( i + 1 ))
        printf -v plain '%2d %-12.12s %6d %5d %10s' \
            "${rank}" "${hss_name}" "${hss_rows}" "${hss_lines}" \
            "${hss_date}"
        # Same guard as the other two screens: color only while the line
        # stays within the HS_LINE_MAX budget, so a hand-edited file with
        # implausible numbers costs the colors, never a cut escape
        # sequence.
        if [ "${#plain}" -le "${HS_LINE_MAX}" ]; then
            highscore_rank_sgr "${rank}"
            printf -v line '%s%2d%s %-12.12s %s%6d%s %5d %10s' \
                "${HS_RANK_SGR}" "${rank}" "${TXT_RESET_SGR}" "${hss_name}" \
                "${TXT_ACCENT_SGR}" "${hss_rows}" "${TXT_RESET_SGR}" \
                "${hss_lines}" "${hss_date}"
            HSB_L1+=("${line}")
        else
            HSB_L1+=("${plain:0:HS_LINE_MAX}")
        fi
        highscore_row2 "${hss_gold}" "${hss_silver}" "${hss_hammers}" \
            "${hss_pieces}" "${hss_time}"
        HSB_L2+=("${HS_ROW2}")
        HSB_DEMO+=("${DEMO_HASH_FILE[${hss_hash}]:-}")
    done
    debug_event "highscore sprint screen shown (${#HSS_ENTRIES[@]} entries)"
    highscore_browse "${title}"
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
# browsed via highscore_browse (HS_PAGE_ENTRIES again), two lines
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
    local i line plain rank hsa_rows hsa_name hsa_date hsa_gold
    local hsa_silver hsa_time hsa_hammers hsa_pieces hsa_hash title
    title="${I18N[hs_title]} - ${I18N[mode_timeattack]}"
    if [ "${#HSA_ENTRIES[@]}" -eq 0 ]; then
        fmt_duration $(( TIME_ATTACK_START_MS / 1000 ))
        body+=("${I18N[hs_empty]}")
        body+=("")
        printf -v line "${I18N[hs_empty_timeattack]}" "${FMT_DURATION}"
        mapfile -t -O "${#body[@]}" body <<< "${line}"
        debug_event "highscore timeattack screen shown (0 entries)"
        menu_message "${title}" "${body[@]}"
        return 0
    fi
    printf -v line '%2s %-12s %6s %5s %10s' \
        "${I18N[hs_col_no]}" "${I18N[hs_col_name]}" "${I18N[hs_col_rows]}" \
        "${I18N[hs_col_time]}" "${I18N[hs_col_date]}"
    HSB_HEAD="${TXT_BOLD_SGR}${line}${TXT_RESET_SGR}"
    HSB_L1=()
    HSB_L2=()
    HSB_DEMO=()
    demo_hash_map
    for i in "${!HSA_ENTRIES[@]}"; do
        IFS='|' read -r hsa_rows _ _ hsa_name hsa_date hsa_gold \
            hsa_silver hsa_time hsa_hammers hsa_pieces hsa_hash \
            <<< "${HSA_ENTRIES[i]}"
        fmt_duration "${hsa_time}"
        rank=$(( i + 1 ))
        printf -v plain '%2d %-12.12s %6d %5s %10s' \
            "${rank}" "${hsa_name}" "${hsa_rows}" "${FMT_DURATION}" \
            "${hsa_date}"
        # Same guard as the other three screens: color only while the
        # line stays within the HS_LINE_MAX budget, so a hand-edited file
        # with implausible numbers costs the colors, never a cut escape
        # sequence.
        if [ "${#plain}" -le "${HS_LINE_MAX}" ]; then
            highscore_rank_sgr "${rank}"
            printf -v line '%s%2d%s %-12.12s %s%6d%s %5s %10s' \
                "${HS_RANK_SGR}" "${rank}" "${TXT_RESET_SGR}" "${hsa_name}" \
                "${TXT_ACCENT_SGR}" "${hsa_rows}" "${TXT_RESET_SGR}" \
                "${FMT_DURATION}" "${hsa_date}"
            HSB_L1+=("${line}")
        else
            HSB_L1+=("${plain:0:HS_LINE_MAX}")
        fi
        highscore_row2 "${hsa_gold}" "${hsa_silver}" "${hsa_hammers}" \
            "${hsa_pieces}" "${hsa_time}"
        HSB_L2+=("${HS_ROW2}")
        HSB_DEMO+=("${DEMO_HASH_FILE[${hsa_hash}]:-}")
    done
    debug_event "highscore timeattack screen shown (${#HSA_ENTRIES[@]} entries)"
    highscore_browse "${title}"
    return 0
}

# --- Hochwasser mode list -------------------------------------------------
# The Hochwasser mode (added 0.49.0, user request) is Marathon under a
# rising floor: every FLOOD_INTERVAL_MS a full row with a single gap is
# pushed in from below, and the round ends when the stack reaches the
# ceiling (see flood_raise in rowhammer.sh). Its results live in their
# own file, for the reason each of the other modes has one: an endless
# round and a round the board itself fills up are not the same
# achievement, and the flood rounds - which end within minutes - would
# never reach the top ten of the endless list.
#
# The score is the row credit, as in Marathon: nothing else about the
# mode changes what a round is worth. Every run is recorded, finished or
# not - like Time Attack and unlike Ultra and Sprint, and for the same
# reason: this mode has no incomparable "did not finish" state. Every
# round here ends in a top-out, that is the mode; a round that drowned
# early simply scored fewer rows.
HSF_MAX=10
HSF_FILE_NAME="highscore-flood"

# In-memory list, one
# "rows|lines|level|name|date|gold|silver|time|rowhammers|pieces|hash"
# string per element, sorted by rows descending. HSF_LAST_RANK is the
# rank the most recently added run reached (1-based, 0 = not on the
# list). The Marathon list's field layout again, for the reason the
# Sprint and the Time Attack list reuse it: the same number in the same
# unit ranks it, so a fifth layout would only be a fifth thing to keep in
# step.
HSF_ENTRIES=()
HSF_LAST_RANK=0

# Field count of a stored Hochwasser line. Eleven, with no shorter
# variant: this list was born with the round hash (0.49.0), so unlike the
# four older ones it never existed without it and has nothing to be
# lenient about.
HSF_FIELDS=11

# highscore_flood_parse_line LINE
# Validate one stored Hochwasser line and, on success, append it to
# HSF_ENTRIES. Field patterns and layout are the Marathon list's; a line
# that fails anywhere is dropped silently, so a damaged file costs single
# entries instead of the game.
highscore_flood_parse_line() {
    local line="${1}"
    local -a f=()
    local i n

    IFS='|' read -r -a f <<< "${line}"
    n="${#f[@]}"
    [ "${n}" -eq "${HSF_FIELDS}" ] || return 0

    # rows, lines, level.
    for ((i = 0; i < 3; i++)); do
        [[ "${f[i]}" =~ ${HS_FIELD_NUM_RE} ]] || return 0
    done
    [[ "${f[3]}" =~ ${HS_FIELD_NAME_RE} ]] || return 0
    [[ "${f[4]}" =~ ${HS_FIELD_DATE_RE} ]] || return 0
    # gold, silver, time, rowhammers, pieces.
    for ((i = 5; i < HSF_FIELDS - 1; i++)); do
        [[ "${f[i]}" =~ ${HS_FIELD_NUM_RE} ]] || return 0
    done
    [[ "${f[HSF_FIELDS - 1]}" =~ ${HS_FIELD_HASH_RE} ]] || return 0

    HSF_ENTRIES+=("${line}")
    return 0
}

# highscore_flood_load
# Read the Hochwasser list into HSF_ENTRIES. Missing file = empty list,
# malformed lines are skipped (highscore_flood_parse_line).
highscore_flood_load() {
    HSF_ENTRIES=()
    local f="${DATA_DIR}/${HSF_FILE_NAME}" line
    if [ ! -r "${f}" ]; then
        return 0
    fi
    while IFS= read -r line; do
        highscore_flood_parse_line "${line}"
        if [ "${#HSF_ENTRIES[@]}" -ge "${HSF_MAX}" ]; then
            break
        fi
    done < "${f}"
    debug_event "highscore flood loaded: ${#HSF_ENTRIES[@]} entries from ${f}"
    return 0
}

# highscore_flood_save
# Write HSF_ENTRIES atomically (temp file + mv), like highscore_save.
highscore_flood_save() {
    local f="${DATA_DIR}/${HSF_FILE_NAME}" tmp
    mkdir -p -- "${DATA_DIR}"
    tmp="$(mktemp -- "${DATA_DIR}/.${HSF_FILE_NAME}.XXXXXX")"
    # Expanding an empty array under set -u errors on bash < 4.4, so the
    # empty list writes an empty file explicitly.
    if [ "${#HSF_ENTRIES[@]}" -gt 0 ]; then
        printf '%s\n' "${HSF_ENTRIES[@]}" > "${tmp}"
    else
        : > "${tmp}"
    fi
    mv -f -- "${tmp}" "${f}"
    debug_event "highscore flood saved: ${f} (${#HSF_ENTRIES[@]} entries)"
    return 0
}

# highscore_flood_add ROWS LINES LEVEL NAME GOLD SILVER TIME ROWHAMMERS
#                     PIECES HASH
# Insert one finished Hochwasser round into the sorted list and persist
# it. Arguments and order are the Marathon list's (highscore_add), TIME
# the play time in whole seconds - here the time the round held the water
# off, which is why the list shows it. Equal row credits rank below
# existing ones, so the older entry keeps its place. Rounds without a
# single row are ignored, and nothing is written when the round does not
# make the list; HSF_LAST_RANK reports the outcome either way.
highscore_flood_add() {
    local rows="${1}" lines="${2}" level="${3}" name="${4}"
    local gold="${5}" silver="${6}" time="${7}" hammers="${8}"
    local pieces="${9}" hash="${10:--}"
    local entry e placed=0 rank=0
    local -a merged=()
    HSF_LAST_RANK=0
    if [ "${rows}" -le 0 ]; then
        return 0
    fi
    entry="${rows}|${lines}|${level}|${name}|$(date +%Y-%m-%d)|${gold}|${silver}|${time}|${hammers}|${pieces}|${hash}"
    if [ "${#HSF_ENTRIES[@]}" -gt 0 ]; then
        for e in "${HSF_ENTRIES[@]}"; do
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
        if [ "${#merged[@]}" -ge "${HSF_MAX}" ]; then
            debug_event "highscore flood: '${name}' rows=${rows} below the top ${HSF_MAX}"
            return 0
        fi
        merged+=("${entry}")
        rank="${#merged[@]}"
    fi
    HSF_ENTRIES=("${merged[@]:0:HSF_MAX}")
    HSF_LAST_RANK="${rank}"
    debug_event "highscore flood: '${name}' rows=${rows} time=${time}s enters at rank ${rank}"
    highscore_flood_save
    return 0
}

# highscore_flood_screen
# Show the Hochwasser list the way the other four screens show theirs:
# browsed via highscore_browse (HS_PAGE_ENTRIES again), two lines
# per entry, same column widths and the same coloring rules. Rows rank
# this list and therefore carry the accent color, as on the Marathon,
# the Sprint and the Time Attack screen.
# The columns are the Marathon ones down to the play time, and that
# column earns its place here for a reason of this mode's own: the water
# rises on a fixed clock, so the time an entry survived says how many
# rows it had to answer - two entries with the same rows are told apart
# by which of them held out longer.
highscore_flood_screen() {
    local -a body=()
    local i line plain rank hsf_rows hsf_name hsf_date hsf_gold
    local hsf_silver hsf_time hsf_hammers hsf_pieces hsf_hash title
    title="${I18N[hs_title]} - ${I18N[mode_flood]}"
    if [ "${#HSF_ENTRIES[@]}" -eq 0 ]; then
        body+=("${I18N[hs_empty]}")
        body+=("")
        printf -v line "${I18N[hs_empty_flood]}" \
            "$(( FLOOD_INTERVAL_MS / 1000 ))"
        mapfile -t -O "${#body[@]}" body <<< "${line}"
        debug_event "highscore flood screen shown (0 entries)"
        menu_message "${title}" "${body[@]}"
        return 0
    fi
    printf -v line '%2s %-12s %6s %5s %10s' \
        "${I18N[hs_col_no]}" "${I18N[hs_col_name]}" "${I18N[hs_col_rows]}" \
        "${I18N[hs_col_time]}" "${I18N[hs_col_date]}"
    HSB_HEAD="${TXT_BOLD_SGR}${line}${TXT_RESET_SGR}"
    HSB_L1=()
    HSB_L2=()
    HSB_DEMO=()
    demo_hash_map
    for i in "${!HSF_ENTRIES[@]}"; do
        IFS='|' read -r hsf_rows _ _ hsf_name hsf_date hsf_gold \
            hsf_silver hsf_time hsf_hammers hsf_pieces hsf_hash \
            <<< "${HSF_ENTRIES[i]}"
        fmt_duration "${hsf_time}"
        rank=$(( i + 1 ))
        printf -v plain '%2d %-12.12s %6d %5s %10s' \
            "${rank}" "${hsf_name}" "${hsf_rows}" "${FMT_DURATION}" \
            "${hsf_date}"
        # Same guard as the other four screens: color only while the
        # line stays within the HS_LINE_MAX budget, so a hand-edited file
        # with implausible numbers costs the colors, never a cut escape
        # sequence.
        if [ "${#plain}" -le "${HS_LINE_MAX}" ]; then
            highscore_rank_sgr "${rank}"
            printf -v line '%s%2d%s %-12.12s %s%6d%s %5s %10s' \
                "${HS_RANK_SGR}" "${rank}" "${TXT_RESET_SGR}" "${hsf_name}" \
                "${TXT_ACCENT_SGR}" "${hsf_rows}" "${TXT_RESET_SGR}" \
                "${FMT_DURATION}" "${hsf_date}"
            HSB_L1+=("${line}")
        else
            HSB_L1+=("${plain:0:HS_LINE_MAX}")
        fi
        highscore_row2 "${hsf_gold}" "${hsf_silver}" "${hsf_hammers}" \
            "${hsf_pieces}" "${hsf_time}"
        HSB_L2+=("${HS_ROW2}")
        HSB_DEMO+=("${DEMO_HASH_FILE[${hsf_hash}]:-}")
    done
    debug_event "highscore flood screen shown (${#HSF_ENTRIES[@]} entries)"
    highscore_browse "${title}"
    return 0
}

# --- Versus mode list -----------------------------------------------------
# The multiplayer (added 1.1.0) is the sixth mode with results of its own.
# A list rather than an entry in the Marathon one, which is the decision
# this project has now taken six times for the same reason: a round under
# different rules belongs in a different list. Garbage cuts a round short
# and hands it extra rows to clear at the same time, so its numbers are
# simply not the same size as an endless round's - merging them would
# mean two yardsticks in one table.
#
# The score is the row credit, as in Marathon: what a round is worth does
# not change because somebody was playing against you. Every round is
# recorded, won or lost - like Time Attack and Hochwasser and unlike Ultra
# and Sprint: a multiplayer round has no incomparable "did not finish"
# state, it ends when it ends, and a player who was knocked out early
# simply scored fewer rows.
#
# The place achieved is deliberately not stored. The list ranks what one
# player did, and that is comparable across evenings of two and of five;
# who won a particular session is not, and a "1st of 2" next to a "3rd of
# 5" would read like an order where there is none. The field layout is
# therefore the Marathon one down to the last field, which is what lets
# every list share the parsing, the screen and the hash lookup.
HSV_MAX=10
HSV_FILE_NAME="highscore-versus"

# In-memory list, one
# "rows|lines|level|name|date|gold|silver|time|rowhammers|pieces|hash"
# string per element, sorted by rows descending. HSV_LAST_RANK is the
# rank the most recently added round reached (1-based, 0 = not on the
# list).
HSV_ENTRIES=()
HSV_LAST_RANK=0

# Field count of a stored versus line. Eleven, with no shorter variant:
# like the Hochwasser list this one was born with the round hash and has
# nothing to be lenient about.
HSV_FIELDS=11

# highscore_versus_parse_line LINE
# Validate one stored versus line and, on success, append it to
# HSV_ENTRIES. Field patterns and layout are the Marathon list's; a line
# that fails anywhere is dropped silently, so a damaged file costs single
# entries instead of the game.
highscore_versus_parse_line() {
    local line="${1}"
    local -a f=()
    local i n

    IFS='|' read -r -a f <<< "${line}"
    n="${#f[@]}"
    [ "${n}" -eq "${HSV_FIELDS}" ] || return 0

    # rows, lines, level.
    for ((i = 0; i < 3; i++)); do
        [[ "${f[i]}" =~ ${HS_FIELD_NUM_RE} ]] || return 0
    done
    [[ "${f[3]}" =~ ${HS_FIELD_NAME_RE} ]] || return 0
    [[ "${f[4]}" =~ ${HS_FIELD_DATE_RE} ]] || return 0
    # gold, silver, time, rowhammers, pieces.
    for ((i = 5; i < HSV_FIELDS - 1; i++)); do
        [[ "${f[i]}" =~ ${HS_FIELD_NUM_RE} ]] || return 0
    done
    [[ "${f[HSV_FIELDS - 1]}" =~ ${HS_FIELD_HASH_RE} ]] || return 0

    HSV_ENTRIES+=("${line}")
    return 0
}

# highscore_versus_load
# Read the versus list into HSV_ENTRIES. Missing file = empty list,
# malformed lines are skipped (highscore_versus_parse_line).
highscore_versus_load() {
    HSV_ENTRIES=()
    local f="${DATA_DIR}/${HSV_FILE_NAME}" line
    if [ ! -r "${f}" ]; then
        return 0
    fi
    while IFS= read -r line; do
        highscore_versus_parse_line "${line}"
        if [ "${#HSV_ENTRIES[@]}" -ge "${HSV_MAX}" ]; then
            break
        fi
    done < "${f}"
    debug_event "highscore versus loaded: ${#HSV_ENTRIES[@]} entries from ${f}"
    return 0
}

# highscore_versus_save
# Write HSV_ENTRIES atomically (temp file + mv), like highscore_save.
highscore_versus_save() {
    local f="${DATA_DIR}/${HSV_FILE_NAME}" tmp
    mkdir -p -- "${DATA_DIR}"
    tmp="$(mktemp -- "${DATA_DIR}/.${HSV_FILE_NAME}.XXXXXX")"
    # Expanding an empty array under set -u errors on bash < 4.4, so the
    # empty list writes an empty file explicitly.
    if [ "${#HSV_ENTRIES[@]}" -gt 0 ]; then
        printf '%s\n' "${HSV_ENTRIES[@]}" > "${tmp}"
    else
        : > "${tmp}"
    fi
    mv -f -- "${tmp}" "${f}"
    debug_event "highscore versus saved: ${f} (${#HSV_ENTRIES[@]} entries)"
    return 0
}

# highscore_versus_add ROWS LINES LEVEL NAME GOLD SILVER TIME ROWHAMMERS
#                      PIECES HASH
# Insert one finished multiplayer round into the sorted list and persist
# it. Arguments and order are the Marathon list's (highscore_add), TIME
# the play time in whole seconds - here the time the player stayed in the
# round, which is why the list shows it. Equal row credits rank below
# existing ones, so the older entry keeps its place. Rounds without a
# single row are ignored, and nothing is written when the round does not
# make the list; HSV_LAST_RANK reports the outcome either way.
highscore_versus_add() {
    local rows="${1}" lines="${2}" level="${3}" name="${4}"
    local gold="${5}" silver="${6}" time="${7}" hammers="${8}"
    local pieces="${9}" hash="${10:--}"
    local entry e placed=0 rank=0
    local -a merged=()
    HSV_LAST_RANK=0
    if [ "${rows}" -le 0 ]; then
        return 0
    fi
    entry="${rows}|${lines}|${level}|${name}|$(date +%Y-%m-%d)|${gold}|${silver}|${time}|${hammers}|${pieces}|${hash}"
    if [ "${#HSV_ENTRIES[@]}" -gt 0 ]; then
        for e in "${HSV_ENTRIES[@]}"; do
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
        if [ "${#merged[@]}" -ge "${HSV_MAX}" ]; then
            debug_event "highscore versus: '${name}' rows=${rows} below the top ${HSV_MAX}"
            return 0
        fi
        merged+=("${entry}")
        rank="${#merged[@]}"
    fi
    HSV_ENTRIES=("${merged[@]:0:HSV_MAX}")
    HSV_LAST_RANK="${rank}"
    debug_event "highscore versus: '${name}' rows=${rows} time=${time}s enters at rank ${rank}"
    highscore_versus_save
    return 0
}

# highscore_versus_screen
# Show the versus list the way the other five screens show theirs:
# browsed via highscore_browse (HS_PAGE_ENTRIES again), two lines per
# entry, same column widths and the same coloring rules. Rows rank this
# list and therefore carry the accent color, as on the Marathon, the
# Sprint, the Time Attack and the Hochwasser screen.
# The columns are the Marathon ones down to the play time, and it earns
# its place here as it does there: a round that ended early is exactly
# the one that is short, so the time tells a knocked-out round from one
# that was played to the end.
highscore_versus_screen() {
    local -a body=()
    local i line plain rank hsv_rows hsv_name hsv_date hsv_gold
    local hsv_silver hsv_time hsv_hammers hsv_pieces hsv_hash title
    title="${I18N[hs_title]} - ${I18N[mode_versus]}"
    if [ "${#HSV_ENTRIES[@]}" -eq 0 ]; then
        body+=("${I18N[hs_empty]}")
        body+=("")
        i18n_lines hs_empty_versus
        body+=("${I18N_LINES[@]}")
        debug_event "highscore versus screen shown (0 entries)"
        menu_message "${title}" "${body[@]}"
        return 0
    fi
    printf -v line '%2s %-12s %6s %5s %10s' \
        "${I18N[hs_col_no]}" "${I18N[hs_col_name]}" "${I18N[hs_col_rows]}" \
        "${I18N[hs_col_time]}" "${I18N[hs_col_date]}"
    HSB_HEAD="${TXT_BOLD_SGR}${line}${TXT_RESET_SGR}"
    HSB_L1=()
    HSB_L2=()
    HSB_DEMO=()
    demo_hash_map
    for i in "${!HSV_ENTRIES[@]}"; do
        IFS='|' read -r hsv_rows _ _ hsv_name hsv_date hsv_gold \
            hsv_silver hsv_time hsv_hammers hsv_pieces hsv_hash \
            <<< "${HSV_ENTRIES[i]}"
        fmt_duration "${hsv_time}"
        rank=$(( i + 1 ))
        printf -v plain '%2d %-12.12s %6d %5s %10s' \
            "${rank}" "${hsv_name}" "${hsv_rows}" "${FMT_DURATION}" \
            "${hsv_date}"
        # Same guard as the other five screens: color only while the line
        # stays within the HS_LINE_MAX budget, so a hand-edited file with
        # implausible numbers costs the colors, never a cut escape
        # sequence.
        if [ "${#plain}" -le "${HS_LINE_MAX}" ]; then
            highscore_rank_sgr "${rank}"
            printf -v line '%s%2d%s %-12.12s %s%6d%s %5s %10s' \
                "${HS_RANK_SGR}" "${rank}" "${TXT_RESET_SGR}" "${hsv_name}" \
                "${TXT_ACCENT_SGR}" "${hsv_rows}" "${TXT_RESET_SGR}" \
                "${FMT_DURATION}" "${hsv_date}"
            HSB_L1+=("${line}")
        else
            HSB_L1+=("${plain:0:HS_LINE_MAX}")
        fi
        highscore_row2 "${hsv_gold}" "${hsv_silver}" "${hsv_hammers}" \
            "${hsv_pieces}" "${hsv_time}"
        HSB_L2+=("${HS_ROW2}")
        HSB_DEMO+=("${DEMO_HASH_FILE[${hsv_hash}]:-}")
    done
    debug_event "highscore versus screen shown (${#HSV_ENTRIES[@]} entries)"
    highscore_browse "${title}"
    return 0
}

# --- Rank preview ---------------------------------------------------------
# highscore_rank_preview MODE VALUE
# Report in HS_PREVIEW_RANK which place a round of MODE would take in
# that mode's list, and in HS_PREVIEW_MAX how many places the list has:
# 1..HS_PREVIEW_MAX for a round that makes it, 0 for one that misses it
# (and 0 as well for a mode without a list of its own). VALUE is what the
# mode ranks by - the play time in milliseconds for Ultra, the row credit
# for every other mode. Nothing is written and no list is touched.
#
# Added 0.17.0 (user request) for the name prompt at the end of a round
# (prompt_round_name, lib/menu.sh): it runs before the entry is inserted
# and therefore cannot read the *_LAST_RANK the add functions set, but it
# is where the place belongs - it is the moment the round is worth a
# name. Deriving the place here instead of asking for the name after the
# insert keeps that name an input of the insert (see record_round in
# rowhammer.sh, where it also goes into the round hash).
#
# The rule is the add functions': every list is kept sorted, a round is
# placed in front of the first entry it beats, and an equal value ranks
# behind the older entry. Its place is therefore one behind the number of
# entries at least as good as it, and a place past the list's capacity is
# no place at all. Both halves of that are exactly what the add function
# of the mode does, so preview and entry cannot disagree - nothing
# changes the list between the two.
HS_PREVIEW_RANK=0
HS_PREVIEW_MAX=0
highscore_rank_preview() {
    local mode="${1}" value="${2}"
    local e better=0 asc=0
    local -a entries=()
    HS_PREVIEW_RANK=0
    HS_PREVIEW_MAX=0
    case "${mode}" in
        marathon)
            HS_PREVIEW_MAX="${HS_MAX}"
            # Expanding an empty array trips set -u on bash < 4.4, so
            # every list is only copied when it holds something (same
            # precaution as in highscore_hash_set above).
            if [ "${#HS_ENTRIES[@]}" -gt 0 ]; then
                entries=("${HS_ENTRIES[@]}")
            fi
            ;;
        ultra)
            # The one list ranked by time, and therefore the one where
            # the smaller value is the better one.
            asc=1
            HS_PREVIEW_MAX="${HSU_MAX}"
            if [ "${#HSU_ENTRIES[@]}" -gt 0 ]; then
                entries=("${HSU_ENTRIES[@]}")
            fi
            ;;
        sprint)
            HS_PREVIEW_MAX="${HSS_MAX}"
            if [ "${#HSS_ENTRIES[@]}" -gt 0 ]; then
                entries=("${HSS_ENTRIES[@]}")
            fi
            ;;
        timeattack)
            HS_PREVIEW_MAX="${HSA_MAX}"
            if [ "${#HSA_ENTRIES[@]}" -gt 0 ]; then
                entries=("${HSA_ENTRIES[@]}")
            fi
            ;;
        flood)
            HS_PREVIEW_MAX="${HSF_MAX}"
            if [ "${#HSF_ENTRIES[@]}" -gt 0 ]; then
                entries=("${HSF_ENTRIES[@]}")
            fi
            ;;
        versus)
            HS_PREVIEW_MAX="${HSV_MAX}"
            if [ "${#HSV_ENTRIES[@]}" -gt 0 ]; then
                entries=("${HSV_ENTRIES[@]}")
            fi
            ;;
        *)
            # A mode without a list of its own: no place to report.
            debug_event "highscore rank preview: unknown mode '${mode}'"
            return 0
            ;;
    esac
    # The add functions ignore a round without a ranking value (no rows
    # resp. no measured time), so it has no place either.
    if [ "${value}" -le 0 ]; then
        return 0
    fi
    if [ "${#entries[@]}" -gt 0 ]; then
        for e in "${entries[@]}"; do
            if [ "${asc}" -eq 1 ]; then
                if [ "${value}" -ge "${e%%|*}" ]; then
                    better=$(( better + 1 ))
                fi
            else
                if [ "${value}" -le "${e%%|*}" ]; then
                    better=$(( better + 1 ))
                fi
            fi
        done
    fi
    if [ "$(( better + 1 ))" -le "${HS_PREVIEW_MAX}" ]; then
        HS_PREVIEW_RANK=$(( better + 1 ))
    fi
    debug_event "highscore rank preview: mode=${mode} value=${value} rank=${HS_PREVIEW_RANK}/${HS_PREVIEW_MAX}"
    return 0
}
