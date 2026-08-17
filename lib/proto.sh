#!/usr/bin/env bash
#
# lib/proto.sh
#
# Description:
#   Message layer of the rowhammer multiplayer (protocol v1, see
#   CLAUDE.md 5.4/5.5). It turns values into lines and lines back into
#   validated values, and it knows neither sockets (lib/net.sh) nor the
#   screen: what a message means for a round is decided by lib/hub.sh and
#   lib/mp.sh.
#   A message is one line, the first field is the verb, the rest are its
#   arguments. Parsing is a whitelist throughout: proto_parse looks the
#   verb up in a table of the verbs this version knows, checks the number
#   of fields against that table and then every field against its own
#   pattern. Only then do the values land in PROTO_ARG - which means no
#   number reaches an arithmetic expansion or an array index before it has
#   been proven to be a number, the single rule that keeps a peer from
#   running commands in this process ("$(( x ))" evaluates its content
#   recursively).
#   Three outcomes, deliberately distinct: 0 - a valid message, act on it;
#   1 - a malformed message, drop it and count it against the sender
#   (three in a row end the connection); 2 - a verb this version does not
#   know, ignore it silently, which is what lets a later version add one.
#   proto_rate_ok is the receiving end's rate limit, counted per sender and
#   second.
#   The board snapshot of the "full" peer view is 200 characters, one per
#   cell, fixed length rather than run-length encoded: the validation is
#   then a length and a character class and has no gaps.
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 1.1.0  (2026-08-11)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/proto.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# Protocol version. A hub rejects a client that announces a different one
# (ERR proto). Per the project's no-backward-compatibility rule this
# number is raised rather than the protocol extended compatibly.
# Version 2 (1.1.0) added SETUP, the session settings the host decides on
# and everybody sees. A version 1 client would in fact still play, but it
# would never learn the mode of the round it is in and would take a
# missing garbage flag for the old "garbage always on" - which is exactly
# the kind of guessing this number exists to prevent.
PROTO_VERSION=2

# --- Field patterns -------------------------------------------------------
# Every field of every message is checked against exactly one of these.
# Numbers are capped at nine digits so no value can leave the range bash
# arithmetic handles comfortably; the name pattern is the one the player
# name is validated against everywhere else in the game.
PROTO_NUM_RE='^[0-9]{1,9}$'
PROTO_FLAG_RE='^[01]$'
PROTO_NAME_RE='^[A-Za-z0-9_-]{1,16}$'
PROTO_SLOT_RE='^[0-9]$'
PROTO_HOLE_RE='^[0-9]$'
PROTO_STATE_RE='^(lobby|play|ko|gone)$'
PROTO_CAPS_RE='^[a-z,]{0,32}$'
PROTO_TOKEN_RE='^[0-9]{1,9}$'
PROTO_CODE_RE='^[a-z]{1,12}$'
# The rules a multiplayer round runs under, decided by the host in the
# lobby (see hub_msg_setup). One name per win condition - which is what
# makes them different modes rather than settings:
#   survival - last one standing wins (the classic duel)
#   sprint   - most rows when the time limit is up
#   ultra    - first to the row target wins
PROTO_MPMODE_RE='^(survival|sprint|ultra)$'
PROTO_TEXT_RE='^[A-Za-z0-9 ._-]{0,64}$'
# One board cell per character, 200 of them (10 columns x 20 visible
# rows): "." empty, a piece type letter, "g"/"s" for a gold/silver square
# cell and "x" for garbage.
PROTO_BOARD_RE='^[.IOTSZJLgsx]{200}$'

# --- Message table --------------------------------------------------------
# One entry per verb: the number of arguments (without the verb) and the
# pattern class of each, separated by spaces. The parser reads nothing but
# this table, so adding a message is adding a line here - and forgetting
# to add one means the message is ignored rather than trusted.
# Classes: n = number, f = 0/1 flag, s = slot, N = name, S = peer state,
# c = caps list, b = board snapshot, h = hole column, k = token,
# e = error code, t = free text, m = multiplayer mode.
declare -A PROTO_MSG=(
    # Client to hub.
    [HELLO]="n N c"
    [READY]="f"
    [STATE]="n n n n n n n"
    [BOARD]="b"
    [CLEAR]="n n n"
    # The client pushed queued garbage rows into its board. From that
    # moment those rows are part of its stack and can no longer be
    # cancelled by a clear, so the hub takes them off its queue as well -
    # the one number both ends have to agree on (see hub_msg_clear).
    [APPLIED]="n"
    [TOPOUT]=""
    # Whether this client is drawing the opponents' boards (detail level
    # 2, see render_peer_level in lib/render.sh). It is what lets the hub
    # ask for snapshots only while somebody is actually looking at them:
    # a session of small terminals then produces no snapshot traffic at
    # all (CLAUDE.md 5.6).
    [VIEW]="f"
    # The session settings: the mode of the round and whether garbage is
    # on. Sent by the host to change them (the hub refuses it from anybody
    # else and while a round runs) and by the hub to everybody whenever
    # they change - one verb in both directions, like ROSTER, because it
    # carries the same thing either way.
    [SETUP]="m f"
    [PONG]="k"
    [BYE]=""
    # Hub to client.
    [WELCOME]="s n n"
    [ROSTER]="s N f S"
    [SEED]="n"
    [START]="n"
    [PEER]="s n n n n n n n S"
    [PEERBOARD]="s b"
    [NEEDBOARD]="f"
    [GARBAGE]="n h"
    # The authoritative length of this client's garbage queue after the
    # hub cancelled part of it against a clear. The hub owns that number
    # because it owns the arithmetic; a second copy kept on the client
    # could only ever drift away from it.
    [QUEUE]="n"
    [KO]="s n"
    [END]="s"
    [PING]="k"
    [ERR]="e t"
)

