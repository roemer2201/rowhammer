#!/usr/bin/env bash
#
# lib/input.sh
#
# Description:
#   Terminal setup and non-blocking keyboard input for rowhammer. Switches
#   to the alternate screen buffer, hides the cursor and provides a
#   single-key reader that understands the arrow-key escape sequences.
#   Escape sequences are parsed byte by byte up to their final byte, so
#   longer sequences (modified arrows, Delete, function keys) are consumed
#   completely instead of leaking tail bytes as fake key presses (issue #7).
#   Enter is reported as ENTER so the menu system can use it as "select".
#   In debug mode every received key press is recorded (raw bytes plus
#   mapped symbol) via debug_input from lib/debug.sh.
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.4.0  (2026-07-20)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/input.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# Poll interval of the game loop in seconds. The read timeout doubles as
# the tick pacing of the main loop, so the game never busy-waits.
TICK_S="0.02"

# Grace period in seconds for the continuation bytes of an escape
# sequence. Deliberately more generous than TICK_S: over SSH, inside
# tmux/screen or under load the bytes of one arrow-key sequence can
# arrive several milliseconds apart, and a too short window tears the
# sequence apart (issue #7). 50 ms is still far below the time a human
# needs to press Esc and a second key on purpose.
ESC_SUFFIX_T="0.05"

SAVED_STTY=""
TERM_ACTIVE=0

# Enter the alternate screen buffer, clear it and hide the cursor. The
# current stty state is saved first so term_restore can bring the terminal
# back exactly as it was.
term_setup() {
    SAVED_STTY="$(stty -g)"
    screen_write $'\e[?1049h\e[2J\e[H\e[?25l'
    TERM_ACTIVE=1
    debug_event "terminal: alternate screen on, cursor hidden"
}

# Restore cursor, screen buffer and stty state. Idempotent on purpose: it
# serves both the EXIT/INT/TERM trap and the regular quit path, and must
# not garble the screen when it runs twice.
term_restore() {
    if [ "${TERM_ACTIVE}" -eq 1 ]; then
        debug_event "terminal: restoring screen and stty state"
        screen_write $'\e[?25h\e[?1049l'
        if [ -n "${SAVED_STTY}" ]; then
            stty "${SAVED_STTY}" || stty sane
        fi
        TERM_ACTIVE=0
    fi
}

# read_key
# Wait up to TICK_S for a key press and map it to a symbolic name in the
# global KEY: LEFT RIGHT UP DOWN SPACE ENTER ESC or the lower-cased
# literal character. KEY is empty when no (usable) key arrived. A closed
# stdin is treated as a fatal error so the loop cannot spin at full speed.
read_key() {
    KEY=""
    local c="" rest="" b="" n=0 ord=0 rc=0
    IFS= read -rsn1 -t "${TICK_S}" c || rc=$?
    if [ "${rc}" -gt 128 ]; then
        # rc > 128 is a timeout. bash (observed on 5.1) can hand over a
        # byte together with the timeout status when it arrives in the
        # very moment the timeout expires; such a byte must not be
        # dropped: discarding it here silently swallowed the leading ESC
        # of an arrow-key sequence and its tail bytes were then misread
        # as normal key presses (issue #7). Only a timeout without data
        # means that no key was pressed during this tick.
        if [ -z "${c}" ]; then
            return 0
        fi
    elif [ "${rc}" -ne 0 ]; then
        die "Input stream closed (stdin is gone)"
    fi
    case "${c}" in
        $'\e')
            # Either a lone ESC key or the start of an escape sequence:
            # arrow keys arrive as ESC [ X (CSI) or ESC O X (SS3 in
            # application mode). The suffix is read byte by byte up to
            # the final byte of the sequence, so longer sequences
            # (Shift/Ctrl-arrows ESC [ 1 ; 2 C, Delete ESC [ 3 ~,
            # function keys) are consumed completely; the fixed
            # two-byte read used before 0.4.0 left their tail bytes in
            # the buffer where the next calls misread them as normal
            # key presses (issue #7). The lone-ESC case falls through
            # (instead of returning early) so the debug input logging
            # below sees every key press. The suffix reads test the
            # variable content instead of the read status for the same
            # bash 5.1 reason as above.
            IFS= read -rsn1 -t "${ESC_SUFFIX_T}" b || :
            if [ -z "${b}" ]; then
                # Nothing followed within the grace period: lone ESC.
                KEY="ESC"
            elif [ "${b}" = '[' ] || [ "${b}" = 'O' ]; then
                rest="${b}"
                # Collect parameter bytes until the final byte (ASCII
                # 0x40..0x7e) ends the sequence. The length cap guards
                # against a runaway byte stream.
                while [ "${n}" -lt 16 ]; do
                    n=$(( n + 1 ))
                    b=""
                    IFS= read -rsn1 -t "${ESC_SUFFIX_T}" b || :
                    if [ -z "${b}" ]; then
                        break
                    fi
                    rest="${rest}${b}"
                    # Linux console function keys use ESC [ [ X; the
                    # second '[' is not a final byte there, exactly one
                    # more byte follows.
                    if [ "${rest}" = '[[' ]; then
                        continue
                    fi
                    printf -v ord '%d' "'${b}"
                    if [ "${ord}" -ge 64 ] && [ "${ord}" -le 126 ]; then
                        break
                    fi
                done
                case "${rest}" in
                    '[A'|'OA') KEY="UP" ;;
                    '[B'|'OB') KEY="DOWN" ;;
                    '[C'|'OC') KEY="RIGHT" ;;
                    '[D'|'OD') KEY="LEFT" ;;
                    *)         KEY="" ;;
                esac
            else
                # ESC immediately followed by an ordinary byte: an
                # Alt-chord (Alt sends ESC plus the key's byte) or a key
                # pressed right after Esc. Neither is a game key, so the
                # pair is consumed without mapping to anything; passing
                # the second byte on as its own key press would be
                # exactly the misinterpretation issue #7 is about.
                rest="${b}"
                KEY=""
            fi
            ;;
        ' ')
            KEY="SPACE"
            ;;
        '')
            # Enter yields an empty read (newline is the read delimiter).
            KEY="ENTER"
            ;;
        *)
            # Letters are matched case-insensitively.
            KEY="${c,,}"
            ;;
    esac
    # Record the press (raw bytes and mapped symbol) in debug mode; the
    # timeout path above never reaches this point, so only real key
    # presses are logged.
    debug_input "${c}${rest}" "${KEY}"
    return 0
}
