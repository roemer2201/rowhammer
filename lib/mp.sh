#!/usr/bin/env bash
#
# lib/mp.sh
#
# Description:
#   LAN multiplayer, lobby stage: opening a game, finding the games
#   other people have opened, joining one and waiting there together
#   until everybody is ready. The round itself follows in a later step
#   (see CLAUDE.md section 5 and its roadmap); everything up to the
#   start of a round lives here.
#   There is no server anywhere in this: a host announces its lobby onto
#   the shared UDP bus (lib/net.sh) about once a second, and every
#   rowhammer listening on that bus builds the list of open games out of
#   what it hears. Nothing has to be installed, configured or started
#   for that, and no machine is special - the list exists as long as
#   somebody is announcing, and a lobby disappears from it when its
#   announcements stop. The host of a session is the authority for that
#   one session: it hands out the slots, keeps the roster and is the
#   only one whose roster the others display.
#   Every screen here is built as an array of plain lines and drawn with
#   render_menu_frame (lib/render.sh), like the menus - and unlike the
#   menus these loops keep working while they wait: one net_poll per
#   input tick, so the list stays live while the cursor sits on it.
#   Received data is validated in lib/proto.sh before it reaches this
#   module, and this module keeps it that way: a name arriving from the
#   network is cut to the width of its column before it is drawn, and
#   the number of sessions and players kept is bounded, so neither a
#   noisy nor a hostile network can grow anything without limit
#   (CLAUDE.md section 5.5).
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 1.0.0  (2026-08-07)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/mp.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# --- Timing ---------------------------------------------------------------
# All in milliseconds of wall clock time (now_ms), not of play time: a
# lobby has no round running and therefore no play clock.
# A host announces once a second and a client says it is still there
# just as often, so a lobby that has gone away is noticed within a few
# seconds without the bus carrying noticeable traffic: one datagram per
# participant per second.
MP_ANNOUNCE_MS=1000
MP_ALIVE_MS=1000
# How often the host repeats the roster even though nothing changed. It
# is sent on every change already; this is what makes a lost datagram
# cost a moment of staleness instead of a permanently wrong list on
# somebody's screen. Slower than the announcement, because it is several
# messages and nobody is waiting for it - a change sends it at once.
MP_ROSTER_MS=2000
# How long an announcement keeps a session in the browser list, and how
# long a silent player keeps its slot. Both are several announcement
# intervals, so a single lost datagram - which on UDP is normal and not
# an error - never makes an entry flicker.
MP_SESSION_TIMEOUT_MS=5000
MP_PEER_TIMEOUT_MS=6000
# How often a client repeats its join request while it waits, and how
# long it waits before giving up. The request is repeated because a
# datagram can be lost and there is nobody to notice that but us.
MP_JOIN_RETRY_MS=500
MP_JOIN_TIMEOUT_MS=5000
# The floor between two answers to a DISCOVER. Without it, a host would
# reply to every single discovery message on the bus, which is exactly
# the amplifier somebody flooding the bus would be looking for.
MP_DISCOVER_MIN_MS=250

# --- Limits ---------------------------------------------------------------
# The most sessions the browser keeps. Everything on the bus can claim
# to be a session, so this is what bounds the list - a screen shows a
# handful of them anyway, and a network that really has more open games
# than this has other problems.
MP_SEEN_LIMIT=32
# The most messages processed per second. A datagram bus has no
# connection to drop, so a sender that will not stop is answered by
# ignoring the rest of its second; the lobby keeps running either way.
MP_MSG_PER_SEC=200

# --- State ----------------------------------------------------------------
# Our own player id for this session, and the id of the session we are
# in (empty when we are in none). MP_ROLE is "host" or "client".
MP_SELF=""
MP_SESSION=""
MP_ROLE=""
MP_SELF_NAME=""
# The roster, as parallel arrays indexed by slot; MP_SLOT_N is how many
# of them are in use. Slot 0 is the host in every session. The host owns
# this list and keeps it compact (no holes), so a client can rebuild it
# from the ROSTER messages by index alone.
MP_SLOT_ID=()
MP_SLOT_NAME=()
MP_SLOT_READY=()
MP_SLOT_SEEN=()
MP_SLOT_N=0
# Which slot we are on (host: always 0).
MP_SLOT_SELF=0
# The sessions heard on the bus, again as parallel arrays; MP_SEEN_N is
# how many are in use.
MP_SEEN_ID=()
MP_SEEN_HOST=()
MP_SEEN_PLAYERS=()
MP_SEEN_MAX=()
MP_SEEN_MODE=()
MP_SEEN_STATE=()
MP_SEEN_MS=()
MP_SEEN_N=0
# Timers and the per-second message budget.
MP_LAST_ANNOUNCE_MS=0
MP_LAST_ROSTER_MS=0
MP_LAST_ALIVE_MS=0
MP_LAST_DISCOVER_MS=0
MP_LAST_HEARD_MS=0
MP_BUDGET=0
MP_BUDGET_SEC=0
# Raised by a message handler when the screen has to be rebuilt, and by
# the client handlers when the lobby has to be left (with MP_LEAVE_MSG
# naming the translation key of the reason).
MP_DIRTY=0
MP_LEAVE=0
MP_LEAVE_MSG=""
# Whether a client's join has been answered with a WELCOME.
MP_JOINED=0
# Scratch results of the helpers below, declared here so none of them
# has to return a string through a subshell: the index a lookup found
# (MP_SEEN_IDX, MP_SLOT_IDX), a padded field (MP_PAD), the display name
# of a mode (MP_MODE_LABEL) and the roster as display lines (MP_LINES).
MP_SEEN_IDX=-1
MP_SLOT_IDX=-1
MP_PAD=""
MP_MODE_LABEL=""
MP_LINES=()
# The mode a lobby plays. Only "versus" exists, and the round it names
# is not implemented yet; it travels in the announcement from the start
# so the browser has something to show and a later mode does not change
# the message table.
MP_MODE="versus"

