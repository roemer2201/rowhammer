#!/usr/bin/env bash
#
# rowhammer.sh
#
# Description:
#   "rowhammer", a terminal Tetris game written in pure bash, modeled
#   after "The New Tetris" (N64). Starts with a menu (singleplayer,
#   multiplayer placeholder, settings); the game offers a 10x20 board,
#   7-bag randomizer with a 3-piece preview, a hold slot, gravity with a
#   level-based speed curve, soft/hard drop, a short lock delay that lets a
#   landing piece still be slid or rotated, pause and game over with
#   restart. Completed rows blink briefly before they are removed, so
#   the player sees which rows scored. The play screen is one fixed
#   48x22 block centered in the terminal: the hold piece with the round
#   counters below it on the left, the board in the middle and the three
#   upcoming pieces top right; pause and game
#   over appear as a box over the board. Frames are pushed out
#   incrementally - only the lines that changed are rewritten (see
#   lib/render.sh). Menus, info screens and prompts are centered the
#   same way (render_menu_frame), so they line up with the play screen
#   instead of sitting in the top left corner. Pressing the quit key (x/ESC) in
#   a running round opens a pause menu instead of aborting: resume,
#   suspend the round into the main menu (it stays resumable via the
#   "Fortsetzen" entry offered in the main menu and in the singleplayer
#   menu) or end it; a round is recorded only when it really ends.
#   The New Tetris square mechanics are in: 4x4 squares built
#   from four complete pieces turn gold (mono) or silver (multi) and make
#   cleared rows worth bonus row credit (the "Rows" counter). Since
#   0.16.0 that weighted row credit is the one and only scoring
#   currency (user decision): cleared rows are the sole source of
#   points, drops, square formation and spins earn nothing, and there
#   is no separate score. The credit
#   accumulates across all rounds in a savegame and builds the seven
#   world wonders of the Wonders mode: the current wonder rises as ASCII
#   art, revealed bottom-up with every invested row, shown after every
#   round and via the "Weltwunder" main menu entry. It left the HUD in
#   0.25.0 (user decision) so the rowhammer counter - four rows cleared
#   in one move, the namesake of the game - could take its slot; since
#   0.26.0 all counters live in the left pane and the HUD has no status
#   lines left to hold it.
#   Player name, color theme and key bindings are
#   configurable in the settings menu and persisted to a user config
#   file. Blocks render in the basic 8/16-color ANSI palette or, when
#   the terminal supports it (auto-detected, overridable via
#   --color-mode), in an extended xterm 256-color palette; the color
#   theme (--color-theme: guideline, classic, mono, colorblind) picks
#   which colors the pieces and gold/silver squares use. With colors off
#   (--no-color / NO_COLOR) each piece type draws its own two-character
#   glyph and the gold/silver squares use distinct non-letter glyphs, so
#   blocks stay tellable apart. All game data (config, persistent top-10 highscore list,
#   the savegame and the all-time statistics) lives in one data
#   directory, by default
#   ~/.config/rowhammer. Finished rounds enter the highscore list, which the
#   main menu shows (two lines per entry: rows, gold/silver squares,
#   rowhammers, pieces placed and their rate in pieces per minute, play
#   time and date) and
#   whose rank appears on the game over screen; the row credit decides
#   the ranking. The HUD also shows the running round's play time (paused
#   time excluded) and the pieces it has placed.
#   Every round also feeds persistent statistics (cleared rows, bonus
#   rows, gold/silver squares built, rowhammers, pieces placed and time
#   played, plus the results of
#   the last three rounds with their play date), shown via the "Statistik" main
#   menu entry; the highscore list shows each entry's date as well.
#   A debug mode (--debug) traces the whole session into log
#   files: every screen update 1:1, every key press and every game
#   action (see lib/debug.sh). The fixed play screen needs a
#   terminal of at least 48x22; a resize during play is caught via
#   SIGWINCH and redraws cleanly, and shrinking below the minimum pauses
#   the round behind a "resize me" overlay until the terminal grows back.
#   A working multiplayer follows in a later phase (see CLAUDE.md).
#
# Program flow:
#   1. Parse arguments (kept aside until the config file is loaded).
#   2. Verify prerequisites (bash >= 4, interactive terminal, minimum
#      size; the size is rechecked live via SIGWINCH while running).
#   3. Source the library modules (debug, config, pieces, board,
#      squares, highscore, save, stats, wonders, input, render, menu).
#   4. Resolve settings with precedence default < config file < env <
#      CLI and validate them.
#   5. Install the cleanup trap, start the debug logs (when --debug is
#      set), load the highscore list, the savegame and the statistics
#      and enter the alternate screen in raw input mode (echo and
#      canonical mode off for the whole session).
#   6. Run the main menu loop; "Einzelspieler" starts the game loop
#      (input, gravity, locking, square detection, row flash, line
#      clearing, rendering), finished rounds are recorded in the
#      highscore list, their row credit is banked into the wonder
#      savegame and their counters into the statistics file,
#      settings changes are written back to the config file. A round
#      suspended via the pause menu returns to the main menu
#      unrecorded and continues via its "Fortsetzen" entry; leaving the
#      game while such a round waits asks for confirmation first.
#   7. Restore the terminal on exit and close the debug logs.
#
# Usage:
#   rowhammer.sh [--seed N] [--name NAME] [--data-dir DIR] [--no-color]
#                [--color-mode auto|basic|extended]
#                [--color-theme guideline|classic|mono|colorblind]
#                [--debug] [--debug-dir DIR] [-h|--help]
#
# Version: 0.32.0  (2026-07-30)

