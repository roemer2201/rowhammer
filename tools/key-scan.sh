#!/usr/bin/env bash
#
# key-scan.sh
#
# Description:
#   Replay every byte sequence a terminal can send to rowhammer through the
#   game's own key reader (read_key from lib/input.sh) and report which
#   symbolic key - and therefore which game action - each one produces.
#   The point is to find sequences that are misread as unrelated key
#   presses, the class of bug behind issue #7 (a torn arrow-key sequence
#   whose trailing "C" byte was applied as the hold key "c").
#
#   The case table covers: cursor and modified cursor keys, navigation and
#   function keys, the keypad in application mode, the three mouse
#   reporting protocols, terminal replies (CSI, OSC, DCS), 8-bit CSI,
#   bracketed paste, Alt chords, control characters and non-ASCII input.
#   Each case carries the symbolic keys it is expected to produce, so the
#   script doubles as a regression test: it exits non-zero as soon as one
#   sequence maps to something else.
#
#   Sequences can additionally be fed byte by byte with a configurable gap
#   (--gap), which reproduces the split delivery seen over SSH, inside
#   tmux/screen or under load - the trigger of issue #7.
#
# Program flow:
#   1. Parse options (defaults < environment < command line).
#   2. In replay mode (internal, --replay): source lib/input.sh with
#      stubs for the game's debug/render helpers, then read keys from
#      stdin until it closes and print the symbolic key names.
#   3. Otherwise: for every case in the table, feed its bytes into a
#      replay child (optionally with a per-byte gap) and collect the keys.
#   4. Compare the result against the expectation, print a verdict line
#      per case and a summary; exit non-zero if any case deviated.
#
# Usage:
#   tools/key-scan.sh [-g SEC] [-d MS] [-o NAME] [-l] [-s|-v] [-h]
#
# Version: 1.2.0  (2026-07-26)

set -u

# --- Defaults (lowest precedence; overridden by env, then by CLI) ---------
GAP="${ROWHAMMER_KEYSCAN_GAP:-0}"
DRAIN="${ROWHAMMER_KEYSCAN_DRAIN:-0}"
ONLY="${ROWHAMMER_KEYSCAN_ONLY:-}"
LIST_ONLY="${ROWHAMMER_KEYSCAN_LIST:-0}"
SILENT="${ROWHAMMER_KEYSCAN_SILENT:-0}"
VERBOSE="${ROWHAMMER_KEYSCAN_VERBOSE:-0}"
REPLAY=0

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
    cat <<EOF
${SCRIPT_NAME} - replay terminal key sequences through rowhammer's read_key

Usage: ${SCRIPT_NAME} [options]

Options (environment variable in brackets; CLI wins over environment):
  -g, --gap SEC     Feed each sequence byte by byte with SEC seconds
                    between bytes instead of all at once. Reproduces the
                    split delivery of issue #7 (SSH, tmux, load).
                    Default: 0 (whole sequence at once)
                    [ROWHAMMER_KEYSCAN_GAP]
  -d, --drain MS    Run key_drain for MS milliseconds before reading, to
                    exercise the paths that pause the game and throw
                    input away (the row-clear flash, the resize overlay).
                    A swallowed sequence is fine (warn); a leaked tail
                    that triggers an action is not (FAIL).
                    Default: 0 (no drain)
                    [ROWHAMMER_KEYSCAN_DRAIN]
  -o, --only NAME   Run only cases whose name contains NAME (substring,
                    case sensitive). Default: all cases
                    [ROWHAMMER_KEYSCAN_ONLY]
  -l, --list        List the case names and exit, run nothing
                    [ROWHAMMER_KEYSCAN_LIST=1]
  -s, --silent      Print only failures and the summary; silent wins if
                    combined with --verbose
                    [ROWHAMMER_KEYSCAN_SILENT=1]
  -v, --verbose     Also print the raw bytes and the game action each key
                    maps to [ROWHAMMER_KEYSCAN_VERBOSE=1]
  -h, --help        Show this help and exit

Verdicts:
  ok    the sequence produced exactly the expected keys
  warn  it deviated but the leaked keys trigger no game action
  FAIL  it deviated and at least one leaked key triggers a game action

Exit status:
  0  no sequence triggered a wrong game action (warn is tolerated)
  1  at least one sequence triggered a wrong action (details on stdout)
  2  usage error

