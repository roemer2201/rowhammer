#!/usr/bin/env bash
#
# tools/net-fuzz.sh
#
# Description:
#   Fuzz test for the three parsers of the rowhammer multiplayer: the
#   line filter of the transport (net_line_ok, lib/net.sh), the message
#   parser of the protocol (proto_parse, lib/proto.sh) and the beacon
#   collector a complete stranger can reach without ever opening a
#   connection (net_discover_poll). It feeds them random and deliberately
#   hostile lines - ANSI escapes, command substitutions, backticks, path
#   traversal, overlength, null bytes, half lines - and checks the three
#   properties CLAUDE.md 5.5 makes non-negotiable:
#     1. no command out of the input is ever executed,
#     2. no byte outside 0x20-0x7E survives into anything the game would
#        print,
#     3. no input kills the process or makes it hang.
#   Property 1 is checked with a canary: every payload that could execute
#   something writes into a file, and the file must not exist afterwards.
#
# Program flow:
#   1. Parse arguments, resolve the repository root.
#   2. Source the library modules the parsers need.
#   3. Run the fixed hostile cases, then --random pseudo-random lines.
#   4. Report how many cases ran and exit non-zero on any violation.
#
# Usage:
#   net-fuzz.sh [-n|--random N] [-s|--seed N] [-v|--verbose] [-q|--silent]
#               [-h|--help]
#
# Version: 1.0.0  (2026-08-11)

set -euo pipefail

SCRIPT_NAME="$(basename -- "${0}")"
REPO_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)"

# --- Defaults seeded from environment variables ---------------------------
# Precedence: command-line argument > environment variable > default.
RANDOM_CASES="${ROWHAMMER_FUZZ_RANDOM:-500}"
FUZZ_SEED="${ROWHAMMER_FUZZ_SEED:-1}"
VERBOSE="${ROWHAMMER_FUZZ_VERBOSE:-0}"
SILENT="${ROWHAMMER_FUZZ_SILENT:-0}"

usage() {
    cat <<'EOF'
Usage: net-fuzz.sh [OPTIONS]

Fuzz the multiplayer parsers of rowhammer with hostile input and verify
that nothing is executed, nothing but printable ASCII gets through and
no case crashes or hangs.

Options:
  -n, --random N   Number of random cases after the fixed ones.
                   Env: ROWHAMMER_FUZZ_RANDOM   Default: 500
  -s, --seed N     Seed for the random cases, so a failure is
                   reproducible.
                   Env: ROWHAMMER_FUZZ_SEED     Default: 1
  -v, --verbose    Print every case as it runs.
                   Env: ROWHAMMER_FUZZ_VERBOSE  Default: 0
  -q, --silent     Print nothing but errors.
                   Env: ROWHAMMER_FUZZ_SILENT   Default: 0
  -h, --help       Show this help and exit.

Exit code 0 when every case passed, 1 on a violation, 2 on a usage error.
EOF
}

die() {
    printf '%s: %s\n' "${SCRIPT_NAME}" "$*" >&2
    exit 1
}

log() {
    if [ "${SILENT}" -eq 0 ]; then
        printf '%s\n' "$*"
    fi
}

vlog() {
    if [ "${VERBOSE}" -eq 1 ] && [ "${SILENT}" -eq 0 ]; then
        printf '  %s\n' "$*"
    fi
}

while [ "$#" -gt 0 ]; do
    case "${1}" in
        -n|--random)
            [ "$#" -ge 2 ] || { printf '%s: %s needs an argument\n' "${SCRIPT_NAME}" "${1}" >&2; exit 2; }
            RANDOM_CASES="${2}"
            shift 2
            ;;
        -s|--seed)
            [ "$#" -ge 2 ] || { printf '%s: %s needs an argument\n' "${SCRIPT_NAME}" "${1}" >&2; exit 2; }
            FUZZ_SEED="${2}"
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
if ! [[ "${RANDOM_CASES}" =~ ^[0-9]+$ ]]; then
    printf '%s: --random expects a number, got: %s\n' "${SCRIPT_NAME}" "${RANDOM_CASES}" >&2
    exit 2