# mp_reset_session
# Forget everything about a session. Called when one is opened, joined
# or left, so no state of the previous one can leak into the next.
mp_reset_session() {
    MP_SESSION=""
    MP_ROLE=""
    MP_SLOT_ID=()
    MP_SLOT_NAME=()
    MP_SLOT_READY=()
    MP_SLOT_SEEN=()
    MP_SLOT_N=0
    MP_SLOT_SELF=0
    MP_LEAVE=0
    MP_LEAVE_MSG=""
    return 0
}

# mp_self_name
# Our name on the bus: the player name from the settings, reduced to
# what the protocol carries (proto_name_sanitize). Read once when a
# lobby is entered rather than per message, because it cannot change
# while a lobby is open - the settings menu is not reachable from there.
mp_self_name() {
    proto_name_sanitize "${PLAYER_NAME}"
    MP_SELF_NAME="${PROTO_NAME}"
    return 0
}

# mp_mode_label MODE
# What a mode is called on screen, into MP_MODE_LABEL. A mode this
# version has no name for is printed as it arrived - which is safe,
# because the parser has already reduced it to at most twelve lowercase
# letters - instead of being hidden behind a placeholder: a lobby of a
# newer version should still be recognizable in the list.
mp_mode_label() {
    local key="mode_${1}"
    if [ "${1}" = "versus" ]; then
        MP_MODE_LABEL="${I18N[mp_mode_versus]}"
    elif [ -n "${I18N[${key}]:-}" ]; then
        MP_MODE_LABEL="${I18N[${key}]}"
    else
        MP_MODE_LABEL="${1}"
    fi
    return 0
}

# mp_budget_ok
# Whether another message may be processed this second. The budget is
# refilled once per wall clock second; NOW_MS is expected to be current
# (the pump reads the clock before it starts).
mp_budget_ok() {
    local sec=$(( NOW_MS / 1000 ))
    if [ "${sec}" -ne "${MP_BUDGET_SEC}" ]; then
        MP_BUDGET_SEC="${sec}"
        MP_BUDGET=0
    fi
    if [ "${MP_BUDGET}" -ge "${MP_MSG_PER_SEC}" ]; then
        return 1
    fi
    MP_BUDGET=$(( MP_BUDGET + 1 ))
    return 0
}

# mp_send LINE
# Put a built message on the bus and note a lost bus as a reason to
# leave the lobby - there is nothing left to be in once the socket is
# gone.
mp_send() {
    if net_send "${1}"; then
        return 0
    fi
    if [ "${NET_OPEN}" -eq 0 ]; then
        MP_LEAVE=1
        MP_LEAVE_MSG="mp_lost"
    fi
    return 1
}

# --- Session list (browser side) -----------------------------------------

# mp_seen_index ID
# The slot of a session in the browser list, into MP_SEEN_IDX; -1 when
# it is not in the list yet.
mp_seen_index() {
    local i
    MP_SEEN_IDX=-1
    for (( i = 0; i < MP_SEEN_N; i++ )); do
        if [ "${MP_SEEN_ID[i]}" = "${1}" ]; then
            MP_SEEN_IDX="${i}"
            return 0
        fi
    done
    return 0
}

# mp_seen_update ID HOST PLAYERS MAX MODE STATE
# Enter or refresh one announced session. All six values have been
# validated by proto_parse; the numbers are still capped here, because
# they are the host's claim about itself and a display should not be at
# the mercy of it (a "0/999999999" would push the columns apart).
mp_seen_update() {
    local id="${1}" host="${2}" players="${3}" max="${4}" mode="${5}" state="${6}"
    if [ "${players}" -gt 99 ]; then
        players=99
    fi
    if [ "${max}" -gt 99 ]; then
        max=99
    fi
    mp_seen_index "${id}"
    local i="${MP_SEEN_IDX}"
    if [ "${i}" -lt 0 ]; then
        if [ "${MP_SEEN_N}" -ge "${MP_SEEN_LIMIT}" ]; then
            return 0
        fi
        i="${MP_SEEN_N}"
        MP_SEEN_N=$(( MP_SEEN_N + 1 ))
        MP_DIRTY=1
    fi
    if [ "${MP_SEEN_HOST[i]:-}" != "${host}" ] || \
       [ "${MP_SEEN_PLAYERS[i]:-}" != "${players}" ] || \
       [ "${MP_SEEN_STATE[i]:-}" != "${state}" ]; then
        MP_DIRTY=1
    fi
    MP_SEEN_ID[i]="${id}"
    MP_SEEN_HOST[i]="${host}"
    MP_SEEN_PLAYERS[i]="${players}"
    MP_SEEN_MAX[i]="${max}"
    MP_SEEN_MODE[i]="${mode}"
    MP_SEEN_STATE[i]="${state}"
    MP_SEEN_MS[i]="${NOW_MS}"
    return 0
}

