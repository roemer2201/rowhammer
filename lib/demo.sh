#!/usr/bin/env bash
#
# lib/demo.sh
#
# Description:
#   Demo recording and playback for rowhammer. A round is recorded as the
#   sequence of things that happened to it - the player's actions, the
#   gravity steps, the lock-delay locks, the flood rows of the Hochwasser
#   mode and the piece stream the round was
#   dealt - not as a picture of the screen. Replaying feeds that sequence
#   back into the real game functions (try_move, try_rotate, step_down,
#   hard_drop, hold_piece, lock_and_next, flood_raise), so a demo shows
#   what the game really did rather than what a terminal once printed.
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
#   Multiplayer. A versus round is recorded the same way, only for
#   everybody at once: every participant gets a stream of their own
#   ("p=<slot> <delta><action>"), fed from this player's own keys and
#   from the moves the hub passes on (PEERACT, protocol 4). That is what
#   makes the recording a recording of the party rather than of one seat
#   in it - the playback can put any of them in the middle and simulate
#   all of them (CLAUDE.md 5.20). Three things only the hub knows go into
#   the streams as well, because no move produces them: incoming garbage,
#   the authoritative queue length and an elimination. Beside them the
#   file carries checkpoints ("v=<slot> ..."): the counters the hub
#   reported for a player, so a replay can tell whether its simulation
#   still agrees with the round it is replaying.
#
#   Timing. Every event carries the round's play time (PLAY_MS, pauses
#   excluded) as a delta to the event before it - in a versus round the
#   round clock instead (mp_round_ms), the one clock all participants
#   share: they all hang off the same countdown, and a multiplayer round
#   has no pause that could stop it (CLAUDE.md 5.8/5.20). Playback runs
#   its own clock over that timeline, so the replay is paced exactly
#   like the round was, can be slowed down or sped up (DEMO_SPEEDS) and
#   can be paused - and no drift can accumulate, because the clock is
#   compared against absolute timestamps rather than slept through per
#   event.
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
#   Failing writes. The free space of neither directory is measured up
#   front - a check would be a snapshot of a directory shared with every
#   other program on the machine, while the write itself is the
#   authoritative answer. Every write is checked instead, and a failing
#   one drops the recording with a note in the debug log while the round
#   plays on: a recording that cannot be made is never a reason to spoil
#   someone's game. Nothing of this module writes to STDERR either, since
#   the game owns the terminal (see demo_record_start).
#
#   The file is parsed and validated line by line, never sourced: it is
#   plain data, and a corrupted or hand-edited file must be rejected
#   rather than executed. Every field has its own pattern.
#
#   Round hash. A recording carries the hash of the round it holds in its
#   file name (round_hash in rowhammer.sh), the same one the round's
#   highscore entry stores as its last field. Both directions of that
#   link are read off the file name alone, without opening a single
#   recording: demo_protected asks whether a recording still backs a
#   highscore entry and must be kept (demo_prune), demo_hash_map answers
#   the opposite question for the highscore screens - which entry still
#   has a recording to watch (highscore_browse, lib/highscore.sh).
#
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.4.1  (2026-08-11)

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
# Version 2 (0.49.0) added the flood event of the Hochwasser mode to the
# alphabet. A version 1 recording would in fact still replay - the events
# it does carry mean exactly what they always did - but the rule is the
# rule, and a reader that has to decide which older versions are close
# enough is exactly what this single number exists to avoid.
# Version 3 (step 9.6) added the multiplayer: the session block of the
# header, one event stream per participant and the checkpoints of what
# the hub reported about them.
DEMO_FORMAT_VERSION=3
# The oldest version still read. Version 2 is the one deliberate
# exception to "no backward compatibility" in this format (CLAUDE.md
# 5.20/6, user decision), and it costs nothing: a singleplayer recording
# of version 3 is written exactly as version 2 was - the whole
# multiplayer section only exists in a versus recording - so a version 2
# file is a version 3 file that could not have had one. Throwing away the
# recordings the highscore entries hang off for a section they never
# could have carried would be a loss without a gain.
DEMO_FORMAT_MIN_VERSION=2

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
DEMO_MODE_RE='^(marathon|ultra|sprint|timeattack|flood|versus)$'
DEMO_DATE_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$'
DEMO_PCS_RE='^[IOTSZJL]{1,80}$'
# One event: the play-time delta in milliseconds since the previous event
# followed by the action letter. The alphabet, deliberately one letter per
# thing that can happen to a round:
#   l/r  move left / right          c/a  rotate clockwise / counter-cw
#   s    soft drop                  h    hard drop (locks the piece)
#   o    hold / swap                g    gravity step
#   k    lock delay expired (the piece locks where it rests)
#   wN   a flood row rose, with the gap in column N (Hochwasser mode)
# A hard drop locks by itself, so it is never followed by a "k"; a piece
# leaving the board through a blocked spawn needs no event either, since
# the replay reaches that spawn on its own.
# The flood event is the only one carrying a payload, and it has to: the
# rise itself follows the clock and the replay could compute it, but the
# gap column is drawn from RANDOM, and a replay that guessed it would
# play a different round from the one recorded.
DEMO_EVENT_RE='^([0-9]{1,7})([lrcashogk]|w[0-9])$'
# A versus recording spells its events "p=<slot> <delta><action>" instead,
# one line per event and the delta counted against the previous event of
# that same slot: the moves of an opponent arrive with the network's
# delay and can be older than the last line written, while each single
# stream stays in order, so five cursors are all a replay needs
# (CLAUDE.md 5.20). Four letters come on top of the alphabet above, all
# of them things no move produces and only the hub knows:
#   y<nn><h>  <nn> garbage rows arrived, their gap in column <h>
#   q<nn>     the hub's authoritative length of that player's queue
#   n<n>      knocked out, taking place <n>
#   z<n>      lost the connection, taking place <n>
# Their payloads are fixed width because the tokens of the move stream
# are written back to back (PROTO_ACT_RE): a digit count that varied
# could not be told from the next token's delta. "w<column>" stays with
# the Hochwasser mode, which is a singleplayer mode and cannot occur here.
# The counters the hub reported for a player go into the file as their
# own line, "v=<slot> <lines> <rows> <level> <gold> <silver> <height>",
# and they are positional: a checkpoint holds for the moment that slot's
# stream has reached the last event written before it. That is the reason
# it carries no timestamp of its own - it is not a thing that happened,
# it is a statement about the stream around it.
DEMO_END_RE='^(over|goal|quit|lost)$'
# The two header fields of a versus recording that are not plain numbers:
# what the session was set to (the hub's own list of modes, CLAUDE.md
# 5.1) and one participant, "<slot> <name>". The name pattern is the
# protocol's, not DEMO_NAME_RE: these names came off the wire and were
# validated there, and the space DEMO_NAME_RE allows would swallow the
# field separator.
DEMO_MPMODE_RE='^(survival|sprint|ultra)$'
DEMO_PEER_RE='^[0-9] [A-Za-z0-9_-]{1,16}$'

