#!/usr/bin/env bash
#
# tetris.sh
#
# Description:
#   Playable core of "rowhammer", a terminal Tetris game written in pure
#   bash, modeled after "The New Tetris" (N64). Phase 1 scope: 10x20
#   board, 7-bag randomizer, gravity with level-based speed, line
#   clearing, soft/hard drop, pause and game over with restart. The
#   square system (gold/silver), wonders and multiplayer follow in later
#   phases (see CLAUDE.md).
#
# Program flow:
#   1. Parse arguments and resolve configuration (CLI > env > default).
#   2. Verify prerequisites (bash >= 4, interactive terminal, size).
#   3. Source the library modules (pieces, board, input, render).
#   4. Enter the alternate screen and install the cleanup trap.
#   5. Run the game loop: read input, apply gravity, lock pieces, clear
#      lines, redraw only when the state changed.
#   6. On game over offer restart or quit; restore the terminal on exit
#      and print the final score.
#
# Usage:
#   tetris.sh [--seed N] [--no-color] [-h|--help]
#
# Version: 0.1.0  (2026-07-17)

set -euo pipefail

SCRIPT_NAME="$(basename -- "${0}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# --- Defaults seeded from environment variables ---------------------------
# Precedence: command-line argument > environment variable > built-in default.
SEED="${ROWHAMMER_SEED:-}"
NO_COLOR_OPT="${ROWHAMMER_NO_COLOR:-0}"

# Print usage information.
usage() {
    cat <<'EOF'
Usage: tetris.sh [OPTIONS]

Terminal Tetris - Phase 1 playable core of the rowhammer project.

Options:
  --seed N      Seed the piece randomizer for a reproducible sequence.
                Env: ROWHAMMER_SEED      Default: (random)
  --no-color    Disable ANSI colors; blocks are drawn as "[]".
                Env: ROWHAMMER_NO_COLOR  Default: 0
  -h, --help    Show this help and exit.

Controls:
  a / d or arrow left/right   move piece
  w or arrow up               rotate clockwise
  q                           rotate counter-clockwise
  s or arrow down             soft drop
  space                       hard drop
  p                           pause / resume
  x or ESC                    quit
  r                           restart (on the game over screen)

Precedence for every option: command-line argument > environment variable
> built-in default.

Example:
  tetris.sh --seed 42 --no-color
EOF
}

# die MESSAGE...
# Report an explicit failure to STDERR and exit non-zero. The game is
# purely interactive and never runs from cron/systemd, so per the script
# conventions the syslog/logger part is intentionally omitted.
die() {
    printf '%s: %s\n' "${SCRIPT_NAME}" "$*" >&2
    exit 1
}

# --- Argument parsing (highest precedence) --------------------------------
while [ "$#" -gt 0 ]; do
    case "${1}" in
        --seed)
            if [ "$#" -lt 2 ]; then
                printf '%s: option %s requires an argument\n' "${SCRIPT_NAME}" "${1}" >&2
                exit 2
            fi
            SEED="${2}"
            shift 2
            ;;
        --seed=*)
            SEED="${1#*=}"
            shift
            ;;
        --no-color)
            NO_COLOR_OPT=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            printf '%s: unknown option: %s\n' "${SCRIPT_NAME}" "${1}" >&2
            usage >&2
            exit 2
            ;;
    esac
done

# Validate option values before touching the terminal.
if [ -n "${SEED}" ] && ! [[ "${SEED}" =~ ^[0-9]+$ ]]; then
    printf '%s: --seed expects a non-negative integer, got: %s\n' \
        "${SCRIPT_NAME}" "${SEED}" >&2
    exit 2
fi
case "${NO_COLOR_OPT}" in
    0|1) : ;;
    *)
        printf '%s: ROWHAMMER_NO_COLOR expects 0 or 1, got: %s\n' \
            "${SCRIPT_NAME}" "${NO_COLOR_OPT}" >&2
        exit 2
        ;;
esac
USE_COLOR=$(( 1 - NO_COLOR_OPT ))

# --- Prerequisites --------------------------------------------------------
# Associative arrays (piece tables) and fractional read timeouts need
# bash 4; EPOCHREALTIME (bash 5) is optional and has a fallback.
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    die "bash >= 4.0 is required, this is bash ${BASH_VERSION}"
fi
if [ ! -t 0 ] || [ ! -t 1 ]; then
    die "This game needs an interactive terminal (stdin/stdout must be a tty)"
