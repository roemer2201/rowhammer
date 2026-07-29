#!/usr/bin/env bash
#
# lib/input.sh
#
# Description:
#   Terminal setup and non-blocking keyboard input for rowhammer. Switches
#   to the alternate screen buffer, hides the cursor, turns autowrap off
#   (the centered game block fills a 48x22 terminal down to its last cell)
#   and provides a
#   single-key reader that understands the arrow-key escape sequences.
#   Since 0.8.0 the terminal is put into raw input mode once for the whole
#   session (term_input_raw: echo and canonical mode off) instead of
#   relying on the mode a single "read -rsn1" installs and drops again:
#   between two reads the terminal used to echo whatever was typed onto
#   the screen, where the incremental renderer left it standing (issue
#   #33). Only the player name prompt switches back to line mode
#   (term_input_line) so the terminal draws the typed name.
#   Escape sequences are parsed by a state machine (key_feed and its
#   key_in_* helpers) whose state lives in globals and therefore survives
#   across read_key calls and game ticks. A sequence the terminal delivers
#   in pieces - over SSH, inside tmux/screen or under load - is still
#   assembled into one sequence however large the gap between its bytes,
#   which is the structural fix for issue #7: up to 0.5.0 the decision had
#   to be made inside one call and late bytes were applied as separate key
#   presses (the trailing "C" of a right arrow became the hold key "c").
#   The same parser consumes the sequence classes that used to leak their
#   payload as key presses: X10 mouse reports, OSC/DCS terminal replies,
#   8-bit CSI, over-long CSI sequences and bracketed paste. Bytes that are
#   not printable ASCII are discarded rather than reported.
#   Callers that pause the game and throw input away (the row-clear
#   flash, the "resize me" overlay) use key_drain rather than reading
#   bytes raw, so a discarded sequence is discarded whole instead of
#   leaving its tail behind for the next read.
#   Enter is reported as ENTER so the menu system can use it as "select".
#   In debug mode every received key press is recorded (raw bytes plus
#   mapped symbol) via debug_input from lib/debug.sh. Terminal resizing is
#   handled here too (since 0.5.0): a SIGWINCH trap armed by term_setup
#   flags the resize, and read_key applies it via term_resize_apply -
#   remeasure (term_measure), recenter the game block (layout_update),
#   clear and let the caller repaint, and while
#   the terminal is too small for the fixed layout, block on a "resize me"
#   overlay until it grows back.
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.8.0  (2026-07-29)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/input.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# Poll interval of the game loop in seconds. The read timeout doubles as
# the tick pacing of the main loop, so the game never busy-waits.
TICK_S="0.02"

# Timeout in seconds for the follow-up bytes of an escape sequence
# *within* one read_key call. Up to 0.5.0 this window (then named
# ESC_SUFFIX_T, 50 ms) decided whether a sequence was complete, and a
# byte arriving later was applied as a separate key press - the trailing
# "C" of a right arrow became the hold key "c" (issue #7). Since 0.6.0
# the parser keeps its state across ticks (ESC_STATE), so this value
# decides nothing any more; it only lets a sequence torn by a few
# milliseconds still finish inside a single call instead of spanning
# several ticks. The 50 ms are kept from the 0.16.1 fix for the reason
# given there: over SSH, inside tmux/screen or under load the bytes of
# one arrow key routinely arrive that far apart.
SEQ_BYTE_T="0.05"

# How long a lone ESC waits for a continuation byte before it is reported
# as the Esc key. This is the only time-based decision left in the input
# layer and it is deliberately generous: a sequence whose rest arrives
# even later is still absorbed (see the esc_late state in key_feed), and
# 300 ms is not noticeable when Esc is pressed on purpose.
ESC_LONE_MS=300

# How long the esc_late state keeps absorbing a late continuation before
# it falls back to normal reading. Bounds the window in which a "[" or
# "O" typed by the user would be mistaken for the rest of a torn
# sequence.
ESC_LATE_MS=1000

# A byte following ESC within this window comes from the terminal itself
# (an Alt chord sends ESC and the key's byte back to back) and is dropped
# together with the ESC. A larger gap means the user pressed Esc and then
# a second key, and both are reported: up to 0.5.0 the pair was swallowed
# unconditionally, so a deliberate Esc was lost whenever another key
# followed quickly.
ESC_ALT_MS=30

