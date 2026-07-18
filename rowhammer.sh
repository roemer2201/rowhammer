#!/usr/bin/env bash
#
# rowhammer.sh
#
# Description:
#   "rowhammer", a terminal Tetris game written in pure bash, modeled
#   after "The New Tetris" (N64). Starts with a menu (singleplayer,
#   multiplayer placeholder, settings); the game offers a 10x20 board,
#   7-bag randomizer with a 3-piece preview, a hold slot, gravity with a
#   level-based speed curve, soft/hard drop, pause and game over with
#   restart. The New Tetris square mechanics are in: 4x4 squares built
#   from four complete pieces turn gold (mono) or silver (multi) and make
#   cleared rows worth bonus row credit (the "Rows" counter, which will
#   build the wonders in Phase 3). Player name and key bindings are
#   configurable in the settings menu and persisted to a user config
#   file. Wonders and a working multiplayer follow in later phases
#   (see CLAUDE.md).
#
# Program flow:
#   1. Parse arguments (kept aside until the config file is loaded).
#   2. Verify prerequisites (bash >= 4, interactive terminal, size).
#   3. Source the library modules (config, pieces, board, squares,
#      input, render, menu).
#   4. Resolve settings with precedence default < config file < env <
#      CLI and validate them.
#   5. Enter the alternate screen and install the cleanup trap.
#   6. Run the main menu loop; "Einzelspieler" starts the game loop
#      (input, gravity, locking, square detection, line clearing,
#      rendering), settings changes are written back to the config file.
#   7. Restore the terminal on exit.
#
# Usage:
#   rowhammer.sh [--seed N] [--name NAME] [--no-color] [-h|--help]
#
# Version: 0.4.0  (2026-07-18)

set -euo pipefail

SCRIPT_NAME="$(basename -- "${0}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# --- Built-in defaults ----------------------------------------------------
# Full precedence: command-line argument > environment variable > config
# file > built-in default. SEED and NO_COLOR are not part of the config
# file, so they take their env fallback directly; the config-driven
# settings (player name, key bindings) start from these defaults, get
# overridden by config_load and the env/CLI blocks after sourcing below.
SEED="${ROWHAMMER_SEED:-}"
NO_COLOR_OPT="${ROWHAMMER_NO_COLOR:-0}"
PLAYER_NAME="Player"
KEY_LEFT="a"
KEY_RIGHT="d"
KEY_ROT_CW="w"
KEY_ROT_CCW="q"
KEY_SOFT="s"
KEY_HARD="SPACE"
KEY_PAUSE="p"
KEY_QUIT="x"
KEY_HOLD="c"
# CLI values are parked here and applied after config_load so the
# command line keeps the highest precedence.
CLI_PLAYER_NAME=""