# --- Parser ---------------------------------------------------------------
# The verb of the last parsed message and its arguments, 0-based (so
# PROTO_ARG[0] is the first argument, not the verb). Globals rather than
# a return value: the receive path runs per tick and must not fork.
PROTO_VERB=""
PROTO_ARG=()

# proto_field_ok CLASS VALUE
# Check one field against the pattern its class stands for. A class this
# function does not know fails closed - a typo in the table above must
# never turn into an unchecked field.
proto_field_ok() {
    case "${1}" in
        n) [[ "${2}" =~ ${PROTO_NUM_RE} ]] ;;
        f) [[ "${2}" =~ ${PROTO_FLAG_RE} ]] ;;
        s) [[ "${2}" =~ ${PROTO_SLOT_RE} ]] ;;
        N) [[ "${2}" =~ ${PROTO_NAME_RE} ]] ;;
        S) [[ "${2}" =~ ${PROTO_STATE_RE} ]] ;;
        c) [[ "${2}" =~ ${PROTO_CAPS_RE} ]] ;;
        b) [[ "${2}" =~ ${PROTO_BOARD_RE} ]] ;;
        h) [[ "${2}" =~ ${PROTO_HOLE_RE} ]] ;;
        k) [[ "${2}" =~ ${PROTO_TOKEN_RE} ]] ;;
        e) [[ "${2}" =~ ${PROTO_CODE_RE} ]] ;;
        m) [[ "${2}" =~ ${PROTO_MPMODE_RE} ]] ;;
        t) [[ "${2}" =~ ${PROTO_TEXT_RE} ]] ;;
        *) return 1 ;;
    esac
}

# proto_parse LINE
# Split and validate one message. Returns 0 and fills PROTO_VERB/PROTO_ARG
# for a valid one, 2 for a verb this version does not know (ignore it) and
# 1 for anything else: a wrong field count, a field that fails its
# pattern, a lower-case verb, an empty line.
# The line is split on spaces with the shell's word splitting, which is
# safe here because the charset filter in lib/net.sh has already rejected
# every byte outside 0x20-0x7E - there are no tabs, no newlines and no
# quotes with a meaning left in it. The last field of a message that holds
# free text (ERR) is deliberately the only one allowed to contain spaces,
# and it is reassembled rather than split.
proto_parse() {
    local line="${1}" verb spec
    local -a fields spec_a
    local i n
    PROTO_VERB=""
    PROTO_ARG=()
    [ -n "${line}" ] || return 1
    verb="${line%% *}"
    # Verbs are upper case; anything else is not a message of this
    # protocol and is not looked up (an associative array subscript is a
    # string, so an odd verb is harmless here - but it should still not
    # count as "unknown verb, ignore").
    [[ "${verb}" =~ ^[A-Z]{2,12}$ ]] || return 1
    if [ -z "${PROTO_MSG[${verb}]+set}" ]; then
        return 2
    fi
    spec="${PROTO_MSG[${verb}]}"
    # shellcheck disable=SC2206  # deliberate splitting of our own table
    spec_a=(${spec})
    n="${#spec_a[@]}"
    if [ "${n}" -eq 0 ]; then
        # A message without arguments must not carry any.
        [ "${line}" = "${verb}" ] || return 1
        PROTO_VERB="${verb}"
        return 0
    fi
    # shellcheck disable=SC2206  # deliberate splitting of a charset-filtered line
    fields=(${line})
    # The trailing free-text field swallows the rest of the line, so an
    # error message may contain spaces; every other class is one word.
    if [ "${spec_a[n - 1]}" = "t" ] && [ "${#fields[@]}" -gt $(( n + 1 )) ]; then
        local head="" rest
        for (( i = 0; i < n; i++ )); do
            head+="${fields[i]} "
        done
        rest="${line#"${head}"}"
        fields=("${fields[@]:0:n}")
        fields+=("${rest}")
    fi
    [ "${#fields[@]}" -eq $(( n + 1 )) ] || return 1
    for (( i = 0; i < n; i++ )); do
        proto_field_ok "${spec_a[i]}" "${fields[i + 1]}" || return 1
    done
    PROTO_VERB="${verb}"
    PROTO_ARG=("${fields[@]:1}")
    return 0
}