fi

# The layout needs room for the board plus sidebar: at least 48x24.
TERM_ROWS=0
TERM_COLS=0
read -r TERM_ROWS TERM_COLS < <(stty size)
if (( TERM_ROWS < 24 || TERM_COLS < 48 )); then
    die "Terminal too small: need at least 48x24, got ${TERM_COLS}x${TERM_ROWS}"
fi

# --- Library modules ------------------------------------------------------
for _lib in pieces board input render; do
    if [ ! -r "${SCRIPT_DIR}/lib/${_lib}.sh" ]; then
        die "Missing library file: ${SCRIPT_DIR}/lib/${_lib}.sh"
    fi
    # shellcheck source=/dev/null
    . "${SCRIPT_DIR}/lib/${_lib}.sh"
done
unset _lib

# Seeding RANDOM makes the 7-bag shuffle sequence reproducible.
if [ -n "${SEED}" ]; then
    RANDOM="${SEED}"
fi

# --- Game state and helpers -----------------------------------------------
CUR_TYPE=""; CUR_ROT=0; CUR_X=0; CUR_Y=0
SCORE=0; CLEARED_TOTAL=0; LEVEL=0; FALL_MS=800
PAUSED=0; GAME_OVER=0; QUIT=0; DIRTY=1
NOW_MS=0; LAST_FALL=0

# now_ms: put the current time in milliseconds into the global NOW_MS.
# Uses bash 5's EPOCHREALTIME when available (no fork); older bash falls
# back to date. A global instead of command substitution keeps the hot
# game loop free of subshell forks on bash 5.
now_ms() {
    if [ -n "${EPOCHREALTIME:-}" ]; then
        # Some locales print a decimal comma; normalize before splitting.
        local t="${EPOCHREALTIME/,/.}"
        local usec="${t#*.}"
        NOW_MS=$(( ${t%.*} * 1000 + 10#${usec:0:3} ))
    else
        NOW_MS=$(( $(date +%s%N) / 1000000 ))
    fi
}

# update_speed: derive level and gravity interval from total cleared
# lines. Values are provisional; the proper level curve is a Phase 2 task.
update_speed() {
    LEVEL=$(( CLEARED_TOTAL / 10 ))
    FALL_MS=$(( 800 - 70 * LEVEL ))
    if (( FALL_MS < 120 )); then
        FALL_MS=120
    fi
}

# spawn_piece: take the next piece from the bag and place it at the spawn
# position. A blocked spawn position means the stack reached the top.
spawn_piece() {
    bag_next
    CUR_TYPE="${NEXT_TYPE}"
    CUR_ROT=0
    CUR_X=3
    CUR_Y=0
    if ! can_place "${CUR_TYPE}" "${CUR_ROT}" "${CUR_X}" "${CUR_Y}"; then
        GAME_OVER=1
    fi
    DIRTY=1
}

# lock_and_next: lock the active piece, clear lines, update score/level
# and spawn the next piece. Scoring uses the classic 1/2/3/4-line values
# scaled by level; the full scoring system is refined in Phase 2.
lock_and_next() {
    lock_piece "${CUR_TYPE}" "${CUR_ROT}" "${CUR_X}" "${CUR_Y}"
    clear_lines
    if (( CLEARED > 0 )); then
        CLEARED_TOTAL=$(( CLEARED_TOTAL + CLEARED ))
        local points=0
        case "${CLEARED}" in
            1) points=100 ;;
            2) points=300 ;;
            3) points=500 ;;
            4) points=800 ;;
        esac
        SCORE=$(( SCORE + points * (LEVEL + 1) ))
        update_speed
    fi
    spawn_piece
    now_ms
    LAST_FALL="${NOW_MS}"
}

# try_move DX DY: move the piece if the target position is free.
try_move() {
    local nx=$(( CUR_X + ${1} )) ny=$(( CUR_Y + ${2} ))
    if can_place "${CUR_TYPE}" "${CUR_ROT}" "${nx}" "${ny}"; then
        CUR_X="${nx}"
        CUR_Y="${ny}"
        DIRTY=1
        return 0
    fi
    return 1
}

