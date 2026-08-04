#!/usr/bin/env bash
#
# lib/stats.sh
#
# Description:
#   Persistent all-time game statistics for rowhammer: cleared rows
#   (physical lines), earned bonus rows (the weighted row credit beyond
#   the physical lines, i.e. gold/silver/Tetris bonuses) and the number
#   of gold and silver squares built, plus the rowhammers (four rows
#   cleared in one move, the namesake of the game), the pieces placed
#   and the time played - plus the results
#   of the last
#   three rounds (lines, bonus rows, gold/silver squares, rowhammers,
#   pieces, play time
#   and the date the round was played; newest
#   first). Since the scoring rebuild (0.4.0) the row credit is the
#   game's only score, so the recent rounds no longer store a separate
#   score field - the round's points are lines + bonus. Since 0.25.0
#   (user decision) the rowhammer count is both an all-time counter and
#   a field of the recent-rounds line. Pieces and play time joined them
#   in 0.27.0 (user decision): together they give the placement rate in
#   pieces per minute, all-time and per round.
#   Everything is kept in ${DATA_DIR}/stats (default
#   ~/.config/rowhammer/stats) as "key=value" lines
#   plus comment lines. The file is parsed and validated, not sourced:
#   a corrupted line only loses that one counter or round entry (falls
#   back to 0 / drops the entry), it
#   never breaks the game. Saving is atomic (temp file + mv). A round is
#   banked into the counters and the recent list exactly once per
#   finished round
#   (record_round in rowhammer.sh calls stats_add_round).
#   Since 0.9.0 the file also counts the rounds played per game mode and,
#   for the three timed modes, how many of them ended in that mode's
#   regular ending instead of a top-out (Ultra reaching its target,
#   Sprint playing its full time, Time Attack running its clock down) -
#   the share of successful attempts is not recoverable from anywhere
#   else, since a failed run never enters its mode's highscore list.
#   Since 0.10.0 (user request) every counter above exists a second time
#   per game mode (STATS_MODE, keys "<mode>_<field>"): the all-time
#   figures say what was achieved but not in which mode, and the modes
#   are played for different things - comparing a Marathon round with a
#   three-minute Sprint only works once each mode has its own totals.
#   The all-time counters stay exactly as they were, they are not a sum
#   derived from the per-mode ones: a round of an unknown mode (only
#   reachable from a future mode) is counted in the totals and nowhere
#   else, so the totals remain the complete picture.
#   stats_screen renders the all-time statistics for the "Statistik"
#   main menu entry via menu_message (lib/menu.sh) on three screens: the
#   all-time counters first, the recent rounds second (both together
#   outgrew the 22-row minimum terminal) and the per-mode round counters
#   third, which doubles as the overview in front of the per-mode
#   screens. stats_mode_screen shows one mode's own counters on a single
#   screen; menu_stats (lib/menu.sh) picks between the two the way
#   menu_highscores picks a list. Since 0.13.0 (user request) every one
#   of those screens - the all-time counters, each recent round and each
#   mode - also states the ratio of cleared rows to bonus rows
#   (stats_ratio, "1:X.XX"): both numbers were always there, but how much
#   of the row credit came from the gold/silver squares rather than from
#   the rows themselves had to be divided in one's head.
#   Since 0.8.0 the weighted total, the
#   gold/silver/rowhammer counters and the recent-round Rows/Gold/Silb/RH
#   figures are colored with the TXT_* SGR globals (lib/render.sh,
#   theme-aware, empty in --no-color/NO_COLOR mode); a recent-round line
#   that would overrun the 46-char budget skips coloring and falls back
#   to the plain truncated text instead of risking a cut escape sequence.
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.13.0  (2026-08-04)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/stats.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# File name below DATA_DIR and the accepted line formats. The digit
# caps keep the arithmetic clear of bash integer overflow (same guard
# as the savegame in lib/save.sh). A "recent" line stores one round as
# "recent=lines|bonus|gold|silver|rowhammers|pieces|time|date" (play time
# in whole seconds, date as YYYY-MM-DD,
# the same shape the highscore list stores); the file keeps the newest
# round first. Old recent lines (without the pieces and time fields,
# without the rowhammer field, date-less,
# or with the pre-rebuild leading score field) are simply dropped on
# load (project rule: no backward compatibility, formats may just
# break).
STATS_FILE_NAME="stats"
STATS_LINE_RE='^(lines|bonus_rows|gold_squares|silver_squares|rowhammers|pieces|play_time)=([0-9]{1,15})$'
STATS_RECENT_RE='^recent=([0-9]{1,15}(\|[0-9]{1,15}){6}\|[0-9]{4}-[0-9]{2}-[0-9]{2})$'

