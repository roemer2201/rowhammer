#!/usr/bin/env bash
#
# lib/hub.sh
#
# Description:
#   Session logic of the rowhammer multiplayer: the hub (CLAUDE.md 5.3).
#   It runs as its own process, started in the background by the host's
#   client ("rowhammer.sh --mp-hub"), and it is headless on purpose - no
#   terminal, no rendering, no stty, none of the game's signal handlers.
#   A hanging client can therefore never block the hub and a hanging hub
#   never the host's own round.
#   The hub is the only authority on the things a client must not be able
#   to decide for itself: how much garbage a clear is worth, which column
#   its gap sits in, who receives it, in which order players are knocked
#   out and when the round is over. Clients report events (CLEAR, TOPOUT),
#   never consequences.
#   It also keeps the session settings the host picks in the lobby (SETUP,
#   since 1.1.0): the mode - survival, sprint or ultra, which is to say
#   who wins - and whether garbage flies at all. They are taken from the
#   host only and only while no round is running, and they are what
#   hub_end_round asks when it has to name a winner. The host is a slot
#   the hub names (HUB_HOST_SLOT, since 1.2.0): when its holder leaves,
#   the lobby passes to whoever joined first of those still there, and
#   everybody's ready flag is cleared with it.
#   It speaks to nobody directly. socat listens (TCP4-LISTEN in the "lan"
#   transport, UNIX-LISTEN in "unix") and starts one bridge process per
#   connection ("rowhammer.sh --mp-bridge"); the bridge has the socket on
#   its standard input and output and translates between it and two FIFOs:
#   every client writes into the one shared inbox with its id in front,
#   and reads from a private "down" FIFO of its own. That way the hub only
#   ever talks to FIFOs, which bash can do natively, socat only ever to
#   sockets, and switching the transport changes exactly one string.
#   Lines are short enough (MP_LINE_MAX, 512 bytes) that a write into the
#   shared inbox is atomic, which is what lets several bridges share it.
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 1.2.1  (2026-09-05)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/hub.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# --- Garbage values -------------------------------------------------------
# What a clear is worth as an attack. The row counts mirror the game's own
# row credit (1 / +5 silver / +10 gold, see CLAUDE.md 3.2) in halved form,
# so the mechanic that decides a singleplayer round decides a duel too:
# a Tetris is worth four rows, and a gold square doubles it. Tunable
# constants like ULTRA_TARGET_ROWS - the numbers come from the row credit,
# not from the original (The New Tetris has no comparable versus mode),
# and are to be retuned after playtesting.
GARBAGE_LINES=(0 0 1 2 4)
GARBAGE_SILVER=2
GARBAGE_GOLD=4
GARBAGE_CAP=10

# Countdown between the host pressing start and the first piece falling,
# in milliseconds. Long enough that everybody has their eyes on the board,
# short enough not to be a wait.
HUB_COUNTDOWN_MS=3000

# How many messages the hub takes out of the inbox before it does its
# periodic work once. A flood from one client can therefore delay the
# ping/timeout pass by at most this many messages, never stall it.
HUB_BATCH_MAX=64

# How many malformed messages in a row cost a client its connection.
HUB_BAD_MAX=3

# How long the successor has to start a hub of their own after the host
# left (PROMOTE -> PROMOTED). Starting one is a fork, a bind and a moment
# of waiting; three seconds is far more than that and still short enough
# that nobody wonders whether the game has hung.
HUB_PROMOTE_MS=3000

# How long this hub keeps running after its last message before it exits,
# so the bridges can push that message out (see hub_stop_soon).
HUB_STOP_GRACE_MS=500

# The head start the new host gets before the others are sent after them
# (see hub_msg_promoted). Long enough that no client on this machine can
# make it up, short enough that nobody sees a pause.
HUB_MIGRATE_DELAY_MS=500

# --- Session state --------------------------------------------------------
# One entry per slot (0 .. MP_MAX-1). A free slot has an empty HUB_ID.
HUB_ID=()
HUB_NAME=()
HUB_READY=()
HUB_STATE=()
HUB_ROWS=()
HUB_LINES=()
HUB_LEVEL=()
HUB_GOLD=()
HUB_SILVER=()
HUB_HEIGHT=()
HUB_PENDING=()
# Whether a slot wants to *receive* board snapshots (it draws the mini
# boards), and what this hub last told it about *sending* them. Two
# different questions, and neither follows from the other: a client sends
# snapshots exactly when some other client is drawing them.
HUB_WANTBOARD=()
HUB_NEEDBOARD=()
# The order the players joined in, as a counter per slot. Slots are handed
# out lowest-free-first, so a slot number is not a join order once
# somebody has left and their place has been taken again - and the join
# order is exactly what decides who inherits the lobby (hub_migrate_begin).
HUB_JOINED=()
# The address each connection came from (the bridge reports it), or "-"
# when there is none - the unix transport has no addresses, and there the
# session is a socket path on the one machine everybody is on anyway.
HUB_ADDR=()
HUB_PLACE=()
HUB_LAST_MS=()
HUB_OPEN_MS=()
HUB_HELLO=()
HUB_BAD=()

# Bridge id -> slot. The id is the bridge's process id, which is unique
# for as long as the connection lives.
declare -A HUB_SLOT_OF_ID=()

# The session settings, decided by the host in the lobby and sent to
# everybody (see hub_msg_setup): the mode of the round and whether
# cleared rows send garbage.
# "survival" is the default because it is the mode that needs no
# explaining - play until your field is full, the last one left wins -
# and garbage is **off** by default (user decision): a duel in which
# somebody else fills your board is the more demanding game, and it
# should be something the host switches on rather than something a
# first-time player is handed without being asked.
# The two values start from what the host's command line said
# (--mp-mode / --mp-garbage, see rowhammer.sh); from then on the settings
# menu in the lobby owns them.
HUB_MODE="${MP_MODE_OPT:-survival}"
HUB_GARBAGE=0
if [ "${MP_GARBAGE_OPT:-off}" = "on" ]; then
    HUB_GARBAGE=1
fi

# Session-wide state: whether the loop runs, whether the round is on,
# the roster's "something changed" flag and the timestamps of the periodic
# work. HUB_ROUND_END_MS is the moment the sprint mode's clock runs out
# (0 in the modes that have no clock).
HUB_RUN=1
HUB_PLAYING=0
HUB_ROUND_END_MS=0
# Which slot runs the lobby, and the counter the join order is taken from.
# -1 means the session has nobody in it yet; the first client to identify
# itself becomes the host. It is a slot the hub names rather than the
# fixed slot 0 it used to be, because the role has to be able to move on
# when its holder leaves (user request, 1.2.0).
HUB_HOST_SLOT=-1
HUB_JOIN_SEQ=0
# The handover, once the host has left: which slot was asked to start a
# hub of its own, when that question was asked, and the moment this hub
# gives up waiting and closes the session instead. While
# HUB_PROMOTED_SLOT is set the session is on its way out either way -
# this hub ends as soon as the new one has taken it over, or as soon as
# it is clear that nobody did.
HUB_PROMOTED_SLOT=-1
HUB_PROMOTE_DEADLINE_MS=0
# The MIGRATE for everybody else, written the moment the successor
# answered and sent a moment later (hub_migrate_finish).
HUB_MIGRATE_LINE=""
HUB_MIGRATE_SLOT=-1
HUB_MIGRATE_AT_MS=0
# When this hub stops, once it has said everything it has to say. A hub
# that quit the instant it sent MIGRATE would take the message with it:
# the bridges still have to push it through their sockets.
HUB_STOP_AT_MS=0
HUB_ROSTER_DIRTY=1
HUB_NEXT_BEACON_MS=0
HUB_NEXT_PING_MS=0
HUB_PING_TOKEN=0
HUB_INBOX_PATH=""
HUB_DOWN_PREFIX=""
# The beginning of a line the inbox read did not get to the end of, kept
# until the rest of it arrives (see hub_main). The same buffer the
# client's receive path keeps for the same reason (NET_PART in net_poll,
# lib/net.sh).
HUB_INBOX_PART=""
HUB_SOCAT_PID=0
HUB_LISTEN_PATH=""

# hub_slot_free
# Index of the first free slot in HUB_FREE_SLOT, or -1 when the session is
# full. Slots are handed out low first, which is why the first player to
# arrive is slot 0 - but only until somebody leaves and their place is
# taken again, so who runs the lobby is a slot of its own
# (HUB_HOST_SLOT) and not "slot 0".
HUB_FREE_SLOT=-1
hub_slot_free() {
    local i
    HUB_FREE_SLOT=-1
    for (( i = 0; i < MP_MAX; i++ )); do
        if [ -z "${HUB_ID[i]}" ]; then
            HUB_FREE_SLOT="${i}"
            return 0
        fi
    done
    return 1
}