# Length caps. A CSI sequence longer than SEQ_MAX bytes is not a key
# press; the parser then keeps discarding up to the final byte instead of
# leaking the tail as key presses (the 16 byte cap used up to 0.5.0 did
# leak). STR_MAX and PASTE_MAX stop an unterminated terminal reply or
# paste from swallowing the keyboard for good.
SEQ_MAX=64
STR_MAX=512
PASTE_MAX=65536

# Escape parser state, kept across read_key calls (and therefore across
# game ticks) so that a sequence delivered in pieces is still parsed as
# one sequence:
#   ""        idle
#   esc       ESC seen, waiting for the introducer
#   esc_late  a lone ESC was already reported, a late rest is absorbed
#   csi       inside ESC [ ... / ESC O ... , collecting up to the final byte
#   str       inside OSC/DCS/APC/PM/SOS, discarding up to ST or BEL
#   mouse     X10 mouse report, discarding the three raw bytes
#   paste     inside a bracketed paste, discarding up to ESC [ 201 ~
ESC_STATE=""
ESC_SEQ=""
ESC_SINCE=0
ESC_DROP=0
SEQ_N=0
MOUSE_N=0
STR_ESC=0
PASTE_TAIL=""
# One key that was parsed but could not be reported yet (Esc plus the key
# pressed after it); handed out by the next read_key call.
KEY_EXTRA=""
# Raw bytes collected for the key press currently being assembled, for
# the debug log. Capped so a large paste cannot grow it without bound.
RAW_BUF=""

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
# the fixed 48x22 layout the function blocks on the "resize me" overlay
# (term_too_small_screen) until it grows back, so the game never tries to
# draw a torn board.
term_resize_apply() {
    TERM_RESIZED=0
    term_measure
    # Recenter the fixed game block on the new size and force a full
    # repaint (the diff renderer must not compare against lines that now
    # sit at different coordinates).
    layout_update
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
    # resumes. The wait goes through key_drain rather than a raw read so
    # a half-consumed escape sequence cannot leave its tail behind.
    while [ "${TERM_TOO_SMALL}" -eq 1 ]; do
        term_too_small_screen
        key_drain 200
        if [ "${TERM_RESIZED}" -eq 1 ]; then
            TERM_RESIZED=0
            term_measure
            layout_update
            screen_write $'\e[2J\e[H'
        fi
    done
    if [ "${was_too_small}" -eq 1 ]; then
        debug_event "terminal size ok again: ${TERM_COLS}x${TERM_ROWS}"
    fi
}

# term_input_raw
# Put the terminal into the input mode the game runs in: echo off and
# canonical (line) mode off, so a key press is neither shown by the
# terminal nor held back until Enter.
#
# Up to 0.28.0 no mode was set at all. The game relied on the temporary
# mode "read -rsn1" installs for the duration of a single read and
# restores right after, which left echo and line mode on for everything
# between two reads - building and writing a frame, the row-clear flash,
# and the pause and game over screens, where the game sits in short reads
# but spends most of its time elsewhere. A key pressed in such a gap was
# echoed by the terminal at the cursor position, i.e. behind the last
# line the renderer had written. Since 0.22.0 only the lines that changed
# are rewritten (see lib/render.sh), so nothing painted over the echoed
# bytes again and they stayed on screen - "^[[C" next to the board, and
# on a paused or finished round they never went away (issue #33). Before
# the incremental renderer a full repaint had covered them up one frame
# later, which is why the artifacts only surfaced now.
#
# "min 1 time 0" keeps a byte-wise read blocking until at least one byte
# arrives; the game's timeouts come from bash's "read -t", which is
# unaffected by these settings. term_restore puts the saved state back.
term_input_raw() {
    stty -echo -icanon min 1 time 0 ||
        die "Cannot switch the terminal into raw input mode"
}

