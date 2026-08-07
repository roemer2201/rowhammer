#!/usr/bin/env bash
#
# lib/proto.sh
#
# Description:
#   Message table, builders and validating parser of the LAN
#   multiplayer. This module knows the messages and nothing else: it has
#   no socket (that is lib/net.sh) and draws no screen (lib/mp.sh). One
#   message is one line of printable ASCII, fields separated by single
#   spaces, the first field the verb in capitals.
#   Everything the parser accepts has been checked field by field
#   against its own pattern first; an unknown verb, a wrong field count
#   or a single field that misses its pattern throws the whole line
#   away. That is deliberately a whitelist and not a filter for known
#   bad input: on a LAN bus anybody can send anything, and a message
#   from a stranger must not be able to reach an arithmetic expansion,
#   an array index or a terminal (see CLAUDE.md section 5.5). Nothing
#   received is ever eval'd, sourced or substituted, and no number is
#   used in $(( )) before it has matched PROTO_NUM_RE.
#   The protocol has no server: every message goes to everybody on the
#   bus and carries the session id it belongs to, so a receiver picks
#   out what concerns it. The host of a session is the authority for
#   that session, which is why the answers to a join come from it and
#   not from a central instance.
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 1.0.0  (2026-08-07)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/proto.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# Protocol version. A message that names a different one is dropped
# without an answer: the game follows the "no backwards compatibility"
# working rule (CLAUDE.md section 6), so this counts up whenever the
# message table changes instead of the table growing compatible
# variants. Silently, because two incompatible versions on one bus is
# not an error either side can fix at runtime.
PROTO_VERSION=1

# Field patterns. Every field of every message is matched against
# exactly one of these before it is used for anything.
#   ID   - session and player ids, generated locally (proto_new_id)
#   NAME - player and session names, the charset the player name has
#          used since 0.2.0, so a name that passes the settings menu
#          passes here as well
#   NUM  - any count; the length limit keeps it inside the range bash
#          computes exactly and away from anything that could overflow
#   MODE - a game mode name (marathon, ultra, ...)
#   STATE- what a session or a player is doing
PROTO_ID_RE='^[0-9a-f]{8}$'
PROTO_NAME_RE='^[A-Za-z0-9_-]{1,16}$'
PROTO_NUM_RE='^[0-9]{1,9}$'
PROTO_MODE_RE='^[a-z]{1,12}$'
PROTO_STATE_RE='^(lobby|play|done)$'
PROTO_READY_RE='^[01]$'
PROTO_REASON_RE='^[a-z]{1,12}$'

# The verbs, and how many fields each of them carries after the verb
# itself. The parser reads the count from here, so a message with a
# field too many or too few is rejected before any field is looked at.
#   ANNOUNCE <proto> <session> <host> <players> <max> <mode> <state>
#       A host offering a lobby, repeated while the lobby is open. This
#       is the whole "list of open games without a server": everybody
#       hears it, nobody has to be asked. A session is named after its
#       host - one name per lobby is what the browser shows, and asking
#       for a second one would be a text prompt for nothing.
#   CLOSED   <proto> <session>
#       The host closed the lobby. Only an optimization - a lobby that
#       stops announcing disappears by itself once it times out - but it
#       makes leaving look immediate on everybody else's screen.
#   DISCOVER <proto>
#       Somebody opened the game browser and would rather not wait for
#       the next announcement round; hosts answer at once.
#   JOIN     <proto> <session> <player> <name>
#       A client asks to be let into a session.
#   WELCOME  <proto> <session> <player> <slot>
#       The host lets that player in, on that slot.
#   DENY     <proto> <session> <player> <reason>
#       The host refuses (full, closed, name already taken).
#   ROSTER   <proto> <session> <count> <slot> <player> <name> <ready>
#       One line per player in the lobby, sent by the host whenever the
#       list changes. The list is the host's, so it is sent whole rather
#       than as differences: six lines cost nothing and a client that
#       missed a datagram is correct again with the next round. Every
#       line carries the length of the whole roster, which is what lets
#       a receiver notice that somebody left: the slots above <count>
#       are stale and are simply not shown any more.
#   READY    <proto> <session> <player> <0|1>
#       A client changing its readiness.
#   ALIVE    <proto> <session> <player>
#       A client saying it is still there; the host drops a player it
#       has not heard from for MP_PEER_TIMEOUT_MS.
#   LEAVE    <proto> <session> <player>
#       A client leaving the lobby.
declare -A PROTO_ARITY=(
    [ANNOUNCE]=7
    [CLOSED]=2
    [DISCOVER]=1
    [JOIN]=4
    [WELCOME]=4
    [DENY]=4
    [ROSTER]=7
    [READY]=4
    [ALIVE]=3
    [LEAVE]=3
)

