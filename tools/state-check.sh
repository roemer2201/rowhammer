#!/usr/bin/env bash
#
# tools/state-check.sh
#
# Description:
#   Regression test for the round state module (lib/state.sh), the
#   foundation the multiplayer demo playback stands on (CLAUDE.md 5.20).
#   It checks the two properties that module has to have, because a fault
#   in either would show up later as a playback that quietly mixes two
#   players' boards:
#     1. Separation. Five slots are created, every one of them is filled
#        with values of its own - arrays, associative arrays and scalars -
#        and every slot is read back afterwards. A write to one slot must
#        never be visible in another, and that has to hold for writes made
#        from inside a function as well, which is how the real round
#        functions write.
#     2. Completeness. STATE_VARS has to cover what a round consists of,
#        and the other end of that list is game_reset in rowhammer.sh:
#        what a round resets is what a round is made of. Every variable
#        game_reset assigns has to be in STATE_VARS or in the small list
#        of session state below, which is deliberately not part of a
#        round (see SESSION_VARS).
#   Headless by design, like tools/key-scan.sh and tools/net-fuzz.sh: it
#   sources the module, never starts the game and needs no terminal, so
#   the CI can run it on every push.
#
# Program flow:
#   1. Parse arguments and resolve the repository root.
#   2. Source lib/state.sh.
#   3. Separation: create five slots, write, read back, compare.
#   4. Rebinding: prove a bound slot survives a detour to another slot,
#      that state_release leaves nothing behind, and that state_unbind
#      puts the plain globals back the way the modules declared them.
#   5. Completeness: compare STATE_VARS against the assignments in
#      game_reset.
#   6. Report the number of checks and exit non-zero on any failure.
#
# Usage:
#   state-check.sh [-v|--verbose] [-s|--silent] [-h|--help]
#
# Version: 1.1.0  (2026-09-02)

set -euo pipefail

SCRIPT_NAME="$(basename -- "${0}")"
REPO_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)"

# --- Defaults seeded from environment variables ---------------------------
# Precedence: command-line argument > environment variable > default.
VERBOSE="${ROWHAMMER_STATE_VERBOSE:-0}"
SILENT="${ROWHAMMER_STATE_SILENT:-0}"

usage() {
    cat <<'EOF'
Usage: state-check.sh [OPTIONS]

Check the round state module (lib/state.sh): five slots must stay
separate, and its variable list must cover everything game_reset resets.

Options:
  -v, --verbose    Print every check as it runs.
                   Env: ROWHAMMER_STATE_VERBOSE  Default: 0
  -s, --silent     Print errors only.
                   Env: ROWHAMMER_STATE_SILENT   Default: 0
  -h, --help       Show this help and exit.

Exit code 0 when every check passed, 1 on a failure, 2 on a usage error.
EOF
}

log() {
    if [ "${SILENT}" -eq 0 ]; then
        printf '%s\n' "${1}"
    fi
}

vlog() {
    if [ "${VERBOSE}" -eq 1 ] && [ "${SILENT}" -eq 0 ]; then
        printf '  %s\n' "${1}"
    fi
}

# --- Argument parsing (highest precedence) --------------------------------
while [ "$#" -gt 0 ]; do
    case "${1}" in
        -v|--verbose) VERBOSE=1; shift ;;
        -s|--silent)  SILENT=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        *)
            printf '%s: unknown option: %s\n' "${SCRIPT_NAME}" "${1}" >&2
            printf 'Try "%s --help".\n' "${SCRIPT_NAME}" >&2
            exit 2
            ;;
    esac
done

if [ "${VERBOSE}" -eq 1 ] && [ "${SILENT}" -eq 1 ]; then
    printf '%s: --verbose and --silent are mutually exclusive\n' \
        "${SCRIPT_NAME}" >&2
    exit 2
fi

# --- Module under test ----------------------------------------------------
# lib/state.sh is self-contained: it declares its own list and touches
# nothing else in the game, which is what makes it testable on its own.
if [ ! -r "${REPO_DIR}/lib/state.sh" ]; then
    printf '%s: missing library file: %s\n' \
        "${SCRIPT_NAME}" "${REPO_DIR}/lib/state.sh" >&2
    exit 1
fi
# shellcheck source=/dev/null
. "${REPO_DIR}/lib/state.sh"

