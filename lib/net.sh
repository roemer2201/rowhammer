#!/usr/bin/env bash
#
# lib/net.sh
#
# Description:
#   Transport layer of the rowhammer multiplayer (see CLAUDE.md 5.2/5.3).
#   It moves lines between two processes and knows nothing about the game:
#   which line means what is lib/proto.sh's business, what to do about it
#   lib/hub.sh's and lib/mp.sh's.
#   Everything here goes through socat, which is a hard requirement of the
#   multiplayer and of nothing else (net_require reports its absence with
#   the package name and the singleplayer runs on without it). Two
#   transports share every line of code below and differ in one string,
#   the socat address: "lan" listens/connects over TCP4 on MP_PORT, "unix"
#   over a domain socket below MP_DIR - which is why switching between
#   them costs no session logic at all.
#   An address is never a string that came in from the network: a peer is
#   remembered as four octets and a port number, each checked against its
#   own pattern, and the socat address is rebuilt from those numbers
#   (net_addr_tcp). That is the one path on which a discovery could
#   otherwise turn into code execution.
#   The client end of a session is a coprocess (net_connect), so reading
#   and writing are ordinary bash file descriptors: net_poll drains at
#   most MP_POLL_MAX lines per game tick without ever blocking, so a
#   flooded socket cannot hold up a frame, and net_send drops a line
#   rather than block on a full socket buffer.
#   In the "lan" transport a session announces itself with a UDP broadcast
#   beacon once a second (net_beacon_send) and a searching client collects
#   beacons through a socat listener whose children write into a FIFO
#   (net_discover_start/_poll/_stop). The address of a session comes from
#   the sender address of its datagram, never from the datagram's content:
#   a forged beacon can therefore point at its forger and at nobody else.
#   Every line sent or received is length- and charset-checked (512 bytes,
#   0x20-0x7E) before anything else looks at it, and the whole traffic is
#   mirrored into net.log in debug mode.
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 1.0.0  (2026-08-11)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/net.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# --- Limits ---------------------------------------------------------------
# One message is one line of at most this many bytes including the newline.
# It used to be a compatibility limit (the smallest write every candidate
# transport was guaranteed to pass through atomically); with socat set it
# is a protection limit: a line this short can never exhaust memory, and
# it stays below the 4096 bytes a pipe write is atomic up to, which is
# what lets several bridges share one inbox FIFO (see lib/hub.sh).
MP_LINE_MAX=512

# How many lines one net_poll takes out of the socket at most. The game
# loop calls it once per tick, so this caps what a flooding peer can cost
# a single frame; whatever is left waits in the socket buffer for the next
# tick, and a peer that keeps it up runs into the rate limit in
# lib/proto.sh long before the buffer matters.
MP_POLL_MAX=16

# Accepted rate per client, counted by the receiver (lib/proto.sh applies
# it). Sixty-four messages a second is an order of magnitude above what a
# well-behaved client sends (10 STATE/s plus 5 BOARD/s plus events).
MP_RATE_MAX=64

# How long a fresh connection has to produce a valid HELLO before the hub
# drops it. Without this a dozen silent connections could sit in the lobby
# forever without ever sending a byte.
MP_HELLO_MS=5000

# Beacon interval, and how long a session stays in a searching client's
# list after its last beacon. Three missed beacons rather than one, so a
# lost datagram does not make a session flicker in and out of the list.
MP_BEACON_MS=1000
MP_BEACON_TTL_MS=3500

# How long a search listens before it shows what it found, and the most
# sessions it will ever list. The cap is what keeps a beacon flooder from
# filling memory or the screen.
MP_DISCOVER_MS=2000
MP_DISCOVER_MAX=32

# Ping interval and the silence after which the hub declares a client
# gone (see CLAUDE.md 5.4).
MP_PING_MS=2000
MP_TIMEOUT_MS=6000

# The first word of a beacon: what makes a datagram of ours recognizable
# on a port somebody else may also be using.
MP_BEACON_MAGIC="ROWHAMMER"

