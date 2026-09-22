#!/usr/bin/env bash
#
# tools/hub-check.sh
#
# Description:
#   Session test for the rowhammer multiplayer hub (lib/hub.sh), run against
#   a real hub process over real socat connections. Where tools/net-fuzz.sh
#   checks that no single line can hurt a parser, this one checks that the
#   session logic does what CLAUDE.md 5.1/5.4/5.5/5.8 says it does when
#   players come, go and misbehave - every case below is a fault that was
#   found in 2.0.2 and is kept from coming back here:
#     - a player who leaves the lobby is announced as gone (VACANT), so no
#       seat stays on the other screens;
#     - "start" while alone is answered, and does not end the session;
#     - a connection that has not said HELLO when the round starts is not
#       a player of it (the round is decided without it);
#     - a host who tops out and then leaves does not move or end a running
#       round;
#     - once the round is over, nobody is let in and nobody is promoted;
#     - a client the hub drops for malformed messages is really
#       disconnected;
#     - in the unix transport, a session that moved to another hub on the
#       same machine keeps its socket when the old hub exits.
#   The clients are plain socat processes fed and read through FIFOs; they
#   answer the hub's PING on their own, so a case may wait as long as it
#   needs to without being dropped for silence.
#   Needs socat, like the multiplayer itself. Without it the test says so
#   and exits 0, so a checkout on a machine without socat is not a failure
#   (the CI installs it).
#
# Program flow:
#   1. Parse arguments, resolve the repository root, check for socat.
#   2. Create a private working directory (session directory, FIFOs).
#   3. Run the cases one by one, each with a hub of its own on its own
#      port or socket, and tear everything down after each.
#   4. Report the number of checks and exit non-zero on any failure.
#
# Usage:
#   hub-check.sh [-p|--port N] [-v|--verbose] [-q|--silent] [-h|--help]
#
# Version: 1.0.0  (2026-09-22)

set -euo pipefail

SCRIPT_NAME="$(basename -- "${0}")"
REPO_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)"
GAME="${REPO_DIR}/rowhammer.sh"

# --- Defaults seeded from environment variables ---------------------------
# Precedence: command-line argument > environment variable > default.
BASE_PORT="${ROWHAMMER_HUBCHECK_PORT:-27380}"
VERBOSE="${ROWHAMMER_HUBCHECK_VERBOSE:-0}"
SILENT="${ROWHAMMER_HUBCHECK_SILENT:-0}"

usage() {
    cat <<'EOF'
Usage: hub-check.sh [OPTIONS]

Run the multiplayer hub of rowhammer against scripted socat clients and
check the session rules: seats that empty, starting alone, the start of a
round, a host leaving mid-round, the end of a session, dropped clients and
a handover in the unix transport.

Options:
  -p, --port N     First TCP port to use; every case takes the next one.
                   Env: ROWHAMMER_HUBCHECK_PORT     Default: 27380
  -v, --verbose    Print every line the clients receive.
                   Env: ROWHAMMER_HUBCHECK_VERBOSE  Default: 0
  -q, --silent     Print nothing but errors.
                   Env: ROWHAMMER_HUBCHECK_SILENT   Default: 0
  -h, --help       Show this help and exit.

Exit code 0 when every check passed (or socat is missing), 1 on a failed
check, 2 on a usage error.
EOF
}

log() {
    if [ "${SILENT}" -eq 0 ]; then
        printf '%s\n' "$*"
    fi
}

vlog() {
    if [ "${VERBOSE}" -eq 1 ] && [ "${SILENT}" -eq 0 ]; then
        printf '    %s\n' "$*"
    fi
}

while [ "$#" -gt 0 ]; do
    case "${1}" in
        -p|--port)
            [ "$#" -ge 2 ] || { printf '%s: %s needs an argument\n' "${SCRIPT_NAME}" "${1}" >&2; exit 2; }
            BASE_PORT="${2}"
            shift 2
            ;;
        -v|--verbose) VERBOSE=1; shift ;;
        -q|--silent)  SILENT=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        *)
            printf '%s: unknown option: %s\n' "${SCRIPT_NAME}" "${1}" >&2
            printf "Try '%s --help' for the list of options.\n" "${SCRIPT_NAME}" >&2
            exit 2
            ;;
    esac
done
if ! [[ "${BASE_PORT}" =~ ^[0-9]{1,5}$ ]] || [ "${BASE_PORT}" -lt 1024 ] \
    || [ "${BASE_PORT}" -gt 65000 ]; then
    printf '%s: --port expects a number in 1024..65000, got: %s\n' "${SCRIPT_NAME}" "${BASE_PORT}" >&2
    exit 2