set -euo pipefail

SCRIPT_NAME="$(basename -- "${0}")"
# CHANGE 2026-07-18 (reapplied 2026-07-21 after the rename to rowhammer.sh):
# resolve symlinks before taking the directory so the packaged launcher
# (/usr/games/rowhammer -> /usr/share/rowhammer/rowhammer.sh) finds the
# library modules and assets next to the real script. readlink -f is part
# of coreutils, which is already a baseline requirement.
SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"

# Game version, reported in the debug session header. Keep in sync with
# the Version field in the header comment above, with debian/changelog and
# with the Version tag in rowhammer.spec (build-rpm.sh checks the latter).
ROWHAMMER_VERSION="0.32.0"

# --- Built-in defaults ----------------------------------------------------
# Full precedence: command-line argument > environment variable > config
# file > built-in default. SEED, the no-color switch and the debug
# switches are not
# part of the config file, so they take their env fallback directly; the
# config-driven settings (player name, key bindings) start from these
# defaults, get overridden by config_load and the env/CLI blocks after
# sourcing below.
SEED="${ROWHAMMER_SEED:-}"
# Color on/off. Beyond the project's own ROWHAMMER_NO_COLOR we honor the
# de-facto standard NO_COLOR variable (https://no-color.org/): when it is
# present and not an empty string, colors are disabled regardless of its
# value. Precedence for the disable switch: standard NO_COLOR < the
# project's ROWHAMMER_NO_COLOR < --no-color on the command line. That
# lets a user who exports NO_COLOR globally still force colors back on for
# rowhammer with ROWHAMMER_NO_COLOR=0.
if [ -n "${ROWHAMMER_NO_COLOR:-}" ]; then
    NO_COLOR_OPT="${ROWHAMMER_NO_COLOR}"
elif [ -n "${NO_COLOR:-}" ]; then
    NO_COLOR_OPT=1
else
    NO_COLOR_OPT=0
fi
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
# CHANGE 2026-07-20: default moved from ~/rowhammer to
# ~/.config/rowhammer (user decision: keep the home directory clean);
# no migration of the old path per the no-backward-compatibility rule.
DATA_DIR="${ROWHAMMER_DATA_DIR:-${HOME}/.config/rowhammer}"
PLAYER_NAME="Player"
# Color theme: maps piece and gold/silver colors to a named scheme
# (COLOR_THEMES in lib/pieces.sh). Like the key bindings it is a
# config-driven setting, so it starts from this default and is then
# overridden by config_load and the env/CLI blocks after sourcing.
COLOR_THEME="guideline"
# CHANGE 2026-07-30 (user decision): the rotation keys moved onto the
# left hand's home row - a turns counter-clockwise, d clockwise - and the
# hold slot took w (replacing the fixed secondary 2). That claimed the
# three letters that used to move left/right and hard drop, so those two
# actions keep only their fixed secondaries: the arrow keys for moving
# and space/arrow up for the hard drop. NONE is the "no letter bound"
# value for exactly that case; the arrows and space are wired in
# handle_key regardless of the bindings, so nothing becomes unreachable.
KEY_LEFT="NONE"
KEY_RIGHT="NONE"
KEY_ROT_CW="d"
KEY_ROT_CCW="a"
KEY_SOFT="s"
KEY_HARD="SPACE"
KEY_PAUSE="p"
KEY_QUIT="x"
KEY_HOLD="c"
# CLI values are parked here and applied after config_load so the
# command line keeps the highest precedence.
CLI_PLAYER_NAME=""
CLI_COLOR_THEME=""

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
  --name NAME   Player name recorded with highscore entries (max. 16
                characters from A-Z a-z 0-9 space _ -).
                Env: ROWHAMMER_PLAYER_NAME  Default: Player
  --data-dir DIR
                Directory for all persistent game data: the config file
                rowhammer.conf, the highscore list, the savegame and
                the statistics file.
                Env: ROWHAMMER_DATA_DIR     Default: ~/.config/rowhammer
  --no-color    Disable ANSI colors. Each piece type is then drawn with
                its own two-letter glyph (II OO TT SS ZZ JJ LL) so blocks
                stay tellable apart after locking; gold squares show as
                "##", silver as "%%". Overrides --color-mode. The
                de-facto standard NO_COLOR variable
                (https://no-color.org/) is also honored: if it is set and
                non-empty, colors default to off; set ROWHAMMER_NO_COLOR=0
                to force them back on.
                Env: ROWHAMMER_NO_COLOR     Default: 0
  --color-mode MODE
                Color palette: "auto" detects 256-color support (tput
                colors, TERM, COLORTERM) and picks extended or basic;
                "basic" forces the 8/16-color ANSI palette; "extended"
                forces the xterm 256-color palette (guideline piece
                colors incl. a real orange L, richer gold/silver).
                Env: ROWHAMMER_COLOR_MODE   Default: auto
  --color-theme NAME
                Color scheme mapping piece and gold/silver colors:
                "guideline" (default), "classic", "mono" or "colorblind".
                Also selectable in the settings menu and persisted there.
                Env: ROWHAMMER_COLOR_THEME  Default: guideline
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
  x or ESC                    open the pause menu: resume, go to the
                              main menu with the round suspended
                              (resumable via the "Fortsetzen" entry in
                              the main and singleplayer menus), or
                              end the round
  r                           restart (on the game over screen)

Square mechanics (The New Tetris): fill a 4x4 area with exactly four
complete, uncut pieces to form a square - gold if all four are the same
type, silver if mixed. Every cleared row is worth 1 row of credit, plus
10 per gold square and 5 per silver square it runs through (additive);
clearing 4 rows at once (a Tetris) adds 1 extra. The credit is shown as
"Rows" in the HUD and is the game's only score: cleared rows are the
sole source of points - drops, square formation and spins earn nothing.
Famous maximum for a single move: a Tetris through two complete gold
squares = 4 + 1 + 8 x 10 = 85.

Wonders: the row credit of every round is added to a persistent counter
stored in <data-dir>/save. It builds seven world wonders in a fixed
sequence; the current wonder and its build percentage are shown in the
HUD, the construction site (ASCII art revealed bottom-up) after every
round and via the "Weltwunder" main menu entry.

Statistics: every finished round also adds its cleared rows, bonus rows
(the gold/silver/Tetris part of the row credit) and the gold and silver
squares built to persistent all-time counters in <data-dir>/stats; the
results of the last three rounds (rows, bonus rows, squares) are
kept there as well. Both are
shown via the "Statistik" main menu entry.

Settings (player name, key bindings) are stored in the config file
<data-dir>/rowhammer.conf, by default ~/.config/rowhammer/rowhammer.conf. The
best 10 rounds are kept in <data-dir>/highscore; the list is shown in
the main menu and a finished round reports its rank on the game over
screen. Key bindings can also be overridden
via environment variables ROWHAMMER_KEY_LEFT, ROWHAMMER_KEY_RIGHT,
ROWHAMMER_KEY_ROT_CW, ROWHAMMER_KEY_ROT_CCW, ROWHAMMER_KEY_SOFT,
ROWHAMMER_KEY_HARD, ROWHAMMER_KEY_PAUSE, ROWHAMMER_KEY_QUIT,
ROWHAMMER_KEY_HOLD (single characters a-z or 0-9, or the words SPACE and
NONE; NONE leaves an action without a letter key). Defaults: a/d rotate
counter-clockwise/clockwise, s soft drop, c hold, p pause, x menu. Moving
left/right (arrow keys), the hard drop (space, arrow up) and holding (w)
always work through their fixed secondary keys as well.

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
        --color-theme)
            if [ "$#" -lt 2 ]; then
                printf '%s: option %s requires an argument\n' "${SCRIPT_NAME}" "${1}" >&2
                exit 2
            fi
            CLI_COLOR_THEME="${2}"
            shift 2
            ;;
        --color-theme=*)
            CLI_COLOR_THEME="${1#*=}"
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

