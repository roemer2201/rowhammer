#!/usr/bin/env bash
#
# lib/debug.sh
#
# Description:
#   Debug/trace mode for rowhammer. When the game runs with --debug (env
#   ROWHAMMER_DEBUG=1), the session writes a complete trace into its own
#   directory (default ${XDG_STATE_HOME:-~/.local/state}/rowhammer/debug/
#   <timestamp>.<pid>, overridable with --debug-dir / ROWHAMMER_DEBUG_DIR):
#     events.log - session header (version, bash, terminal, seed, player,
#                  key bindings, data directory, loaded config files)
#                  followed by every
#                  game action: spawns, moves and rotations (including
#                  blocked attempts), gravity falls, locks, square
#                  formation, line clears with credit details, hold,
#                  pause, menu choices, config saves, fatal errors and a
#                  board snapshot after every lock.
#     input.log  - every key press: the raw byte(s) read from the
#                  terminal (printf %q quoted) and the mapped symbolic
#                  key (empty = unmapped sequence).
#     frames.log - every screen update byte for byte (1:1, ANSI escape
#                  sequences included), one delimited entry per write.
#   Every log line carries the elapsed milliseconds since session start
#   and the screen update counter ("f N"): an entry tagged f 42 happened
#   after screen update 42 was drawn and before update 43. That lets the
#   three files be correlated when analyzing a bug report or a gameplay
#   question.
#   The switch variables DEBUG_OPT and DEBUG_DIR are owned by
#   rowhammer.sh (defaults/env/CLI blocks); this module only reads them.
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.3.0  (2026-07-19)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/debug.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# DEBUG_ACTIVE only turns 1 once debug_init has opened the log files;
# every log helper below is a no-op before that, so instrumentation calls
# are safe anywhere in the code regardless of the --debug switch.
DEBUG_ACTIVE=0
DEBUG_T0_MS=0
DEBUG_FRAME_NO=0

# Fixed file descriptors for the three log files. Literal numbers because
# bash's exec cannot redirect through a variable fd; kept well above the
# standard descriptors to avoid collisions.
#   21 = events.log, 22 = input.log, 23 = frames.log

# debug_init
# Create the session directory, open the log files and write the session
# header. Called from main() after settings resolution and before the
# terminal switches to the alternate screen, so init errors (unwritable
# directory etc.) stay readable on the normal screen.
debug_init() {
    if [ "${DEBUG_OPT:-0}" -ne 1 ]; then
        return 0
    fi
    if [ -z "${DEBUG_DIR:-}" ]; then
        DEBUG_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/rowhammer/debug/$(date +%Y%m%d-%H%M%S).$$"
    fi
    mkdir -p -- "${DEBUG_DIR}"
    exec 21>>"${DEBUG_DIR}/events.log" \
         22>>"${DEBUG_DIR}/input.log" \
         23>>"${DEBUG_DIR}/frames.log"
    now_ms
    DEBUG_T0_MS="${NOW_MS}"
    DEBUG_ACTIVE=1

    # Session header: everything needed to reproduce the run.
    local keys="" var
    for var in "${KEY_ACTIONS[@]}"; do
        keys+="${keys:+ }${var}=${!var}"
    done
    {
        printf '# rowhammer debug session\n'
        printf '# started:  %s\n' "$(date -Iseconds)"
        printf '# version:  %s\n' "${ROWHAMMER_VERSION}"
        printf '# bash:     %s\n' "${BASH_VERSION}"
        printf '# terminal: TERM=%s size=%sx%s tick=%ss\n' \
            "${TERM:-unset}" "${TERM_COLS}" "${TERM_ROWS}" "${TICK_S}"
        printf '# seed:     %s\n' "${SEED:-unset (random)}"
        printf '# player:   %s  color=%s mode=%s\n' \
            "${PLAYER_NAME}" "${USE_COLOR}" "${COLOR_MODE}"
        printf '# keys:     %s\n' "${keys}"
        printf '# data:     %s\n' "${DATA_DIR}"
        printf '# config:   %s\n' "${CONFIG_LOADED_FILES:-none}"
        printf '# Line format: [elapsed_ms] [f screen_update_no] message.\n'
        printf '# An event tagged f N happened after screen update N.\n'
    } >&21
    printf '# rowhammer key input log. Line format: [elapsed_ms] [f N] raw=<%%q-quoted bytes> key=<mapped symbol>.\n' >&22
    printf '# rowhammer frame log. Each entry: one header line, then the exact bytes written to the terminal.\n' >&23
    debug_event "session start"
    return 0
}