fi
if [ "${VERBOSE}" -eq 1 ] && [ "${SILENT}" -eq 1 ]; then
    printf '%s: --verbose and --silent are mutually exclusive\n' "${SCRIPT_NAME}" >&2
    exit 2
fi
if ! command -v socat >/dev/null 2>&1; then
    log "${SCRIPT_NAME}: socat not found, nothing to test (the multiplayer needs it)"
    exit 0
fi

# The protocol version the clients announce, read from the library rather
# than written down here, so the test follows the protocol it tests.
PROTO="$(sed -n 's/^PROTO_VERSION=\([0-9][0-9]*\)$/\1/p' "${REPO_DIR}/lib/proto.sh")"
[ -n "${PROTO}" ] || { printf '%s: cannot read PROTO_VERSION from lib/proto.sh\n' "${SCRIPT_NAME}" >&2; exit 1; }

# --- Harness --------------------------------------------------------------
# One private directory for everything: the session directory the hubs
# use, the FIFOs of the clients and the clients' output. Removed on exit,
# together with every process this test started.
WORK="$(mktemp -d -- "${TMPDIR:-/tmp}/rowhammer-hubcheck.XXXXXX")"
MPDIR="${WORK}/mp"
mkdir -m 0700 -- "${MPDIR}"
declare -A CL_PID=() CL_IN=() CL_OUT=()
HUB_PIDS=()
NEXT_FD=20
PORT="${BASE_PORT}"
FAILURES=0
CHECKS=0

cleanup() {
    local pid
    for pid in "${CL_PID[@]}" "${HUB_PIDS[@]}"; do
        kill "${pid}" 2>/dev/null || :
    done
    rm -rf -- "${WORK}"
}
trap cleanup EXIT
# A write into the FIFO of a client whose connection the hub has closed
# must not end the test - that closed connection is often the very thing
# a case checks for.
trap '' PIPE

# fail MESSAGE / pass MESSAGE: count one check.
fail() {
    CHECKS=$(( CHECKS + 1 ))
    FAILURES=$(( FAILURES + 1 ))
    printf '%s: FAIL %s\n' "${SCRIPT_NAME}" "$*" >&2
}
pass() {
    CHECKS=$(( CHECKS + 1 ))
    vlog "ok: $*"
}

# hub_start TRANSPORT [HUB OPTIONS...]
# Start a hub for the next case; lan hubs get a port of their own, unix
# hubs a session name of their own. The session name is in HUB_SESSION.
hub_start() {
    local transport="${1}"
    shift
    PORT=$(( PORT + 1 ))
    HUB_SESSION="hc${PORT}"
    setsid "${GAME}" --mp-hub --mp-transport "${transport}" --mp-port "${PORT}" \
        --mp-max 5 --mp-session "${HUB_SESSION}" --mp-dir "${MPDIR}" "$@" \
        >/dev/null 2>"${WORK}/hub-${PORT}.err" &
    HUB_PIDS+=("$!")
    HUB_PID="$!"
    sleep 0.8
    if ! kill -0 "${HUB_PID}" 2>/dev/null; then
        printf '%s: the hub did not start:\n' "${SCRIPT_NAME}" >&2
        cat -- "${WORK}/hub-${PORT}.err" >&2
        exit 1
    fi
}

# cl_open NAME [unix]
# Open a client connection: socat between two FIFOs and the hub, and two
# descriptors of this shell on the FIFOs.
cl_open() {
    local name="${1}" addr="TCP4:127.0.0.1:${PORT}"
    if [ "${2:-}" = "unix" ]; then
        addr="UNIX-CONNECT:${MPDIR}/${HUB_SESSION}.sock"
    fi
    mkfifo -- "${WORK}/${name}.in" "${WORK}/${name}.out"
    # socat's own messages go into a file of the client: the test ends
    # every client with a signal, which socat reports on its way out, and
    # that is not a finding. The file is there to be read when a case
    # fails for a reason socat knows better.
    socat -T 60 "${addr}" - <"${WORK}/${name}.in" >"${WORK}/${name}.out" \
        2>"${WORK}/${name}.err" &
    CL_PID["${name}"]="$!"
    NEXT_FD=$(( NEXT_FD + 1 ))
    eval "exec ${NEXT_FD}>\"\${WORK}/\${name}.in\""
    CL_IN["${name}"]="${NEXT_FD}"
    NEXT_FD=$(( NEXT_FD + 1 ))
    eval "exec ${NEXT_FD}<\"\${WORK}/\${name}.out\""
    CL_OUT["${name}"]="${NEXT_FD}"
    : > "${WORK}/${name}.log"
    CL_EOF["${name}"]=0
}
declare -A CL_EOF=()

