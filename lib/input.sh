#!/usr/bin/env bash
#
# lib/input.sh
#
# Description:
#   Terminal setup and non-blocking keyboard input for rowhammer. Switches
#   to the alternate screen buffer, hides the cursor and provides a
#   single-key reader that understands the arrow-key escape sequences.
#   Library file: sourced by tetris.sh, not meant to be executed directly.
#
# Version: 0.1.0  (2026-07-17)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/input.sh is a library; source it from tetris.sh\n' >&2
    exit 2
fi

# Poll interval of the game loop in seconds. The read timeout doubles as
# the tick pacing of the main loop, so the game never busy-waits.
TICK_S="0.02"

SAVED_STTY=""
TERM_ACTIVE=0

# Enter the alternate screen buffer, clear it and hide the cursor. The
# current stty state is saved first so term_restore can bring the terminal
# back exactly as it was.
term_setup() {
    SAVED_STTY="$(stty -g)"
    printf '\e[?1049h\e[2J\e[H\e[?25l'
    TERM_ACTIVE=1
}

# Restore cursor, screen buffer and stty state. Idempotent on purpose: it
# serves both the EXIT/INT/TERM trap and the regular quit path, and must
# not garble the screen when it runs twice.
term_restore() {
    if [ "${TERM_ACTIVE}" -eq 1 ]; then
        printf '\e[?25h\e[?1049l'
        if [ -n "${SAVED_STTY}" ]; then
            stty "${SAVED_STTY}" || stty sane
        fi
        TERM_ACTIVE=0
    fi
}

# read_key
# Wait up to TICK_S for a key press and map it to a symbolic name in the
# global KEY: LEFT RIGHT UP DOWN SPACE ESC or the lower-cased literal
# character. KEY is empty when no (usable) key arrived. A closed stdin is
# treated as a fatal error so the loop cannot spin at full speed.
read_key() {
    KEY=""
    local c="" rest="" rc=0
    IFS= read -rsn1 -t "${TICK_S}" c || rc=$?
    if [ "${rc}" -gt 128 ]; then
        # Timeout: no key pressed during this tick.
        return 0
    elif [ "${rc}" -ne 0 ]; then
        die "Input stream closed (stdin is gone)"
    fi
    case "${c}" in
        $'\e')
            # Either a lone ESC key or the start of an escape sequence:
            # arrow keys arrive as ESC [ X (or ESC O X in application
            # mode) within a few milliseconds.
            rc=0
            IFS= read -rsn2 -t 0.02 rest || rc=$?
            if [ "${rc}" -ne 0 ]; then
                KEY="ESC"
                return 0
            fi
            case "${rest}" in
                '[A'|'OA') KEY="UP" ;;
                '[B'|'OB') KEY="DOWN" ;;
                '[C'|'OC') KEY="RIGHT" ;;
                '[D'|'OD') KEY="LEFT" ;;
                *)         KEY="" ;;
            esac
            ;;
        ' ')
            KEY="SPACE"
            ;;
        '')
            # Enter yields an empty read; the game has no use for it.
            KEY=""
            ;;
        *)
            # Letters are matched case-insensitively.
            KEY="${c,,}"
            ;;
    esac
    return 0
}