# --- Recording state ------------------------------------------------------
# Whether the running round is being recorded, the RAM disk file it is
# written to, the buffered event lines, the piece letters the round was
# dealt so far and the play time the last event was stamped with.
DEMO_RECORDING=0
DEMO_TMP_FILE=""
DEMO_BUF=()
DEMO_PIECES=""
DEMO_LAST_MS=0

# --- Multiplayer recording state ------------------------------------------
# Only a versus round fills any of this. DEMO_MP says whether the running
# recording holds a session at all - it is what routes an event into a
# slot's stream instead of the single one - and DEMO_MP_SLOT is the seat
# this player sat in.
DEMO_MP=0
DEMO_MP_SLOT=0
# Per slot: the round time of that slot's last recorded event (the deltas
# are counted against it), the counters of the checkpoint waiting to be
# written, when the last checkpoint for that slot was written, and the
# place of an elimination whose kind is not settled yet (see
# demo_record_ko).
DEMO_SLOT_LAST_MS=()
DEMO_V_PEND=()
DEMO_V_LAST_MS=()
DEMO_KO_PEND=()
# End of the recorded timeline, taken when the round ended rather than
# when the recording is closed: between the two lies the name prompt, and
# the round clock does not stop for it (demo_mark_end).
DEMO_END_MS=0
# How far apart two checkpoints of the same slot are at the closest, in
# milliseconds of that slot's stream. A checkpoint is a cross-check and
# nothing else, so one a second is plenty - the counters change with
# every lock (the stack height does), and writing one per reported change
# would multiply the size of a five player recording for no gain.
DEMO_V_MS=1000

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
    local mode="${1}" i
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
    # A mode this format does not know is not recorded: a file saying
    # "marathon" over a round that was nothing of the sort would be worse
    # than no file at all - it would replay as a round with garbage rows
    # appearing out of nowhere. Since format 3 (step 9.6) the versus mode
    # is one this format does know.
    if ! [[ "${mode}" =~ ${DEMO_MODE_RE} ]]; then
        debug_event "demo: mode '${mode}' is not recordable, round is not recorded"
        return 0
    fi
    if ! demo_tmp_base; then
        debug_event "demo: no writable temp directory, round is not recorded"
        return 0
    fi
    # STDERR is discarded for every write of this module: the game owns
    # the terminal (alternate screen, own cursor positioning), and a
    # message from mktemp or printf would be painted into the middle of
    # the playfield. In the default render mode only changed lines are
    # rewritten (see render_flush), so such a line would stay on screen
    # until something forces a full redraw. The failure itself is not
    # swallowed - it is caught below and noted in the debug log, which is
    # where a diagnosis belongs in a full screen program.
    if ! DEMO_TMP_FILE="$(mktemp -- "${DEMO_TMP_BASE}/rowhammer-demo.XXXXXX" 2>/dev/null)"; then
        DEMO_TMP_FILE=""
        debug_event "demo: could not create a temp file below ${DEMO_TMP_BASE}, round is not recorded"
        return 0
    fi
    DEMO_RECORDING=1
    DEMO_BUF=()
    DEMO_PIECES=""
    DEMO_LAST_MS=0
    DEMO_END_MS=0
    # A versus round records everybody, so it needs a stream per seat and
    # the seat this player is in. Without a slot there is nothing to
    # record into - which cannot happen (the hub hands one out before the
    # round starts) but must not end up writing into index -1 if it ever
    # does.
    DEMO_MP=0
    if [ "${mode}" = "versus" ]; then
        if [ "${MP_SLOT}" -lt 0 ] || [ "${MP_SLOT}" -ge "${MP_MAX}" ]; then
            debug_event "demo: no slot in this session, round is not recorded"
            demo_record_discard
            return 0
        fi
        DEMO_MP=1
        DEMO_MP_SLOT="${MP_SLOT}"
        for (( i = 0; i < MP_MAX; i++ )); do
            DEMO_SLOT_LAST_MS[i]=0
            DEMO_V_PEND[i]=""
            DEMO_V_LAST_MS[i]=0
            DEMO_KO_PEND[i]=""
        done
        debug_event "demo: recording a versus round as slot ${DEMO_MP_SLOT} (mode=${MP_MODE} garbage=${MP_GARBAGE})"
    fi
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

