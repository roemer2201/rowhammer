#!/usr/bin/env bash
#
# lib/net.sh
#
# Description:
#   Transport layer of the LAN multiplayer: one UDP datagram bus that
#   every rowhammer on the local network shares. There is no server
#   process and no connection - a message is a datagram sent to a
#   multicast group (default) or to the limited broadcast address, and
#   everybody listening on the port receives it. That is what makes the
#   list of open games work without a central instance: a host announces
#   its lobby onto the bus, every other rowhammer hears it.
#   This module knows nothing about the game or the messages themselves
#   (that is lib/proto.sh); it opens and closes the bus, sends one line,
#   collects the lines that arrived and drops everything that cannot be
#   a legal message: a line longer than NET_LINE_MAX or carrying a byte
#   outside printable ASCII never reaches a parser. The charset filter
#   sits here on purpose - it is the one place all received data passes
#   through, and a player name full of ANSI escapes must never get near
#   a terminal (see CLAUDE.md section 5.5).
#   Bash has no socket of its own for this: /dev/udp can only send on a
#   connected socket, it cannot bind, join a multicast group or set
#   SO_BROADCAST. The bus is therefore a coprocess running socat, whose
#   stdin/stdout are the datagrams; socat is the only one of the usual
#   helpers that does a bidirectional UDP datagram socket with multicast
#   membership, which is why it is required rather than preferred.
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 1.0.0  (2026-08-07)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/net.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# Longest message the bus carries, newline included. Well below the
# smallest MTU in use so a message is never fragmented, and small enough
# that a flooding sender cannot make a receiver allocate anything worth
# mentioning. Every message of the protocol fits comfortably.
NET_LINE_MAX=512

# How many lines one net_poll takes out of the socket. The lobby polls
# once per input tick, and an unbounded drain would let a busy (or
# hostile) network hold the loop for as long as it keeps sending. What
# is left stays in the socket buffer and is read on the next tick.
NET_MAX_PER_POLL=16

# Fixed file descriptors for the bus. Literal numbers because exec
# cannot redirect through a variable, and above the ones lib/debug.sh
# uses (21-24). They are duplicates of the coprocess descriptors: bash
# unsets the coproc array as soon as the coprocess is reaped, and an
# array element that vanishes under "set -u" is a fatal error in the
# middle of a round.
#   26 = bus read, 27 = bus write

# Bus state. NET_OPEN is the one flag every other module asks; NET_ERROR
# names the translation key of the last failure, so the caller can show
# a message without this module knowing any language.
NET_OPEN=0
NET_HELPER_BIN=""
NET_ADDRESS=""
NET_PID=0
NET_ERROR=""
# A line that arrived during the startup check in net_open and would
# otherwise be lost: the check reads from the bus to find out whether
# the helper is alive, and on a busy network that read can come back
# with somebody's announcement instead of a timeout.
NET_PENDING=""

# Lines collected by the last net_poll, already filtered but not parsed.
NET_LINES=()

# Counters for the session, reported into the debug log on close: they
# are the quickest answer to "did anything arrive at all" when a lobby
# stays empty on somebody's network.
NET_SENT=0
NET_RECEIVED=0
NET_DROPPED=0

# net_line_ok LINE
# Whether a received line can be a legal message at all: short enough
# and printable ASCII only (0x20-0x7E). Nothing else is examined here.
# LC_ALL is set locally so the range is a range of bytes and ${#line}
# counts bytes: in a UTF-8 locale the range would follow the collation
# order and let through anything the locale calls printable, which is
# exactly the multi-byte input this filter exists to reject.
net_line_ok() {
    local LC_ALL=C
    local line="${1}"
    if [ -z "${line}" ] || [ "${#line}" -gt "${NET_LINE_MAX}" ]; then
        return 1
    fi
    case "${line}" in
        *[!\ -~]*) return 1 ;;
    esac
    return 0
}

