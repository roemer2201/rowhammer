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
#   the player sees which rows scored. The singleplayer menu offers five
#   game modes: the endless "Marathon", "Ultra", a race to
#   clear ULTRA_TARGET_ROWS rows of credit as fast as possible - it ends
#   the moment the target is reached and the play time is the result -
#   "Sprint", its mirror image: as much row credit as possible within
#   SPRINT_TIME_MS, ending when the time is up - "Time Attack",
#   which starts with TIME_ATTACK_START_MS on a clock running backwards
#   and pays TIME_ATTACK_ROW_MS back per row of credit, so the run lasts
#   as long as it is kept fed and the rows are the result - and
#   "Hochwasser", Marathon under a rising floor: every FLOOD_INTERVAL_MS
#   a full row with a single gap is pushed in from below, and the round
#   lasts until the stack reaches the ceiling. Each mode
#   keeps a highscore list of its own (lib/highscore.sh); of the two
#   fixed-goal modes only successful runs are recorded, while every Time
#   Attack and every Hochwasser round is - their rows are the same
#   achievement whether the clock, the water or the stack ended them.
#   The play screen is one fixed
#   48x22 block centered in the terminal: the hold piece with the round
#   counters below it on the left, the board in the middle and the three
#   upcoming pieces top right; pause and game
#   over appear as a box over the board. Frames are pushed out
#   incrementally - only the lines that changed are rewritten (see
#   lib/render.sh); --render-mode full switches that off and rewrites
#   the whole block per frame, for terminals on which the incremental
#   update draws wrong. Menus, info screens and prompts are centered the
#   same way (render_menu_frame), so they line up with the play screen
#   instead of sitting in the top left corner. Pressing the quit key (x/ESC) in
#   a running round opens a pause menu instead of aborting: resume,
#   restart the round in the same mode,
#   suspend the round into the main menu (it stays resumable via the
#   "Fortsetzen" entry offered in the main menu and in the singleplayer
#   menu) or end it; a round is recorded only when it really ends -
#   which a given-up round does, so a restart banks it first. The two
#   entries that discard the round ask back before they act.
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
#   Interface language, player name, color theme and key bindings are
#   configurable in the settings menu and persisted to a user config
#   file. Every text the player sees - menus, the manual, the HUD
#   labels, the result box, the tables, the reset dialog and this
#   --help output - comes from a translation table (lib/i18n.sh, one
#   file per language below lib/lang/); --lang picks German or English,
#   and its default "auto" takes the language from the locale.
#   Blocks render in the basic 8/16-color ANSI palette or, when
#   the terminal supports it (auto-detected, overridable via
#   --color-mode), in an extended xterm 256-color palette; the color
#   theme (--color-theme: guideline, classic, mono, colorblind) picks
#   which colors the pieces and gold/silver squares use. With colors off
#   (--no-color / NO_COLOR) each piece type draws its own two-character
#   glyph and the gold/silver squares use distinct non-letter glyphs, so
#   blocks stay tellable apart. All game data (config, persistent top-10 highscore list,
#   the savegame and the all-time statistics) lives in one data
#   directory, by default
#   ~/.config/rowhammer. A round that is about to enter a list asks for
#   the name it is filed under (since 0.45.0, user request): the name
#   from the settings comes preselected, so keeping it is one Enter and
#   changing it is typing over it; what is typed applies to that round
#   only. Finished rounds enter the highscore list of
#   their mode, which the
#   main menu shows (two lines per entry: rows, gold/silver squares,
#   rowhammers, pieces placed and their rate in pieces per minute, play
#   time and date) and
#   whose rank appears on the game over screen; the row credit decides
#   the ranking of the Marathon, the Sprint and the Time Attack list,
#   the play time that
#   of the Ultra one, so the "Highscores" menu entry asks for the mode
#   before drawing
#   the list. The HUD also shows the running round's play time (paused
#   time excluded) and the pieces it has placed.
#   Every round also feeds persistent statistics (cleared rows, bonus
#   rows, gold/silver squares built, rowhammers, pieces placed and time
#   played, plus the results of
#   the last three rounds with their play date), shown via the
#   "Statistik" main menu entry. Since 0.47.0 (user request) every one
#   of those counters exists a second time per game mode, so the entry
#   asks which set to show first - the all-time counters over every
#   round ever played, or one mode's own; the rounds played per mode
#   and, for the timed ones, how many reached their goal are part of
#   both. The highscore list shows each entry's date as well.
#   Every round is also recorded as a demo (lib/demo.sh) and can be
#   watched again from the "Demos" main menu entry, which lists the
#   recordings and plays or deletes the one picked. Recorded are the
#   moves, the gravity steps and the piece stream, not the screen, so a
#   replay runs the round through the real game logic again - it is
#   small, independent of the terminal and the render mode, and can be
#   paused and played between a quarter and four times its speed. A
#   replay is never banked into highscores, wonder progress or
#   statistics.
#   The "Anleitung" main menu entry explains the game on seven screens,
#   paged with the left/right arrow keys (wrapping at both ends):
#   the rules, the current key bindings, hold and preview, the
#   gold/silver squares with their row bonus, the wonder construction,
#   the four game modes, how their highscore lists are kept and the
#   demos (menu_help in lib/menu.sh).
#   --reset resets persistent data on purpose: the config file, the
#   statistics, the highscore lists, the wonder savegame, the demo
#   recordings or all of them
#   at once. Nothing is deleted - each file is moved to
#   <file>-YYYYMMDDhhmmss.bak beside it, so a reset can be undone. It
#   runs before the game starts, asks for confirmation on a terminal
#   (unless --force answers for the caller) and then exits instead of
#   entering the menu.
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
#   2. Verify the bash version (>= 4).
#   3. Source the library modules (debug, config, i18n, demo, pieces,
#      board, squares, highscore, save, stats, wonders, input, render,
#      menu).
#   4. Read the config file and resolve the interface language
#      (default < config < ROWHAMMER_LANG < --lang), then load its text
#      table - everything printed from here on is translated, --help
#      and the reset report included. Print the help and exit if
#      -h/--help was given.
#   5. Rename a leftover "highscore" file to "highscore-marathon" once
#      (the Marathon list names its mode like the other four since
#      0.51.0), ahead of the reset so it works on the current name.
#   6. Carry out --reset if requested: move the selected persistent
#      files below the data directory aside to timestamped .bak copies
#      and exit, without ever touching the terminal.
#   7. Verify the remaining prerequisites (interactive terminal, minimum
#      size; the size is rechecked live via SIGWINCH while running).
#   8. Resolve the remaining settings with precedence default < config
#      file < env < CLI and validate them.
#   9. Install the cleanup trap, start the debug logs (when --debug is
#      set), load the highscore lists, the savegame and the statistics
#      and enter the alternate screen in raw input mode (echo and
#      canonical mode off for the whole session).
#  10. Run the main menu loop; the singleplayer entry picks a game mode and
#      starts the game loop
#      (input, gravity, locking, square detection, row flash, line
#      clearing, rendering), finished rounds are recorded - under the
#      name asked for at the end of the round - in the
#      highscore list of their mode, their row credit is banked into the wonder
#      savegame and their counters into the statistics file,
#      settings changes are written back to the config file. A round
#      suspended via the pause menu returns to the main menu
#      unrecorded and continues via its "Fortsetzen" entry; leaving the
#      game while such a round waits asks for confirmation first. A
#      round restarted via the pause menu is recorded like any other
#      abandoned one before the fresh round replaces it.
#  11. Restore the terminal on exit and close the debug logs.
#
# Usage:
#   rowhammer.sh [--seed N] [--name NAME] [--lang de|en|auto]
#                [--data-dir DIR] [--no-color]
#                [--color-mode auto|basic|extended]
#                [--color-theme guideline|classic|mono|colorblind]
#                [--render-mode partial|full] [--demo-record on|off]
#                [--reset config|stats|highscore|save|demo|all] [--force]
#                [--debug] [--debug-dir DIR] [-h|--help]
#
# Version: 0.53.0  (2026-08-04)

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
ROWHAMMER_VERSION="0.53.0"

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
# Rendering mode: "partial" (the default) rewrites only the lines that
# actually changed, "full" rewrites the whole block on every frame the
# way the renderer worked before 0.22.0. Partial is what a normal run
# wants - it is the cheaper mode by roughly half the time and a
# fourteenth of the output per frame; full exists for terminals and
# multiplexers on which the incremental update draws incorrectly and for
# reading whole frames out of a debug frame log. Like the color mode it
# is not a config file setting: it is a per-terminal workaround, not a
# taste, and it must stay reachable without editing a file when the
# screen is the thing that is broken. Precedence default < env < CLI.
RENDER_MODE="${ROWHAMMER_RENDER_MODE:-partial}"
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
# Reset target: which persistent files below DATA_DIR to delete before
# the game would start ("" = no reset, the normal case). Deliberately
# not a config file setting - the config file is one of the things a
# reset deletes, so honoring it from there would let a file order its
# own removal on every start. Precedence is therefore default < env <
# CLI, like the data directory and the debug switches.
RESET_OPT="${ROWHAMMER_RESET:-}"
# The accepted reset targets. "highscore" covers every list (the endless
# one, the Ultra and the Sprint list) - they are the same kind of data
# and a caller asking to drop "the highscores" means all of them. "all"
# includes the
# savegame, i.e. the wonder progress: it is the plain reading of the
# word, and "save" exists as its own target for the case where only the
# wonder progress is meant while config, stats and highscores stay
# (CLAUDE.md 4.5 left that choice open; this is the decision). "demo"
# (the recorded rounds) follows the same rule: it is in "all" and has a
# target of its own, because it is by far the bulkiest of these and the
# one most likely to be cleared on its own.
RESET_TARGETS=(config stats highscore save demo all)
# Answer confirmation questions with "yes" instead of asking. Today that
# is the --reset question; the switch is written as a general one (it may
# be combined with any other option and is simply without effect where
# nothing is asked) so a future prompt does not need a second flag. Kept
# out of the config file for the same reason as the reset target itself:
# a stored "never ask me again" would defeat the safety net.
FORCE_OPT="${ROWHAMMER_FORCE:-0}"
PLAYER_NAME="Player"
# Demo recording on/off ("on"/"off"). Unlike the render or color mode
# this is a taste, not a property of the terminal, so it is a config file
# setting like the player name and the color theme: it starts from this
# default, is overridden by config_load and then by the env/CLI blocks
# after sourcing, and the settings menu writes it back. Recording a round
# never changes how it plays (see lib/demo.sh), it only costs a few
# kilobytes on a RAM disk while the round runs.
DEMO_RECORD="on"
# Color theme: maps piece and gold/silver colors to a named scheme
# (COLOR_THEMES in lib/pieces.sh). Like the key bindings it is a
# config-driven setting, so it starts from this default and is then
# overridden by config_load and the env/CLI blocks after sourcing.
COLOR_THEME="guideline"
# Interface language (lib/i18n.sh): a code from I18N_LANGS or "auto",
# which takes the language from the POSIX locale variables. A
# config-driven setting like the color theme and the demo recording -
# which language somebody reads is a property of the person, not of the
# terminal - so it starts from this default and is then overridden by
# config_load and the env/CLI blocks below. "auto" as the default,
# because a game that ships two languages and ignores the locale it is
# started in supports neither of them properly; a locale that names no
# language this game speaks falls back to German, the language its menus
# were written in (I18N_FALLBACK_LANG).
LANGUAGE="auto"
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
CLI_DEMO_RECORD=""
CLI_LANGUAGE=""
# -h/--help only raises this flag; the text itself is printed further
# down, once the modules are sourced and the language is resolved. The
# help is one of the texts the translation layer covers (lib/i18n.sh),
# and the language it has to be written in is only known after the
# config file, the environment and the rest of the command line have
# been read.
HELP_OPT=0