# Print usage information.
usage() {
    cat <<'EOF'
Usage: rowhammer.sh [OPTIONS]

Terminal Tetris of the rowhammer project. Starts with a menu:
singleplayer, multiplayer (placeholder) and settings.

Options:
  --seed N      Seed the piece randomizer for a reproducible sequence.
                Env: ROWHAMMER_SEED         Default: (random)
  --name NAME   Player name shown in the HUD (max. 16 characters from
                A-Z a-z 0-9 space _ -).
                Env: ROWHAMMER_PLAYER_NAME  Default: Player
  --no-color    Disable ANSI colors; blocks are drawn as "[]".
                Env: ROWHAMMER_NO_COLOR     Default: 0
  -h, --help    Show this help and exit.

Controls (defaults; rebindable in the settings menu):
  a / d or arrow left/right   move piece
  w or arrow up               rotate clockwise
  q                           rotate counter-clockwise
  s or arrow down             soft drop
  space                       hard drop
  c                           hold / swap piece (once per piece)
  p                           pause / resume
  x or ESC                    back to the menu
  r                           restart (on the game over screen)

Square mechanics (The New Tetris): fill a 4x4 area with exactly four
complete, uncut pieces to form a square - gold if all four are the same
type, silver if mixed. Every cleared row is worth 1 row of credit, plus
10 per gold square and 5 per silver square it runs through (additive);
clearing 4 rows at once (a Tetris) adds 1 extra. The credit is shown as
"Rows" in the HUD and will build the wonders in Phase 3.

Settings (player name, key bindings) are stored in a config file, by
default ~/.config/rowhammer.conf (organization-based lookup, see the
script conventions and CLAUDE.md). Key bindings can also be overridden
via environment variables ROWHAMMER_KEY_LEFT, ROWHAMMER_KEY_RIGHT,
ROWHAMMER_KEY_ROT_CW, ROWHAMMER_KEY_ROT_CCW, ROWHAMMER_KEY_SOFT,
ROWHAMMER_KEY_HARD, ROWHAMMER_KEY_PAUSE, ROWHAMMER_KEY_QUIT,
ROWHAMMER_KEY_HOLD (single characters a-z or 0-9, or the word SPACE).

Precedence for every option: command-line argument > environment variable
> config file > built-in default.

Example:
  rowhammer.sh --seed 42 --name Alice --no-color
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
        --name)
            if [ "$#" -lt 2 ]; then
                printf '%s: option %s requires an argument\n' "${SCRIPT_NAME}" "${1}" >&2
                exit 2
            fi
            CLI_PLAYER_NAME="${2}"
            shift 2
            ;;
        --name=*)
            CLI_PLAYER_NAME="${1#*=}"
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
for _lib in config pieces board squares input render menu; do
    if [ ! -r "${SCRIPT_DIR}/lib/${_lib}.sh" ]; then
        die "Missing library file: ${SCRIPT_DIR}/lib/${_lib}.sh"
    fi
    # shellcheck source=/dev/null
    . "${SCRIPT_DIR}/lib/${_lib}.sh"
done
unset _lib

# --- Settings resolution (default < config < env < CLI) -------------------
# The config file may override the built-in defaults above.
config_load

# Environment variables override the config file.
PLAYER_NAME="${ROWHAMMER_PLAYER_NAME:-${PLAYER_NAME}}"
KEY_LEFT="${ROWHAMMER_KEY_LEFT:-${KEY_LEFT}}"
KEY_RIGHT="${ROWHAMMER_KEY_RIGHT:-${KEY_RIGHT}}"
KEY_ROT_CW="${ROWHAMMER_KEY_ROT_CW:-${KEY_ROT_CW}}"
KEY_ROT_CCW="${ROWHAMMER_KEY_ROT_CCW:-${KEY_ROT_CCW}}"
KEY_SOFT="${ROWHAMMER_KEY_SOFT:-${KEY_SOFT}}"
KEY_HARD="${ROWHAMMER_KEY_HARD:-${KEY_HARD}}"
KEY_PAUSE="${ROWHAMMER_KEY_PAUSE:-${KEY_PAUSE}}"
KEY_QUIT="${ROWHAMMER_KEY_QUIT:-${KEY_QUIT}}"
KEY_HOLD="${ROWHAMMER_KEY_HOLD:-${KEY_HOLD}}"

# The command line has the final say.
if [ -n "${CLI_PLAYER_NAME}" ]; then
    PLAYER_NAME="${CLI_PLAYER_NAME}"
fi

# Validate the resolved settings; the config file and env vars are user
# input too. The name charset also keeps the sourced config file safe
# (no quotes or expansions can sneak into it).
_name_re='^[A-Za-z0-9_ -]{1,16}$'
if ! [[ "${PLAYER_NAME}" =~ ${_name_re} ]]; then
    die "Invalid player name: '${PLAYER_NAME}' (allowed: max. 16 characters from A-Z a-z 0-9 space _ -)"
fi
_key_re='^([a-z0-9]|SPACE)$'
for _var in "${KEY_ACTIONS[@]}"; do
    if ! [[ "${!_var}" =~ ${_key_re} ]]; then
        die "Invalid key binding ${_var}='${!_var}' (allowed: a-z, 0-9 or SPACE)"
    fi
    for _other in "${KEY_ACTIONS[@]}"; do
        if [ "${_var}" != "${_other}" ] && [ "${!_var}" = "${!_other}" ]; then
            die "Key bindings ${_var} and ${_other} both use '${!_var}'"
        fi
    done