# Result of the last proto_parse: the verb and the fields, one per
# array slot (PROTO_F[0] is the first field after the verb). Both are
# only meaningful while proto_parse returned 0.
PROTO_VERB=""
PROTO_F=()

# Scratch results of the helpers below, declared here so every one of
# them is a plain global and no function has to return a string through
# a subshell: PROTO_ID (a fresh id), PROTO_NAME (a sanitized name),
# PROTO_KINDS (the field kinds of one verb) and PROTO_LINE (the message
# a builder has just assembled).
PROTO_ID=""
PROTO_NAME=""
PROTO_KINDS=()
PROTO_LINE=""

# proto_new_id
# A fresh 8 hex digit id into PROTO_ID, used for the session a host
# opens and for the player a client is. RANDOM twice because it only
# yields 15 bits; the id has to be unlikely to collide on one LAN, not
# unguessable - the protocol grants nothing to whoever knows an id that
# a listener on the same bus would not see anyway.
proto_new_id() {
    printf -v PROTO_ID '%04x%04x' \
        "$(( RANDOM & 0xffff ))" "$(( RANDOM & 0xffff ))"
    return 0
}

# proto_name_sanitize NAME
# Reduce a name to what the protocol carries, into PROTO_NAME. The
# player name comes from the config file and may hold anything that got
# past an older version or a hand-edited file; sending it unchecked
# would only produce messages everybody else has to discard. Characters
# outside the pattern are dropped, the rest is cut to 16, and a name
# that ends up empty becomes "Player" so a lobby never shows a nameless
# slot.
proto_name_sanitize() {
    local LC_ALL=C
    local name="${1}"
    name="${name//[^A-Za-z0-9_-]/}"
    name="${name:0:16}"
    if [ -z "${name}" ]; then
        name="Player"
    fi
    PROTO_NAME="${name}"
    return 0
}

# proto_field_ok VALUE PATTERN_NAME
# Check one field against the pattern of its kind. The pattern is
# selected by name rather than passed in, so every caller uses the same
# ones and a new message cannot quietly invent a looser rule.
proto_field_ok() {
    local value="${1}" kind="${2}"
    case "${kind}" in
        id)     [[ "${value}" =~ ${PROTO_ID_RE} ]] ;;
        name)   [[ "${value}" =~ ${PROTO_NAME_RE} ]] ;;
        num)    [[ "${value}" =~ ${PROTO_NUM_RE} ]] ;;
        mode)   [[ "${value}" =~ ${PROTO_MODE_RE} ]] ;;
        state)  [[ "${value}" =~ ${PROTO_STATE_RE} ]] ;;
        ready)  [[ "${value}" =~ ${PROTO_READY_RE} ]] ;;
        reason) [[ "${value}" =~ ${PROTO_REASON_RE} ]] ;;
        *)      return 1 ;;
    esac
}

# proto_kinds VERB
# The kind of every field of a message, in order, into PROTO_KINDS. The
# leading "num" of each is the protocol version, which is checked like
# any other field and then compared in proto_parse.
proto_kinds() {
    case "${1}" in
        ANNOUNCE) PROTO_KINDS=(num id name num num mode state) ;;
        CLOSED)   PROTO_KINDS=(num id) ;;
        DISCOVER) PROTO_KINDS=(num) ;;
        JOIN)     PROTO_KINDS=(num id id name) ;;
        WELCOME)  PROTO_KINDS=(num id id num) ;;
        DENY)     PROTO_KINDS=(num id id reason) ;;
        ROSTER)   PROTO_KINDS=(num id num num id name ready) ;;
        READY)    PROTO_KINDS=(num id id ready) ;;
        ALIVE)    PROTO_KINDS=(num id id) ;;
        LEAVE)    PROTO_KINDS=(num id id) ;;
        *)        PROTO_KINDS=(); return 1 ;;
    esac
    return 0
}