# Print usage information in the resolved interface language. The text
# itself lives in the language file (i18n_usage_text, lib/lang/*.sh):
# it is long, it is printed exactly once, and a heredoc per language
# keeps it readable as the block of prose it is.
usage() {
    i18n_usage_text
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

# reset_opt_required
# Reject an empty --reset argument during parsing. An unset RESET_OPT
# means "no reset", so "--reset ''" would otherwise start the game as if
# nothing had been asked for - the one case the shared validation below
# cannot tell apart from the option being absent.
reset_opt_required() {
    if [ -z "${RESET_OPT}" ]; then
        printf '%s: --reset expects one of: %s\n' \
            "${SCRIPT_NAME}" "${RESET_TARGETS[*]}" >&2
        exit 2
    fi
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
        --render-mode)
            if [ "$#" -lt 2 ]; then
                printf '%s: option %s requires an argument\n' "${SCRIPT_NAME}" "${1}" >&2
                exit 2
            fi
            RENDER_MODE="${2}"
            shift 2
            ;;
        --render-mode=*)
            RENDER_MODE="${1#*=}"
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
        --lang)
            if [ "$#" -lt 2 ]; then
                printf '%s: option %s requires an argument\n' "${SCRIPT_NAME}" "${1}" >&2
                exit 2
            fi
            CLI_LANGUAGE="${2}"
            shift 2
            ;;
        --lang=*)
            CLI_LANGUAGE="${1#*=}"
            shift
            ;;
        --demo-record)
            if [ "$#" -lt 2 ]; then
                printf '%s: option %s requires an argument\n' "${SCRIPT_NAME}" "${1}" >&2
                exit 2
            fi
            CLI_DEMO_RECORD="${2}"
            shift 2
            ;;
        --demo-record=*)
            CLI_DEMO_RECORD="${1#*=}"
            shift
            ;;
        --reset)
            if [ "$#" -lt 2 ]; then
                printf '%s: option %s requires an argument\n' "${SCRIPT_NAME}" "${1}" >&2
                exit 2
            fi
            RESET_OPT="${2}"
            reset_opt_required
            shift 2
            ;;
        --reset=*)
            RESET_OPT="${1#*=}"
            reset_opt_required
            shift
            ;;
        --force)
            FORCE_OPT=1
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
            # Only noted here: the help text is translated (lib/i18n.sh)
            # and the language is not resolved until the config file, the
            # environment and the rest of this command line have been
            # read, which happens below.
            HELP_OPT=1
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            # CHANGE 2026-08-04: a wrong option no longer dumps the whole
            # usage text to STDERR. That text is translated now and is
            # therefore unavailable at this point - and pointing at
            # --help is what the reader needs anyway, since the error
            # itself already says what was wrong.
            printf '%s: unknown option: %s\n' "${SCRIPT_NAME}" "${1}" >&2
            printf "Try '%s --help' for the list of options.\n" "${SCRIPT_NAME}" >&2
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
case "${RENDER_MODE}" in
    partial|full) : ;;
    *)
        printf '%s: --render-mode expects partial or full, got: %s\n' \
            "${SCRIPT_NAME}" "${RENDER_MODE}" >&2
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
if [ -n "${RESET_OPT}" ]; then
    _reset_ok=0
    for _target in "${RESET_TARGETS[@]}"; do
        if [ "${_target}" = "${RESET_OPT}" ]; then
            _reset_ok=1
            break
        fi
    done
    if [ "${_reset_ok}" -eq 0 ]; then
        printf '%s: --reset expects one of: %s, got: %s\n' \
            "${SCRIPT_NAME}" "${RESET_TARGETS[*]}" "${RESET_OPT}" >&2
        exit 2
    fi
    unset _reset_ok _target
fi
case "${FORCE_OPT}" in
    0|1) : ;;
    *)
        printf '%s: ROWHAMMER_FORCE expects 0 or 1, got: %s\n' \
            "${SCRIPT_NAME}" "${FORCE_OPT}" >&2
        exit 2
        ;;
esac