Examples:
  tools/key-scan.sh                 # full scan, instant delivery
  tools/key-scan.sh -g 0.06 -o arrow  # tear arrow keys apart (issue #7)
  tools/key-scan.sh -v -o mouse     # show what a mouse click injects
EOF
}

# err MESSAGE...
# Report a failure on stderr. Errors are never suppressed by --silent.
err() {
    printf '%s: %s\n' "${SCRIPT_NAME}" "$*" >&2
}

# say MESSAGE...
# Normal status output; suppressed in silent mode.
say() {
    if [ "${SILENT}" -eq 0 ]; then
        printf '%s\n' "$*"
    fi
}

# --- Case table -----------------------------------------------------------
# One entry per line: NAME|EXPECTED|BYTES
#   NAME      human readable label
#   EXPECTED  space separated symbolic keys read_key should report; empty
#             means the sequence must be swallowed without any key press
#   BYTES     printf %b escapes of what the terminal sends
#   FLAG      optional; "gap0" marks a case whose expectation only holds
#             for instant delivery, so --gap skips it
# The expectations describe the *correct* behaviour, not today's - a
# deviation is exactly what this script is meant to surface.
CASES=(
    # Cursor keys, both the CSI and the SS3 (application mode) form.
    "arrow up CSI|UP|\\e[A"
    "arrow down CSI|DOWN|\\e[B"
    "arrow right CSI|RIGHT|\\e[C"
    "arrow left CSI|LEFT|\\e[D"
    "arrow up SS3|UP|\\eOA"
    "arrow down SS3|DOWN|\\eOB"
    "arrow right SS3|RIGHT|\\eOC"
    "arrow left SS3|LEFT|\\eOD"
    "lone ESC|ESC|\\e"

    # Modified cursor keys. They are not game keys, so they must be
    # consumed silently - never leak their final letter.
    "mod arrow shift-up|:none:|\\e[1;2A"
    "mod arrow ctrl-right|:none:|\\e[1;5C"
    "mod arrow alt-left|:none:|\\e[1;3D"
    "mod arrow ctrl-shift-down|:none:|\\e[1;6B"
    "mod arrow rxvt ctrl-right|:none:|\\eOc"
    "mod arrow rxvt shift-right|:none:|\\e[c"
    "mod arrow rxvt ctrl-up|:none:|\\eOa"

    # Navigation and editing keys.
    "nav home CSI 1~|:none:|\\e[1~"
    "nav insert CSI 2~|:none:|\\e[2~"
    "nav delete CSI 3~|:none:|\\e[3~"
    "nav end CSI 4~|:none:|\\e[4~"
    "nav pageup CSI 5~|:none:|\\e[5~"
    "nav pagedown CSI 6~|:none:|\\e[6~"
    "nav home CSI H|:none:|\\e[H"
    "nav end CSI F|:none:|\\e[F"
    "nav shift-tab CSI Z|:none:|\\e[Z"

    # Function keys, including the Linux console's ESC [ [ X form.
    "fkey F1 SS3 P|:none:|\\eOP"
    "fkey F4 SS3 S|:none:|\\eOS"
    "fkey F5 CSI 15~|:none:|\\e[15~"
    "fkey F12 CSI 24~|:none:|\\e[24~"
    "fkey linux F1|:none:|\\e[[A"
    "fkey linux F5|:none:|\\e[[E"

    # Keypad in application mode: SS3 plus one letter, the letters happen
    # to include game keys (q, s, w, x, l, m, n, o).
    "keypad SS3 q|:none:|\\eOq"
    "keypad SS3 s|:none:|\\eOs"
    "keypad SS3 w|:none:|\\eOw"
    "keypad SS3 x|:none:|\\eOx"
    "keypad SS3 M enter|:none:|\\eOM"

    # Mouse reporting. X10 appends three raw bytes after the final "M";
    # the byte values are 32 + button/column/row, so a click in the right
    # half of a wide terminal carries printable letters.
    "mouse X10 click col 3|:none:|\\e[M \\x23\\x23"
    "mouse X10 click col 51|:none:|\\e[M \\x53\\x25"
    "mouse X10 click col 67|:none:|\\e[M \\x63\\x25"
    "mouse X10 wheel up|:none:|\\e[M\\x60\\x30\\x30"
    "mouse SGR press|:none:|\\e[<0;12;34M"
    "mouse SGR release|:none:|\\e[<0;12;34m"
    "mouse urxvt 1015|:none:|\\e[32;12;34M"

    # Terminal replies. The game does not query the terminal itself, but
    # a reply left over from a program that ran before it lands in the
    # same input stream.
    "reply focus in|:none:|\\e[I"
    "reply focus out|:none:|\\e[O"
    "reply DA1|:none:|\\e[?1;2c"
    "reply DA2|:none:|\\e[>0;276;0c"
    "reply CPR cursor position|:none:|\\e[24;80R"
    "reply CSI with many params|:none:|\\e[1;2;3;4;5;6;7;8;9;10;11;12;13;14;15c"
    "reply OSC 11 color (ST)|:none:|\\e]11;rgb:2e2e/3434/3636\\e\\\\"
    "reply OSC 11 color (BEL)|:none:|\\e]11;rgb:2e2e/3434/3636\\a"
    "reply OSC 52 clipboard|:none:|\\e]52;c;d3dhc2Q=\\a"
    "reply DCS DECRPSS|:none:|\\eP1\$r0m\\e\\\\"
    "reply DCS XTVERSION|:none:|\\eP>|XTerm(388)\\e\\\\"
    # 8-bit CSI: a terminal in 8-bit mode sends 0x9b instead of "ESC [",
    # so this is a genuine arrow key press and must map like one.
    "8-bit CSI arrow up|UP|\\x9bA"

    # Bracketed paste: the wrapper is a CSI sequence, the payload is not.
    # A middle-click paste during play must not run the pasted text as
    # game commands.
    "paste bracketed wasd|:none:|\\e[200~wasd\\e[201~"
    "paste bracketed sentence|:none:|\\e[200~hello world\\e[201~"

    # Alt chords: ESC plus the plain byte of the key.
    # Alt chords are only recognisable as one chord while ESC and the
    # byte arrive together (ESC_ALT_MS in lib/input.sh). Torn further
    # apart they are deliberately read as a real Esc plus a key, which is
    # the trade-off that keeps a deliberate Esc from being swallowed - so
    # these cases are meaningful without an artificial gap only.
    "alt chord alt-c|:none:|\\ec|gap0"
    "alt chord alt-x|:none:|\\ex|gap0"
    "alt chord alt-2|:none:|\\e2|gap0"

    # Control characters. Enter arrives as LF once the tty translated it.
    "ctrl NUL (ctrl-space)|:none:|\\x00"
    "ctrl ctrl-a|:none:|\\x01"
    "ctrl ctrl-c|:none:|\\x03"
    "ctrl tab|:none:|\\x09"
    "ctrl LF is enter|ENTER|\\x0a"
    "ctrl DEL 0x7f|:none:|\\x7f"

    # Non-ASCII input (umlaut on a German keyboard, euro sign).
    "utf8 umlaut|:none:|\\xc3\\xa4"
    "utf8 euro|:none:|\\xe2\\x82\\xac"

    # Sanity: the plain game keys and an autorepeat burst must still work.
    "plain game keys|a d s w e q c p x 2 SPACE|adsweqcpx2 "
    "plain uppercase|a d c|ADC"
    "burst arrows autorepeat|RIGHT RIGHT RIGHT|\\e[C\\e[C\\e[C"
    "burst arrows mixed|RIGHT LEFT UP DOWN|\\e[C\\e[D\\e[A\\e[B"
)