# demo_stamp
# The clock this recording runs on, into DEMO_STAMP_MS. A versus round
# uses the round clock: it is the one clock every participant shares, and
# a stream fed from several of them can only be laid out on a clock they
# all agree on (CLAUDE.md 5.20). Everywhere else it is the play clock,
# computed the way play_clock_tick would compute it but without writing
# it back - recording must never change how the round plays, and PLAY_MS
# is what the Sprint mode and the HUD read. Only NOW_MS is refreshed,
# which every caller in the game loop re-reads anyway.
DEMO_STAMP_MS=0
demo_stamp() {
    if [ "${DEMO_MP}" -eq 1 ]; then
        mp_round_ms
        DEMO_STAMP_MS="${MP_ROUND_MS}"
        return 0
    fi
    now_ms
    DEMO_STAMP_MS=$(( PLAY_MS + NOW_MS - PLAY_LAST ))
    return 0
}

# demo_buf_full
# Write the buffer out once it has grown to DEMO_FLUSH_MAX lines. Its own
# helper because four places append to the buffer now.
demo_buf_full() {
    if [ "${#DEMO_BUF[@]}" -ge "${DEMO_FLUSH_MAX}" ]; then
        demo_flush
    fi
    return 0
}

# demo_slot_event SLOT T ACTION
# Append one event to a slot's stream, T being the round time it happened
# at. The delta is counted against that slot's own last event, which is
# what lets the streams of five players share one file in arrival order.
# Everything that keeps the deltas non-negative works on that per-slot
# clock: an event stamped earlier than the slot's last one lands on it
# rather than going backwards. That is the ordinary case for the three
# things the hub sends (garbage, queue, elimination): they are stamped
# when they arrive here, while a peer's moves reach us up to one send
# window (MP_ACT_MS) later than they happened. The stream is off by at
# most that window for the one token after such an event and back in step
# afterwards - and the effects themselves are queued rather than applied,
# so what they do to a board does not move at all.
demo_slot_event() {
    local slot="${1}" t="${2}" action="${3}" delta
    delta=$(( t - DEMO_SLOT_LAST_MS[slot] ))
    if [ "${delta}" -lt 0 ]; then
        delta=0
    fi
    # Seven digits is what the event pattern allows; a gap that long
    # cannot arise in a round, but a clamp here keeps this end from ever
    # writing a line its own reader would reject.
    if [ "${delta}" -gt 9999999 ]; then
        delta=9999999
    fi
    # Advanced by the delta actually written, not to T: after a clamp the
    # two differ, and the file is the truth the replay follows.
    DEMO_SLOT_LAST_MS[slot]=$(( DEMO_SLOT_LAST_MS[slot] + delta ))
    DEMO_BUF+=("p=${slot} ${delta}${action}")
    demo_buf_full
    return 0
}

