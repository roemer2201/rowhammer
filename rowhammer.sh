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
#   cleared rows worth bonus row credit (the "Rows" counter). That credit
#   accumulates across all rounds in a savegame and builds the seven
#   world wonders of the Wonders mode: the current wonder rises as ASCII
#   art, revealed bottom-up with every invested row, shown live in the
#   HUD, after every round and via the "Weltwunder" main menu entry.
#   Player name and key bindings are
#   configurable in the settings menu and persisted to a user config
#   file. Blocks render in the basic 8/16-color ANSI palette or, when
#   the terminal supports it (auto-detected, overridable via
#   --color-mode), in an extended xterm 256-color palette. All game data (config, persistent top-10 highscore list,
#   the savegame and the all-time statistics) lives in one data
#   directory, by default
#   ~/rowhammer. Finished rounds enter the highscore list, which the
#   main menu shows and whose rank appears on the game over screen.
#   Every round also feeds persistent statistics (cleared rows, bonus
#   rows, gold/silver squares built), shown via the "Statistik" main
#   menu entry.
#   A debug mode (--debug) traces the whole session into log
#   files: every screen update 1:1, every key press and every game
#   action (see lib/debug.sh). A working multiplayer follows
#   in a later phase (see CLAUDE.md).
#
# Program flow:
#   1. Parse arguments (kept aside until the config file is loaded).
#   2. Verify prerequisites (bash >= 4, interactive terminal, size).
#   3. Source the library modules (debug, config, pieces, board,
#      squares, highscore, save, stats, wonders, input, render, menu).
#   4. Resolve settings with precedence default < config file < env <
#      CLI and validate them.
#   5. Install the cleanup trap, start the debug logs (when --debug is
#      set), load the highscore list, the savegame and the statistics
#      and enter the alternate screen.
#   6. Run the main menu loop; "Einzelspieler" starts the game loop
#      (input, gravity, locking, square detection, line clearing,
#      rendering), finished rounds are recorded in the highscore list,
#      their row credit is banked into the wonder savegame and their
#      counters into the statistics file,
#      settings changes are written back to the config file.
#   7. Restore the terminal on exit and close the debug logs.
#
# Usage:
#   rowhammer.sh [--seed N] [--name NAME] [--data-dir DIR] [--no-color]
#                [--color-mode auto|basic|extended] [--debug]
#                [--debug-dir DIR] [-h|--help]
#
# Version: 0.10.0  (2026-07-19)

set -euo pipefail

SCRIPT_NAME="$(basename -- "${0}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Game version, reported in the debug session header. Keep in sync with
# the Version field in the header comment above.
ROWHAMMER_VERSION="0.10.0"

# --- Built-in defaults ----------------------------------------------------
# Full precedence: command-line argument > environment variable > config
# file > built-in default. SEED, NO_COLOR and the debug switches are not
# part of the config file, so they take their env fallback directly; the
# config-driven settings (player name, key bindings) start from these
# defaults, get overridden by config_load and the env/CLI blocks after
# sourcing below.
SEED="${ROWHAMMER_SEED:-}"
NO_COLOR_OPT="${ROWHAMMER_NO_COLOR:-0}"
# Color mode: auto probes the terminal for 256-color support and picks
# extended or basic accordingly (color_mode_resolve, lib/render.sh);
# basic/extended force the respective palette. --no-color disables
# colors entirely and makes the mode irrelevant.
COLOR_MODE="${ROWHAMMER_COLOR_MODE:-auto}"
DEBUG_OPT="${ROWHAMMER_DEBUG:-0}"
DEBUG_DIR="${ROWHAMMER_DEBUG_DIR:-}"
# Data directory for everything the game persists (rowhammer.conf,
# highscore, later the savegame). Not part of the config file itself,
# because the config file lives inside it; precedence is therefore
# default < env < CLI like the debug switches.
DATA_DIR="${ROWHAMMER_DATA_DIR:-${HOME}/rowhammer}"
PLAYER_NAME="Player"
KEY_LEFT="a"
KEY_RIGHT="d"
KEY_ROT_CW="e"
KEY_ROT_CCW="q"
KEY_SOFT="s"
KEY_HARD="w"
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
singleplayer, multiplayer (placeholder), highscores, wonders,
statistics and settings.