CHECKS=0
FAILURES=0

# check DESCRIPTION EXPECTED ACTUAL
# One comparison. Counted either way, reported only when it fails - a
# passing run should say how much it checked, not what.
check() {
    local what="${1}" want="${2}" got="${3}"
    CHECKS=$(( CHECKS + 1 ))
    if [ "${want}" = "${got}" ]; then
        vlog "ok: ${what}"
        return 0
    fi
    printf '%s: FAIL %s\n  expected: %s\n  actual:   %s\n' \
        "${SCRIPT_NAME}" "${what}" "${want}" "${got}" >&2
    FAILURES=$(( FAILURES + 1 ))
    return 0
}

# --- 1. Separation of five slots ------------------------------------------
# Five is the number that matters: MP_MAX, the largest session the game
# allows, and therefore the most rounds a playback ever has to hold.
log "${SCRIPT_NAME}: five slots, separation"

# Written from inside a function on purpose: the real round functions are
# functions too, and a nameref has to carry a write out of one.
fill_slot() {
    local slot="${1}"
    BOARD=("b${slot}-0" "b${slot}-1")
    BOARD_ID=("${slot}" "${slot}")
    INSTANCE_CUT["inst${slot}"]="cut${slot}"
    INSTANCE_SQUARED["inst${slot}"]="sq${slot}"
    QUEUE=("q${slot}")
    ROW_CREDIT=$(( slot * 100 ))
    CLEARED_TOTAL=$(( slot * 10 ))
    GAME_MODE="mode${slot}"
    MP_PENDING="${slot}"
    return 0
}

for slot in 0 1 2 3 4; do
    state_new "${slot}"
done
for slot in 0 1 2 3 4; do
    state_bind "${slot}"
    fill_slot "${slot}"
done

# Read every slot back after all five have been written: a bug that lets
# one slot overwrite another only shows up once the others have run.
for slot in 0 1 2 3 4; do
    state_bind "${slot}"
    check "slot ${slot} board"      "b${slot}-0 b${slot}-1" "${BOARD[*]}"
    check "slot ${slot} board id"   "${slot} ${slot}"       "${BOARD_ID[*]}"
    check "slot ${slot} cut"        "cut${slot}"   "${INSTANCE_CUT[inst${slot}]}"
    check "slot ${slot} squared"    "sq${slot}"    "${INSTANCE_SQUARED[inst${slot}]}"
    check "slot ${slot} queue"      "q${slot}"     "${QUEUE[*]}"
    check "slot ${slot} row credit" "$(( slot * 100 ))" "${ROW_CREDIT}"
    check "slot ${slot} lines"      "$(( slot * 10 ))"  "${CLEARED_TOTAL}"
    check "slot ${slot} mode"       "mode${slot}"  "${GAME_MODE}"
    check "slot ${slot} pending"    "${slot}"      "${MP_PENDING}"
    # The associative tables must hold their own key only: a shared table
    # would show every slot's entries at once, which is the failure this
    # separates out from a merely wrong value.
    check "slot ${slot} cut keys"   "1" "${#INSTANCE_CUT[@]}"
done

# The types have to survive the binding, not just the values: an indexed
# array that arrives as a scalar would break board_init on the first frame.
state_bind 2
check "board stays an indexed array" "-a" "$(declare -p RSTATE2_BOARD | cut -d' ' -f2)"
check "cut stays associative"        "-A" "$(declare -p RSTATE2_INSTANCE_CUT | cut -d' ' -f2)"

# --- 2. Rebinding, unbinding and releasing --------------------------------
log "${SCRIPT_NAME}: rebinding and release"

# A detour to another slot and back must leave the first one untouched -
# that is what a playback does several times per frame.
state_bind 1
ROW_CREDIT=111
state_bind 3
ROW_CREDIT=333
state_bind 1
check "slot 1 survives a detour" "111" "${ROW_CREDIT}"
state_bind 3
check "slot 3 survives a detour" "333" "${ROW_CREDIT}"

# state_unbind must remove the pointer, not the data behind it, and it
# has to put plain globals back in its place: a round started after a
# playback runs on them, and the two instance tables have to be
# associative again or it would key them by a number it never meant.
state_unbind
check "unbind clears the slot marker" "-1" "${STATE_SLOT}"
check "unbind leaves the data"        "333" "${RSTATE3_ROW_CREDIT}"
check "unbind leaves no nameref"      "" \
    "$(declare -p ROW_CREDIT 2>/dev/null | grep -o -- '-n')"