# demo_record_event ACTION
# One thing this player did, appended to the recording. In a versus round
# it goes into this player's own stream, everywhere else into the single
# one. Not called while the round is paused (the game loop and handle_key
# skip everything that could record then), so the stale PLAY_LAST of a
# pause can never leak into a delta.
demo_record_event() {
    local delta
    if [ "${DEMO_RECORDING}" -eq 0 ]; then
        return 0
    fi
    demo_stamp
    if [ "${DEMO_MP}" -eq 1 ]; then
        demo_slot_event "${DEMO_MP_SLOT}" "${DEMO_STAMP_MS}" "${1}"
        demo_own_checkpoint
        return 0
    fi
    delta=$(( DEMO_STAMP_MS - DEMO_LAST_MS ))
    # A clock that jumped backwards (NTP step) must not write a negative
    # delta into the file; the event then simply lands on the previous
    # event's timestamp.
    if [ "${delta}" -lt 0 ]; then
        delta=0
    fi
    DEMO_LAST_MS="${DEMO_STAMP_MS}"
    DEMO_BUF+=("e=${delta}${1}")
    demo_buf_full
    return 0
}

# demo_mark_end
# Where the recorded timeline ends. Called by record_round (rowhammer.sh)
# before it does anything else, because "anything else" includes asking
# for the player's name - and the round clock of a versus recording keeps
# running while somebody types. A singleplayer recording does not need
# the mark (its timeline ends at PLAY_MS, which is final by then) but
# takes it all the same: one moment, one meaning.
demo_mark_end() {
    if [ "${DEMO_RECORDING}" -eq 0 ]; then
        return 0
    fi
    demo_stamp
    DEMO_END_MS="${DEMO_STAMP_MS}"
    return 0
}

# --- The other players ----------------------------------------------------
# Everything below is fed from lib/mp.sh and does nothing unless a versus
# round is being recorded. The guard is repeated in each of them rather
# than asked at the call sites: a recording that is not running must not
# be something the message handlers have to think about.

# demo_slot_ok SLOT
# True for a seat this session actually has. The hub is not trusted
# either (CLAUDE.md 5.5) and the protocol's slot field is a single digit,
# which is wider than any session: a number past the last seat would grow
# the per-slot tables and write a player into the file who never sat
# down. Asked at the entry points below rather than in demo_slot_event,
# so every value coming from outside is checked where it comes in.
demo_slot_ok() {
    [ "${1}" -ge 0 ] && [ "${1}" -lt "${MP_MAX}" ]
}