Options:
  --seed N      Seed the piece randomizer for a reproducible sequence.
                Env: ROWHAMMER_SEED         Default: (random)
  --name NAME   Player name shown in the HUD (max. 16 characters from
                A-Z a-z 0-9 space _ -).
                Env: ROWHAMMER_PLAYER_NAME  Default: Player
  --data-dir DIR
                Directory for all persistent game data: the config file
                rowhammer.conf, the highscore list, the savegame and
                the statistics file.
                Env: ROWHAMMER_DATA_DIR     Default: ~/rowhammer
  --no-color    Disable ANSI colors; blocks are drawn as "[]".
                Overrides --color-mode.
                Env: ROWHAMMER_NO_COLOR     Default: 0
  --color-mode MODE
                Color palette: "auto" detects 256-color support (tput
                colors, TERM, COLORTERM) and picks extended or basic;
                "basic" forces the 8/16-color ANSI palette; "extended"
                forces the xterm 256-color palette (guideline piece
                colors incl. a real orange L, richer gold/silver).
                Env: ROWHAMMER_COLOR_MODE   Default: auto
  --debug       Enable the debug/trace mode: the session is recorded
                into log files (see below). Logs can grow to several
                megabytes in long sessions.
                Env: ROWHAMMER_DEBUG        Default: 0
  --debug-dir DIR
                Directory for the debug logs of this run.
                Env: ROWHAMMER_DEBUG_DIR
                Default: ~/.local/state/rowhammer/debug/<timestamp>.<pid>
  -h, --help    Show this help and exit.

Debug mode writes three correlated log files (shared millisecond
timestamps and a screen update counter) meant to make bug reports
reproducible:
  events.log    session header (version, terminal, seed, key bindings,
                config files) and every game action: spawns, moves and
                rotations (including blocked ones), falls, locks, square
                formation, line clears with credit details, hold, pause,
                menu choices, config saves and a board snapshot after
                every lock.
  input.log     every key press, raw bytes and mapped symbol.
  frames.log    every screen update byte for byte (1:1, ANSI included).
The log directory is printed when the game exits.

Controls (defaults; rebindable in the settings menu):
  a / d or arrow left/right   move piece
  e                           rotate clockwise
  q                           rotate counter-clockwise
  s or arrow down             soft drop
  w, arrow up or space        hard drop
  c or 2                      hold / swap piece (once per piece)
  p                           pause / resume
  x or ESC                    back to the menu
  r                           restart (on the game over screen)

Square mechanics (The New Tetris): fill a 4x4 area with exactly four
complete, uncut pieces to form a square - gold if all four are the same
type, silver if mixed. Every cleared row is worth 1 row of credit, plus
10 per gold square and 5 per silver square it runs through (additive);
clearing 4 rows at once (a Tetris) adds 1 extra. The credit is shown as
"Rows" in the HUD.

Wonders: the row credit of every round is added to a persistent counter
stored in <data-dir>/save. It builds seven world wonders in a fixed
sequence; the current wonder and its build percentage are shown in the
HUD, the construction site (ASCII art revealed bottom-up) after every
round and via the "Weltwunder" main menu entry.

Statistics: every finished round also adds its cleared rows, bonus rows
(the gold/silver/Tetris part of the row credit) and the gold and silver
squares built to persistent all-time counters in <data-dir>/stats,
shown via the "Statistik" main menu entry.

