#!/usr/bin/env bash
#
# lib/mp.sh
#
# Description:
#   Client side of the rowhammer multiplayer (CLAUDE.md 5.3/5.6/5.10):
#   the "Mehrspieler" menu, the session search, the lobby, the peer states
#   and everything the running round needs to talk to the hub.
#   Three ways into a session, all of them ending in the same lobby: open
#   one (which starts a hub process in the background and connects to it
#   like any other client - the host is simply the client in slot 0),
#   join one found by its beacon, or connect to an address typed by hand.
#   The third is not a fallback but an equal path: WLANs with client
#   isolation, separate VLANs and quite a few container networks drop
#   broadcasts, and without it the game would be broken there for no
#   reason a player could see. That is also why the lobby shows the host
#   its own address and port - an address one has to look up with "ip
#   addr" first is no help to somebody who is stuck.
#   The lobby also carries the session settings the host decides on - the
#   mode, which decides how the round is won, and whether garbage flies -
#   and shows them to every player, not only to the one who set them
#   (mp_settings_menu, CLAUDE.md 5.1).
#   During the round mp_poll drains the link once per tick and applies
#   what arrived; nothing here ever blocks, and nothing here draws - the
#   peers are painted by lib/render.sh from the arrays this module keeps.
#   The client reports events and never consequences: it sends its
#   counters, its clears and its top-out, and the hub decides what they
#   are worth (see lib/hub.sh).
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 1.4.1  (2026-09-05)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/mp.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# --- Session state --------------------------------------------------------
# MP_ACTIVE is read all over the game loop and the renderer: 1 means this
# round is a multiplayer round. MP_SLOT is our own slot, MP_STATE what the
# hub thinks we are doing, MP_PHASE where the session is (lobby, play,
# end).
MP_ACTIVE=0
MP_SLOT=-1
MP_STATE="lobby"
MP_PHASE="lobby"
# Whether this client runs the lobby - which is the hub's answer (the HOST
# message), not something this end decides. Since 1.2.0 the role can move:
# when the host leaves, the lobby passes to whoever joined first of those
# still there, and this flag follows.
MP_IS_HOST=0
MP_HOST_SLOT=-1
# Whether this client started the hub process, and its pid. Deliberately
# separate from MP_IS_HOST: the two used to be the same thing and are not
# any more. Whoever started the hub keeps the pid (and only they may end
# it); who runs the lobby is the hub's to say.
MP_OWNS_HUB=0
MP_HUB_PID=0
# A host change that still has to be shown: the slot it went to, or -1
# when there is nothing to show. The lobby turns it into a notice that has
# to be acknowledged; during a round it stays unshown, because there is
# nothing to do about it until the round is over.
MP_HOST_NOTICE=-1
# The port the hub this client started really listens on (it may have had
# to move up from MP_PORT), read back from the file the hub writes. It is
# what a takeover reports to the old hub so the others know where to go.
MP_HUB_PORT=0
# A session that has moved or ended while this client was in its lobby:
# the address to follow, or the reason the session is over. The lobby acts
# on them - nothing here talks to the screen.
MP_MOVE_ADDR=""
MP_MOVE_PORT=0
MP_CLOSED=""
# When the last message from the hub arrived. A hub that has gone away
# without closing its sockets - a killed process, a machine that fell off
# the network - produces no end of file, so silence is the only thing left
# to notice it by (user request, 1.2.0). The hub watches its clients the
# same way and with the same limit.
MP_LAST_RX_MS=0
# The name of the session this client is in, as its hub reported it
# (WELCOME). MP_SESSION beside it stays what this client would call a
# session it opens itself; the two are the same only for the player who
# opened this one.
MP_SESSION_NAME=""
# How many players the session we are in holds, as its hub reported it
# (WELCOME). It is not this client's MP_MAX: a session keeps its size
# when it moves to another hub (1.2.0), and a successor whose own
# --mp-max happens to be a different number must not quietly resize the
# room everybody is sitting in.
MP_SESSION_MAX=0
# Garbage waiting to be pushed into our board, and the gap column of the
# rows waiting. The hub owns the authoritative queue length and corrects
# ours with QUEUE whenever a clear of ours cancelled part of it.
MP_PENDING=0
MP_HOLE=0
# The round's outcome as the hub reported it: our place, the winning slot
# and whether the round has been decided at all.
MP_PLACE=0
MP_WINNER=-1
MP_ENDED=0
# Why the session ended, for the message shown afterwards: "" (regular),
# "lost" (connection gone), "err:<code>" (the hub refused us).
MP_ERROR=""
# How much of the round's state still has to reach the hub: the counters
# are only sent when they changed, and a board snapshot only when one is
# wanted (NEEDBOARD) and at most MP_BOARD_MS apart.
MP_NEEDBOARD=0
MP_LAST_STATE=""
MP_NEXT_BOARD_MS=0
MP_BOARD_MS=200
# The move stream (ACT, protocol 4): what this player did since the last
# window went out, as "<delta><action>" tokens in the demo format's own
# alphabet (CLAUDE.md 4.10/5.20). MP_ACT_BUF collects them, MP_ACT_BASE_MS
# is the round time the first token of the current window counts from,
# MP_ACT_LAST_MS the round time of the last token collected, and
# MP_ACT_NEXT_MS when the window is due.
# The window is 100 ms: about ten messages a second while a player is
# doing something, which is the same order as the counters (STATE) and
# far below the rate limit - and short enough that a move is never held
# back long enough to be noticed.
# The 48 tokens are the protocol's own limit on the field (PROTO_ACT_RE);
# reaching it inside one window would take a key repeat far beyond human
# speed, but a full buffer is flushed early rather than truncated,
# because a dropped move would make a recording diverge silently.
MP_ACT_BUF=""
MP_ACT_BASE_MS=0
MP_ACT_LAST_MS=0
MP_ACT_NEXT_MS=0
MP_ACT_MS=100
MP_ACT_MAX=48
# How long the last message to a hub we are about to leave is given to
# get out (mp_promote). Well below HUB_PROMOTE_MS, the window the old hub
# waits in, and long enough for socat to move one line into a loopback
# socket.
MP_HANDOFF_FLUSH_MS=250
# Start of the round, counted down from the hub's START.
MP_START_MS=0
# The session settings as the hub last sent them (SETUP): the mode of the
# round and whether cleared rows send garbage. Every client keeps them,
# not only the host - the lobby of every player shows them, and during the
# round they decide what the HUD has to show and what the result means.
# The defaults here are the hub's; they are overwritten by the first SETUP
# the moment a client is let in.
MP_MODE="survival"
MP_GARBAGE=0
# The modes the host can pick, in the order the settings menu offers them.
# One entry per win condition - which is what makes them modes rather than
# options (see CLAUDE.md 5.1).
MP_MODES=(survival sprint ultra)

# Peer tables, indexed by slot. Every one of them is filled from validated
# protocol fields only (lib/proto.sh), and the renderer clamps them again
# before they reach the screen - the hub is not trusted either, it could
# be a different program altogether (CLAUDE.md 5.5).
MP_PEER_NAME=()
MP_PEER_READY=()
MP_PEER_STATE=()
MP_PEER_ROWS=()
MP_PEER_LINES=()
MP_PEER_LEVEL=()
MP_PEER_GOLD=()
MP_PEER_SILVER=()
MP_PEER_HEIGHT=()
MP_PEER_PENDING=()
MP_PEER_PLACE=()
MP_PEER_BOARD=()

# How many seats those tables cover. In a session that is this client's
# own MP_MAX - a hub may never seat more than the client can show, which
# is what mp_hub_start clamps against. A demo playback sets it to
# MP_SEAT_MAX instead: a recording is a file, and it must not lose seats
# because the session watching it was started with a smaller --mp-max
# than the session that played it (the same reasoning DEMO_STREAM_MAX
# stands on, lib/demo.sh).
# MP_SEAT_MAX is the technical maximum, the 5 that --mp-max accepts at
# the most (see rowhammer.sh); mp_reset initialises that many entries, so
# no seat a playback opens is ever an unset one.
MP_SEAT_MAX=5
MP_SEATS="${MP_MAX:-5}"

# mp_reset
# Clear the whole session state. Called before every join attempt, so a
# second session never inherits anything from the first.
mp_reset() {
    local i
    # MP_SESSION_NAME is deliberately not cleared here: a session that
    # moves to another hub runs through the connect path, and the name is
    # the one thing that has to survive it. The new hub confirms it in its
    # WELCOME anyway.
    MP_SLOT=-1
    MP_STATE="lobby"
    MP_PHASE="lobby"
    MP_PENDING=0
    MP_HOLE=0
    MP_PLACE=0
    MP_WINNER=-1
    MP_ENDED=0
    MP_ERROR=""
    MP_NEEDBOARD=0
    MP_LAST_STATE=""
    MP_NEXT_BOARD_MS=0
    MP_ACT_BUF=""
    MP_ACT_BASE_MS=0
    MP_ACT_LAST_MS=0
    MP_ACT_NEXT_MS=0
    MP_START_MS=0
    MP_VIEW_SENT=-1
    MP_HOST_SLOT=-1
    MP_HOST_NOTICE=-1
    MP_MOVE_ADDR=""
    MP_MOVE_PORT=0
    MP_CLOSED=""
    now_ms
    MP_LAST_RX_MS="${NOW_MS}"
    MP_MODE="survival"
    MP_GARBAGE=0
    # Back to the session's own size; a playback that widened it has
    # given the tables back by the time this runs.
    MP_SEATS="${MP_MAX}"
    # Every technically possible seat, not just MP_SEATS of them: the
    # ones beyond it are what a demo playback of a larger session opens,
    # and they have to hold a value rather than nothing.
    for (( i = 0; i < MP_SEAT_MAX; i++ )); do
        MP_PEER_NAME[i]=""
        MP_PEER_READY[i]=0
        MP_PEER_STATE[i]="lobby"
        MP_PEER_ROWS[i]=0
        MP_PEER_LINES[i]=0
        MP_PEER_LEVEL[i]=0
        MP_PEER_GOLD[i]=0
        MP_PEER_SILVER[i]=0
        MP_PEER_HEIGHT[i]=0
        MP_PEER_PENDING[i]=0
        MP_PEER_PLACE[i]=0
        MP_PEER_BOARD[i]=""
    done
    return 0
}

# mp_peer_count
# How many other players the session has (slots with a name that are not
# our own), into MP_PEER_COUNT, and their slot numbers in MP_PEER_SLOTS.
# The renderer asks this to pick its detail level and to lay the mini
# boards out.
MP_PEER_COUNT=0
MP_PEER_SLOTS=()
mp_peer_count() {
    local i
    MP_PEER_COUNT=0
    MP_PEER_SLOTS=()
    for (( i = 0; i < MP_SEATS; i++ )); do
        [ -n "${MP_PEER_NAME[i]}" ] || continue
        [ "${i}" -ne "${MP_SLOT}" ] || continue
        MP_PEER_SLOTS+=("${i}")
        MP_PEER_COUNT=$(( MP_PEER_COUNT + 1 ))
    done
    return 0
}