# mp_seen_drop INDEX
# Remove one session from the list, closing the gap by moving the last
# entry into it. The list has no order of its own - it is whatever the
# network happens to be offering - so keeping the original sequence
# would cost a shift for nothing.
mp_seen_drop() {
    local i="${1}" last=$(( MP_SEEN_N - 1 ))
    if [ "${i}" -lt 0 ] || [ "${i}" -gt "${last}" ]; then
        return 0
    fi
    if [ "${i}" -ne "${last}" ]; then
        MP_SEEN_ID[i]="${MP_SEEN_ID[last]}"
        MP_SEEN_HOST[i]="${MP_SEEN_HOST[last]}"
        MP_SEEN_PLAYERS[i]="${MP_SEEN_PLAYERS[last]}"
        MP_SEEN_MAX[i]="${MP_SEEN_MAX[last]}"
        MP_SEEN_MODE[i]="${MP_SEEN_MODE[last]}"
        MP_SEEN_STATE[i]="${MP_SEEN_STATE[last]}"
        MP_SEEN_MS[i]="${MP_SEEN_MS[last]}"
    fi
    unset 'MP_SEEN_ID[last]' 'MP_SEEN_HOST[last]' 'MP_SEEN_PLAYERS[last]' \
        'MP_SEEN_MAX[last]' 'MP_SEEN_MODE[last]' 'MP_SEEN_STATE[last]' \
        'MP_SEEN_MS[last]'
    MP_SEEN_N="${last}"
    MP_DIRTY=1
    return 0
}

# mp_seen_expire
# Drop the sessions nobody has announced for MP_SESSION_TIMEOUT_MS.
mp_seen_expire() {
    local i
    for (( i = MP_SEEN_N - 1; i >= 0; i-- )); do
        if (( NOW_MS - MP_SEEN_MS[i] > MP_SESSION_TIMEOUT_MS )); then
            debug_event "mp: session ${MP_SEEN_ID[i]} timed out of the list"
            mp_seen_drop "${i}"
        fi
    done
    return 0
}

# --- Roster (host side) ---------------------------------------------------

# mp_slot_index PLAYER
# The slot of a player in the roster, into MP_SLOT_IDX; -1 when unknown.
mp_slot_index() {
    local i
    MP_SLOT_IDX=-1
    for (( i = 0; i < MP_SLOT_N; i++ )); do
        if [ "${MP_SLOT_ID[i]}" = "${1}" ]; then
            MP_SLOT_IDX="${i}"
            return 0
        fi
    done
    return 0
}

# mp_slot_name_taken NAME PLAYER
# Whether NAME is already used by somebody other than PLAYER. Two
# identical names in one lobby would make the roster unreadable, and
# during the round they would make it impossible to tell who is being
# attacked.
mp_slot_name_taken() {
    local i
    for (( i = 0; i < MP_SLOT_N; i++ )); do
        if [ "${MP_SLOT_NAME[i]}" = "${1}" ] && \
           [ "${MP_SLOT_ID[i]}" != "${2}" ]; then
            return 0
        fi
    done
    return 1
}

# mp_slot_drop INDEX
# Remove one player from the roster. Unlike the session list this one is
# shifted down: the slots are the seats of the round to come and their
# order is what everybody sees, so a leaving player must not make
# somebody else appear to change seats.
mp_slot_drop() {
    local i="${1}" j
    if [ "${i}" -le 0 ] || [ "${i}" -ge "${MP_SLOT_N}" ]; then
        # Slot 0 is the host and cannot leave its own lobby: it closes
        # it instead.
        return 0
    fi
    for (( j = i; j < MP_SLOT_N - 1; j++ )); do
        MP_SLOT_ID[j]="${MP_SLOT_ID[j + 1]}"
        MP_SLOT_NAME[j]="${MP_SLOT_NAME[j + 1]}"
        MP_SLOT_READY[j]="${MP_SLOT_READY[j + 1]}"
        MP_SLOT_SEEN[j]="${MP_SLOT_SEEN[j + 1]}"
    done
    MP_SLOT_N=$(( MP_SLOT_N - 1 ))
    unset "MP_SLOT_ID[${MP_SLOT_N}]" "MP_SLOT_NAME[${MP_SLOT_N}]" \
        "MP_SLOT_READY[${MP_SLOT_N}]" "MP_SLOT_SEEN[${MP_SLOT_N}]"
    MP_DIRTY=1
    return 0
}