# Per-mode counter lines, "mode_<mode>_<field>=N" (0.10.0). One flat key
# per mode and field rather than one line per mode with packed fields:
# the file is a list of counters, and a counter that is missing (a mode
# never played, a hand-edited file) then simply falls back to 0 instead
# of invalidating everything the same line carries.
# CHANGE 2026-08-04: this replaces the "rounds_<mode>[_goal]" keys of
# 0.9.0, which counted rounds per mode but nothing else. Their two
# figures are now the "rounds" and "goal" fields of the same scheme, so
# there is one naming rule for per-mode data instead of two. Old files
# lose their per-mode round counts (project rule: no backward
# compatibility); the all-time counters and the recent rounds, which
# were never per mode, are unaffected.
STATS_MODE_RE='^mode_(marathon|ultra|sprint|timeattack|flood)_(rounds|goal|lines|bonus_rows|gold_squares|silver_squares|rowhammers|pieces|play_time)=([0-9]{1,15})$'

# How many recent rounds are kept and shown.
STATS_RECENT_MAX=3

# All-time counters across every round ever played, plus the recent
# round list ("lines|bonus|gold|silver|rowhammers|pieces|time|date" per
# element, newest
# first). Loaded on startup, extended by stats_add_round, read by
# stats_screen. STATS_PLAY_TIME is the summed play time in whole
# seconds; with STATS_PIECES it yields the all-time placement rate.
STATS_LINES=0
STATS_BONUS_ROWS=0
STATS_GOLD=0
STATS_SILVER=0
STATS_ROWHAMMERS=0
STATS_PIECES=0
STATS_PLAY_TIME=0
STATS_RECENT=()

# The same counters once per game mode, plus the rounds played in it and
# - for the three timed modes - how many of those ended in that mode's
# regular ending rather than in a top-out: Ultra reaching
# ULTRA_TARGET_ROWS, Sprint playing its full SPRINT_TIME_MS, Time Attack
# running its clock down to zero (see rowhammer.sh). The share of
# attempts that got there is the one figure no other stored number can
# reconstruct, because a failed run never enters its mode's highscore
# list.
# Keys are "<mode>_<field>" of the two lists below, so the file format,
# the reset, the write and both screens walk the same two loops; every
# combination exists from startup on, which keeps reads free of set -u
# guards. Marathon and Hochwasser have no goal to reach - both end in a
# top-out and nothing else - so their "goal" entry stays 0 and is neither
# written nor shown.
# CHANGE 2026-08-04 (user request): 0.9.0 had seven scalars here and
# counted only rounds per mode. Extending that shape to every counter
# would have meant 36 more globals, so the per-mode data moved into one
# keyed array - the fixed field list below took over from the variable
# names as the single source of truth for what may appear in the file.
STATS_MODES=(marathon ultra sprint timeattack flood)
STATS_MODE_FIELDS=(rounds goal lines bonus_rows gold_squares
                   silver_squares rowhammers pieces play_time)
declare -A STATS_MODE=()

# The modes whose round can only ever end in a top-out and that
# therefore have no goal to reach: their "goal" counter would be a
# permanent 0. Kept as data here rather than derived from the presence
# of a translated label, so what the file contains never depends on a
# language file (stats_mode_has_goal is what everything asks).
STATS_MODES_NO_GOAL=(marathon flood)

# stats_mode_has_goal MODE
# True when MODE has a regular ending of its own besides the top-out, and
# therefore a "goal" counter worth writing and showing.
stats_mode_has_goal() {
    local m
    for m in "${STATS_MODES_NO_GOAL[@]}"; do
        if [ "${m}" = "${1}" ]; then
            return 1
        fi
    done
    return 0
}

# CHANGE 2026-08-04: the two label tables that used to sit here (the
# mode names and the wording of their goal counter) are gone into the
# translation layer, keyed by mode: "mode_<mode>" for the name, which
# the pickers in lib/menu.sh read as well, and "stats_goal_<mode>" for
# the goal counter. Marathon and Hochwasser have no goal to reach and
# therefore no stats_goal_marathon / stats_goal_flood key; which modes
# those are is decided by stats_mode_has_goal above, not by the presence
# of the label.