# term_input_line
# Hand the line editing back to the terminal (canonical mode with echo)
# for the one prompt that wants it: the player name input in
# prompt_player_name, where the terminal draws the typed name and handles
# backspace. Every other prompt reads single keys through read_key and
# stays in raw mode. The caller switches back with term_input_raw.
term_input_line() {
    stty icanon echo ||
        die "Cannot switch the terminal into line input mode"
}

# Enter the alternate screen buffer, clear it and hide the cursor. The
# current stty state is saved first so term_restore can bring the terminal
# back exactly as it was, and the terminal is switched into the raw input
# mode the game needs for the whole session (term_input_raw). A SIGWINCH
# trap is armed here so a resize during play is noticed: the handler only
# flags TERM_RESIZED (signal-safe), and read_key applies it via
# term_resize_apply on the next tick.
term_setup() {
    SAVED_STTY="$(stty -g)"
    term_input_raw
    # Autowrap off (\e[?7l) alongside the alternate screen: the centered
    # game block fills the terminal exactly at the 48x22 minimum, so its
    # bottom right character lands in the very last cell. With autowrap on
    # that cell can push the screen up one line on some terminals; with it
    # off the write simply stays put. term_restore turns it back on.
    # Bracketed paste is switched on so pasted text arrives wrapped in
    # ESC [ 200 ~ ... ESC [ 201 ~ and the parser can discard it in one
    # piece; without it an accidental middle-click paste runs every
    # pasted character as a game command. The mouse reporting modes are
    # switched off for the opposite reason: the game never enables them,
    # but a mode left behind by a program that ran before it stays active
    # here, and an X10 click injects raw bytes as key presses (see
    # key_in_csi). Terminals that do not know a mode ignore it.
    screen_write $'\e[?1049h\e[?7l\e[2J\e[H\e[?25l\e[?2004h\e[?1000l\e[?1002l\e[?1003l\e[?1005l\e[?1006l\e[?1015l'

    trap 'TERM_RESIZED=1' WINCH
    TERM_ACTIVE=1
    debug_event "terminal: alternate screen on, cursor hidden, bracketed paste on, mouse reporting off, resize watch armed"
}

# Restore cursor, screen buffer and stty state. Idempotent on purpose: it
# serves both the EXIT/INT/TERM trap and the regular quit path, and must
# not garble the screen when it runs twice. The SIGWINCH trap is dropped
# so no resize handling runs once the game has left the alternate screen.
term_restore() {
    if [ "${TERM_ACTIVE}" -eq 1 ]; then
        debug_event "terminal: restoring screen and stty state"
        trap - WINCH
        screen_write $'\e[?2004l\e[?25h\e[?7h\e[?1049l'
        if [ -n "${SAVED_STTY}" ]; then
            stty "${SAVED_STTY}" || stty sane
        fi
        TERM_ACTIVE=0
    fi
}

# key_emit SYMBOL
# Report a key press and flush the raw bytes collected for it into the
# debug log.
key_emit() {
    KEY="${1}"
    debug_input "${RAW_BUF}" "${KEY}"
    RAW_BUF=""
}

# key_drop REASON
# Finish a byte group that is not a key press. Logged like a key press so
# the debug trace still shows what was swallowed and why (mouse report,
# terminal reply, paste, ...).
key_drop() {
    debug_input "${RAW_BUF}" "(${1})"
    RAW_BUF=""
}

# key_plain BYTE
# Map a byte that is not part of an escape sequence. Enter arrives as an
# empty read (the newline is read's delimiter) and space gets its own
# name so the bindings can use it; letters are matched case-insensitively.
# Anything that is not printable ASCII - control characters, the single
# bytes of a UTF-8 character - is discarded instead of becoming a key:
# nothing in the game is bound to it, and passing it on only invites the
# kind of misreading issue #7 is about.
key_plain() {
    local b="${1}" ord
    case "${b}" in
        $'\e')
            ESC_STATE="esc"
            now_ms
            ESC_SINCE="${NOW_MS}"
            return 0
            ;;
        $'\x9b')
            # 8-bit CSI: a terminal in 8-bit mode sends this single byte
            # instead of "ESC [". Entering the CSI parser here means the
            # rest of the sequence is consumed as a sequence; up to 0.5.0
            # the byte fell through and the letter behind it arrived as a
            # key press ("\x9b A" moved the piece left).
            ESC_STATE="csi"
            ESC_SEQ="["
            SEQ_N=0
            ESC_DROP=0
            return 0
            ;;
        ' ')
            key_emit "SPACE"
            return 0
            ;;
        '')
            key_emit "ENTER"
            return 0
            ;;
    esac
    printf -v ord '%d' "'${b}"
    if [ "${ord}" -ge 33 ] && [ "${ord}" -le 126 ]; then
        key_emit "${b,,}"
    else
        key_drop "inert byte"
    fi
    return 0
}

