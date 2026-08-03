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
#   stats_screen renders the statistics for the "Statistik" main menu
#   entry via menu_message (lib/menu.sh) on three screens: the all-time
#   counters first, the recent rounds second (both together outgrew the
#   22-row minimum terminal) and the per-mode round counters third. Since 0.8.0 the weighted total, the
#   gold/silver/rowhammer counters and the recent-round Rows/Gold/Silb/RH
#   figures are colored with the TXT_* SGR globals (lib/render.sh,
#   theme-aware, empty in --no-color/NO_COLOR mode); a recent-round line
#   that would overrun the 46-char budget skips coloring and falls back
#   to the plain truncated text instead of risking a cut escape sequence.
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.9.0  (2026-08-03)

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
STATS_LINE_RE='^(lines|bonus_rows|gold_squares|silver_squares|rowhammers|pieces|play_time|rounds_marathon|rounds_ultra|rounds_ultra_goal|rounds_sprint|rounds_sprint_goal|rounds_timeattack|rounds_timeattack_goal)=([0-9]{1,15})$'
STATS_RECENT_RE='^recent=([0-9]{1,15}(\|[0-9]{1,15}){6}\|[0-9]{4}-[0-9]{2}-[0-9]{2})$'

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

# Rounds played per game mode, and for the three timed modes how many of
# them ended in that mode's regular ending rather than in a top-out:
# Ultra reaching ULTRA_TARGET_ROWS, Sprint playing its full
# SPRINT_TIME_MS, Time Attack running its clock down to zero (see
# rowhammer.sh). Added 2026-08-03 with the Time Attack mode, the last
# open part of the "statistics per mode" roadmap item: the counters
# above say what was achieved but not in which mode, and for the timed
# modes the interesting figure is the share of attempts that got there -
# which no other stored number can reconstruct, because a failed run is
# not in that mode's highscore list.
# One counter per mode instead of one keyed array: the file format is
# flat "key=value" lines, and a fixed set of keys keeps the validation
# regex above the single source of truth for what may appear in it.
STATS_ROUNDS_MARATHON=0
STATS_ROUNDS_ULTRA=0
STATS_ROUNDS_ULTRA_GOAL=0
STATS_ROUNDS_SPRINT=0
STATS_ROUNDS_SPRINT_GOAL=0
STATS_ROUNDS_TIMEATTACK=0
STATS_ROUNDS_TIMEATTACK_GOAL=0

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
    STATS_ROUNDS_MARATHON=0
    STATS_ROUNDS_ULTRA=0
    STATS_ROUNDS_ULTRA_GOAL=0
    STATS_ROUNDS_SPRINT=0
    STATS_ROUNDS_SPRINT_GOAL=0
    STATS_ROUNDS_TIMEATTACK=0
    STATS_ROUNDS_TIMEATTACK_GOAL=0
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
                rounds_marathon)
                    STATS_ROUNDS_MARATHON=$(( 10#${BASH_REMATCH[2]} )) ;;
                rounds_ultra)
                    STATS_ROUNDS_ULTRA=$(( 10#${BASH_REMATCH[2]} )) ;;
                rounds_ultra_goal)
                    STATS_ROUNDS_ULTRA_GOAL=$(( 10#${BASH_REMATCH[2]} )) ;;
                rounds_sprint)
                    STATS_ROUNDS_SPRINT=$(( 10#${BASH_REMATCH[2]} )) ;;
                rounds_sprint_goal)
                    STATS_ROUNDS_SPRINT_GOAL=$(( 10#${BASH_REMATCH[2]} )) ;;
                rounds_timeattack)
                    STATS_ROUNDS_TIMEATTACK=$(( 10#${BASH_REMATCH[2]} )) ;;
                rounds_timeattack_goal)
                    STATS_ROUNDS_TIMEATTACK_GOAL=$(( 10#${BASH_REMATCH[2]} )) ;;
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
    debug_event "stats: loaded lines=${STATS_LINES} bonus=${STATS_BONUS_ROWS} gold=${STATS_GOLD} silver=${STATS_SILVER} rowhammers=${STATS_ROWHAMMERS} pieces=${STATS_PIECES} play_time=${STATS_PLAY_TIME} recent=${#STATS_RECENT[@]} from ${f}"
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
        printf 'rowhammers=%d\n' "${STATS_ROWHAMMERS}"
        printf 'pieces=%d\n' "${STATS_PIECES}"
        printf 'play_time=%d\n' "${STATS_PLAY_TIME}"
        printf 'rounds_marathon=%d\n' "${STATS_ROUNDS_MARATHON}"
        printf 'rounds_ultra=%d\n' "${STATS_ROUNDS_ULTRA}"
        printf 'rounds_ultra_goal=%d\n' "${STATS_ROUNDS_ULTRA_GOAL}"
        printf 'rounds_sprint=%d\n' "${STATS_ROUNDS_SPRINT}"
        printf 'rounds_sprint_goal=%d\n' "${STATS_ROUNDS_SPRINT_GOAL}"
        printf 'rounds_timeattack=%d\n' "${STATS_ROUNDS_TIMEATTACK}"
        printf 'rounds_timeattack_goal=%d\n' \
            "${STATS_ROUNDS_TIMEATTACK_GOAL}"
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
# (GOAL_REACHED); together they feed the per-mode round counters
# (2026-08-03). They are counted behind the same guard as everything
# else: a round that placed no piece at all is not a round played, and
# counting it here while it is missing from every other counter would
# only make the two sets disagree.
stats_add_round() {
    local lines="${1}" bonus="${2}" gold="${3}" silver="${4}"
    local rowhammers="${5}" pieces="${6}" time="${7}"
    local mode="${8}" goal="${9}"
    local entry
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
    # An unknown mode name (only reachable from a future mode whose
    # branch is missing here) is counted nowhere rather than lumped in
    # with Marathon, so the per-mode screen shows a gap instead of a
    # wrong attribution.
    case "${mode}" in
        marathon)
            STATS_ROUNDS_MARATHON=$(( STATS_ROUNDS_MARATHON + 1 ))
            ;;
        ultra)
            STATS_ROUNDS_ULTRA=$(( STATS_ROUNDS_ULTRA + 1 ))
            if [ "${goal}" -eq 1 ]; then
                STATS_ROUNDS_ULTRA_GOAL=$(( STATS_ROUNDS_ULTRA_GOAL + 1 ))
            fi
            ;;
        sprint)
            STATS_ROUNDS_SPRINT=$(( STATS_ROUNDS_SPRINT + 1 ))
            if [ "${goal}" -eq 1 ]; then
                STATS_ROUNDS_SPRINT_GOAL=$(( STATS_ROUNDS_SPRINT_GOAL + 1 ))
            fi
            ;;
        timeattack)
            STATS_ROUNDS_TIMEATTACK=$(( STATS_ROUNDS_TIMEATTACK + 1 ))
            if [ "${goal}" -eq 1 ]; then
                STATS_ROUNDS_TIMEATTACK_GOAL=$(( STATS_ROUNDS_TIMEATTACK_GOAL + 1 ))
            fi
            ;;
    esac
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

# stats_screen
# Show the all-time statistics as a menu-style info screen and wait for
# any key. Labels are German like the menus (ASCII, no umlauts per the
# conventions). The weighted total (lines + bonus rows) is shown as a
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
    local r_time r_date secs plain
    printf -v line '%-26s %10d' "Abgebaute Reihen:" "${STATS_LINES}"
    body+=("${line}")
    printf -v line '%-26s %10d' "Bonusreihen:" "${STATS_BONUS_ROWS}"
    body+=("${line}")
    printf -v line '%-26s %s%10d%s' "Reihen gesamt (gewertet):" \
        "${TXT_ACCENT_SGR}" "$(( STATS_LINES + STATS_BONUS_ROWS ))" \
        "${TXT_RESET_SGR}"
    body+=("${line}")
    body+=("")
    printf -v line '%-26s %s%10d%s' "Goldbloecke:" \
        "${TXT_GOLD_SGR}" "${STATS_GOLD}" "${TXT_RESET_SGR}"
    body+=("${line}")
    printf -v line '%-26s %s%10d%s' "Silberbloecke:" \
        "${TXT_SILVER_SGR}" "${STATS_SILVER}" "${TXT_RESET_SGR}"
    body+=("${line}")
    # The namesake move: four rows cleared in one go.
    printf -v line '%-26s %s%10d%s' "Rowhammer (4 Reihen):" \
        "${TXT_WARN_SGR}" "${STATS_ROWHAMMERS}" "${TXT_RESET_SGR}"
    body+=("${line}")
    body+=("")
    printf -v line '%-26s %10d' "Abgelegte Steine:" "${STATS_PIECES}"
    body+=("${line}")
    # Total play time as H:MM:SS - fmt_duration's MM:SS is meant for a
    # single round and would grow to four-digit minutes here.
    secs="${STATS_PLAY_TIME}"
    printf -v line '%-26s %10s' "Spielzeit gesamt:" \
        "$(printf '%d:%02d:%02d' "$(( secs / 3600 ))" \
            "$(( secs % 3600 / 60 ))" "$(( secs % 60 ))")"
    body+=("${line}")
    fmt_ppm "${STATS_PIECES}" "${STATS_PLAY_TIME}"
    printf -v line '%-26s %10s' "Steine/Minute (PCS/min):" "${FMT_PPM}"
    body+=("${line}")
    debug_event "stats screen shown (counters)"
    menu_message "Statistik (1/3)" "${body[@]}"

    # Second screen: the recent rounds. The first line per round carries
    # the date and the row counters, the second the squares, the
    # rowhammers and the placement rate; the Rows column is the round's
    # score (lines + bonus), derived instead of stored so the file can
    # never contradict itself.
    body=()
    body+=("Letzte Spiele (neueste zuerst):")
    body+=("")
    if [ "${#STATS_RECENT[@]}" -eq 0 ]; then
        body+=("Noch keine Spiele.")
    else
        for entry in "${STATS_RECENT[@]}"; do
            IFS='|' read -r r_lines r_bonus r_gold r_silver r_hammers \
                r_pieces r_time r_date <<< "${entry}"
            printf -v plain '%10s Rows %5d Reihen %4d Bonus %4d' \
                "${r_date}" "$(( r_lines + r_bonus ))" "${r_lines}" \
                "${r_bonus}"
            # Same safety fallback as highscore_screen: the counters here
            # are internal and bounded in practice, but a corrupted stats
            # file could still overrun the 46-char budget, so an
            # oversized line skips coloring rather than risking a cut
            # escape sequence.
            if [ "${#plain}" -le 46 ]; then
                printf -v line '%10s %sRows %5d%s Reihen %4d Bonus %4d' \
                    "${r_date}" "${TXT_ACCENT_SGR}" \
                    "$(( r_lines + r_bonus ))" "${TXT_RESET_SGR}" \
                    "${r_lines}" "${r_bonus}"
                body+=("${line}")
            else
                body+=("${plain:0:46}")
            fi
            fmt_ppm "${r_pieces}" "${r_time}"
            printf -v plain '  Gold %3d Silb %3d RH %2d PCS %4d PPM %5s' \
                "${r_gold}" "${r_silver}" "${r_hammers}" "${r_pieces}" \
                "${FMT_PPM}"
            if [ "${#plain}" -le 46 ]; then
                printf -v line '  %sGold %3d%s %sSilb %3d%s %sRH %2d%s PCS %4d PPM %5s' \
                    "${TXT_GOLD_SGR}" "${r_gold}" "${TXT_RESET_SGR}" \
                    "${TXT_SILVER_SGR}" "${r_silver}" "${TXT_RESET_SGR}" \
                    "${TXT_WARN_SGR}" "${r_hammers}" "${TXT_RESET_SGR}" \
                    "${r_pieces}" "${FMT_PPM}"
                body+=("${line}")
            else
                body+=("${plain:0:46}")
            fi
            body+=("")
        done
    fi
    debug_event "stats screen shown (${#STATS_RECENT[@]} recent rounds)"
    menu_message "Statistik (2/3)" "${body[@]}"

    # Third screen (2026-08-03): the rounds played per game mode. Its own
    # screen rather than a block on the first one - that one is full at
    # ten lines of counters, and these seven counters plus their headings
    # would not fit next to it in the 18 lines MENU_BODY_MAX leaves. The
    # timed modes carry their success count indented below their round
    # count, because it is a share of that number and not a figure of its
    # own; Marathon has none, having no goal to reach.
    body=()
    body+=("Runden je Spielmodus:")
    body+=("")
    printf -v line '%-26s %10d' "Marathon:" "${STATS_ROUNDS_MARATHON}"
    body+=("${line}")
    printf -v line '%-26s %10d' "Ultra:" "${STATS_ROUNDS_ULTRA}"
    body+=("${line}")
    printf -v line '  %-24s %s%10d%s' "davon Ziel erreicht:" \
        "${TXT_ACCENT_SGR}" "${STATS_ROUNDS_ULTRA_GOAL}" "${TXT_RESET_SGR}"
    body+=("${line}")
    printf -v line '%-26s %10d' "Sprint:" "${STATS_ROUNDS_SPRINT}"
    body+=("${line}")
    printf -v line '  %-24s %s%10d%s' "davon volle Zeit:" \
        "${TXT_ACCENT_SGR}" "${STATS_ROUNDS_SPRINT_GOAL}" "${TXT_RESET_SGR}"
    body+=("${line}")
    printf -v line '%-26s %10d' "Time Attack:" \
        "${STATS_ROUNDS_TIMEATTACK}"
    body+=("${line}")
    printf -v line '  %-24s %s%10d%s' "davon Zeit abgelaufen:" \
        "${TXT_ACCENT_SGR}" "${STATS_ROUNDS_TIMEATTACK_GOAL}" \
        "${TXT_RESET_SGR}"
    body+=("${line}")
    body+=("")
    printf -v line '%-26s %10d' "Runden gesamt:" \
        "$(( STATS_ROUNDS_MARATHON + STATS_ROUNDS_ULTRA \
            + STATS_ROUNDS_SPRINT + STATS_ROUNDS_TIMEATTACK ))"
    body+=("${line}")
    debug_event "stats screen shown (rounds per mode)"
    menu_message "Statistik (3/3)" "${body[@]}"
    return 0
}