# --- Validation patterns --------------------------------------------------
# Every one of these guards a value that goes into arithmetic, an array
# index or a socat address, so they are all anchored and all capped in
# length - an unbounded number would be an arithmetic overflow waiting to
# happen and an unbounded name a screen full of somebody else's text.
MP_NUM_RE='^[0-9]{1,9}$'
MP_PORT_RE='^[0-9]{1,5}$'
MP_OCTET_RE='^[0-9]{1,3}$'
# A session name goes into a file path in the unix transport, so it may
# not contain a slash or a dot-dot; the pattern allows neither.
MP_SESSION_RE='^[A-Za-z0-9_-]{1,16}$'
# A host name typed in by hand. Deliberately narrower than RFC 1123 (no
# underscores, no trailing dot): it is passed to socat, and everything
# that is not a letter, a digit, a dot or a hyphen has no business there.
MP_HOST_RE='^[A-Za-z0-9]([A-Za-z0-9.-]{0,62})$'

# --- Runtime state --------------------------------------------------------
# Path of the socat binary once net_require found it.
NET_SOCAT=""
# The address the last net_addr_* built, and the connection state of the
# client end: NET_LINK_UP is 1 while the coprocess lives, NET_LINK_IN and
# NET_LINK_OUT are its file descriptors.
NET_ADDR=""
NET_LINK_UP=0
NET_LINK_IN=-1
NET_LINK_OUT=-1
NET_LINK_PID=0
# Lines net_poll took out of the socket, oldest first.
NET_INBOX=()
# The tail of a line that arrived in pieces (TCP may split anywhere), kept
# until its remainder shows up. Without this a message torn in two would
# be lost and, worse, its halves would look like two malformed messages.
NET_PART=""
# Why the link went down, for the message the client shows afterwards:
# "eof" (the other end closed), "send" (writing failed).
NET_LINK_ERROR=""

# Discovery state: the FIFO the socat children write their beacons into,
# the directory holding it, the listener's process id, and the sessions
# found so far (one array per column, indexed together).
NET_DISCOVER_FIFO=""
NET_DISCOVER_DIR=""
NET_DISCOVER_PID=0
NET_DISCOVER_FD=""
NET_SESSION_HOST=()
NET_SESSION_PORT=()
NET_SESSION_NAME=()
NET_SESSION_PLAYERS=()
NET_SESSION_MAX=()
NET_SESSION_STATE=()
NET_SESSION_SEEN=()

# --- Debug log ------------------------------------------------------------
# net_log DIRECTION LINE
# Mirror one message into the debug event log, %q-quoted like the key
# input log: the traffic is the one thing a protocol bug or an attack
# attempt can be reconstructed from, and a raw line could carry anything.
# DIRECTION is a short tag ("tx", "rx", "beacon", "drop").
net_log() {
    if [ "${DEBUG_ACTIVE:-0}" -ne 1 ]; then
        return 0
    fi
    debug_event "$(printf 'net %s: %q' "${1}" "${2}")"
    return 0
}

# --- socat ----------------------------------------------------------------
# net_require
# Find socat and remember it in NET_SOCAT. Returns 1 when it is missing,
# leaving the caller to say so in the interface language - the multiplayer
# menu names the package and returns, and the singleplayer is untouched,
# which is why socat is a Recommends and not a Depends of the packages.
net_require() {
    if [ -n "${NET_SOCAT}" ]; then
        return 0
    fi
    NET_SOCAT="$(command -v socat 2>/dev/null)" || NET_SOCAT=""
    if [ -z "${NET_SOCAT}" ]; then
        return 1
    fi
    return 0
}