Settings (player name, key bindings) are stored in the config file
<data-dir>/rowhammer.conf, by default ~/rowhammer/rowhammer.conf. The
best 10 rounds are kept in <data-dir>/highscore; the list is shown in
the main menu and a finished round reports its rank on the game over
screen. Key bindings can also be overridden
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
# conventions the syslog/logger part is intentionally omitted. In debug
# mode the failure also lands in the event log (guarded with a default,
# because die can run before lib/debug.sh is sourced).
die() {
    if [ "${DEBUG_ACTIVE:-0}" -eq 1 ]; then
        debug_event "fatal: $*"
    fi
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
        --data-dir)
            if [ "$#" -lt 2 ]; then
                printf '%s: option %s requires an argument\n' "${SCRIPT_NAME}" "${1}" >&2
                exit 2
            fi
            DATA_DIR="${2}"
            shift 2
            ;;
        --data-dir=*)
            DATA_DIR="${1#*=}"
            shift
            ;;
        --no-color)
            NO_COLOR_OPT=1
            shift
            ;;
        --color-mode)
            if [ "$#" -lt 2 ]; then
                printf '%s: option %s requires an argument\n' "${SCRIPT_NAME}" "${1}" >&2
                exit 2
            fi
            COLOR_MODE="${2}"
            shift 2
            ;;
        --color-mode=*)
            COLOR_MODE="${1#*=}"
            shift
            ;;
        --debug)
            DEBUG_OPT=1
            shift
            ;;
        --debug-dir)
            if [ "$#" -lt 2 ]; then
                printf '%s: option %s requires an argument\n' "${SCRIPT_NAME}" "${1}" >&2
                exit 2
            fi
            DEBUG_DIR="${2}"
            shift 2
            ;;
        --debug-dir=*)
            DEBUG_DIR="${1#*=}"
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
if [ -z "${DATA_DIR}" ]; then
    printf '%s: --data-dir must not be empty\n' "${SCRIPT_NAME}" >&2
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
case "${COLOR_MODE}" in
    auto|basic|extended) : ;;
    *)
        printf '%s: --color-mode expects auto, basic or extended, got: %s\n' \
            "${SCRIPT_NAME}" "${COLOR_MODE}" >&2
        exit 2
        ;;
esac
case "${DEBUG_OPT}" in
    0|1) : ;;
    *)
        printf '%s: ROWHAMMER_DEBUG expects 0 or 1, got: %s\n' \
            "${SCRIPT_NAME}" "${DEBUG_OPT}" >&2
        exit 2
        ;;
esac

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
for _lib in debug config pieces board squares highscore save stats wonders input render menu; do
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

# Resolve "auto" into basic or extended by probing the terminal, then
# precompute the block SGR sequences for the renderer (lib/render.sh).
color_mode_resolve
render_colors_init

# --- Game state and helpers -----------------------------------------------
CUR_TYPE=""; CUR_ROT=0; CUR_X=0; CUR_Y=0
SCORE=0; CLEARED_TOTAL=0; ROW_CREDIT=0; LEVEL=0; FALL_MS=800
GOLD_COUNT=0; SILVER_COUNT=0; NEXT_INSTANCE_ID=1
HOLD_TYPE=""; HOLD_USED=0
PAUSED=0; GAME_OVER=0; GAME_EXIT=0; DIRTY=1
NOW_MS=0; LAST_FALL=0
# Guards record_round_score so one round enters the highscore list only
# once (a round can end twice: game over, then quitting to the menu).
SCORE_RECORDED=0

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