# hub_slot_reset SLOT
# Put a slot back into its empty state.
hub_slot_reset() {
    local s="${1}"
    HUB_ID[s]=""
    HUB_NAME[s]=""
    HUB_READY[s]=0
    HUB_STATE[s]="lobby"
    HUB_ROWS[s]=0
    HUB_LINES[s]=0
    HUB_LEVEL[s]=0
    HUB_GOLD[s]=0
    HUB_SILVER[s]=0
    HUB_HEIGHT[s]=0
    HUB_PENDING[s]=0
    HUB_WANTBOARD[s]=0
    HUB_NEEDBOARD[s]=0
    HUB_PLACE[s]=0
    HUB_LAST_MS[s]=0
    HUB_OPEN_MS[s]=0
    HUB_JOINED[s]=0
    HUB_ADDR[s]="-"
    HUB_HELLO[s]=0
    HUB_BAD[s]=0
    return 0
}

# hub_count_players
# Number of occupied slots in HUB_PLAYERS, and of those still in play in
# HUB_ALIVE. "In play" means the player has a running round: in the lobby
# everybody counts, during the round the ones that are neither knocked out
# nor gone.
HUB_PLAYERS=0
HUB_ALIVE=0
hub_count_players() {
    local i
    HUB_PLAYERS=0
    HUB_ALIVE=0
    for (( i = 0; i < MP_MAX; i++ )); do
        [ -n "${HUB_ID[i]}" ] || continue
        HUB_PLAYERS=$(( HUB_PLAYERS + 1 ))
        case "${HUB_STATE[i]}" in
            ko|gone) : ;;
            *) HUB_ALIVE=$(( HUB_ALIVE + 1 )) ;;
        esac
    done
    return 0
}

# --- Sending --------------------------------------------------------------
# hub_send SLOT LINE
# Write one message into the private down FIFO of a slot. Every caller
# appends "|| :": a slot whose bridge has just gone away makes this
# return 1, and the hub runs under set -e - a client leaving in the wrong
# millisecond must not take the session down with it. The FIFO is
# opened read-write for the single write, which never blocks on a missing
# reader and needs no descriptor bookkeeping - the hub sends a handful of
# short lines per client and tick, so the open costs nothing that matters.
# A slot whose FIFO is gone has lost its bridge; it is dropped.
hub_send() {
    local slot="${1}" line="${2}" fifo
    [ -n "${HUB_ID[slot]}" ] || return 1
    fifo="${HUB_DOWN_PREFIX}.${HUB_ID[slot]}"
    if [ ! -p "${fifo}" ]; then
        hub_client_close "${HUB_ID[slot]}"
        return 1
    fi
    net_line_ok "${line}" || return 1
    if ! printf '%s\n' "${line}" 1<>"${fifo}" 2>/dev/null; then
        return 1
    fi
    net_log "tx>${slot}" "${line}"
    return 0
}

# hub_bcast LINE [EXCEPT_SLOT]
# Send to every occupied slot, optionally skipping one - which is what
# every peer update needs: a player is not their own peer.
hub_bcast() {
    local line="${1}" except="${2:--1}" i
    for (( i = 0; i < MP_MAX; i++ )); do
        [ -n "${HUB_ID[i]}" ] || continue
        [ "${i}" -ne "${except}" ] || continue
        hub_send "${i}" "${line}" || :
    done
    return 0
}

# hub_roster_send
# Send the whole player list to everybody: one ROSTER line per occupied
# slot. Sent on every change rather than on a timer, because the lobby is
# the one screen where a change has to show up at once.
hub_roster_send() {
    local i
    for (( i = 0; i < MP_MAX; i++ )); do
        [ -n "${HUB_ID[i]}" ] || continue
        # A connection that has not said HELLO yet has no name, and a
        # roster line without one is not a valid message - the receiving
        # parser would throw it away. It is also nothing anybody wants to
        # see: a slot is a player once it has a name.
        [ -n "${HUB_NAME[i]}" ] || continue
        proto_msg ROSTER "${i}" "${HUB_NAME[i]}" "${HUB_READY[i]}" \
            "${HUB_STATE[i]}"
        hub_bcast "${PROTO_LINE}"
    done
    HUB_ROSTER_DIRTY=0
    return 0
}

# --- Connection handling --------------------------------------------------
# hub_client_open ID
# A bridge announced a new connection. The slot is taken here, before a
# HELLO has arrived, so the session cannot be filled past MP_MAX by
# clients that never identify themselves; a slot that stays silent is
# released again by the HELLO deadline in hub_periodic.
hub_client_open() {
    local id="${1}" slot
    if ! hub_slot_free; then
        proto_msg ERR full "session is full"
        # No slot, so no hub_send: write straight to the bridge's FIFO.
        local fifo="${HUB_DOWN_PREFIX}.${id}"
        if [ -p "${fifo}" ]; then
            printf '%s\n' "${PROTO_LINE}" 1<>"${fifo}" 2>/dev/null || :
        fi
        debug_event "hub: connection ${id} refused, session full"
        return 0
    fi
    slot="${HUB_FREE_SLOT}"
    hub_slot_reset "${slot}"
    HUB_ID[slot]="${id}"
    now_ms
    HUB_OPEN_MS[slot]="${NOW_MS}"
    HUB_LAST_MS[slot]="${NOW_MS}"
    HUB_SLOT_OF_ID["${id}"]="${slot}"
    HUB_JOIN_SEQ=$(( HUB_JOIN_SEQ + 1 ))
    HUB_JOINED[slot]="${HUB_JOIN_SEQ}"
    debug_event "hub: connection ${id} -> slot ${slot} (join #${HUB_JOINED[slot]})"
    return 0
}

# hub_client_close ID
# A connection ended (bridge EOF, a dropped client, a missing FIFO). In
# the lobby the slot is simply freed; during a round the player counts as
# knocked out, so the round can finish without them (CLAUDE.md 5.8) - and
# their slot stays occupied, because the others are still looking at it.
hub_client_close() {
    local id="${1}" slot
    slot="${HUB_SLOT_OF_ID[${id}]:-}"
    [ -n "${slot}" ] || return 0
    unset "HUB_SLOT_OF_ID[${id}]"
    proto_rate_forget "${id}"
    if [ "${HUB_PLAYING}" -eq 1 ] && [ "${HUB_STATE[slot]}" = "play" ]; then
        debug_event "hub: slot ${slot} (${HUB_NAME[slot]}) lost the connection during the round"
        hub_eliminate "${slot}" "gone"
        # The slot keeps its name and figures so the others still see who
        # it was; only the id is cleared, so nothing is sent there again.
        HUB_ID[slot]=""
        # No handover during a round: the settings are frozen, the round
        # plays itself out for everybody who is left, and moving the
        # session to another machine mid-round would mean every board
        # reconnecting in the middle of a duel. The host slot is simply
        # vacated; the round ends the session anyway.
        if [ "${slot}" -eq "${HUB_HOST_SLOT}" ]; then
            HUB_HOST_SLOT=-1
            debug_event "hub: the host left during the round; no handover until it is over"
        fi
        return 0
    fi
    debug_event "hub: slot ${slot} (${HUB_NAME[slot]:-unnamed}) left"
    local was_host=0
    if [ "${slot}" -eq "${HUB_HOST_SLOT}" ]; then
        was_host=1
    fi
    hub_slot_reset "${slot}"
    HUB_ROSTER_DIRTY=1
    # The host left: the session moves to whoever joined first of those
    # still here, and this hub ends with the handover. Done after the slot
    # is cleared, so the one who is leaving cannot be picked again.
    if [ "${was_host}" -eq 1 ] && [ "${HUB_STOP_AT_MS}" -eq 0 ]; then
        hub_migrate_begin
    fi
    return 0
}

# hub_drop SLOT CODE TEXT
# Refuse a client: send it the reason and let its slot go. Used for a
# wrong protocol version, a flood and repeated malformed messages.
hub_drop() {
    local slot="${1}" code="${2}" text="${3}"
    proto_msg ERR "${code}" "${text}"
    hub_send "${slot}" "${PROTO_LINE}" || :
    debug_event "hub: slot ${slot} dropped (${code}: ${text})"
    if [ -n "${HUB_ID[slot]}" ]; then
        hub_client_close "${HUB_ID[slot]}"
    fi
    return 0
}