# key_after_esc BYTE
# Handle the byte behind an ESC: the introducer of a sequence, an Alt
# chord, or the key the user pressed after a real Esc.
key_after_esc() {
    local b="${1}"
    case "${b}" in
        '['|'O')
            ESC_STATE="csi"
            ESC_SEQ="${b}"
            SEQ_N=0
            ESC_DROP=0
            ;;
        ']'|'P'|'^'|'_'|'X')
            # OSC, DCS, APC, PM and SOS carry a string payload ending at
            # a String Terminator (ESC \) or BEL. They are terminal
            # replies (colour query, XTVERSION, clipboard), never key
            # presses - but up to 0.5.0 only "[" and "O" were known here,
            # so the whole payload arrived as individual key presses
            # ("r" restarted the round, "x" opened the pause menu).
            ESC_STATE="str"
            SEQ_N=0
            STR_ESC=0
            ;;
        *)
            now_ms
            if [ $(( NOW_MS - ESC_SINCE )) -lt "${ESC_ALT_MS}" ]; then
                # Back to back with the ESC: an Alt chord sent by the
                # terminal. Neither byte is a game key, drop both.
                ESC_STATE=""
                key_drop "alt chord"
            else
                # Too far apart to be one chord: the user pressed Esc and
                # then another key. Report the Esc now and keep the
                # second key for the next call instead of swallowing both.
                RAW_BUF=$'\e'
                key_emit "ESC"
                ESC_STATE=""
                RAW_BUF="${b}"
                KEY=""
                key_plain "${b}"
                KEY_EXTRA="${KEY}"
                KEY="ESC"
            fi
            ;;
    esac
}

# key_in_csi BYTE
# Collect a CSI or SS3 sequence up to its final byte (ASCII 0x40..0x7e)
# and map the four cursor keys; everything else is discarded as a whole.
key_in_csi() {
    local b="${1}" ord sym=""
    SEQ_N=$(( SEQ_N + 1 ))
    if [ "${SEQ_N}" -gt "${SEQ_MAX}" ]; then
        # Far longer than any key press. Keep reading up to the final
        # byte so the tail cannot leak, but discard the result. The 16
        # byte cap used up to 0.5.0 stopped here and let the rest through
        # as key presses (a long device reply ended on "c" = hold).
        ESC_DROP=1
    else
        ESC_SEQ="${ESC_SEQ}${b}"
    fi
    # The Linux console sends function keys as ESC [ [ X; the second "["
    # is not a final byte there, exactly one more byte follows.
    if [ "${ESC_SEQ}" = '[[' ]; then
        return 0
    fi
    printf -v ord '%d' "'${b}"
    if [ "${ord}" -lt 64 ] || [ "${ord}" -gt 126 ]; then
        return 0
    fi
    if [ "${ESC_SEQ}" = '[M' ]; then
        # X10 mouse report (DECSET 1000): three raw bytes follow the
        # final "M" - button, column and row, each offset by 32 and hence
        # printable. Up to 0.5.0 they arrived as key presses, so every
        # click was a hard drop (the left button byte is 0x20 = space)
        # plus whatever the column byte happened to map to (column 67 ->
        # "c" = hold). The SGR (1006) and urxvt (1015) protocols need no
        # special case, they end cleanly on their final byte.
        ESC_STATE="mouse"
        MOUSE_N=3
        return 0
    fi
    if [ "${ESC_SEQ}" = '[200~' ]; then
        # Start of a bracketed paste (enabled in term_setup): swallow the
        # pasted text instead of running it as game commands.
        ESC_STATE="paste"
        SEQ_N=0
        PASTE_TAIL=""
        return 0
    fi
    if [ "${ESC_DROP}" -eq 0 ]; then
        case "${ESC_SEQ}" in
            '[A'|'OA') sym="UP" ;;
            '[B'|'OB') sym="DOWN" ;;
            '[C'|'OC') sym="RIGHT" ;;
            '[D'|'OD') sym="LEFT" ;;
        esac
    fi
    ESC_STATE=""
    ESC_SEQ=""
    ESC_DROP=0
    if [ -n "${sym}" ]; then
        key_emit "${sym}"
    else
        key_drop "sequence"
    fi
}