# demo_record_peer_act SLOT T TOKENS
# The moves of another player, as they arrived (PEERACT): T is the round
# time the first delta counts from, the tokens are "<delta><action>" back
# to back. They are taken apart here and written as that slot's own
# events, so the file holds one kind of stream for everybody and the
# reader never has to know which of them came off the wire.
# The tokens have been through the protocol parser already; they are
# taken apart again with a pattern of their own all the same - a stream
# that does not match stops being read instead of putting a letter the
# alphabet does not have into the file.
demo_record_peer_act() {
    local slot="${1}" t="${2}" rest="${3}"
    [ "${DEMO_RECORDING}" -eq 1 ] || return 0
    [ "${DEMO_MP}" -eq 1 ] || return 0
    demo_slot_ok "${slot}" || return 0
    [ "${slot}" -ne "${DEMO_MP_SLOT}" ] || return 0
    while [ -n "${rest}" ]; do
        [[ "${rest}" =~ ^([0-9]{1,6})([acghklors])(.*)$ ]] || break
        t=$(( t + 10#${BASH_REMATCH[1]} ))
        demo_slot_event "${slot}" "${t}" "${BASH_REMATCH[2]}"
        rest="${BASH_REMATCH[3]}"
    done
    # A checkpoint waiting for this slot goes out behind the moves it
    # describes; see demo_record_peer_state for why it waits at all.
    demo_checkpoint_flush "${slot}"
    return 0
}

# demo_record_peer_state SLOT LINES ROWS LEVEL GOLD SILVER HEIGHT
# The counters the hub reported for another player (PEER). They are not
# written straight away but kept until that slot's next moves have been
# written (demo_record_peer_act). The reason is the order the two leave
# the player they describe: their game loop sends its counters at the end
# of the tick and flushes its move window afterwards, so the counters can
# be up to one window ahead of the moves that produced them. A checkpoint
# placed there would accuse a correct replay of having diverged.
# Only the latest is kept - a checkpoint is a cross-check, and the newest
# one is the only interesting one.
demo_record_peer_state() {
    local slot="${1}"
    [ "${DEMO_RECORDING}" -eq 1 ] || return 0
    [ "${DEMO_MP}" -eq 1 ] || return 0
    demo_slot_ok "${slot}" || return 0
    [ "${slot}" -ne "${DEMO_MP_SLOT}" ] || return 0
    DEMO_V_PEND[slot]="${2} ${3} ${4} ${5} ${6} ${7}"
    return 0
}

# demo_checkpoint_flush SLOT
# Write the checkpoint waiting for a slot, at most every DEMO_V_MS of
# that slot's stream. Measured on the stream rather than on the clock, so
# the spacing means the same thing when the file is read as when it was
# written.
demo_checkpoint_flush() {
    local slot="${1}"
    [ -n "${DEMO_V_PEND[slot]}" ] || return 0
    (( DEMO_SLOT_LAST_MS[slot] - DEMO_V_LAST_MS[slot] >= DEMO_V_MS )) || return 0
    DEMO_V_LAST_MS[slot]="${DEMO_SLOT_LAST_MS[slot]}"
    DEMO_BUF+=("v=${slot} ${DEMO_V_PEND[slot]}")
    DEMO_V_PEND[slot]=""
    demo_buf_full
    return 0
}

# demo_own_checkpoint
# The same cross-check for this player's own seat, taken from the live
# counters right behind the event that changed them. Worth having even
# though nothing came over the network for it: our own stream and our own
# counters were produced by the same process, so a replay that disagrees
# with them is a replay that got the game wrong - which is exactly what
# these checkpoints are for.
demo_own_checkpoint() {
    local slot="${DEMO_MP_SLOT}"
    (( DEMO_SLOT_LAST_MS[slot] - DEMO_V_LAST_MS[slot] >= DEMO_V_MS )) || return 0
    DEMO_V_LAST_MS[slot]="${DEMO_SLOT_LAST_MS[slot]}"
    proto_stack_height
    DEMO_BUF+=("v=${slot} ${CLEARED_TOTAL} ${ROW_CREDIT} ${LEVEL} ${GOLD_COUNT} ${SILVER_COUNT} ${PROTO_HEIGHT}")
    demo_buf_full
    return 0
}

# demo_record_garbage SLOT COUNT HOLE
# Garbage rows on their way to a player, exactly as the hub announced
# them - for every slot, not only for our own: the recording follows
# every board, and this is the one thing that happens to a board without
# a move behind it. The rows are noted where they arrive, not where they
# are pushed in; when that is depends on the player's next lock, which
# the replay works out for itself.
# Both numbers are clamped into the width of the token. The hub caps an
# attack at ten rows and the gap is a column, so neither clamp can bite
# on anything this game sends; they are there because the hub is not
# something this end gets to trust (CLAUDE.md 5.5).
demo_record_garbage() {
    local slot="${1}" count="${2}" hole="${3}" token
    [ "${DEMO_RECORDING}" -eq 1 ] || return 0
    [ "${DEMO_MP}" -eq 1 ] || return 0
    demo_slot_ok "${slot}" || return 0
    [ "${count}" -ge 1 ] || return 0
    [ "${count}" -le 99 ] || count=99
    [ "${hole}" -le 9 ] || hole=9
    printf -v token 'y%02d%d' "${count}" "${hole}"
    demo_stamp
    demo_slot_event "${slot}" "${DEMO_STAMP_MS}" "${token}"
    return 0
}

# demo_record_queue SLOT COUNT
# What the hub says is left of a player's queue after a clear of theirs
# cancelled part of it. The authoritative number, which is why it is
# recorded at all: a replay that added the garbage up itself would drift
# away from the round the moment the first attack was cancelled.
demo_record_queue() {
    local slot="${1}" count="${2}" token
    [ "${DEMO_RECORDING}" -eq 1 ] || return 0
    [ "${DEMO_MP}" -eq 1 ] || return 0
    demo_slot_ok "${slot}" || return 0
    [ "${count}" -le 99 ] || count=99
    printf -v token 'q%02d' "${count}"
    demo_stamp
    demo_slot_event "${slot}" "${DEMO_STAMP_MS}" "${token}"
    return 0
}

# demo_record_ko SLOT PLACE
# A player is out of the round, with the place they took. Not written
# yet: the hub's KO says the same thing for somebody who topped out and
# for somebody whose connection died, and the recording tells the two
# apart ("n" and "z"). Which it was follows in the roster a moment later,
# and demo_record_peer_status writes the event then - or, if the round
# ends before any roster arrives, demo_ko_flush does.
demo_record_ko() {
    local slot="${1}" place="${2}"
    [ "${DEMO_RECORDING}" -eq 1 ] || return 0
    [ "${DEMO_MP}" -eq 1 ] || return 0
    demo_slot_ok "${slot}" || return 0
    [ -z "${DEMO_KO_PEND[slot]}" ] || return 0
    [ "${place}" -le 9 ] || place=9
    DEMO_KO_PEND[slot]="${place}"
    return 0
}

# demo_record_peer_status SLOT STATE
# What the roster says a player is doing. Only one thing is taken from
# it: it settles an elimination that is waiting for its kind.
demo_record_peer_status() {
    local slot="${1}" state="${2}"
    [ "${DEMO_RECORDING}" -eq 1 ] || return 0
    [ "${DEMO_MP}" -eq 1 ] || return 0
    demo_slot_ok "${slot}" || return 0
    [ -n "${DEMO_KO_PEND[slot]}" ] || return 0
    demo_stamp
    case "${state}" in
        ko)   demo_ko_write "${slot}" "n" "${DEMO_STAMP_MS}" ;;
        gone) demo_ko_write "${slot}" "z" "${DEMO_STAMP_MS}" ;;
    esac
    return 0
}