# The fixed board+sidebar layout needs at least this much room. The check
# runs at startup (below, once the input module is sourced) and, since
# 0.19.0, continuously while the game runs: a SIGWINCH that shrinks the
# terminal below this pauses play behind a "resize me" overlay until it
# grows back (see term_measure, term_resize_apply in lib/input.sh and the
# too-small screen in lib/render.sh). TERM_RESIZED is raised by the
# SIGWINCH handler and applied at the next read_key, so nothing is drawn
# from inside the async signal handler.
MIN_TERM_COLS=48
# CHANGE 2026-07-28: 24 down to 22 rows. The two status lines below the
# board are gone (their counters now sit in the left pane, see
# render_pane_left in lib/render.sh), so the game block is two rows
# shorter and the game runs in correspondingly smaller terminals. The
# menu and info screens fit as well: the tallest of them, the wonder
# construction site, needs 19 lines (it lost its leading blank line when
# the screens became centered blocks in 0.28.0).
MIN_TERM_ROWS=22
TERM_ROWS=0
TERM_COLS=0
TERM_TOO_SMALL=0
TERM_RESIZED=0

# --- Library modules ------------------------------------------------------
for _lib in debug config pieces board squares highscore save stats wonders input render menu; do
    if [ ! -r "${SCRIPT_DIR}/lib/${_lib}.sh" ]; then
        die "Missing library file: ${SCRIPT_DIR}/lib/${_lib}.sh"
    fi
    # shellcheck source=/dev/null
    . "${SCRIPT_DIR}/lib/${_lib}.sh"
done
unset _lib

# Terminal size check, now that term_measure (lib/input.sh) is available.
# It fills TERM_ROWS/TERM_COLS and sets TERM_TOO_SMALL against the minimum
# above; a too-small terminal at startup is a hard error, while one that
# shrinks later is handled live via SIGWINCH.
term_measure
if [ "${TERM_TOO_SMALL}" -eq 1 ]; then
    die "Terminal too small: need at least ${MIN_TERM_COLS}x${MIN_TERM_ROWS}, got ${TERM_COLS}x${TERM_ROWS}"
fi

# --- Settings resolution (default < config < env < CLI) -------------------
# The config file may override the built-in defaults above.
config_load

# Environment variables override the config file.
PLAYER_NAME="${ROWHAMMER_PLAYER_NAME:-${PLAYER_NAME}}"
COLOR_THEME="${ROWHAMMER_COLOR_THEME:-${COLOR_THEME}}"
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
if [ -n "${CLI_COLOR_THEME}" ]; then
    COLOR_THEME="${CLI_COLOR_THEME}"
fi

# Validate the resolved settings; the config file and env vars are user
# input too. The name charset also keeps the sourced config file safe
# (no quotes or expansions can sneak into it).
_name_re='^[A-Za-z0-9_ -]{1,16}$'
if ! [[ "${PLAYER_NAME}" =~ ${_name_re} ]]; then
    die "Invalid player name: '${PLAYER_NAME}' (allowed: max. 16 characters from A-Z a-z 0-9 space _ -)"
