#!/usr/bin/env bash
#
# lib/state.sh
#
# Description:
#   Round state of rowhammer, named and switchable (CLAUDE.md 5.20).
#   The game keeps a round in globals - the board, the instance tables,
#   the queue, the bag, the falling piece, the counters, the clocks and
#   the garbage queue. That is exactly right for one round and not enough
#   for the multiplayer demo playback, which has to hold up to MP_MAX
#   rounds at the same time and simulate all of them.
#   This module is the answer: STATE_VARS lists the round state once, and
#   state_bind points every one of those names at the backing variables of
#   one slot using namerefs (declare -n). The game's functions keep
#   writing to BOARD, ROW_CREDIT and the rest and do not know that the
#   variable behind the name has changed - so nothing in the round logic
#   has to be parametrised for a second player.
#   The list here is the single place the round state is enumerated: a new
#   counter is added to it and nowhere else. It is kept in step with
#   game_reset (rowhammer.sh), which is the other end of the same list -
#   what a round resets is what a round consists of.
#   No user of this module exists yet: the game still runs on the plain
#   globals, and step 9.9 is where the playback starts binding slots.
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Program flow (how a caller uses it):
#   1. state_new SLOT   - create the backing variables of one slot.
#   2. state_bind SLOT  - point the round state names at that slot.
#   3. ... run the ordinary round functions, they write into the slot ...
#   4. state_bind OTHER - switch to another slot (no unbinding needed).
#   5. state_release SLOT - drop a slot's variables when it is done.
#
# Version: 1.0.0  (2026-09-02)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/state.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# --- The round state ------------------------------------------------------
# One entry per variable, "<kind>:<name>":
#   a - indexed array
#   A - associative array
#   s - scalar
# The kind is what state_new has to know; state_bind treats all three the
# same, because a nameref does not care what it points at.
#
# What is deliberately NOT in here, so the boundary stays visible:
#   - Session and loop state: DIRTY, RENDER_FULL, GAME_EXIT, GAME_SUSPENDED,
#     GAME_RESTART, REDRAW_PENDING, NOW_MS. They belong to the one process
#     and the one screen, not to a round - a playback of five rounds still
#     draws one picture and has one exit flag.
#   - Values transient within a single lock: NEXT_TYPE (bag_next hands it
#     to spawn_piece), FULL_ROWS and FLASH_ROWS (board_full_rows fills
#     them, clear_lines and flash_rows consume them right after). They
#     never survive the function that produced them, so a slot cannot
#     carry them across a context switch either.
#   - Everything the player configured (keys, colours, name) and every
#     tuning constant (LEVEL_SPEEDS, ULTRA_TARGET_ROWS, ...): the same for
#     every slot by definition.
STATE_VARS=(
    # Board: cell type, piece instance id and square status, three
    # parallel arrays over BOARD_W * BOARD_H cells (lib/board.sh).
    a:BOARD
    a:BOARD_ID
    a:BOARD_SQ
    # Which instances are cut (a clear ran through them) and which have
    # been consumed by a square. Associative, keyed by instance id.
    A:INSTANCE_CUT
    A:INSTANCE_SQUARED
    s:NEXT_INSTANCE_ID
    # Piece supply: the shuffled bag and the preview queue (lib/pieces.sh).
    a:BAG
    a:QUEUE
    # The falling piece and the hold slot.
    s:CUR_TYPE
    s:CUR_ROT
    s:CUR_X
    s:CUR_Y
    s:HOLD_TYPE
    s:HOLD_USED
    # The round's counters - the numbers the HUD shows and record_round
    # banks into the highscore list, the statistics and the wonder.
    s:CLEARED_TOTAL
    s:ROW_CREDIT
    s:LEVEL
    s:FALL_MS
    s:GOLD_COUNT
    s:SILVER_COUNT
    s:ROWHAMMER_COUNT
    s:PIECE_COUNT
    # Where the round stands: paused, over, its mode's goal reached, and
    # whether it has been booked already.
    s:GAME_MODE
    s:PAUSED
    s:GAME_OVER
    s:GOAL_REACHED
    s:ROUND_RECORDED
    # The clocks: gravity, lock delay and play time.
    s:LAST_FALL
    s:LOCK_PENDING
    s:TOUCHDOWN_MS
    s:PLAY_MS
    s:PLAY_LAST
    # Mode state: the Time Attack budget and the play time the next flood
    # row of a Hochwasser round is due at.
    s:TIME_ATTACK_BUDGET_MS
    s:FLOOD_NEXT_MS
    # The garbage waiting to be pushed into this board and the gap column
    # it will have. Round state like everything else here - in a playback
    # every simulated player has a queue of their own (CLAUDE.md 5.7).
    s:MP_PENDING
    s:MP_HOLE
)