# proto_msg VERB ARG...
# Assemble one message into PROTO_LINE. The arguments are joined with
# single spaces; they are not validated here, because everything this
# game sends is a number it computed itself or a name that went through
# proto_name below - and the last gate before the wire is net_send, which
# refuses a line that is malformed whatever produced it.
PROTO_LINE=""
proto_msg() {
    local verb="${1}"
    shift
    if [ "$#" -eq 0 ]; then
        PROTO_LINE="${verb}"
    else
        PROTO_LINE="${verb} $*"
    fi
    return 0
}

# proto_name NAME
# Reduce a player name to what the protocol accepts, into PROTO_NAME:
# every character outside [A-Za-z0-9_-] is dropped, spaces become
# underscores (a name may hold them locally, the wire format may not), the
# result is cut to 16 characters, and an empty result becomes "Player".
# Outgoing data is sanitized as carefully as incoming data is checked: the
# player name comes from a config file and may be anything, and a client
# should not produce rubbish its peers then have to throw away.
PROTO_NAME=""
proto_name() {
    local name="${1// /_}"
    name="${name//[^A-Za-z0-9_-]/}"
    name="${name:0:16}"
    PROTO_NAME="${name:-Player}"
    return 0
}

# --- Rate limiting --------------------------------------------------------
# Messages counted per sender in the current second, and the second they
# are counted in. Keyed by whatever the caller uses as a sender id (the
# bridge id in the hub, a single fixed key in the client, which only ever
# talks to the hub).
declare -A PROTO_RATE_N=()
declare -A PROTO_RATE_T=()

# proto_rate_ok KEY
# Count one received message from KEY and report whether the sender is
# still within MP_RATE_MAX per second. A sender above it gets no service
# until the second is over; the caller decides whether that means dropping
# the message or the connection.
proto_rate_ok() {
    local key="${1}" sec
    now_ms
    sec=$(( NOW_MS / 1000 ))
    if [ "${PROTO_RATE_T[${key}]:-0}" -ne "${sec}" ]; then
        PROTO_RATE_T["${key}"]="${sec}"
        PROTO_RATE_N["${key}"]=0
    fi
    PROTO_RATE_N["${key}"]=$(( ${PROTO_RATE_N[${key}]} + 1 ))
    [ "${PROTO_RATE_N[${key}]}" -le "${MP_RATE_MAX}" ]
}

# proto_rate_forget KEY
# Drop the counters of a sender that is gone, so a long session does not
# accumulate one entry per connection ever made.
proto_rate_forget() {
    unset "PROTO_RATE_N[${1}]" "PROTO_RATE_T[${1}]"
    return 0
}

# --- Board snapshot -------------------------------------------------------
# proto_board_encode
# Encode the visible board (the 20 rows below the hidden spawn rows) into
# PROTO_BOARD: one character per cell, row by row from the top. A square
# cell is reported as what it is worth to the viewer - "g"/"s" rather than
# the piece type it was built from - and garbage as "x", so the receiving
# end can paint a mini board without knowing anything about instances.
# The falling piece is deliberately not part of it: it would be stale by
# the time it arrived (CLAUDE.md 5.4).
PROTO_BOARD=""
proto_board_encode() {
    local y x idx cell sq s=""
    for (( y = HIDDEN_ROWS; y < BOARD_H; y++ )); do
        for (( x = 0; x < BOARD_W; x++ )); do
            idx=$(( y * BOARD_W + x ))
            cell="${BOARD[idx]}"
            if [ "${cell}" = "${EMPTY_CELL}" ]; then
                s+="."
                continue
            fi
            if [ "${cell}" = "${GARBAGE_CELL}" ]; then
                s+="x"
                continue
            fi
            sq="${BOARD_SQ[idx]}"
            case "${sq}" in
                G) s+="g" ;;
                S) s+="s" ;;
                *) s+="${cell}" ;;
            esac
        done
    done
    PROTO_BOARD="${s}"
    return 0
}

# proto_stack_height
# Height of the highest occupied column of the own board, in rows above
# the floor, into PROTO_HEIGHT. It is one of the numbers a peer shows
# (the compact view draws it as a bar), and it is cheap to compute here
# once per state update rather than sending the whole board for it.
PROTO_HEIGHT=0
proto_stack_height() {
    local y x
    PROTO_HEIGHT=0
    for (( y = HIDDEN_ROWS; y < BOARD_H; y++ )); do
        for (( x = 0; x < BOARD_W; x++ )); do
            if [ "${BOARD[y * BOARD_W + x]}" != "${EMPTY_CELL}" ]; then
                PROTO_HEIGHT=$(( BOARD_H - y ))
                return 0
            fi
        done
    done
    return 0
}