fi
_theme_ok=0
for _theme in "${COLOR_THEMES[@]}"; do
    if [ "${_theme}" = "${COLOR_THEME}" ]; then
        _theme_ok=1
        break
    fi
done
if [ "${_theme_ok}" -eq 0 ]; then
    die "Invalid color theme: '${COLOR_THEME}' (allowed: ${COLOR_THEMES[*]})"
fi
# CHANGE 2026-07-30: NONE joined the allowed values as "this action has
# no letter key" (see the defaults above). It is exempt from the
# duplicate check on purpose - several actions may be unbound at once -
# and it can never collide with a real key press either, because read_key
# only ever reports single characters or the names LEFT/RIGHT/UP/DOWN/
# SPACE/ENTER/ESC.
_key_re='^([a-z0-9]|SPACE|NONE)$'
for _var in "${KEY_ACTIONS[@]}"; do
    if ! [[ "${!_var}" =~ ${_key_re} ]]; then
        die "Invalid key binding ${_var}='${!_var}' (allowed: a-z, 0-9, SPACE or NONE)"
    fi
    if [ "${!_var}" = "NONE" ]; then
        continue
    fi
    for _other in "${KEY_ACTIONS[@]}"; do
        if [ "${_var}" != "${_other}" ] && [ "${!_var}" = "${!_other}" ]; then
            die "Key bindings ${_var} and ${_other} both use '${!_var}'"
        fi
    done
done
unset _name_re _key_re _var _other _theme _theme_ok

# Seeding RANDOM makes the 7-bag shuffle sequence reproducible.
if [ -n "${SEED}" ]; then
    RANDOM="${SEED}"
fi

# Resolve "auto" into basic or extended by probing the terminal, then
# precompute the block SGR sequences for the renderer (lib/render.sh).
color_mode_resolve
render_colors_init
# Center the fixed game block on the measured terminal; its position
# only changes on a resize, so it is computed once here, not per frame.
layout_update

# --- Game state and helpers -----------------------------------------------
CUR_TYPE=""; CUR_ROT=0; CUR_X=0; CUR_Y=0
CLEARED_TOTAL=0; ROW_CREDIT=0; LEVEL=0; FALL_MS=800
GOLD_COUNT=0; SILVER_COUNT=0; NEXT_INSTANCE_ID=1
# Round counter of four-row clears, the move this game is named after.
# Raised in clear_lines (lib/board.sh) where the Tetris bonus is paid,
# reset per round in game_reset and banked into the all-time statistics
# by record_round. Round state, not one of the ROWHAMMER_* settings
# variables that carry the environment overrides.
ROWHAMMER_COUNT=0
# Round counter of pieces actually placed ("Pieces" in the HUD, "PCS" in
# the tables). Raised in lock_and_next where a piece really settles - a
# piece put into the hold slot or one still falling has not been placed
# yet - reset per round in game_reset and banked into the highscore entry
# and the all-time statistics by record_round. Together with the round's
# play time it yields the pieces per minute the statistics and highscore
# screens show (fmt_ppm).
PIECE_COUNT=0
HOLD_TYPE=""; HOLD_USED=0
PAUSED=0; GAME_OVER=0; GAME_EXIT=0; DIRTY=1
# Raised by term_resize_apply (lib/input.sh) after a terminal resize was
# handled, so the loops that gate their own redraw (the game loop via
# DIRTY, menu_run and the info screens via their local dirty flag) repaint
# the screen that the resize cleared. Every loop clears it after acting.
REDRAW_PENDING=0
# A round left via the pause menu's "Ins Hauptmenue" keeps its complete
# state in the globals above; this flag marks it as waiting for the
# "Fortsetzen" main menu entry (issue #12).
GAME_SUSPENDED=0
NOW_MS=0; LAST_FALL=0
# Lock delay (2026-07-22): a piece that cannot fall is not locked on the
# spot but rests for a short grace window (LOCK_DELAY_MS below), during
# which the player may still slide or rotate it. LOCK_PENDING marks that
# armed state, TOUCHDOWN_MS is the timestamp the current rest started -
# the lock fires once the delay has elapsed (see lock_touchdown, step_down
# and the game loop).
LOCK_PENDING=0; TOUCHDOWN_MS=0
# Play time of the current round in milliseconds and the timestamp the
# currently running play segment was last accounted from. Only time spent
# actually playing counts: pauses (the "p" toggle and the pause menu) and
# the game over screen do not, because those states reset PLAY_LAST to
# "now" when play resumes (play_clock_resume), so the idle interval is
# never added. The round keeps its PLAY_MS across a suspend/resume too.
PLAY_MS=0; PLAY_LAST=0
# Guards record_round so one round enters the highscore list only
# once (a round can end twice: game over, then quitting to the menu).
ROUND_RECORDED=0

# CHANGE 2026-07-20: the separate score (line points scaling with the
# level, flat square formation bonuses, drop points) was removed on user
# decision. The weighted row credit ROW_CREDIT (1 per row, +5 per silver
# and +10 per gold square strip in a cleared row, +1 for a Tetris; see
# ROWS_* in lib/squares.sh) is the game's only scoring currency now -
# the same number that builds the wonders.