# record_round_score: close the books on a finished round, at most once
# per round: enter it into the highscore list, bank its row credit
# into the persistent wonder counter (savegame) and its counters into
# the all-time statistics (lib/stats.sh). Runs right when the
# game over triggers, so the game over sidebar can show the achieved
# rank (HS_LAST_RANK) and the HUD the updated wonder progress, and again
# as a catch-all when the player quits a running round to the menu.
record_round_score() {
    if [ "${SCORE_RECORDED}" -eq 1 ]; then
        return 0
    fi
    SCORE_RECORDED=1
    highscore_add "${SCORE}" "${CLEARED_TOTAL}" "${ROW_CREDIT}" "${LEVEL}" "${PLAYER_NAME}"
    # Every cleared row counts toward the wonder, even from an aborted
    # round - like the original, where all modes feed the line total.
    if [ "${ROW_CREDIT}" -gt 0 ]; then
        TOTAL_ROW_CREDIT=$(( TOTAL_ROW_CREDIT + ROW_CREDIT ))
        save_write
    fi
    wonders_update "${TOTAL_ROW_CREDIT}"
    # All-time statistics: physical lines, the bonus part of the row
    # credit (credit minus physical lines) and the squares built.
    stats_add_round "${CLEARED_TOTAL}" "$(( ROW_CREDIT - CLEARED_TOTAL ))" \
        "${GOLD_COUNT}" "${SILVER_COUNT}"
    return 0
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
        debug_event "spawn ${CUR_TYPE} at ${CUR_X},${CUR_Y} blocked - game over (score=${SCORE} lines=${CLEARED_TOTAL} rows=${ROW_CREDIT})"
        record_round_score
    else
        debug_event "spawn ${CUR_TYPE} at ${CUR_X},${CUR_Y} queue=${QUEUE[*]}"
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
    # lock_piece consumed the id it stamped into the board.
    debug_event "lock ${CUR_TYPE} rot=${CUR_ROT} at ${CUR_X},${CUR_Y} id=$(( NEXT_INSTANCE_ID - 1 ))"
    if detect_square "${CUR_X}" "${CUR_Y}"; then
        if [ "${SQUARE_RESULT}" = "G" ]; then
            GOLD_COUNT=$(( GOLD_COUNT + 1 ))
            SCORE=$(( SCORE + SCORE_SQUARE_GOLD ))
            debug_event "gold square bonus: +${SCORE_SQUARE_GOLD} score=${SCORE} gold_total=${GOLD_COUNT}"
        else
            SILVER_COUNT=$(( SILVER_COUNT + 1 ))
            SCORE=$(( SCORE + SCORE_SQUARE_SILVER ))
            debug_event "silver square bonus: +${SCORE_SQUARE_SILVER} score=${SCORE} silver_total=${SILVER_COUNT}"
        fi
    fi
    clear_lines
    if (( CLEARED > 0 )); then
        CLEARED_TOTAL=$(( CLEARED_TOTAL + CLEARED ))
        ROW_CREDIT=$(( ROW_CREDIT + CLEARED_CREDIT ))
        SCORE=$(( SCORE + SCORE_LINES[CLEARED] * (LEVEL + 1) ))
        update_speed
        # The HUD wonder line tracks the running round live: banked
        # total plus the credit earned so far in this round.
        wonders_update $(( TOTAL_ROW_CREDIT + ROW_CREDIT ))
        debug_event "cleared ${CLEARED} row(s): credit=+${CLEARED_CREDIT} lines=${CLEARED_TOTAL} rows=${ROW_CREDIT} score=${SCORE} level=${LEVEL} fall_ms=${FALL_MS} wonder=${WONDER_HUD_NAME} ${WONDER_PERCENT}%"
    fi
    debug_board_snapshot
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
        debug_event "hold refused: already used for this piece"
        return 0
    fi
    if [ -z "${HOLD_TYPE}" ]; then
        queue_fill
        if ! can_place "${QUEUE[0]}" 0 3 0; then
            debug_event "hold refused: next piece ${QUEUE[0]} has no room to spawn"
            return 0
        fi
        HOLD_TYPE="${CUR_TYPE}"
        HOLD_USED=1
        debug_event "hold: stashed ${HOLD_TYPE}"
        spawn_piece
    else
        if ! can_place "${HOLD_TYPE}" 0 3 0; then
            debug_event "hold refused: held piece ${HOLD_TYPE} has no room to spawn"
            return 0
        fi
        debug_event "hold: swap ${CUR_TYPE} <-> ${HOLD_TYPE}"
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
        debug_event "move ${1},${2} -> ${CUR_X},${CUR_Y}"
        DIRTY=1
        return 0
    fi
    debug_event "move ${1},${2} blocked at ${CUR_X},${CUR_Y}"
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
            debug_event "rotate dir=${1} -> rot=${CUR_ROT} kick=${kick} at ${CUR_X},${CUR_Y}"
            DIRTY=1
            return 0
        fi
    done
    debug_event "rotate dir=${1} blocked (rot=${CUR_ROT} at ${CUR_X},${CUR_Y})"
    return 1
}

# step_down: move the piece one row down; lock it when it cannot fall.
# Serves both gravity and soft drop; the debug input log tells the two
# apart (a fall right after a soft-drop key press was manual).
step_down() {
    if can_place "${CUR_TYPE}" "${CUR_ROT}" "${CUR_X}" "$(( CUR_Y + 1 ))"; then
        CUR_Y=$(( CUR_Y + 1 ))
        debug_event "fall -> y=${CUR_Y}"
        DIRTY=1
    else
        lock_and_next
    fi
    return 0
}