# mp_roster_send
# Send the whole roster, one message per slot. Whole rather than as
# changes: a lost datagram then costs a moment of staleness instead of
# leaving a client permanently out of step, and with at most six players
# the difference is a handful of bytes.
mp_roster_send() {
    local i
    for (( i = 0; i < MP_SLOT_N; i++ )); do
        proto_roster "${MP_SESSION}" "${MP_SLOT_N}" "${i}" \
            "${MP_SLOT_ID[i]}" "${MP_SLOT_NAME[i]}" "${MP_SLOT_READY[i]}"
        mp_send "${PROTO_LINE}" || return 1
    done
    return 0
}

# mp_announce
# Announce our lobby onto the bus. This is the entire discovery: nobody
# is asked, nobody keeps a directory, and whoever is listening has the
# entry a moment later.
mp_announce() {
    proto_announce "${MP_SESSION}" "${MP_SLOT_NAME[0]}" "${MP_SLOT_N}" \
        "${MP_MAX}" "${MP_MODE}" "lobby"
    mp_send "${PROTO_LINE}"
    MP_LAST_ANNOUNCE_MS="${NOW_MS}"
    return 0
}

# --- Message handlers -----------------------------------------------------
# One per role. Both are called from mp_pump with a message already
# parsed into PROTO_VERB/PROTO_F, so neither of them ever sees an
# unchecked field.

# mp_handle_browse
# What the game browser listens for: announcements to put in the list
# and the note that a lobby has closed.
mp_handle_browse() {
    case "${PROTO_VERB}" in
        ANNOUNCE)
            mp_seen_update "${PROTO_F[1]}" "${PROTO_F[2]}" "${PROTO_F[3]}" \
                "${PROTO_F[4]}" "${PROTO_F[5]}" "${PROTO_F[6]}"
            ;;
        CLOSED)
            mp_seen_index "${PROTO_F[1]}"
            if [ "${MP_SEEN_IDX}" -ge 0 ]; then
                mp_seen_drop "${MP_SEEN_IDX}"
            fi
            ;;
    esac
    return 0
}

# mp_handle_host
# What the host of a lobby listens for. Everything not addressed to our
# session is ignored without a word: the bus carries the traffic of
# every lobby on the network, and answering a stranger's message would
# only confuse the lobby it belongs to.
mp_handle_host() {
    local player name
    case "${PROTO_VERB}" in
        DISCOVER)
            # Answer at once instead of at the next interval, but not
            # more often than MP_DISCOVER_MIN_MS.
            if (( NOW_MS - MP_LAST_DISCOVER_MS >= MP_DISCOVER_MIN_MS )); then
                MP_LAST_DISCOVER_MS="${NOW_MS}"
                mp_announce
            fi
            ;;
        JOIN)
            if [ "${PROTO_F[1]}" != "${MP_SESSION}" ]; then
                return 0
            fi
            player="${PROTO_F[2]}"
            name="${PROTO_F[3]}"
            mp_slot_index "${player}"
            if [ "${MP_SLOT_IDX}" -ge 0 ]; then
                # Already in: the welcome was lost on the way, so it is
                # simply repeated. Joining twice has to be harmless -
                # the client cannot tell a lost welcome from a slow one
                # and will keep asking.
                proto_welcome "${MP_SESSION}" "${player}" "${MP_SLOT_IDX}"
                mp_send "${PROTO_LINE}"
                MP_SLOT_SEEN[MP_SLOT_IDX]="${NOW_MS}"
                mp_roster_send
                return 0
            fi
            if [ "${MP_SLOT_N}" -ge "${MP_MAX}" ]; then
                proto_deny "${MP_SESSION}" "${player}" "full"
                mp_send "${PROTO_LINE}"
                return 0
            fi
            if mp_slot_name_taken "${name}" "${player}"; then
                proto_deny "${MP_SESSION}" "${player}" "name"
                mp_send "${PROTO_LINE}"
                return 0
            fi
            MP_SLOT_ID[MP_SLOT_N]="${player}"
            MP_SLOT_NAME[MP_SLOT_N]="${name}"
            MP_SLOT_READY[MP_SLOT_N]=0
            MP_SLOT_SEEN[MP_SLOT_N]="${NOW_MS}"
            proto_welcome "${MP_SESSION}" "${player}" "${MP_SLOT_N}"
            MP_SLOT_N=$(( MP_SLOT_N + 1 ))
            mp_send "${PROTO_LINE}"
            mp_roster_send
            mp_announce
            MP_DIRTY=1
            debug_event "mp: ${name} (${player}) joined slot $(( MP_SLOT_N - 1 ))"
            ;;
        READY)
            if [ "${PROTO_F[1]}" != "${MP_SESSION}" ]; then
                return 0
            fi
            mp_slot_index "${PROTO_F[2]}"
            if [ "${MP_SLOT_IDX}" -le 0 ]; then
                # Unknown player, or slot 0 - the host's readiness is
                # its own business and is not taken from the network.
                return 0
            fi
            MP_SLOT_READY[MP_SLOT_IDX]="${PROTO_F[3]}"
            MP_SLOT_SEEN[MP_SLOT_IDX]="${NOW_MS}"
            MP_DIRTY=1
            mp_roster_send
            ;;
        ALIVE)
            if [ "${PROTO_F[1]}" != "${MP_SESSION}" ]; then
                return 0
            fi
            mp_slot_index "${PROTO_F[2]}"
            if [ "${MP_SLOT_IDX}" -ge 0 ]; then
                MP_SLOT_SEEN[MP_SLOT_IDX]="${NOW_MS}"
            fi
            ;;
        LEAVE)
            if [ "${PROTO_F[1]}" != "${MP_SESSION}" ]; then
                return 0
            fi
            mp_slot_index "${PROTO_F[2]}"
            if [ "${MP_SLOT_IDX}" -gt 0 ]; then
                debug_event "mp: ${MP_SLOT_NAME[MP_SLOT_IDX]} left the lobby"
                mp_slot_drop "${MP_SLOT_IDX}"
                mp_roster_send
                mp_announce
            fi
            ;;
    esac
    return 0
}