# Gravity interval per level in milliseconds. A lookup table instead of a
# formula so the curve stays easy to tune; the last entry is the cap.
LEVEL_SPEEDS=(800 720 640 560 480 410 350 300 260 220 190 160 140 120)

# Lock delay in milliseconds: the grace window a resting piece gets before
# it locks, so a landing can still be nudged left/right or rotated. Only a
# move that makes the piece airborne again cancels the pending lock (see
# lock_delay_recheck); a move that leaves it resting keeps the original
# deadline, so a piece cannot be kept alive forever on the floor. An
# adjustable game-feel constant, like LEVEL_SPEEDS and TICK_S.
LOCK_DELAY_MS=250

# Clear animation: rows completed by a lock blink FLASH_CYCLES times
# (highlighted / normal) with FLASH_MS milliseconds per half cycle before
# they are actually removed, so the player sees which rows scored. The
# defaults add up to a short 280 ms; adjustable game-feel constants like
# LEVEL_SPEEDS and LOCK_DELAY_MS. FLASH_CYCLES=0 turns the animation off.
FLASH_MS=70
FLASH_CYCLES=2

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

# fmt_duration SECONDS: format a whole-second duration as MM:SS into the
# global FMT_DURATION. Minutes are not rolled into hours so the field
# stays five characters for any realistic round (90 min -> "90:00"),
# which keeps the HUD and the highscore column narrow. Shared by the HUD
# (draw_frame) and the highscore screen so both read identically.
FMT_DURATION="00:00"
fmt_duration() {
    local s="${1}"
    printf -v FMT_DURATION '%02d:%02d' $(( s / 60 )) $(( s % 60 ))
}

# fmt_ppm PIECES SECONDS: format a placement rate as pieces per minute
# with one decimal into the global FMT_PPM ("-" while no play time has
# been measured yet, which is the only division-by-zero case). Bash has
# no floating point, so the value is computed in tenths and split for
# printing. Shared by the highscore and the statistics screen so both
# read identically.
FMT_PPM="-"
fmt_ppm() {
    local pieces="${1}" secs="${2}" tenths
    if [ "${secs}" -le 0 ]; then
        FMT_PPM="-"
        return 0
    fi
    tenths=$(( pieces * 600 / secs ))
    printf -v FMT_PPM '%d.%d' "$(( tenths / 10 ))" "$(( tenths % 10 ))"
    return 0
}