# stats_mode_reset
# Put every per-mode counter back to 0. Called by stats_load before
# reading the file, so a counter the file does not carry (a mode never
# played, a hand-edited file) reads as 0 rather than as the value of the
# previous load.
stats_mode_reset() {
    local mode field
    for mode in "${STATS_MODES[@]}"; do
        for field in "${STATS_MODE_FIELDS[@]}"; do
            STATS_MODE["${mode}_${field}"]=0
        done
    done
    return 0
}
stats_mode_reset

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
    STATS_ROWHAMMERS=0
    STATS_PIECES=0
    STATS_PLAY_TIME=0
    STATS_RECENT=()
    stats_mode_reset
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
                rowhammers)     STATS_ROWHAMMERS=$(( 10#${BASH_REMATCH[2]} )) ;;
                pieces)         STATS_PIECES=$(( 10#${BASH_REMATCH[2]} )) ;;
                play_time)      STATS_PLAY_TIME=$(( 10#${BASH_REMATCH[2]} )) ;;
            esac
        elif [[ "${line}" =~ ${STATS_MODE_RE} ]]; then
            # The regex already limited mode and field to the known
            # names, so the key cannot be anything stats_mode_reset did
            # not create.
            found=1
            STATS_MODE["${BASH_REMATCH[1]}_${BASH_REMATCH[2]}"]=$(( 10#${BASH_REMATCH[3]} ))
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
    debug_event "stats: loaded lines=${STATS_LINES} bonus=${STATS_BONUS_ROWS} gold=${STATS_GOLD} silver=${STATS_SILVER} rowhammers=${STATS_ROWHAMMERS} pieces=${STATS_PIECES} play_time=${STATS_PLAY_TIME} recent=${#STATS_RECENT[@]} from ${f}"
    return 0
}

# stats_write
# Write the STATS_* counters and the recent round list atomically: into
# a temp file in the target
# directory, then mv over the real file, so a crash can never leave a
# half-written statistics file behind.
stats_write() {
    local f="${DATA_DIR}/${STATS_FILE_NAME}" tmp mode field
    mkdir -p -- "${DATA_DIR}"
    tmp="$(mktemp -- "${DATA_DIR}/.${STATS_FILE_NAME}.XXXXXX")"
    {
        printf '# rowhammer statistics: all-time counters and recent rounds.\n'
        printf '# Written after every finished round; edits are validated on load.\n'
        printf 'lines=%d\n' "${STATS_LINES}"
        printf 'bonus_rows=%d\n' "${STATS_BONUS_ROWS}"
        printf 'gold_squares=%d\n' "${STATS_GOLD}"
        printf 'silver_squares=%d\n' "${STATS_SILVER}"
        printf 'rowhammers=%d\n' "${STATS_ROWHAMMERS}"
        printf 'pieces=%d\n' "${STATS_PIECES}"
        printf 'play_time=%d\n' "${STATS_PLAY_TIME}"
        # The same counters per mode, in the order of the two lists at
        # the top of this file. The "goal" of a mode that has no goal to
        # reach (Marathon, Hochwasser) is skipped: the key would be a
        # permanent 0 that only invites the question what it means.
        for mode in "${STATS_MODES[@]}"; do
            for field in "${STATS_MODE_FIELDS[@]}"; do
                if [ "${field}" = "goal" ] && ! stats_mode_has_goal "${mode}"; then
                    continue
                fi
                printf 'mode_%s_%s=%d\n' "${mode}" "${field}" \
                    "${STATS_MODE[${mode}_${field}]}"
            done
        done
        # Newest round first;
        # lines|bonus|gold|silver|rowhammers|pieces|time|date.
        # The length guard keeps bash < 4.4 happy under set -u.
        if [ "${#STATS_RECENT[@]}" -gt 0 ]; then
            printf 'recent=%s\n' "${STATS_RECENT[@]}"
        fi
    } > "${tmp}"
    mv -f -- "${tmp}" "${f}"
    debug_event "stats: wrote lines=${STATS_LINES} bonus=${STATS_BONUS_ROWS} gold=${STATS_GOLD} silver=${STATS_SILVER} rowhammers=${STATS_ROWHAMMERS} pieces=${STATS_PIECES} play_time=${STATS_PLAY_TIME} recent=${#STATS_RECENT[@]} to ${f}"
    return 0
}

# stats_add_round LINES BONUS GOLD SILVER ROWHAMMERS PIECES TIME MODE GOAL
# Bank one finished round into the all-time counters, prepend it to the
# recent round list (capped at STATS_RECENT_MAX) and persist both. The
# round is stamped with today's date, the same way the highscore list
# dates its entries. ROWHAMMERS is the round's number of four-row
# clears, PIECES the number of pieces placed and TIME its play time in
# whole seconds; all three feed the all-time counters and the recent
# round entry alike. A
# round without any progress at all (no lines, no bonus, no squares, no
# piece placed) leaves the counters, the list and the file
# untouched, so idle rounds cause no disk writes (a rowhammer implies
# cleared lines, so it needs no own guard).
# CHANGE 2026-07-28: the piece count joined that guard. A round that
# ends without a single cleared row used to vanish silently; now it
# still carries pieces and play time, and dropping it would bend the
# all-time placement rate.
# MODE is the round's game mode (GAME_MODE in rowhammer.sh) and GOAL 1
# when it ended in that mode's regular ending rather than in a top-out
# (GOAL_REACHED); together they say which set of per-mode counters the
# round belongs to (2026-08-03, extended from the round count to every
# counter 2026-08-04). They are counted behind the same guard as
# everything else: a round that placed no piece at all is not a round
# played, and counting it here while it is missing from every other
# counter would only make the two sets disagree.
stats_add_round() {
    local lines="${1}" bonus="${2}" gold="${3}" silver="${4}"
    local rowhammers="${5}" pieces="${6}" time="${7}"
    local mode="${8}" goal="${9}"
    local entry known=0 m
    if (( lines == 0 && bonus == 0 && gold == 0 && silver == 0 \
        && pieces == 0 )); then
        return 0
    fi
    STATS_LINES=$(( STATS_LINES + lines ))
    STATS_BONUS_ROWS=$(( STATS_BONUS_ROWS + bonus ))
    STATS_GOLD=$(( STATS_GOLD + gold ))
    STATS_SILVER=$(( STATS_SILVER + silver ))
    STATS_ROWHAMMERS=$(( STATS_ROWHAMMERS + rowhammers ))
    STATS_PIECES=$(( STATS_PIECES + pieces ))
    STATS_PLAY_TIME=$(( STATS_PLAY_TIME + time ))
    # The same round once more into its mode's counters. An unknown mode
    # name (only reachable from a future mode that is missing from
    # STATS_MODES) is counted nowhere here rather than lumped in with
    # Marathon, so the per-mode screens show a gap instead of a wrong
    # attribution - the all-time counters above have it either way,
    # which is why they are kept as counters of their own instead of
    # being summed from these.
    for m in "${STATS_MODES[@]}"; do
        if [ "${m}" = "${mode}" ]; then
            known=1
            break
        fi
    done
    if [ "${known}" -eq 1 ]; then
        STATS_MODE["${mode}_rounds"]=$(( STATS_MODE["${mode}_rounds"] + 1 ))
        STATS_MODE["${mode}_lines"]=$(( STATS_MODE["${mode}_lines"] + lines ))
        STATS_MODE["${mode}_bonus_rows"]=$(( STATS_MODE["${mode}_bonus_rows"] + bonus ))
        STATS_MODE["${mode}_gold_squares"]=$(( STATS_MODE["${mode}_gold_squares"] + gold ))
        STATS_MODE["${mode}_silver_squares"]=$(( STATS_MODE["${mode}_silver_squares"] + silver ))
        STATS_MODE["${mode}_rowhammers"]=$(( STATS_MODE["${mode}_rowhammers"] + rowhammers ))
        STATS_MODE["${mode}_pieces"]=$(( STATS_MODE["${mode}_pieces"] + pieces ))
        STATS_MODE["${mode}_play_time"]=$(( STATS_MODE["${mode}_play_time"] + time ))
        # Marathon never reaches a goal (it has none), and record_round
        # leaves GOAL_REACHED at 0 there, so this needs no mode check.
        if [ "${goal}" -eq 1 ]; then
            STATS_MODE["${mode}_goal"]=$(( STATS_MODE["${mode}_goal"] + 1 ))
        fi
    else
        debug_event "stats: unknown mode '${mode}', round counted in the all-time counters only"
    fi
    entry="${lines}|${bonus}|${gold}|${silver}|${rowhammers}|${pieces}|${time}|$(date +%Y-%m-%d)"
    # Prepend the round; slicing an empty array errors under set -u on
    # bash < 4.4, hence the guard.
    if [ "${#STATS_RECENT[@]}" -gt 0 ]; then
        STATS_RECENT=("${entry}" \
            "${STATS_RECENT[@]:0:STATS_RECENT_MAX-1}")
    else
        STATS_RECENT=("${entry}")
    fi
    debug_event "stats: round banked +${lines} lines +${bonus} bonus +${gold} gold +${silver} silver +${rowhammers} rowhammers +${pieces} pieces +${time}s play time mode=${mode} goal=${goal}"
    stats_write
    return 0
}

# stats_ratio LINES BONUS
# Format the ratio of cleared physical rows to bonus rows into the global
# STATS_RATIO as "1:X.XX" - per cleared row, that many bonus rows were
# earned on top. "-" while no row has been cleared yet, which is the only
# division-by-zero case (and the only case in which the ratio would say
# nothing anyway: without a cleared row there is no bonus either).
# Added 2026-08-04 (user request): both figures were on every statistics
# screen, but how they relate - how much of the row credit came from the
# gold/silver squares rather than from the rows themselves - had to be
# divided in one's head.
# The 1:X form rather than a percentage or a plain quotient, because that
# is what the two numbers are: one row of the field, however many bonus
# rows it was worth. Two decimals rather than one, because the
# interesting differences between two playing styles sit in the second
# one. Bash has no floating point, so the value is computed in hundredths
# and split for printing, the same way fmt_ppm (rowhammer.sh) does it.
# Local to this file rather than next to fmt_ppm: fmt_ppm is shared with
# the highscore screens, this ratio is a statistics figure only.
STATS_RATIO="-"
stats_ratio() {
    local lines="${1}" bonus="${2}" hundredths
    if [ "${lines}" -le 0 ]; then
        STATS_RATIO="-"
        return 0
    fi
    hundredths=$(( bonus * 100 / lines ))
    # A hand-edited or corrupted stats file can hold any pair of numbers,
    # and the value goes into a ten-character field on every screen that
    # shows it. In a played round the integer part stays below 21 (a
    # Tetris through two gold squares is 4 lines and 81 bonus rows), so
    # anything beyond four digits is garbage anyway and is cut off here
    # rather than allowed to push the line past its 46-character budget.
    if (( hundredths / 100 > 9999 )); then
        STATS_RATIO="1:>9999"
        return 0
    fi
    printf -v STATS_RATIO '1:%d.%02d' \
        "$(( hundredths / 100 ))" "$(( hundredths % 100 ))"
    return 0
}

# stats_screen
# Show the all-time statistics - the counters over every round ever
# played, in every mode - as a menu-style info screen and wait for a
# key. One mode's own counters are stats_mode_screen's job; both are
# reached through menu_stats (lib/menu.sh). The labels come from the
# translation table (lib/i18n.sh). The weighted total (lines + bonus rows) is shown as a
# summary line because it is the number that builds the wonders, and the
# placement rate (pieces per minute over all rounds ever played) as the
# summary of pieces and play time. The results of the last
# STATS_RECENT_MAX rounds follow on a second screen, newest first, two
# lines each and including the date they were played; every line stays
# within the 46 characters the 48-column
# minimum terminal width leaves next to the two-column menu indent.
# CHANGE 2026-07-28 (user decision, 0.27.0): counters and recent rounds
# no longer share one screen. The pieces, the play time and the derived
# rate need three more counter lines and a second line per round, which
# together exceed the 17 body lines a 22-row terminal offers (see
# MENU_BODY_MAX in lib/menu.sh) - so the screen was split rather than
# columns dropped.
stats_screen() {
    local -a body=()
    local line entry r_lines r_bonus r_gold r_silver r_hammers r_pieces
    local r_time r_date secs plain mode total
    printf -v line '%-26s %10d' "${I18N[stats_lines]}" "${STATS_LINES}"
    body+=("${line}")
    printf -v line '%-26s %10d' "${I18N[stats_bonus]}" "${STATS_BONUS_ROWS}"
    body+=("${line}")
    # The two counters above in relation (2026-08-04, user request),
    # directly below them and above the weighted total: it relates the raw
    # figures, while the total and the per-round average below are derived
    # from them. Left uncolored on purpose - the accent color on this
    # screen marks the weighted total, the number that builds the wonders.
    stats_ratio "${STATS_LINES}" "${STATS_BONUS_ROWS}"
    printf -v line '%-26s %10s' "${I18N[stats_ratio]}" "${STATS_RATIO}"
    body+=("${line}")
    printf -v line '%-26s %s%10d%s' "${I18N[stats_total]}" \
        "${TXT_ACCENT_SGR}" "$(( STATS_LINES + STATS_BONUS_ROWS ))" \
        "${TXT_RESET_SGR}"
    body+=("${line}")
    body+=("")
    printf -v line '%-26s %s%10d%s' "${I18N[stats_gold]}" \
        "${TXT_GOLD_SGR}" "${STATS_GOLD}" "${TXT_RESET_SGR}"
    body+=("${line}")
    printf -v line '%-26s %s%10d%s' "${I18N[stats_silver]}" \
        "${TXT_SILVER_SGR}" "${STATS_SILVER}" "${TXT_RESET_SGR}"
    body+=("${line}")
    # The namesake move: four rows cleared in one go.
    printf -v line '%-26s %s%10d%s' "${I18N[stats_hammer]}" \
        "${TXT_WARN_SGR}" "${STATS_ROWHAMMERS}" "${TXT_RESET_SGR}"
    body+=("${line}")
    body+=("")
    printf -v line '%-26s %10d' "${I18N[stats_pieces]}" "${STATS_PIECES}"
    body+=("${line}")
    # Total play time as H:MM:SS - fmt_duration's MM:SS is meant for a
    # single round and would grow to four-digit minutes here.
    secs="${STATS_PLAY_TIME}"
    printf -v line '%-26s %10s' "${I18N[stats_playtime]}" \
        "$(printf '%d:%02d:%02d' "$(( secs / 3600 ))" \
            "$(( secs % 3600 / 60 ))" "$(( secs % 60 ))")"
    body+=("${line}")
    fmt_ppm "${STATS_PIECES}" "${STATS_PLAY_TIME}"
    printf -v line '%-26s %10s' "${I18N[stats_ppm]}" "${FMT_PPM}"
    body+=("${line}")
    debug_event "stats screen shown (counters)"
    menu_message "${I18N[stats_title]} (1/3)" "${body[@]}"

    # Second screen: the recent rounds. The first line per round carries
    # the date and the row counters, the second the squares, the
    # rowhammers and the placement rate; the Rows column is the round's
    # score (lines + bonus), derived instead of stored so the file can
    # never contradict itself.
    body=()
    body+=("${I18N[stats_recent_head]}")
    body+=("")
    if [ "${#STATS_RECENT[@]}" -eq 0 ]; then
        body+=("${I18N[stats_recent_none]}")
    else
        for entry in "${STATS_RECENT[@]}"; do
            IFS='|' read -r r_lines r_bonus r_gold r_silver r_hammers \
                r_pieces r_time r_date <<< "${entry}"
            printf -v plain "%10s ${I18N[stats_recent_rows]} %5d ${I18N[stats_recent_lines]} %4d ${I18N[stats_recent_bonus]} %4d" \
                "${r_date}" "$(( r_lines + r_bonus ))" "${r_lines}" \
                "${r_bonus}"
            # Same safety fallback as highscore_screen: the counters here
            # are internal and bounded in practice, but a corrupted stats
            # file could still overrun the 46-char budget, so an
            # oversized line skips coloring rather than risking a cut
            # escape sequence.
            if [ "${#plain}" -le 46 ]; then
                printf -v line "%10s %s${I18N[stats_recent_rows]} %5d%s ${I18N[stats_recent_lines]} %4d ${I18N[stats_recent_bonus]} %4d" \
                    "${r_date}" "${TXT_ACCENT_SGR}" \
                    "$(( r_lines + r_bonus ))" "${TXT_RESET_SGR}" \
                    "${r_lines}" "${r_bonus}"
                body+=("${line}")
            else
                body+=("${plain:0:46}")
            fi
            fmt_ppm "${r_pieces}" "${r_time}"
            printf -v plain "  ${I18N[hs_lbl_gold]} %3d ${I18N[hs_lbl_silver]} %3d RH %2d PCS %4d PPM %5s" \
                "${r_gold}" "${r_silver}" "${r_hammers}" "${r_pieces}" \
                "${FMT_PPM}"
            if [ "${#plain}" -le 46 ]; then
                printf -v line "  %s${I18N[hs_lbl_gold]} %3d%s %s${I18N[hs_lbl_silver]} %3d%s %sRH %2d%s PCS %4d PPM %5s" \
                    "${TXT_GOLD_SGR}" "${r_gold}" "${TXT_RESET_SGR}" \
                    "${TXT_SILVER_SGR}" "${r_silver}" "${TXT_RESET_SGR}" \
                    "${TXT_WARN_SGR}" "${r_hammers}" "${TXT_RESET_SGR}" \
                    "${r_pieces}" "${FMT_PPM}"
                body+=("${line}")
            else
                body+=("${plain:0:46}")
            fi
            # The round's rows-to-bonus ratio (2026-08-04, user request).
            # A third line of its own, because the two above are full: at
            # 44 of the 46 available characters neither has room for the
            # seven the value needs, and dropping one of their columns to
            # make space would trade a stored figure for a derived one.
            # Three lines per round still fit - the screen shows
            # STATS_RECENT_MAX rounds and lands at 14 of the 18 lines
            # MENU_BODY_MAX offers. No color and hence no length
            # fallback like the two lines above: there is no escape
            # sequence here that a cut could tear apart, and stats_ratio
            # caps the value's width itself.
            stats_ratio "${r_lines}" "${r_bonus}"
            printf -v plain "  %s %s" "${I18N[stats_recent_ratio]}" \
                "${STATS_RATIO}"
            body+=("${plain:0:46}")
            body+=("")
        done
    fi
    debug_event "stats screen shown (${#STATS_RECENT[@]} recent rounds)"
    menu_message "${I18N[stats_title]} (2/3)" "${body[@]}"

    # Third screen (2026-08-03): the rounds played per game mode. Its own
    # screen rather than a block on the first one - that one is full at
    # ten lines of counters, and these seven counters plus their headings
    # would not fit next to it in the 18 lines MENU_BODY_MAX leaves. The
    # timed modes carry their success count indented below their round
    # count, because it is a share of that number and not a figure of its
    # own; Marathon and Hochwasser have none, having no goal to reach.
    # Since 0.10.0 this is also the overview in front of the per-mode
    # screens (menu_stats in lib/menu.sh): it is the one place that puts
    # all modes side by side, which is exactly what a picker wants
    # to show before it is used.
    body=()
    body+=("${I18N[stats_modes_head]}")
    body+=("")
    total=0
    for mode in "${STATS_MODES[@]}"; do
        printf -v line '%-26s %10d' "${I18N[mode_${mode}]}:" \
            "${STATS_MODE[${mode}_rounds]}"
        body+=("${line}")
        total=$(( total + STATS_MODE[${mode}_rounds] ))
        # Marathon and Hochwasser are the modes without a goal, hence
        # without the indented line below their round count.
        if stats_mode_has_goal "${mode}"; then
            printf -v line '  %-24s %s%10d%s' \
                "${I18N[stats_goal_${mode}]}" \
                "${TXT_ACCENT_SGR}" "${STATS_MODE[${mode}_goal]}" \
                "${TXT_RESET_SGR}"
            body+=("${line}")
        fi
    done
    body+=("")
    printf -v line '%-26s %10d' "${I18N[stats_rounds_total]}" "${total}"
    body+=("${line}")
    debug_event "stats screen shown (rounds per mode)"
    menu_message "${I18N[stats_title]} (3/3)" "${body[@]}"
    return 0
}

# stats_mode_screen MODE
# Show one game mode's own counters on a single info screen, in the same
# order and with the same labels as the all-time screen (stats_screen
# above), so the two read as the same table for a smaller set of rounds.
# Added 0.10.0 (user request): the all-time counters do not say in which
# mode anything was achieved, and the modes are played for different
# things - a Marathon round and a three-minute Sprint only compare once
# each mode carries its own totals.
# Two figures are derived rather than stored, for the same reason the
# all-time screen derives its weighted total and its placement rate: the
# rows per round, which is what makes two modes comparable at all, and
# for the timed modes the share of attempts that reached the goal. Both
# read "-" while the mode has no round to divide by.
stats_mode_screen() {
    local mode="${1}"
    local -a body=()
    local line secs rounds rows
    rounds="${STATS_MODE[${mode}_rounds]}"
    rows=$(( STATS_MODE[${mode}_lines] + STATS_MODE[${mode}_bonus_rows] ))
    printf -v line '%-26s %10d' "${I18N[stats_rounds]}" "${rounds}"
    body+=("${line}")
    if stats_mode_has_goal "${mode}"; then
        printf -v line '  %-24s %s%10d%s' \
            "${I18N[stats_goal_${mode}]}" "${TXT_ACCENT_SGR}" \
            "${STATS_MODE[${mode}_goal]}" "${TXT_RESET_SGR}"
        body+=("${line}")
        if [ "${rounds}" -gt 0 ]; then
            printf -v line '  %-24s %9d%%' "${I18N[stats_goal_rate]}" \
                "$(( STATS_MODE[${mode}_goal] * 100 / rounds ))"
        else
            printf -v line '  %-24s %10s' "${I18N[stats_goal_rate]}" "-"
        fi
        body+=("${line}")
    fi
    body+=("")
    printf -v line '%-26s %10d' "${I18N[stats_lines]}" \
        "${STATS_MODE[${mode}_lines]}"
    body+=("${line}")
    printf -v line '%-26s %10d' "${I18N[stats_bonus]}" \
        "${STATS_MODE[${mode}_bonus_rows]}"
    body+=("${line}")
    # Same place and same reasoning as on the all-time screen: this is
    # the figure that says how a mode was actually played, and comparing
    # it between two modes is the whole point of the per-mode screens.
    stats_ratio "${STATS_MODE[${mode}_lines]}" \
        "${STATS_MODE[${mode}_bonus_rows]}"
    printf -v line '%-26s %10s' "${I18N[stats_ratio]}" "${STATS_RATIO}"
    body+=("${line}")
    printf -v line '%-26s %s%10d%s' "${I18N[stats_total]}" \
        "${TXT_ACCENT_SGR}" "${rows}" "${TXT_RESET_SGR}"
    body+=("${line}")
    if [ "${rounds}" -gt 0 ]; then
        printf -v line '%-26s %10d' "${I18N[stats_rows_per_round]}" \
            "$(( rows / rounds ))"
    else
        printf -v line '%-26s %10s' "${I18N[stats_rows_per_round]}" "-"
    fi
    body+=("${line}")
    body+=("")
    printf -v line '%-26s %s%10d%s' "${I18N[stats_gold]}" \
        "${TXT_GOLD_SGR}" "${STATS_MODE[${mode}_gold_squares]}" \
        "${TXT_RESET_SGR}"
    body+=("${line}")
    printf -v line '%-26s %s%10d%s' "${I18N[stats_silver]}" \
        "${TXT_SILVER_SGR}" "${STATS_MODE[${mode}_silver_squares]}" \
        "${TXT_RESET_SGR}"
    body+=("${line}")
    printf -v line '%-26s %s%10d%s' "${I18N[stats_hammer]}" \
        "${TXT_WARN_SGR}" "${STATS_MODE[${mode}_rowhammers]}" \
        "${TXT_RESET_SGR}"
    body+=("${line}")
    body+=("")
    printf -v line '%-26s %10d' "${I18N[stats_pieces]}" \
        "${STATS_MODE[${mode}_pieces]}"
    body+=("${line}")
    # Play time as H:MM:SS like the all-time screen: this is a sum over
    # rounds too, so fmt_duration's MM:SS would grow four-digit minutes.
    secs="${STATS_MODE[${mode}_play_time]}"
    printf -v line '%-26s %10s' "${I18N[stats_playtime]}" \
        "$(printf '%d:%02d:%02d' "$(( secs / 3600 ))" \
            "$(( secs % 3600 / 60 ))" "$(( secs % 60 ))")"
    body+=("${line}")
    fmt_ppm "${STATS_MODE[${mode}_pieces]}" "${secs}"
    printf -v line '%-26s %10s' "${I18N[stats_ppm]}" "${FMT_PPM}"
    body+=("${line}")
    debug_event "stats screen shown (mode ${mode})"
    menu_message "${I18N[stats_title]} - ${I18N[mode_${mode}]}" "${body[@]}"
    return 0
}