# cl_send NAME LINE
# The write fails once the hub has closed the connection and socat is
# gone - the case then checks exactly that - so the shell's own message
# about it is not wanted; the group is what catches a failed redirection
# (the same construction net_send uses, lib/net.sh).
cl_send() {
    { printf '%s\n' "${2}" 1>&"${CL_IN[${1}]}"; } 2>/dev/null || :
}

# cl_pump NAME SECONDS
# Read what the hub sends a client for SECONDS, answer its pings, and keep
# the lines in the client's log; an end of file is noted in CL_EOF.
cl_pump() {
    local name="${1}" secs="${2}" line rc end
    end=$(( $(date +%s%N) / 1000000 + ${secs%.*} * 1000 ))
    if [[ "${secs}" == *.* ]]; then
        end=$(( end + 10#${secs#*.} * 100 ))
    fi
    while [ $(( $(date +%s%N) / 1000000 )) -lt "${end}" ]; do
        [ "${CL_EOF[${name}]}" -eq 0 ] || return 0
        rc=0
        IFS= read -r -t 0.1 -u "${CL_OUT[${name}]}" line || rc=$?
        if [ "${rc}" -gt 128 ]; then
            continue
        elif [ "${rc}" -ne 0 ]; then
            CL_EOF["${name}"]=1
            vlog "[${name}] <eof>"
            return 0
        fi
        vlog "[${name}] ${line}"
        case "${line}" in
            PING\ *) cl_send "${name}" "PONG ${line#PING }" ;;
        esac
        printf '%s\n' "${line}" >> "${WORK}/${name}.log"
    done
}

# pump SECONDS NAME...: cl_pump for several clients, interleaved, for
# about SECONDS in total (each turn of one client takes a tenth of a
# second when nothing arrives).
pump() {
    local secs="${1}" name i rounds ms
    shift
    ms=$(( ${secs%.*} * 1000 ))
    if [[ "${secs}" == *.* ]]; then
        ms=$(( ms + 10#${secs#*.} * 100 ))
    fi
    rounds=$(( (ms + 100 * $# - 1) / (100 * $#) ))
    for (( i = 0; i < rounds; i++ )); do
        for name in "$@"; do
            cl_pump "${name}" 0.1
        done
    done
}

# saw NAME REGEX: did the client receive a matching line?
saw() {
    grep -Eq -- "${2}" "${WORK}/${1}.log"
}

# case_done: end the case's processes, so the next one starts clean.
case_done() {
    local name
    for name in "${!CL_PID[@]}"; do
        kill "${CL_PID[${name}]}" 2>/dev/null || :
        eval "exec ${CL_IN[${name}]}>&-" 2>/dev/null || :
        eval "exec ${CL_OUT[${name}]}<&-" 2>/dev/null || :
        rm -f -- "${WORK}/${name}.in" "${WORK}/${name}.out"
    done
    CL_PID=()
    CL_IN=()
    CL_OUT=()
    kill "${HUB_PID}" 2>/dev/null || :
    sleep 0.3
}

# join NAME [unix]: open a client and say HELLO under its own name.
join() {
    cl_open "${1}" "${2:-}"
    cl_send "${1}" "HELLO ${PROTO} ${1} board"
    cl_pump "${1}" 0.4
}

# --- The cases ------------------------------------------------------------
log "${SCRIPT_NAME}: hub session checks (protocol ${PROTO})"

# 1. A player leaving the lobby is announced to everybody who stays.
log "  lobby: a seat that empties is announced"
hub_start lan
join alice; join bob; join carol
pump 0.5 alice bob carol
cl_send carol "BYE"
pump 1 alice bob
if saw alice '^VACANT 2$' && saw bob '^VACANT 2$'; then
    pass "VACANT for the seat carol left"
else
    fail "nobody was told that carol's seat is empty (no VACANT 2)"
fi
case_done

# 2. The host asking to start alone is answered and stays in the session.
log "  lobby: starting alone"
hub_start lan
join alice
cl_send alice "READY 1"
pump 1 alice
if saw alice '^ERR alone'; then
    pass "ERR alone"
else
    fail "the host starting alone got no ERR alone"
fi
join bob
pump 0.6 alice bob
if saw bob '^ROSTER 0 alice ' && [ "${CL_EOF[alice]}" -eq 0 ]; then
    pass "session still open after ERR alone"
else
    fail "the session did not survive a start while alone"
fi
case_done

# 3. A connection without HELLO at the start of the round is no player:
#    a two-player survival round is decided by the first top-out.
log "  round: a silent connection is not a player"
hub_start lan
join alice; join bob
cl_open mute
pump 0.5 alice bob
cl_send alice "READY 1"
pump 2.5 alice bob mute
if saw mute '^ERR running' && [ "${CL_EOF[mute]}" -eq 1 ]; then
    pass "the silent connection was refused and closed"
else
    fail "the silent connection was not refused and closed at the start"
fi
pump 3 alice bob
cl_send bob "TOPOUT"
pump 1 alice bob
if saw alice '^KO 1 2 ko$' && saw alice '^END 0$'; then
    pass "round decided by the first top-out"
else
    fail "the round was not decided when bob topped out (expected KO 1 2 ko, END 0)"
fi
case_done

# 4. A host who topped out and then leaves does not end a running round.
log "  round: the host leaves after topping out"
hub_start lan
join alice; join bob; join carol
pump 0.5 alice bob carol
cl_send alice "READY 1"
pump 4 alice bob carol
cl_send alice "TOPOUT"
pump 0.5 bob carol
cl_send alice "BYE"
pump 1.5 bob carol
if saw bob '^PROMOTE' || saw bob '^CLOSED' || ! kill -0 "${HUB_PID}" 2>/dev/null; then
    fail "the round was moved or closed when the host left after topping out"
else
    pass "round kept its hub"
fi
cl_send bob "TOPOUT"
pump 1 bob carol
if saw carol '^END 2$'; then
    pass "round played to its end"
else
    fail "the round did not end with carol as winner (expected END 2)"
fi

# 5. The session is over after END: no newcomer, no promotion.
log "  session over: no newcomer, no handover"
cl_open late
cl_pump late 3
if saw late '^ERR over' && [ "${CL_EOF[late]}" -eq 1 ]; then
    pass "a newcomer after END is refused and closed"
else
    fail "a newcomer after END was not refused and closed (ERR over)"
fi
cl_send carol "BYE"
pump 1.5 bob
if saw bob '^PROMOTE'; then
    fail "a player was promoted after the round was over"
else
    pass "no promotion after END"
fi
case_done

# 6. A client dropped for malformed messages is really disconnected.
log "  drop: malformed messages end the connection"
hub_start lan
join alice
cl_open junk
cl_send junk "junk one"
cl_send junk "junk two"
cl_send junk "junk three"
cl_pump junk 3
if saw junk '^ERR proto' && [ "${CL_EOF[junk]}" -eq 1 ]; then
    pass "dropped client disconnected"
else
    fail "the dropped client was not disconnected (ERR proto, then end of file)"
fi
case_done

# 7. unix transport: the successor's socket survives the old hub.
log "  unix: a moved session keeps its socket"
hub_start unix
join alice unix; join bob unix
pump 0.5 alice bob
cl_send alice "BYE"
pump 0.5 bob
setsid "${GAME}" --mp-hub --mp-transport unix --mp-max 5 \
    --mp-session "${HUB_SESSION}" --mp-dir "${MPDIR}" \
    >/dev/null 2>"${WORK}/hub-successor.err" &
HUB_PIDS+=("$!")
SUCCESSOR="$!"
sleep 0.8
cl_send bob "PROMOTED ${PORT}"
pump 2 bob
if saw bob '^PROMOTE$' && [ -S "${MPDIR}/${HUB_SESSION}.sock" ] \
    && ! kill -0 "${HUB_PID}" 2>/dev/null; then
    pass "socket of the successor still there after the old hub exited"
else
    fail "the moved session lost its socket (or the old hub did not hand over)"
fi
join newbie unix
pump 0.5 newbie
if saw newbie "^WELCOME 0 ${PROTO} 5 ${HUB_SESSION}\$"; then
    pass "the moved session can be joined"
else
    fail "the moved session could not be joined"
fi
case_done
kill "${SUCCESSOR}" 2>/dev/null || :

# --- Verdict --------------------------------------------------------------
if [ "${FAILURES}" -gt 0 ]; then
    printf '%s: %d of %d checks failed\n' "${SCRIPT_NAME}" "${FAILURES}" "${CHECKS}" >&2
    exit 1
fi
log "${SCRIPT_NAME}: ${CHECKS} checks, no failures"
exit 0
