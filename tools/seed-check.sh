#!/usr/bin/env bash
#
# tools/seed-check.sh
#
# Description:
#   Regression test for the piece sequence (lib/pieces.sh): a seed has to
#   give the same pieces on every bash the game runs on. That is what
#   "--seed N" promises and what a multiplayer round stands on - every
#   participant gets the hub's SEED and has to draw the same bags from it
#   (CLAUDE.md 3.1 and 5.1).
#   Until 2.1.1 the shuffle drew from bash's RANDOM, and the generator
#   behind RANDOM is a different one in bash 4.3/4.4, in 5.0 and from 5.1
#   on (issue #115): mixed shells in one session played different pieces
#   and nothing on screen said so. The bag has a generator of its own
#   since then (bag_seed, bag_rand), which reproduces the one of bash 5.1
#   and later in shell arithmetic. This test holds it to that:
#     1. Fixed vectors. The numbers and the piece sequences for a handful
#        of seeds are written down here, taken from the RANDOM of a bash
#        5.2 before the change. They have to come out on whatever bash
#        runs this file - which is the whole point, so the CI runs it on
#        bash 4.3 to 5.3.
#     2. The original. On a bash that has the generator being reproduced
#        (5.1 or later, no compatibility level set) every draw is
#        compared with RANDOM itself, over many seeds.
#     3. Independence. Drawing from RANDOM must not move the piece
#        sequence and drawing pieces must not move RANDOM - the fault the
#        test bot had in 2.0.2, when both were one stream.
#   Headless by design, like tools/state-check.sh: it sources the module,
#   never starts the game and needs no terminal. It uses shell builtins
#   only, because the containers of the old bash releases it runs in are
#   minimal ones.
#
# Program flow:
#   1. Parse arguments and resolve the repository root.
#   2. Source lib/pieces.sh with the two hooks of the game it calls
#      stubbed out.
#   3. Generator: fixed numbers per seed, the rule against a repeated
#      value, the spelling of a seed (leading zeros).
#   4. Piece sequence: fixed sequences per seed through the game's own
#      queue, and the make-up of a bag.
#   5. Independence of RANDOM and the piece sequence, both ways.
#   6. Comparison with RANDOM where the shell has the same generator.
#   7. Report the number of checks and exit non-zero on any failure.
#
# Usage:
#   seed-check.sh [-v|--verbose] [-s|--silent] [-h|--help]
#
# Version: 1.0.0  (2026-11-09)

set -euo pipefail