# Prefix of the backing variables. Slot 2's board lives in RSTATE2_BOARD;
# the name is long enough that nothing else in the game can collide with
# it, and it says where it comes from when it shows up in a "declare -p".
STATE_PREFIX="RSTATE"

# The slot the round state names currently point at, -1 while they are
# still the plain globals the game starts with. state_bind reads it to
# find out whether it has to break that first binding.
STATE_SLOT=-1

# Slots created with state_new, so state_new can be called twice without
# wiping a slot that is already in use and state_release knows there is
# something to drop. Keyed by slot number.
declare -A STATE_MADE=()

# state_new SLOT
# Create the backing variables of one slot, empty. Does nothing when the
# slot already exists - so a caller may set up its slots once per round
# without keeping track of what it has already made.
# The slot number is used to build a variable name and is therefore
# checked against a digit pattern first: everything in this game that
# builds a name from a number does that, and here it is what keeps a
# stray value out of a "declare -g".
state_new() {
    local slot="${1}" entry kind name bname
    if ! [[ "${slot}" =~ ^[0-9]{1,2}$ ]]; then
        return 1
    fi
    if [ -n "${STATE_MADE[${slot}]+set}" ]; then
        return 0
    fi
    for entry in "${STATE_VARS[@]}"; do
        kind="${entry%%:*}"
        name="${entry#*:}"
        bname="${STATE_PREFIX}${slot}_${name}"
        case "${kind}" in
            a) declare -g -a "${bname}=()" ;;
            A) declare -g -A "${bname}=()" ;;
            s) declare -g "${bname}=" ;;
            *) return 1 ;;
        esac
    done
    STATE_MADE["${slot}"]=1
    return 0
}

# state_bind SLOT
# Point every name in STATE_VARS at that slot's backing variables. From
# here on the ordinary round functions - try_move, lock_and_next,
# clear_lines and the rest - read and write this slot without knowing it.
#
# The first bind has to unset the plain globals first: a variable that
# already holds an array cannot be turned into a nameref, bash refuses it
# with "cannot make a nameref out of an existing variable" (measured with
# bash 5.2). And it has to be a real "unset", not "unset -n" - the latter
# only removes a nameref attribute, which these do not have yet. Every
# later bind is a plain reassignment of an existing nameref, which bash
# does allow; that is the cheap path, and it is the one a playback takes
# several times per frame.
# The values in the globals are discarded by that first unset. That is
# correct rather than lossy: a caller binds slots to run rounds inside
# them, and the round it started from is not one of those slots.
state_bind() {
    local slot="${1}" entry name
    if ! [[ "${slot}" =~ ^[0-9]{1,2}$ ]]; then
        return 1
    fi
    if [ -z "${STATE_MADE[${slot}]+set}" ]; then
        state_new "${slot}" || return 1
    fi
    if [ "${STATE_SLOT}" -lt 0 ]; then
        for entry in "${STATE_VARS[@]}"; do
            name="${entry#*:}"
            unset "${name}"
        done
    fi
    for entry in "${STATE_VARS[@]}"; do
        name="${entry#*:}"
        declare -g -n "${name}=${STATE_PREFIX}${slot}_${name}"
    done
    STATE_SLOT="${slot}"
    return 0
}

# state_unbind
# Drop the namerefs and leave the round state names undefined, so the
# game can go back to plain globals (a playback returning to the menu).
# "unset -n" is the point here: a plain unset would follow the reference
# and delete the slot's data instead of the pointer to it.
state_unbind() {
    local entry name
    [ "${STATE_SLOT}" -ge 0 ] || return 0
    for entry in "${STATE_VARS[@]}"; do
        name="${entry#*:}"
        unset -n "${name}"
    done
    STATE_SLOT=-1
    return 0
}

# state_release SLOT
# Drop a slot's backing variables. The slot must not be the one currently
# bound - the names would then point at variables that no longer exist -
# so a bound slot is unbound first rather than left dangling.
state_release() {
    local slot="${1}" entry name
    if ! [[ "${slot}" =~ ^[0-9]{1,2}$ ]]; then
        return 1
    fi
    [ -n "${STATE_MADE[${slot}]+set}" ] || return 0
    if [ "${STATE_SLOT}" -eq "${slot}" ]; then
        state_unbind
    fi
    for entry in "${STATE_VARS[@]}"; do
        name="${entry#*:}"
        unset "${STATE_PREFIX}${slot}_${name}"
    done
    unset "STATE_MADE[${slot}]"
    return 0
}

# state_release_all
# Drop every slot. The way back to a plain, single-round process - a
# playback calls it when it returns to the list it was started from.
state_release_all() {
    local slot
    state_unbind
    for slot in "${!STATE_MADE[@]}"; do
        state_release "${slot}"
    done
    return 0
}