# --- Replay child ---------------------------------------------------------
# Source lib/input.sh and report the symbolic key of every press until
# stdin closes. Runs as a child process of the scan so a torn sequence
# cannot bleed from one case into the next. The library needs a handful of
# helpers from the game; they are stubbed out because this tool tests the
# key mapping, not the renderer or the debug log.
run_replay() {
    die() { exit 0; }                 # read_key calls die on closed stdin
    debug_input() { :; }
    debug_event() { :; }
    screen_write() { :; }
    term_too_small_screen() { :; }
    # The escape parser timestamps a pending ESC; now_ms lives in
    # rowhammer.sh, so provide the same contract here.
    now_ms() {
        local t="${EPOCHREALTIME/,/.}"
        local usec="${t#*.}"
        NOW_MS=$(( ${t%.*} * 1000 + 10#${usec:0:3} ))
    }
    TERM_RESIZED=0
    TERM_TOO_SMALL=0
    REDRAW_PENDING=0
    TERM_ROWS=40
    TERM_COLS=120
    MIN_TERM_ROWS=22
    MIN_TERM_COLS=48
    # shellcheck source=/dev/null
    source "${REPO_ROOT}/lib/input.sh"
    # Exercise the discard path first when asked: whatever it consumes
    # must be consumed whole, never leaving a sequence tail behind.
    if [ "${KEYSCAN_DRAIN:-0}" -gt 0 ]; then
        key_drain "${KEYSCAN_DRAIN}"
    fi
    local out=""
    while :; do
        KEY=""
        read_key
        if [ -n "${KEY}" ]; then
            out="${out}${out:+ }${KEY}"
            # Print incrementally: die exits the process on EOF, so a
            # final print after the loop would never be reached.
            printf '%s\n' "${out}" > "${KEYSCAN_OUT}"
        fi
    done
}

# action_for KEY
# Map a symbolic key to the game action it triggers, using the default
# bindings from rowhammer.sh. Only used for the verbose report.
action_for() {
    case "${1}" in
        LEFT|a)      printf 'move left' ;;
        RIGHT|d)     printf 'move right' ;;
        e)           printf 'rotate cw' ;;
        q)           printf 'rotate ccw' ;;
        DOWN|s)      printf 'soft drop' ;;
        UP|SPACE|w)  printf 'hard drop' ;;
        2|c)         printf 'HOLD' ;;
        p)           printf 'pause' ;;
        x|ESC)       printf 'pause menu' ;;
        r)           printf 'restart (game over screen)' ;;
        ENTER)       printf 'menu select' ;;
        *)           printf 'no action' ;;
    esac
}