# key_in_str BYTE
# Discard the payload of an OSC/DCS/APC/PM/SOS reply up to its String
# Terminator (ESC \) or BEL.
key_in_str() {
    local b="${1}"
    SEQ_N=$(( SEQ_N + 1 ))
    if [ "${STR_ESC}" -eq 1 ]; then
        STR_ESC=0
        if [ "${b}" = '\' ]; then
            ESC_STATE=""
            key_drop "terminal reply"
            return 0
        fi
    fi
    case "${b}" in
        $'\e') STR_ESC=1; return 0 ;;
        $'\a')
            ESC_STATE=""
            key_drop "terminal reply"
            return 0
            ;;
    esac
    if [ "${SEQ_N}" -gt "${STR_MAX}" ]; then
        # Unterminated: stop swallowing rather than lock the keyboard.
        ESC_STATE=""
        key_drop "overlong terminal reply"
    fi
}

# key_in_mouse BYTE
# Discard the three raw coordinate bytes of an X10 mouse report.
key_in_mouse() {
    MOUSE_N=$(( MOUSE_N - 1 ))
    if [ "${MOUSE_N}" -le 0 ]; then
        ESC_STATE=""
        key_drop "mouse report"
    fi
}

# key_in_paste BYTE
# Discard pasted text up to the closing ESC [ 201 ~ marker.
key_in_paste() {
    local b="${1}"
    SEQ_N=$(( SEQ_N + 1 ))
    PASTE_TAIL="${PASTE_TAIL}${b}"
    if [ "${#PASTE_TAIL}" -gt 6 ]; then
        PASTE_TAIL="${PASTE_TAIL: -6}"
    fi
    if [ "${PASTE_TAIL}" = $'\e[201~' ]; then
        ESC_STATE=""
        PASTE_TAIL=""
        key_drop "paste"
        return 0
    fi
    if [ "${SEQ_N}" -gt "${PASTE_MAX}" ]; then
        ESC_STATE=""
        PASTE_TAIL=""
        key_drop "overlong paste"
    fi
}

# key_feed BYTE
# Push one byte into the escape parser. The parser state lives in globals
# and therefore survives across read_key calls and game ticks: a sequence
# split by the terminal (SSH, tmux/screen, load) is still assembled into
# one sequence no matter how large the gap between its bytes. That is the
# structural fix for issue #7 - up to 0.5.0 the decision had to be made
# inside a single call, and bytes arriving after its timeout were applied
# as separate key presses.
key_feed() {
    local b="${1}"
    if [ "${#RAW_BUF}" -lt 64 ]; then
        RAW_BUF="${RAW_BUF}${b}"
    fi
    case "${ESC_STATE}" in
        '')   key_plain "${b}" ;;
        esc)  key_after_esc "${b}" ;;
        esc_late)
            # A lone ESC was reported because no continuation arrived in
            # time. If the rest of the sequence still shows up, it is
            # absorbed here instead of leaking as key presses - this is
            # what keeps a torn arrow key harmless even when the gap
            # exceeds ESC_LONE_MS.
            if [ "${b}" = '[' ] || [ "${b}" = 'O' ]; then
                ESC_STATE="csi"
                ESC_SEQ="${b}"
                SEQ_N=0
                ESC_DROP=1
            else
                ESC_STATE=""
                key_plain "${b}"
            fi
            ;;
        csi)   key_in_csi "${b}" ;;
        str)   key_in_str "${b}" ;;
        mouse) key_in_mouse "${b}" ;;
        paste) key_in_paste "${b}" ;;
    esac
}