# --- Message handling -----------------------------------------------------
# hub_client_msg ID LINE
# One message from one client. Everything before the game logic is a
# gate: the rate limit, the whitelist parser, and the rule that a client
# which has not said HELLO may say nothing else.
hub_client_msg() {
    local id="${1}" line="${2}" slot rc=0
    slot="${HUB_SLOT_OF_ID[${id}]:-}"
    [ -n "${slot}" ] || return 0
    now_ms
    HUB_LAST_MS[slot]="${NOW_MS}"
    if ! proto_rate_ok "${id}"; then
        hub_drop "${slot}" "flood" "too many messages"
        return 0
    fi
    proto_parse "${line}" || rc=$?
    if [ "${rc}" -eq 2 ]; then
        # A verb this version does not know: ignored on purpose, so a
        # later version can add one without breaking this one.
        return 0
    fi
    if [ "${rc}" -ne 0 ]; then
        HUB_BAD[slot]=$(( ${HUB_BAD[slot]} + 1 ))
        net_log "bad<${slot}" "${line}"
        if [ "${HUB_BAD[slot]}" -ge "${HUB_BAD_MAX}" ]; then
            hub_drop "${slot}" "proto" "malformed messages"
        fi
        return 0
    fi
    HUB_BAD[slot]=0
    if [ "${HUB_HELLO[slot]}" -eq 0 ] && [ "${PROTO_VERB}" != "HELLO" ]; then
        hub_drop "${slot}" "proto" "expected HELLO"
        return 0
    fi
    case "${PROTO_VERB}" in
        HELLO)  hub_msg_hello "${slot}" ;;
        VIEW)   hub_msg_view "${slot}" ;;
        SETUP)  hub_msg_setup "${slot}" ;;
        PROMOTED) hub_msg_promoted "${slot}" ;;
        READY)  hub_msg_ready "${slot}" ;;
        STATE)  hub_msg_state "${slot}" ;;
        BOARD)  hub_msg_board "${slot}" ;;
        CLEAR)  hub_msg_clear "${slot}" ;;
        ACT)    hub_msg_act "${slot}" ;;
        APPLIED) hub_msg_applied "${slot}" ;;
        TOPOUT) hub_msg_topout "${slot}" ;;
        PONG)   : ;;
        BYE)    hub_client_close "${id}" ;;
    esac
    return 0
}

# hub_msg_hello SLOT: HELLO <proto> <name> <caps>
# The only message accepted from a client that has not identified itself.
# A different protocol version is refused right here rather than allowed
# to produce confusing failures later on.
hub_msg_hello() {
    local slot="${1}" name
    if [ "${HUB_HELLO[slot]}" -eq 1 ]; then
        hub_drop "${slot}" "proto" "duplicate hello"
        return 0
    fi
    if [ "${PROTO_ARG[0]}" != "${PROTO_VERSION}" ]; then
        hub_drop "${slot}" "proto" "protocol version mismatch"
        return 0
    fi
    if [ "${HUB_PLAYING}" -eq 1 ]; then
        hub_drop "${slot}" "running" "round already running"
        return 0
    fi
    name="${PROTO_ARG[1]}"
    HUB_NAME[slot]="${name}"
    HUB_HELLO[slot]=1
    HUB_STATE[slot]="lobby"
    proto_msg WELCOME "${slot}" "${PROTO_VERSION}" "${MP_MAX}" "${MP_SESSION}"
    hub_send "${slot}" "${PROTO_LINE}" || :
    # The first player to identify themselves opens the session and runs
    # its lobby. That used to be slot 0 by definition; since the role can
    # move on (hub_migrate_begin) it is a slot the hub remembers, and an
    # empty session is the one case in which it is handed out afresh.
    if [ "${HUB_HOST_SLOT}" -lt 0 ]; then
        HUB_HOST_SLOT="${slot}"
        debug_event "hub: slot ${slot} opens the session and runs the lobby"
    fi
    # The settings and the host before the roster: a client that has just
    # been let in should know what it has joined, and who runs it, before
    # it sees who it plays against.
    hub_setup_send "${slot}"
    hub_host_send "${slot}"
    HUB_ROSTER_DIRTY=1
    # A new player changes who is looking at whom, so the send flags are
    # re-derived here as well as on every VIEW.
    hub_needboard_update
    debug_event "hub: slot ${slot} is '${name}' (caps=${PROTO_ARG[2]})"
    return 0
}

# hub_msg_ready SLOT: READY <0|1>
# In the lobby every player marks themselves ready or not; the host - slot
# 0, the first connection, which is the host's own client - is the one
# whose "ready" starts the round (CLAUDE.md 5.1: the start belongs to the
# host alone, and nobody waits for a number agreed in advance). That is
# also why it needs no message of its own: for the host the lobby entry is
# the start button.
hub_msg_ready() {
    local slot="${1}"
    HUB_READY[slot]="${PROTO_ARG[0]}"
    HUB_ROSTER_DIRTY=1
    if [ "${slot}" -eq "${HUB_HOST_SLOT}" ] && [ "${PROTO_ARG[0]}" -eq 1 ] \
        && [ "${HUB_PLAYING}" -eq 0 ]; then
        hub_count_players
        if [ "${HUB_PLAYERS}" -ge 2 ]; then
            hub_start_round
        else
            HUB_READY[slot]=0
            proto_msg ERR alone "need a second player"
            hub_send "${slot}" "${PROTO_LINE}" || :
        fi
    fi
    return 0
}

# hub_msg_setup SLOT: SETUP <mode> <garbage>
# The host changes the rules of the session. Refused from anybody else
# and refused once the round runs - the settings decide how the round is
# won, and a rule that changes mid-round is no rule. Both refusals are
# silent towards the sender's screen (it has no entry to press) and land
# in the debug log; a client that sends this without being the host is
# not malformed, only wrong about who it is.
# The new settings go to everybody, the host included: the lobby of every
# player shows them, which is the whole point of putting them in the
# hands of one person.
hub_msg_setup() {
    local slot="${1}"
    if [ "${slot}" -ne "${HUB_HOST_SLOT}" ] || [ "${HUB_PLAYING}" -eq 1 ]; then
        debug_event "hub: SETUP from slot ${slot} ignored (host=${HUB_HOST_SLOT}, playing=${HUB_PLAYING})"
        return 0
    fi
    HUB_MODE="${PROTO_ARG[0]}"
    HUB_GARBAGE="${PROTO_ARG[1]}"
    debug_event "hub: settings changed to mode=${HUB_MODE} garbage=${HUB_GARBAGE}"
    hub_setup_send
    return 0
}

# hub_setup_send [SLOT]
# Send the session settings to one slot, or to everybody when no slot is
# given.
hub_setup_send() {
    proto_msg SETUP "${HUB_MODE}" "${HUB_GARBAGE}"
    if [ "$#" -ge 1 ]; then
        hub_send "${1}" "${PROTO_LINE}" || :
        return 0
    fi
    hub_bcast "${PROTO_LINE}"
    return 0
}

# hub_host_send [SLOT]
# Tell one slot, or everybody, who runs the lobby.
hub_host_send() {
    [ "${HUB_HOST_SLOT}" -ge 0 ] || return 0
    proto_msg HOST "${HUB_HOST_SLOT}"
    if [ "$#" -ge 1 ]; then
        hub_send "${1}" "${PROTO_LINE}" || :
        return 0
    fi
    hub_bcast "${PROTO_LINE}"
    return 0
}

# hub_client_addr ID ADDRESS
# Remember where a connection came from. The value comes off the wire
# through the bridge, so it is checked here and nowhere trusted: anything
# that is not a dotted quad becomes "-", which the handover below reads as
# "no address" (the unix transport, or a socat that did not report one).
hub_client_addr() {
    local id="${1}" addr="${2}" slot
    slot="${HUB_SLOT_OF_ID[${id}]:-}"
    [ -n "${slot}" ] || return 0
    # socat reports "address:port" for a TCP peer; only the address half
    # is of interest, and only when it really is one.
    addr="${addr%%:*}"
    if net_ipv4_ok "${addr}"; then
        HUB_ADDR[slot]="${addr}"
    else
        HUB_ADDR[slot]="-"
    fi
    return 0
}

