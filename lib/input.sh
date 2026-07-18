#!/usr/bin/env bash
#
# lib/input.sh
#
# Description:
#   Terminal setup and non-blocking keyboard input for rowhammer. Switches
#   to the alternate screen buffer, hides the cursor and provides a
#   single-key reader that understands the arrow-key escape sequences.
#   Escape sequences are consumed completely (including modifier variants
#   like ESC [ 1 ; 2 D and unknown keys like PgUp), so no tail bytes can
#   leak into the key stream and trigger phantom game keys. Enter is
#   reported as ENTER so the menu system can use it as "select".
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.3.0  (2026-07-18)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/input.sh is a library; source it from rowhammer.sh\n' >&2
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

# input_flush
# Drain any pending bytes after a garbled or unfinished escape sequence,
# so stray tail bytes cannot be misread as game keys on later ticks.
input_flush() {
    local junk
    while IFS= read -rsn1 -t 0.001 junk; do
        :
    done
    return 0
}

# read_escape_sequence
# Called after an ESC byte was read. Consumes the complete sequence and
# maps the cursor keys into KEY. CHANGE 2026-07-18: previously a fixed
# 2-byte read left the tail of longer sequences (e.g. the modifier
# variant ESC [ 1 ; 2 D, or ESC [ 5 ~ for PgUp) in the input buffer;
# those tail bytes were then misread as literal keys ('D' -> phantom
# move, 'C' -> phantom hold). Keep parsing byte-wise until the final
# byte, and flush on anything unexpected.
read_escape_sequence() {
    local b="" rc=0 i
    # A lone ESC key has no follow-up byte; a sequence delivers it
    # within a few milliseconds.
    IFS= read -rsn1 -t 0.02 b || rc=$?
    if [ "${rc}" -ne 0 ]; then
        KEY="ESC"
        return 0
    fi
    case "${b}" in
        '[')
            # CSI sequence: optional parameter bytes (digits and ';'),
            # then one final byte. Bounded loop as a safety net against
            # binary garbage (e.g. stray mouse reports).
            for (( i = 0; i < 8; i++ )); do
                rc=0
                IFS= read -rsn1 -t 0.02 b || rc=$?
                if [ "${rc}" -ne 0 ]; then
                    # Sequence torn mid-way: drop it entirely.
                    input_flush
                    return 0
                fi
                case "${b}" in
                    [0-9\;]) : ;;
                    *)       break ;;
                esac
            done
            case "${b}" in
                A) KEY="UP" ;;
                B) KEY="DOWN" ;;
                C) KEY="RIGHT" ;;
                D) KEY="LEFT" ;;
                [0-9\;])
                    # Loop bound hit while still in parameter bytes.
                    input_flush
                    ;;
                *)
                    # Complete but unknown sequence (Home, PgUp, F-keys,
                    # ...): ignore it as a whole.
                    ;;
            esac
            ;;
        O)
            # SS3 variant (application cursor mode): ESC O A..D.
            rc=0
            IFS= read -rsn1 -t 0.02 b || rc=$?
            if [ "${rc}" -ne 0 ]; then
                input_flush
                return 0
            fi
            case "${b}" in
                A) KEY="UP" ;;
                B) KEY="DOWN" ;;
                C) KEY="RIGHT" ;;
                D) KEY="LEFT" ;;
                *) : ;;
            esac
            ;;
        *)
            # ESC followed by a printable byte (Alt+key chords): ignore.
            ;;
    esac
    return 0
}

# read_key
# Wait up to TICK_S for a key press and map it to a symbolic name in the
# global KEY: LEFT RIGHT UP DOWN SPACE ENTER ESC or a literal lowercase
# letter/digit. KEY is empty when no (usable) key arrived. Uppercase
# letters are ignored on purpose: the finals of escape sequences are
# uppercase, so mapping them to bindings would reintroduce phantom keys.
# A closed stdin is a fatal error so the loop cannot spin at full speed.
read_key() {
    KEY=""
    local c="" rc=0
    IFS= read -rsn1 -t "${TICK_S}" c || rc=$?
    if [ "${rc}" -gt 128 ]; then
        # Timeout: no key pressed during this tick.
        return 0
    elif [ "${rc}" -ne 0 ]; then
        die "Input stream closed (stdin is gone)"
    fi
    case "${c}" in
        $'\e')
            read_escape_sequence
            ;;
        ' ')
            KEY="SPACE"
            ;;
        '')
            # Enter yields an empty read (newline is the read delimiter).
            KEY="ENTER"
            ;;
        [a-z0-9])
            KEY="${c}"
            ;;
        *)
            # Uppercase, punctuation, control bytes: ignore.
            ;;
    esac
    return 0
}