check "unbind restores a plain global" "0" \
    "$(declare -p ROW_CREDIT >/dev/null 2>&1; printf '%d' "$?")"
check "unbind restores the array kind" "-a" \
    "$(declare -p BOARD | cut -d' ' -f2)"
check "unbind restores the table kind" "-A" \
    "$(declare -p INSTANCE_CUT | cut -d' ' -f2)"
check "unbind restores it empty"       "0" "${#BOARD[@]}"

# Releasing a slot drops its backing variables; releasing the bound slot
# has to unbind it first rather than leave dangling names behind.
state_bind 0
state_release 0
check "release unbinds the bound slot" "-1" "${STATE_SLOT}"
check "release drops the data"         "1" \
    "$(declare -p RSTATE0_ROW_CREDIT >/dev/null 2>&1; printf '%d' "$?")"
check "release of an unknown slot is fine" "0" \
    "$(state_release 9; printf '%d' "$?")"
check "a bad slot number is refused" "1" \
    "$(state_new 'x[0]' 2>/dev/null; printf '%d' "$?")"

state_release_all
check "release_all leaves no slot" "0" "${#STATE_MADE[@]}"

# --- 3. Completeness against game_reset -----------------------------------
# The list in lib/state.sh and the reset in rowhammer.sh are two ends of
# the same statement about what a round is. This reads the assignments out
# of game_reset and insists that every one of them is accounted for.
log "${SCRIPT_NAME}: STATE_VARS against game_reset"

# Session state: assigned by game_reset but deliberately not part of a
# round (see the comment block in lib/state.sh). DIRTY is a redraw flag of
# the one screen the process has, not of a round - a playback of five
# rounds still draws one picture.
SESSION_VARS=(DIRTY)

if [ ! -r "${REPO_DIR}/rowhammer.sh" ]; then
    printf '%s: missing %s\n' "${SCRIPT_NAME}" "${REPO_DIR}/rowhammer.sh" >&2
    exit 1
fi

# The body of game_reset: from its opening line to the closing brace in
# column one. Assignments are read as NAME= at the start of a line, which
# is how every one of them is written there.
RESET_VARS="$(
    sed -n '/^game_reset() {$/,/^}$/p' "${REPO_DIR}/rowhammer.sh" \
        | sed -n 's/^[[:space:]]*\([A-Z_][A-Z0-9_]*\)=.*/\1/p' \
        | sort -u
)"
check "game_reset was found in rowhammer.sh" "0" \
    "$( [ -n "${RESET_VARS}" ]; printf '%d' "$?" )"

# The names lib/state.sh knows, as a lookup.
declare -A KNOWN=()
for entry in "${STATE_VARS[@]}"; do
    KNOWN["${entry#*:}"]=1
done
for name in "${SESSION_VARS[@]}"; do
    KNOWN["${name}"]=1
done

MISSING=""
while IFS= read -r name; do
    [ -n "${name}" ] || continue
    if [ -z "${KNOWN[${name}]+set}" ]; then
        MISSING+="${name} "
    fi
done <<< "${RESET_VARS}"
check "every game_reset variable is covered" "" "${MISSING% }"

# The reverse direction is not an error but is worth seeing: game_reset
# reaches several of these through helpers (board_init, update_speed,
# spawn_piece, play_clock_resume, time_attack_budget), so a name missing
# from its body is normal.
if [ "${VERBOSE}" -eq 1 ]; then
    for entry in "${STATE_VARS[@]}"; do
        name="${entry#*:}"
        if ! grep -q "^${name}$" <<< "${RESET_VARS}"; then
            vlog "note: ${name} is reset through a helper, not in game_reset itself"
        fi
    done
fi

# --- Result ---------------------------------------------------------------
if [ "${FAILURES}" -gt 0 ]; then
    printf '%s: %d failure(s) in %d checks\n' \
        "${SCRIPT_NAME}" "${FAILURES}" "${CHECKS}" >&2
    exit 1
fi
log "${SCRIPT_NAME}: ${CHECKS} checks, no failures"
exit 0