# hub_migrate_begin
# The host has left, so this hub is finished - but the session need not
# be (user request, 1.2.0). The lobby is offered to the player who joined
# first of those still there: the one who has been waiting longest has
# the best claim to it, and it is a rule everybody can see coming, unlike
# "the lowest free slot", which after a few comings and goings is nobody's
# idea of an order.
#
# Why the session moves instead of this hub simply carrying on: the hub is
# a process on the departed host's machine. Leaving it running would keep
# a session alive on a computer whose owner has walked away from it - and
# nothing would ever end it but the last player leaving. So the successor
# starts a hub of their own (PROMOTE), reports the port it listens on
# (PROMOTED), and everybody else is sent after it (MIGRATE) before this
# hub stops.
#
# Nobody left to ask, or nobody who answers: the session is over and says
# so (CLOSED) rather than leaving its players to work it out by timeout.
hub_migrate_begin() {
    local i best=-1 seq=0
    HUB_HOST_SLOT=-1
    for (( i = 0; i < MP_MAX; i++ )); do
        [ -n "${HUB_ID[i]}" ] || continue
        [ "${HUB_HELLO[i]}" -eq 1 ] || continue
        if [ "${best}" -lt 0 ] || [ "${HUB_JOINED[i]}" -lt "${seq}" ]; then
            best="${i}"
            seq="${HUB_JOINED[i]}"
        fi
    done
    if [ "${best}" -lt 0 ]; then
        debug_event "hub: the host left and nobody is here to take over"
        hub_close_session "host"
        return 0
    fi
    # Everybody's ready flag goes with the old host: they were given to
    # somebody who is gone, and for the new host "ready" means "start the
    # round" - an inherited flag could start a round nobody asked for.
    for (( i = 0; i < MP_MAX; i++ )); do
        HUB_READY[i]=0
    done
    HUB_PROMOTED_SLOT="${best}"
    now_ms
    HUB_PROMOTE_DEADLINE_MS=$(( NOW_MS + HUB_PROMOTE_MS ))
    debug_event "hub: the host left; slot ${best} (${HUB_NAME[best]}) is asked to take the session over"
    proto_msg PROMOTE
    hub_send "${best}" "${PROTO_LINE}" || :
    return 0
}

# hub_msg_promoted SLOT: PROMOTED <port>
# The answer to PROMOTE: the port of the hub the successor started, or 0
# when they could not start one. Accepted from the one client that was
# asked and from nobody else - and only once, because the session is on
# its way out from here either way.
hub_msg_promoted() {
    local slot="${1}" port="${PROTO_ARG[0]}" addr i
    if [ "${slot}" -ne "${HUB_PROMOTED_SLOT}" ]; then
        debug_event "hub: PROMOTED from slot ${slot}, which was not asked"
        return 0
    fi
    HUB_PROMOTED_SLOT=-1
    if [ "${port}" -eq 0 ] || ! net_port_ok "${port}"; then
        debug_event "hub: slot ${slot} could not take the session over"
        hub_close_session "failed"
        return 0
    fi
    # Where the others have to go. In the unix transport there is no
    # address to send: everybody is on this machine and finds the session
    # by its name, so 0.0.0.0 stands for "the socket of this session,
    # here".
    addr="${HUB_ADDR[slot]}"
    if [ "${MP_TRANSPORT}" != "lan" ] || [ "${addr}" = "-" ]; then
        addr="0.0.0.0"
    fi
    debug_event "hub: the session moves to slot ${slot} at ${addr}:${port}"
    proto_msg MIGRATE "${addr}" "${port}"
    # Held back for a moment rather than sent straight away: the new hub
    # hands its lobby to whoever identifies itself first, and that has to
    # be the player who took the session over, not whoever happens to
    # reconnect quickest. Their client is already on its way to a hub on
    # its own machine while this message still has a network to cross,
    # but on one machine - two clients and a test bot on a loopback
    # address - that lead is a few milliseconds and the wrong client wins
    # it about as often as the right one. The delay turns a coin toss
    # into a lead nothing local can make up.
    HUB_MIGRATE_LINE="${PROTO_LINE}"
    HUB_MIGRATE_SLOT="${slot}"
    now_ms
    HUB_MIGRATE_AT_MS=$(( NOW_MS + HUB_MIGRATE_DELAY_MS ))
    return 0
}

# hub_migrate_finish
# Send the MIGRATE held back above and end this hub. Called from
# hub_periodic once the successor's lead is long enough.
hub_migrate_finish() {
    local i slot="${HUB_MIGRATE_SLOT}"
    HUB_MIGRATE_AT_MS=0
    HUB_MIGRATE_SLOT=-1
    for (( i = 0; i < MP_MAX; i++ )); do
        [ -n "${HUB_ID[i]}" ] || continue
        [ "${i}" -ne "${slot}" ] || continue
        hub_send "${i}" "${HUB_MIGRATE_LINE}" || :
    done
    HUB_MIGRATE_LINE=""
    hub_stop_soon
    return 0
}

# hub_close_session REASON
# Tell everybody that this session is over and end this hub. Used where a
# handover cannot happen or did not work; a round that is running is not
# interrupted by it, because a host leaving mid-round is an ordinary
# elimination and the round plays itself out (see hub_client_close).
hub_close_session() {
    local reason="${1}"
    proto_msg CLOSED "${reason}"
    hub_bcast "${PROTO_LINE}"
    debug_event "hub: session closed (${reason})"
    hub_stop_soon
    return 0
}

# hub_stop_soon
# Stop this hub, but not this instant: the messages just written are
# sitting in the down FIFOs, and the bridges still have to push them
# through their sockets. A hub that exited straight away would take its
# own last word with it, because hub_cleanup removes those FIFOs.
hub_stop_soon() {
    now_ms
    HUB_STOP_AT_MS=$(( NOW_MS + HUB_STOP_GRACE_MS ))
    return 0
}

# hub_msg_state SLOT: STATE <lines> <rows> <level> <gold> <silver> <height> <pending>
# A player's counters. Kept and forwarded to everybody else as PEER; the
# pending figure the client reports is display only - the hub keeps its
# own (HUB_PENDING), which is the one the garbage arithmetic uses.
hub_msg_state() {
    local slot="${1}"
    HUB_LINES[slot]="${PROTO_ARG[0]}"
    HUB_ROWS[slot]="${PROTO_ARG[1]}"
    HUB_LEVEL[slot]="${PROTO_ARG[2]}"
    HUB_GOLD[slot]="${PROTO_ARG[3]}"
    HUB_SILVER[slot]="${PROTO_ARG[4]}"
    HUB_HEIGHT[slot]="${PROTO_ARG[5]}"
    proto_msg PEER "${slot}" "${HUB_LINES[slot]}" "${HUB_ROWS[slot]}" \
        "${HUB_LEVEL[slot]}" "${HUB_GOLD[slot]}" "${HUB_SILVER[slot]}" \
        "${HUB_HEIGHT[slot]}" "${HUB_PENDING[slot]}" "${HUB_STATE[slot]}"
    hub_bcast "${PROTO_LINE}" "${slot}"
    # Ultra: the first player past the row target has won, and this is the
    # message that says so - the counters are the only thing the hub knows
    # about a player's progress. Checked here rather than on a timer, so
    # the round ends on the clear that decided it.
    if [ "${HUB_PLAYING}" -eq 1 ] && [ "${HUB_MODE}" = "ultra" ] \
        && [ "${HUB_STATE[slot]}" = "play" ] \
        && [ "${HUB_ROWS[slot]}" -ge "${ULTRA_TARGET_ROWS}" ]; then
        debug_event "hub: slot ${slot} reached the ultra target (${HUB_ROWS[slot]}/${ULTRA_TARGET_ROWS})"
        hub_end_round "${slot}"
    fi
    return 0
}

# hub_msg_board SLOT: BOARD <200 chars>
# A field snapshot, forwarded to the peers that asked for one. A client
# that was never told to send them (NEEDBOARD 0) is simply ignored here
# rather than dropped: the flag may have changed while its message was
# in flight.
hub_msg_board() {
    local slot="${1}" i
    proto_msg PEERBOARD "${slot}" "${PROTO_ARG[0]}"
    for (( i = 0; i < MP_MAX; i++ )); do
        [ -n "${HUB_ID[i]}" ] || continue
        [ "${i}" -ne "${slot}" ] || continue
        [ "${HUB_WANTBOARD[i]}" -eq 1 ] || continue
        hub_send "${i}" "${PROTO_LINE}" || :
    done
    return 0
}

# hub_msg_view SLOT: VIEW <0|1>
# A client says whether it is drawing the opponents' boards. The hub keeps
# that per slot and derives from it what every client has to send:
# snapshots are worth their bandwidth exactly as long as somebody else is
# looking at them (CLAUDE.md 5.6).
hub_msg_view() {
    local slot="${1}"
    HUB_WANTBOARD[slot]="${PROTO_ARG[0]}"
    hub_needboard_update
    return 0
}