done
unset _name_re _key_re _var _other

# Seeding RANDOM makes the 7-bag shuffle sequence reproducible.
if [ -n "${SEED}" ]; then
    RANDOM="${SEED}"
fi

# --- Game state and helpers -----------------------------------------------
CUR_TYPE=""; CUR_ROT=0; CUR_X=0; CUR_Y=0
SCORE=0; CLEARED_TOTAL=0; ROW_CREDIT=0; LEVEL=0; FALL_MS=800
GOLD_COUNT=0; SILVER_COUNT=0; NEXT_INSTANCE_ID=1
HOLD_TYPE=""; HOLD_USED=0
PAUSED=0; GAME_OVER=0; GAME_EXIT=0; DIRTY=1
NOW_MS=0; LAST_FALL=0

# Scoring values (adjustable; the detailed system incl. combos is a later
# roadmap item). Line points scale with (level + 1); squares pay a flat
# formation bonus on top of the row credit they earn when cleared.
SCORE_LINES=(0 100 300 500 800)
SCORE_SQUARE_GOLD=2000
SCORE_SQUARE_SILVER=1000

# Gravity interval per level in milliseconds. A lookup table instead of a
# formula so the curve stays easy to tune; the last entry is the cap.
LEVEL_SPEEDS=(800 720 640 560 480 410 350 300 260 220 190 160 140 120)

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

# update_speed: derive level and gravity interval from the physical lines
# cleared this round (one level per 10 lines, speed from LEVEL_SPEEDS).
update_speed() {
    LEVEL=$(( CLEARED_TOTAL / 10 ))
    local idx="${LEVEL}"
    local max=$(( ${#LEVEL_SPEEDS[@]} - 1 ))
    if (( idx > max )); then
        idx="${max}"
    fi
    FALL_MS="${LEVEL_SPEEDS[idx]}"
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

# lock_and_next: lock the active piece, detect squares, clear lines,
# update score/credit/level and spawn the next piece. Square detection
# runs before line clearing on purpose: a piece that completes a square
# and a row at once still forms the square first, so the cleared row
# already earns the square's bonus credit.
lock_and_next() {
    lock_piece "${CUR_TYPE}" "${CUR_ROT}" "${CUR_X}" "${CUR_Y}"
    if detect_square "${CUR_X}" "${CUR_Y}"; then
        if [ "${SQUARE_RESULT}" = "G" ]; then
            GOLD_COUNT=$(( GOLD_COUNT + 1 ))
            SCORE=$(( SCORE + SCORE_SQUARE_GOLD ))
        else
            SILVER_COUNT=$(( SILVER_COUNT + 1 ))
            SCORE=$(( SCORE + SCORE_SQUARE_SILVER ))
        fi
    fi
    clear_lines
    if (( CLEARED > 0 )); then
        CLEARED_TOTAL=$(( CLEARED_TOTAL + CLEARED ))
        ROW_CREDIT=$(( ROW_CREDIT + CLEARED_CREDIT ))
        SCORE=$(( SCORE + SCORE_LINES[CLEARED] * (LEVEL + 1) ))
        update_speed
    fi
    # The hold slot unlocks again once a piece has locked.
    HOLD_USED=0
    spawn_piece
    now_ms
    LAST_FALL="${NOW_MS}"
}

# hold_piece: stash the active piece (first use) or swap it with the held
# one - at most once per piece. The swap is refused instead of forcing a
# game over when the incoming piece has no room at the spawn position.
hold_piece() {
    if [ "${HOLD_USED}" -eq 1 ]; then
        return 0
    fi
    if [ -z "${HOLD_TYPE}" ]; then
        queue_fill
        if ! can_place "${QUEUE[0]}" 0 3 0; then
            return 0
        fi
        HOLD_TYPE="${CUR_TYPE}"
        HOLD_USED=1
        spawn_piece
    else
        if ! can_place "${HOLD_TYPE}" 0 3 0; then
            return 0
        fi
        local tmp="${HOLD_TYPE}"
        HOLD_TYPE="${CUR_TYPE}"
        CUR_TYPE="${tmp}"
        CUR_ROT=0
        CUR_X=3
        CUR_Y=0
        HOLD_USED=1
        DIRTY=1
    fi
    now_ms
    LAST_FALL="${NOW_MS}"
    return 0
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
# keys are ignored while paused or on the game over screen. Letter keys
# come from the configurable bindings; the arrow keys are always active
# as a fixed secondary layout.
handle_key() {
    if [ -z "${KEY}" ]; then
        return 0
    fi
    if [ "${GAME_OVER}" -eq 1 ]; then
        case "${KEY}" in
            r)                  game_reset ;;
            "${KEY_QUIT}"|ESC)  GAME_EXIT=1 ;;
        esac
        return 0
    fi
    case "${KEY}" in
        "${KEY_PAUSE}")
            PAUSED=$(( 1 - PAUSED ))
            # Restart the gravity timer so a long pause is not counted
            # as elapsed fall time.
            now_ms
            LAST_FALL="${NOW_MS}"
            DIRTY=1
            ;;
        "${KEY_QUIT}"|ESC)
            GAME_EXIT=1
            ;;
    esac
    if [ "${PAUSED}" -eq 1 ]; then
        return 0
    fi
    case "${KEY}" in
        LEFT|"${KEY_LEFT}")   try_move -1 0 || : ;;
        RIGHT|"${KEY_RIGHT}") try_move 1 0 || : ;;
        UP|"${KEY_ROT_CW}")   try_rotate 1 || : ;;
        "${KEY_ROT_CCW}")     try_rotate -1 || : ;;
        DOWN|"${KEY_SOFT}")
            # Soft drop: one point per manually dropped row.
            if can_place "${CUR_TYPE}" "${CUR_ROT}" "${CUR_X}" "$(( CUR_Y + 1 ))"; then
                SCORE=$(( SCORE + 1 ))
            fi
            step_down
            now_ms
            LAST_FALL="${NOW_MS}"
            ;;
        "${KEY_HARD}")
            hard_drop
            ;;
        "${KEY_HOLD}")
            hold_piece
            ;;
    esac
    return 0
}

