#!/usr/bin/env bash
#
# lib/demo.sh
#
# Description:
#   Demo recording and playback for rowhammer. A round is recorded as the
#   sequence of things that happened to it - the player's actions, the
#   gravity steps, the lock-delay locks and the piece stream the round was
#   dealt - not as a picture of the screen. Replaying feeds that sequence
#   back into the real game functions (try_move, try_rotate, step_down,
#   hard_drop, hold_piece, lock_and_next), so a demo shows what the game
#   really did rather than what a terminal once printed.
#
#   Why actions and not frames:
#     - Size. A frame recording costs the whole screen per update; an
#       action recording costs a handful of bytes per event. Measured
#       against a real round: roughly 4 events per second of play (two to
#       three inputs plus the gravity steps) at about 9 bytes each, so
#       ~2 kB per minute and ~20 kB for a ten minute round. Ten of them
#       (DEMO_MAX) stay well under a megabyte, which is why the count cap
#       below can be a flat number instead of a size budget.
#     - Independence from the terminal. The recording holds no ANSI at
#       all, so it does not care about the terminal size, the color mode,
#       the color theme or the render mode (--render-mode partial|full,
#       see rowhammer.sh) of either session: playback rebuilds every
#       frame through the normal renderer of the session watching it. A
#       demo recorded on a partial-mode session therefore replays
#       correctly in full mode and the other way round, and a recording
#       made in one color theme can be watched in another. A frame or
#       asciinema-style recording would have had to pin all of that down
#       and would have had to record in full mode to stay replayable.
#     - Robustness. The piece stream is stored literally (the letters the
#       queue was filled with), not as an RNG seed: bash's RANDOM is
#       seeded once per session, not per round, and its generator changed
#       between bash releases - a seed would replay differently on a
#       different bash. The literal stream costs one byte per piece.
#
#   Timing. Every event carries the round's play time (PLAY_MS, pauses
#   excluded) as a delta to the event before it. Playback runs its own
#   clock over that timeline, so the replay is paced exactly like the
#   round was, can be slowed down or sped up (DEMO_SPEEDS) and can be
#   paused - and no drift can accumulate, because the clock is compared
#   against absolute timestamps rather than slept through per event.
#
#   Storage. During the round the events go to a file on a RAM disk
#   (XDG_RUNTIME_DIR, /dev/shm; see demo_tmp_base) in batches of
#   DEMO_FLUSH_MAX lines - never to the data directory, so a round costs
#   no disk writes while it is being played. Only when the round really
#   ends (record_round in rowhammer.sh) is the finished recording
#   assembled into ${DATA_DIR}/demos/<timestamp>-<mode>.demo, atomically
#   (temp file + mv) like every other persistent file of this game. The
#   directory keeps the DEMO_MAX newest recordings; older ones are
#   removed when a new one arrives.
#
#   The file is parsed and validated line by line, never sourced: it is
#   plain data, and a corrupted or hand-edited file must be rejected
#   rather than executed. Every field has its own pattern.
#
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.1.0  (2026-08-03)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/demo.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# Directory below DATA_DIR holding the finished recordings, and the file
# name suffix. The name is also the reset target "demo" (see reset_run in
# rowhammer.sh), which is why it lives here with the module that owns it.
DEMO_DIR_NAME="demos"
DEMO_FILE_EXT=".demo"

# Format version of the recording files. Bumped when the event alphabet
# or the header changes; a file of any other version is rejected on load
# rather than guessed at (no backward compatibility, see CLAUDE.md).
DEMO_FORMAT_VERSION=1

# How many recordings are kept. Ten like the highscore lists, and for the
# same reason: it is the number a player still finds their way around in.
# The demo list is a plain selection menu, and ten entries plus "Zurueck"
# fit a 22-row terminal with room to spare, which a larger cap would not.
# A total-size budget was considered and dropped: with ~20 kB for a long
# round the ten files together stay far below anything worth budgeting.
DEMO_MAX=10

# Event lines buffered in memory before they are appended to the RAM disk
# file. One append per 64 events is roughly one every 15 seconds of play,
# so the write never lands in a frame the player would notice, and a
# session killed mid-round loses at most those few seconds.
DEMO_FLUSH_MAX=64

# Playback speeds in percent of the recorded pace and their labels for
# the HUD (the pane value column is five characters wide, see pane_stat).
# The two arrays are indexed together by DEMO_SPEED_IDX.
DEMO_SPEEDS=(25 50 100 200 400)
DEMO_SPEED_LABELS=("0.25x" "0.50x" "1.00x" "2.00x" "4.00x")
DEMO_SPEED_DEFAULT=2