# mp_handle_client
# What a client in a lobby listens for. The host's announcement doubles
# as its heartbeat here, which is why it is noted rather than ignored:
# a lobby whose host has gone quiet is one to leave.
mp_handle_client() {
    local slot count
    case "${PROTO_VERB}" in
        ANNOUNCE)
            if [ "${PROTO_F[1]}" = "${MP_SESSION}" ]; then
                MP_LAST_HEARD_MS="${NOW_MS}"
            fi
            ;;
        WELCOME)
            if [ "${PROTO_F[1]}" != "${MP_SESSION}" ] || \
               [ "${PROTO_F[2]}" != "${MP_SELF}" ]; then
                return 0
            fi
            MP_SLOT_SELF="${PROTO_F[3]}"
            MP_JOINED=1
            MP_LAST_HEARD_MS="${NOW_MS}"
            MP_DIRTY=1
            ;;
        DENY)
            if [ "${PROTO_F[1]}" != "${MP_SESSION}" ] || \
               [ "${PROTO_F[2]}" != "${MP_SELF}" ]; then
                return 0
            fi
            MP_LEAVE=1
            case "${PROTO_F[3]}" in
                full) MP_LEAVE_MSG="mp_denied_full" ;;
                name) MP_LEAVE_MSG="mp_denied_name" ;;
                *)    MP_LEAVE_MSG="mp_denied" ;;
            esac
            debug_event "mp: join denied (${PROTO_F[3]})"
            ;;
        ROSTER)
            if [ "${PROTO_F[1]}" != "${MP_SESSION}" ]; then
                return 0
            fi
            count="${PROTO_F[2]}"
            slot="${PROTO_F[3]}"
            # The host's own limit is not ours to trust: a roster longer
            # than a session can be is capped here, before the slot is
            # used as an array index.
            if [ "${count}" -gt "${MP_MAX_LIMIT}" ]; then
                count="${MP_MAX_LIMIT}"
            fi
            if [ "${slot}" -ge "${count}" ]; then
                return 0
            fi
            MP_SLOT_ID[slot]="${PROTO_F[4]}"
            MP_SLOT_NAME[slot]="${PROTO_F[5]}"
            MP_SLOT_READY[slot]="${PROTO_F[6]}"
            MP_SLOT_N="${count}"
            MP_LAST_HEARD_MS="${NOW_MS}"
            MP_DIRTY=1
            ;;
        CLOSED)
            if [ "${PROTO_F[1]}" != "${MP_SESSION}" ]; then
                return 0
            fi
            MP_LEAVE=1
            MP_LEAVE_MSG="mp_host_left"
            ;;
    esac
    return 0
}

# mp_pump HANDLER
# One turn of the network: read what has arrived, hand every message
# that parses to HANDLER. Called once per input tick from each of the
# loops below, so a screen stays live while it waits for a key.
# The handler is called by name from a fixed set of our own functions -
# never from anything that came off the network.
mp_pump() {
    local handler="${1}" line
    net_poll
    if [ "${NET_OPEN}" -eq 0 ] && [ "${#NET_LINES[@]}" -eq 0 ]; then
        MP_LEAVE=1
        MP_LEAVE_MSG="mp_lost"
        return 0
    fi
    for line in ${NET_LINES[@]+"${NET_LINES[@]}"}; do
        if ! mp_budget_ok; then
            break
        fi
        if ! proto_parse "${line}"; then
            continue
        fi
        "${handler}"
    done
    return 0
}

# --- Screens --------------------------------------------------------------