# proto_parse LINE
# Validate one received line and split it into PROTO_VERB and PROTO_F.
# Returns 0 when the line is a message this version understands, 1 for
# everything else - an unknown verb, a wrong number of fields, a field
# that misses its pattern or a foreign protocol version. There is no
# third answer on purpose: a caller cannot accidentally work with a
# half-checked message.
# The line has already passed the transport filter (printable ASCII,
# length), so splitting it on spaces cannot produce anything but plain
# words here.
proto_parse() {
    local line="${1}"
    PROTO_VERB=""
    PROTO_F=()
    # Word splitting on a single space, without globbing: the fields are
    # taken as they came in and nothing in them is expanded.
    local -a parts
    local IFS=' '
    read -r -a parts <<<"${line}" || return 1
    if [ "${#parts[@]}" -lt 1 ]; then
        return 1
    fi
    local verb="${parts[0]}"
    # Whitelist: the verb has to be a key of the arity table. Checked
    # before it is used as a key anywhere else, because an arbitrary
    # string as the index of an associative array is exactly the kind of
    # value the security rules keep away from expansions.
    if [ -z "${PROTO_ARITY[${verb}]+x}" ]; then
        return 1
    fi
    local want="${PROTO_ARITY[${verb}]}"
    if [ "${#parts[@]}" -ne $(( want + 1 )) ]; then
        return 1
    fi
    proto_kinds "${verb}" || return 1
    local i
    for (( i = 0; i < want; i++ )); do
        if ! proto_field_ok "${parts[i + 1]}" "${PROTO_KINDS[i]}"; then
            return 1
        fi
    done
    # Field 0 is the protocol version in every message; a different one
    # is not ours to interpret.
    if [ "${parts[1]}" != "${PROTO_VERSION}" ]; then
        return 1
    fi
    PROTO_VERB="${verb}"
    PROTO_F=("${parts[@]:1}")
    return 0
}

# --- Builders -------------------------------------------------------------
# One function per message, each building the line into PROTO_LINE. They
# are separate from the parser so a caller never assembles a message by
# hand: the field order lives here once, and every line the game sends
# goes back through the same validation on the receiving side anyway.

# proto_announce SESSION HOST PLAYERS MAX MODE STATE
proto_announce() {
    printf -v PROTO_LINE 'ANNOUNCE %s %s %s %s %s %s %s' \
        "${PROTO_VERSION}" "${1}" "${2}" "${3}" "${4}" "${5}" "${6}"
}

# proto_closed SESSION
proto_closed() {
    printf -v PROTO_LINE 'CLOSED %s %s' "${PROTO_VERSION}" "${1}"
}

# proto_discover
proto_discover() {
    printf -v PROTO_LINE 'DISCOVER %s' "${PROTO_VERSION}"
}

# proto_join SESSION PLAYER NAME
proto_join() {
    printf -v PROTO_LINE 'JOIN %s %s %s %s' \
        "${PROTO_VERSION}" "${1}" "${2}" "${3}"
}

# proto_welcome SESSION PLAYER SLOT
proto_welcome() {
    printf -v PROTO_LINE 'WELCOME %s %s %s %s' \
        "${PROTO_VERSION}" "${1}" "${2}" "${3}"
}

# proto_deny SESSION PLAYER REASON
proto_deny() {
    printf -v PROTO_LINE 'DENY %s %s %s %s' \
        "${PROTO_VERSION}" "${1}" "${2}" "${3}"
}

# proto_roster SESSION COUNT SLOT PLAYER NAME READY
proto_roster() {
    printf -v PROTO_LINE 'ROSTER %s %s %s %s %s %s %s' \
        "${PROTO_VERSION}" "${1}" "${2}" "${3}" "${4}" "${5}" "${6}"
}

# proto_ready SESSION PLAYER READY
proto_ready() {
    printf -v PROTO_LINE 'READY %s %s %s %s' \
        "${PROTO_VERSION}" "${1}" "${2}" "${3}"
}

# proto_alive SESSION PLAYER
proto_alive() {
    printf -v PROTO_LINE 'ALIVE %s %s %s' "${PROTO_VERSION}" "${1}" "${2}"
}

# proto_leave SESSION PLAYER
proto_leave() {
    printf -v PROTO_LINE 'LEAVE %s %s %s' "${PROTO_VERSION}" "${1}" "${2}"
}
