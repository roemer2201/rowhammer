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
# Version: 1.0.0  (2026-08-11)

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
HUB_PLACE=()
HUB_LAST_MS=()
HUB_OPEN_MS=()
HUB_HELLO=()
HUB_BAD=()

# Bridge id -> slot. The id is the bridge's process id, which is unique
# for as long as the connection lives.
declare -A HUB_SLOT_OF_ID=()

# Session-wide state: whether the loop runs, whether the round is on,
# the roster's "something changed" flag and the timestamps of the periodic
# work.
HUB_RUN=1
HUB_PLAYING=0
HUB_ROSTER_DIRTY=1
HUB_NEXT_BEACON_MS=0
HUB_NEXT_PING_MS=0
HUB_PING_TOKEN=0
HUB_INBOX_PATH=""
HUB_DOWN_PREFIX=""
HUB_SOCAT_PID=0
HUB_LISTEN_PATH=""

# hub_slot_free
# Index of the first free slot in HUB_FREE_SLOT, or -1 when the session is
# full. Slots are handed out low first, so the host is always slot 0 - the
# one place the "who may start the round" question is answered.
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
    debug_event "hub: connection ${id} -> slot ${slot}"
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
        return 0
    fi
    debug_event "hub: slot ${slot} (${HUB_NAME[slot]:-unnamed}) left"
    hub_slot_reset "${slot}"
    HUB_ROSTER_DIRTY=1
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
        READY)  hub_msg_ready "${slot}" ;;
        STATE)  hub_msg_state "${slot}" ;;
        BOARD)  hub_msg_board "${slot}" ;;
        CLEAR)  hub_msg_clear "${slot}" ;;
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
    proto_msg WELCOME "${slot}" "${PROTO_VERSION}" "${MP_MAX}"
    hub_send "${slot}" "${PROTO_LINE}" || :
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
    if [ "${slot}" -eq 0 ] && [ "${PROTO_ARG[0]}" -eq 1 ] \
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
    proto_msg GARBAGE "${count}" "${hole}"
    hub_send "${slot}" "${PROTO_LINE}" || :
    debug_event "hub: ${count} garbage row(s) hole=${hole} -> slot ${slot} (${HUB_NAME[slot]}), queue=${HUB_PENDING[slot]}"
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
    hub_attack "${lines}" "${PROTO_ARG[1]}" "${PROTO_ARG[2]}"
    cancel="${HUB_ATTACK}"
    if [ "${cancel}" -gt "${HUB_PENDING[slot]}" ]; then
        cancel="${HUB_PENDING[slot]}"
    fi
    if [ "${cancel}" -gt 0 ]; then
        HUB_PENDING[slot]=$(( ${HUB_PENDING[slot]} - cancel ))
        proto_msg QUEUE "${HUB_PENDING[slot]}"
        hub_send "${slot}" "${PROTO_LINE}" || :
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
    if [ "${HUB_ALIVE}" -le 1 ]; then
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
    for (( i = 0; i < MP_MAX; i++ )); do
        [ -n "${HUB_ID[i]}" ] || continue
        HUB_STATE[i]="play"
        HUB_PENDING[i]=0
        HUB_PLACE[i]=0
    done
    HUB_PLAYING=1
    proto_msg SEED "${seed}"
    hub_bcast "${PROTO_LINE}"
    proto_msg START "${HUB_COUNTDOWN_MS}"
    hub_bcast "${PROTO_LINE}"
    HUB_ROSTER_DIRTY=1
    hub_count_players
    debug_event "hub: round starts with ${HUB_PLAYERS} player(s), seed=${seed}, target mode=${MP_TARGET}"
    return 0
}

# hub_end_round
# The round is decided: the last player standing wins. If the last two
# went out in the same moment - which the loop can produce, since two
# messages are handled one after the other - the higher row credit
# decides and the lower slot breaks a tie, exactly as CLAUDE.md 5.8 says.
hub_end_round() {
    local i winner=-1 best=-1
    for (( i = 0; i < MP_MAX; i++ )); do
        [ -n "${HUB_NAME[i]}" ] || continue
        if [ "${HUB_STATE[i]}" = "play" ]; then
            winner="${i}"
            break
        fi
    done
    if [ "${winner}" -lt 0 ]; then
        for (( i = 0; i < MP_MAX; i++ )); do
            [ -n "${HUB_NAME[i]}" ] || continue
            if [ "${HUB_ROWS[i]}" -gt "${best}" ]; then
                best="${HUB_ROWS[i]}"
                winner="${i}"
            fi
        done
    fi
    if [ "${winner}" -ge 0 ]; then
        HUB_PLACE[winner]=1
    fi
    HUB_PLAYING=0
    proto_msg END "${winner}"
    hub_bcast "${PROTO_LINE}"
    debug_event "hub: round over, winner slot ${winner} (${HUB_NAME[winner]:-none})"
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
            debug_event "hub: listening on tcp/${MP_PORT}"
            return 0
        fi
        port=$(( port + 1 ))
        net_port_ok "${port}" || return 1
    done
    return 1
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
    HUB_INBOX_PATH="${MP_DIR}/${MP_SESSION}.inbox"
    HUB_DOWN_PREFIX="${MP_DIR}/${MP_SESSION}.down"
    trap 'hub_cleanup' EXIT
    trap 'HUB_RUN=0' INT TERM
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