# Validation patterns. The numeric one caps the digits so a hand-edited
# file cannot push arithmetic out of bash's integer range; the name
# pattern is the one the player name is validated against everywhere else
# (rowhammer.sh, HS_FIELD_NAME_RE in lib/highscore.sh).
DEMO_NUM_RE='^[0-9]{1,9}$'
DEMO_NAME_RE='^[A-Za-z0-9_ -]{1,16}$'
DEMO_MODE_RE='^(marathon|ultra|sprint|timeattack)$'
DEMO_DATE_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$'
DEMO_PCS_RE='^[IOTSZJL]{1,80}$'
# One event: the play-time delta in milliseconds since the previous event
# followed by the action letter. The alphabet, deliberately one letter per
# thing that can happen to a round:
#   l/r  move left / right          c/a  rotate clockwise / counter-cw
#   s    soft drop                  h    hard drop (locks the piece)
#   o    hold / swap                g    gravity step
#   k    lock delay expired (the piece locks where it rests)
# A hard drop locks by itself, so it is never followed by a "k"; a piece
# leaving the board through a blocked spawn needs no event either, since
# the replay reaches that spawn on its own.
DEMO_EVENT_RE='^([0-9]{1,7})([lrcashogk])$'
DEMO_END_RE='^(over|goal|quit)$'

# --- Recording state ------------------------------------------------------
# Whether the running round is being recorded, the RAM disk file it is
# written to, the buffered event lines, the piece letters the round was
# dealt so far and the play time the last event was stamped with.
DEMO_RECORDING=0
DEMO_TMP_FILE=""
DEMO_BUF=()
DEMO_PIECES=""
DEMO_LAST_MS=0

# --- Playback state -------------------------------------------------------
# DEMO_PLAYING is read outside this module: queue_fill (lib/pieces.sh)
# takes its pieces from the recorded stream instead of the bag while it is
# set, record_round (rowhammer.sh) refuses to bank a replayed round, and
# the renderer (lib/render.sh) shows the speed and the end-of-demo box.
DEMO_PLAYING=0
DEMO_ENDED=0
DEMO_SPEED_IDX="${DEMO_SPEED_DEFAULT}"
DEMO_SPEED=100
DEMO_SPEED_LABEL="1.00x"
DEMO_PLAY_PIECES=""
DEMO_PLAY_POS=0
DEMO_EV_T=()
DEMO_EV_A=()
# Play time the replay has reached, in milliseconds of the recorded
# round: the playback loop advances it by the real time between two
# passes scaled by DEMO_SPEED, and every event is due once it has passed
# the event's timestamp.
DEMO_CLOCK_MS=0
# Header fields of the loaded recording that are actually used - the
# rules of the round, what the list shows and what its final box says.
# The remaining header fields are validated on load like these but not
# kept: the replay recomputes every counter as it runs, so keeping them
# would only invite reading a stored number where the live one belongs.
DEMO_HDR_MODE="marathon"
DEMO_HDR_DATE=""
DEMO_HDR_TIME=0
DEMO_HDR_ROWS=0
DEMO_HDR_END="quit"

# Entries of the demo list screen, filled by demo_scan: the file paths,
# the menu labels belonging to them and, per entry, whether the recording
# is protected by a highscore entry - newest first. DEMO_LIST_KEPT is how
# many of them are, which the list screen needs for its legend.
DEMO_LIST_FILE=()
DEMO_LIST_LABEL=()
DEMO_LIST_MARKED=()
DEMO_LIST_KEPT=0

# demo_dir
# Path of the recording directory. A function rather than a constant
# because DATA_DIR is a setting; every other module resolves its file the
# same way at call time.
demo_dir() {
    DEMO_DIR="${DATA_DIR}/${DEMO_DIR_NAME}"
    return 0
}

# demo_tmp_base
# Pick the directory the running recording is written to: a RAM disk, so
# the frequent small appends of a round never reach a real disk (frame
# times and, on SSDs, write cycles). XDG_RUNTIME_DIR is a tmpfs by
# definition and private to the user, /dev/shm is the usual fallback.
# TMPDIR/tmp is the last resort and may well be a real filesystem - the
# recording still works there, it just loses that guarantee, which is why
# it comes last and is noted in the debug log.
DEMO_TMP_BASE=""
demo_tmp_base() {
    local d
    for d in "${XDG_RUNTIME_DIR:-}" /dev/shm; do
        if [ -n "${d}" ] && [ -d "${d}" ] && [ -w "${d}" ]; then
            DEMO_TMP_BASE="${d}"
            return 0
        fi
    done
    d="${TMPDIR:-/tmp}"
    if [ -d "${d}" ] && [ -w "${d}" ]; then
        DEMO_TMP_BASE="${d}"
        debug_event "demo: no RAM disk found, recording to ${d} (may be a real filesystem)"
        return 0
    fi
    DEMO_TMP_BASE=""
    return 1
}