# net_helper_detect
# Find the helper program that provides the socket. Sets NET_HELPER_BIN
# and returns 0, or sets NET_ERROR and returns 1.
# Only socat: a bidirectional UDP datagram socket that stays bound while
# datagrams from several senders arrive is beyond both netcats - the
# OpenBSD nc connects itself to the first sender and ignores the rest,
# and neither nc nor ncat can join a multicast group. Falling back to
# one of them would produce a lobby that shows the first host and never
# a second, which is worse than saying plainly what is missing.
net_helper_detect() {
    local bin
    bin="$(command -v socat 2>/dev/null || true)"
    if [ -z "${bin}" ]; then
        NET_ERROR="net_no_helper"
        return 1
    fi
    NET_HELPER_BIN="${bin}"
    return 0
}

# net_address
# Build the socat address of the bus into NET_ADDRESS, from the settings
# owned by rowhammer.sh (MP_DISCOVERY, MP_GROUP, MP_PORT). Both variants
# bind to the port and send to the same address they listen on, so one
# socket both announces and hears - the bus is symmetric, there is no
# server side to it.
#   broadcast (the default): the limited broadcast address, which no
#     router forwards. It needs nothing of the socket but the permission
#     to broadcast, which is why it is the one that works everywhere.
#   multicast: joins the group and keeps the loopback copy on, so two
#     rowhammers on one machine still find each other. Reaches only the
#     machines that joined the group, so it is the quieter of the two on
#     a segment shared with other traffic - but it depends on the
#     helper's group-membership option, which is not equally sound
#     everywhere (socat 1.8.0.0 mis-parses it and exits), and on
#     switches and access points passing the group on.
net_address() {
    case "${MP_DISCOVERY}" in
        multicast)
            NET_ADDRESS="UDP4-DATAGRAM:${MP_GROUP}:${MP_PORT},bind=:${MP_PORT}"
            NET_ADDRESS+=",ip-add-membership=${MP_GROUP}:0.0.0.0"
            NET_ADDRESS+=",reuseaddr,ip-multicast-loop=1"
            ;;
        *)
            NET_ADDRESS="UDP4-DATAGRAM:255.255.255.255:${MP_PORT},bind=:${MP_PORT},broadcast,reuseaddr"
            ;;
    esac
    return 0
}

# net_open
# Put the bus into service. Returns 0 on success, or 1 with NET_ERROR
# set to the translation key of the reason.
net_open() {
    if [ "${NET_OPEN}" -eq 1 ]; then
        return 0
    fi
    NET_ERROR=""
    if ! net_helper_detect; then
        return 1
    fi
    net_address
    # SIGPIPE is ignored for as long as the bus is open. Should the
    # helper die (network gone, port taken away, killed), the next write
    # would otherwise not fail but end the whole game with signal 13 -
    # in the middle of a round, with the terminal in raw mode. Ignored,
    # the write returns an error and net_send reports a closed bus. The
    # helper inherits the ignored signal, which is what we want there
    # too: socat should report a broken pipe rather than die silently.
    trap '' PIPE
    # socat's diagnostics go nowhere: the game owns the terminal, and a
    # message written into the alternate screen would sit in the middle
    # of the board (an unchanged line is not redrawn, see CLAUDE.md 4.3).
    # What went wrong is visible here as a dead coprocess and lands in
    # the debug log.
    coproc NET_LINK { "${NET_HELPER_BIN}" "${NET_ADDRESS}" - 2>/dev/null; }
    NET_PID="${NET_LINK_PID}"
    exec 26<&"${NET_LINK[0]}" 27>&"${NET_LINK[1]}"
    NET_OPEN=1
    NET_SENT=0
    NET_RECEIVED=0
    NET_DROPPED=0
    NET_PENDING=""
    # Startup check: read once with a short timeout. A helper that could
    # not open the socket - a port already taken, a multicast option its
    # version cannot parse, no permission to broadcast - is gone by now
    # and the read hits end of file instead of the timeout. Without this
    # the lobby would open normally and then simply stay empty forever,
    # which is the hardest kind of failure to make sense of. What the
    # read may catch instead is a real line from somebody already on the
    # bus; it is kept and handed out by the next net_poll.
    local probe="" rc=0
    IFS= read -r -t 0.05 -u 26 probe || rc=$?
    if [ "${rc}" -eq 1 ]; then
        debug_event "net: helper died on startup (${NET_ADDRESS})"
        NET_ERROR="net_helper_failed"
        net_close
        return 1
    fi
    if [ -n "${probe}" ] && net_line_ok "${probe}"; then
        NET_PENDING="${probe}"
    fi
    debug_event "net: bus open (${MP_DISCOVERY} ${MP_GROUP}:${MP_PORT} helper=${NET_HELPER_BIN} pid=${NET_PID})"
    debug_net "open" "${NET_ADDRESS}"
    return 0
}