# --- Prerequisites --------------------------------------------------------
# Associative arrays (piece tables) and fractional read timeouts need
# bash 4; EPOCHREALTIME (bash 5) is optional and has a fallback.
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    die "bash >= 4.0 is required, this is bash ${BASH_VERSION}"
fi
# CHANGE 2026-08-02: the tty check moved below the library modules and
# the --reset block. --reset only deletes files and prints a report, so
# it must work from a script or a CI job without a terminal - and it
# needs the file name constants the modules define.

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
# demo comes before pieces: queue_fill (lib/pieces.sh) reads its state to
# take the piece stream from a recording during playback, and the
# renderer reads it as well, so the flags have to exist before either
# module runs.
for _lib in debug config i18n demo pieces board squares highscore save stats wonders input render menu; do
    if [ ! -r "${SCRIPT_DIR}/lib/${_lib}.sh" ]; then
        die "Missing library file: ${SCRIPT_DIR}/lib/${_lib}.sh"
    fi
    # shellcheck source=/dev/null
    . "${SCRIPT_DIR}/lib/${_lib}.sh"
done
unset _lib

# --- Language resolution (default < config < env < CLI) -------------------
# Ahead of everything else that talks to the user, because everything
# else that talks to the user is translated: the --help text, the reset
# dialog and, later on, the menus. That is also why config_load runs
# here and not down in the settings block - the config file is where the
# chosen language is stored, and reading it twice to keep the blocks
# apart would be a fork of the same file for nothing. The remaining
# config-driven settings are resolved as before, further down; loading
# them early is harmless, since nothing reads them until then.
config_load
LANGUAGE="${ROWHAMMER_LANG:-${LANGUAGE}}"
if [ -n "${CLI_LANGUAGE}" ]; then
    LANGUAGE="${CLI_LANGUAGE}"
fi
# Validated like every other setting that comes out of a file, the
# environment or the command line. The message stays English: it is a
# diagnostic on STDERR (script conventions) and, more to the point, the
# language it would have to be written in is exactly what is broken.
if ! i18n_is_valid "${LANGUAGE}"; then
    die "Invalid language: '${LANGUAGE}' (allowed: auto, ${I18N_LANGS[*]})"
fi
i18n_init

if [ "${HELP_OPT}" -eq 1 ]; then
    usage
    exit 0
fi

# --- One-time rename of the Marathon highscore file -----------------------
# "highscore" became "highscore-marathon" in 0.51.0 (user decision), so
# the list names its mode like the four others do. This has to run
# before the reset block below: --reset highscore works from the names
# the modules own, and a file still sitting under the old name would be
# reported as absent and then survive its own reset. It is also before
# anything reads a list, so the game only ever sees the current name.
highscore_migrate_legacy

# --- Reset of persistent data (runs before the game starts) ---------------
# How often reset_run retries when a backup of the current second is
# already there. One wait is normally enough (the next second brings a
# free name); more attempts only matter if the clock stands still or
# jumps back, and after these the reset gives up instead of looping.
RESET_STAMP_ATTEMPTS=3

# reset_run TARGET
# Reset the persistent files TARGET stands for below DATA_DIR and report
# what happened on STDOUT. The file names come from the library modules
# that own them, so a renamed file never leaves the reset behind.
# CHANGE 2026-08-02 (user decision): nothing is deleted any more. Every
# affected file is moved aside to "<file>-YYYYMMDDhhmmss.bak" in the same
# directory, so a reset stays undoable - a mistyped --reset all used to
# cost the wonder progress of every round ever played. Should a backup of
# that very second already exist, the reset ran twice within one second;
# it then waits for the next second (sleep 1) and tries again with a
# fresh timestamp rather than overwriting the older backup.
# This runs before anything touches the terminal: no alternate screen, no
# raw input mode - which is why the report is plain lines and the
# confirmation is a plain read instead of menu_confirm, which needs both.
# Like menu_confirm the question defaults to declining. Returns 0 after a
# completed or a declined reset; a file that exists but cannot be moved
# aside is a hard error.
reset_run() {
    local target="${1}"
    local -a names=()
    local name path backup answer
    local stamp="" try attempt collision
    local moved=0 missing=0

    case "${target}" in
        config)    names=("${CONFIG_NAME}") ;;
        stats)     names=("${STATS_FILE_NAME}") ;;
        highscore) names=("${HS_FILE_NAME}" "${HSU_FILE_NAME}"
                          "${HSS_FILE_NAME}" "${HSA_FILE_NAME}"
                          "${HSF_FILE_NAME}") ;;
        save)      names=("${SAVE_FILE_NAME}") ;;
        # The only target that is a directory rather than a file. It is
        # moved aside as a whole, which the loop below does without
        # knowing the difference (its -e test and its mv work on both) -
        # so all recordings of a reset stay together in one .bak
        # directory and can be moved back in one go.
        demo)      names=("${DEMO_DIR_NAME}") ;;
        all)       names=("${CONFIG_NAME}" "${STATS_FILE_NAME}"
                          "${HS_FILE_NAME}" "${HSU_FILE_NAME}"
                          "${HSS_FILE_NAME}" "${HSA_FILE_NAME}"
                          "${HSF_FILE_NAME}"
                          "${SAVE_FILE_NAME}" "${DEMO_DIR_NAME}") ;;
        # Unreachable: the value is validated against RESET_TARGETS
        # right after the argument parsing. Kept so a new target added
        # there without a case here fails loudly instead of silently
        # resetting nothing.
        *)         die "Unhandled reset target: ${target}" ;;
    esac

    printf "${I18N[reset_affects]}\n" "${target}" "${DATA_DIR}"
    for name in "${names[@]}"; do
        path="${DATA_DIR}/${name}"
        if [ -e "${path}" ]; then
            printf '  %s\n' "${path}"
        else
            printf '  %s %s\n' "${path}" "${I18N[reset_absent]}"
        fi
    done
    printf '%s\n' "${I18N[reset_note]}"

    # Ask first - but only when someone is there to answer and --force
    # did not answer already. Without a tty (scripting, CI) a waiting
    # read would hang the caller, so the reset is carried out right away;
    # asking for it non-interactively is explicit enough.
    if [ "${FORCE_OPT}" -eq 0 ] && [ -t 0 ] && [ -t 1 ]; then
        # The declining answer is the default, so it is spelled first and
        # capitalized - a reset must never be the path of least
        # resistance (same rule as menu_confirm's preselected "no").
        printf "${I18N[reset_confirm]}" "${target}"
        # EOF (Ctrl-D) leaves the answer empty and therefore declines.
        read -r answer || answer=""
        # The accepting answers stay the English y/yes in every language:
        # the prompt spells the two letters out as "[N/y]", and a
        # scripted caller that answers "y" must not depend on the
        # language the terminal happens to run in.
        case "${answer}" in
            y|Y|yes|YES) : ;;
            *)
                printf '%s\n' "${I18N[reset_aborted]}"
                return 0
                ;;
        esac
    fi

    # One timestamp for the whole run, so the backups of a "--reset all"
    # belong together visibly. A backup of that second already sitting
    # there means this very reset just ran; waiting a second yields a
    # free name instead of clobbering that first backup.
    for (( attempt = 1; attempt <= RESET_STAMP_ATTEMPTS; attempt++ )); do
        try="$(date +%Y%m%d%H%M%S)"
        collision=0
        for name in "${names[@]}"; do
            path="${DATA_DIR}/${name}"
            if [ -e "${path}" ] && [ -e "${path}-${try}.bak" ]; then
                collision=1
                break
            fi
        done
        if [ "${collision}" -eq 0 ]; then
            stamp="${try}"
            break
        fi
        printf '%s\n' "${I18N[reset_wait]}"
        sleep 1
    done
    if [ -z "${stamp}" ]; then
        die "Could not find a free backup timestamp after ${RESET_STAMP_ATTEMPTS} attempts in ${DATA_DIR} (is the clock going backwards?)"
    fi

    for name in "${names[@]}"; do
        path="${DATA_DIR}/${name}"
        # A file that is already gone is not an error: the goal of the
        # reset is reached for it, and there is nothing to back up.
        if [ ! -e "${path}" ]; then
            missing=$(( missing + 1 ))
            continue
        fi
        backup="${path}-${stamp}.bak"
        # Plain mv, no -f: the loop above made sure the backup name is
        # free, and overwriting an existing backup is exactly what this
        # must never do.
        if ! mv -- "${path}" "${backup}"; then
            die "Failed to move aside: ${path}"
        fi
        printf "${I18N[reset_moved]}\n" "${path}" "${backup}"
        moved=$(( moved + 1 ))
    done
    # The line the user asked for, kept short and always the same, so it
    # is easy to grep for in a script. The counts follow on their own
    # line: a reset of a target whose files never existed is a success
    # too (the goal is reached), and the numbers say which case it was.
    printf '%s\n' "${I18N[reset_done]}"
    printf "${I18N[reset_summary]}\n" \
        "${target}" "${moved}" "${missing}"
    return 0
}