fi
if ! [[ "${FUZZ_SEED}" =~ ^[0-9]+$ ]]; then
    printf '%s: --seed expects a number, got: %s\n' "${SCRIPT_NAME}" "${FUZZ_SEED}" >&2
    exit 2
fi
if [ "${VERBOSE}" -eq 1 ] && [ "${SILENT}" -eq 1 ]; then
    printf '%s: --verbose and --silent are mutually exclusive\n' "${SCRIPT_NAME}" >&2
    exit 2
fi

# --- Harness --------------------------------------------------------------
# The parsers are library code that expects to be sourced into the game,
# so the few globals they read are stubbed here rather than pulling the
# whole game in. This is deliberately the same code path the game uses -
# a fuzz test against a copy of the parser would prove nothing.
SCRIPT_DIR="${REPO_DIR}"
DEBUG_ACTIVE=0
DEBUG_OPT=0
NOW_MS=0
BOARD_W=10
BOARD_H=22
HIDDEN_ROWS=2
EMPTY_CELL="."
GARBAGE_CELL="x"
BOARD=()
BOARD_SQ=()
MP_PORT=27301
MP_MAX=5
MP_SESSION="fuzz"
MP_TRANSPORT="lan"
MP_DIR="${TMPDIR:-/tmp}/rowhammer-fuzz-$$"