# mp_alive_count
# How many players are still in the round, into MP_ALIVE - the opponents
# whose state is neither "ko" nor "gone", plus this player when their own
# board is still standing. The HUD shows it: in a duel it is the number
# that says whether this is still a race or already a victory lap.
MP_ALIVE=0
mp_alive_count() {
    local i
    MP_ALIVE=0
    if [ "${MP_STATE}" = "play" ]; then
        MP_ALIVE=1
    fi
    for (( i = 0; i < MP_SEATS; i++ )); do
        [ -n "${MP_PEER_NAME[i]}" ] || continue
        [ "${i}" -ne "${MP_SLOT}" ] || continue
        case "${MP_PEER_STATE[i]}" in
            ko|gone) : ;;
            *) MP_ALIVE=$(( MP_ALIVE + 1 )) ;;
        esac
    done
    return 0
}

# --- Receiving ------------------------------------------------------------
# mp_handle LINE
# Apply one message from the hub. Every field it reads has been through
# the whitelist parser first, so no value here needs a second look before
# it is used as a number or an array index.
mp_handle() {
    local line="${1}" rc=0 slot
    proto_parse "${line}" || rc=$?
    if [ "${rc}" -ne 0 ]; then
        # An unknown verb (2) is ignored on purpose; a malformed line (1)
        # is dropped and noted. A client does not hang up on its hub for
        # it: the hub is the only peer it has, and losing the round over
        # one bad line would be worse than ignoring it.
        net_log "bad" "${line}"
        return 0
    fi
    case "${PROTO_VERB}" in
        WELCOME)
            MP_SLOT="${PROTO_ARG[0]}"
            # The name of the session we are in - which a client that
            # joined by address could not know otherwise. It is what the
            # lobby shows and what a session keeps when it moves to
            # another hub, so it is deliberately not this client's own
            # MP_SESSION (the name it would give a session it opened).
            MP_SESSION_NAME="${PROTO_ARG[3]}"
            # Kept for the same reason as the name: it is a property of
            # the session, not of this client, and it has to survive a
            # move to another hub (see mp_hub_start).
            MP_SESSION_MAX="${PROTO_ARG[2]}"
            debug_event "mp: welcome to '${MP_SESSION_NAME}', slot ${MP_SLOT} of ${PROTO_ARG[2]}"
            ;;
        ROSTER)
            slot="${PROTO_ARG[0]}"
            if [ "${slot}" -lt "${MP_MAX}" ]; then
                MP_PEER_NAME[slot]="${PROTO_ARG[1]}"
                MP_PEER_READY[slot]="${PROTO_ARG[2]}"
                MP_PEER_STATE[slot]="${PROTO_ARG[3]}"
                # The roster is the only message that tells a top-out
                # from a lost connection: the KO before it says the same
                # thing for both, and the recording keeps them apart.
                demo_record_peer_status "${slot}" "${PROTO_ARG[3]}"
            fi
            ;;
        SEED)
            # The shared piece sequence: everybody plays the same pieces,
            # which is what makes the duel about play rather than luck. A
            # --seed given on the host's command line became this seed in
            # the hub; on every client it simply arrives here.
            RANDOM="${PROTO_ARG[0]}"
            debug_event "mp: seed ${PROTO_ARG[0]}"
            ;;
        START)
            now_ms
            MP_START_MS=$(( NOW_MS + ${PROTO_ARG[0]} ))
            MP_PHASE="start"
            ;;
        PEER)
            slot="${PROTO_ARG[0]}"
            if [ "${slot}" -lt "${MP_MAX}" ]; then
                MP_PEER_LINES[slot]="${PROTO_ARG[1]}"
                MP_PEER_ROWS[slot]="${PROTO_ARG[2]}"
                MP_PEER_LEVEL[slot]="${PROTO_ARG[3]}"
                MP_PEER_GOLD[slot]="${PROTO_ARG[4]}"
                MP_PEER_SILVER[slot]="${PROTO_ARG[5]}"
                MP_PEER_HEIGHT[slot]="${PROTO_ARG[6]}"
                MP_PEER_PENDING[slot]="${PROTO_ARG[7]}"
                MP_PEER_STATE[slot]="${PROTO_ARG[8]}"
                # The counters go into the recording as a checkpoint, so
                # a replay can tell whether its simulation of this player
                # still agrees with the round it is replaying. The
                # pending queue is not among them: it is the one number
                # the stream carries by itself (the y and q events).
                demo_record_peer_state "${slot}" "${PROTO_ARG[1]}" \
                    "${PROTO_ARG[2]}" "${PROTO_ARG[3]}" "${PROTO_ARG[4]}" \
                    "${PROTO_ARG[5]}" "${PROTO_ARG[6]}"
                DIRTY=1
            fi
            ;;
        PEERBOARD)
            slot="${PROTO_ARG[0]}"
            if [ "${slot}" -lt "${MP_MAX}" ]; then
                MP_PEER_BOARD[slot]="${PROTO_ARG[1]}"
                DIRTY=1
            fi
            ;;
        PEERACT)
            # Another player's moves: written into the recording of this
            # round and otherwise left alone. Nothing is done with them
            # while the round runs, on purpose - the mini boards keep
            # coming from the snapshots (PEERBOARD), because simulating
            # four more rounds per frame is what the playback does, not
            # the game (CLAUDE.md 5.20, "Nicht Ziel").
            slot="${PROTO_ARG[0]}"
            if [ "${slot}" -lt "${MP_MAX}" ]; then
                debug_event "mp: moves of slot ${slot} at ${PROTO_ARG[1]}: ${PROTO_ARG[2]}"
                demo_record_peer_act "${slot}" "${PROTO_ARG[1]}" "${PROTO_ARG[2]}"
            fi
            ;;
        NEEDBOARD)
            MP_NEEDBOARD="${PROTO_ARG[0]}"
            ;;
        HOST)
            # Who runs the lobby. The first one of these is the session
            # this client just joined and is nothing to report; every one
            # after it is a handover, and the lobby shows it as a notice
            # that has to be acknowledged (user request).
            if [ "${MP_HOST_SLOT}" -ge 0 ] \
                && [ "${PROTO_ARG[0]}" -ne "${MP_HOST_SLOT}" ]; then
                MP_HOST_NOTICE="${PROTO_ARG[0]}"
            fi
            MP_HOST_SLOT="${PROTO_ARG[0]}"
            if [ "${MP_HOST_SLOT}" -eq "${MP_SLOT}" ]; then
                MP_IS_HOST=1
            else
                MP_IS_HOST=0
            fi
            debug_event "mp: slot ${MP_HOST_SLOT} runs the lobby (own slot ${MP_SLOT})"
            DIRTY=1
            ;;
        SETUP)
            # What the host settled on. Taken as it comes: the hub is the
            # one that decides, and a client that argued with it would
            # only be playing a different round from everybody else.
            MP_MODE="${PROTO_ARG[0]}"
            MP_GARBAGE="${PROTO_ARG[1]}"
            debug_event "mp: session settings mode=${MP_MODE} garbage=${MP_GARBAGE}"
            DIRTY=1
            ;;
        GARBAGE)
            # Since protocol 4 these come with the slot they are meant
            # for and go to everybody, so a recording can follow every
            # board (CLAUDE.md 5.20). Only our own rows are queued;
            # somebody else's are noted and otherwise left alone - what a
            # peer's queue looks like is what its PEER message says, and
            # a second source for the same number could only drift away
            # from it.
            slot="${PROTO_ARG[0]}"
            # Into the recording for every slot, our own included: a
            # board's garbage is the one thing that happens to it without
            # a move behind it, so a replay cannot work it out on its own.
            demo_record_garbage "${slot}" "${PROTO_ARG[1]}" "${PROTO_ARG[2]}"
            if [ "${slot}" -eq "${MP_SLOT}" ]; then
                # Queued, not applied: garbage comes in at the next lock,
                # never while a piece is falling, so the move in progress
                # stays plannable (CLAUDE.md 5.7).
                MP_PENDING=$(( MP_PENDING + ${PROTO_ARG[1]} ))
                MP_HOLE="${PROTO_ARG[2]}"
                debug_event "mp: ${PROTO_ARG[1]} garbage row(s) incoming, hole=${MP_HOLE}, queue=${MP_PENDING}"
                DIRTY=1
            else
                debug_event "mp: ${PROTO_ARG[1]} garbage row(s) hole=${PROTO_ARG[2]} -> slot ${slot}"
            fi
            ;;
        QUEUE)
            # The hub cancelled part of a queue against a clear and says
            # what is left of it. Its number wins over ours - but only for
            # our own queue; see GARBAGE above for the rest.
            slot="${PROTO_ARG[0]}"
            # Recorded for every slot, and for the same reason as the
            # garbage above: what a clear cancelled is the hub's
            # arithmetic, and a replay adding the rows up itself would
            # drift away from the round at the first cancelled attack.
            demo_record_queue "${slot}" "${PROTO_ARG[1]}"
            if [ "${slot}" -eq "${MP_SLOT}" ]; then
                MP_PENDING="${PROTO_ARG[1]}"
                DIRTY=1
            else
                debug_event "mp: queue of slot ${slot} is now ${PROTO_ARG[1]}"
            fi
            ;;
        KO)
            slot="${PROTO_ARG[0]}"
            if [ "${slot}" -lt "${MP_MAX}" ]; then
                MP_PEER_PLACE[slot]="${PROTO_ARG[1]}"
                # Noted for the recording, written once the roster says
                # whether this was a top-out or a lost connection.
                demo_record_ko "${slot}" "${PROTO_ARG[1]}"
                MP_PEER_STATE[slot]="ko"
                if [ "${slot}" -eq "${MP_SLOT}" ]; then
                    MP_PLACE="${PROTO_ARG[1]}"
                    MP_STATE="ko"
                fi
                DIRTY=1
            fi
            ;;
        END)
            MP_WINNER="${PROTO_ARG[0]}"
            MP_ENDED=1
            MP_PHASE="end"
            if [ "${MP_WINNER}" -eq "${MP_SLOT}" ]; then
                MP_PLACE=1
            fi
            debug_event "mp: round over, winner slot ${MP_WINNER}, own place ${MP_PLACE}"
            DIRTY=1
            ;;
        PROMOTE)
            # The host has left and this client is the one asked to carry
            # the session on. Answered here rather than in the lobby: the
            # old hub is waiting for the port, and a menu that happens to
            # be open must not delay it.
            mp_promote
            ;;
        MIGRATE)
            # The session has moved to the hub the new host started.
            MP_MOVE_ADDR="${PROTO_ARG[0]}"
            MP_MOVE_PORT="${PROTO_ARG[1]}"
            debug_event "mp: session moved to ${MP_MOVE_ADDR}:${MP_MOVE_PORT}"
            ;;
        CLOSED)
            MP_CLOSED="${PROTO_ARG[0]}"
            debug_event "mp: session closed by the hub (${MP_CLOSED})"
            ;;
        PING)
            proto_msg PONG "${PROTO_ARG[0]}"
            net_send "${PROTO_LINE}" || :
            ;;
        ERR)
            MP_ERROR="err:${PROTO_ARG[0]}"
            debug_event "mp: hub error ${PROTO_ARG[0]}: ${PROTO_ARG[1]:-}"
            ;;
    esac
    return 0
}