# hub_needboard_update
# Tell every client whether it should be sending board snapshots: it
# should when any *other* client is drawing them. Sent only on a change -
# the flag is stable for whole rounds, and repeating it every time
# somebody resizes their terminal would be chatter for nothing.
hub_needboard_update() {
    local i j want
    for (( i = 0; i < MP_MAX; i++ )); do
        [ -n "${HUB_ID[i]}" ] || continue
        want=0
        for (( j = 0; j < MP_MAX; j++ )); do
            [ -n "${HUB_ID[j]}" ] || continue
            [ "${j}" -ne "${i}" ] || continue
            if [ "${HUB_WANTBOARD[j]}" -eq 1 ]; then
                want=1
                break
            fi
        done
        if [ "${HUB_NEEDBOARD[i]}" -ne "${want}" ]; then
            HUB_NEEDBOARD[i]="${want}"
            proto_msg NEEDBOARD "${want}"
            hub_send "${i}" "${PROTO_LINE}" || :
        fi
    done
    return 0
}

# hub_attack LINES SILVER GOLD
# What one clear is worth in garbage rows, into HUB_ATTACK: the row count
# from GARBAGE_LINES, plus GARBAGE_SILVER per silver and GARBAGE_GOLD per
# gold square the cleared rows ran through, capped at GARBAGE_CAP. This
# is the arithmetic the whole "clients report events, never consequences"
# rule exists for: it runs here and nowhere else.
HUB_ATTACK=0
hub_attack() {
    local lines="${1}" silver="${2}" gold="${3}" n
    if [ "${lines}" -gt 4 ]; then
        lines=4
    fi
    n="${GARBAGE_LINES[lines]}"
    n=$(( n + silver * GARBAGE_SILVER + gold * GARBAGE_GOLD ))
    if [ "${n}" -gt "${GARBAGE_CAP}" ]; then
        n="${GARBAGE_CAP}"
    fi
    HUB_ATTACK="${n}"
    return 0
}