# mp_pad TEXT WIDTH
# Cut TEXT to WIDTH and pad it to exactly that, into MP_PAD. Every field
# that came off the network goes through this before it is drawn: the
# parser bounds a name to 16 characters, but a column is narrower than
# that and a line of the frame has to keep its width (CLAUDE.md 3.4).
mp_pad() {
    local text="${1}" width="${2}"
    text="${text:0:width}"
    printf -v MP_PAD '%-*s' "${width}" "${text}"
    return 0
}

# mp_roster_lines READY_COLUMN
# The roster as display lines, into MP_LINES: slot number, name and
# either "(Host)" or the readiness of that player. Shared by the host
# and the client screen so both show the same list in the same shape.
mp_roster_lines() {
    local i state
    MP_LINES=()
    for (( i = 0; i < MP_SLOT_N; i++ )); do
        if [ "${i}" -eq 0 ]; then
            state="${I18N[mp_is_host]}"
        elif [ "${MP_SLOT_READY[i]:-0}" -eq 1 ]; then
            state="${I18N[mp_ready]}"
        else
            state="${I18N[mp_waiting]}"
        fi
        mp_pad "${MP_SLOT_NAME[i]:-}" 16
        if [ "${MP_SLOT_ID[i]:-}" = "${MP_SELF}" ]; then
            MP_LINES+=("   ${MP_PAD} ${state}  <<")
        else
            MP_LINES+=("   ${MP_PAD} ${state}")
        fi
    done
    return 0
}

# mp_message KEY
# Show one of the module's own messages (a multi-line block from the
# translation table) as an info screen.
mp_message() {
    i18n_lines "${1}"
    menu_message "${I18N[mp_title]}" "${I18N_LINES[@]}"
    return 0
}

# --- Host -----------------------------------------------------------------

# mp_host
# Open a lobby and stay in it until it is closed. The session id is
# generated locally; nothing hands it out, because there is nothing that
# could. A collision would need two hosts to draw the same 32 bits in
# the same few minutes on the same network.
mp_host() {
    mp_reset_session
    mp_self_name
    proto_new_id
    MP_SELF="${PROTO_ID}"
    proto_new_id
    MP_SESSION="${PROTO_ID}"
    MP_ROLE="host"
    MP_SLOT_ID[0]="${MP_SELF}"
    MP_SLOT_NAME[0]="${MP_SELF_NAME}"
    MP_SLOT_READY[0]=1
    MP_SLOT_SEEN[0]=0
    MP_SLOT_N=1
    MP_SLOT_SELF=0
    debug_event "mp: hosting session ${MP_SESSION} as ${MP_SELF_NAME} (max=${MP_MAX})"
    now_ms
    MP_LAST_ANNOUNCE_MS=0
    MP_LAST_ROSTER_MS="${NOW_MS}"
    MP_DIRTY=1

    local -a lines
    local i title players
    while :; do
        now_ms
        mp_pump mp_handle_host
        if [ "${MP_LEAVE}" -eq 1 ]; then
            break
        fi
        # Drop the players that have gone silent. Counted down so a
        # removal does not skip the entry that moves into its place.
        for (( i = MP_SLOT_N - 1; i > 0; i-- )); do
            if (( NOW_MS - MP_SLOT_SEEN[i] > MP_PEER_TIMEOUT_MS )); then
                debug_event "mp: ${MP_SLOT_NAME[i]} timed out of the lobby"
                mp_slot_drop "${i}"
                mp_roster_send
                mp_announce
            fi
        done
        if (( NOW_MS - MP_LAST_ANNOUNCE_MS >= MP_ANNOUNCE_MS )); then
            mp_announce
        fi
        if (( NOW_MS - MP_LAST_ROSTER_MS >= MP_ROSTER_MS )); then
            MP_LAST_ROSTER_MS="${NOW_MS}"
            mp_roster_send
        fi
        if [ "${MP_DIRTY}" -eq 1 ] || [ "${REDRAW_PENDING}" -eq 1 ]; then
            REDRAW_PENDING=0
            MP_DIRTY=0
            printf -v title "${I18N[mp_lobby_title]}" "${MP_SELF_NAME}"
            printf -v players "${I18N[mp_players]}" "${MP_SLOT_N}" "${MP_MAX}"
            lines=("  ${title}" "" "  ${players}" "")
            mp_roster_lines
            lines+=(${MP_LINES[@]+"${MP_LINES[@]}"})
            lines+=("" "  ${I18N[mp_host_keys]}")
            render_menu_frame "${lines[@]}"
            screen_write "${RENDER_MENU_FRAME}"
        fi
        read_key
        case "${KEY}" in
            ENTER|SPACE)
                # The round itself is the next step of the multiplayer
                # roadmap; the lobby around it is complete.
                mp_message mp_round_todo
                MP_DIRTY=1
                ;;
            ESC|x)
                break
                ;;
        esac
    done
    # Tell the network the lobby is gone instead of letting it time out
    # on everybody else's screen.
    if [ "${NET_OPEN}" -eq 1 ]; then
        proto_closed "${MP_SESSION}"
        mp_send "${PROTO_LINE}" || true
    fi
    debug_event "mp: lobby ${MP_SESSION} closed"
    if [ -n "${MP_LEAVE_MSG}" ]; then
        mp_message "${MP_LEAVE_MSG}"
    fi
    mp_reset_session
    return 0
}

