#!/usr/bin/env bash
#
# lib/clock.sh
#
# Description:
#   Millisecond elapsed-time clock with wall-clock jump correction.
#   Keeps the fast wall source's resolution and checks it against Linux
#   boot time. Shared by the game, hub and network deadlines; calendar
#   dates continue to use date(1) directly.
#   Library file: source from rowhammer.sh; no command-line parameters.
#
# Program flow:
#   1. Select and validate the wall source and /proc/uptime at startup.
#   2. Bracket each wall reading with two boot-time readings.
#   3. Correct detected jumps with a process-wide offset; never go back.
#
# Version: 1.0.0  (2026-10-10)

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/clock.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# CLOCK_SRC: which time source now_ms uses. Resolved once here rather
# than probed per call - the game loop asks for the time several times
# per frame.
CLOCK_SRC=""
CLOCK_OFFSET_MS=0
CLOCK_READY=0
CLOCK_TOLERANCE_MS=20
# clock_wall_source_init
# Pick the time source and report whether one works at all. bash 5's
# EPOCHREALTIME is the first choice (no fork); below that the only
# millisecond clock left is date +%s%N.
# CHANGE 2026-09-06 (SP-001 of the singleplayer review): the date path is
# now verified before the game relies on it. %N is a GNU extension and
# not required by POSIX, so a date(1) without it either passes the letter
# through ("1757000000N") or drops it and leaves the plain seconds
# behind. The first form makes $(( )) fail, which under set -e killed the
# game in the middle of a round - at the one moment nobody can do
# anything about it; the second form is worse, because it looks like a
# number and would put the clock in 1970 once divided by a million.
# Hence the two-part probe: all digits, and exactly nine digits longer
# than the plain seconds. A source that fails it is a startup error like
# the bash version above, not a degraded mode - a game whose gravity and
# lock delay are measured in whole seconds is not this game.
# Invoked after the non-clock CLI paths rather than in the prerequisites,
# for the same reason the tty check is (see there): --help and --reset never ask
# what time it is. The headless multiplayer processes do, though -
# the hub's tick and its timeouts run on this clock - so unlike the
# tty check this one is not skipped for them.
clock_wall_source_init() {
    if [ -n "${EPOCHREALTIME:-}" ]; then
        CLOCK_SRC="epochrealtime"
        return 0
    fi
    local secs nsec
    # STDERR is deliberately not swallowed: a missing date(1) says so
    # itself, and the message lands before the alternate screen.
    secs="$(date +%s)" || return 1
    nsec="$(date +%s%N)" || return 1
    [[ "${secs}" =~ ^[0-9]+$ ]] || return 1
    [[ "${nsec}" =~ ^[0-9]+$ ]] || return 1
    [ "${#nsec}" -eq $(( ${#secs} + 9 )) ] || return 1
    CLOCK_SRC="date"
    return 0
}

# Read Linux boot time without forking. The kernel prints hundredths of
# a second: each value is the lower edge of a ten-millisecond interval.
# BOOTTIME includes suspend, so a real suspension is elapsed time too.
clock_boot_read() {
    local uptime idle
    IFS=' ' read -r uptime idle < /proc/uptime || return 1
    [[ "${uptime}" =~ ^[0-9]+[.][0-9]{2}$ ]] || return 1
    CLOCK_BOOT_MS=$(( 10#${uptime%.*} * 1000 + 10#${uptime#*.} * 10 ))
}

# Read the validated wall source into a global (no command substitution
# on Bash 5). Normalize the decimal comma used by some locales.
clock_wall_read() {
    if [ "${CLOCK_SRC}" = "epochrealtime" ]; then
        local t="${EPOCHREALTIME/,/.}" usec
        usec="${t#*.}"
        CLOCK_WALL_MS=$(( ${t%.*} * 1000 + 10#${usec:0:3} ))
    else
        local nsec
        nsec="$(date +%s%N)" || return 1
        [[ "${nsec}" =~ ^[0-9]+$ ]] || return 1
        CLOCK_WALL_MS=$(( 10#${nsec} / 1000000 ))
    fi
}

# Bracket the wall sample: scheduling or date(1) may take time between
# reads. Keep the entire possible boot-time interval instead of treating
# that sampling delay as a wall jump. +9 accounts for truncation to 10 ms.
clock_sample() {
    clock_boot_read || return 1
    CLOCK_BOOT_LO="${CLOCK_BOOT_MS}"
    clock_wall_read || return 1
    clock_boot_read || return 1
    CLOCK_BOOT_HI=$(( CLOCK_BOOT_MS + 9 ))
    (( CLOCK_BOOT_HI >= CLOCK_BOOT_LO ))
}

# Fail before entering a round if either source is unavailable. Help and
# reset bypass this check in rowhammer.sh; headless network roles do not.
clock_source_init() {
    clock_wall_source_init || return 1
    clock_sample || return 1
    CLOCK_OFFSET_MS=0
    CLOCK_REF_WALL="${CLOCK_WALL_MS}"
    CLOCK_REF_LO="${CLOCK_BOOT_LO}"
    CLOCK_REF_HI="${CLOCK_BOOT_HI}"
    CLOCK_LAST_MS="${CLOCK_WALL_MS}"
    NOW_MS="${CLOCK_WALL_MS}"
    CLOCK_READY=1
}

# now_ms: corrected wall time in NOW_MS. Keep an anchor rather than only
# comparing adjacent ticks: several small changes can accumulate into a
# detectable drift. A jump is outside the boot intervals plus a 20-ms
# tolerance. Reconstruct that sample from the intervals' midpoints, then
# preserve the offset for every caller. Normal samples retain 1-ms steps;
# a correction has the boot intervals' uncertainty, not 1-ms accuracy.
now_ms() {
    if [ "${CLOCK_READY}" -ne 1 ] || ! clock_sample; then
        die "cannot read elapsed-time clock (wall source and /proc/uptime required)"
    fi
    local wall_delta low high jump corrected=0
    wall_delta=$(( CLOCK_WALL_MS - CLOCK_REF_WALL ))
    low=$(( CLOCK_BOOT_LO - CLOCK_REF_HI - CLOCK_TOLERANCE_MS ))
    high=$(( CLOCK_BOOT_HI - CLOCK_REF_LO + CLOCK_TOLERANCE_MS ))
    if (( wall_delta < low || wall_delta > high )); then
        jump=$(( wall_delta - (CLOCK_BOOT_LO + CLOCK_BOOT_HI - CLOCK_REF_LO - CLOCK_REF_HI) / 2 ))
        CLOCK_OFFSET_MS=$(( CLOCK_OFFSET_MS + jump ))
        CLOCK_REF_WALL="${CLOCK_WALL_MS}"
        CLOCK_REF_LO="${CLOCK_BOOT_LO}"
        CLOCK_REF_HI="${CLOCK_BOOT_HI}"
        corrected=1
    elif (( CLOCK_BOOT_HI - CLOCK_BOOT_LO < CLOCK_REF_HI - CLOCK_REF_LO )); then
        # Improve an anchor obtained while the process was descheduled.
        CLOCK_REF_WALL="${CLOCK_WALL_MS}"
        CLOCK_REF_LO="${CLOCK_BOOT_LO}"
        CLOCK_REF_HI="${CLOCK_BOOT_HI}"
    fi
    NOW_MS=$(( CLOCK_WALL_MS - CLOCK_OFFSET_MS ))
    # A small backward step within tolerance is ambiguous. Clamp it until
    # the source catches up, rather than subtracting already played time.
    if (( NOW_MS < CLOCK_LAST_MS )); then
        NOW_MS="${CLOCK_LAST_MS}"
    fi
    CLOCK_LAST_MS="${NOW_MS}"
    # debug_event timestamps via now_ms itself. Publish the complete
    # correction first and suppress nested reports to avoid recursion.
    if [ "${corrected}" -eq 1 ] && [ "${CLOCK_LOGGING:-0}" -eq 0 ]; then
        local CLOCK_LOGGING=1
        debug_event "clock: corrected wall jump=${jump}ms offset=${CLOCK_OFFSET_MS}ms"
    fi
}