# demo_ko_write SLOT LETTER T
# Write the elimination that was waiting for this slot, at round time T.
demo_ko_write() {
    local slot="${1}"
    demo_slot_event "${slot}" "${3}" "${2}${DEMO_KO_PEND[slot]}"
    DEMO_KO_PEND[slot]=""
    return 0
}

# demo_ko_flush
# Settle every elimination still waiting when the recording is closed. A
# round that ended on the knock-out deciding it is the ordinary case
# here: the hub sends its ROSTER on the pass after the KO, and this
# client is already closing its books by then. They are written as
# knock-outs, which is what an elimination is unless a roster said
# otherwise - and a player whose connection died has left a trail the
# round itself does not need this event to show.
# Stamped with the end of the timeline (demo_mark_end) rather than with
# "now": this runs after the name prompt, and a person typing must not
# push an event of the round past the length the file says it had.
demo_ko_flush() {
    local i
    [ "${DEMO_RECORDING}" -eq 1 ] || return 0
    [ "${DEMO_MP}" -eq 1 ] || return 0
    for (( i = 0; i < MP_MAX; i++ )); do
        [ -n "${DEMO_KO_PEND[i]}" ] || continue
        demo_ko_write "${i}" "n" "${DEMO_END_MS}"
    done
    return 0
}