# actions_for KEYS
# Join the actions of a whole key list for the verbose report.
actions_for() {
    local k out=""
    for k in ${1}; do
        out="${out}${out:+, }${k}=$(action_for "${k}")"
    done
    printf '%s' "${out:--}"
}

# How long the feeder holds the pipe open after a sequence that can leave
# a lone ESC pending. read_key only reports ESC once ESC_LONE_MS has
# passed without a continuation byte, so closing stdin right away would
# never let that timer fire. Kept above lib/input.sh's ESC_LONE_MS.
HOLD_S="0.4"

# feed BYTES HOLD
# Write the sequence to stdout, either in one go or byte by byte with the
# configured gap. The gap path is what tears a sequence apart the way a
# slow SSH link or a loaded host does. With HOLD set to 1 the pipe stays
# open afterwards long enough for the lone-ESC timer to fire.
feed() {
    local bytes="${1}" hold="${2}" raw i len
    if [ "${GAP}" = "0" ]; then
        printf '%b' "${bytes}"
    else
        printf -v raw '%b' "${bytes}"
        len="${#raw}"
        for (( i = 0; i < len; i++ )); do
            printf '%s' "${raw:i:1}"
            sleep "${GAP}"
        done
    fi
    if [ "${hold}" -eq 1 ]; then
        sleep "${HOLD_S}"
    fi
}

# triggers_action KEYS
# True when at least one of the reported keys is bound to a game action.
# This is what separates a dangerous leak (the piece moves, the hold slot
# swaps, the pause menu opens) from harmless noise such as a stray control
# byte that maps to nothing.
triggers_action() {
    local k
    for k in ${1}; do
        if [ "$(action_for "${k}")" != "no action" ]; then
            return 0
        fi
    done
    return 1
}

# run_case NAME EXPECTED BYTES
# Feed one sequence into a replay child and compare the keys it reported
# against the expectation. Sets CASE_STATUS to ok, warn (deviates but
# triggers nothing) or fail (deviates and triggers a game action).
run_case() {
    local name="${1}" expected="${2}" bytes="${3}" got="" hold=0
    if [ "${expected}" = ":none:" ]; then
        expected=""
    fi
    # A case that expects an ESC needs the lone-ESC timer to run out.
    if [[ "${expected}" == *ESC* ]]; then
        hold=1
    fi
    KEYSCAN_OUT="$(mktemp)"
    export KEYSCAN_OUT
    feed "${bytes}" "${hold}" | KEYSCAN_REPLAY=1 KEYSCAN_DRAIN="${DRAIN}" \
        "${BASH}" "${SCRIPT_DIR}/${SCRIPT_NAME}" --replay
    got="$(cat "${KEYSCAN_OUT}")"
    rm -f "${KEYSCAN_OUT}"
    if [ "${got}" = "${expected}" ]; then
        CASE_STATUS="ok"
        say "$(printf 'ok   %-32s -> %s' "${name}" "${got:-(nothing)}")"
        if [ "${VERBOSE}" -eq 1 ]; then
            say "$(printf '     bytes %-26s    %s' "${bytes}" "$(actions_for "${got}")")"
        fi
        return 0
    fi
    if triggers_action "${got}"; then
        CASE_STATUS="fail"
        printf 'FAIL %-32s -> %s\n' "${name}" "${got:-(nothing)}"
    else
        CASE_STATUS="warn"
        # Deviates from the expectation but maps to nothing the game acts
        # on. Worth fixing for tidiness, not a gameplay bug.
        say "$(printf 'warn %-32s -> %s' "${name}" "${got:-(nothing)}")"
        if [ "${SILENT}" -eq 1 ]; then
            return 0
        fi
    fi
    printf '     expected %s\n' "${expected:-(nothing)}"
    printf '     bytes    %s\n' "${bytes}"
    printf '     actions  %s\n' "$(actions_for "${got}")"
    return 0
}