# mp_poll
# Drain the link and apply everything that arrived. Returns 1 when the
# link is gone, which the caller turns into "connection lost". Called once
# per game tick and, during the clear animation, from flash_rows as well:
# 280 ms without reading would let the hub's messages pile up right at the
# moment a clear is being reported.
mp_poll() {
    local line
    [ "${MP_ACTIVE}" -eq 1 ] || return 0
    if ! net_poll; then
        MP_ERROR="lost"
        return 1
    fi
    if [ "${#NET_INBOX[@]}" -gt 0 ]; then
        now_ms
        MP_LAST_RX_MS="${NOW_MS}"
    fi
    for line in ${NET_INBOX[@]+"${NET_INBOX[@]}"}; do
        mp_handle "${line}"
    done
    return 0
}

# mp_link_silent
# True when nothing has come from the hub for MP_TIMEOUT_MS. A hub that
# ends properly closes its sockets and the client sees an end of file; one
# that is killed, or a machine that disappears from the network, leaves
# the connection open and silent forever. The hub sends a PING every
# MP_PING_MS, so silence for three times that long is not a quiet moment -
# it is a session that is not there any more (user request).
# Deliberately the same limit the hub drops a silent client after: both
# ends give up on each other at the same moment rather than one of them
# waiting for a peer that has already written it off.
mp_link_silent() {
    [ "${MP_ACTIVE}" -eq 1 ] || return 1
    now_ms
    (( NOW_MS - MP_LAST_RX_MS > MP_TIMEOUT_MS ))
}

# --- Sending --------------------------------------------------------------
# mp_send_state
# Report our counters, but only when they actually changed - the limit in
# the protocol is ten a second, and a round produces far fewer changes
# than that. The peers see the same numbers our own HUD shows.
mp_send_state() {
    local key
    [ "${MP_ACTIVE}" -eq 1 ] || return 0
    proto_stack_height
    key="${CLEARED_TOTAL}|${ROW_CREDIT}|${LEVEL}|${GOLD_COUNT}|${SILVER_COUNT}|${PROTO_HEIGHT}|${MP_PENDING}"
    if [ "${key}" = "${MP_LAST_STATE}" ]; then
        return 0
    fi
    MP_LAST_STATE="${key}"
    proto_msg STATE "${CLEARED_TOTAL}" "${ROW_CREDIT}" "${LEVEL}" \
        "${GOLD_COUNT}" "${SILVER_COUNT}" "${PROTO_HEIGHT}" "${MP_PENDING}"
    net_send "${PROTO_LINE}" || :
    return 0
}

# mp_send_view LEVEL
# Tell the hub whether this client is drawing the opponents' boards. Sent
# only when the answer changes, which is at the start of a round and
# whenever a resize moves the detail level across the line (see
# render_peer_level in lib/render.sh, which is where this is called from -
# the level is decided per frame, and this is the one thing about it the
# hub has to know).
MP_VIEW_SENT=-1
mp_send_view() {
    local want=0
    [ "${MP_ACTIVE}" -eq 1 ] || return 0
    # A demo playback draws the very same opponent boards and therefore
    # runs through the same decision, but it has nobody to report to: a
    # replay never sends a byte (CLAUDE.md 5.20). net_send would refuse
    # it anyway for want of a link; saying so here keeps that from being
    # the reason.
    [ "${DEMO_PLAYING}" -eq 0 ] || return 0
    if [ "${1}" -ge 2 ]; then
        want=1
    fi
    [ "${want}" -ne "${MP_VIEW_SENT}" ] || return 0
    MP_VIEW_SENT="${want}"
    proto_msg VIEW "${want}"
    net_send "${PROTO_LINE}" || :
    debug_event "mp: board snapshots ${want} (detail level ${1})"
    return 0
}

# mp_send_board
# Send a board snapshot, at most every MP_BOARD_MS and only while some
# peer actually shows one (NEEDBOARD). That flag is what keeps a session
# of small terminals from producing snapshot traffic nobody looks at.
mp_send_board() {
    [ "${MP_ACTIVE}" -eq 1 ] || return 0
    [ "${MP_NEEDBOARD}" -eq 1 ] || return 0
    now_ms
    (( NOW_MS >= MP_NEXT_BOARD_MS )) || return 0
    MP_NEXT_BOARD_MS=$(( NOW_MS + MP_BOARD_MS ))
    proto_board_encode
    proto_msg BOARD "${PROTO_BOARD}"
    net_send "${PROTO_LINE}" || :
    return 0
}

# --- The move stream ------------------------------------------------------
# mp_round_ms
# The round time in milliseconds, into MP_ROUND_MS: how long ago the round
# started for everybody. Deliberately not the play clock (PLAY_MS): the
# round time is the one clock all participants share - they all hang off
# the same countdown (MP_START_MS) - and a multiplayer round has no pause
# that could stop it (CLAUDE.md 5.8/5.20). Clamped at zero so the
# countdown before the start cannot produce a negative stamp.
MP_ROUND_MS=0
mp_round_ms() {
    now_ms
    MP_ROUND_MS=$(( NOW_MS - MP_START_MS ))
    if [ "${MP_ROUND_MS}" -lt 0 ]; then
        MP_ROUND_MS=0
    fi
    return 0
}

# mp_act_event ACTION
# Note one thing this player did, for the move stream. Called from the
# same places the demo recording is fed from, and for the same alphabet -
# but always, not only while a recording runs: the traffic of a round has
# to be the same whether --demo-record is on or off, or the setting would
# be visible on the wire (CLAUDE.md 3.8).
# Anything outside the move alphabet is dropped here rather than sent:
# the flood row of the Hochwasser mode ("w<column>") is the one such event
# today, it cannot occur in a multiplayer round, and a message the peers
# would have to throw away should not be produced in the first place
# (the same rule the player name goes through in proto_name).
mp_act_event() {
    local action="${1}" delta
    [ "${MP_ACTIVE}" -eq 1 ] || return 0
    # A playback runs the very same round functions and therefore reaches
    # here, with MP_ACTIVE set for the renderer's sake and no link behind
    # it (demo_play_peers_begin). It has nothing to report: the moves it
    # is replaying came out of a recording, and a window buffered here
    # would only grow (CLAUDE.md 5.20).
    [ "${DEMO_PLAYING}" -eq 0 ] || return 0
    [ "${MP_PHASE}" = "play" ] || return 0
    [[ "${action}" =~ ^[acghklors]$ ]] || return 0
    mp_round_ms
    if [ -z "${MP_ACT_BUF}" ]; then
        # First token of a window: it counts from the round time of the
        # previous window's last token, so the deltas stay continuous
        # across windows and a receiver never has to guess.
        MP_ACT_BASE_MS="${MP_ACT_LAST_MS}"
    fi
    delta=$(( MP_ROUND_MS - MP_ACT_LAST_MS ))
    # A clock that jumped backwards must not write a negative delta; the
    # event then lands on the previous one's timestamp, exactly as the
    # demo recording handles it.
    if [ "${delta}" -lt 0 ]; then
        delta=0
    fi
    # Six digits is what the field pattern allows per delta. A longer gap
    # can only happen when a player does nothing for ten minutes, and the
    # window below goes out long before that - but the clamp keeps this
    # end from ever composing a line its own parser would reject.
    if [ "${delta}" -gt 999999 ]; then
        delta=999999
    fi
    MP_ACT_LAST_MS="${MP_ROUND_MS}"
    MP_ACT_BUF+="${delta}${action}"
    return 0
}