# now_ms and debug_* are the only game functions the parsers call.
now_ms() {
    if [ -n "${EPOCHREALTIME:-}" ]; then
        local t="${EPOCHREALTIME/,/.}"
        local usec="${t#*.}"
        NOW_MS=$(( ${t%.*} * 1000 + 10#${usec:0:3} ))
    else
        NOW_MS=$(( $(date +%s%N) / 1000000 ))
    fi
}
debug_event() { :; }
debug_frame() { :; }
debug_input() { :; }

for lib in net proto; do
    [ -r "${REPO_DIR}/lib/${lib}.sh" ] || die "missing library: lib/${lib}.sh"
    # shellcheck source=/dev/null
    . "${REPO_DIR}/lib/${lib}.sh"
done

# The canary: every payload that could run a command writes into this
# file. It must not exist when the run is over - if it does, something
# expanded input as code, which is the one failure this test exists for.
CANARY_DIR="$(mktemp -d -- "${TMPDIR:-/tmp}/rowhammer-fuzz.XXXXXX")"
CANARY="${CANARY_DIR}/canary"
trap 'rm -rf -- "${CANARY_DIR}"' EXIT

FAILURES=0
CASES=0

# check_line LINE
# Run one input through both parsers and verify the three properties. The
# parsers are allowed to accept or reject it - what they may not do is
# execute it, pass control characters on, or die.
check_line() {
    local line="${1}" rc=0
    CASES=$(( CASES + 1 ))
    vlog "case: $(printf '%q' "${line}")"

    # 1. The transport's filter. Whatever it accepts must be printable
    #    ASCII; whatever it rejects is simply gone.
    if net_line_ok "${line}"; then
        # LC_ALL=C for the duration of the test, because a glob range
        # like [\x00-\x1f] follows the locale's collation order: in a
        # UTF-8 locale it matches "." and this check would report a
        # failure that is not one. In the C locale the class means the
        # bytes it says.
        local LC_ALL=C
        if [[ "${line}" == *[![:print:]]* ]]; then
            printf '%s: FAIL net_line_ok accepted a control character: %q\n' \
                "${SCRIPT_NAME}" "${line}" >&2
            FAILURES=$(( FAILURES + 1 ))
        fi
    fi

    # 2. The message parser. Its verdict is not under test - its
    #    behaviour is: it must return, and it must not leave a value in
    #    PROTO_ARG that failed its pattern.
    PROTO_VERB=""
    PROTO_ARG=()
    proto_parse "${line}" || rc=$?
    if [ "${rc}" -eq 0 ]; then
        local spec i
        local -a spec_a
        spec="${PROTO_MSG[${PROTO_VERB}]}"
        # shellcheck disable=SC2206
        spec_a=(${spec})
        for (( i = 0; i < ${#spec_a[@]}; i++ )); do
            if ! proto_field_ok "${spec_a[i]}" "${PROTO_ARG[i]}"; then
                printf '%s: FAIL proto_parse accepted a bad field: %q\n' \
                    "${SCRIPT_NAME}" "${line}" >&2
                FAILURES=$(( FAILURES + 1 ))
            fi
        done
    fi
    return 0
}

# check_beacon LINE
# The same for the beacon collector, which is the first parser a stranger
# reaches - it needs no connection at all, only a datagram. The line is
# handed to it exactly as a socat child would: sender address in front.
check_beacon() {
    local line="${1}"
    CASES=$(( CASES + 1 ))
    # Cut to the transport's limit before writing, which is exactly what
    # the real collector does with a datagram (net_discover_child): a
    # 100 kB line would otherwise fill the FIFO's buffer and block this
    # test rather than the parser it is meant to test.
    line="${line:0:${MP_LINE_MAX}}"
    printf '%s %s\n' "192.0.2.7" "${line}" >&"${NET_DISCOVER_FD}"
    net_discover_poll
    local i
    for (( i = 0; i < ${#NET_SESSION_NAME[@]}; i++ )); do
        if ! [[ "${NET_SESSION_NAME[i]}" =~ ${MP_SESSION_RE} ]]; then
            printf '%s: FAIL a beacon put an invalid session name in the list: %q\n' \
                "${SCRIPT_NAME}" "${NET_SESSION_NAME[i]}" >&2
            FAILURES=$(( FAILURES + 1 ))
        fi
        if ! net_ipv4_ok "${NET_SESSION_HOST[i]}"; then
            printf '%s: FAIL a beacon put an invalid address in the list: %q\n' \
                "${SCRIPT_NAME}" "${NET_SESSION_HOST[i]}" >&2
            FAILURES=$(( FAILURES + 1 ))
        fi
    done
    return 0
}

# check_addr HOST PORT
# Address building must never carry a byte of its input into the socat
# address: whatever comes out has to match the shape of a TCP address
# built from numbers.
check_addr() {
    CASES=$(( CASES + 1 ))
    NET_ADDR=""
    if net_addr_tcp "${1}" "${2}"; then
        if ! [[ "${NET_ADDR}" =~ ^TCP4:[A-Za-z0-9.-]+:[0-9]{1,5}$ ]]; then
            printf '%s: FAIL net_addr_tcp built a suspicious address: %q\n' \
                "${SCRIPT_NAME}" "${NET_ADDR}" >&2
            FAILURES=$(( FAILURES + 1 ))
        fi
    fi
    return 0
}

# --- The hostile cases ----------------------------------------------------
log "${SCRIPT_NAME}: fixed cases"

# A pipe as the collector's FIFO, so the beacon path can be exercised
# without a socat listener.
BEACON_DIR="${CANARY_DIR}/beacons"
mkdir -p -- "${BEACON_DIR}"
NET_DISCOVER_FIFO="${BEACON_DIR}/fifo"
mkfifo -m 0600 -- "${NET_DISCOVER_FIFO}"
exec 7<>"${NET_DISCOVER_FIFO}"
NET_DISCOVER_FD=7

HOSTILE=(
    # Command substitution and backticks in every field a message has.
    'HELLO 1 $(touch CANARY) board'
    'HELLO 1 `touch CANARY` board'
    'STATE $(touch CANARY) 0 0 0 0 0 0'
    'GARBAGE $(touch CANARY) 0'
    'GARBAGE 1;touch CANARY 0'
    'KO 0 $((1+1))'
    # Arithmetic injection: the classic way an unchecked number turns
    # into code inside $(( )).
    'STATE a[$(touch CANARY)] 0 0 0 0 0 0'
    'QUEUE a[$(touch CANARY)]'
    'APPLIED 1$(touch CANARY)'
    # Array index injection.
    'PEER a[$(touch CANARY)] 0 0 0 0 0 0 0 play'
    'ROSTER 9999999999 name 1 lobby'
    'PEERBOARD -1 ..................................................................................................................................................................................................'
    # ANSI escapes and terminal replies in a name.
    "HELLO 1 $(printf '\033[2J') board"
    "ROSTER 0 $(printf '\033]0;pwned\007') 1 lobby"
    "ERR proto $(printf '\033[6n')"
    # Path traversal where a name becomes a file name.
    'HELLO 1 ../../etc/passwd board'
    'HELLO 1 ..%2f..%2fetc board'
    # Nulls, tabs, newlines, high bytes.
    "HELLO 1 na$(printf '\t')me board"
    "HELLO 1 na$(printf '\001')me board"
    # Wrong shapes.
    ''
    ' '
    'hello 1 name board'
    'HELLO'
    'HELLO 1'
    'HELLO 1 name board extra'
    'UNKNOWNVERB 1 2 3'
    'STATE 1 2 3'
    'BOARD tooshort'
    'PING abc'
    'END x'
)
for c in "${HOSTILE[@]}"; do
    check_line "${c}"
    check_beacon "${c}"
done

# Overlength: 100 kB in one line, and a line of exactly the limit.
long="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
while [ "${#long}" -lt 100000 ]; do
    long="${long}${long}"
done
check_line "HELLO 1 ${long} board"
check_line "${long}"
check_beacon "ROWHAMMER 1 ${long} 1 6 27301 lobby"

# A well-formed beacon must actually make it through, otherwise the test
# above would pass on a parser that rejects everything.
check_beacon "ROWHAMMER ${PROTO_VERSION} lanparty 2 6 27301 lobby"
if [ "${#NET_SESSION_NAME[@]}" -eq 0 ]; then
    printf '%s: FAIL a valid beacon was not accepted\n' "${SCRIPT_NAME}" >&2
    FAILURES=$(( FAILURES + 1 ))
fi

# Addresses out of hostile input.
check_addr '$(touch CANARY)' 27301
check_addr '1.2.3.4,exec:sh' 27301
check_addr '1.2.3.4' '27301,fork'
check_addr '999.1.1.1' 27301
check_addr '1.2.3.4' '0'
check_addr '../../etc' 27301
check_addr 'host name' 27301
# ... and a good one, so the check cannot pass by rejecting everything.
NET_ADDR=""
if ! net_addr_tcp '192.168.1.23' 27301 || [ "${NET_ADDR}" != "TCP4:192.168.1.23:27301" ]; then
    printf '%s: FAIL a valid address was not built: %q\n' "${SCRIPT_NAME}" "${NET_ADDR}" >&2
    FAILURES=$(( FAILURES + 1 ))
fi

# --- Random cases ---------------------------------------------------------
log "${SCRIPT_NAME}: ${RANDOM_CASES} random cases (seed ${FUZZ_SEED})"
RANDOM="${FUZZ_SEED}"
ALPHABET=(A B C Z 0 1 9 ' ' '$' '(' ')' '`' ';' '|' '&' '*' '.' '/' '\' '-' '_' '[' ']' '{' '}' '%' '!' '#' "'" '"' $'\t' $'\033')
VERBS=(HELLO READY STATE BOARD CLEAR APPLIED TOPOUT PONG BYE WELCOME ROSTER SEED START PEER PEERBOARD NEEDBOARD GARBAGE QUEUE KO END PING ERR XXXX)
for (( n = 0; n < RANDOM_CASES; n++ )); do
    len=$(( RANDOM % 40 ))
    line="${VERBS[RANDOM % ${#VERBS[@]}]} "
    for (( j = 0; j < len; j++ )); do
        line+="${ALPHABET[RANDOM % ${#ALPHABET[@]}]}"
    done
    check_line "${line}"
    if [ $(( n % 5 )) -eq 0 ]; then
        check_beacon "${line}"
    fi
done

# --- Verdict --------------------------------------------------------------
exec 7<&-
if [ -e "${CANARY}" ] || [ -e "CANARY" ] || [ -e "${REPO_DIR}/CANARY" ]; then
    printf '%s: FAIL a payload was executed (canary file exists)\n' "${SCRIPT_NAME}" >&2
    rm -f -- CANARY "${REPO_DIR}/CANARY" 2>/dev/null || :
    FAILURES=$(( FAILURES + 1 ))
fi

if [ "${FAILURES}" -gt 0 ]; then
    printf '%s: %d failure(s) in %d cases\n' "${SCRIPT_NAME}" "${FAILURES}" "${CASES}" >&2
    exit 1
fi
log "${SCRIPT_NAME}: ${CASES} cases, no failures"
exit 0