# --- Option parsing (command line wins over the environment) --------------
if [ "${KEYSCAN_REPLAY:-0}" = "1" ]; then
    REPLAY=1
fi
while [ "$#" -gt 0 ]; do
    case "${1}" in
        --replay)      REPLAY=1 ;;
        -g|--gap)
            if [ "$#" -lt 2 ]; then
                err "Option ${1} needs a value (seconds between bytes)"
                exit 2
            fi
            GAP="${2}"
            shift
            ;;
        -d|--drain)
            if [ "$#" -lt 2 ]; then
                err "Option ${1} needs a value (milliseconds)"
                exit 2
            fi
            DRAIN="${2}"
            shift
            ;;
        -o|--only)
            if [ "$#" -lt 2 ]; then
                err "Option ${1} needs a value (case name substring)"
                exit 2
            fi
            ONLY="${2}"
            shift
            ;;
        -l|--list)     LIST_ONLY=1 ;;
        -s|--silent)   SILENT=1 ;;
        -v|--verbose)  VERBOSE=1 ;;
        -h|--help)     usage; exit 0 ;;
        *)
            err "Unknown option: ${1}"
            usage >&2
            exit 2
            ;;
    esac
    shift
done

if [ "${REPLAY}" -eq 1 ]; then
    run_replay
    exit 0
fi

# Silent wins over verbose, as documented in the help.
if [ "${SILENT}" -eq 1 ]; then
    VERBOSE=0
fi
if ! [[ "${GAP}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    err "Invalid --gap value: '${GAP}' (expected seconds, e.g. 0.06)"
    exit 2
fi
if ! [[ "${DRAIN}" =~ ^[0-9]+$ ]]; then
    err "Invalid --drain value: '${DRAIN}' (expected whole milliseconds)"
    exit 2
fi
if [ ! -r "${REPO_ROOT}/lib/input.sh" ]; then
    err "Cannot read ${REPO_ROOT}/lib/input.sh - run this from the repository"
    exit 2
fi

# --- Run ------------------------------------------------------------------
total=0
failed=0
warned=0
CASE_STATUS="ok"
for entry in "${CASES[@]}"; do
    IFS='|' read -r case_name case_expect case_bytes case_flag <<<"${entry}"
    if [ -n "${ONLY}" ] && [[ "${case_name}" != *"${ONLY}"* ]]; then
        continue
    fi
    if [ "${case_flag}" = "gap0" ] && [ "${GAP}" != "0" ] && [ "${LIST_ONLY}" -eq 0 ]; then
        say "$(printf 'skip %-32s -> expectation holds for instant delivery only' "${case_name}")"
        continue
    fi
    if [ "${LIST_ONLY}" -eq 1 ]; then
        printf '%s\n' "${case_name}"
        continue
    fi
    total=$(( total + 1 ))
    run_case "${case_name}" "${case_expect}" "${case_bytes}"
    case "${CASE_STATUS}" in
        fail) failed=$(( failed + 1 )) ;;
        warn) warned=$(( warned + 1 )) ;;
    esac
done

if [ "${LIST_ONLY}" -eq 1 ]; then
    exit 0
fi
if [ "${total}" -eq 0 ]; then
    err "No case matched --only '${ONLY}'"
    exit 2
fi

printf '\n%d of %d sequences trigger a wrong game action, %d leak inert keys (gap %ss)\n' \
    "${failed}" "${total}" "${warned}" "${GAP}"
if [ "${failed}" -gt 0 ]; then
    exit 1
fi
exit 0