# mp_act_flush [force]
# Send the collected moves as one ACT and start a new window. Called once
# per tick from the game loop; it sends only when there is something to
# send and the window is up, so a player who is not touching anything
# produces no traffic at all. With an argument it sends regardless of the
# window - which is what the end of a round needs, so the last few moves
# before a top-out are not lost with the buffer.
mp_act_flush() {
    local force="${1:-0}" count
    [ "${MP_ACTIVE}" -eq 1 ] || return 0
    [ -n "${MP_ACT_BUF}" ] || return 0
    now_ms
    if [ "${force}" -ne 1 ]; then
        # Count the tokens by their action letters: a full buffer goes out
        # early, because the field cannot carry more and dropping a move
        # would make a recording of this round diverge without saying so.
        count="${MP_ACT_BUF//[^acghklors]/}"
        if (( NOW_MS < MP_ACT_NEXT_MS && ${#count} < MP_ACT_MAX )); then
            return 0
        fi
    fi
    MP_ACT_NEXT_MS=$(( NOW_MS + MP_ACT_MS ))
    proto_msg ACT "${MP_ACT_BASE_MS}" "${MP_ACT_BUF}"
    # Emptied before the send, and a failed send is not retried: the moves
    # are not one of the messages that have to arrive (CLEAR and TOPOUT
    # are, see CLAUDE.md 5.9). Holding them back would grow the buffer
    # past what the field can carry, on a link that is failing anyway.
    MP_ACT_BUF=""
    net_send "${PROTO_LINE}" || :
    return 0
}

# mp_send_clear LINES SILVER GOLD
# Report a clear: how many rows, and how many silver and gold squares ran
# through them. What that is worth in garbage is the hub's arithmetic -
# this end never computes an attack, which is what makes "I simply send
# twenty rows" impossible (CLAUDE.md 5.4).
mp_send_clear() {
    [ "${MP_ACTIVE}" -eq 1 ] || return 0
    # A playback clears rows on five simulated boards and reports none of
    # them: it has no link, and the attacks of that round were settled
    # when it was played (CLAUDE.md 5.20).
    [ "${DEMO_PLAYING}" -eq 0 ] || return 0
    proto_msg CLEAR "${1}" "${2}" "${3}"
    net_send "${PROTO_LINE}" || :
    return 0
}

# mp_send_topout
# Report our own game over. From here on this client is a spectator: it
# keeps drawing the others until the hub calls the round.
mp_send_topout() {
    [ "${MP_ACTIVE}" -eq 1 ] || return 0
    MP_STATE="ko"
    proto_msg TOPOUT
    net_send "${PROTO_LINE}" || :
    debug_event "mp: reported top-out"
    return 0
}

# mp_send_bye
# Leave in an orderly fashion. Best effort: a link that is already gone
# makes this a no-op, and the hub notices the same thing one timeout
# later either way.
mp_send_bye() {
    [ "${MP_ACTIVE}" -eq 1 ] || return 0
    proto_msg BYE
    net_send "${PROTO_LINE}" || :
    return 0
}

# --- Garbage --------------------------------------------------------------
# mp_apply_garbage
# Push the queued garbage rows into our board. Called from lock_and_next
# after a lock that cleared nothing: a lock that cleared rows has just
# sent its CLEAR, and the hub cancels against the queue before it is
# applied - which is what rewards the counter-attack over pure defence.
# Returns 1 when the rows push the stack out of the field, which is a
# top-out like any other.
mp_apply_garbage() {
    local n="${MP_PENDING}" i
    [ "${MP_ACTIVE}" -eq 1 ] || return 0
    [ "${n}" -gt 0 ] || return 0
    MP_PENDING=0
    # Row by row through the same function the Hochwasser mode uses
    # (board_flood_row): one rule for a row rising from below, whether the
    # water or an opponent sent it.
    for (( i = 0; i < n; i++ )); do
        board_flood_row "${MP_HOLE}" || break
    done
    # A playback pushes the very same rows into its simulated boards and
    # has nobody to tell about it - the queue it works off came out of
    # the recording (see demo_apply).
    if [ "${DEMO_PLAYING}" -eq 0 ]; then
        proto_msg APPLIED "${n}"
        net_send "${PROTO_LINE}" || :
    fi
    debug_event "mp: applied ${n} garbage row(s) with hole=${MP_HOLE}"
    DIRTY=1
    if board_top_out; then
        return 1
    fi
    return 0
}

# mp_wait_ms MS
# Wait a moment without busy-looping. In a normal session that is
# key_drain, the timed read the whole game paces itself with, which also
# swallows keys pressed while nothing is meant to be typed. The test bot
# has no terminal at all - a read on its closed standard input would be a
# fatal error there - so it waits with sleep instead. One helper, because
# every wait in this file is on one side or the other of that line.
mp_wait_ms() {
    local ms="${1}" secs
    if [ "${MP_BOT}" -eq 1 ]; then
        printf -v secs '%d.%03d' "$(( ms / 1000 ))" "$(( ms % 1000 ))"
        sleep "${secs}"
        return 0
    fi
    key_drain "${ms}"
    return 0
}

# --- Connecting -----------------------------------------------------------
# mp_hello
# Announce ourselves and wait for the hub's WELCOME. Returns 1 when the
# hub refuses us or does not answer within MP_HELLO_MS - the two cases a
# player has to be told about, because nothing else would happen
# afterwards.
mp_hello() {
    local deadline
    proto_name "${PLAYER_NAME}"
    proto_msg HELLO "${PROTO_VERSION}" "${PROTO_NAME}" "board"
    net_send "${PROTO_LINE}" || return 1
    now_ms
    deadline=$(( NOW_MS + MP_HELLO_MS ))
    while :; do
        now_ms
        (( NOW_MS < deadline )) || return 1
        mp_poll || return 1
        [ -z "${MP_ERROR}" ] || return 1
        if [ "${MP_SLOT}" -ge 0 ]; then
            return 0
        fi
        # The same short timed read the rest of the game paces itself
        # with; no sleep, and a key pressed here is swallowed on purpose
        # (the bot, which has no terminal, waits differently - see
        # mp_wait_ms).
        mp_wait_ms 50
    done
}

# mp_connect_host HOST PORT
# Connect to a session over TCP. The address is built from checked parts
# by net_addr_tcp; not one byte of what may have come off the network
# reaches a command line (CLAUDE.md 5.5).
mp_connect_host() {
    mp_reset
    net_addr_tcp "${1}" "${2}" || return 1
    net_connect "${NET_ADDR}" || return 1
    MP_ACTIVE=1
    if ! mp_hello; then
        mp_disconnect
        return 1
    fi
    return 0
}

# mp_connect_unix NAME
# Connect to a session on this host over its domain socket.
mp_connect_unix() {
    mp_reset
    net_session_path "${1}" || return 1
    [ -S "${NET_SESSION_PATH}" ] || return 1
    net_addr_unix "${NET_SESSION_PATH}" || return 1
    net_connect "${NET_ADDR}" || return 1
    MP_ACTIVE=1
    if ! mp_hello; then
        mp_disconnect
        return 1
    fi
    return 0
}

# mp_disconnect
# Leave the session and put everything back: the link, the hub process
# this client may have started, and the multiplayer flag the game loop
# and the renderer read.
mp_disconnect() {
    if [ "${MP_ACTIVE}" -eq 1 ]; then
        mp_send_bye
    fi
    # Before the link is dropped: mp_hub_stop asks the roster whether
    # anybody else is still in the session, and the roster is only
    # meaningful while the session is.
    mp_hub_stop
    net_close
    MP_ACTIVE=0
    return 0
}

# mp_promote
# Take the session over after the host has left: start a hub of our own
# and tell the old one which port it listens on, so it can send the others
# after us. Answering with 0 is a real answer - the old hub then closes
# the session properly instead of letting everybody run into a timeout.
# Nothing is drawn here and no key is asked for: this runs inside the
# receive path, and the old hub is waiting.
mp_promote() {
    debug_event "mp: asked to take the session over"
    if ! mp_hub_start; then
        MP_HUB_PORT=0
    fi
    proto_msg PROMOTED "${MP_HUB_PORT}"
    net_send "${PROTO_LINE}" || :
    # A moment for that line to leave the machine before the caller tears
    # the link down: net_send only writes into the coprocess, and
    # net_close kills it, so an answer written and closed on in the same
    # breath can be thrown away with the process that was to carry it.
    # The old hub would then wait out HUB_PROMOTE_MS and close a session
    # that was taken over perfectly well.
    mp_wait_ms "${MP_HANDOFF_FLUSH_MS}"
    if [ "${MP_HUB_PORT}" -eq 0 ]; then
        debug_event "mp: could not start a hub, the session cannot be taken over"
        return 0
    fi
    # Straight over to our own hub, without waiting for the MIGRATE the
    # others get: being first is what makes this client the host of the
    # new session (the hub gives the lobby to the first player that
    # identifies itself), and that is the whole point of being asked.
    # The old hub holds the others back for a moment for the same reason
    # (HUB_MIGRATE_DELAY_MS) - on one machine this head start is the only
    # thing between "the one who was asked" and "whoever reconnects
    # quickest".
    MP_MOVE_PORT="${MP_HUB_PORT}"
    MP_MOVE_ADDR="127.0.0.1"
    if [ "${MP_TRANSPORT}" != "lan" ]; then
        MP_MOVE_ADDR="0.0.0.0"
    fi
    return 0
}

# mp_migrate
# Follow a session that has moved: drop the old link and connect to the
# hub the new host started, under the same session name. Returns 1 when
# that does not work, which the lobby turns into "the session is gone" -
# there is nothing else it could be.
# The old host, the settings and the ready flags are all left behind: this
# is a new session with the same people in it, and the hub it now belongs
# to says who runs it and what it is set to (HOST, SETUP).
mp_migrate() {
    local addr="${MP_MOVE_ADDR}" port="${MP_MOVE_PORT}" ok=0
    MP_MOVE_ADDR=""
    MP_MOVE_PORT=0
    net_close
    MP_ACTIVE=0
    # The hub bookkeeping (MP_OWNS_HUB, MP_HUB_PID) survives this on its
    # own - mp_reset does not touch it - which is what a client that
    # started a hub for this very migration needs. A connect that fails
    # takes that hub down with it through mp_disconnect, and rightly so:
    # a hub nobody can reach is of no use to anybody.
    local session="${MP_SESSION_NAME:-${MP_SESSION}}"
    if [ "${MP_TRANSPORT}" != "lan" ] || [ "${addr}" = "0.0.0.0" ]; then
        mp_connect_unix "${session}" && ok=1
    else
        mp_connect_host "${addr}" "${port}" && ok=1
    fi
    [ "${ok}" -eq 1 ] || return 1
    debug_event "mp: followed the session to ${addr}:${port}"
    return 0
}

# mp_hub_start
# Start the hub for a session we are opening. It is a process of its own,
# detached from this client's terminal and process group, so neither can
# take the other down: a client killed with Ctrl-C leaves a hub that ends
# itself when the last player is gone, and a hub that dies leaves clients
# that see an end of file and return to the menu.
mp_hub_start() {
    local args=()
    # The session keeps its name when it moves to another hub: the others
    # know it by that name, it is what the beacon announces, and in the
    # unix transport it is the socket everybody reconnects to. Only a
    # client opening a session of its own falls back to the name it would
    # give one (mp_host sets MP_SESSION_NAME for exactly that case).
    local session="${MP_SESSION_NAME:-${MP_SESSION}}"
    # The size of the session travels with it, too: a takeover continues
    # the room the others are already sitting in, and this client's own
    # --mp-max is what it would open a session of its own with.
    # Never above this client's own limit, though: the peer arrays and
    # the layout are built for MP_MAX seats, and a hub that admitted more
    # than that would send this very client a roster it cannot show.
    local max="${MP_MAX}"
    if [ "${MP_SESSION_MAX}" -ge 2 ] && [ "${MP_SESSION_MAX}" -lt "${max}" ]; then
        max="${MP_SESSION_MAX}"
    fi
    args=(--mp-hub --mp-transport "${MP_TRANSPORT}" --mp-port "${MP_PORT}"
          --mp-max "${max}" --mp-target "${MP_TARGET}"
          --mp-session "${session}" --mp-dir "${MP_DIR}"
          --mp-mode "${MP_MODE_OPT}" --mp-garbage "${MP_GARBAGE_OPT}")
    if [ -n "${SEED}" ]; then
        args+=(--seed "${SEED}")
    fi
    if [ "${DEBUG_OPT}" -eq 1 ]; then
        # The hub logs into a directory of its own below the session's, so
        # its events and the client's do not interleave in one file.
        args+=(--debug --debug-dir "${DEBUG_DIR}/hub")
    fi
    rm -f -- "${MP_DIR}/${session}.port" 2>/dev/null || :
    setsid "${SCRIPT_DIR}/rowhammer.sh" "${args[@]}" >/dev/null 2>&1 &
    MP_HUB_PID=$!
    MP_OWNS_HUB=1
    MP_HUB_PORT=0
    # Give it the moment it needs to bind and create its FIFOs; the
    # connect below would otherwise race it and fail on the first try.
    mp_wait_ms 400
    if ! kill -0 "${MP_HUB_PID}" 2>/dev/null; then
        MP_HUB_PID=0
        MP_OWNS_HUB=0
        return 1
    fi
    # Which port it really got. It may not be the one asked for - a taken
    # port moves the hub up to the next free one - and a takeover has to
    # report the true number, so the other players reach the right door.
    mp_hub_port_read
    if [ "${MP_TRANSPORT}" = "lan" ] && [ "${MP_HUB_PORT}" -eq 0 ]; then
        debug_event "mp: the hub did not report a port"
        mp_hub_stop
        return 1
    fi
    debug_event "mp: hub started (pid ${MP_HUB_PID}, session ${session}, port ${MP_HUB_PORT})"
    return 0
}

# mp_hub_port_read
# Read the port our hub bound from the file it writes (hub_port_publish),
# retrying for a moment: the hub writes it right after binding, and that
# can land a hair after the wait above. In the unix transport there is no
# port to speak of and the file only says so.
mp_hub_port_read() {
    local tries port
    MP_HUB_PORT=0
    for (( tries = 0; tries < 10; tries++ )); do
        if [ -r "${MP_DIR}/${MP_SESSION_NAME}.port" ]; then
            IFS= read -r port < "${MP_DIR}/${MP_SESSION_NAME}.port" || port=""
            if net_port_ok "${port}"; then
                MP_HUB_PORT="${port}"
                return 0
            fi
        fi
        mp_wait_ms 100
    done
    return 0
}

# mp_hub_stop
# End the hub this client started - but only when nobody else is in the
# session (user request, 1.2.0). Whoever opened a session used to take it
# down with them; now the lobby passes to the next player
# (hub_host_reassign), and killing the hub here would pull the session out
# from under everybody who is still in it.
# Leaving it running is safe in every case: a hub with no players left
# ends itself on its next pass (hub_periodic), so an abandoned session
# never outlives its last player - this call only makes the common case,
# somebody quitting an empty lobby, immediate instead of a tick later.
# A hub of somebody else's session is never touched: MP_HUB_PID is only
# set by mp_hub_start.
mp_hub_stop() {
    if [ "${MP_HUB_PID}" -le 0 ]; then
        return 0
    fi
    if [ "${MP_ACTIVE}" -eq 1 ]; then
        mp_peer_count
        if [ "${MP_PEER_COUNT}" -gt 0 ]; then
            debug_event "mp: leaving the hub (pid ${MP_HUB_PID}) to the ${MP_PEER_COUNT} player(s) still in the session"
            MP_HUB_PID=0
            MP_OWNS_HUB=0
            return 0
        fi
    fi
    kill "${MP_HUB_PID}" 2>/dev/null || :
    MP_HUB_PID=0
    MP_OWNS_HUB=0
    return 0
}

# --- Menu -----------------------------------------------------------------
# mp_available
# True when a session can be opened or joined at all. socat is the one
# thing the multiplayer needs beyond the game itself; without it the entry
# stays visible and says which package is missing, which is why socat is
# a Recommends of the packages and not a Depends.
mp_available() {
    if net_require; then
        return 0
    fi
    i18n_lines mp_no_socat
    menu_message "${I18N[main_multi]}" "${I18N_LINES[@]}"
    return 1
}

# mp_menu
# The "Mehrspieler" main menu entry: open a session, join one from the
# list of those found, connect to an address by hand, or go back.
mp_menu() {
    local -a entries
    mp_available || return 0
    while :; do
        entries=("${I18N[mp_host]}" "${I18N[mp_join]}" "${I18N[mp_direct]}"
                 "${I18N[menu_back]}")
        menu_run "${I18N[main_multi]}" "${entries[@]}"
        case "${MENU_CHOICE}" in
            0) mp_host ;;
            1) mp_join ;;
            2) mp_direct ;;
            *) return 0 ;;
        esac
    done
}