# --- Client ---------------------------------------------------------------

# mp_join_wait ID HOST
# Ask to join one session and wait for the answer. Returns 0 once we are
# in, 1 when the host refused, went away or never answered. The request
# is repeated while waiting because a datagram may be lost and nobody
# would ever tell us.
mp_join_wait() {
    local id="${1}" host="${2}"
    MP_SESSION="${id}"
    MP_ROLE="client"
    MP_JOINED=0
    now_ms
    local started="${NOW_MS}" last=0
    local -a lines
    local title note
    printf -v title "${I18N[mp_lobby_title]}" "${host}"
    note="  ${I18N[mp_joining]}"
    lines=("  ${title}" "" "${note}" "" "  ${I18N[mp_cancel_key]}")
    render_menu_frame "${lines[@]}"
    screen_write "${RENDER_MENU_FRAME}"
    while :; do
        now_ms
        mp_pump mp_handle_client
        if [ "${MP_JOINED}" -eq 1 ]; then
            return 0
        fi
        if [ "${MP_LEAVE}" -eq 1 ]; then
            return 1
        fi
        if (( NOW_MS - started > MP_JOIN_TIMEOUT_MS )); then
            MP_LEAVE_MSG="mp_no_answer"
            return 1
        fi
        if (( NOW_MS - last >= MP_JOIN_RETRY_MS )); then
            last="${NOW_MS}"
            proto_join "${MP_SESSION}" "${MP_SELF}" "${MP_SELF_NAME}"
            mp_send "${PROTO_LINE}" || true
        fi
        if [ "${REDRAW_PENDING}" -eq 1 ]; then
            REDRAW_PENDING=0
            render_menu_frame "${lines[@]}"
            screen_write "${RENDER_MENU_FRAME}"
        fi
        read_key
        case "${KEY}" in
            ESC|x)
                MP_LEAVE_MSG=""
                return 1
                ;;
        esac
    done
}

# mp_client_lobby HOST
# Sit in a joined lobby until it is left: toggle readiness, watch the
# roster, notice when the host disappears.
mp_client_lobby() {
    local host="${1}"
    local -a lines
    local title ready=0 players
    MP_DIRTY=1
    now_ms
    MP_LAST_ALIVE_MS="${NOW_MS}"
    MP_LAST_HEARD_MS="${NOW_MS}"
    printf -v title "${I18N[mp_lobby_title]}" "${host}"
    while :; do
        now_ms
        mp_pump mp_handle_client
        if [ "${MP_LEAVE}" -eq 1 ]; then
            break
        fi
        # A host that has stopped announcing is gone; without this the
        # screen would show a lobby that no longer exists.
        if (( NOW_MS - MP_LAST_HEARD_MS > MP_SESSION_TIMEOUT_MS )); then
            MP_LEAVE=1
            MP_LEAVE_MSG="mp_host_left"
            break
        fi
        if (( NOW_MS - MP_LAST_ALIVE_MS >= MP_ALIVE_MS )); then
            MP_LAST_ALIVE_MS="${NOW_MS}"
            proto_alive "${MP_SESSION}" "${MP_SELF}"
            mp_send "${PROTO_LINE}" || true
        fi
        if [ "${MP_DIRTY}" -eq 1 ] || [ "${REDRAW_PENDING}" -eq 1 ]; then
            REDRAW_PENDING=0
            MP_DIRTY=0
            printf -v players "${I18N[mp_players]}" "${MP_SLOT_N}" "${MP_MAX}"
            lines=("  ${title}" "" "  ${players}" "")
            mp_roster_lines
            lines+=(${MP_LINES[@]+"${MP_LINES[@]}"})
            lines+=("" "  ${I18N[mp_client_keys]}")
            render_menu_frame "${lines[@]}"
            screen_write "${RENDER_MENU_FRAME}"
        fi
        read_key
        case "${KEY}" in
            ENTER|SPACE)
                ready=$(( 1 - ready ))
                proto_ready "${MP_SESSION}" "${MP_SELF}" "${ready}"
                mp_send "${PROTO_LINE}" || true
                MP_DIRTY=1
                ;;
            ESC|x)
                break
                ;;
        esac
    done
    if [ "${NET_OPEN}" -eq 1 ]; then
        proto_leave "${MP_SESSION}" "${MP_SELF}"
        mp_send "${PROTO_LINE}" || true
    fi
    debug_event "mp: left lobby ${MP_SESSION}"
    return 0
}

# --- Browser --------------------------------------------------------------