# game_reset: start a fresh round (used at launch and for restart).
game_reset() {
    board_init
    BAG=()
    QUEUE=()
    INSTANCE_CUT=()
    INSTANCE_SQUARED=()
    NEXT_INSTANCE_ID=1
    SCORE=0
    CLEARED_TOTAL=0
    ROW_CREDIT=0
    GOLD_COUNT=0
    SILVER_COUNT=0
    HOLD_TYPE=""
    HOLD_USED=0
    PAUSED=0
    GAME_OVER=0
    update_speed
    spawn_piece
    now_ms
    LAST_FALL="${NOW_MS}"
    DIRTY=1
}

# --- Game loop ------------------------------------------------------------
# game_run: one complete game session; returns to the caller (the menu)
# when the player leaves via the quit key or the game over screen.
game_run() {
    GAME_EXIT=0
    game_reset

    while [ "${GAME_EXIT}" -eq 0 ]; do
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
    return 0
}

# --- Main menu loop -------------------------------------------------------
main() {
    # Restore the terminal on any exit path, including Ctrl-C.
    trap term_restore EXIT
    trap 'exit 130' INT TERM
    term_setup

    while :; do
        menu_run "R O W H A M M E R" \
            "Einzelspieler" \
            "Mehrspieler" \
            "Einstellungen" \
            "Beenden"
        case "${MENU_CHOICE}" in
            0)
                menu_singleplayer
                ;;
            1)
                # Placeholder until the multiplayer phase (see CLAUDE.md).
                menu_message "Mehrspieler" \
                    "Der Mehrspieler-Modus ist noch nicht verfuegbar." \
                    "Er folgt in einer spaeteren Phase (siehe Roadmap)."
                ;;
            2)
                menu_settings
                ;;
            *)
                # "Beenden" or ESC on the top level leaves the game.
                break
                ;;
        esac
    done

    term_restore
}

main "$@"