# key_drain MS
# Wait about MS milliseconds while throwing away everything the user
# types - but route the bytes through the escape parser instead of
# reading them raw. Callers that deliberately pause the game (the
# row-clear flash in rowhammer.sh, the "resize me" overlay above) used to
# read single bytes directly, which reintroduced issue #7 behind the
# parser's back: a raw read that swallows only the ESC of an arrow key
# leaves "[C" in the buffer, and the next read_key applies the "C" as the
# hold key "c". Feeding the bytes to key_feed keeps a sequence atomic, so
# either all of it is discarded or none of it.
# Keys that do resolve are dropped on purpose - they must not fire on the
# piece that appears after the animation. A sequence still in flight when
# the window closes keeps its parser state and is finished by the next
# read_key, which is better than losing its tail.
key_drain() {
    local ms="${1}" left b rc timeout
    now_ms
    local deadline=$(( NOW_MS + ms ))
    while :; do
        now_ms
        left=$(( deadline - NOW_MS ))
        if [ "${left}" -le 0 ]; then
            return 0
        fi
        printf -v timeout '%d.%03d' $(( left / 1000 )) $(( left % 1000 ))
        b=""
        rc=0
        IFS= read -rsn1 -t "${timeout}" b || rc=$?
        if [ "${rc}" -gt 128 ]; then
            # Timeout, or a signal (SIGWINCH) interrupted the read. A byte
            # handed over together with the timeout status is still valid
            # and must be parsed, see read_key.
            if [ -z "${b}" ]; then
                return 0
            fi
        elif [ "${rc}" -ne 0 ]; then
            die "Input stream closed (stdin is gone)"
        fi
        key_feed "${b}"
        KEY=""
        KEY_EXTRA=""
    done
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
    # A key parsed but not reportable in the call that produced it (Esc
    # plus the key pressed after it) is handed out first.
    if [ -n "${KEY_EXTRA}" ]; then
        KEY="${KEY_EXTRA}"
        KEY_EXTRA=""
        return 0
    fi
    # The only time-based decision left in the input layer: an ESC that
    # has waited long enough without a continuation byte is the Esc key.
    # The state moves on to esc_late rather than back to idle, so a rest
    # that still arrives afterwards is absorbed instead of leaking.
    if [ "${ESC_STATE}" = "esc" ]; then
        now_ms
        if [ $(( NOW_MS - ESC_SINCE )) -ge "${ESC_LONE_MS}" ]; then
            ESC_STATE="esc_late"
            ESC_SINCE="${NOW_MS}"
            key_emit "ESC"
            return 0
        fi
    elif [ "${ESC_STATE}" = "esc_late" ]; then
        now_ms
        if [ $(( NOW_MS - ESC_SINCE )) -ge "${ESC_LATE_MS}" ]; then
            ESC_STATE=""
            RAW_BUF=""
        fi
    fi
    local c rc timeout="${TICK_S}"
    while :; do
        c=""
        rc=0
        IFS= read -rsn1 -t "${timeout}" c || rc=$?
        if [ "${rc}" -gt 128 ]; then
            # rc > 128 is a timeout. bash (observed on 5.1) can hand over
            # a byte together with the timeout status when it arrives in
            # the very moment the timeout expires; such a byte must not be
            # dropped: discarding it here silently swallowed the leading
            # ESC of an arrow-key sequence and its tail bytes were then
            # misread as normal key presses (issue #7). Only a timeout
            # without data means that no key arrived during this tick.
            if [ -z "${c}" ]; then
                return 0
            fi
        elif [ "${rc}" -ne 0 ]; then
            die "Input stream closed (stdin is gone)"
        fi
        key_feed "${c}"
        if [ -n "${KEY}" ]; then
            return 0
        fi
        case "${ESC_STATE}" in
            esc|csi|str|mouse|paste) ;;
            *) return 0 ;;
        esac
        # Mid-sequence: pull the remaining bytes within this call while
        # they are already there, so an intact sequence still costs a
        # single tick. If they are not, the call simply returns and the
        # parser continues on the next tick with its state intact.
        timeout="${SEQ_BYTE_T}"
    done
}