if [ -n "${RESET_OPT}" ]; then
    reset_run "${RESET_OPT}"
    exit 0
fi

# The game itself needs a terminal (the reset above does not, see the
# prerequisites section).
if [ ! -t 0 ] || [ ! -t 1 ]; then
    die "This game needs an interactive terminal (stdin/stdout must be a tty)"
fi

# Terminal size check, now that term_measure (lib/input.sh) is available.
# It fills TERM_ROWS/TERM_COLS and sets TERM_TOO_SMALL against the minimum
# above; a too-small terminal at startup is a hard error, while one that
# shrinks later is handled live via SIGWINCH.
term_measure
if [ "${TERM_TOO_SMALL}" -eq 1 ]; then
    die "Terminal too small: need at least ${MIN_TERM_COLS}x${MIN_TERM_ROWS}, got ${TERM_COLS}x${TERM_ROWS}"
fi

# --- Settings resolution (default < config < env < CLI) -------------------
# The config file was already read by the language resolution above (it
# holds the language too), so its values are in place here.

# Environment variables override the config file.
PLAYER_NAME="${ROWHAMMER_PLAYER_NAME:-${PLAYER_NAME}}"
COLOR_THEME="${ROWHAMMER_COLOR_THEME:-${COLOR_THEME}}"
DEMO_RECORD="${ROWHAMMER_DEMO_RECORD:-${DEMO_RECORD}}"
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
if [ -n "${CLI_DEMO_RECORD}" ]; then
    DEMO_RECORD="${CLI_DEMO_RECORD}"
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
# Spelled-out words rather than 0/1: this one is written into the config
# file by the settings menu, where "DEMO_RECORD='on'" says what it means
# without a lookup. Validated like every other config value, because the
# file, the environment and the command line are all user input.
case "${DEMO_RECORD}" in
    on|off) : ;;
    *) die "Invalid demo recording setting: '${DEMO_RECORD}' (allowed: on, off)" ;;
esac
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
# Set by the pause menu's "Neustarten" entry (2026-08-03, user request)
# and cleared by handle_key, which does the actual restart. A flag rather
# than a direct game_reset in the menu for the same reason GAME_EXIT and
# GAME_SUSPENDED are flags: lib/menu.sh decides, rowhammer.sh acts - and
# the running round has to be recorded before its counters are wiped.
GAME_RESTART=0
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
# Game mode of the running round, one of "marathon" (endless, the classic
# round; CHANGE 2026-07-31, user decision: renamed from "normal"/"Normales
# Spiel" to match the term used by other Tetris games for the endless
# mode), "ultra" (race: clear ULTRA_TARGET_ROWS of row credit as fast as
# possible) or "sprint" (the inverse race: as much row credit as possible
# within SPRINT_TIME_MS). Round state like the counters above: it is
# chosen in the singleplayer menu, set by game_reset and kept across a
# suspend/resume, so a resumed round always comes back in the mode it was
# started in. The mode decides which highscore list the round is recorded
# in and whether the HUD shows the goal counters (render_pane_left).
# "timeattack" (2026-08-03, user request) is the fourth: a countdown that
# the player extends by playing - see TIME_ATTACK_START_MS below.
# "flood" (2026-08-04, user request) is the fifth: Marathon with a floor
# that rises every FLOOD_INTERVAL_MS - see there.
GAME_MODE="marathon"
# Row credit an Ultra run has to reach. Weighted rows ("Rows", see the
# scoring note below), not physical lines: in this game "cleared rows"
# has meant the weighted figure everywhere else too (wonder progress,
# statistics), and it makes the gold/silver squares - the mechanic the
# game is built around - the fast way to the goal instead of dead weight.
# An adjustable game-feel constant like LEVEL_SPEEDS and LOCK_DELAY_MS;
# the menu entry and the HUD read it, but the usage text above spells it
# out (its heredoc is unexpanded, and it is printed before this line ever
# runs) - so keep that one number in sync when tuning this.
ULTRA_TARGET_ROWS=150
# Time a Sprint run gets, in milliseconds: three minutes of play time
# (pauses excluded, like everything else measured in PLAY_MS - see
# play_clock_tick), in which as much row credit as possible is to be
# scored. The mirror image of Ultra: there the rows are fixed and the
# time is the result, here the time is fixed and the rows are. Weighted
# rows again, for the same reason as above - the gold/silver squares
# should be the fast way to a good result, not dead weight.
# An adjustable game-feel constant like ULTRA_TARGET_ROWS; the menu
# entries and the HUD read it, but the usage text above spells the three
# minutes out (its heredoc is unexpanded and is printed before this line
# ever runs), so keep that wording in sync when tuning this.
SPRINT_TIME_MS=180000
# Time Attack (user request): the round starts with TIME_ATTACK_START_MS
# of play time running backwards, and every row of credit scored buys
# TIME_ATTACK_ROW_MS more. The run therefore lasts exactly as long as it
# is kept fed - it ends when the clock hits zero (or, like any round,
# when the stack tops out). Weighted rows again, for the reason Ultra
# and Sprint use them: the gold/silver squares are what the game is
# built around, and here they are literally the way to buy time.
# Adjustable game-feel constants like ULTRA_TARGET_ROWS and
# SPRINT_TIME_MS; the menu entries, the HUD and the manual read them,
# but the usage text above spells the minute and the second out (its
# heredoc is unexpanded and is printed before this line ever runs), so
# keep that wording in sync when tuning these.
TIME_ATTACK_START_MS=60000
TIME_ATTACK_ROW_MS=1000
# The Time Attack budget as of the last time it was computed: the start
# time plus what the rows scored so far have bought (time_attack_budget).
# A global instead of a computed-on-the-spot expression because both the
# game loop and the HUD need the same number every tick.
TIME_ATTACK_BUDGET_MS="${TIME_ATTACK_START_MS}"
# Hochwasser (2026-08-04, user request): every FLOOD_INTERVAL_MS of play
# time a full row with a single gap is pushed in from below and the whole
# board moves up by one row (flood_raise, board_flood_row in
# lib/board.sh). Everything else is Marathon - the round ends when a
# piece has no room left, and its rows are its score. There is no goal to
# reach here; the water always wins in the end, and the question is only
# how long and how well the player keeps up with it.
# The interval is measured in play time (PLAY_MS) like every other clock
# in this game, so a pause never lets the water in. Twenty seconds is the
# starting value the mode was asked for; an adjustable game-feel constant
# like ULTRA_TARGET_ROWS and SPRINT_TIME_MS, read by the menu entry, the
# HUD and the manual - but the usage text above spells the twenty seconds
# out (its heredoc is unexpanded and is printed before this line ever
# runs), so keep that wording in sync when tuning this.
FLOOD_INTERVAL_MS=20000
# Play time the next flood row is due at (round state, reset per round
# and carried across a suspend/resume like PLAY_MS itself).
FLOOD_NEXT_MS="${FLOOD_INTERVAL_MS}"
# Set when a round ended by reaching its mode's goal instead of by
# topping out: for Ultra that is the row target, for Sprint surviving
# the full time, for Time Attack running the clock down to zero (the
# regular end of such a run - it is the one ending that is not a
# top-out). Both end the round (GAME_OVER=1 drives the end-of-round
# handling), this flag only tells the two apart - for the box over the
# board (render_status_box) and for record_round, which enters an Ultra
# or Sprint run in its list only when it really got there (a Time Attack
# run is recorded either way, see there).
GOAL_REACHED=0

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