# mp_browse
# The list of open games: everything the bus has announced lately, with
# a cursor on it. The list is live - entries appear and disappear while
# it is on screen - which is why this is a loop of its own instead of a
# menu_run over a fixed set of entries.
mp_browse() {
    mp_reset_session
    mp_self_name
    proto_new_id
    MP_SELF="${PROTO_ID}"
    MP_SEEN_ID=()
    MP_SEEN_HOST=()
    MP_SEEN_PLAYERS=()
    MP_SEEN_MAX=()
    MP_SEEN_MODE=()
    MP_SEEN_STATE=()
    MP_SEEN_MS=()
    MP_SEEN_N=0
    MP_DIRTY=1
    now_ms
    # Ask once instead of waiting up to a full announcement interval for
    # the first entry to appear.
    proto_discover
    mp_send "${PROTO_LINE}" || true
    local -a lines
    local i sel=0 host players mode entry
    while :; do
        now_ms
        mp_pump mp_handle_browse
        if [ "${MP_LEAVE}" -eq 1 ]; then
            break
        fi
        mp_seen_expire
        if [ "${sel}" -ge "${MP_SEEN_N}" ]; then
            sel=$(( MP_SEEN_N > 0 ? MP_SEEN_N - 1 : 0 ))
            MP_DIRTY=1
        fi
        if [ "${MP_DIRTY}" -eq 1 ] || [ "${REDRAW_PENDING}" -eq 1 ]; then
            REDRAW_PENDING=0
            MP_DIRTY=0
            lines=("  ${I18N[mp_browse_title]}" "")
            if [ "${MP_SEEN_N}" -eq 0 ]; then
                lines+=("  ${I18N[mp_searching]}")
            else
                for (( i = 0; i < MP_SEEN_N; i++ )); do
                    mp_pad "${MP_SEEN_HOST[i]}" 16
                    host="${MP_PAD}"
                    printf -v players '%2d/%-2d' \
                        "${MP_SEEN_PLAYERS[i]}" "${MP_SEEN_MAX[i]}"
                    mp_mode_label "${MP_SEEN_MODE[i]}"
                    mp_pad "${MP_MODE_LABEL}" 12
                    mode="${MP_PAD}"
                    entry="${host} ${players} ${mode}"
                    if [ "${i}" -eq "${sel}" ]; then
                        lines+=($'  \e[7m '"${entry}"$' \e[0m')
                    else
                        lines+=("   ${entry} ")
                    fi
                done
            fi
            lines+=("" "  ${I18N[mp_browse_keys]}")
            render_menu_frame "${lines[@]}"
            screen_write "${RENDER_MENU_FRAME}"
        fi
        read_key
        case "${KEY}" in
            UP|w)
                if [ "${MP_SEEN_N}" -gt 0 ]; then
                    sel=$(( (sel + MP_SEEN_N - 1) % MP_SEEN_N ))
                    MP_DIRTY=1
                fi
                ;;
            DOWN|s)
                if [ "${MP_SEEN_N}" -gt 0 ]; then
                    sel=$(( (sel + 1) % MP_SEEN_N ))
                    MP_DIRTY=1
                fi
                ;;
            ENTER|SPACE)
                if [ "${MP_SEEN_N}" -eq 0 ]; then
                    continue
                fi
                host="${MP_SEEN_HOST[sel]}"
                debug_event "mp: joining session ${MP_SEEN_ID[sel]} of ${host}"
                if mp_join_wait "${MP_SEEN_ID[sel]}" "${host}"; then
                    mp_client_lobby "${host}"
                fi
                if [ -n "${MP_LEAVE_MSG}" ]; then
                    mp_message "${MP_LEAVE_MSG}"
                fi
                # Back in the browser: the session state is dropped, the
                # list itself is kept - it is about the network, not
                # about the lobby just left.
                mp_reset_session
                if [ "${NET_OPEN}" -eq 0 ]; then
                    break
                fi
                proto_discover
                mp_send "${PROTO_LINE}" || true
                MP_DIRTY=1
                ;;
            ESC|x)
                break
                ;;
        esac
    done
    if [ -n "${MP_LEAVE_MSG}" ]; then
        mp_message "${MP_LEAVE_MSG}"
    fi
    mp_reset_session
    return 0
}

# --- Entry point ----------------------------------------------------------

# mp_menu
# The "Mehrspieler" main menu entry: open a game or join one. The bus is
# opened once for the whole visit and closed on the way out, so walking
# between the two entries does not restart the helper - and a session
# that has no multiplayer in it never starts one at all.
mp_menu() {
    local -a entries
    while :; do
        entries=("${I18N[mp_host_entry]}" "${I18N[mp_join_entry]}" \
            "${I18N[menu_back]}")
        menu_run "${I18N[mp_title]}" "${entries[@]}"
        case "${MENU_CHOICE}" in
            0|1) : ;;
            *)   break ;;
        esac
        if ! net_open; then
            i18n_lines "${NET_ERROR:-net_no_helper}"
            menu_message "${I18N[mp_title]}" "${I18N_LINES[@]}"
            break
        fi
        if [ "${MENU_CHOICE}" -eq 0 ]; then
            mp_host
        else
            mp_browse
        fi
        # The bus stays open across this loop, so walking between the
        # two entries does not restart the helper. A bus that died took
        # itself out of service; the net_open above opens a fresh one on
        # the next round instead of the menu ending here.
    done
    net_close
    return 0
}