# play_clock_resume: mark "now" as the start of a fresh play-time segment
# (also restarting the gravity timer, which every resume point already
# did). Called wherever the round returns to active play after an idle
# phase - unpausing, leaving the pause menu, a new or a resumed round -
# so the interval spent paused or in a menu is not counted as play time.
play_clock_resume() {
    now_ms
    LAST_FALL="${NOW_MS}"
    PLAY_LAST="${NOW_MS}"
    # A piece resting with the lock delay armed must not lose that window
    # to the idle interval (pause, pause menu, resumed round); restamp its
    # touchdown to "now" so the delay starts over on resume instead of
    # firing immediately from the real time elapsed while idle.
    if [ "${LOCK_PENDING}" -eq 1 ]; then
        TOUCHDOWN_MS="${NOW_MS}"
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

# record_round: close the books on a finished round, at most once
# per round: enter it into the highscore list, bank its row credit
# into the persistent wonder counter (savegame) and its counters into
# the all-time statistics (lib/stats.sh). Runs right when the
# game over triggers, so the game over box can show the achieved
# rank (HS_LAST_RANK), and again as a catch-all when the player quits a
# running round to the menu.
record_round() {
    if [ "${ROUND_RECORDED}" -eq 1 ]; then
        return 0
    fi
    ROUND_RECORDED=1
    # Round play time in whole seconds, the round's four-row clears and
    # the pieces it placed; all three are stored with the highscore entry
    # (play time and pieces are what its PCS/min column is computed from).
    highscore_add "${ROW_CREDIT}" "${CLEARED_TOTAL}" "${LEVEL}" \
        "${PLAYER_NAME}" "${GOLD_COUNT}" "${SILVER_COUNT}" \
        "$(( PLAY_MS / 1000 ))" "${ROWHAMMER_COUNT}" "${PIECE_COUNT}"
    # Every cleared row counts toward the wonder, even from an aborted
    # round - like the original, where all modes feed the line total.
    if [ "${ROW_CREDIT}" -gt 0 ]; then
        TOTAL_ROW_CREDIT=$(( TOTAL_ROW_CREDIT + ROW_CREDIT ))
        save_write
    fi
    wonders_update "${TOTAL_ROW_CREDIT}"
    # All-time statistics: the round's physical lines, the bonus
    # part of the row credit (credit minus physical lines), the
    # squares built, its four-row clears, the pieces it placed and its
    # play time in whole seconds; the round also enters the
    # recent-rounds list. Pieces and play time are the pair the
    # statistics screen derives its PCS/min figures from.
    stats_add_round "${CLEARED_TOTAL}" \
        "$(( ROW_CREDIT - CLEARED_TOTAL ))" "${GOLD_COUNT}" "${SILVER_COUNT}" \
        "${ROWHAMMER_COUNT}" "${PIECE_COUNT}" "$(( PLAY_MS / 1000 ))"
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
    # A freshly spawned piece starts airborne: clear any lock delay left
    # from the piece that just locked.
    LOCK_PENDING=0
    if ! can_place "${CUR_TYPE}" "${CUR_ROT}" "${CUR_X}" "${CUR_Y}"; then
        GAME_OVER=1
        debug_event "spawn ${CUR_TYPE} at ${CUR_X},${CUR_Y} blocked - game over (lines=${CLEARED_TOTAL} rows=${ROW_CREDIT})"
        record_round
    else
        debug_event "spawn ${CUR_TYPE} at ${CUR_X},${CUR_Y} queue=${QUEUE[*]}"
    fi
    DIRTY=1
}

# flash_rows: blink the rows that a lock just completed, before they are
# removed from the board. The rows come from board_full_rows (FULL_ROWS);
# the render layer draws the highlight for FLASH_ROWS whenever FLASH_STATE
# is 1, so the animation is nothing but toggling that flag and redrawing.
# The wait between the half cycles reuses a timed read instead of sleep:
# no fork per frame, and key presses arriving during the animation are
# swallowed on purpose so a burst of them cannot fire at once on the piece
# that spawns right afterwards (same rationale as the resize overlay in
# lib/input.sh). A pending SIGWINCH interrupts the read and is applied by
# read_key on the next tick, as usual.
flash_rows() {
    if [ "${FLASH_CYCLES}" -le 0 ] || [ "${#FULL_ROWS[@]}" -eq 0 ]; then
        return 0
    fi
    local y i
    FLASH_ROWS=()
    for y in "${FULL_ROWS[@]}"; do
        FLASH_ROWS["${y}"]=1
    done
    debug_event "row flash: rows=${FULL_ROWS[*]} cycles=${FLASH_CYCLES} ms=${FLASH_MS}"
    for (( i = 0; i < FLASH_CYCLES; i++ )); do
        FLASH_STATE=1
        draw_frame
        key_drain "${FLASH_MS}"
        FLASH_STATE=0
        draw_frame
        key_drain "${FLASH_MS}"
    done
    FLASH_ROWS=()
    FLASH_STATE=0
    return 0
}

# lock_and_next: lock the active piece, detect squares, flash and clear
# completed rows, update credit/level and spawn the next piece. The flash
# (flash_rows) blocks the loop for its short duration, which is intended:
# the round waits for the animation before the next piece appears. Square
# detection runs before line clearing on purpose: a piece that completes a square
# and a row at once still forms the square first, so the cleared row
# already earns the square's bonus credit. Forming a square earns no
# instant points (only its strips pay off when their rows clear later).
lock_and_next() {
    lock_piece "${CUR_TYPE}" "${CUR_ROT}" "${CUR_X}" "${CUR_Y}"
    # One more piece placed this round: this is the only spot where a
    # piece really settles, so it is where the HUD's "Pieces" counter
    # grows (a held or still falling piece is not placed).
    PIECE_COUNT=$(( PIECE_COUNT + 1 ))
    # lock_piece consumed the id it stamped into the board.
    debug_event "lock ${CUR_TYPE} rot=${CUR_ROT} at ${CUR_X},${CUR_Y} id=$(( NEXT_INSTANCE_ID - 1 )) pieces=${PIECE_COUNT}"
    if detect_square "${CUR_X}" "${CUR_Y}"; then
        if [ "${SQUARE_RESULT}" = "G" ]; then
            GOLD_COUNT=$(( GOLD_COUNT + 1 ))
            debug_event "gold square formed: gold_total=${GOLD_COUNT}"
        else
            SILVER_COUNT=$(( SILVER_COUNT + 1 ))
            debug_event "silver square formed: silver_total=${SILVER_COUNT}"
        fi
    fi
    # Let completed rows blink briefly before they vanish (the square
    # detection above already ran, so a row through a fresh gold/silver
    # square flashes as the scoring row it is).
    board_full_rows
    flash_rows
    clear_lines
    if (( CLEARED > 0 )); then
        CLEARED_TOTAL=$(( CLEARED_TOTAL + CLEARED ))
        ROW_CREDIT=$(( ROW_CREDIT + CLEARED_CREDIT ))
        update_speed
        # CHANGE 2026-07-28: the wonder state is no longer refreshed per
        # clear. It used to feed the HUD's live wonder line, which gave
        # up its slot to the rowhammer counter (see render_status in
        # lib/render.sh); record_round and wonder_screen each recompute
        # it from the row total, so nothing reads a stale value.
        debug_event "cleared ${CLEARED} row(s): credit=+${CLEARED_CREDIT} lines=${CLEARED_TOTAL} rows=${ROW_CREDIT} level=${LEVEL} fall_ms=${FALL_MS} rowhammers=${ROWHAMMER_COUNT}"
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
        # The swapped-in piece re-enters airborne at the spawn position;
        # drop any lock delay armed for the piece we just swapped out.
        LOCK_PENDING=0
        DIRTY=1
    fi
    now_ms
    LAST_FALL="${NOW_MS}"
    return 0
}

# lock_delay_recheck: after a successful move or rotation of a piece whose
# lock delay is already armed, cancel the pending lock if the repositioned
# piece can fall again. Per the lock-delay design (see LOCK_DELAY_MS) only
# a shift that makes the piece airborne again resets the touchdown timer -
# it then falls under normal gravity; a move that leaves it resting keeps
# the original deadline running, so repeated floor moves cannot stall the
# lock forever.
lock_delay_recheck() {
    if [ "${LOCK_PENDING}" -eq 1 ] && \
       can_place "${CUR_TYPE}" "${CUR_ROT}" "${CUR_X}" "$(( CUR_Y + 1 ))"; then
        LOCK_PENDING=0
        now_ms
        LAST_FALL="${NOW_MS}"
        debug_event "lock delay reset: piece airborne again at ${CUR_X},${CUR_Y}"
    fi
}

# try_move DX DY: move the piece if the target position is free.
try_move() {
    local nx=$(( CUR_X + ${1} )) ny=$(( CUR_Y + ${2} ))
    if can_place "${CUR_TYPE}" "${CUR_ROT}" "${nx}" "${ny}"; then
        CUR_X="${nx}"
        CUR_Y="${ny}"
        debug_event "move ${1},${2} -> ${CUR_X},${CUR_Y}"
        DIRTY=1
        lock_delay_recheck
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
            lock_delay_recheck
            return 0
        fi
    done
    debug_event "rotate dir=${1} blocked (rot=${CUR_ROT} at ${CUR_X},${CUR_Y})"
    return 1
}

# lock_touchdown: the active piece cannot fall. Instead of locking on the
# spot, arm the lock delay (LOCK_DELAY_MS) so the game loop locks it only
# after the grace window, giving the player a moment to still slide or
# rotate the landing. Only the transition into the pending state stamps
# the deadline, so repeated gravity ticks against the floor (or a soft
# drop on an already resting piece) do not keep pushing it back.
lock_touchdown() {
    if [ "${LOCK_PENDING}" -eq 0 ]; then
        LOCK_PENDING=1
        now_ms
        TOUCHDOWN_MS="${NOW_MS}"
        debug_event "touchdown at ${CUR_X},${CUR_Y}: lock delay ${LOCK_DELAY_MS}ms armed"
    fi
}

# step_down: move the piece one row down; arm the lock delay when it cannot
# fall. Serves both gravity and soft drop; the debug input log tells the
# two apart (a fall right after a soft-drop key press was manual).
step_down() {
    if can_place "${CUR_TYPE}" "${CUR_ROT}" "${CUR_X}" "$(( CUR_Y + 1 ))"; then
        CUR_Y=$(( CUR_Y + 1 ))
        debug_event "fall -> y=${CUR_Y}"
        DIRTY=1
    else
        lock_touchdown
    fi
    return 0
}

# hard_drop: drop the piece to the floor and lock it immediately.
# CHANGE 2026-07-20: no points per dropped row anymore - cleared rows
# are the only score source (see the scoring note above).
hard_drop() {
    local dropped=0
    while can_place "${CUR_TYPE}" "${CUR_ROT}" "${CUR_X}" "$(( CUR_Y + 1 ))"; do
        CUR_Y=$(( CUR_Y + 1 ))
        dropped=$(( dropped + 1 ))
    done
    debug_event "hard drop: ${dropped} row(s) to y=${CUR_Y}"
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
            # Restart the gravity and play-time clocks so a long pause is
            # counted neither as elapsed fall time nor as play time (on
            # pausing PLAY_LAST is moot; on resuming it must be "now").
            play_clock_resume
            DIRTY=1
            ;;
        "${KEY_QUIT}"|ESC)
            # Since 0.12.0 the quit key no longer aborts the round on
            # the spot (issue #12): the pause menu asks whether to
            # resume, suspend the round into the main menu or end it
            # (lib/menu.sh sets GAME_EXIT/GAME_SUSPENDED accordingly).
            debug_event "pause menu opened"
            menu_pause
            # The menu overdrew the game screen and consumed time: force
            # a full repaint (the diff renderer cannot know what the menu
            # put on screen) and restart the gravity and play-time clocks
            # (the time spent in the menu is not play time). Return so the
            # menu's confirmation key (Enter/space) is not applied to the
            # game as well.
            play_clock_resume
            RENDER_FULL=1
            DIRTY=1
            return 0
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
            # Soft drop earns no points (cleared rows are the only
            # score source); it just pulls the piece down early.
            step_down
            now_ms
            LAST_FALL="${NOW_MS}"
            ;;
        UP|SPACE|"${KEY_HARD}")
            hard_drop
            ;;
        # CHANGE 2026-07-30 (user decision): w replaced 2 as the fixed
        # secondary hold key. It sits below the rotation keys a/d on the
        # left hand and is free since the hard drop gave up its letter.
        w|"${KEY_HOLD}")
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
    CLEARED_TOTAL=0
    ROW_CREDIT=0
    GOLD_COUNT=0
    SILVER_COUNT=0
    ROWHAMMER_COUNT=0
    PIECE_COUNT=0
    HOLD_TYPE=""
    HOLD_USED=0
    PAUSED=0
    GAME_OVER=0
    ROUND_RECORDED=0
    LOCK_PENDING=0
    PLAY_MS=0
    update_speed
    spawn_piece
    play_clock_resume
    DIRTY=1
}