# fmt_duration_ms MILLISECONDS: format a millisecond duration as
# MM:SS.mmm into the global FMT_DURATION_MS. Used where the tenths and
# hundredths actually matter - the Ultra mode, where the play time is the
# score and two attempts routinely land in the same second (the Ultra
# highscore list therefore stores milliseconds, see lib/highscore.sh).
# fmt_duration's MM:SS stays the format for everything else.
FMT_DURATION_MS="00:00.000"
fmt_duration_ms() {
    local ms="${1}"
    printf -v FMT_DURATION_MS '%02d:%02d.%03d' \
        "$(( ms / 60000 ))" "$(( ms / 1000 % 60 ))" "$(( ms % 1000 ))"
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

# round_hash VALUE...
# Build the short identifier of a finished round into the global
# ROUND_HASH: eight hex digits over the values handed in. It is what ties
# the round's highscore entry to its demo recording - the entry stores it
# as its last field (lib/highscore.sh), the recording carries it in its
# file name (lib/demo.sh), and the pruning of old recordings keeps every
# file whose hash is still on one of the lists.
# The algorithm is FNV-1a (32 bit), written out here rather than shelled
# out to cksum or sha256sum: it costs no fork, it cannot differ between
# systems the way a checksum tool's variants can, and eight hex digits
# are short enough for a file name. Collision resistance against an
# attacker is not a goal and not needed - the values include the round's
# play time in milliseconds, so two different rounds colliding is not a
# case that occurs in practice, and a collision would at worst keep one
# recording longer than necessary.
# Bash arithmetic is 64 bit, so masking back to 32 bits after each step
# keeps the intermediate product (at most 2^56) well inside its range.
ROUND_HASH=""
round_hash() {
    local s="$*" i c
    local h=2166136261
    for (( i = 0; i < ${#s}; i++ )); do
        printf -v c '%d' "'${s:i:1}"
        h=$(( (h ^ c) & 0xFFFFFFFF ))
        h=$(( (h * 16777619) & 0xFFFFFFFF ))
    done
    printf -v ROUND_HASH '%08x' "${h}"
    return 0
}

# play_clock_tick: account the play time elapsed since the last accounted
# moment into PLAY_MS (and refresh NOW_MS on the way). The game loop does
# this once per tick; the Ultra mode calls it again at the very moment
# its goal is reached, because a hard drop finishes a run between two of
# those ticks and those milliseconds belong to the run - which in that
# mode is its score. Idempotent: it only ever adds the interval since
# PLAY_LAST, which it then moves to "now".
play_clock_tick() {
    now_ms
    PLAY_MS=$(( PLAY_MS + NOW_MS - PLAY_LAST ))
    PLAY_LAST="${NOW_MS}"
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

# time_attack_budget: refresh TIME_ATTACK_BUDGET_MS, the play time the
# running Time Attack round has bought itself so far - the start time
# plus TIME_ATTACK_ROW_MS per row of credit. Derived from ROW_CREDIT
# instead of accumulated in a counter of its own: the row credit is
# already the one number the whole mode turns on, and a second counter
# fed at every clear could only ever drift away from it.
time_attack_budget() {
    TIME_ATTACK_BUDGET_MS=$(( TIME_ATTACK_START_MS \
        + ROW_CREDIT * TIME_ATTACK_ROW_MS ))
    return 0
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

# round_is_ranked: does the round that just ended enter a highscore list
# at all? Mirrors the two rules that decide it - the per-mode rule of
# record_round below (only a successful Ultra or Sprint run is listed)
# and the "nothing to rank" check inside the list functions themselves
# (lib/highscore.sh ignores a round without rows resp. without a measured
# time). It is the condition for asking for the player's name: a round
# that is filed nowhere has no name to ask for, and everything else it
# still feeds - wonder progress and statistics - is nameless.
round_is_ranked() {
    case "${GAME_MODE}" in
        ultra)  [ "${GOAL_REACHED}" -eq 1 ] && [ "${PLAY_MS}" -gt 0 ] ;;
        sprint) [ "${GOAL_REACHED}" -eq 1 ] && [ "${ROW_CREDIT}" -gt 0 ] ;;
        *)      [ "${ROW_CREDIT}" -gt 0 ] ;;
    esac
}

# round_rank_preview: which place the round that just ended would take in
# the list of its mode, reported in HS_PREVIEW_RANK / HS_PREVIEW_MAX
# (highscore_rank_preview, lib/highscore.sh; 0 = misses the list). Asked
# by the name prompt (prompt_round_name, lib/menu.sh), which runs before
# the entry is written and so cannot read the rank the insert reports.
# Only meaningful for a round round_is_ranked accepts.
#
# It sits next to round_is_ranked because it answers with the same piece
# of knowledge: which number of the round its mode is ranked by - the
# play time for Ultra, the row credit everywhere else. Keeping the two
# together means a new mode has one place to be entered, not two.
round_rank_preview() {
    case "${GAME_MODE}" in
        ultra) highscore_rank_preview "${GAME_MODE}" "${PLAY_MS}" ;;
        *)     highscore_rank_preview "${GAME_MODE}" "${ROW_CREDIT}" ;;
    esac
}

# record_round: close the books on a finished round, at most once
# per round: enter it into the highscore list of its mode, bank its row
# credit
# into the persistent wonder counter (savegame) and its counters into
# the all-time statistics (lib/stats.sh). Runs right when the
# game over triggers, so the game over box can show the achieved
# rank (HS_LAST_RANK / HSU_LAST_RANK / HSS_LAST_RANK / HSA_LAST_RANK /
# HSF_LAST_RANK), and again as a
# catch-all when the player quits a running round to the menu.
# The five lists are separate and a round enters exactly one of them (see
# lib/highscore.sh): an Ultra run is ranked by time and would otherwise
# push endless rounds out of a top ten it cannot be compared against, and
# a Sprint, Time Attack or Hochwasser run - a fixed three minutes resp.
# only as much time as it earns itself resp. as long as it holds the
# water off - ranks by rows like the endless list but
# against a completely different yardstick.
# Wonder progress and statistics do not care about the mode - those rows
# were really cleared, and per the concept even an aborted round counts.
record_round() {
    # A replayed round is not a round: it books nothing into the
    # highscore lists, the wonder counter or the statistics, and it is
    # not recorded as a demo either. The guard sits here rather than at
    # the call sites because a replay reaches this function through the
    # very game functions it replays (lock_and_next on the Ultra goal,
    # spawn_piece on a blocked spawn).
    if [ "${DEMO_PLAYING}" -eq 1 ]; then
        return 0
    fi
    if [ "${ROUND_RECORDED}" -eq 1 ]; then
        return 0
    fi
    ROUND_RECORDED=1
    # Which name this round is filed under (2026-08-03, user request).
    # The name from the settings is the default and the prompt offers it
    # preselected, so keeping it costs one Enter; what is typed instead
    # applies to this round only and does not change the settings (see
    # prompt_round_name in lib/menu.sh). Asked only for a round that
    # really enters a list - and asked here, before the entry is written,
    # because this is where the name goes in and where the rank shown by
    # the result box is decided.
    local name="${PLAYER_NAME}"
    if round_is_ranked; then
        prompt_round_name
        name="${ROUND_NAME}"
    fi
    # The round's identifier, computed once and handed to both books it
    # appears in: the highscore entry stores it as its last field, and
    # the demo recording carries it in its file name, which is what lets
    # the demo pruning keep the recording of a run that still holds a
    # highscore place (see round_hash, lib/highscore.sh, lib/demo.sh).
    # The values are the round's own results, including the play time in
    # milliseconds - two different rounds cannot realistically produce
    # the same ones. Computed after the name prompt above and over the
    # name that is really going to be stored, so the identifier describes
    # the entry as it ends up on the list.
    round_hash "${GAME_MODE}" "${name}" "${PLAY_MS}" "${ROW_CREDIT}" \
        "${CLEARED_TOTAL}" "${LEVEL}" "${GOLD_COUNT}" "${SILVER_COUNT}" \
        "${ROWHAMMER_COUNT}" "${PIECE_COUNT}"
    # Round play time in whole seconds, the round's four-row clears and
    # the pieces it placed; all three are stored with the highscore entry
    # (play time and pieces are what its PCS/min column is computed from).
    if [ "${GAME_MODE}" = "ultra" ]; then
        # Only a run that reached the goal is recorded: an attempt that
        # topped out early has no comparable time, and ranking it by rows
        # would mean two orderings in one list. Its rows and counters
        # still feed the wonder and the statistics below.
        if [ "${GOAL_REACHED}" -eq 1 ]; then
            highscore_ultra_add "${PLAY_MS}" "${ROW_CREDIT}" \
                "${CLEARED_TOTAL}" "${LEVEL}" "${name}" \
                "${GOLD_COUNT}" "${SILVER_COUNT}" "${ROWHAMMER_COUNT}" \
                "${PIECE_COUNT}" "${ROUND_HASH}"
        else
            HSU_LAST_RANK=0
            debug_event "ultra run not recorded: goal not reached (rows=${ROW_CREDIT}/${ULTRA_TARGET_ROWS})"
        fi
    elif [ "${GAME_MODE}" = "sprint" ]; then
        # Same rule as Ultra, mirrored: only a run that used its full
        # time is recorded. A Sprint attempt that topped out after one
        # minute has fewer rows for a reason that has nothing to do with
        # how well it was played, so ranking it next to full runs would
        # compare two different things. Its rows still feed the wonder
        # and the statistics below, like those of any aborted round.
        if [ "${GOAL_REACHED}" -eq 1 ]; then
            highscore_sprint_add "${ROW_CREDIT}" "${CLEARED_TOTAL}" \
                "${LEVEL}" "${name}" "${GOLD_COUNT}" \
                "${SILVER_COUNT}" "$(( PLAY_MS / 1000 ))" \
                "${ROWHAMMER_COUNT}" "${PIECE_COUNT}" "${ROUND_HASH}"
        else
            HSS_LAST_RANK=0
            debug_event "sprint run not recorded: topped out early (time=${PLAY_MS}ms/${SPRINT_TIME_MS}ms rows=${ROW_CREDIT})"
        fi
    elif [ "${GAME_MODE}" = "timeattack" ]; then
        # Deliberately NOT mirrored from Ultra and Sprint: every Time
        # Attack run is recorded, the ones that ran the clock out and the
        # ones that topped out alike. Those two modes each have a "did
        # not finish" state that is incomparable with a finished run - no
        # time for Ultra, less than the full three minutes to score in
        # for Sprint. Time Attack has no such state: the run is over when
        # it is over, the rows are the same achievement either way, and a
        # player who builds themselves to death simply scored fewer of
        # them. That makes this mode the Marathon case, where the round
        # ends in a top-out and is recorded all the same.
        highscore_timeattack_add "${ROW_CREDIT}" "${CLEARED_TOTAL}" \
            "${LEVEL}" "${name}" "${GOLD_COUNT}" \
            "${SILVER_COUNT}" "$(( PLAY_MS / 1000 ))" \
            "${ROWHAMMER_COUNT}" "${PIECE_COUNT}" "${ROUND_HASH}"
    elif [ "${GAME_MODE}" = "flood" ]; then
        # Like Time Attack, and for the same reason: every round is
        # recorded. A Hochwasser round has no ending but the top-out -
        # sooner or later the water gets there - so there is no
        # "incomplete" run to keep out of the list, only rounds that
        # lasted longer or shorter.
        highscore_flood_add "${ROW_CREDIT}" "${CLEARED_TOTAL}" \
            "${LEVEL}" "${name}" "${GOLD_COUNT}" \
            "${SILVER_COUNT}" "$(( PLAY_MS / 1000 ))" \
            "${ROWHAMMER_COUNT}" "${PIECE_COUNT}" "${ROUND_HASH}"
    else
        highscore_add "${ROW_CREDIT}" "${CLEARED_TOTAL}" "${LEVEL}" \
            "${name}" "${GOLD_COUNT}" "${SILVER_COUNT}" \
            "$(( PLAY_MS / 1000 ))" "${ROWHAMMER_COUNT}" "${PIECE_COUNT}" \
            "${ROUND_HASH}"
    fi
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
    # statistics screen derives its PCS/min figures from. The mode and
    # the goal flag feed the per-mode round counters (2026-08-03): they
    # are the only round data the counters above cannot reconstruct, and
    # this is the one place that knows both.
    stats_add_round "${CLEARED_TOTAL}" \
        "$(( ROW_CREDIT - CLEARED_TOTAL ))" "${GOLD_COUNT}" "${SILVER_COUNT}" \
        "${ROWHAMMER_COUNT}" "${PIECE_COUNT}" "$(( PLAY_MS / 1000 ))" \
        "${GAME_MODE}" "${GOAL_REACHED}"
    # Close the demo recording of this round and move it from the RAM
    # disk into the data directory (lib/demo.sh). Here, with the rest of
    # the books, so a round is stored exactly once and exactly when it
    # really ended - a round suspended into the main menu keeps recording
    # and is stored when it is finished for good.
    local demo_end="quit"
    if [ "${GOAL_REACHED}" -eq 1 ]; then
        demo_end="goal"
    elif [ "${GAME_OVER}" -eq 1 ]; then
        demo_end="over"
    fi
    demo_record_finish "${demo_end}" "${ROUND_HASH}"
    return 0
}

# sprint_time_up: end a Sprint run whose SPRINT_TIME_MS are used up.
# Called from the game loop right after the play time was accounted,
# which is the only place the limit can be crossed - the clock is this
# mode's goal, the way the row credit is Ultra's (see lock_and_next).
# The run simply stops where it is: the piece still falling is not locked
# and rows it might have completed do not count, because the time ran out
# before it settled. GOAL_REACHED marks the run as a full one, so
# record_round enters it into the Sprint list; the result box over the
# board reads the same flag.
sprint_time_up() {
    GOAL_REACHED=1
    GAME_OVER=1
    debug_event "sprint time up: time=${PLAY_MS}ms/${SPRINT_TIME_MS}ms rows=${ROW_CREDIT} lines=${CLEARED_TOTAL} pieces=${PIECE_COUNT}"
    record_round
    DIRTY=1
    return 0
}

# time_attack_time_up: end a Time Attack run whose countdown has reached
# zero. Called from the same spot in the game loop as sprint_time_up and
# for the same reason - the clock is this mode's limit too, it is just a
# moving one (TIME_ATTACK_BUDGET_MS grows with every row of credit), and
# the piece still falling is not locked, so rows it might have completed
# would have been completed on time that had already run out.
# GOAL_REACHED marks the regular ending here rather than a success: it
# tells the result box which of the two endings this was (the run is
# recorded either way, see record_round).
time_attack_time_up() {
    GOAL_REACHED=1
    GAME_OVER=1
    debug_event "time attack clock empty: time=${PLAY_MS}ms/${TIME_ATTACK_BUDGET_MS}ms rows=${ROW_CREDIT} lines=${CLEARED_TOTAL} pieces=${PIECE_COUNT}"
    record_round
    DIRTY=1
    return 0
}

# flood_raise HOLE
# One rise of the Hochwasser mode: the whole board moves up by a row and
# a full row with a single gap at column HOLE comes in at the bottom
# (board_flood_row in lib/board.sh). The column is the caller's: the game
# loop draws it, a replay hands back the one its recording carries, which
# is why the event stores it - the rise itself follows the clock, but the
# column comes from RANDOM and could not be guessed again (lib/demo.sh).
# The round ends right here when the board is already full to the top: a
# stack that would be pushed off the board has reached the ceiling, which
# is this mode's game over just as a blocked spawn is Marathon's.
flood_raise() {
    local hole="${1}"
    # The next rise is scheduled from the moment this one happened, not
    # from the moment it was due. A tick that arrives late (a resize, the
    # clear animation, a slow terminal) would otherwise leave two or
    # three rises outstanding and flood them in one after another - the
    # same reason gravity restamps LAST_FALL from "now" instead of
    # counting due intervals.
    FLOOD_NEXT_MS=$(( PLAY_MS + FLOOD_INTERVAL_MS ))
    # Recorded before the effect, and recorded even when the rise ends
    # the round: the replay applies the same event to the same board and
    # therefore reaches the same ending.
    demo_record_event "w${hole}"
    if ! board_flood_row "${hole}"; then
        GAME_OVER=1
        debug_event "flood blocked: stack at the ceiling (lines=${CLEARED_TOTAL} rows=${ROW_CREDIT} pieces=${PIECE_COUNT})"
        record_round
        DIRTY=1
        return 0
    fi
    # The falling piece keeps its place on screen while the stack rises
    # under it - unless that leaves it inside the risen stack, in which
    # case it moves up with the board: it was resting on what just moved,
    # so this puts it back exactly where it sat. If even that position is
    # blocked (the piece is at the very top), the board has run out of
    # room and the round is over.
    if ! can_place "${CUR_TYPE}" "${CUR_ROT}" "${CUR_X}" "${CUR_Y}"; then
        if can_place "${CUR_TYPE}" "${CUR_ROT}" "${CUR_X}" "$(( CUR_Y - 1 ))"; then
            CUR_Y=$(( CUR_Y - 1 ))
        else
            GAME_OVER=1
            debug_event "flood row hole=${hole}: no room left for ${CUR_TYPE} at ${CUR_X},${CUR_Y} - game over (lines=${CLEARED_TOTAL} rows=${ROW_CREDIT})"
            record_round
            DIRTY=1
            return 0
        fi
    fi
    # A piece whose lock delay is armed may be airborne again now that it
    # was pushed up (a rise into a gap can leave room below it); the
    # usual rule then applies and it falls on normally. A piece that only
    # now came to rest needs nothing: the next gravity step arms its lock
    # delay, exactly as if it had landed by falling.
    lock_delay_recheck
    debug_event "flood row: hole=${hole} next=${FLOOD_NEXT_MS}ms piece=${CUR_TYPE} at ${CUR_X},${CUR_Y}"
    debug_board_snapshot
    DIRTY=1
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
    local y i ms="${FLASH_MS}"
    FLASH_ROWS=()
    for y in "${FULL_ROWS[@]}"; do
        FLASH_ROWS["${y}"]=1
    done
    # During a demo playback the animation is scaled with the playback
    # speed. It runs on real time while the rest of the replay runs on
    # the demo clock, so an unscaled flash would eat demo time at double
    # speed and the replay would jump over the events right after a clear
    # (at half speed it would drag). One millisecond is the floor, so a
    # very fast replay still blinks instead of dividing down to a
    # zero-length read.
    if [ "${DEMO_PLAYING}" -eq 1 ]; then
        ms=$(( FLASH_MS * 100 / DEMO_SPEED ))
        if [ "${ms}" -lt 1 ]; then
            ms=1
        fi
    fi
    debug_event "row flash: rows=${FULL_ROWS[*]} cycles=${FLASH_CYCLES} ms=${ms}"
    for (( i = 0; i < FLASH_CYCLES; i++ )); do
        FLASH_STATE=1
        draw_frame
        key_drain "${ms}"
        FLASH_STATE=0
        draw_frame
        key_drain "${ms}"
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
        # Ultra mode: the goal is a row credit, so this - right after a
        # clear was scored - is the only place it can ever be reached.
        # The run ends here, before the next piece spawns: it is over the
        # moment the target is hit, and the piece would only be in the
        # way of the result box.
        if [ "${GAME_MODE}" = "ultra" ] && (( ROW_CREDIT >= ULTRA_TARGET_ROWS )); then
            # Count the time up to this very moment: a hard drop lands
            # between two loop ticks, and those milliseconds are part of
            # the run's time - which in this mode is its score.
            play_clock_tick
            GOAL_REACHED=1
            GAME_OVER=1
            debug_event "ultra goal reached: rows=${ROW_CREDIT}/${ULTRA_TARGET_ROWS} time=${PLAY_MS}ms lines=${CLEARED_TOTAL} pieces=${PIECE_COUNT}"
            record_round
            debug_board_snapshot
            DIRTY=1
            return 0
        fi
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
# down = soft drop), space for hard drop and w for hold (w replaced the
# earlier 2 in 0.31.0, see the note at the hold branch below).
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
            # resume, restart, suspend the round into the main menu or
            # end it (lib/menu.sh sets
            # GAME_EXIT/GAME_SUSPENDED/GAME_RESTART accordingly).
            debug_event "pause menu opened"
            menu_pause
            # "Neustarten" (2026-08-03, user request): the running round
            # is given up for a fresh one in the same mode (game_reset
            # without an argument keeps GAME_MODE, like the game over
            # screen's restart key). menu_pause has confirmed the
            # discard at this point - the flag is only set on a "yes".
            # Its books are closed first -
            # an abandoned round counts toward the wonder and the
            # statistics like any other aborted one (see CLAUDE.md 3.3),
            # and game_reset is about to wipe the counters record_round
            # reads. That is the same order game_run uses when a new
            # round replaces a suspended one. The restart key on the game
            # over screen needs no such call: there the round was already
            # recorded when it ended.
            if [ "${GAME_RESTART}" -eq 1 ]; then
                GAME_RESTART=0
                debug_event "restart from pause menu (mode=${GAME_MODE} lines=${CLEARED_TOTAL} rows=${ROW_CREDIT})"
                record_round
                game_reset
            fi
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
    # Each of these actions is handed to the demo recorder before it is
    # carried out (demo_record_event is a no-op when nothing is being
    # recorded). Before, not after, so the event carries the play time the
    # key was pressed at rather than the time the action - a hard drop
    # with its row flash, say - happened to finish; and blocked attempts
    # are recorded too, because the replay runs them against the same
    # board and they are blocked there as well.
    case "${KEY}" in
        LEFT|"${KEY_LEFT}")   demo_record_event l; try_move -1 0 || : ;;
        RIGHT|"${KEY_RIGHT}") demo_record_event r; try_move 1 0 || : ;;
        "${KEY_ROT_CW}")      demo_record_event c; try_rotate 1 || : ;;
        "${KEY_ROT_CCW}")     demo_record_event a; try_rotate -1 || : ;;
        DOWN|"${KEY_SOFT}")
            # Soft drop earns no points (cleared rows are the only
            # score source); it just pulls the piece down early.
            demo_record_event s
            step_down
            now_ms
            LAST_FALL="${NOW_MS}"
            ;;
        UP|SPACE|"${KEY_HARD}")
            demo_record_event h
            hard_drop
            ;;
        # CHANGE 2026-07-30 (user decision): w replaced 2 as the fixed
        # secondary hold key. It sits below the rotation keys a/d on the
        # left hand and is free since the hard drop gave up its letter.
        w|"${KEY_HOLD}")
            demo_record_event o
            hold_piece
            ;;
    esac
    return 0
}