# hard_drop: drop the piece to the floor and lock it immediately. Two
# points per dropped row, like most guideline implementations.
hard_drop() {
    local dropped=0
    while can_place "${CUR_TYPE}" "${CUR_ROT}" "${CUR_X}" "$(( CUR_Y + 1 ))"; do
        CUR_Y=$(( CUR_Y + 1 ))
        SCORE=$(( SCORE + 2 ))
        dropped=$(( dropped + 1 ))
    done
    debug_event "hard drop: ${dropped} row(s) to y=${CUR_Y} score=${SCORE}"
    lock_and_next
    return 0
}

# handle_key: apply the key in the global KEY to the game state. Movement
# keys are ignored while paused or on the game over screen. Letter keys
# come from the configurable bindings; a fixed secondary layout is always
# active on top of them: the arrow keys (left/right move, up = hard drop,
# down = soft drop), space for hard drop and 2 for hold.
handle_key() {
    if [ -z "${KEY}" ]; then
        return 0
    fi
    if [ "${GAME_OVER}" -eq 1 ]; then
        case "${KEY}" in
            r)
                debug_event "restart from game over screen"
                game_reset
                ;;
            "${KEY_QUIT}"|ESC)
                debug_event "quit to menu from game over screen"
                GAME_EXIT=1
                ;;
        esac
        return 0
    fi
    case "${KEY}" in
        "${KEY_PAUSE}")
            PAUSED=$(( 1 - PAUSED ))
            if [ "${PAUSED}" -eq 1 ]; then
                debug_event "paused"
            else
                debug_event "resumed"
            fi
            # Restart the gravity timer so a long pause is not counted
            # as elapsed fall time.
            now_ms
            LAST_FALL="${NOW_MS}"
            DIRTY=1
            ;;
        "${KEY_QUIT}"|ESC)
            debug_event "quit to menu"
            GAME_EXIT=1
            ;;
    esac
    if [ "${PAUSED}" -eq 1 ]; then
        return 0
    fi
    case "${KEY}" in
        LEFT|"${KEY_LEFT}")   try_move -1 0 || : ;;
        RIGHT|"${KEY_RIGHT}") try_move 1 0 || : ;;
        "${KEY_ROT_CW}")      try_rotate 1 || : ;;
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
        UP|SPACE|"${KEY_HARD}")
            hard_drop
            ;;
        2|"${KEY_HOLD}")
            hold_piece
            ;;
    esac
    return 0
}

# game_reset: start a fresh round (used at launch and for restart).
game_reset() {
    debug_event "round start (seed=${SEED:-unset})"
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
    SCORE_RECORDED=0
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
    # Quitting a running round to the menu ends it too; the flag makes
    # this a no-op when the game over path already recorded the round.
    record_round_score
    debug_event "game session end (score=${SCORE} lines=${CLEARED_TOTAL} rows=${ROW_CREDIT} level=${LEVEL})"
    return 0
}

# --- Main menu loop -------------------------------------------------------
main() {
    # Restore the terminal on any exit path, including Ctrl-C; the debug
    # logs close afterwards, so the "logs written to" note lands on the
    # normal screen buffer.
    trap 'term_restore; debug_close' EXIT
    trap 'exit 130' INT TERM
    # Debug logging starts before the alternate screen, so init errors
    # (unwritable log directory etc.) stay readable.
    debug_init
    # Load the persistent highscore list once; rounds update it in
    # memory and rewrite the file when they enter the list.
    highscore_load
    # Load the wonder savegame and derive the initial wonder state for
    # the HUD before the first frame is drawn.
    save_load
    wonders_update "${TOTAL_ROW_CREDIT}"
    # Load the all-time statistics; rounds extend them via
    # record_round_score.
    stats_load
    term_setup

    while :; do
        menu_run "R O W H A M M E R" \
            "Einzelspieler" \
            "Mehrspieler" \
            "Highscores" \
            "Weltwunder" \
            "Statistik" \
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
                highscore_screen
                ;;
            3)
                # Progress screen: the current construction site with
                # the banked all-time row total.
                wonder_screen "${TOTAL_ROW_CREDIT}"
                ;;
            4)
                stats_screen
                ;;
            5)
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