# mp_host
# Open a session: start the hub, connect to it as the first client and go
# into the lobby. Being the host is nothing but being slot 0 - the same
# client, the same protocol, one extra process in the background.
mp_host() {
    local ok=0
    if ! net_dir_prepare; then
        menu_message "${I18N[main_multi]}" "${NET_ERROR}"
        return 0
    fi
    # The session this client opens is the one it named; from the moment
    # somebody joins, that name travels with the session (WELCOME).
    MP_SESSION_NAME="${MP_SESSION}"
    # A session of our own is as big as this client says; whatever an
    # earlier session was sized at is none of its business.
    MP_SESSION_MAX=0
    if ! mp_hub_start; then
        i18n_lines mp_host_failed
        menu_message "${I18N[mp_host]}" "${I18N_LINES[@]}"
        return 0
    fi
    # Not "MP_IS_HOST=1" any more: who runs the lobby is the hub's answer
    # and arrives as its HOST message. Opening the session and running it
    # are the same thing at this moment, but they stop being the same the
    # first time a host leaves (see hub_host_reassign in lib/hub.sh).
    if [ "${MP_TRANSPORT}" = "unix" ]; then
        mp_connect_unix "${MP_SESSION}" && ok=1
    else
        # Through the loopback address rather than the outside one: the
        # host's own client and its hub are on the same machine, and this
        # works whether or not the machine has a usable network address.
        mp_connect_host "127.0.0.1" "${MP_PORT}" && ok=1
    fi
    if [ "${ok}" -eq 0 ]; then
        mp_hub_stop
        MP_IS_HOST=0
        i18n_lines mp_host_failed
        menu_message "${I18N[mp_host]}" "${I18N_LINES[@]}"
        return 0
    fi
    mp_lobby
    return 0
}