# game_reset [MODE]
# Start a fresh round in MODE ("marathon", "ultra", "sprint",
# "timeattack" or "flood"); without
# an argument the current GAME_MODE is kept, which is what the game over
# screen's restart key does - a failed Ultra run restarts as an Ultra
# run, a finished Sprint as a Sprint.
game_reset() {
    GAME_MODE="${1:-${GAME_MODE}}"
    debug_event "round start (mode=${GAME_MODE} seed=${SEED:-unset})"
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
    GOAL_REACHED=0
    ROUND_RECORDED=0
    LOCK_PENDING=0
    PLAY_MS=0
    # Back to the plain start time: the credit that bought the last
    # round's extra time is gone with ROW_CREDIT above.
    time_attack_budget
    # The first flood row of a Hochwasser round is due after one full
    # interval, so the round starts on a clean board like every other.
    FLOOD_NEXT_MS="${FLOOD_INTERVAL_MS}"
    # Start the recording before the first piece is drawn: spawn_piece
    # below fills the queue, and those pieces belong to the recording
    # (see demo_record_piece in queue_fill, lib/pieces.sh). Replaying a
    # demo runs through here as well - demo_record_start then knows not
    # to record a replay.
    demo_record_start "${GAME_MODE}"
    update_speed
    spawn_piece
    play_clock_resume
    DIRTY=1
}