# hub_targets SLOT COUNT
# Deal COUNT garbage rows to the living opponents of SLOT, following the
# session's target mode (CLAUDE.md 5.7): "random" gives the whole attack
# to one of them, "all" gives every one of them the full amount, "even"
# splits it and hands the remainder to one at random. With two players
# all three are the same thing.
hub_targets() {
    local slot="${1}" count="${2}" i hole share rest pick
    local -a alive=()
    [ "${count}" -gt 0 ] || return 0
    for (( i = 0; i < MP_MAX; i++ )); do
        [ -n "${HUB_ID[i]}" ] || continue
        [ "${i}" -ne "${slot}" ] || continue
        [ "${HUB_STATE[i]}" = "play" ] || continue
        alive+=("${i}")
    done
    [ "${#alive[@]}" -gt 0 ] || return 0
    # The gap column comes from the hub's own RANDOM and is the same for
    # every row of one attack, so a player can plan around it - and no
    # client can influence it.
    hole=$(( RANDOM % BOARD_W ))
    case "${MP_TARGET}" in
        all)
            for i in "${alive[@]}"; do
                hub_deal "${i}" "${count}" "${hole}"
            done
            ;;
        even)
            share=$(( count / ${#alive[@]} ))
            rest=$(( count % ${#alive[@]} ))
            pick="${alive[RANDOM % ${#alive[@]}]}"
            for i in "${alive[@]}"; do
                local n="${share}"
                if [ "${i}" -eq "${pick}" ]; then
                    n=$(( n + rest ))
                fi
                hub_deal "${i}" "${n}" "${hole}"
            done
            ;;
        *)
            pick="${alive[RANDOM % ${#alive[@]}]}"
            hub_deal "${pick}" "${count}" "${hole}"
            ;;
    esac
    return 0
}

# hub_deal SLOT COUNT HOLE
# Put COUNT rows into a slot's queue and tell it. The client adds them to
# its own queue and pushes them in at its next lock; the hub keeps the
# count so it knows what a clear of that player can still cancel.
hub_deal() {
    local slot="${1}" count="${2}" hole="${3}"
    [ "${count}" -gt 0 ] || return 0
    HUB_PENDING[slot]=$(( ${HUB_PENDING[slot]} + count ))
    # Addressed to one player and sent to all (protocol 4): the rows are
    # the one thing that enters a board without coming from its owner's
    # moves, so every client needs to see them to be able to record the
    # round (CLAUDE.md 5.20). Only the slot named acts on them - the
    # others merely write them down.
    proto_msg GARBAGE "${slot}" "${count}" "${hole}"
    hub_bcast "${PROTO_LINE}"
    debug_event "hub: ${count} garbage row(s) hole=${hole} -> slot ${slot} (${HUB_NAME[slot]}), queue=${HUB_PENDING[slot]}"
    return 0
}

# hub_msg_act SLOT: ACT <t> <tokens>
# A player's moves of the last window, passed on to everybody else as
# PEERACT. The hub does not look inside the token stream and does not
# keep it: it is the one message it purely relays, because the moves mean
# nothing to the session logic - what a clear is worth is computed from
# CLEAR, what a round costs is decided by TOPOUT and the clock. Every
# client needs them though, and the hub is the only path between clients
# (CLAUDE.md 5.20).
# Only from a player who is actually playing: a spectator has no moves to
# report, and a lobby that relayed them would be sending its members
# something they cannot place anywhere.
# The stream is validated by proto_parse before it gets here (PROTO_ACT_RE
# is the whole check - characters and length), so relaying it is passing
# on something already proven to be well formed, not trusting the sender.
hub_msg_act() {
    local slot="${1}"
    [ "${HUB_STATE[slot]}" = "play" ] || return 0
    proto_msg PEERACT "${slot}" "${PROTO_ARG[0]}" "${PROTO_ARG[1]}"
    hub_bcast "${PROTO_LINE}" "${slot}"
    return 0
}

# hub_msg_clear SLOT: CLEAR <lines> <silver> <gold>
# A player cleared rows. The attack is computed here, first cancelled
# against that player's own queue - which is what rewards a counter-attack
# over pure defence - and only the remainder goes out. The player is told
# its new queue length with QUEUE, because the hub owns that number: two
# copies of it, one on each end, could only ever drift apart.
hub_msg_clear() {
    local slot="${1}" lines="${PROTO_ARG[0]}" cancel
    [ "${HUB_STATE[slot]}" = "play" ] || return 0
    # Garbage off (the default, see HUB_GARBAGE): the clear is still a
    # clear - it counts towards the player's rows, which is what every
    # mode is scored by - it just does not travel. Nothing else about the
    # round changes, which is why this is a switch and not a mode.
    if [ "${HUB_GARBAGE}" -ne 1 ]; then
        return 0
    fi
    hub_attack "${lines}" "${PROTO_ARG[1]}" "${PROTO_ARG[2]}"
    cancel="${HUB_ATTACK}"
    if [ "${cancel}" -gt "${HUB_PENDING[slot]}" ]; then
        cancel="${HUB_PENDING[slot]}"
    fi
    if [ "${cancel}" -gt 0 ]; then
        HUB_PENDING[slot]=$(( ${HUB_PENDING[slot]} - cancel ))
        # Like GARBAGE above: the correction belongs to one player and is
        # told to everybody, so a recording follows every queue and not
        # only its own.
        proto_msg QUEUE "${slot}" "${HUB_PENDING[slot]}"
        hub_bcast "${PROTO_LINE}"
    fi
    debug_event "hub: slot ${slot} cleared ${lines} row(s) (silver=${PROTO_ARG[1]} gold=${PROTO_ARG[2]}): attack=${HUB_ATTACK} cancelled=${cancel}"
    hub_targets "${slot}" "$(( HUB_ATTACK - cancel ))"
    return 0
}

# hub_msg_applied SLOT: APPLIED <count>
# The client pushed COUNT queued rows into its board. From that moment
# they are part of its stack and can no longer be cancelled, so they leave
# the hub's queue too. Clamped at zero: a client claiming to have applied
# more than it was ever dealt gains nothing by it.
hub_msg_applied() {
    local slot="${1}" n="${PROTO_ARG[0]}"
    if [ "${n}" -gt "${HUB_PENDING[slot]}" ]; then
        n="${HUB_PENDING[slot]}"
    fi
    HUB_PENDING[slot]=$(( ${HUB_PENDING[slot]} - n ))
    return 0
}

# hub_msg_topout SLOT
# The player built themselves out of the field. They become a spectator
# and take the highest place still free.
hub_msg_topout() {
    local slot="${1}"
    # A round that is already decided cannot be lost again. The message is
    # not a mistake: the winner's own board keeps running for the handful
    # of milliseconds between the hub's END and the client noticing it, so
    # a late top-out is the normal case rather than the odd one.
    [ "${HUB_PLAYING}" -eq 1 ] || return 0
    [ "${HUB_STATE[slot]}" = "play" ] || return 0
    hub_eliminate "${slot}" "ko"
    return 0
}

# hub_eliminate SLOT STATE
# Take a player out of the running round, either knocked out (they topped
# out) or gone (the connection died - which counts the same, see
# CLAUDE.md 5.8). Places are handed out from the back: the first player
# out takes the last place. When one player is left the round is over.
hub_eliminate() {
    local slot="${1}" state="${2}"
    HUB_STATE[slot]="${state}"
    hub_count_players
    # The place is the number of players who were still in when this one
    # went out, i.e. the count before the elimination - hub_count_players
    # has already subtracted this player, so add them back.
    HUB_PLACE[slot]=$(( HUB_ALIVE + 1 ))
    proto_msg KO "${slot}" "${HUB_PLACE[slot]}"
    hub_bcast "${PROTO_LINE}"
    HUB_ROSTER_DIRTY=1
    debug_event "hub: slot ${slot} (${HUB_NAME[slot]}) out as ${state}, place ${HUB_PLACE[slot]}"
    # When an elimination ends the round is the one thing the mode decides
    # (CLAUDE.md 5.1): in survival the last player standing has won and
    # there is nothing left to play for, while in sprint and ultra the
    # rows decide - so a lone survivor plays on, because somebody who
    # already topped out may still be ahead of them.
    if [ "${HUB_MODE}" = "survival" ]; then
        if [ "${HUB_ALIVE}" -le 1 ]; then
            hub_end_round
        fi
    elif [ "${HUB_ALIVE}" -eq 0 ]; then
        hub_end_round
    fi
    return 0
}

# hub_start_round
# Deal the shared seed and start the countdown. Everybody plays the same
# piece sequence, which is what makes the duel about play rather than
# luck; the seed is the host's --seed when one was given (so a session can
# be reproduced) and a fresh random number otherwise.
hub_start_round() {
    local i seed
    seed="${SEED:-}"
    if [ -z "${seed}" ]; then
        seed=$(( (RANDOM << 15 | RANDOM) & 0x3FFFFFFF ))
    fi
    # Whatever the seed came from, it has to fit the number field of the
    # protocol - nine digits (PROTO_NUM_RE, lib/proto.sh). Neither source
    # respected that: the mask above reaches 0x3FFFFFFF and is therefore
    # ten digits in about 7% of all rounds, and --seed accepts digits of
    # any length. Found by the load probe of step 9.5, and it had been
    # there since the seed was introduced.
    # The consequence was silent and bad: every client rejected the SEED
    # message as malformed, kept the RANDOM it already had, and each of
    # them played a different piece sequence - the very fairness the
    # shared seed exists for (CLAUDE.md 5.1), with nothing on screen to
    # say so. A seed that differs from the one asked for is a far smaller
    # thing than a seed nobody gets.
    # Twice, so an overlong --seed that wrapped into a negative value in
    # bash arithmetic still lands in 0..999999999 rather than carrying a
    # minus sign onto the wire.
    seed=$(( (seed % 1000000000 + 1000000000) % 1000000000 ))
    for (( i = 0; i < MP_MAX; i++ )); do
        [ -n "${HUB_ID[i]}" ] || continue
        HUB_STATE[i]="play"
        HUB_PENDING[i]=0
        HUB_PLACE[i]=0
    done
    HUB_PLAYING=1
    # The settings once more, right before the round: they decide how it
    # is played and won, and a client that joined while the host was still
    # switching things around must not start under the old ones.
    hub_setup_send
    proto_msg SEED "${seed}"
    hub_bcast "${PROTO_LINE}"
    proto_msg START "${HUB_COUNTDOWN_MS}"
    hub_bcast "${PROTO_LINE}"
    # Sprint runs against a clock the hub owns. It starts when the
    # countdown ends, so everybody gets the same three minutes; the
    # clients count the same limit down for their own display, but only
    # this clock ends the round.
    HUB_ROUND_END_MS=0
    if [ "${HUB_MODE}" = "sprint" ]; then
        now_ms
        HUB_ROUND_END_MS=$(( NOW_MS + HUB_COUNTDOWN_MS + SPRINT_TIME_MS ))
    fi
    HUB_ROSTER_DIRTY=1
    hub_count_players
    debug_event "hub: round starts with ${HUB_PLAYERS} player(s), seed=${seed}, mode=${HUB_MODE}, garbage=${HUB_GARBAGE}, target mode=${MP_TARGET}"
    return 0
}

# hub_places_by_rows WINNER
# Give every player the place their row credit earned them and tell them:
# the winner is first (they are handed in, because in ultra that is the
# player who hit the target rather than the one with the most rows), the
# rest follow by rows, and equal rows go to the lower slot - the one
# tiebreaker that reads the same for everybody.
# The places are sent as KO, the message that carries a place already;
# a client simply takes the newer one.
hub_places_by_rows() {
    local winner="${1}" place=1 i best rows
    local -a left=()
    for (( i = 0; i < MP_MAX; i++ )); do
        [ -n "${HUB_NAME[i]}" ] || continue
        [ "${i}" -ne "${winner}" ] || continue
        left+=("${i}")
    done
    if [ "${winner}" -ge 0 ]; then
        HUB_PLACE[winner]=1
        place=2
    fi
    # Selection sort over at most five entries: shorter than any clever
    # alternative and free at this size.
    while [ "${#left[@]}" -gt 0 ]; do
        best=0
        rows="${HUB_ROWS[${left[0]}]}"
        for (( i = 1; i < ${#left[@]}; i++ )); do
            if [ "${HUB_ROWS[${left[i]}]}" -gt "${rows}" ]; then
                rows="${HUB_ROWS[${left[i]}]}"
                best="${i}"
            fi
        done
        HUB_PLACE[${left[best]}]="${place}"
        proto_msg KO "${left[best]}" "${place}"
        hub_bcast "${PROTO_LINE}"
        left=("${left[@]:0:best}" "${left[@]:best+1}")
        place=$(( place + 1 ))
    done
    return 0
}

# hub_end_round [WINNER]
# The round is decided. Who won is the mode's question and therefore the
# one thing this function asks it about (CLAUDE.md 5.1/5.8):
#   survival - the last player standing. If the last two went out in the
#              same moment - which the loop can produce, since two
#              messages are handled one after the other - the higher row
#              credit decides and the lower slot breaks a tie.
#   sprint   - the most rows when the clock ran out, over everybody who
#              took part; somebody who topped out early keeps the rows
#              they scored, which is why a lone survivor cannot simply
#              sit out the rest.
#   ultra    - the first player past the target, which is who the caller
#              hands in as WINNER; without one (everybody topped out
#              first) the most rows decide, as in sprint.
# Ties always go to the lower slot, because a duel needs an answer and
# the slot order is the only tiebreaker that is the same for everybody.
hub_end_round() {
    local winner="${1:--1}"
    local i best=-1
    # Once only. Several things can decide a round in the same tick - the
    # last elimination, the sprint clock, a late top-out - and a second
    # END would tell everybody a different winner than the first.
    [ "${HUB_PLAYING}" -eq 1 ] || return 0
    if [ "${winner}" -lt 0 ] && [ "${HUB_MODE}" = "survival" ]; then
        for (( i = 0; i < MP_MAX; i++ )); do
            [ -n "${HUB_NAME[i]}" ] || continue
            if [ "${HUB_STATE[i]}" = "play" ]; then
                winner="${i}"
                break
            fi
        done
    fi
    if [ "${winner}" -lt 0 ]; then
        for (( i = 0; i < MP_MAX; i++ )); do
            [ -n "${HUB_NAME[i]}" ] || continue
            if [ "${HUB_ROWS[i]}" -gt "${best}" ]; then
                best="${HUB_ROWS[i]}"
                winner="${i}"
            fi
        done
    fi
    # In the modes that are decided by rows, the places a player was
    # given as they dropped out say the wrong thing: they are the order of
    # dying, and here the order is the score. They are recomputed and sent
    # again before the round ends, so everybody's result box names the
    # place they really took.
    if [ "${HUB_MODE}" != "survival" ]; then
        hub_places_by_rows "${winner}"
    fi
    if [ "${winner}" -ge 0 ]; then
        HUB_PLACE[winner]=1
    fi
    HUB_PLAYING=0
    HUB_ROUND_END_MS=0
    proto_msg END "${winner}"
    hub_bcast "${PROTO_LINE}"
    debug_event "hub: round over (mode=${HUB_MODE}), winner slot ${winner} (${HUB_NAME[winner]:-none})"
    return 0
}

# --- Periodic work --------------------------------------------------------
# hub_periodic
# Everything that happens on the clock rather than on a message: the
# beacon, the ping, the HELLO deadline and the silence timeout.
hub_periodic() {
    local i
    now_ms
    if [ "${HUB_ROSTER_DIRTY}" -eq 1 ]; then
        hub_roster_send
    fi
    # Beacon (lan transport only): the session announces itself once a
    # second. It keeps going during the round, marked "play", so a
    # searching player sees that there is a session here rather than
    # nothing at all - it is not needed for the round itself, which runs
    # entirely over the established TCP connections.
    if [ "${MP_TRANSPORT}" = "lan" ] && (( NOW_MS >= HUB_NEXT_BEACON_MS )); then
        HUB_NEXT_BEACON_MS=$(( NOW_MS + MP_BEACON_MS ))
        hub_count_players
        local state="lobby"
        if [ "${HUB_PLAYING}" -eq 1 ]; then
            state="play"
        fi
        net_beacon_line "${MP_SESSION}" "${HUB_PLAYERS}" "${MP_MAX}" \
            "${MP_PORT}" "${state}"
        net_beacon_send "${NET_BEACON}" || :
    fi
    # Sprint: the clock is the round's ending, so it is checked on the
    # same pass as the ping rather than waiting for a message that may
    # never come (a player who stopped playing sends nothing).
    if [ "${HUB_PLAYING}" -eq 1 ] && [ "${HUB_ROUND_END_MS}" -gt 0 ] \
        && (( NOW_MS >= HUB_ROUND_END_MS )); then
        debug_event "hub: sprint time is up after ${SPRINT_TIME_MS}ms"
        hub_end_round
    fi
    if (( NOW_MS >= HUB_NEXT_PING_MS )); then
        HUB_NEXT_PING_MS=$(( NOW_MS + MP_PING_MS ))
        HUB_PING_TOKEN=$(( (HUB_PING_TOKEN + 1) % 1000000 ))
        proto_msg PING "${HUB_PING_TOKEN}"
        hub_bcast "${PROTO_LINE}"
    fi
    for (( i = 0; i < MP_MAX; i++ )); do
        [ -n "${HUB_ID[i]}" ] || continue
        if [ "${HUB_HELLO[i]}" -eq 0 ] \
            && (( NOW_MS - ${HUB_OPEN_MS[i]} > MP_HELLO_MS )); then
            hub_drop "${i}" "timeout" "no hello"
            continue
        fi
        if (( NOW_MS - ${HUB_LAST_MS[i]} > MP_TIMEOUT_MS )); then
            debug_event "hub: slot ${i} timed out after ${MP_TIMEOUT_MS}ms of silence"
            hub_client_close "${HUB_ID[i]}"
        fi
    done
    # The successor never answered: the session cannot move, so it ends
    # here rather than leaving everybody waiting for a hub that is about
    # to stop anyway.
    if [ "${HUB_PROMOTED_SLOT}" -ge 0 ] \
        && (( NOW_MS >= HUB_PROMOTE_DEADLINE_MS )); then
        debug_event "hub: slot ${HUB_PROMOTED_SLOT} did not take the session over in time"
        HUB_PROMOTED_SLOT=-1
        hub_close_session "failed"
    fi
    # The successor has had their head start: after them, everybody.
    if [ "${HUB_MIGRATE_AT_MS}" -gt 0 ] && (( NOW_MS >= HUB_MIGRATE_AT_MS )); then
        hub_migrate_finish
    fi
    # The last word has had its moment to reach the sockets.
    if [ "${HUB_STOP_AT_MS}" -gt 0 ] && (( NOW_MS >= HUB_STOP_AT_MS )); then
        HUB_RUN=0
        return 0
    fi
    # Nobody left: the session is over. A hub that outlived its players
    # would keep the port and keep beaconing an empty room.
    hub_count_players
    if [ "${HUB_PLAYERS}" -eq 0 ] && [ "${HUB_STARTED_MS}" -gt 0 ] \
        && (( NOW_MS - HUB_STARTED_MS > MP_HELLO_MS )); then
        debug_event "hub: no players left, shutting down"
        HUB_RUN=0
    fi
    return 0
}
HUB_STARTED_MS=0

# --- Listener and main loop -----------------------------------------------
# hub_listen
# Start the socat listener for the configured transport. This is the one
# place the two transports differ: a TCP port versus a socket file, both
# with a fork per connection, a child limit of MP_MAX and the bridge as
# the child. Everything above this line is transport-blind.
# In the lan transport a port that is already taken is not an error: the
# next free one is used and announced in the beacon, so a second session
# on the same machine simply moves up.
hub_listen() {
    local addr tries port
    if [ "${MP_TRANSPORT}" = "unix" ]; then
        net_session_path "${MP_SESSION}" || return 1
        HUB_LISTEN_PATH="${NET_SESSION_PATH}"
        # A leftover socket of a session that died is removed; a live one
        # would have been refused by the connect test in lib/mp.sh before
        # we ever got here.
        rm -f -- "${HUB_LISTEN_PATH}" 2>/dev/null || :
        addr="UNIX-LISTEN:${HUB_LISTEN_PATH},fork,max-children=${MP_MAX},mode=0600"
        ROWHAMMER_MP_INBOX="${HUB_INBOX_PATH}" \
        ROWHAMMER_MP_DOWN="${HUB_DOWN_PREFIX}" \
        "${NET_SOCAT}" "${addr}" \
            "EXEC:${SCRIPT_DIR}/rowhammer.sh --mp-bridge" >/dev/null 2>&1 &
        HUB_SOCAT_PID=$!
        sleep 0.2
        if ! kill -0 "${HUB_SOCAT_PID}" 2>/dev/null; then
            return 1
        fi
        hub_port_publish
        debug_event "hub: listening on ${HUB_LISTEN_PATH}"
        return 0
    fi
    port="${MP_PORT}"
    for (( tries = 0; tries < 10; tries++ )); do
        addr="TCP4-LISTEN:${port},fork,reuseaddr,max-children=${MP_MAX}"
        ROWHAMMER_MP_INBOX="${HUB_INBOX_PATH}" \
        ROWHAMMER_MP_DOWN="${HUB_DOWN_PREFIX}" \
        "${NET_SOCAT}" "${addr}" \
            "EXEC:${SCRIPT_DIR}/rowhammer.sh --mp-bridge" >/dev/null 2>&1 &
        HUB_SOCAT_PID=$!
        # A listener that cannot bind exits at once; anything still alive
        # a moment later has the port.
        sleep 0.2
        if kill -0 "${HUB_SOCAT_PID}" 2>/dev/null; then
            MP_PORT="${port}"
            hub_port_publish
            debug_event "hub: listening on tcp/${MP_PORT}"
            return 0
        fi
        port=$(( port + 1 ))
        net_port_ok "${port}" || return 1
    done
    return 1
}

# hub_port_publish
# Write the port this hub really listens on into a file beside its FIFOs,
# so the client that started it can read it back. It cannot be told
# otherwise: the port is only settled once the listener has bound (a taken
# port moves the hub to the next free one), and by then the hub is a
# process of its own. The number matters for exactly one thing - a
# takeover has to tell the other players where the session moved to
# (hub_msg_promoted).
hub_port_publish() {
    local tmp
    HUB_PORT_PATH="${MP_DIR}/${MP_SESSION}.port"
    tmp="${HUB_PORT_PATH}.tmp"
    if printf '%s\n' "${MP_PORT}" > "${tmp}" 2>/dev/null; then
        mv -f -- "${tmp}" "${HUB_PORT_PATH}" 2>/dev/null || :
    fi
    return 0
}
HUB_PORT_PATH=""

# hub_sweep_stale
# Clear away the FIFOs of hubs of this session name that are no longer
# running. They can only be left by a hub that was killed outright (a
# SIGKILL, a machine going down), because every other end runs through
# hub_cleanup - but since the paths now carry a process id, nothing else
# would ever remove them. Strictly by "the process is gone": a FIFO whose
# hub still answers belongs to a session somebody may well be playing in,
# and taking it away is exactly the damage the process id is there to
# prevent.
hub_sweep_stale() {
    local path pid
    for path in "${MP_DIR}/${MP_SESSION}."*".inbox" \
                "${MP_DIR}/${MP_SESSION}."*".down."*; do
        [ -e "${path}" ] || continue
        # <session>.<pid>.inbox and <session>.<pid>.down.<bridge>: the
        # process id is the field after the session name either way.
        pid="${path#"${MP_DIR}/${MP_SESSION}."}"
        pid="${pid%%.*}"
        [[ "${pid}" =~ ${MP_NUM_RE} ]] || continue
        if kill -0 "${pid}" 2>/dev/null; then
            continue
        fi
        rm -f -- "${path}" 2>/dev/null || :
    done
    return 0
}

# hub_cleanup
# Remove everything the hub created: the listener, the inbox FIFO, the
# down FIFOs of the bridges and, in the unix transport, the socket. Runs
# from the hub process's EXIT trap, so a killed hub leaves nothing behind.
hub_cleanup() {
    if [ "${HUB_SOCAT_PID}" -gt 0 ]; then
        kill "${HUB_SOCAT_PID}" 2>/dev/null || :
    fi
    if [ -n "${HUB_INBOX_PATH}" ]; then
        rm -f -- "${HUB_INBOX_PATH}" 2>/dev/null || :
    fi
    if [ -n "${HUB_DOWN_PREFIX}" ]; then
        rm -f -- "${HUB_DOWN_PREFIX}".* 2>/dev/null || :
    fi
    if [ -n "${HUB_LISTEN_PATH}" ]; then
        rm -f -- "${HUB_LISTEN_PATH}" 2>/dev/null || :
    fi
    if [ -n "${HUB_PORT_PATH}" ]; then
        rm -f -- "${HUB_PORT_PATH}" 2>/dev/null || :
    fi
    return 0
}

# hub_main
# The hub process: prepare the session directory and its FIFOs, start the
# listener, then loop until nobody is left. The timed read on the inbox is
# both the message pump and the clock - it returns a line when there is
# one and times out otherwise, which is when the periodic work runs. No
# sleep, no busy loop.
hub_main() {
    local line rc id rest n
    umask 0077
    net_require || die "socat is required for the multiplayer (package: socat)"
    net_dir_prepare || die "${NET_ERROR}"
    [[ "${MP_SESSION}" =~ ${MP_SESSION_RE} ]] || die "Invalid session name: ${MP_SESSION}"
    # The FIFOs carry this hub's process id, not just the session name.
    # Two hubs of the same name on one machine are not a mistake but the
    # normal picture during a handover (1.2.0): the session moves to
    # another player's hub under the same name, and for a moment - or
    # longer, if somebody opens a fresh session named like the one they
    # just left - both exist. With the name alone, the second hub would
    # remove and recreate the first one's inbox, and the first one's
    # bridges would from then on write their clients' messages into the
    # second one's, where nobody is waiting for them.
    HUB_INBOX_PATH="${MP_DIR}/${MP_SESSION}.$$.inbox"
    HUB_DOWN_PREFIX="${MP_DIR}/${MP_SESSION}.$$.down"
    trap 'hub_cleanup' EXIT
    trap 'HUB_RUN=0' INT TERM
    hub_sweep_stale
    rm -f -- "${HUB_INBOX_PATH}" 2>/dev/null || :
    mkfifo -m 0600 -- "${HUB_INBOX_PATH}" || die "Cannot create ${HUB_INBOX_PATH}"
    # Read-write, so the hub neither blocks on the open nor ever sees an
    # end of file when the last bridge exits.
    exec 9<>"${HUB_INBOX_PATH}" || die "Cannot open ${HUB_INBOX_PATH}"
    local i
    for (( i = 0; i < MP_MAX; i++ )); do
        hub_slot_reset "${i}"
    done
    hub_listen || die "Cannot listen for connections"
    now_ms
    HUB_STARTED_MS="${NOW_MS}"
    HUB_NEXT_BEACON_MS=0
    HUB_NEXT_PING_MS=$(( NOW_MS + MP_PING_MS ))
    debug_event "hub: session '${MP_SESSION}' up (transport=${MP_TRANSPORT} max=${MP_MAX} target=${MP_TARGET})"
    while [ "${HUB_RUN}" -eq 1 ]; do
        n=0
        while [ "${n}" -lt "${HUB_BATCH_MAX}" ]; do
            line=""
            rc=0
            IFS= read -r -t 0.05 -u 9 line || rc=$?
            if [ "${rc}" -gt 128 ]; then
                # Timed out - the normal case, and then the variable is
                # empty and this is just the clock. It is not always
                # empty though: a read that runs into its timeout in the
                # middle of a line hands back the part it did get, and
                # dropping that would lose the line and everything the
                # same message still had to say. It happens when the hub
                # is descheduled mid-read, which is exactly what a full
                # session on a busy machine does - measured once in a
                # four player round, where it cost one player's move
                # window: on screen nothing at all, since the next board
                # snapshot papers over it, but the demo recording of
                # that round keeps the hole for good (CLAUDE.md 5.20).
                # So the part is kept and the remainder glued in front
                # of it next time, exactly as the client's receive path
                # does it (NET_PART in net_poll, lib/net.sh) - including
                # the cap, so a writer sending MP_LINE_MAX bytes without
                # a newline cannot make this buffer grow.
                HUB_INBOX_PART="${HUB_INBOX_PART}${line}"
                if [ "${#HUB_INBOX_PART}" -ge "${MP_LINE_MAX}" ]; then
                    HUB_INBOX_PART=""
                fi
                break
            fi
            line="${HUB_INBOX_PART}${line}"
            HUB_INBOX_PART=""
            if [ -z "${line}" ]; then
                break
            fi
            n=$(( n + 1 ))
            id="${line%% *}"
            rest="${line#* }"
            [[ "${id}" =~ ${MP_NUM_RE} ]] || continue
            case "${rest}" in
                _OPEN) hub_client_open "${id}" ;;
                _EOF)  hub_client_close "${id}" ;;
                _PEER\ *) hub_client_addr "${id}" "${rest#_PEER }" ;;
                *)     hub_client_msg "${id}" "${rest}" ;;
            esac
            # Nothing more waiting: leave the batch so the periodic work
            # below runs promptly instead of after another timeout.
            read -t 0 -u 9 2>/dev/null || break
        done
        hub_periodic
    done
    debug_event "hub: session '${MP_SESSION}' down"
    return 0
}

# --- Bridge ---------------------------------------------------------------
# hub_bridge_main
# The body of "rowhammer.sh --mp-bridge": one process per connection,
# started by socat with the socket on its standard input and output. It
# owns no game state and understands no message; it moves lines between
# the socket and the hub's FIFOs and cuts them to length on the way in.
# Its process id is the client id the hub knows it by - unique for as long
# as the connection lives, which is exactly as long as it is needed.
hub_bridge_main() {
    local inbox="${ROWHAMMER_MP_INBOX:-}" down_prefix="${ROWHAMMER_MP_DOWN:-}"
    local id=$$ down line cat_pid=0
    if [ -z "${inbox}" ] || [ ! -p "${inbox}" ] || [ -z "${down_prefix}" ]; then
        return 1
    fi
    umask 0077
    down="${down_prefix}.${id}"
    mkfifo -m 0600 -- "${down}" 2>/dev/null || return 1
    # Held open read-write for as long as this connection lives, and
    # opened before the hub is told the connection exists. Both halves
    # matter: a FIFO's buffer only exists while somebody has it open, so
    # a hub that opens it, writes and closes again - which is what a
    # single write does - would have its message thrown away with the
    # pipe if nobody else were holding it. This descriptor is that
    # somebody, and it also means the hub can answer the very first
    # message without racing the reader below into existence.
    exec 8<>"${down}" || return 1
    printf '%s _OPEN\n' "${id}" >>"${inbox}" 2>/dev/null || return 1
    # The address this connection came from, which only a process socat
    # started can see (SOCAT_PEERADDR). The hub needs it for exactly one
    # thing: when the host leaves, it has to tell everybody where the
    # session has moved to, and that is the new host's address. Cut hard
    # and checked by the hub - it is data from the network like any other.
    printf '%s _PEER %s\n' "${id}" "${SOCAT_PEERADDR:-none}" \
        >>"${inbox}" 2>/dev/null || return 1
    # Everything the hub writes for this client goes straight to the
    # socket.
    cat <&8 &
    cat_pid=$!
    while IFS= read -r line; do
        # Cut rather than reject: the hub's parser decides what a line
        # means, this end only makes sure it stays within the length the
        # protocol allows - which is also what keeps the write into the
        # shared inbox atomic.
        line="${line:0:${MP_LINE_MAX}}"
        printf '%s %s\n' "${id}" "${line}" >>"${inbox}" 2>/dev/null || break
    done
    printf '%s _EOF\n' "${id}" >>"${inbox}" 2>/dev/null || :
    if [ "${cat_pid}" -gt 0 ]; then
        kill "${cat_pid}" 2>/dev/null || :
    fi
    rm -f -- "${down}" 2>/dev/null || :
    return 0
}