# try_rotate DIR (1 = clockwise, -1 = counter-clockwise)
# Rotation with simple wall kicks: try the rotated position in place,
# then shifted left/right by up to two columns (two for the I piece).
try_rotate() {
    local nrot=$(( (CUR_ROT + ${1} + 4) % 4 ))
    local kick
    for kick in 0 -1 1 -2 2; do
        if can_place "${CUR_TYPE}" "${nrot}" "$(( CUR_X + kick ))" "${CUR_Y}"; then
            CUR_ROT="${nrot}"
            CUR_X=$(( CUR_X + kick ))
            DIRTY=1
            return 0
        fi
    done
    return 1
}

# step_down: move the piece one row down; lock it when it cannot fall.
step_down() {
    if can_place "${CUR_TYPE}" "${CUR_ROT}" "${CUR_X}" "$(( CUR_Y + 1 ))"; then
        CUR_Y=$(( CUR_Y + 1 ))
        DIRTY=1
    else
        lock_and_next
    fi
    return 0
}

# hard_drop: drop the piece to the floor and lock it immediately. Two
# points per dropped row, like most guideline implementations.
hard_drop() {
    while can_place "${CUR_TYPE}" "${CUR_ROT}" "${CUR_X}" "$(( CUR_Y + 1 ))"; do
        CUR_Y=$(( CUR_Y + 1 ))
        SCORE=$(( SCORE + 2 ))
    done
    lock_and_next
    return 0
}

# handle_key: apply the key in the global KEY to the game state. Movement
# keys are ignored while paused or on the game over screen.
handle_key() {
    if [ -z "${KEY}" ]; then
        return 0
    fi
    if [ "${GAME_OVER}" -eq 1 ]; then
        case "${KEY}" in
            r)     game_reset ;;
            x|ESC) QUIT=1 ;;
        esac
        return 0
    fi
    case "${KEY}" in
        p)
            PAUSED=$(( 1 - PAUSED ))
            # Restart the gravity timer so a long pause is not counted
            # as elapsed fall time.
            now_ms
            LAST_FALL="${NOW_MS}"
            DIRTY=1
            ;;
        x|ESC)
            QUIT=1
            ;;
    esac
    if [ "${PAUSED}" -eq 1 ]; then
        return 0
    fi
    case "${KEY}" in
        LEFT|a)  try_move -1 0 || : ;;
        RIGHT|d) try_move 1 0 || : ;;
        UP|w)    try_rotate 1 || : ;;
        q)       try_rotate -1 || : ;;
        DOWN|s)
            # Soft drop: one point per manually dropped row.
            if can_place "${CUR_TYPE}" "${CUR_ROT}" "${CUR_X}" "$(( CUR_Y + 1 ))"; then
                SCORE=$(( SCORE + 1 ))
            fi
            step_down
            now_ms
            LAST_FALL="${NOW_MS}"
            ;;
        SPACE)
            hard_drop
            ;;
    esac
    return 0
}

# game_reset: start a fresh round (used at launch and for restart).
game_reset() {
    board_init
    BAG=()
    SCORE=0
    CLEARED_TOTAL=0
    PAUSED=0
    GAME_OVER=0
    update_speed
    spawn_piece
    now_ms
    LAST_FALL="${NOW_MS}"
    DIRTY=1
}

# --- Main loop ------------------------------------------------------------
main() {
    # Restore the terminal on any exit path, including Ctrl-C.
    trap term_restore EXIT
    trap 'exit 130' INT TERM
    term_setup
    game_reset

    while [ "${QUIT}" -eq 0 ]; do
        # read_key also paces the loop via its TICK_S timeout.
        read_key
        handle_key
        if [ "${PAUSED}" -eq 0 ] && [ "${GAME_OVER}" -eq 0 ]; then
            now_ms
            if (( NOW_MS - LAST_FALL >= FALL_MS )); then
                LAST_FALL="${NOW_MS}"
                step_down
            fi
        fi
        if [ "${DIRTY}" -eq 1 ]; then
            draw_frame
            DIRTY=0
        fi
    done

    # Leave the alternate screen before printing the summary so it ends
    # up in the normal scrollback.
    term_restore
    printf 'Final score: %s (lines: %s, level: %s)\n' \
        "${SCORE}" "${CLEARED_TOTAL}" "${LEVEL}"
}

main "$@"