# --- Game loop ------------------------------------------------------------
# game_run [marathon|ultra|sprint|timeattack|flood|resume]
# One game session; returns to the caller (the menu) when the player
# leaves via the pause menu or the game over screen. The argument is
# either the game mode of the new round (see GAME_MODE) or "resume",
# which continues the round suspended earlier through the pause menu
# instead of starting a fresh one - in the mode that round was started
# in, since the suspended state carries its GAME_MODE along. A resumed
# round comes back paused so it does not run before the player is ready.
# A round suspended (again) is not recorded - the books close only when
# the round really ends.
game_run() {
    local mode="${1:-marathon}"
    GAME_EXIT=0
    # The screen still holds a menu: the first frame must repaint it all.
    RENDER_FULL=1
    if [ "${mode}" = "resume" ] && [ "${GAME_SUSPENDED}" -eq 1 ]; then
        GAME_SUSPENDED=0
        PAUSED=1
        debug_event "round resumed from menu (mode=${GAME_MODE} lines=${CLEARED_TOTAL} rows=${ROW_CREDIT})"
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
        game_reset "${mode}"
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
            # Accumulate the play time of the segment since the last
            # accounted moment (and refresh NOW_MS for the gravity checks
            # below). play_clock_resume set PLAY_LAST to "now" at every
            # resume, so an idle phase never lands in PLAY_MS.
            play_clock_tick
            # Time Attack: refresh the budget the rows scored so far have
            # bought, so the check below and the HUD read the same number
            # (the clock counts down against a target that moves).
            if [ "${GAME_MODE}" = "timeattack" ]; then
                time_attack_budget
            fi
            # Hochwasser mode: the play time just accounted may have
            # brought the next flood row due. Its own "if" rather than a
            # branch of the chain below, because a rise is not an ending
            # and must not cost the tick its gravity - the water comes
            # while the piece keeps falling, that is the whole mode. It
            # can still end the round (a stack pushed against the
            # ceiling), which is what the GAME_OVER test in front of the
            # chain catches: nothing should fall or lock after that.
            if [ "${GAME_MODE}" = "flood" ] && \
               (( PLAY_MS >= FLOOD_NEXT_MS )); then
                # The gap column is drawn where the rise really happens;
                # a replay feeds the recorded one to the same function.
                flood_raise "$(( RANDOM % BOARD_W ))"
            fi
            # Sprint mode: the play time just accounted may have used up
            # the run's three minutes. Checked before gravity so no piece
            # falls or locks on time that is already over - which holds
            # for the Time Attack countdown in the branch below just as
            # much.
            if [ "${GAME_OVER}" -eq 1 ]; then
                # The flood above ended the round on this very tick:
                # nothing falls, locks or times out on a finished round.
                :
            elif [ "${GAME_MODE}" = "sprint" ] && \
               (( PLAY_MS >= SPRINT_TIME_MS )); then
                sprint_time_up
            elif [ "${GAME_MODE}" = "timeattack" ] && \
                 (( PLAY_MS >= TIME_ATTACK_BUDGET_MS )); then
                time_attack_time_up
            elif [ "${LOCK_PENDING}" -eq 1 ]; then
                # Resting piece: lock once the grace window has elapsed.
                # Gravity is idle here - the piece cannot fall anyway.
                if (( NOW_MS - TOUCHDOWN_MS >= LOCK_DELAY_MS )); then
                    debug_event "lock delay expired at ${CUR_X},${CUR_Y}"
                    # The two things the clock does to a round on its own
                    # are recorded like the player's keys, so a replay
                    # needs no timers of its own: it simply applies the
                    # events on the timeline they were recorded at.
                    demo_record_event k
                    lock_and_next
                fi
            elif (( NOW_MS - LAST_FALL >= FALL_MS )); then
                LAST_FALL="${NOW_MS}"
                demo_record_event g
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
        debug_event "game session suspended (mode=${GAME_MODE} lines=${CLEARED_TOTAL} rows=${ROW_CREDIT} level=${LEVEL})"
        return 0
    fi
    # Quitting a running round to the menu ends it too; the flag makes
    # this a no-op when the game over path already recorded the round.
    record_round
    debug_event "game session end (mode=${GAME_MODE} lines=${CLEARED_TOTAL} rows=${ROW_CREDIT} level=${LEVEL} goal_reached=${GOAL_REACHED})"
    return 0
}