# demo_record_start MODE
# Begin recording the round that is just starting. Called from game_reset
# (rowhammer.sh); does nothing when recording is switched off, when a
# demo is being replayed (a replay must not record itself) or when no
# writable temp directory could be found - a failed recording is never a
# reason to keep a player from playing, so it only reports into the debug
# log and leaves the round alone.
demo_record_start() {
    local mode="${1}"
    # A replay runs through game_reset as well; it must not touch the
    # recording state at all - hence before the discard below, which is
    # there so a new round replaces a recording left over from one that
    # was never finished.
    if [ "${DEMO_PLAYING}" -eq 1 ]; then
        return 0
    fi
    demo_record_discard
    if [ "${DEMO_RECORD}" != "on" ]; then
        return 0
    fi
    if ! demo_tmp_base; then
        debug_event "demo: no writable temp directory, round is not recorded"
        return 0
    fi
    if ! DEMO_TMP_FILE="$(mktemp -- "${DEMO_TMP_BASE}/rowhammer-demo.XXXXXX")"; then
        DEMO_TMP_FILE=""
        debug_event "demo: could not create a temp file below ${DEMO_TMP_BASE}, round is not recorded"
        return 0
    fi
    DEMO_RECORDING=1
    DEMO_BUF=()
    DEMO_PIECES=""
    DEMO_LAST_MS=0
    debug_event "demo: recording round (mode=${mode}) to ${DEMO_TMP_FILE}"
    return 0
}

# demo_record_piece TYPE
# Note one piece the queue was filled with. Called from queue_fill
# (lib/pieces.sh), which is the single place pieces enter the round, so
# the stream covers the preview and the spawns alike.
demo_record_piece() {
    if [ "${DEMO_RECORDING}" -eq 0 ]; then
        return 0
    fi
    DEMO_PIECES+="${1}"
    return 0
}

# demo_record_event ACTION
# Append one event, stamped with the play time it happened at. The
# timestamp is computed the way play_clock_tick would compute it, but
# without writing it back: recording must never change how the round
# plays, and PLAY_MS is what the Sprint mode and the HUD read. Only
# NOW_MS is refreshed, which every caller in the game loop re-reads
# anyway. Not called while the round is paused (the game loop and
# handle_key skip everything that could record then), so the stale
# PLAY_LAST of a pause can never leak into a delta.
demo_record_event() {
    local ts delta
    if [ "${DEMO_RECORDING}" -eq 0 ]; then
        return 0
    fi
    now_ms
    ts=$(( PLAY_MS + NOW_MS - PLAY_LAST ))
    delta=$(( ts - DEMO_LAST_MS ))
    # A clock that jumped backwards (NTP step) must not write a negative
    # delta into the file; the event then simply lands on the previous
    # event's timestamp.
    if [ "${delta}" -lt 0 ]; then
        delta=0
    fi
    DEMO_LAST_MS="${ts}"
    DEMO_BUF+=("e=${delta}${1}")
    if [ "${#DEMO_BUF[@]}" -ge "${DEMO_FLUSH_MAX}" ]; then
        demo_flush
    fi
    return 0
}

# demo_flush
# Write the buffered events to the RAM disk file. A failing write ends
# the recording instead of the round: the game keeps running, the demo is
# dropped with a note in the debug log.
demo_flush() {
    if [ "${DEMO_RECORDING}" -eq 0 ] || [ "${#DEMO_BUF[@]}" -eq 0 ]; then
        return 0
    fi
    if ! printf '%s\n' "${DEMO_BUF[@]}" >> "${DEMO_TMP_FILE}"; then
        debug_event "demo: write to ${DEMO_TMP_FILE} failed, recording stopped"
        demo_record_discard
        return 1
    fi
    DEMO_BUF=()
    return 0
}

# demo_record_discard
# Drop the running recording and its temp file. Used when a recording is
# replaced by a new one, when writing failed and from the exit trap, so a
# session that ends mid-round leaves no file behind on the RAM disk.
demo_record_discard() {
    if [ -n "${DEMO_TMP_FILE}" ]; then
        rm -f -- "${DEMO_TMP_FILE}"
    fi
    DEMO_RECORDING=0
    DEMO_TMP_FILE=""
    DEMO_BUF=()
    DEMO_PIECES=""
    DEMO_LAST_MS=0
    return 0
}