# --- Line hygiene ---------------------------------------------------------
# net_line_ok LINE
# The first gate every received line passes and the last one every sent
# line passes: printable ASCII only (0x20-0x7E) and no longer than
# MP_LINE_MAX minus the newline. The charset half is the single most
# important rule in the whole multiplayer (CLAUDE.md 5.5): a name carrying
# ANSI escapes could otherwise rewrite the screen of everybody in the
# round, set their window title or - on some terminals - push text into
# their input buffer through a reply sequence. Checked here, once, in the
# transport, rather than at every place that later prints something.
net_line_ok() {
    # Both the character class and any range in a pattern follow the
    # locale's collation order, and in a UTF-8 locale that is not the
    # order of the bytes: a range like [\x01-\x1f] happily matches "." and
    # [:print:] counts every printable character of the locale, not the
    # printable ASCII this protocol allows. Setting LC_ALL for the
    # duration of this function pins both to the bytes they are meant to
    # mean; being a local, it is restored on the way out, so nothing else
    # in the game sees a changed locale.
    local LC_ALL=C
    local line="${1}"
    if [ "${#line}" -eq 0 ] || [ "${#line}" -ge "${MP_LINE_MAX}" ]; then
        return 1
    fi
    case "${line}" in
        *[![:print:]]*) return 1 ;;
    esac
    return 0
}