# Builtins only (see the description): no basename, dirname or readlink.
SCRIPT_NAME="${0##*/}"
case "${BASH_SOURCE[0]}" in
    */*) SCRIPT_DIR="${BASH_SOURCE[0]%/*}" ;;
    *)   SCRIPT_DIR="." ;;
esac
REPO_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

# --- Defaults seeded from environment variables ---------------------------
# Precedence: command-line argument > environment variable > default.
VERBOSE="${ROWHAMMER_SEEDCHECK_VERBOSE:-0}"
SILENT="${ROWHAMMER_SEEDCHECK_SILENT:-0}"

usage() {
    cat <<'EOF'
Usage: seed-check.sh [OPTIONS]

Check the piece sequence (lib/pieces.sh): a seed must give the same
pieces on every bash version. Run it with the bash to be checked, e.g.
"bash-4.4 tools/seed-check.sh".

Options:
  -v, --verbose    Print every check as it runs.
                   Env: ROWHAMMER_SEEDCHECK_VERBOSE  Default: 0
  -s, --silent     Print errors only.
                   Env: ROWHAMMER_SEEDCHECK_SILENT   Default: 0
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
# lib/pieces.sh talks to two other modules: it logs a bag refill
# (debug_event, lib/debug.sh) and queue_fill reports to and reads from the
# demo layer (lib/demo.sh). Neither belongs to what is tested here, so the
# flag is off and both are stubs - the same three lines
# tools/demo/probe_pieces.sh uses.
if [ ! -r "${REPO_DIR}/lib/pieces.sh" ]; then
    printf '%s: missing library file: %s\n' \
        "${SCRIPT_NAME}" "${REPO_DIR}/lib/pieces.sh" >&2
    exit 1
fi
debug_event() { :; }
demo_record_piece() { :; }
DEMO_PLAYING=0
# shellcheck source=/dev/null
. "${REPO_DIR}/lib/pieces.sh"

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

# draws SEED FIRST LAST
# The numbers FIRST..LAST (counted from 1) the generator hands out after
# seed SEED, space separated, into DRAWS.
DRAWS=""
draws() {
    local k
    DRAWS=""
    bag_seed "${1}"
    for (( k = 1; k <= ${3}; k++ )); do
        bag_rand
        if [ "${k}" -ge "${2}" ]; then
            DRAWS+="${DRAWS:+ }${BAG_RAND}"
        fi
    done
    return 0
}

# stream SEED COUNT
# The first COUNT pieces of seed SEED as one word into STREAM, drawn the
# way a round draws them: an empty bag and queue (game_reset) and then
# bag_next piece by piece, so the preview queue is part of what is tested.
STREAM=""
stream() {
    local k
    STREAM=""
    bag_seed "${1}"
    BAG=()
    QUEUE=()
    NEXT_TYPE=""
    for (( k = 0; k < ${2}; k++ )); do
        bag_next
        STREAM+="${NEXT_TYPE}"
    done
    return 0
}

# --- 1. The generator: fixed numbers --------------------------------------
# The first eight numbers per seed, as bash 5.2 gives them for
# "RANDOM=<seed>". Seed 0 is in the list for the state the generator may
# not have (it is replaced by 123459876), 999999999 as the largest seed
# the game accepts.
draws 0 1 8
check "numbers of seed 0" \
    "20814 24386 149 25587 12277 14239 29607 30583" "${DRAWS}"
draws 1 1 8
check "numbers of seed 1" \
    "16807 10791 19566 13983 29619 18126 2269 24347" "${DRAWS}"
draws 12345 1 8
check "numbers of seed 12345" \
    "25202 15552 10638 12271 21721 18331 12889 12436" "${DRAWS}"
draws 999999999 1 8
check "numbers of seed 999999999" \
    "3496 3062 5199 12951 19986 3954 11358 4366" "${DRAWS}"

# The rule against a repeated value. Seed 3 is the smallest seed that
# meets it inside one bag: its 62nd step gives 24547 again, which is
# thrown away, and 22257 is handed out instead. A generator without the
# rule passes every vector above and still deals a different second bag.
draws 3 59 66
check "seed 3 skips the repeated value at draw 62" \
    "5682 8308 24547 22257 19546 10083 24575 30688" "${DRAWS}"

# The spelling of a seed. Bash reads a leading zero as octal wherever a
# number is evaluated; bag_seed must not (010 is ten, 08 is eight and not
# an error).
draws 10 1 4
WANT="${DRAWS}"
draws 010 1 4
check "seed 010 is seed 10" "${WANT}" "${DRAWS}"
draws 8 1 4
WANT="${DRAWS}"
draws 08 1 4
check "seed 08 is seed 8" "${WANT}" "${DRAWS}"
draws 0 1 4
WANT="${DRAWS}"
draws 000000000 1 4
check "seed 000000000 is seed 0" "${WANT}" "${DRAWS}"

# --- 2. The piece sequence: fixed sequences -------------------------------
# Two full bags (126 pieces) for seed 1 and seed 3, so the second shuffle
# is covered: it starts from wherever the first one left the generator.
# Seed 3 is the one whose repeated value falls on the last draw of the
# first bag (see above). The shorter ones are the two seeds of the table
# in issue #115 and the ends of the range.
stream 1 126
check "pieces of seed 1 (two bags)" \
    "TTOZOSILSTISTZOTTZZIOLTJIZLLJIZOIOLSJIJLSSSLILZJJJTJSLOOZTOJZSIJJTJZSIOZSOITIILJSJLIOOLJZLTZTLZJTZLJTTSSZOLLOJSZIOLSIISZOOSTTI" \
    "${STREAM}"
stream 3 126
check "pieces of seed 3 (two bags)" \
    "JITISJJZTOOOZLTTLLLSSILSJLOJITOTOLJLZZOTTZZISSTSOZZSSJJOIJIIZILJILJZZSOSIZOZZOLTIJTSLSIIZILOSJOIJLTSTLSTOTZTIOTJJOSJJOLSLLIZZT" \
    "${STREAM}"
stream 12345 40
check "pieces of seed 12345" \
    "JILTISJOOTIJILJZLIZLSIZZOTLTOTZZOOSZOLIO" "${STREAM}"
stream 0 40
check "pieces of seed 0" \
    "JISJZZOSSOTOTOZLLTLOIOTSOTLTSIIJSJZZJIOT" "${STREAM}"
stream 999999999 40
check "pieces of seed 999999999" \
    "OILLSSOILZJJTZTOTJLSOZTSILOZOZITLJILISOL" "${STREAM}"

# The make-up of a bag: BAG_SETS complete sets, so every type comes up
# equally often over a full bag (CLAUDE.md 3.1). Checked on three bags in
# a row, drawn by bag_refill itself.
bag_seed 12345
for bag_no in 1 2 3; do
    bag_refill
    check "bag ${bag_no} holds $(( BAG_SETS * ${#PIECE_TYPES[@]} )) pieces" \
        "$(( BAG_SETS * ${#PIECE_TYPES[@]} ))" "${#BAG[@]}"
    declare -A COUNT=()
    for piece in "${BAG[@]}"; do
        COUNT["${piece}"]=$(( ${COUNT[${piece}]:-0} + 1 ))
    done
    UNEVEN=""
    for piece in "${PIECE_TYPES[@]}"; do
        if [ "${COUNT[${piece}]:-0}" -ne "${BAG_SETS}" ]; then
            UNEVEN+="${piece}=${COUNT[${piece}]:-0} "
        fi
    done
    check "bag ${bag_no} holds every type ${BAG_SETS} times" "" "${UNEVEN% }"
    unset COUNT
done

# --- 3. Independence of RANDOM and the piece sequence ---------------------
# Both directions. A draw from RANDOM between two pieces must leave the
# sequence alone (the test bot of 2.0.2 chose its moves from RANDOM and
# played other pieces than everybody else from the second bag on), and
# drawing pieces must leave RANDOM alone (the gap column of the
# Hochwasser mode and the hub's garbage come from it).
stream 1 126
WANT="${STREAM}"
STREAM=""
bag_seed 1
BAG=()
QUEUE=()
for (( n = 0; n < 126; n++ )); do
    bag_next
    STREAM+="${NEXT_TYPE}"
    : "${RANDOM}" "${RANDOM}"
done
check "draws from RANDOM do not move the piece sequence" \
    "${WANT}" "${STREAM}"

RANDOM=4711
WANT="${RANDOM} ${RANDOM} ${RANDOM} ${RANDOM}"
RANDOM=4711
GOT="${RANDOM} ${RANDOM}"
stream 1 126
GOT+=" ${RANDOM} ${RANDOM}"
check "drawing pieces does not move RANDOM" "${WANT}" "${GOT}"

# --- 4. The original: RANDOM itself ---------------------------------------
# Only where the shell has the generator that is reproduced: bash 5.1 or
# later, and no compatibility level in force (BASH_COMPAT of 50 or lower
# switches RANDOM back to the 5.0 generator). The seeds are spread over
# the whole range the game accepts by a fixed rule, so a failure names a
# seed that fails again.
if [ "$(( BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] ))" -ge 501 ] \
   && [ -z "${BASH_COMPAT:-}" ]; then
    MISMATCH=""
    for (( n = 0; n < 150; n++ )); do
        seed=$(( (n * 2654435761 + n) % 1000000000 ))
        RANDOM="${seed}"
        WANT=""
        for (( k = 0; k < 250; k++ )); do
            WANT+="${RANDOM} "
        done
        draws "${seed}" 1 250
        if [ "${WANT% }" != "${DRAWS}" ]; then
            MISMATCH+="${seed} "
        fi
    done
    check "150 seeds match the RANDOM of bash ${BASH_VERSION}" \
        "" "${MISMATCH% }"
else
    log "${SCRIPT_NAME}: comparison with RANDOM skipped (bash ${BASH_VERSION}${BASH_COMPAT:+, BASH_COMPAT=${BASH_COMPAT}} has another generator)"
fi

# --- Result ---------------------------------------------------------------
if [ "${FAILURES}" -gt 0 ]; then
    printf '%s: %d failure(s) in %d checks on bash %s\n' \
        "${SCRIPT_NAME}" "${FAILURES}" "${CHECKS}" "${BASH_VERSION}" >&2
    exit 1
fi
log "${SCRIPT_NAME}: ${CHECKS} checks on bash ${BASH_VERSION}, no failures"
exit 0