# debug_ts
# Build the shared line prefix (elapsed ms + screen update counter) into
# the global DEBUG_TS. Uses now_ms, which only moves NOW_MS forward; the
# game loop re-reads the clock before every timing decision, so this
# cannot disturb the gravity timer.
debug_ts() {
    now_ms
    printf -v DEBUG_TS '[%8d] [f %04d]' \
        "$(( NOW_MS - DEBUG_T0_MS ))" "${DEBUG_FRAME_NO}"
}

# debug_event MESSAGE...
# Append one (possibly multi-line) entry to events.log.
debug_event() {
    if [ "${DEBUG_ACTIVE}" -ne 1 ]; then
        return 0
    fi
    debug_ts
    printf '%s %s\n' "${DEBUG_TS}" "$*" >&21
    return 0
}

# debug_input RAW MAPPED
# Append one key press to input.log. RAW is the byte sequence exactly as
# read from the terminal (may be empty for Enter), MAPPED the symbolic
# key it resolved to (may be empty for unmapped escape sequences).
debug_input() {
    if [ "${DEBUG_ACTIVE}" -ne 1 ]; then
        return 0
    fi
    debug_ts
    printf '%s raw=%q key=%s\n' "${DEBUG_TS}" "${1}" "${2}" >&22
    return 0
}

# debug_frame CONTENT
# Append one screen update to frames.log, byte for byte, and advance the
# shared screen update counter. Called by screen_write (lib/render.sh)
# for every write that reaches the terminal.
debug_frame() {
    if [ "${DEBUG_ACTIVE}" -ne 1 ]; then
        return 0
    fi
    DEBUG_FRAME_NO=$(( DEBUG_FRAME_NO + 1 ))
    debug_ts
    printf -- '--- %s screen update (%d bytes) ---\n%s\n' \
        "${DEBUG_TS}" "${#1}" "${1}" >&23
    return 0
}

# debug_board_snapshot
# Dump the logical board state into events.log: piece type grid and
# square marking grid side by side, plus the cut/squared instance sets.
# Cheap enough to run after every lock; the grids make "why did no square
# form here" questions answerable without replaying the frames.
debug_board_snapshot() {
    if [ "${DEBUG_ACTIVE}" -ne 1 ]; then
        return 0
    fi
    local y x idx tline sline mark line out cut_list="" squared_list=""
    out="board snapshot (types | squares; * = hidden spawn row):"$'\n'
    for (( y = 0; y < BOARD_H; y++ )); do
        tline=""
        sline=""
        for (( x = 0; x < BOARD_W; x++ )); do
            idx=$(( y * BOARD_W + x ))
            tline+="${BOARD[idx]}"
            sline+="${BOARD_SQ[idx]:-.}"
        done
        mark=" "
        if (( y < HIDDEN_ROWS )); then
            mark="*"
        fi
        printf -v line '  y=%2d%s |%s| |%s|' "${y}" "${mark}" "${tline}" "${sline}"
        out+="${line}"$'\n'
    done
    # Key expansion of an empty associative array trips set -u on older
    # bash, so both lists are only expanded when non-empty.
    if [ "${#INSTANCE_CUT[@]}" -gt 0 ]; then
        cut_list="${!INSTANCE_CUT[*]}"
    fi
    if [ "${#INSTANCE_SQUARED[@]}" -gt 0 ]; then
        squared_list="${!INSTANCE_SQUARED[*]}"
    fi
    out+="  cut instances: ${cut_list:-none}; squared instances: ${squared_list:-none}"
    debug_event "${out}"
    return 0
}

# debug_close
# Final entry, close the log files and tell the player where the logs
# are. Runs from the EXIT trap after term_restore, so the message lands
# on the normal screen buffer and stays visible after the game ends.
debug_close() {
    if [ "${DEBUG_ACTIVE}" -ne 1 ]; then
        return 0
    fi
    debug_event "session end"
    DEBUG_ACTIVE=0
    exec 21>&- 22>&- 23>&-
    printf '%s: debug logs written to: %s\n' "${SCRIPT_NAME}" "${DEBUG_DIR}"
    return 0
}