# mp_join
# Search for sessions and join the one picked. The search listens for
# MP_DISCOVER_MS and then shows what it heard; a session that stopped
# beaconing drops out of the list after three missed beacons.
# The list is a hint and never a truth (CLAUDE.md 5.5): a forged beacon
# can at worst point at its own sender, and joining it then simply fails.
mp_join() {
    local -a entries
    local i n choice
    if [ "${MP_TRANSPORT}" = "unix" ]; then
        mp_join_unix
        return 0
    fi
    if ! net_dir_prepare; then
        menu_message "${I18N[main_multi]}" "${NET_ERROR}"
        return 0
    fi
    if ! net_discover_start; then
        i18n_lines mp_search_failed
        menu_message "${I18N[mp_join]}" "${I18N_LINES[@]}"
        return 0
    fi
    while :; do
        mp_search_wait
        net_discover_expire
        n="${#NET_SESSION_HOST[@]}"
        entries=()
        for (( i = 0; i < n; i++ )); do
            printf -v choice "${I18N[mp_session_entry]}" \
                "${NET_SESSION_NAME[i]}" "${NET_SESSION_HOST[i]}" \
                "${NET_SESSION_PLAYERS[i]}" "${NET_SESSION_MAX[i]}" \
                "${I18N[mp_state_${NET_SESSION_STATE[i]}]}"
            entries+=("${choice}")
        done
        if [ "${n}" -eq 0 ]; then
            entries+=("${I18N[mp_none]}")
        fi
        entries+=("${I18N[mp_search_again]}" "${I18N[menu_back]}")
        menu_run "${I18N[mp_join]}" "${entries[@]}"
        choice="${MENU_CHOICE}"
        if [ "${choice}" -lt 0 ] || [ "${choice}" -eq $(( ${#entries[@]} - 1 )) ]; then
            break
        fi
        if [ "${choice}" -eq $(( ${#entries[@]} - 2 )) ]; then
            continue
        fi
        if [ "${n}" -eq 0 ]; then
            continue
        fi
        net_discover_stop
        if mp_connect_host "${NET_SESSION_HOST[choice]}" \
            "${NET_SESSION_PORT[choice]}"; then
            mp_lobby
        else
            mp_connect_failed
        fi
        return 0
    done
    net_discover_stop
    return 0
}

# mp_search_wait
# Collect beacons for MP_DISCOVER_MS with a "searching..." screen up.
# Nothing is drawn from the collector itself; this loop simply reads the
# FIFO between two short waits, the same way the game loop reads the
# socket between two ticks.
mp_search_wait() {
    local deadline line
    local -a lines
    printf -v line "${I18N[mp_searching]}" "${MP_PORT}"
    lines=("  ${I18N[mp_join]}" "" "  ${line}")
    render_menu_frame "${lines[@]}"
    screen_write "${RENDER_MENU_FRAME}"
    now_ms
    deadline=$(( NOW_MS + MP_DISCOVER_MS ))
    while :; do
        net_discover_poll
        now_ms
        (( NOW_MS < deadline )) || break
        key_drain 100
    done
    return 0
}

# mp_join_unix
# The same thing for the unix transport, where no beacon is needed: the
# live sessions are the socket files in the shared directory, so a glob
# finds them.
mp_join_unix() {
    local -a entries names
    local sock name choice
    if ! net_dir_prepare; then
        menu_message "${I18N[main_multi]}" "${NET_ERROR}"
        return 0
    fi
    entries=()
    names=()
    for sock in "${MP_DIR}"/*.sock; do
        [ -S "${sock}" ] || continue
        name="${sock##*/}"
        name="${name%.sock}"
        [[ "${name}" =~ ${MP_SESSION_RE} ]] || continue
        names+=("${name}")
        entries+=("${name}")
    done
    if [ "${#entries[@]}" -eq 0 ]; then
        entries+=("${I18N[mp_none]}")
    fi
    entries+=("${I18N[menu_back]}")
    menu_run "${I18N[mp_join]}" "${entries[@]}"
    choice="${MENU_CHOICE}"
    if [ "${choice}" -lt 0 ] || [ "${choice}" -ge "${#names[@]}" ]; then
        return 0
    fi
    if mp_connect_unix "${names[choice]}"; then
        mp_lobby
    else
        mp_connect_failed
    fi
    return 0
}

# mp_direct
# Join by an address typed in by hand: "host" or "host:port". An equal
# path to the beacon search, not a fallback - a network that drops
# broadcasts is common enough that a game without this way in would be
# broken there for no visible reason.
# The input is checked and split exactly like an address that came out of
# a datagram; that it was typed here changes nothing about that.
mp_direct() {
    local host port
    MENU_INPUT_RE_CUR='^[A-Za-z0-9_.:-]$'
    MENU_INPUT_MAX_CUR=45
    i18n_lines mp_direct_body
    if ! menu_text_input "${I18N[mp_direct]}" "" "${I18N_LINES[@]}"; then
        return 0
    fi
    [ -n "${MENU_INPUT}" ] || return 0
    host="${MENU_INPUT%%:*}"
    port="${MP_PORT}"
    if [[ "${MENU_INPUT}" == *:* ]]; then
        port="${MENU_INPUT##*:}"
    fi
    if ! net_host_ok "${host}" || ! net_port_ok "${port}"; then
        i18n_lines mp_bad_address
        menu_message "${I18N[mp_direct]}" "${I18N_LINES[@]}"
        return 0
    fi
    if mp_connect_host "${host}" "${port}"; then
        mp_lobby
    else
        mp_connect_failed
    fi
    return 0
}

# mp_connect_failed
# One message for every way a join can fail - refused, unreachable, no
# answer. Which of them it was is in the debug log; on screen the useful
# half is what to try instead.
mp_connect_failed() {
    local -a body
    i18n_lines mp_join_failed
    body=("${I18N_LINES[@]}")
    if [ -n "${MP_ERROR}" ]; then
        body+=("" "${I18N[mp_reason]:-} ${MP_ERROR}")
    fi
    mp_disconnect
    menu_message "${I18N[main_multi]}" "${body[@]}"
    return 0
}

# --- Lobby ----------------------------------------------------------------
# mp_lobby
# The waiting room. It is a menu with a network connection, so it cannot
# use menu_run: the frame has to be redrawn when the roster changes, not
# only when a key is pressed, and the link has to be drained meanwhile.
# The host's entry is "start the round" (which the hub reads as its READY
# and answers with SEED and START), everybody else's is "ready".
mp_lobby() {
    local -a lines entries actions
    local sel=0 dirty=1 i n line ready=0 left=0
    net_local_addr
    while :; do
        if ! mp_poll; then
            mp_lobby_lost
            return 0
        fi
        if [ -n "${MP_ERROR}" ]; then
            mp_lobby_lost
            return 0
        fi
        # The session moved: the host left and somebody else took it over.
        # Followed first, told about afterwards - the notice belongs in
        # the lobby the player ends up in, not in the one they are
        # leaving.
        if [ -n "${MP_MOVE_ADDR}" ]; then
            local moved_to="${MP_HOST_SLOT}"
            if mp_migrate; then
                MP_HOST_NOTICE="${moved_to}"
                ready=0
                sel=0
                dirty=1
                continue
            fi
            mp_lobby_closed "failed"
            return 0
        fi
        if [ -n "${MP_CLOSED}" ]; then
            mp_lobby_closed "${MP_CLOSED}"
            return 0
        fi
        # Nothing from the hub for far too long: it is gone without
        # having said so (see mp_link_silent).
        if mp_link_silent; then
            mp_lobby_closed "silent"
            return 0
        fi
        # A handover that arrived: shown before the lobby is redrawn, so
        # nobody presses Enter on a menu that changed under their hands.
        # The ready flags were cleared by the hub with the handover, so
        # this end's copy has to go with them.
        if [ "${MP_HOST_NOTICE}" -ge 0 ]; then
            MP_HOST_NOTICE=-1
            ready=0
            sel=0
            # Who it went to is read from the session as it is now, not
            # from the slot the message named: after following a moved
            # session the slots have been handed out afresh.
            mp_host_notice "${MP_HOST_SLOT}"
            dirty=1
            continue
        fi
        if [ "${MP_PHASE}" = "start" ]; then
            mp_countdown
            if [ "${MP_PHASE}" = "play" ]; then
                mp_round
            fi
            return 0
        fi
        # The entries and what they do, built together: the host has one
        # more than everybody else, and hanging the dispatch below off a
        # position would break the moment that changes again.
        entries=()
        actions=()
        if [ "${MP_IS_HOST}" -eq 1 ]; then
            entries+=("${I18N[mp_start]}")
            actions+=("start")
            entries+=("${I18N[mp_settings]}")
            actions+=("settings")
        elif [ "${ready}" -eq 1 ]; then
            entries+=("${I18N[mp_unready]}")
            actions+=("ready")
        else
            entries+=("${I18N[mp_ready]}")
            actions+=("ready")
        fi
        entries+=("${I18N[mp_leave]}")
        actions+=("leave")
        if [ "${dirty}" -eq 1 ] || [ "${DIRTY}" -eq 1 ]; then
            DIRTY=0
            lines=("  ${I18N[mp_lobby_title]}" "")
            printf -v line "${I18N[mp_lobby_session]}" \
                "${MP_SESSION_NAME:-${MP_SESSION}}"
            lines+=("  ${line}")
            if [ "${MP_IS_HOST}" -eq 1 ] && [ "${MP_TRANSPORT}" = "lan" ]; then
                # The host's own address, so it can be read out to
                # somebody whose network swallows the beacon.
                printf -v line "${I18N[mp_lobby_addr]}" \
                    "${NET_LOCAL_ADDR:-?}" "${MP_PORT}"
                lines+=("  ${line}")
            fi
            # The session settings, shown to everybody and not only to
            # the host who set them: they decide how this round is won,
            # and a player who cannot see them is guessing (user
            # request). Only the host has the entry that changes them.
            mp_setting_lines
            lines+=("  ${MP_SETUP_MODE_LINE}")
            lines+=("  ${MP_SETUP_GARBAGE_LINE}")
            lines+=("")
            n=0
            for (( i = 0; i < MP_MAX; i++ )); do
                [ -n "${MP_PEER_NAME[i]}" ] || continue
                n=$(( n + 1 ))
                mp_lobby_line "${i}"
                lines+=("  ${MP_LOBBY_LINE}")
            done
            lines+=("")
            if [ "${MP_IS_HOST}" -eq 1 ] && [ "${n}" -lt 2 ]; then
                lines+=("  ${I18N[mp_lobby_alone]}")
            else
                lines+=("")
            fi
            for (( i = 0; i < ${#entries[@]}; i++ )); do
                if [ "${i}" -eq "${sel}" ]; then
                    lines+=($'  \e[7m '"${entries[i]}"$' \e[0m')
                else
                    lines+=("   ${entries[i]} ")
                fi
            done
            lines+=("" "  ${I18N[menu_nav]}")
            render_menu_frame "${lines[@]}"
            screen_write "${RENDER_MENU_FRAME}"
            dirty=0
        fi
        read_key
        if [ "${REDRAW_PENDING}" -eq 1 ]; then
            REDRAW_PENDING=0
            dirty=1
            continue
        fi
        case "${KEY}" in
            UP|w)   sel=$(( (sel + ${#entries[@]} - 1) % ${#entries[@]} )); dirty=1 ;;
            DOWN|s) sel=$(( (sel + 1) % ${#entries[@]} )); dirty=1 ;;
            ENTER|SPACE)
                case "${actions[sel]}" in
                    start)
                        proto_msg READY 1
                        net_send "${PROTO_LINE}" || :
                        dirty=1
                        ;;
                    ready)
                        ready=$(( 1 - ready ))
                        proto_msg READY "${ready}"
                        net_send "${PROTO_LINE}" || :
                        dirty=1
                        ;;
                    settings)
                        mp_settings_menu
                        dirty=1
                        ;;
                    *) left=1 ;;
                esac
                ;;
            ESC|x) left=1 ;;
        esac
        if [ "${left}" -eq 1 ]; then
            debug_event "mp: left the lobby"
            mp_disconnect
            MP_IS_HOST=0
            return 0
        fi
    done
}

# mp_host_notice
# Show that the lobby has changed hands and wait for it to be
# acknowledged (user request): the host who opened the session has left,
# and the player who joined first of those still there has inherited it.
# It has to be confirmed with Enter rather than dismissed by any key,
# because it is not a decoration: everybody's ready flag was cleared with
# the handover, and whoever inherited the lobby now has a start button
# where their "ready" entry used to be. A message that scrolls past on the
# next arrow key would leave them pressing Enter on something else than
# they think.
# Like every other wait in this file it keeps draining the link, so the
# hub does not lose a player who is reading.
mp_host_notice() {
    local -a lines
    local slot="${1}" dirty=1 line name i
    if [ "${slot}" -lt 0 ]; then
        slot=0
    fi
    name="${MP_PEER_NAME[slot]:-?}"
    while :; do
        if ! mp_poll; then
            return 0
        fi
        if [ -n "${MP_ERROR}" ] || [ "${MP_PHASE}" != "lobby" ]; then
            return 0
        fi
        # Anything that ends the session hands control straight back to
        # the lobby, which is where those cases are dealt with.
        if [ -n "${MP_CLOSED}" ] || [ -n "${MP_MOVE_ADDR}" ] \
            || mp_link_silent; then
            return 0
        fi
        if [ "${dirty}" -eq 1 ]; then
            lines=("  ${I18N[mp_host_left_title]}" "")
            i18n_lines mp_host_left_body
            for (( i = 0; i < ${#I18N_LINES[@]}; i++ )); do
                lines+=("  ${I18N_LINES[i]}")
            done
            lines+=("")
            if [ "${slot}" -eq "${MP_SLOT}" ]; then
                # The one who inherited it needs the plainer sentence: the
                # menu under this message is not the one they saw before.
                i18n_lines mp_host_you
            else
                printf -v line "${I18N[mp_host_new]}" "${name}"
                mapfile -t I18N_LINES <<< "${line}"
            fi
            for (( i = 0; i < ${#I18N_LINES[@]}; i++ )); do
                lines+=("  ${I18N_LINES[i]}")
            done
            lines+=("" "  ${I18N[mp_host_confirm]}")
            render_menu_frame "${lines[@]}"
            screen_write "${RENDER_MENU_FRAME}"
            dirty=0
        fi
        # The name of whoever took over can still be on its way when this
        # screen opens: after following a moved session the roster arrives
        # a moment after the welcome. Any message that changed something
        # therefore redraws the notice.
        if [ "${DIRTY}" -eq 1 ]; then
            DIRTY=0
            slot="${MP_HOST_SLOT}"
            name="${MP_PEER_NAME[slot]:-?}"
            dirty=1
        fi
        read_key
        if [ "${REDRAW_PENDING}" -eq 1 ]; then
            REDRAW_PENDING=0
            dirty=1
            continue
        fi
        # Enter only, as asked for: this is an acknowledgement, and every
        # other key in this lobby means something else.
        if [ "${KEY}" = "ENTER" ]; then
            return 0
        fi
    done
}

# mp_setting_lines
# The two lines that show the session settings, in
# MP_SETUP_MODE_LINE / MP_SETUP_GARBAGE_LINE: the mode with the win
# condition it stands for, and whether garbage is on. The win condition is
# spelled out rather than left to the mode's name - "Sprint" says how long
# a round lasts, not who wins it, and that is the question a player in a
# lobby is asking.
MP_SETUP_MODE_LINE=""
MP_SETUP_GARBAGE_LINE=""
mp_setting_lines() {
    local state
    printf -v MP_SETUP_MODE_LINE "${I18N[mp_setup_mode]}" \
        "${I18N[mpmode_${MP_MODE}]}" "${I18N[mpwin_${MP_MODE}]}"
    if [ "${MP_GARBAGE}" -eq 1 ]; then
        state="${I18N[mp_on]}"
    else
        state="${I18N[mp_off]}"
    fi
    printf -v MP_SETUP_GARBAGE_LINE "${I18N[mp_setup_garbage]}" "${state}"
    return 0
}

# mp_settings_menu
# The host's settings menu, opened from the lobby. Enter switches the
# entry it stands on - the mode cycles through MP_MODES, the garbage
# switch flips - and every change goes to the hub at once, which sends it
# back to everybody. Changing them is therefore never a private decision:
# the lobby of every player shows the new state the moment it is made.
# Like the lobby it keeps draining the link while it is open, for the same
# reason (a menu that stops reading runs into the ping timeout).
# The two limits that make a mode what it is - the Sprint time and the
# Ultra target - are the singleplayer constants and are shown as such, so
# a retuned SPRINT_TIME_MS cannot leave this screen lying.
mp_settings_menu() {
    local -a lines entries
    local sel=0 dirty=1 i line
    while :; do
        if ! mp_poll; then
            return 0
        fi
        if [ -n "${MP_ERROR}" ] || [ "${MP_PHASE}" != "lobby" ]; then
            # The round started or the session died while this was open.
            return 0
        fi
        # The session moved, ended or went quiet while this was open: the
        # lobby behind this menu is where all three are handled.
        if [ -n "${MP_CLOSED}" ] || [ -n "${MP_MOVE_ADDR}" ] \
            || mp_link_silent; then
            return 0
        fi
        mp_setting_lines
        entries=("${MP_SETUP_MODE_LINE}" "${MP_SETUP_GARBAGE_LINE}"
                 "${I18N[menu_back]}")
        if [ "${dirty}" -eq 1 ] || [ "${DIRTY}" -eq 1 ]; then
            DIRTY=0
            lines=("  ${I18N[mp_settings_title]}" "")
            i18n_lines mp_settings_body
            for (( i = 0; i < ${#I18N_LINES[@]}; i++ )); do
                lines+=("  ${I18N_LINES[i]}")
            done
            lines+=("")
            for (( i = 0; i < ${#entries[@]}; i++ )); do
                if [ "${i}" -eq "${sel}" ]; then
                    lines+=($'  \e[7m '"${entries[i]}"$' \e[0m')
                else
                    lines+=("   ${entries[i]} ")
                fi
            done
            lines+=("")
            # What the picked mode costs to win, from the live constants.
            case "${MP_MODE}" in
                sprint)
                    fmt_duration $(( SPRINT_TIME_MS / 1000 ))
                    printf -v line "${I18N[mp_setup_limit_sprint]}" \
                        "${FMT_DURATION}"
                    ;;
                ultra)
                    printf -v line "${I18N[mp_setup_limit_ultra]}" \
                        "${ULTRA_TARGET_ROWS}"
                    ;;
                *) line="" ;;
            esac
            lines+=("  ${line}")
            lines+=("" "  ${I18N[mp_settings_nav]}")
            render_menu_frame "${lines[@]}"
            screen_write "${RENDER_MENU_FRAME}"
            dirty=0
        fi
        read_key
        if [ "${REDRAW_PENDING}" -eq 1 ]; then
            REDRAW_PENDING=0
            dirty=1
            continue
        fi
        case "${KEY}" in
            UP|w)   sel=$(( (sel + ${#entries[@]} - 1) % ${#entries[@]} )); dirty=1 ;;
            DOWN|s) sel=$(( (sel + 1) % ${#entries[@]} )); dirty=1 ;;
            ENTER|SPACE|LEFT|RIGHT)
                case "${sel}" in
                    0) mp_settings_cycle_mode "${KEY}" ;;
                    1) MP_GARBAGE=$(( 1 - MP_GARBAGE )); mp_settings_send ;;
                    *)
                        if [ "${KEY}" = "ENTER" ] || [ "${KEY}" = "SPACE" ]; then
                            return 0
                        fi
                        ;;
                esac
                dirty=1
                ;;
            ESC|x) return 0 ;;
        esac
    done
}

# mp_settings_cycle_mode KEY
# Step to the next (or, on the left arrow, the previous) mode and send it.
mp_settings_cycle_mode() {
    local key="${1}" i idx=0 n="${#MP_MODES[@]}"
    for (( i = 0; i < n; i++ )); do
        if [ "${MP_MODES[i]}" = "${MP_MODE}" ]; then
            idx="${i}"
            break
        fi
    done
    if [ "${key}" = "LEFT" ]; then
        idx=$(( (idx + n - 1) % n ))
    else
        idx=$(( (idx + 1) % n ))
    fi
    MP_MODE="${MP_MODES[idx]}"
    mp_settings_send
    return 0
}

# mp_settings_send
# Hand the settings to the hub. Only the host ever gets here (the entry
# exists nowhere else), and the hub checks that again - a client that says
# it is the host is not one.
mp_settings_send() {
    proto_msg SETUP "${MP_MODE}" "${MP_GARBAGE}"
    net_send "${PROTO_LINE}" || :
    debug_event "mp: host set mode=${MP_MODE} garbage=${MP_GARBAGE}"
    return 0
}

# mp_lobby_line SLOT
# One player's line in the lobby, in MP_LOBBY_LINE: the slot, the name,
# whether they are ready, and a marker on our own entry so everybody can
# find themselves. The name is clamped again here even though it came
# through the parser - the hub is not trusted either (CLAUDE.md 5.5).
MP_LOBBY_LINE=""
mp_lobby_line() {
    local slot="${1}" name mark="" state
    name="${MP_PEER_NAME[slot]:0:16}"
    if [ "${slot}" -eq "${MP_SLOT}" ]; then
        mark="${I18N[mp_you]}"
    fi
    if [ "${slot}" -eq 0 ]; then
        state="${I18N[mp_is_host]}"
    elif [ "${MP_PEER_READY[slot]}" -eq 1 ]; then
        state="${I18N[mp_is_ready]}"
    else
        state="${I18N[mp_is_waiting]}"
    fi
    printf -v MP_LOBBY_LINE '%d. %-16s %-10s %s' \
        "$(( slot + 1 ))" "${name}" "${state}" "${mark}"
    return 0
}

# mp_countdown
# The moment between "start" and the first piece: the hub named a point
# in time, and every client counts down to it, so the round really starts
# for everybody at once. The link keeps being drained meanwhile - a
# player leaving during the countdown is news the others need.
mp_countdown() {
    local -a lines
    local left line
    while :; do
        # The clock first, the link afterwards. The other way round the
        # last pass of this loop would drain the link once more after the
        # round has begun - key_drain below waits up to 100 ms, so that
        # pass can sit well past the starting point - and the first moves
        # of everybody else would be read here, where the round state and
        # with it the recording of it does not exist yet. They are simply
        # left in the socket buffer instead; the game loop reads them a
        # moment later, with the recording running. Nothing is missed by
        # not polling for that last stretch either: nobody can move
        # before MP_START_MS, and a link that dies in it is noticed by
        # the game loop on its first pass.
        now_ms
        left=$(( MP_START_MS - NOW_MS ))
        if [ "${left}" -le 0 ]; then
            break
        fi
        if ! mp_poll; then
            mp_lobby_lost
            return 0
        fi
        if mp_link_silent; then
            mp_lobby_lost
            MP_PHASE="lobby"
            return 0
        fi
        printf -v line "${I18N[mp_countdown]}" "$(( (left + 999) / 1000 ))"
        lines=("  ${I18N[mp_lobby_title]}" "" "  ${line}")
        render_menu_frame "${lines[@]}"
        screen_write "${RENDER_MENU_FRAME}"
        key_drain 100
    done
    MP_PHASE="play"
    MP_STATE="play"
    debug_event "mp: round starts"
    return 0
}

# mp_pause_menu
# The pause menu of a multiplayer round: two entries instead of four.
# "Suspend into the main menu" is missing because there is nothing to
# come back to - the others do not wait - and there is no restart for the
# same reason (see handle_key in rowhammer.sh).
# It keeps draining the link on every pass, which is the whole reason it
# is not menu_pause: a menu that stops reading for as long as somebody
# stares at it would let the hub's ping time out and get this client
# dropped from a round it never meant to leave. The board is frozen
# meanwhile, and the screen says as much - the opponents keep playing,
# so this is not a pause, it is a decision to make quickly.
mp_pause_menu() {
    local -a lines
    local sel=0 dirty=1 i
    local -a entries
    entries=("${I18N[main_resume]}" "${I18N[pause_end]}")
    while :; do
        if ! mp_poll; then
            # The link died while the menu was open: leave the round, the
            # game loop notices the same thing on its next pass.
            return 0
        fi
        if [ "${MP_ENDED}" -eq 1 ]; then
            # The round was decided while the menu was open. Back to the
            # board, where the result box is waiting.
            return 0
        fi
        if [ "${dirty}" -eq 1 ]; then
            lines=("  ${I18N[pause_title]}" "")
            i18n_lines mp_pause_note
            for (( i = 0; i < ${#I18N_LINES[@]}; i++ )); do
                lines+=("  ${I18N_LINES[i]}")
            done
            lines+=("")
            for (( i = 0; i < ${#entries[@]}; i++ )); do
                if [ "${i}" -eq "${sel}" ]; then
                    lines+=($'  \e[7m '"${entries[i]}"$' \e[0m')
                else
                    lines+=("   ${entries[i]} ")
                fi
            done
            lines+=("" "  ${I18N[menu_nav]}")
            render_menu_frame "${lines[@]}"
            screen_write "${RENDER_MENU_FRAME}"
            dirty=0
        fi
        read_key
        if [ "${REDRAW_PENDING}" -eq 1 ]; then
            REDRAW_PENDING=0
            dirty=1
            continue
        fi
        case "${KEY}" in
            UP|DOWN|w|s) sel=$(( 1 - sel )); dirty=1 ;;
            ENTER|SPACE)
                if [ "${sel}" -eq 1 ]; then
                    # Leaving a running round is leaving it for good, so
                    # it is confirmed like the same entry in the
                    # singleplayer pause menu.
                    if mp_confirm_leave; then
                        GAME_EXIT=1
                        return 0
                    fi
                    dirty=1
                else
                    return 0
                fi
                ;;
            ESC|x) return 0 ;;
        esac
    done
}

# mp_confirm_leave
# Ask before a running multiplayer round is thrown away, the way the
# singleplayer pause menu asks - with the state of the round, so the
# question is answerable, and with "no" preselected. The link is drained
# in this loop too, for the reason mp_pause_menu drains it.
mp_confirm_leave() {
    local -a lines
    local sel=0 dirty=1 round_line i
    printf -v round_line "${I18N[round_state]}" \
        "${CLEARED_TOTAL}" "${ROW_CREDIT}" "${LEVEL}"
    while :; do
        mp_poll || return 0
        if [ "${dirty}" -eq 1 ]; then
            lines=("  ${I18N[end_title]}" "" "  ${I18N[end_head]}"
                   "  ${round_line}" "")
            i18n_lines mp_end_tail
            for (( i = 0; i < ${#I18N_LINES[@]}; i++ )); do
                lines+=("  ${I18N_LINES[i]}")
            done
            lines+=("")
            if [ "${sel}" -eq 0 ]; then
                lines+=($'  \e[7m '"${I18N[confirm_no]}"$' \e[0m')
                lines+=("   ${I18N[end_yes]} ")
            else
                lines+=("   ${I18N[confirm_no]} ")
                lines+=($'  \e[7m '"${I18N[end_yes]}"$' \e[0m')
            fi
            lines+=("" "  ${I18N[menu_nav_cancel]}")
            render_menu_frame "${lines[@]}"
            screen_write "${RENDER_MENU_FRAME}"
            dirty=0
        fi
        read_key
        if [ "${REDRAW_PENDING}" -eq 1 ]; then
            REDRAW_PENDING=0
            dirty=1
            continue
        fi
        case "${KEY}" in
            UP|DOWN|w|s) sel=$(( 1 - sel )); dirty=1 ;;
            ENTER|SPACE)
                if [ "${sel}" -eq 1 ]; then
                    return 0
                fi
                return 1
                ;;
            ESC|x) return 1 ;;
        esac
    done
}

# mp_round
# Play the round and clean up after it. The session ends with the round:
# there is no way back into the lobby, because the others have left it
# long ago - a second round is a second session, which is one menu entry
# away. The construction site is shown afterwards like after any other
# round: the rows were really cleared, so they built the wonder (see
# CLAUDE.md 5.8 on what a multiplayer round counts towards).
mp_round() {
    game_run versus
    mp_disconnect
    MP_IS_HOST=0
    wonder_screen "${TOTAL_ROW_CREDIT}"
    return 0
}

# mp_join_target TARGET
# Join the session TARGET names without going through the search: an
# address "host" or "host:port" in the lan transport, a session name in
# the unix one. This is what --mp-join uses, and it is the only way to
# tell a bot where to play. The input is split and checked exactly like
# an address that came off the network.
mp_join_target() {
    local target="${1}" host port
    if [ "${MP_TRANSPORT}" = "unix" ]; then
        mp_connect_unix "${target}"
        return $?
    fi
    host="${target%%:*}"
    port="${MP_PORT}"
    if [[ "${target}" == *:* ]]; then
        port="${target##*:}"
    fi
    net_host_ok "${host}" || return 1
    net_port_ok "${port}" || return 1
    mp_connect_host "${host}" "${port}"
}

# --- Test bot -------------------------------------------------------------
# How long a bot sits in the lobby before it asks for the round to start.
# Only the bot that happens to be slot 0 can start one at all, and this is
# the window everybody else has to join in.
MP_BOT_LOBBY_MS=5000

# mp_bot_column
# Where the bot drops its next piece, in MP_BOT_COLUMN: the emptiest
# column of its board, ties broken at random. That is barely a strategy,
# and it is not meant to be one - but it does complete a row now and
# then, which a bot dropping into random columns practically never does.
# Without that the bot could not exercise the half of the multiplayer
# that only starts at the first clear: the attack arithmetic, the queue
# and the cancelling.
MP_BOT_COLUMN=0
mp_bot_column() {
    local x y best=-1 h
    local -a candidates=()
    for (( x = 0; x < BOARD_W; x++ )); do
        h=0
        for (( y = HIDDEN_ROWS; y < BOARD_H; y++ )); do
            if [ "${BOARD[y * BOARD_W + x]}" != "${EMPTY_CELL}" ]; then
                h=$(( BOARD_H - y ))
                break
            fi
        done
        if [ "${best}" -lt 0 ] || [ "${h}" -lt "${best}" ]; then
            best="${h}"
            candidates=("${x}")
        elif [ "${h}" -eq "${best}" ]; then
            candidates+=("${x}")
        fi
    done
    MP_BOT_COLUMN="${candidates[RANDOM % ${#candidates[@]}]}"
    # The target is the piece's origin, and a piece is up to four cells
    # wide, so an origin beyond this is never reachable. Clamping it here
    # is cheaper than teaching the bot the shape table, and it keeps
    # every choice a move it can actually carry out.
    if [ "${MP_BOT_COLUMN}" -gt $(( BOARD_W - 4 )) ]; then
        MP_BOT_COLUMN=$(( BOARD_W - 4 ))
    fi
    return 0
}

# mp_bot_main
# The body of --mp-bot: a client without a terminal that joins a session
# and plays badly but legally, so a round with six players can be tested
# without six terminals (roadmap step 11).
# It runs its own loop rather than game_run: that loop is paced by
# read_key on the terminal, and a bot has none - a read on a closed stdin
# would be a fatal error there. Everything below it is the real game
# though: the same board, the same pieces, the same locking and the same
# messages, which is what makes it a useful test partner rather than a
# traffic generator.
mp_bot_main() {
    local target="${MP_JOIN}" tick=0 want_x=0 want_rot=0
    net_require || die "socat is required for --mp-bot (package: socat)"
    [ -n "${target}" ] || die "--mp-bot needs --mp-join HOST[:PORT]"
    # No terminal, so nothing may draw. The clear animation is the one
    # part of the game logic that renders on its own; switching it off is
    # what keeps this loop silent (see flash_rows in rowhammer.sh).
    FLASH_CYCLES=0
    # And nothing may be kept either: a bot's rounds are test traffic,
    # and their recordings would sit in a data directory as real ones,
    # counting against DEMO_MAX and pushing out rounds somebody played.
    # Switched off here rather than asked for at the call site, so a bot
    # is off the books whatever --demo-record says.
    DEMO_RECORD="off"
    if ! mp_join_target "${target}"; then
        die "bot could not join ${target}"
    fi
    # The first "ready" waits MP_BOT_LOBBY_MS and is then repeated every
    # second. Both halves are needed for a test with more than two bots:
    # whichever bot connects first is the host of the session, and a host
    # that asks to start the moment a second player appears would slam
    # the door on everybody still joining (the hub refuses a late join
    # into a running round). The repeat is for the other side of it - the
    # very first request, while the bot is still alone, is refused with
    # ERR alone.
    now_ms
    local next_ready=$(( NOW_MS + MP_BOT_LOBBY_MS ))
    while [ "${MP_PHASE}" != "start" ] && [ "${MP_PHASE}" != "play" ]; do
        mp_poll || { mp_disconnect; return 0; }
        # An "alone" refusal is not a reason to give up - it is the
        # answer to a question asked too early.
        if [ "${MP_ERROR}" = "err:alone" ]; then
            MP_ERROR=""
        fi
        [ -z "${MP_ERROR}" ] || { mp_disconnect; return 0; }
        # The host left and the session moved: follow it, exactly as a
        # player's lobby does. A bot that stayed behind would be testing
        # the one path that no longer exists.
        if [ -n "${MP_MOVE_ADDR}" ]; then
            if ! mp_migrate; then
                debug_event "bot: could not follow the moved session"
                mp_disconnect
                return 0
            fi
            next_ready=0
            continue
        fi
        if [ -n "${MP_CLOSED}" ] || mp_link_silent; then
            debug_event "bot: session closed (${MP_CLOSED:-silent})"
            mp_disconnect
            return 0
        fi
        now_ms
        if (( NOW_MS >= next_ready )); then
            next_ready=$(( NOW_MS + 1000 ))
            proto_msg READY 1
            net_send "${PROTO_LINE}" || :
        fi
        mp_wait_ms 100
    done
    while :; do
        mp_poll || break
        now_ms
        (( NOW_MS >= MP_START_MS )) || { mp_wait_ms 50; continue; }
        break
    done
    MP_PHASE="play"
    MP_STATE="play"
    game_reset versus
    while :; do
        mp_poll || break
        if [ "${MP_ENDED}" -eq 1 ] || mp_link_silent; then
            break
        fi
        play_clock_tick
        if [ "${GAME_OVER}" -eq 0 ]; then
            # One decision per piece: a target column and a rotation,
            # both drawn at random. Then one step towards it per tick and
            # a hard drop once it is reached - which produces a stack
            # that fills up at a believable pace.
            if [ "${tick}" -eq 0 ]; then
                mp_bot_column
                want_x="${MP_BOT_COLUMN}"
                want_rot=$(( RANDOM % 4 ))
            fi
            tick=$(( tick + 1 ))
            # A blocked move or rotation ends the plan instead of being
            # retried: the target column is chosen without looking at the
            # piece's width, so the right-hand columns are regularly out
            # of reach, and a bot that kept pushing against the wall
            # would never drop another piece.
            # Announced through the same funnel a player's keys go
            # through, so a bot produces a real move stream: without it
            # the streams could only ever be tested with as many
            # terminals as players (CLAUDE.md 5.20).
            if [ "${CUR_ROT}" -ne "${want_rot}" ]; then
                round_event c
                try_rotate 1 || want_rot="${CUR_ROT}"
            elif [ "${CUR_X}" -gt "${want_x}" ]; then
                round_event l
                try_move -1 0 || want_x="${CUR_X}"
            elif [ "${CUR_X}" -lt "${want_x}" ]; then
                round_event r
                try_move 1 0 || want_x="${CUR_X}"
            else
                round_event h
                hard_drop
                tick=0
            fi
            mp_send_state
            mp_act_flush
            # Snapshots too, when somebody is drawing them: a bot that
            # showed up as an empty board would make the mini board view
            # untestable without a second terminal.
            mp_send_board
        fi
        mp_wait_ms 50
    done
    debug_event "bot: session over (rows=${ROW_CREDIT} lines=${CLEARED_TOTAL} place=${MP_PLACE})"
    mp_disconnect
    return 0
}

# mp_lobby_closed REASON
# The session is over while we were waiting in its lobby, and the reason
# is known: the host left and nobody could take over ("host"), the
# takeover failed ("failed"), or the hub stopped answering ("silent").
# Told apart on screen because they are told apart by the player: the
# first is somebody's decision, the other two are a fault.
mp_lobby_closed() {
    local reason="${1}"
    local -a body
    case "${reason}" in
        host)   i18n_lines mp_closed_host ;;
        failed) i18n_lines mp_closed_failed ;;
        *)      i18n_lines mp_closed_silent ;;
    esac
    body=("${I18N_LINES[@]}")
    debug_event "mp: lobby closed (${reason})"
    mp_disconnect
    MP_IS_HOST=0
    menu_message "${I18N[main_multi]}" "${body[@]}"
    return 0
}

# mp_lobby_lost
# The hub is gone while we were waiting. Nothing was played, so nothing is
# recorded; the message says what happened and the menu takes over again.
mp_lobby_lost() {
    local -a body
    i18n_lines mp_lost_body
    body=("${I18N_LINES[@]}")
    mp_disconnect
    MP_IS_HOST=0
    menu_message "${I18N[main_multi]}" "${body[@]}"
    return 0
}