# --- Main menu loop -------------------------------------------------------
main() {
    # Restore the terminal on any exit path, including Ctrl-C; the debug
    # logs close afterwards, so the "logs written to" note lands on the
    # normal screen buffer.
    # demo_record_discard removes the RAM disk file of a round that never
    # finished (Ctrl-C, a killed session); a finished round has already
    # moved its recording into the data directory and left nothing here.
    trap 'term_restore; demo_record_discard; debug_close' EXIT
    trap 'exit 130' INT TERM
    # Debug logging starts before the alternate screen, so init errors
    # (unwritable log directory etc.) stay readable.
    debug_init
    # Load the persistent highscore lists once; rounds update them in
    # memory and rewrite their file when they enter one. Ultra, Sprint,
    # Time Attack and Hochwasser keep separate files with their own
    # rankings (fastest run first resp. most rows in a fixed time resp.
    # most rows on a clock the run feeds itself resp. most rows against
    # the rising water), so runs of different modes never compete for the
    # same slots.
    highscore_load
    highscore_ultra_load
    highscore_sprint_load
    highscore_timeattack_load
    highscore_flood_load
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
    local choice round_line
    while :; do
        entries=()
        if [ "${GAME_SUSPENDED}" -eq 1 ]; then
            entries+=("${I18N[main_resume]}")
        fi
        entries+=("${I18N[main_single]}" "${I18N[main_multi]}" \
            "${I18N[main_highscores]}" "${I18N[main_wonders]}" \
            "${I18N[main_stats]}" "${I18N[main_demos]}" \
            "${I18N[main_settings]}" "${I18N[main_help]}" \
            "${I18N[main_quit]}")
        # The title is the game's name and therefore the one screen text
        # that is the same in every language.
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
                i18n_lines mp_body
                menu_message "${I18N[main_multi]}" "${I18N_LINES[@]}"
                ;;
            2)
                # Picks the mode first (Marathon or Ultra): the two
                # lists rank by different numbers and are not
                # comparable, see lib/highscore.sh.
                menu_highscores
                ;;
            3)
                # Progress screen: the current construction site with
                # the banked all-time row total.
                wonder_screen "${TOTAL_ROW_CREDIT}"
                ;;
            4)
                # Picks between the all-time counters and one mode's
                # own, the way "Highscores" picks a list (lib/stats.sh).
                menu_stats
                ;;
            5)
                # Recorded rounds: watch one again or delete it. It sits
                # behind the statistics because it is the same kind of
                # entry - a look back at rounds already played.
                menu_demos
                ;;
            6)
                menu_settings
                ;;
            7)
                # Short manual (user request): rules, controls, hold,
                # gold/silver squares and the wonder construction. It
                # sits right before "Beenden" so the entry a player
                # needs on the first start is the last one they pass.
                menu_help
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
                    printf -v round_line "${I18N[round_state]}" \
                        "${CLEARED_TOTAL}" "${ROW_CREDIT}" "${LEVEL}"
                    i18n_lines quit_tail
                    if ! menu_confirm "${I18N[quit_title]}" \
                        "${I18N[quit_yes]}" "${I18N[confirm_no]}" \
                        "${I18N[quit_head]}" \
                        "${round_line}" \
                        "" \
                        "${I18N_LINES[@]}"; then
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