# --- Address building -----------------------------------------------------
# net_ipv4_ok ADDRESS
# True for a dotted-quad IPv4 address with every octet in 0..255. The
# check exists so an address coming out of a datagram can be split into
# numbers and reassembled; nothing that fails it ever reaches a command
# line.
net_ipv4_ok() {
    local addr="${1}"
    local -a parts
    local part
    IFS='.' read -ra parts <<< "${addr}"
    if [ "${#parts[@]}" -ne 4 ]; then
        return 1
    fi
    for part in "${parts[@]}"; do
        [[ "${part}" =~ ${MP_OCTET_RE} ]] || return 1
        # 10# so a "010" is read as ten rather than as an octal number.
        if (( 10#${part} > 255 )); then
            return 1
        fi
    done
    return 0
}

# net_port_ok PORT
# True for a port in 1..65535. Ports come from the command line, the
# config and - as the beacon's own field - from the network.
net_port_ok() {
    [[ "${1}" =~ ${MP_PORT_RE} ]] || return 1
    if (( 10#${1} < 1 || 10#${1} > 65535 )); then
        return 1
    fi
    return 0
}

# net_host_ok HOST
# True for something a player may type into the "connect directly" field:
# an IPv4 address or a host name of the narrow shape MP_HOST_RE allows.
net_host_ok() {
    if net_ipv4_ok "${1}"; then
        return 0
    fi
    [[ "${1}" =~ ${MP_HOST_RE} ]]
}

# net_addr_tcp HOST PORT
# Build the socat address of a TCP peer into NET_ADDR, from parts that
# were checked one by one. An IPv4 address is split into its four numbers
# and printed back from them, so not one byte of the input string is
# carried over; a host name (only ever typed by hand, never taken from the
# network) passes MP_HOST_RE. Returns 1 without touching NET_ADDR when
# either part fails.
net_addr_tcp() {
    local host="${1}" port="${2}"
    local -a o
    net_port_ok "${port}" || return 1
    if net_ipv4_ok "${host}"; then
        IFS='.' read -ra o <<< "${host}"
        printf -v NET_ADDR 'TCP4:%d.%d.%d.%d:%d' \
            "$(( 10#${o[0]} ))" "$(( 10#${o[1]} ))" \
            "$(( 10#${o[2]} ))" "$(( 10#${o[3]} ))" "$(( 10#${port} ))"
        return 0
    fi
    [[ "${host}" =~ ${MP_HOST_RE} ]] || return 1
    printf -v NET_ADDR 'TCP4:%s:%d' "${host}" "$(( 10#${port} ))"
    return 0
}

# net_addr_unix PATH
# Build the socat address of a domain socket into NET_ADDR. The path is
# assembled by net_session_path from a validated session name, so what
# arrives here is ours; the check that it holds no comma or colon is
# nevertheless kept, because those two characters would change the meaning
# of a socat address rather than break it.
net_addr_unix() {
    local path="${1}"
    case "${path}" in
        *,*|*:*|"") return 1 ;;
    esac
    NET_ADDR="UNIX-CONNECT:${path}"
    return 0
}

# net_session_path NAME
# Path of a unix-transport session socket in NET_SESSION_PATH. The name is
# checked against MP_SESSION_RE first, so no ".." and no slash can enter
# the path.
NET_SESSION_PATH=""
net_session_path() {
    [[ "${1}" =~ ${MP_SESSION_RE} ]] || return 1
    NET_SESSION_PATH="${MP_DIR}/${1}.sock"
    return 0
}

# net_dir_ok DIR
# Check a session directory before anything is created in it: it has to
# exist, be a directory rather than a symlink to one, belong to the caller
# or to root, and must not be world-writable without the sticky bit. That
# is the guard against socket squatting and symlink traps in a shared
# /tmp; the message it fails with names the directory.
net_dir_ok() {
    local dir="${1}" perms owner
    if [ -L "${dir}" ]; then
        NET_ERROR="session directory is a symlink: ${dir}"
        return 1
    fi
    if [ ! -d "${dir}" ]; then
        NET_ERROR="not a directory: ${dir}"
        return 1
    fi
    perms="$(stat -c '%a' -- "${dir}" 2>/dev/null)" || perms=""
    owner="$(stat -c '%u' -- "${dir}" 2>/dev/null)" || owner=""
    if [ -n "${owner}" ] && [ "${owner}" != "$(id -u)" ] && [ "${owner}" != "0" ]; then
        NET_ERROR="session directory belongs to uid ${owner}: ${dir}"
        return 1
    fi
    # World-writable (last digit has the 2 bit) is only acceptable with the
    # sticky bit set, the /tmp arrangement in which nobody can remove
    # somebody else's socket.
    if [ -n "${perms}" ] && [ "${#perms}" -eq 3 ] \
        && (( 10#${perms:2:1} & 2 )); then
        NET_ERROR="session directory is world-writable without sticky bit: ${dir}"
        return 1
    fi
    return 0
}
NET_ERROR=""

# net_dir_prepare
# Make sure MP_DIR exists with private permissions and passes net_dir_ok.
# A directory that is already there is checked but never re-chmodded: a
# shared setup (a group-writable directory an administrator created for
# several accounts on one host) is a legitimate arrangement, and the game
# has no business tightening it behind the administrator's back.
net_dir_prepare() {
    if [ ! -e "${MP_DIR}" ]; then
        # Created and then tightened, rather than "mkdir -p -m 0700":
        # with -p the mode applies to the deepest directory only, so any
        # parent this call has to create would be left at the umask's
        # mercy (ShellCheck SC2174 - and a real hole for a session
        # directory).
        mkdir -p -- "${MP_DIR}" 2>/dev/null || {
            NET_ERROR="cannot create session directory: ${MP_DIR}"
            return 1
        }
        chmod 0700 -- "${MP_DIR}" 2>/dev/null || {
            NET_ERROR="cannot secure session directory: ${MP_DIR}"
            return 1
        }
    fi
    net_dir_ok "${MP_DIR}"
}

# --- Client link ----------------------------------------------------------
# net_connect ADDRESS
# Open the client end of a session: socat as a coprocess, so its two pipe
# ends are ordinary file descriptors this shell can read from and write to
# without a fork per message. The address must already be built by
# net_addr_tcp / net_addr_unix - this function never assembles one.
# Returns 1 when the coprocess could not be started at all; a connection
# that is refused shows up as an immediate EOF on the first poll, which is
# the same path a hub dying mid-round takes.
net_connect() {
    local addr="${1}"
    net_require || return 1
    net_close
    # A coprocess rather than two FIFOs: bash gives both directions as
    # file descriptors, and "read -t 0" on the read end is the only way to
    # ask "is there anything?" without blocking the game loop.
    # shellcheck disable=SC2034  # NET_CO is used through its array elements
    coproc NET_CO { "${NET_SOCAT}" -T 3600 "${addr}" - 2>/dev/null; } || return 1
    NET_LINK_IN="${NET_CO[0]}"
    NET_LINK_OUT="${NET_CO[1]}"
    NET_LINK_PID="${NET_CO_PID}"
    NET_LINK_UP=1
    NET_LINK_ERROR=""
    NET_INBOX=()
    debug_event "net: link up via ${addr} (socat pid ${NET_LINK_PID})"
    return 0
}

# net_close
# Tear the client link down: close both descriptors and end the socat
# process. Idempotent, because it serves both the regular end of a round
# and the EXIT trap.
net_close() {
    if [ "${NET_LINK_UP}" -eq 0 ]; then
        return 0
    fi
    NET_LINK_UP=0
    # Closed through eval rather than "exec {var}>&-": the descriptor
    # numbers come from the coprocess array, and the {var} form of the
    # redirection needs bash 4.1 while this game asks for 4.0 (the same
    # consideration queue_fill in lib/pieces.sh is written under).
    if [ "${NET_LINK_OUT}" -ge 0 ]; then
        eval "exec ${NET_LINK_OUT}>&-" 2>/dev/null || :
    fi
    if [ "${NET_LINK_IN}" -ge 0 ]; then
        eval "exec ${NET_LINK_IN}<&-" 2>/dev/null || :
    fi
    if [ "${NET_LINK_PID}" -gt 0 ]; then
        kill "${NET_LINK_PID}" 2>/dev/null || :
        wait "${NET_LINK_PID}" 2>/dev/null || :
    fi
    NET_LINK_IN=-1
    NET_LINK_OUT=-1
    NET_LINK_PID=0
    debug_event "net: link closed"
    return 0
}

# net_send LINE
# Send one message. The line is checked against net_line_ok first - an
# outgoing line is validated as strictly as an incoming one, so a peer
# never has to deal with rubbish this end produced (the player name is the
# realistic source of it, see proto_name).
# The write must never block: a socket buffer that is full means the peer
# is not reading, and a game loop stuck in a write would freeze the round
# for everybody at this end. "printf" into the coprocess with a short
# timeout is not available in bash, so the line is dropped instead and the
# caller is told - the two messages that may not be dropped (CLEAR,
# TOPOUT) are resent by lib/mp.sh rather than blocked on here.
net_send() {
    local line="${1}"
    if [ "${NET_LINK_UP}" -eq 0 ]; then
        return 1
    fi
    if ! net_line_ok "${line}"; then
        net_log drop "${line}"
        return 1
    fi
    # "1>&fd" rather than ">&fd": the short form reads as a redirection
    # to a *file* named by the variable when a second redirection follows
    # it, which is exactly the ambiguity ShellCheck flags (SC2261).
    if ! printf '%s\n' "${line}" 1>&"${NET_LINK_OUT}" 2>/dev/null; then
        NET_LINK_ERROR="send"
        NET_LINK_UP=0
        debug_event "net: send failed, link down"
        return 1
    fi
    net_log tx "${line}"
    return 0
}

# net_poll
# Drain up to MP_POLL_MAX lines from the link into NET_INBOX without ever
# blocking: "read -t 0" answers whether anything is there, and only then
# is a line read with a very short timeout. Returns 1 when the link is
# down or just went down (EOF), which is how the round learns that the hub
# or the connection is gone.
net_poll() {
    local line n=0 rc
    NET_INBOX=()
    if [ "${NET_LINK_UP}" -eq 0 ]; then
        return 1
    fi
    while [ "${n}" -lt "${MP_POLL_MAX}" ]; do
        if ! read -t 0 -u "${NET_LINK_IN}" 2>/dev/null; then
            # Nothing pending. That is the normal case in most ticks.
            return 0
        fi
        line=""
        rc=0
        IFS= read -r -t 0.05 -u "${NET_LINK_IN}" line || rc=$?
        if [ "${rc}" -gt 128 ]; then
            # Timed out with the line still unterminated: bash hands the
            # part it did read back in the variable, so it is kept and
            # the remainder is prepended to it on the next poll. Capped,
            # so a peer sending 512 bytes without a newline cannot make
            # this buffer grow.
            NET_PART="${NET_PART}${line}"
            if [ "${#NET_PART}" -ge "${MP_LINE_MAX}" ]; then
                net_log drop "${NET_PART}"
                NET_PART=""
            fi
            return 0
        elif [ "${rc}" -ne 0 ]; then
            # End of file: the peer or the hub is gone. Anything read
            # before it was an unterminated line and is discarded.
            NET_PART=""
            NET_LINK_ERROR="eof"
            NET_LINK_UP=0
            debug_event "net: link closed by peer"
            return 1
        fi
        line="${NET_PART}${line}"
        NET_PART=""
        if net_line_ok "${line}"; then
            NET_INBOX+=("${line}")
            net_log rx "${line}"
        else
            net_log drop "${line}"
        fi
        n=$(( n + 1 ))
    done
    return 0
}

# --- Beacon (lan transport only) ------------------------------------------
# net_beacon_line NAME PLAYERS MAX PORT STATE
# Build the beacon a session announces itself with into NET_BEACON:
#   ROWHAMMER <proto> <session> <players> <max> <tcpport> <lobby|play>
# There is deliberately no address field. An address a sender may choose
# freely could point a whole network at a third party; the receiver takes
# the address from the datagram's sender instead, where a forger can only
# ever name themselves (CLAUDE.md 5.2/5.5).
NET_BEACON=""
net_beacon_line() {
    printf -v NET_BEACON '%s %d %s %d %d %d %s' \
        "${MP_BEACON_MAGIC}" "${PROTO_VERSION}" "${1}" \
        "${2}" "${3}" "${4}" "${5}"
    return 0
}

# net_beacon_send LINE
# Send one beacon datagram to the limited broadcast address. 255.255.255.255
# is deliberate: no router forwards it, so the announcement reaches exactly
# the local network and nothing beyond it. One socat per beacon is one fork
# a second in the hub, which has no frame to hold up.
net_beacon_send() {
    local line="${1}"
    net_line_ok "${line}" || return 1
    printf '%s\n' "${line}" | "${NET_SOCAT}" -u - \
        "UDP4-DATAGRAM:255.255.255.255:${MP_PORT},broadcast" 2>/dev/null || {
        # A machine without a broadcast route (a container with a single
        # host route, say) cannot announce itself. That is not fatal: the
        # session is still reachable by its address, which is exactly why
        # the lobby shows it (CLAUDE.md 5.2).
        return 1
    }
    return 0
}

# net_discover_start
# Begin collecting beacons: a FIFO in a private directory plus a socat
# listener whose children (rowhammer.sh --mp-discover) write one line
# "<sender> <datagram>" into it. The child exists for one reason only -
# the sender address is available to a process socat starts, in
# SOCAT_PEERADDR, and nowhere else - and it is what makes the address of a
# session something the sender cannot choose.
net_discover_start() {
    net_require || return 1
    net_discover_stop
    NET_DISCOVER_DIR="$(mktemp -d -- "${TMPDIR:-/tmp}/rowhammer-disc.XXXXXX")" || return 1
    NET_DISCOVER_FIFO="${NET_DISCOVER_DIR}/beacons"
    mkfifo -m 0600 -- "${NET_DISCOVER_FIFO}" || return 1
    # Opened read-write so this end never blocks and never sees EOF when
    # the last child exits. A fixed descriptor number instead of the
    # "{var}<>" form, which needs bash 4.1 (see net_close); 7 is free
    # beside the debug logs (21-23) and the hub's inbox (9).
    exec 7<>"${NET_DISCOVER_FIFO}" || return 1
    NET_DISCOVER_FD=7
    ROWHAMMER_MP_FIFO="${NET_DISCOVER_FIFO}" \
    "${NET_SOCAT}" "UDP4-RECVFROM:${MP_PORT},fork,reuseaddr,broadcast" \
        "EXEC:${SCRIPT_DIR}/rowhammer.sh --mp-discover" >/dev/null 2>&1 &
    NET_DISCOVER_PID=$!
    NET_SESSION_HOST=()
    NET_SESSION_PORT=()
    NET_SESSION_NAME=()
    NET_SESSION_PLAYERS=()
    NET_SESSION_MAX=()
    NET_SESSION_STATE=()
    NET_SESSION_SEEN=()
    debug_event "net: discovery listening on udp/${MP_PORT} (pid ${NET_DISCOVER_PID})"
    return 0
}

# net_discover_stop
# End the collection and remove its FIFO. Idempotent (the menu calls it on
# every way out, including the EXIT trap).
net_discover_stop() {
    if [ "${NET_DISCOVER_PID}" -gt 0 ]; then
        kill "${NET_DISCOVER_PID}" 2>/dev/null || :
        wait "${NET_DISCOVER_PID}" 2>/dev/null || :
        NET_DISCOVER_PID=0
    fi
    if [ -n "${NET_DISCOVER_FD}" ]; then
        exec 7<&- 2>/dev/null || :
        NET_DISCOVER_FD=""
    fi
    if [ -n "${NET_DISCOVER_DIR}" ] && [ -d "${NET_DISCOVER_DIR}" ]; then
        rm -rf -- "${NET_DISCOVER_DIR}" 2>/dev/null || :
    fi
    NET_DISCOVER_DIR=""
    NET_DISCOVER_FIFO=""
    return 0
}

# net_discover_poll
# Read whatever beacons have arrived and fold them into the session list.
# Never blocks. A beacon is only ever a hint (CLAUDE.md 5.5): every field
# is checked against its pattern, an entry is replaced rather than added
# when its sender is already listed, at most one beacon per sender and
# second is counted, and the list stops growing at MP_DISCOVER_MAX - so a
# flooder can waste neither memory nor screen.
net_discover_poll() {
    local line sender payload host port i found
    local -a f
    if [ -z "${NET_DISCOVER_FIFO}" ]; then
        return 1
    fi
    now_ms
    while read -t 0 -u "${NET_DISCOVER_FD}" 2>/dev/null; do
        line=""
        IFS= read -r -t 0.05 -u "${NET_DISCOVER_FD}" line || break
        net_line_ok "${line}" || continue
        net_log beacon "${line}"
        sender="${line%% *}"
        payload="${line#* }"
        # socat reports the sender as an address, sometimes with the port
        # appended after a colon; only the address half is of interest.
        host="${sender%%:*}"
        net_ipv4_ok "${host}" || continue
        # shellcheck disable=SC2206  # deliberate word splitting of a validated line
        f=(${payload})
        [ "${#f[@]}" -eq 7 ] || continue
        [ "${f[0]}" = "${MP_BEACON_MAGIC}" ] || continue
        [ "${f[1]}" = "${PROTO_VERSION}" ] || continue
        [[ "${f[2]}" =~ ${MP_SESSION_RE} ]] || continue
        [[ "${f[3]}" =~ ${MP_NUM_RE} ]] || continue
        [[ "${f[4]}" =~ ${MP_NUM_RE} ]] || continue
        net_port_ok "${f[5]}" || continue
        case "${f[6]}" in
            lobby|play) : ;;
            *) continue ;;
        esac
        port="${f[5]}"
        found=-1
        for (( i = 0; i < ${#NET_SESSION_HOST[@]}; i++ )); do
            if [ "${NET_SESSION_HOST[i]}" = "${host}" ] \
                && [ "${NET_SESSION_PORT[i]}" = "${port}" ]; then
                found="${i}"
                break
            fi
        done
        if [ "${found}" -lt 0 ]; then
            if [ "${#NET_SESSION_HOST[@]}" -ge "${MP_DISCOVER_MAX}" ]; then
                continue
            fi
            found="${#NET_SESSION_HOST[@]}"
            NET_SESSION_HOST[found]="${host}"
            NET_SESSION_PORT[found]="${port}"
        elif (( NOW_MS - ${NET_SESSION_SEEN[found]} < MP_BEACON_MS / 2 )); then
            # More than two beacons a second from the same sender: the
            # extra ones are ignored instead of refreshing the entry.
            continue
        fi
        NET_SESSION_NAME[found]="${f[2]}"
        NET_SESSION_PLAYERS[found]="${f[3]}"
        NET_SESSION_MAX[found]="${f[4]}"
        NET_SESSION_STATE[found]="${f[6]}"
        NET_SESSION_SEEN[found]="${NOW_MS}"
    done
    return 0
}

# net_discover_expire
# Drop sessions whose last beacon is older than MP_BEACON_TTL_MS. This is
# how a session disappears from the list when its host quits: the beacon
# stops, three of them are missed, the entry goes.
net_discover_expire() {
    local i
    local -a host port name players max state seen
    now_ms
    for (( i = 0; i < ${#NET_SESSION_HOST[@]}; i++ )); do
        if (( NOW_MS - ${NET_SESSION_SEEN[i]} > MP_BEACON_TTL_MS )); then
            continue
        fi
        host+=("${NET_SESSION_HOST[i]}")
        port+=("${NET_SESSION_PORT[i]}")
        name+=("${NET_SESSION_NAME[i]}")
        players+=("${NET_SESSION_PLAYERS[i]}")
        max+=("${NET_SESSION_MAX[i]}")
        state+=("${NET_SESSION_STATE[i]}")
        seen+=("${NET_SESSION_SEEN[i]}")
    done
    NET_SESSION_HOST=("${host[@]}")
    NET_SESSION_PORT=("${port[@]}")
    NET_SESSION_NAME=("${name[@]}")
    NET_SESSION_PLAYERS=("${players[@]}")
    NET_SESSION_MAX=("${max[@]}")
    NET_SESSION_STATE=("${state[@]}")
    NET_SESSION_SEEN=("${seen[@]}")
    return 0
}

# net_discover_child
# The body of "rowhammer.sh --mp-discover": one process per received
# datagram, started by the socat listener above. It reads the datagram
# from its standard input and writes it into the collecting FIFO with the
# sender address in front. Nothing here parses anything - the sender is
# the untrusted-most data the game ever touches, and the only thing this
# process does with it is put it in front of the line and cut both to
# length.
net_discover_child() {
    local fifo="${ROWHAMMER_MP_FIFO:-}" line peer
    if [ -z "${fifo}" ] || [ ! -p "${fifo}" ]; then
        return 1
    fi
    IFS= read -r -t 5 line || return 0
    peer="${SOCAT_PEERADDR:-}"
    # Cut hard: an absurd datagram is not worth a byte more than the
    # collector could possibly use, and the collector checks the rest.
    line="${line:0:${MP_LINE_MAX}}"
    peer="${peer:0:64}"
    printf '%s %s\n' "${peer}" "${line}" >>"${fifo}" 2>/dev/null || return 1
    return 0
}

# --- Local addresses ------------------------------------------------------
# net_local_addr
# The host's own IPv4 address in NET_LOCAL_ADDR, for the lobby to show so
# the host can read it out to somebody whose network swallows broadcasts
# (CLAUDE.md 5.2). "ip route get" names the address the kernel would send
# from, which is the one that matters; hostname -I is the fallback, and an
# empty result is not an error - the lobby then simply shows nothing.
NET_LOCAL_ADDR=""
net_local_addr() {
    local out
    NET_LOCAL_ADDR=""
    out="$(ip route get 1.1.1.1 2>/dev/null)" || out=""
    if [[ "${out}" =~ src[[:space:]]+([0-9.]+) ]]; then
        NET_LOCAL_ADDR="${BASH_REMATCH[1]}"
    fi
    if [ -z "${NET_LOCAL_ADDR}" ]; then
        out="$(hostname -I 2>/dev/null)" || out=""
        NET_LOCAL_ADDR="${out%% *}"
    fi
    net_ipv4_ok "${NET_LOCAL_ADDR}" || NET_LOCAL_ADDR=""
    return 0
}