# demo_record_finish END [HASH]
# Close the recording of a finished round and move it into the data
# directory. END is how the round ended: "goal" (Ultra target reached or
# Sprint time survived), "over" (topped out) or "quit" (ended from the
# pause menu). HASH is the round's identifier (round_hash in
# rowhammer.sh), which goes into the file name: the same hash is stored
# with the round's highscore entry, so demo_prune can tell which
# recordings still back a place on one of the lists and has to keep
# them. It is part of the name rather than of the file so that listing
# and pruning never have to open a single recording. Called from record_round (rowhammer.sh), so a round is
# stored exactly once and at the same moment it enters the highscore
# list, the wonder counter and the statistics.
# A round without a single event is dropped: it was started and left
# again, and an empty recording is only noise in the list.
demo_record_finish() {
    local end="${1}" hash="${2:--}" name path tmp i suffix
    if [ "${DEMO_RECORDING}" -eq 0 ]; then
        return 0
    fi
    demo_flush || return 0
    if [ ! -s "${DEMO_TMP_FILE}" ]; then
        debug_event "demo: round had no events, recording dropped"
        demo_record_discard
        return 0
    fi
    demo_dir
    if ! mkdir -p -- "${DEMO_DIR}"; then
        debug_event "demo: could not create ${DEMO_DIR}, recording dropped"
        demo_record_discard
        return 0
    fi
    # File name from the date, so the directory sorts oldest to newest by
    # name and the pruning below needs no stat calls. A second recording
    # within the same second (possible for two very short rounds) gets a
    # counter appended rather than overwriting the first one.
    # <date>-<mode>-<hash>: the date first so the glob is sorted
    # chronologically, the hash last so it can be read back off the name
    # with a single expansion (demo_file_hash). A counter for a second
    # recording within the same second goes between date and mode, which
    # keeps that expansion right - two rounds finishing in the same
    # second is unlikely, two of them also sharing a hash impossible.
    name="$(date +%Y%m%d-%H%M%S)"
    path="${DEMO_DIR}/${name}-${GAME_MODE}-${hash}${DEMO_FILE_EXT}"
    i=2
    while [ -e "${path}" ] && [ "${i}" -le 9 ]; do
        printf -v suffix '%s-%d' "${name}" "${i}"
        path="${DEMO_DIR}/${suffix}-${GAME_MODE}-${hash}${DEMO_FILE_EXT}"
        i=$(( i + 1 ))
    done
    if ! tmp="$(mktemp -- "${DEMO_DIR}/.demo.XXXXXX")"; then
        debug_event "demo: could not create a temp file in ${DEMO_DIR}, recording dropped"
        demo_record_discard
        return 0
    fi
    # Header, piece stream, events - written into a temp file and moved
    # into place, so a crash can never leave a half-written recording.
    {
        printf '# rowhammer demo recording. Parsed and validated on load, never sourced.\n'
        printf '# pcs = the piece stream, e = <play time delta in ms><action>.\n'
        printf 'version=%d\n' "${DEMO_FORMAT_VERSION}"
        printf 'game=%s\n' "${ROWHAMMER_VERSION}"
        printf 'mode=%s\n' "${GAME_MODE}"
        printf 'name=%s\n' "${PLAYER_NAME}"
        printf 'date=%s\n' "$(date '+%Y-%m-%d %H:%M')"
        printf 'time=%d\n' "${PLAY_MS}"
        printf 'lines=%d\n' "${CLEARED_TOTAL}"
        printf 'rows=%d\n' "${ROW_CREDIT}"
        printf 'level=%d\n' "${LEVEL}"
        printf 'gold=%d\n' "${GOLD_COUNT}"
        printf 'silver=%d\n' "${SILVER_COUNT}"
        printf 'rowhammers=%d\n' "${ROWHAMMER_COUNT}"
        printf 'pieces=%d\n' "${PIECE_COUNT}"
        printf 'goal=%d\n' "${GOAL_REACHED}"
        printf 'end=%s\n' "${end}"
        # The stream is cut into lines of at most 80 letters so no line of
        # the file grows unbounded (DEMO_PCS_RE caps it at that length).
        for (( i = 0; i < ${#DEMO_PIECES}; i += 80 )); do
            printf 'pcs=%s\n' "${DEMO_PIECES:i:80}"
        done
        cat -- "${DEMO_TMP_FILE}"
    } > "${tmp}"
    if ! mv -f -- "${tmp}" "${path}"; then
        rm -f -- "${tmp}"
        debug_event "demo: could not move the recording to ${path}, dropped"
        demo_record_discard
        return 0
    fi
    debug_event "demo: recording saved to ${path} (end=${end} time=${PLAY_MS}ms rows=${ROW_CREDIT} pieces=${#DEMO_PIECES})"
    demo_record_discard
    demo_prune "${path}"
    return 0
}

# demo_file_hash FILE
# The round hash a recording carries in its name, into the global
# DEMO_FILE_HASH ("-" when the name has none, which is what a file from
# before 0.46.0 or a renamed one looks like). Reading it off the name
# instead of out of the file is the whole point of putting it there:
# listing and pruning stay free of file reads.
DEMO_FILE_HASH="-"
demo_file_hash() {
    local base="${1##*/}"
    base="${base%${DEMO_FILE_EXT}}"
    DEMO_FILE_HASH="${base##*-}"
    if ! [[ "${DEMO_FILE_HASH}" =~ ^[0-9a-f]{8}$ ]]; then
        DEMO_FILE_HASH="-"
    fi
    return 0
}

# demo_protected FILE
# True when this recording still backs an entry on one of the highscore
# lists, which is what keeps it from being pruned. Expects
# highscore_hash_set to have filled HS_HASH_SET.
demo_protected() {
    demo_file_hash "${1}"
    if [ "${DEMO_FILE_HASH}" = "-" ]; then
        return 1
    fi
    [ -n "${HS_HASH_SET[${DEMO_FILE_HASH}]:-}" ]
}

# demo_prune [KEEP]
# Keep the DEMO_MAX newest ordinary recordings, deleting older ones -
# the file names start with the date, so the glob is already in that
# order. A recording that still backs a highscore entry is never deleted
# (user decision): the run behind a top ten place must stay watchable for
# as long as it holds that place, and it gives up that protection by
# itself the moment a better round pushes its entry off the list.
# The cap counts the ordinary recordings only, not the protected ones.
# Counting them together looks tidier but breaks down exactly where the
# feature matters: with DEMO_MAX highscore-backed recordings on disk, the
# budget would be used up by them alone and every freshly played round
# would lose its recording the moment it was written. The directory can
# therefore hold more than DEMO_MAX files - at worst the four lists' ten
# entries each plus DEMO_MAX ordinary ones, some fifty recordings or a
# few megabytes at the very most.
# KEEP is the recording just written. It counts against the cap like any
# other, but it is sorted to the end of the list rather than left where
# its name puts it: it is the newest recording by definition, while
# "newest" is otherwise decided by the file name and therefore by the
# clock. Without that, a clock that jumped backwards would let the round
# a player just finished lose its recording in the same breath.
demo_prune() {
    local keep="${1:-}"
    local -a files
    local -a ordinary=()
    local i over keep_found=0
    demo_dir
    files=("${DEMO_DIR}"/*"${DEMO_FILE_EXT}")
    # An unmatched glob stays unexpanded; that single non-existing entry
    # is the empty-directory case.
    if [ ! -e "${files[0]}" ]; then
        return 0
    fi
    if [ "${#files[@]}" -le "${DEMO_MAX}" ]; then
        # Cannot be over the cap either way, so the highscore lists do
        # not even have to be looked at.
        return 0
    fi
    highscore_hash_set
    for (( i = 0; i < ${#files[@]}; i++ )); do
        if [ -n "${keep}" ] && [ "${files[i]}" = "${keep}" ]; then
            keep_found=1
            continue
        fi
        if demo_protected "${files[i]}"; then
            debug_event "demo: kept ${files[i]} (hash ${DEMO_FILE_HASH} still holds a highscore)"
            continue
        fi
        ordinary+=("${files[i]}")
    done
    # Appended last, so the deletion below - which works from the front,
    # oldest first - reaches it only once nothing else is left.
    if [ "${keep_found}" -eq 1 ]; then
        ordinary+=("${keep}")
    fi
    over=$(( ${#ordinary[@]} - DEMO_MAX ))
    for (( i = 0; i < over; i++ )); do
        rm -f -- "${ordinary[i]}"
        debug_event "demo: pruned ${ordinary[i]} (keeping ${DEMO_MAX} ordinary recordings)"
    done
    return 0
}

# demo_header_read FILE
# Read and validate the header of a recording into the DEMO_HDR_*
# globals. Stops at the first non-header line, so listing the directory
# costs a handful of lines per file instead of the whole event stream.
# Returns 1 for a file that is not a valid recording of this format
# version; the caller shows it as defective rather than dropping it
# silently, so a broken file can still be deleted from the menu.
demo_header_read() {
    local file="${1}" line key val version=0
    DEMO_HDR_MODE=""
    DEMO_HDR_DATE=""
    DEMO_HDR_TIME=0
    DEMO_HDR_ROWS=0
    DEMO_HDR_END=""
    if [ ! -r "${file}" ]; then
        return 1
    fi
    while IFS= read -r line; do
        case "${line}" in
            '#'*|'') continue ;;
            pcs=*|e=*) break ;;
        esac
        key="${line%%=*}"
        val="${line#*=}"
        case "${key}" in
            version)
                [[ "${val}" =~ ${DEMO_NUM_RE} ]] || return 1
                version=$(( 10#${val} ))
                ;;
            mode)
                [[ "${val}" =~ ${DEMO_MODE_RE} ]] || return 1
                DEMO_HDR_MODE="${val}"
                ;;
            name)
                [[ "${val}" =~ ${DEMO_NAME_RE} ]] || return 1
                ;;
            date)
                [[ "${val}" =~ ${DEMO_DATE_RE} ]] || return 1
                DEMO_HDR_DATE="${val}"
                ;;
            time)
                [[ "${val}" =~ ${DEMO_NUM_RE} ]] || return 1
                DEMO_HDR_TIME=$(( 10#${val} ))
                ;;
            rows)
                [[ "${val}" =~ ${DEMO_NUM_RE} ]] || return 1
                DEMO_HDR_ROWS=$(( 10#${val} ))
                ;;
            lines)
                [[ "${val}" =~ ${DEMO_NUM_RE} ]] || return 1
                ;;
            goal)
                [[ "${val}" =~ ^[01]$ ]] || return 1
                ;;
            end)
                [[ "${val}" =~ ${DEMO_END_RE} ]] || return 1
                DEMO_HDR_END="${val}"
                ;;
            # The remaining header fields (game, level, gold, silver,
            # rowhammers, pieces) are informational for a human reading
            # the file; like name, lines and goal above they are checked
            # for shape but not kept, because the replay recomputes every
            # counter as it runs.
            game|level|gold|silver|rowhammers|pieces) ;;
            *) return 1 ;;
        esac
    done < "${file}"
    if [ "${version}" -ne "${DEMO_FORMAT_VERSION}" ]; then
        return 1
    fi
    # A recording without these is not replayable: the mode decides the
    # rules of the round, the ending decides what the final box says.
    if [ -z "${DEMO_HDR_MODE}" ] || [ -z "${DEMO_HDR_END}" ] || \
       [ -z "${DEMO_HDR_DATE}" ]; then
        return 1
    fi
    return 0
}

# demo_load FILE
# Read a recording completely: header, piece stream and the event list,
# whose deltas are accumulated into absolute play-time stamps here (the
# playback loop compares them against its clock, so no drift can build up
# over a long demo). Returns 1 on any invalid line - a recording is
# replayed as a whole or not at all.
demo_load() {
    local file="${1}" line key val t=0 body=0
    if ! demo_header_read "${file}"; then
        return 1
    fi
    DEMO_PLAY_PIECES=""
    DEMO_EV_T=()
    DEMO_EV_A=()
    while IFS= read -r line; do
        case "${line}" in
            '#'*|'') continue ;;
        esac
        key="${line%%=*}"
        val="${line#*=}"
        case "${key}" in
            pcs)
                [[ "${val}" =~ ${DEMO_PCS_RE} ]] || return 1
                DEMO_PLAY_PIECES+="${val}"
                body=1
                ;;
            e)
                [[ "${val}" =~ ${DEMO_EVENT_RE} ]] || return 1
                t=$(( t + 10#${BASH_REMATCH[1]} ))
                DEMO_EV_T+=("${t}")
                DEMO_EV_A+=("${BASH_REMATCH[2]}")
                body=1
                ;;
            # The header keys, already validated by demo_header_read -
            # but only where a header belongs. demo_header_read stops at
            # the first stream line, so a header line appended behind the
            # stream would otherwise pass unread: a file that has one is
            # not a recording this game wrote, and is rejected rather
            # than half-read.
            version|game|mode|name|date|time|lines|rows|level|gold| \
            silver|rowhammers|pieces|goal|end)
                [ "${body}" -eq 0 ] || return 1
                ;;
            *) return 1 ;;
        esac
    done < "${file}"
    if [ "${#DEMO_EV_T[@]}" -eq 0 ] || [ -z "${DEMO_PLAY_PIECES}" ]; then
        return 1
    fi
    debug_event "demo: loaded ${file} (${#DEMO_EV_T[@]} events, ${#DEMO_PLAY_PIECES} pieces, ${DEMO_HDR_TIME}ms)"
    return 0
}

# demo_next_piece
# Hand out the next piece of the recorded stream. Called by queue_fill
# (lib/pieces.sh) while a demo is playing. A stream that runs dry cannot
# happen for a recording written by this game (every piece the queue was
# filled with was noted); should it happen for a hand-edited file, the
# replay falls back to the normal bag instead of breaking - it then
# diverges from the original, which the debug log says.
DEMO_NEXT_PIECE=""
demo_next_piece() {
    if [ "${DEMO_PLAY_POS}" -ge "${#DEMO_PLAY_PIECES}" ]; then
        DEMO_NEXT_PIECE=""
        debug_event "demo: piece stream exhausted at ${DEMO_PLAY_POS}, falling back to the bag"
        return 1
    fi
    DEMO_NEXT_PIECE="${DEMO_PLAY_PIECES:DEMO_PLAY_POS:1}"
    DEMO_PLAY_POS=$(( DEMO_PLAY_POS + 1 ))
    return 0
}

# demo_speed_apply
# Take DEMO_SPEED and its label from the current DEMO_SPEED_IDX. Kept in
# globals so neither the playback loop nor the renderer has to index the
# tables themselves.
demo_speed_apply() {
    DEMO_SPEED="${DEMO_SPEEDS[DEMO_SPEED_IDX]}"
    DEMO_SPEED_LABEL="${DEMO_SPEED_LABELS[DEMO_SPEED_IDX]}"
    return 0
}

# demo_apply ACTION
# Apply one recorded event to the game state, through the very functions
# the live round uses - which is what makes a replay show the game rather
# than a picture of it.
demo_apply() {
    case "${1}" in
        l) try_move -1 0 || : ;;
        r) try_move 1 0 || : ;;
        c) try_rotate 1 || : ;;
        a) try_rotate -1 || : ;;
        # Soft drop and gravity are the same movement; they stay two
        # letters so the recording still says which of them it was.
        s) step_down ;;
        g) step_down ;;
        h) hard_drop ;;
        o) hold_piece ;;
        k) lock_and_next ;;
    esac
    return 0
}

# demo_play FILE
# Replay one recording. Runs its own loop instead of game_run: there is no
# input to react to here, the timeline drives everything, and the round
# must not be recorded, banked or ranked (record_round refuses while
# DEMO_PLAYING is set).
# Controls: the pause key toggles the replay (reusing the game's PAUSED
# flag and therefore its box), left/right and -/+ step through
# DEMO_SPEEDS, the quit key or ESC leaves, and "r" restarts the demo once
# it has finished.
# The clock advances by the real time between two loop passes, scaled by
# the speed, and events are applied when it passes their timestamp. The
# row flash inside lock_and_next scales along with it (see flash_rows),
# so the pacing holds at every speed.
demo_play() {
    local file="${1}"
    local idx count last_real delta restart scaled rem
    if ! demo_load "${file}"; then
        menu_message "Demo" \
            "Diese Aufzeichnung ist beschaedigt oder stammt" \
            "aus einer anderen Version und kann nicht" \
            "abgespielt werden." \
            "" \
            "Du kannst sie im Demo-Menue loeschen."
        debug_event "demo: refused to play invalid recording ${file}"
        return 1
    fi
    count="${#DEMO_EV_T[@]}"
    DEMO_SPEED_IDX="${DEMO_SPEED_DEFAULT}"
    demo_speed_apply
    while :; do
        restart=0
        DEMO_PLAYING=1
        DEMO_ENDED=0
        DEMO_PLAY_POS=0
        DEMO_CLOCK_MS=0
        idx=0
        rem=0
        # The ranks of the last real round would otherwise show up in the
        # replayed round's boxes; a demo has no rank of its own.
        HS_LAST_RANK=0
        HSU_LAST_RANK=0
        HSS_LAST_RANK=0
        HSA_LAST_RANK=0
        # Sets up board, bag, counters and the first piece exactly like a
        # live round - only the pieces come from the recorded stream,
        # because DEMO_PLAYING is set (see queue_fill).
        game_reset "${DEMO_HDR_MODE}"
        PAUSED=0
        RENDER_FULL=1
        DIRTY=1
        now_ms
        last_real="${NOW_MS}"
        debug_event "demo: playback started (${file}, mode=${DEMO_HDR_MODE})"
        while :; do
            read_key
            if [ "${REDRAW_PENDING}" -eq 1 ]; then
                REDRAW_PENDING=0
                RENDER_FULL=1
                DIRTY=1
                # The overlay may have blocked for a while; that idle time
                # is not playback time.
                now_ms
                last_real="${NOW_MS}"
            fi
            case "${KEY}" in
                "${KEY_PAUSE}"|SPACE)
                    PAUSED=$(( 1 - PAUSED ))
                    DIRTY=1
                    ;;
                LEFT|-)
                    if [ "${DEMO_SPEED_IDX}" -gt 0 ]; then
                        DEMO_SPEED_IDX=$(( DEMO_SPEED_IDX - 1 ))
                        demo_speed_apply
                        DIRTY=1
                    fi
                    ;;
                RIGHT|+)
                    if [ "${DEMO_SPEED_IDX}" -lt $(( ${#DEMO_SPEEDS[@]} - 1 )) ]; then
                        DEMO_SPEED_IDX=$(( DEMO_SPEED_IDX + 1 ))
                        demo_speed_apply
                        DIRTY=1
                    fi
                    ;;
                "${KEY_QUIT}"|ESC)
                    debug_event "demo: playback left at ${DEMO_CLOCK_MS}ms of ${DEMO_HDR_TIME}ms"
                    DEMO_PLAYING=0
                    DEMO_ENDED=0
                    return 0
                    ;;
                r)
                    if [ "${DEMO_ENDED}" -eq 1 ]; then
                        restart=1
                    fi
                    ;;
            esac
            if [ "${restart}" -eq 1 ]; then
                break
            fi
            # Advance the demo clock by the real time that passed, scaled
            # by the playback speed. Done before the events so a slow loop
            # pass never leaves an event behind.
            now_ms
            delta=$(( NOW_MS - last_real ))
            last_real="${NOW_MS}"
            if [ "${PAUSED}" -eq 0 ] && [ "${DEMO_ENDED}" -eq 0 ]; then
                if [ "${delta}" -gt 0 ]; then
                    # Scaled with a carried remainder instead of a plain
                    # integer division: at 0.25x a short pass would
                    # otherwise round its quarter down to zero every time
                    # and the replay would run slower than it says.
                    scaled=$(( delta * DEMO_SPEED + rem ))
                    DEMO_CLOCK_MS=$(( DEMO_CLOCK_MS + scaled / 100 ))
                    rem=$(( scaled % 100 ))
                fi
                # Everything due by now, in order. A single pass may cover
                # several events (a burst of inputs, or a slow terminal).
                # Each of them marks the screen dirty, exactly like the
                # live game does: the loop runs at the input tick rate,
                # and rebuilding a frame 50 times a second for a HUD that
                # did not change would cost more than the round itself.
                while [ "${idx}" -lt "${count}" ] && \
                      [ "${DEMO_EV_T[idx]}" -le "${DEMO_CLOCK_MS}" ]; do
                    demo_apply "${DEMO_EV_A[idx]}"
                    idx=$(( idx + 1 ))
                    DIRTY=1
                done
                # The HUD reads PLAY_MS; feeding it the demo clock makes
                # the time counter (and the Sprint countdown) run like it
                # did in the recorded round.
                PLAY_MS="${DEMO_CLOCK_MS}"
                if [ "${PLAY_MS}" -gt "${DEMO_HDR_TIME}" ]; then
                    PLAY_MS="${DEMO_HDR_TIME}"
                fi
                # The recording ends when its last event has been applied
                # and its play time is up - the tail after the last action
                # belongs to the round as much as the rest.
                if [ "${idx}" -ge "${count}" ] && \
                   [ "${DEMO_CLOCK_MS}" -ge "${DEMO_HDR_TIME}" ]; then
                    DEMO_ENDED=1
                    DIRTY=1
                    debug_event "demo: playback finished (${DEMO_HDR_TIME}ms, rows=${ROW_CREDIT})"
                fi
            fi
            if [ "${DIRTY}" -eq 1 ]; then
                draw_frame
                DIRTY=0
            fi
        done
        debug_event "demo: playback restarted"
    done
}

# demo_scan
# Fill DEMO_LIST_FILE/DEMO_LIST_LABEL with the recordings on disk, newest
# first. The label is one menu line: date, mode, play time and the rows
# scored - the three things that tell two rounds apart - led by a "*"
# when the recording still backs a highscore entry and is therefore kept
# regardless of DEMO_MAX (see demo_prune). A file whose
# header does not validate is listed as defective instead of hidden, so
# it can still be deleted from the menu.
demo_scan() {
    local -a files
    local i f label mode_label mark
    DEMO_LIST_FILE=()
    DEMO_LIST_LABEL=()
    DEMO_LIST_MARKED=()
    DEMO_LIST_KEPT=0
    demo_dir
    if [ ! -d "${DEMO_DIR}" ]; then
        return 0
    fi
    files=("${DEMO_DIR}"/*"${DEMO_FILE_EXT}")
    if [ ! -e "${files[0]}" ]; then
        return 0
    fi
    # Which recordings are protected is read fresh here rather than kept
    # around: a round played in between changes the lists.
    highscore_hash_set
    # Names start with the date, so the glob is oldest first; walk it
    # backwards for a newest-first list.
    for (( i = ${#files[@]} - 1; i >= 0; i-- )); do
        f="${files[i]}"
        if demo_protected "${f}"; then
            mark="*"
            DEMO_LIST_KEPT=$(( DEMO_LIST_KEPT + 1 ))
        else
            mark=" "
        fi
        if ! demo_header_read "${f}"; then
            printf -v label '%s%-16s %s' "${mark}" "(defekt)" "${f##*/}"
            DEMO_LIST_FILE+=("${f}")
            DEMO_LIST_LABEL+=("${label:0:43}")
            DEMO_LIST_MARKED+=("${mark}")
            continue
        fi
        # Eight columns for the mode, which is what the label format
        # below leaves it; "TimeAtk" is the Time Attack mode shortened to
        # fit, the way the list has to shorten it anyway.
        case "${DEMO_HDR_MODE}" in
            ultra)      mode_label="Ultra" ;;
            sprint)     mode_label="Sprint" ;;
            timeattack) mode_label="TimeAtk" ;;
            *)          mode_label="Marathon" ;;
        esac
        fmt_duration $(( DEMO_HDR_TIME / 1000 ))
        # 1 + 16 + 1 + 8 + 1 + 5 + 1 + 5 + 5 = 43 characters, which the
        # menu's three-column indent leaves room for in the 48-column
        # minimum (see menu_run in lib/menu.sh).
        printf -v label '%s%s %-8s %s %5d Rows' \
            "${mark}" "${DEMO_HDR_DATE}" "${mode_label}" "${FMT_DURATION}" \
            "${DEMO_HDR_ROWS}"
        DEMO_LIST_FILE+=("${f}")
        DEMO_LIST_LABEL+=("${label}")
        DEMO_LIST_MARKED+=("${mark}")
    done
    return 0
}

# demo_delete FILE
# Remove one recording. Unlike --reset (which moves files aside, see
# reset_run in rowhammer.sh) this really deletes: it is a single entry
# picked from a list and confirmed right before, not a sweeping reset
# that could take a player by surprise, and the list is capped anyway -
# every recording here is going to be pruned sooner or later.
demo_delete() {
    local file="${1}"
    if rm -f -- "${file}"; then
        debug_event "demo: deleted ${file}"
        return 0
    fi
    debug_event "demo: could not delete ${file}"
    return 1
}