# net_close
# Take the bus out of service. Safe to call when it never opened, which
# is why the EXIT trap can call it unconditionally.
net_close() {
    if [ "${NET_OPEN}" -eq 0 ]; then
        return 0
    fi
    NET_OPEN=0
    exec 26<&- 27>&-
    if [ "${NET_PID}" -gt 0 ]; then
        kill "${NET_PID}" 2>/dev/null || true
        wait "${NET_PID}" 2>/dev/null || true
    fi
    NET_PID=0
    trap - PIPE
    debug_net "close" "sent=${NET_SENT} received=${NET_RECEIVED} dropped=${NET_DROPPED}"
    debug_event "net: bus closed (sent=${NET_SENT} received=${NET_RECEIVED} dropped=${NET_DROPPED})"
    return 0
}

# net_send LINE
# Put one message on the bus. Returns 1 without sending when the line is
# not a legal message - the same filter the receive path uses, applied to
# our own output as well, so a broken caller cannot make everybody else
# discard our messages (CLAUDE.md 5.5: outgoing data is checked too).
# A failed write closes the bus: the helper is gone, and every later
# send would fail the same way.
net_send() {
    local line="${1}"
    if [ "${NET_OPEN}" -eq 0 ]; then
        return 1
    fi
    if ! net_line_ok "${line}"; then
        debug_net "send-invalid" "${line}"
        return 1
    fi
    if ! printf '%s\n' "${line}" >&27 2>/dev/null; then
        debug_net "send-failed" "${line}"
        NET_ERROR="net_lost"
        net_close
        return 1
    fi
    NET_SENT=$(( NET_SENT + 1 ))
    debug_net "out" "${line}"
    return 0
}

# net_poll
# Collect what has arrived since the last call into NET_LINES, at most
# NET_MAX_PER_POLL lines, filtered but not parsed. Never blocks longer
# than the read timeout of a single line and returns 0 even when nothing
# arrived - "no traffic" is the normal case, not an error.
# The timeout is the smallest one bash accepts as a fraction and exists
# only to bridge a line that is still on its way through the pipe; the
# loop leaves as soon as a read comes back empty-handed.
net_poll() {
    NET_LINES=()
    if [ "${NET_OPEN}" -eq 0 ]; then
        return 0
    fi
    # A line the startup check took off the bus comes first, so it keeps
    # its place in the order it arrived in.
    if [ -n "${NET_PENDING}" ]; then
        NET_LINES+=("${NET_PENDING}")
        NET_RECEIVED=$(( NET_RECEIVED + 1 ))
        debug_net "in" "${NET_PENDING}"
        NET_PENDING=""
    fi
    local line rc i
    for (( i = 0; i < NET_MAX_PER_POLL; i++ )); do
        line=""
        rc=0
        IFS= read -r -t 0.01 -u 26 line || rc=$?
        if [ "${rc}" -gt 128 ]; then
            # Timeout: nothing (more) waiting.
            break
        fi
        if [ "${rc}" -ne 0 ]; then
            # End of file: the helper is gone. A partial line it may
            # have left behind is still worth having, so it is handled
            # below before the bus is torn down.
            if [ -n "${line}" ] && net_line_ok "${line}"; then
                NET_LINES+=("${line}")
                NET_RECEIVED=$(( NET_RECEIVED + 1 ))
                debug_net "in" "${line}"
            fi
            NET_ERROR="net_lost"
            net_close
            break
        fi
        if ! net_line_ok "${line}"; then
            NET_DROPPED=$(( NET_DROPPED + 1 ))
            debug_net "drop" "${line}"
            continue
        fi
        NET_RECEIVED=$(( NET_RECEIVED + 1 ))
        NET_LINES+=("${line}")
        debug_net "in" "${line}"
    done
    return 0
}