# --- Game loop ------------------------------------------------------------
# game_run [MODE]
# One game session; returns to the caller (the menu) when the player
# leaves via the pause menu or the game over screen. MODE "resume"
# continues the round suspended earlier through the pause menu instead
# of starting a fresh one; the round comes back paused so it does not
# run before the player is ready. A round suspended (again) is not
# recorded - the books close only when the round really ends.
game_run() {
    local mode="${1:-new}"
    GAME_EXIT=0
    # The screen still holds a menu: the first frame must repaint it all.
    RENDER_FULL=1
    if [ "${mode}" = "resume" ] && [ "${GAME_SUSPENDED}" -eq 1 ]; then
        GAME_SUSPENDED=0
        PAUSED=1
        debug_event "round resumed from menu (lines=${CLEARED_TOTAL} rows=${ROW_CREDIT})"
        # The round keeps its accumulated PLAY_MS; only restart the clocks
        # so the suspended interval is not counted (it comes back paused).
        play_clock_resume
        DIRTY=1
    else
        # Starting a new round while another one is still suspended
        # ends the suspended one for good; record it first so its row
        # credit is not lost (aborted rounds count, see CLAUDE.md).
        if [ "${GAME_SUSPENDED}" -eq 1 ]; then
            GAME_SUSPENDED=0
            record_round
        fi
        game_reset
    fi

    while [ "${GAME_EXIT}" -eq 0 ]; do
        # read_key also paces the loop via its TICK_S timeout, and it is
        # where a pending SIGWINCH is applied (remeasure, clear, and block
        # on the too-small overlay while the terminal is undersized).
        read_key
        handle_key
        # A resize just happened: read_key cleared the screen (and may have
        # blocked for a while behind the too-small overlay). Repaint and
        # restart the gravity and play-time clocks so the resize interval
        # counts as neither fall time nor play time - like leaving a pause.
        if [ "${REDRAW_PENDING}" -eq 1 ]; then
            REDRAW_PENDING=0
            play_clock_resume
            RENDER_FULL=1
            DIRTY=1
        fi
        if [ "${PAUSED}" -eq 0 ] && [ "${GAME_OVER}" -eq 0 ]; then
            now_ms
            # Accumulate the play time of the segment since the last
            # accounted moment. play_clock_resume set PLAY_LAST to "now"
            # at every resume, so an idle phase never lands in PLAY_MS.
            PLAY_MS=$(( PLAY_MS + NOW_MS - PLAY_LAST ))
            PLAY_LAST="${NOW_MS}"
            if [ "${LOCK_PENDING}" -eq 1 ]; then
                # Resting piece: lock once the grace window has elapsed.
                # Gravity is idle here - the piece cannot fall anyway.
                if (( NOW_MS - TOUCHDOWN_MS >= LOCK_DELAY_MS )); then
                    debug_event "lock delay expired at ${CUR_X},${CUR_Y}"
                    lock_and_next
                fi
            elif (( NOW_MS - LAST_FALL >= FALL_MS )); then
                LAST_FALL="${NOW_MS}"
                step_down
            fi
        fi
        if [ "${DIRTY}" -eq 1 ]; then
            draw_frame
            DIRTY=0
        fi
    done
    # A suspended round is not finished: keep the whole game state
    # (including the ROUND_RECORDED guard) for the "Fortsetzen" entry.
    if [ "${GAME_SUSPENDED}" -eq 1 ]; then
        debug_event "game session suspended (lines=${CLEARED_TOTAL} rows=${ROW_CREDIT} level=${LEVEL})"
        return 0
    fi
    # Quitting a running round to the menu ends it too; the flag makes
    # this a no-op when the game over path already recorded the round.
    record_round
    debug_event "game session end (lines=${CLEARED_TOTAL} rows=${ROW_CREDIT} level=${LEVEL})"
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
    # Load the wonder savegame and derive the wonder state once, so the
    # "Weltwunder" screen and record_round start from a valid state.
    save_load
    wonders_update "${TOTAL_ROW_CREDIT}"
    # Load the all-time statistics; rounds extend them via
    # record_round.
    stats_load
    term_setup

    # While a round is suspended (pause menu, issue #12) the main menu
    # grows a "Fortsetzen" entry at the top; the other entries shift
    # down by one, so the selection is normalized before the dispatch.
    local -a entries
    local choice
    while :; do
        entries=()
        if [ "${GAME_SUSPENDED}" -eq 1 ]; then
            entries+=("Fortsetzen")
        fi
        entries+=("Einzelspieler" "Mehrspieler" "Highscores" \
            "Weltwunder" "Statistik" "Einstellungen" "Beenden")
        menu_run "R O W H A M M E R" "${entries[@]}"
        choice="${MENU_CHOICE}"
        if [ "${GAME_SUSPENDED}" -eq 1 ]; then
            if [ "${choice}" -eq 0 ]; then
                # Resume the suspended round; when it ends for real
                # now, show the construction site like after any other
                # round (when it was suspended again, skip it).
                game_run resume
                if [ "${GAME_SUSPENDED}" -eq 0 ]; then
                    wonder_screen "${TOTAL_ROW_CREDIT}"
                fi
                continue
            elif [ "${choice}" -gt 0 ]; then
                choice=$(( choice - 1 ))
            fi
        fi
        case "${choice}" in
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
                # "Beenden" or ESC on the top level leaves the game. A
                # round still suspended here would end unnoticed, so ask
                # first (it is easy to hit ESC twice and lose a round one
                # only meant to park). Declining returns to the menu, where
                # "Fortsetzen" still picks the round up; confirming ends it
                # and records it, which keeps its row credit (aborted
                # rounds count, see CLAUDE.md).
                if [ "${GAME_SUSPENDED}" -eq 1 ]; then
                    if ! menu_confirm "Wirklich beenden?" \
                        "Ja, beenden" "Nein, zurueck" \
                        "Eine pausierte Runde wartet noch:" \
                        "${CLEARED_TOTAL} Lines, ${ROW_CREDIT} Rows, Level ${LEVEL}." \
                        "" \
                        "Beim Beenden wird sie gewertet und ist danach" \
                        "nicht mehr fortsetzbar."; then
                        continue
                    fi
                    GAME_SUSPENDED=0
                    record_round
                fi
                break
                ;;
        esac
    done

    term_restore
}

main "$@"
