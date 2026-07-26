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
#   mapped symbol) via debug_input from lib/debug.sh. Terminal resizing is
#   handled here too (since 0.5.0): a SIGWINCH trap armed by term_setup
#   flags the resize, and read_key applies it via term_resize_apply -
#   remeasure (term_measure), clear and let the caller repaint, and while
#   the terminal is too small for the fixed layout, block on a "resize me"
#   overlay until it grows back.
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.5.0  (2026-07-23)

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

# term_measure
# Read the current terminal size into TERM_ROWS/TERM_COLS and set the
# TERM_TOO_SMALL flag against the MIN_TERM_* minimum the fixed layout
# needs. Used at startup (rowhammer.sh) and after every resize. stty size
# reports "rows cols"; a failed or malformed read leaves the previous
# values untouched so a transient hiccup never fakes a zero-size terminal.
term_measure() {
    local size
    size="$(stty size 2>/dev/null)" || size=""
    if [[ "${size}" =~ ^([0-9]+)[[:space:]]+([0-9]+)$ ]]; then
        TERM_ROWS="${BASH_REMATCH[1]}"
        TERM_COLS="${BASH_REMATCH[2]}"
    fi
    if (( TERM_ROWS < MIN_TERM_ROWS || TERM_COLS < MIN_TERM_COLS )); then
        TERM_TOO_SMALL=1
    else
        TERM_TOO_SMALL=0
    fi
}

# term_resize_apply
# Apply a pending SIGWINCH (TERM_RESIZED, set asynchronously by the
# handler installed in term_setup). Called from read_key - the one funnel
# every game and menu loop polls through - so no drawing ever happens from
# inside the async signal handler. A resize typically garbles or reflows
# the alternate screen, so the screen is wiped and REDRAW_PENDING is
# raised for the caller to repaint. While the terminal is too small for
# the fixed 48x24 layout the function blocks on the "resize me" overlay
# (term_too_small_screen) until it grows back, so the game never tries to
# draw a torn board.
term_resize_apply() {
    TERM_RESIZED=0
    term_measure
    screen_write $'\e[2J\e[H'
    REDRAW_PENDING=1
    local was_too_small="${TERM_TOO_SMALL}"
    if [ "${TERM_TOO_SMALL}" -eq 1 ]; then
        debug_event "terminal resized to ${TERM_COLS}x${TERM_ROWS} (too small, minimum ${MIN_TERM_COLS}x${MIN_TERM_ROWS})"
    else
        debug_event "terminal resized to ${TERM_COLS}x${TERM_ROWS}"
    fi
    # Hold here until the terminal is big enough again. A short blocking
    # read paces the wait without busy-looping; the SIGWINCH trap
    # interrupts it, so the live "now WxH" figure updates promptly while
    # the user drags the terminal border. Keys pressed meanwhile are
    # swallowed on purpose - they must not leak into the game once play
    # resumes.
    local ignore=""
    while [ "${TERM_TOO_SMALL}" -eq 1 ]; do
        term_too_small_screen
        ignore=""
        IFS= read -rsn1 -t 0.2 ignore || :
        if [ "${TERM_RESIZED}" -eq 1 ]; then
            TERM_RESIZED=0
            term_measure
            screen_write $'\e[2J\e[H'
        fi
    done
    if [ "${was_too_small}" -eq 1 ]; then
        debug_event "terminal size ok again: ${TERM_COLS}x${TERM_ROWS}"
    fi
}

# Enter the alternate screen buffer, clear it and hide the cursor. The
# current stty state is saved first so term_restore can bring the terminal
# back exactly as it was. A SIGWINCH trap is armed here so a resize during
# play is noticed: the handler only flags TERM_RESIZED (signal-safe), and
# read_key applies it via term_resize_apply on the next tick.
term_setup() {
    SAVED_STTY="$(stty -g)"
    screen_write $'\e[?1049h\e[2J\e[H\e[?25l'
    trap 'TERM_RESIZED=1' WINCH
    TERM_ACTIVE=1
    debug_event "terminal: alternate screen on, cursor hidden, resize watch armed"
}

# Restore cursor, screen buffer and stty state. Idempotent on purpose: it
# serves both the EXIT/INT/TERM trap and the regular quit path, and must
# not garble the screen when it runs twice. The SIGWINCH trap is dropped
# so no resize handling runs once the game has left the alternate screen.
term_restore() {
    if [ "${TERM_ACTIVE}" -eq 1 ]; then
        debug_event "terminal: restoring screen and stty state"
        trap - WINCH
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
    # A SIGWINCH sets TERM_RESIZED asynchronously; the handler only flags
    # it so nothing is drawn from inside the signal. Apply it here, before
    # reading, so every game and menu loop that polls through read_key
    # handles a resize the same way (remeasure, clear, block while too
    # small). term_resize_apply raises REDRAW_PENDING for the caller.
    if [ "${TERM_RESIZED}" -eq 1 ]; then
        term_resize_apply
    fi
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