# demo_flush
# Write the buffered events to the RAM disk file. A failing write ends
# the recording instead of the round: the game keeps running, the demo is
# dropped with a note in the debug log. This is where a RAM disk running
# out of space is caught - bash's printf reports a write error and
# returns non-zero on ENOSPC. The free space is deliberately not measured
# beforehand: a check would only be a snapshot of a directory shared with
# every other program on the machine, while the write itself is the
# authoritative answer, and a round costs about 2 kB per minute anyway.
# Its STDERR is discarded for the reason given in demo_record_start.
demo_flush() {
    if [ "${DEMO_RECORDING}" -eq 0 ] || [ "${#DEMO_BUF[@]}" -eq 0 ]; then
        return 0
    fi
    if ! printf '%s\n' "${DEMO_BUF[@]}" >> "${DEMO_TMP_FILE}" 2>/dev/null; then
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
    # A failing rm reports into the debug log and nothing else: the game
    # runs under "set -e", so an unchecked rm would take the whole round
    # down over a leftover temp file, and its message would land on the
    # playfield (see demo_record_start).
    if [ -n "${DEMO_TMP_FILE}" ] && ! rm -f -- "${DEMO_TMP_FILE}" 2>/dev/null; then
        debug_event "demo: could not remove ${DEMO_TMP_FILE}"
    fi
    DEMO_RECORDING=0
    DEMO_TMP_FILE=""
    DEMO_BUF=()
    DEMO_PIECES=""
    DEMO_LAST_MS=0
    DEMO_END_MS=0
    # Back to a singleplayer recording: the per-slot tables belong to the
    # session that is over, and leaving the flag set would route the next
    # round's events into a stream nobody asked for.
    DEMO_MP=0
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
    local end="${1}" hash="${2:--}" name path tmp i suffix written players=0
    local -a lines
    if [ "${DEMO_RECORDING}" -eq 0 ]; then
        return 0
    fi
    # Before the buffer goes out for the last time: an elimination still
    # waiting for the roster that would have named its kind is written
    # now, or it is lost with the buffer.
    demo_ko_flush
    demo_flush || return 0
    if [ ! -s "${DEMO_TMP_FILE}" ]; then
        debug_event "demo: round had no events, recording dropped"
        demo_record_discard
        return 0
    fi
    demo_dir
    if ! mkdir -p -- "${DEMO_DIR}" 2>/dev/null; then
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
    if ! tmp="$(mktemp -- "${DEMO_DIR}/.demo.XXXXXX" 2>/dev/null)"; then
        debug_event "demo: could not create a temp file in ${DEMO_DIR}, recording dropped"
        demo_record_discard
        return 0
    fi
    # Header and piece stream, assembled as lines before anything is
    # written: that way the whole recording leaves the process in exactly
    # two write commands, both of which can be checked (see below).
    lines=(
        '# rowhammer demo recording. Parsed and validated on load, never sourced.'
        '# pcs = the piece stream, e = <play time delta in ms><action>,'
        '# p = <slot> <round time delta in ms><action>, v = a counter checkpoint.'
        "version=${DEMO_FORMAT_VERSION}"
        "game=${ROWHAMMER_VERSION}"
        "mode=${GAME_MODE}"
        "name=${PLAYER_NAME}"
        "date=$(date '+%Y-%m-%d %H:%M')"
        "time=${PLAY_MS}"
    )
    # The session block, and only in a versus recording - which is what
    # keeps a singleplayer recording of this version exactly what it was
    # in version 2 (see DEMO_FORMAT_MIN_VERSION).
    # "time" stays this player's own play time, the number the HUD showed
    # and the statistics take; "length" is how long the round went on,
    # which is a different thing the moment somebody tops out early and
    # watches the rest of it.
    if [ "${DEMO_MP}" -eq 1 ]; then
        lines+=("length=${DEMO_END_MS}")
    fi
    lines+=(
        "lines=${CLEARED_TOTAL}"
        "rows=${ROW_CREDIT}"
        "level=${LEVEL}"
        "gold=${GOLD_COUNT}"
        "silver=${SILVER_COUNT}"
        "rowhammers=${ROWHAMMER_COUNT}"
        "pieces=${PIECE_COUNT}"
        "goal=${GOAL_REACHED}"
        "end=${end}"
    )
    if [ "${DEMO_MP}" -eq 1 ]; then
        for (( i = 0; i < MP_MAX; i++ )); do
            [ -n "${MP_PEER_NAME[i]}" ] || continue
            players=$(( players + 1 ))
        done
        lines+=(
            "players=${players}"
            "slot=${DEMO_MP_SLOT}"
            "mpmode=${MP_MODE}"
            "garbage=${MP_GARBAGE}"
        )
        # Only when there is one: a round this client left before the hub
        # called it has no winner, and a number standing in for "none"
        # would be a number somebody reads as a slot.
        if [ "${MP_WINNER}" -ge 0 ]; then
            lines+=("winner=${MP_WINNER}")
        fi
        # One line per seat, this player's own included: the replay puts
        # a name over every board it draws, and the "name" field above
        # only says who was sitting in front of this screen.
        for (( i = 0; i < MP_MAX; i++ )); do
            [ -n "${MP_PEER_NAME[i]}" ] || continue
            lines+=("peer=${i} ${MP_PEER_NAME[i]}")
        done
    fi
    # The stream is cut into lines of at most 80 letters so no line of
    # the file grows unbounded (DEMO_PCS_RE caps it at that length).
    for (( i = 0; i < ${#DEMO_PIECES}; i += 80 )); do
        lines+=("pcs=${DEMO_PIECES:i:80}")
    done
    # Written into a temp file and moved into place, so a crash can never
    # leave a half-written recording. Both writes are checked through the
    # "written" flag instead of through the exit status of the group:
    # that status is the last command's alone, and it must not be the
    # only thing decided on. A data directory running out of space while
    # the header goes out would leave a truncated file, and moving that
    # into place would cost one of the DEMO_MAX slots and push out an
    # intact recording - demo_load rejects it, but only when someone
    # tries to watch it. Errexit is no help here either: bash suspends it
    # inside a command that is part of an if condition, and re-arming it
    # in a subshell there does not work. STDERR goes nowhere for the
    # reason given in demo_record_start.
    written=1
    {
        printf '%s\n' "${lines[@]}" || written=0
        cat -- "${DEMO_TMP_FILE}" || written=0
    } > "${tmp}" 2>/dev/null
    if [ "${written}" -ne 1 ]; then
        # "|| :" for the reason given in demo_record_discard: under
        # "set -e" a failing cleanup must not end the round.
        rm -f -- "${tmp}" 2>/dev/null || :
        debug_event "demo: could not write ${tmp} (out of space?), recording dropped"
        demo_record_discard
        return 0
    fi
    if ! mv -f -- "${tmp}" "${path}" 2>/dev/null; then
        rm -f -- "${tmp}" 2>/dev/null || :
        debug_event "demo: could not move the recording to ${path}, dropped"
        demo_record_discard
        return 0
    fi
    if [ "${DEMO_MP}" -eq 1 ]; then
        debug_event "demo: recording saved to ${path} (end=${end} time=${PLAY_MS}ms length=${DEMO_END_MS}ms rows=${ROW_CREDIT} pieces=${#DEMO_PIECES} players=${players} slot=${DEMO_MP_SLOT} winner=${MP_WINNER})"
    else
        debug_event "demo: recording saved to ${path} (end=${end} time=${PLAY_MS}ms rows=${ROW_CREDIT} pieces=${#DEMO_PIECES})"
    fi
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

# demo_hash_map
# Fill the associative array DEMO_HASH_FILE with one entry per recording
# that carries a round hash in its name: the hash is the key, the file
# path the value. It is the mirror image of highscore_hash_set
# (lib/highscore.sh) - that one asks "does this recording still back a
# highscore entry", this one asks "does this highscore entry still have
# a recording", which is what the list browser needs to mark an entry and
# to play it (highscore_browse). Reading the hash off the file name means
# the whole map costs one glob and no file read at all, so a highscore
# screen can rebuild it every time it is opened instead of caching a
# state that a round played in between would invalidate.
# Two recordings sharing a hash cannot happen in practice (the round's
# play time in milliseconds goes into it, see round_hash in
# rowhammer.sh); should it ever happen, the newer file wins, because the
# glob is sorted oldest first.
declare -A DEMO_HASH_FILE=()
demo_hash_map() {
    local -a files
    local i
    DEMO_HASH_FILE=()
    demo_dir
    if [ ! -d "${DEMO_DIR}" ]; then
        return 0
    fi
    files=("${DEMO_DIR}"/*"${DEMO_FILE_EXT}")
    # An unmatched glob stays unexpanded; that single non-existing entry
    # is the empty-directory case.
    if [ ! -e "${files[0]}" ]; then
        return 0
    fi
    for (( i = 0; i < ${#files[@]}; i++ )); do
        demo_file_hash "${files[i]}"
        if [ "${DEMO_FILE_HASH}" != "-" ]; then
            DEMO_HASH_FILE["${DEMO_FILE_HASH}"]="${files[i]}"
        fi
    done
    return 0
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
        if rm -f -- "${ordinary[i]}" 2>/dev/null; then
            debug_event "demo: pruned ${ordinary[i]} (keeping ${DEMO_MAX} ordinary recordings)"
        else
            # Checked for the same reason as in demo_record_discard: an
            # undeletable recording must not end the round.
            debug_event "demo: could not prune ${ordinary[i]}"
        fi
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
            pcs=*|e=*|p=*|v=*) break ;;
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
            # The session block of a versus recording (format 3). Checked
            # for shape here and otherwise left alone: what the playback
            # of one needs from it is picked up where the playback is
            # built (step 9.8), and this function is what the demo list
            # calls for every file in the directory.
            length|players|winner)
                [[ "${val}" =~ ${DEMO_NUM_RE} ]] || return 1
                ;;
            slot)
                [[ "${val}" =~ ^[0-9]$ ]] || return 1
                ;;
            mpmode)
                [[ "${val}" =~ ${DEMO_MPMODE_RE} ]] || return 1
                ;;
            garbage)
                [[ "${val}" =~ ^[01]$ ]] || return 1
                ;;
            peer)
                [[ "${val}" =~ ${DEMO_PEER_RE} ]] || return 1
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
    if [ "${version}" -lt "${DEMO_FORMAT_MIN_VERSION}" ] || \
       [ "${version}" -gt "${DEMO_FORMAT_VERSION}" ]; then
        return 1
    fi
    # A recording without these is not replayable: the mode decides the
    # rules of the round, the ending decides what the final box says.
    if [ -z "${DEMO_HDR_MODE}" ] || [ -z "${DEMO_HDR_END}" ] || \
       [ -z "${DEMO_HDR_DATE}" ]; then
        return 1
    fi
    # A versus round is what the multiplayer section was added for, so a
    # file claiming one in a version that has no such section is not a
    # short recording of one - it is a file somebody edited.
    if [ "${DEMO_HDR_MODE}" = "versus" ] && [ "${version}" -lt 3 ]; then
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
    # A versus recording is written since step 9.6 and read since step
    # 9.8; until then it is refused here rather than half-read. Its
    # streams are keyed by slot, and taking them for the single stream
    # below would replay one board out of five boards' events.
    if [ "${DEMO_HDR_MODE}" = "versus" ]; then
        debug_event "demo: ${file} is a versus recording, which cannot be replayed yet"
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
            version|game|mode|name|date|time|length|lines|rows|level|gold| \
            silver|rowhammers|pieces|goal|end|players|slot|mpmode|garbage| \
            winner|peer)
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
        # The recorded gap column is handed back to the very function
        # that drew it, so the replay floods the same column the round
        # did (see flood_raise in rowhammer.sh).
        w[0-9]) flood_raise "${1#w}" ;;
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
        i18n_lines demo_invalid
        menu_message "${I18N[demo_title]}" "${I18N_LINES[@]}"
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
        HSF_LAST_RANK=0
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
            printf -v label '%s%-16s %s' "${mark}" "${I18N[demo_broken]}" "${f##*/}"
            DEMO_LIST_FILE+=("${f}")
            DEMO_LIST_LABEL+=("${label:0:43}")
            DEMO_LIST_MARKED+=("${mark}")
            continue
        fi
        # Eight columns for the mode, which is what the label format
        # below leaves it; Time Attack and Hochwasser have a short name
        # of their own in the translation table, because their full ones
        # do not fit.
        case "${DEMO_HDR_MODE}" in
            ultra)      mode_label="${I18N[mode_ultra]}" ;;
            sprint)     mode_label="${I18N[mode_sprint]}" ;;
            timeattack) mode_label="${I18N[mode_timeattack_short]}" ;;
            flood)      mode_label="${I18N[mode_flood_short]}" ;;
            versus)     mode_label="${I18N[mode_versus_short]}" ;;
            *)          mode_label="${I18N[mode_marathon]}" ;;
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
    if rm -f -- "${file}" 2>/dev/null; then
        debug_event "demo: deleted ${file}"
        return 0
    fi
    debug_event "demo: could not delete ${file}"
    return 1
}
