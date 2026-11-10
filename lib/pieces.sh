#!/usr/bin/env bash
#
# lib/pieces.sh
#
# Description:
#   Piece definitions for rowhammer: the seven piece types with their
#   four rotation states, the configurable color schemes (symbolic color
#   names with a basic 8/16-color ANSI and an extended xterm 256-color
#   meaning, mapped to pieces, gold/silver squares and the flood rows of
#   the "Hochwasser" mode by the selectable
#   theme), a per-type two-character glyph (PIECE_GLYPH) that keeps pieces
#   distinguishable in the no-color mode, the bag randomizer (nine
#   complete sets of the seven types per bag, shuffled as a whole), the
#   generator that drives its shuffle (bag_seed/bag_rand, since 2.1.1:
#   the same sequence for a seed on every bash version, which RANDOM
#   does not give) and
#   the upcoming-piece queue that feeds the HUD preview. In debug mode
#   every bag refill is logged with the shuffled piece order.
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.11.0  (2026-11-09)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/pieces.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# Piece shapes follow the SRS (Super Rotation System) cell layout: for each
# piece type (I O T S Z J L) and rotation state (0-3, clockwise) the four
# occupied cells are listed as "x,y" offsets inside a 4x4 bounding box.
declare -A PIECE_SHAPE=(
    [I0]="0,1 1,1 2,1 3,1"  [I1]="2,0 2,1 2,2 2,3"
    [I2]="0,2 1,2 2,2 3,2"  [I3]="1,0 1,1 1,2 1,3"
    [O0]="1,0 2,0 1,1 2,1"  [O1]="1,0 2,0 1,1 2,1"
    [O2]="1,0 2,0 1,1 2,1"  [O3]="1,0 2,0 1,1 2,1"
    [T0]="1,0 0,1 1,1 2,1"  [T1]="1,0 1,1 2,1 1,2"
    [T2]="0,1 1,1 2,1 1,2"  [T3]="1,0 0,1 1,1 1,2"
    [S0]="1,0 2,0 0,1 1,1"  [S1]="1,0 1,1 2,1 2,2"
    [S2]="1,1 2,1 0,2 1,2"  [S3]="0,0 0,1 1,1 1,2"
    [Z0]="0,0 1,0 1,1 2,1"  [Z1]="2,0 1,1 2,1 1,2"
    [Z2]="0,1 1,1 1,2 2,2"  [Z3]="1,0 0,1 1,1 0,2"
    [J0]="0,0 0,1 1,1 2,1"  [J1]="1,0 2,0 1,1 1,2"
    [J2]="0,1 1,1 2,1 2,2"  [J3]="1,0 1,1 0,2 1,2"
    [L0]="2,0 0,1 1,1 2,1"  [L1]="1,0 1,1 1,2 2,2"
    [L2]="0,1 1,1 2,1 0,2"  [L3]="0,0 1,0 1,1 1,2"
)

# Configurable colors (since 0.19.0): instead of hard-wiring one palette
# per piece, colors are addressed by symbolic name (cyan, orange, ...)
# and a color scheme ("theme") maps every piece type and the gold/silver
# squares to such a name. This solves the two-palette problem cleanly: a
# raw SGR number only works in one mode, whereas a name carries both a
# basic (8/16-color ANSI) and an extended (xterm 256-color) meaning. The
# renderer (render_colors_init, lib/render.sh) turns the active theme's
# names into the final SGR sequences for the resolved COLOR_MODE.

# Basic color mode: ANSI foreground SGR code per color name. Rendering
# draws pieces as reverse-video blocks of this foreground, and gold/silver
# squares as black text on the matching background (foreground + 10). The
# basic 8-color palette has no true orange/purple/etc.; those names fall
# back to the closest of the eight base colors.
declare -A COLOR_BASIC=(
    [cyan]="36"  [yellow]="33" [magenta]="35" [green]="32" [red]="31"
    [blue]="34"  [white]="37"  [orange]="37"  [gold]="33"  [silver]="37"
    [grey]="37"  [purple]="35" [sky]="36"     [amber]="33"
)

# Extended color mode: xterm 256-color index per color name. Rendering
# paints these as backgrounds (48;5;N) for pieces and squares, so the
# extended palette can express real orange (208), purple (129) and richer
# gold/silver tones the basic palette cannot.
declare -A COLOR_EXT=(
    [cyan]="51"  [yellow]="220" [magenta]="135" [green]="40" [red]="196"
    [blue]="33"  [white]="252"  [orange]="208"  [gold]="178" [silver]="250"
    [grey]="245" [purple]="129" [sky]="39"       [amber]="214"
)

# Available color schemes, in menu order. COLOR_THEME (a validated user
# setting in rowhammer.sh) picks one of these names.
COLOR_THEMES=(guideline classic mono colorblind)
# CHANGE 2026-08-04: the display names of the themes moved into the
# translation layer (lib/i18n.sh), keyed "theme_<name>". The theme
# identifiers below are what the config file and --color-theme use and
# stay English; only what the settings menu prints is translated.

# Theme table: for every theme and slot (the seven piece types plus the
# GOLD, SILVER and GARBAGE looks) the color name to use. Keys are
# "theme:slot"; a flat map keeps it a single associative array (bash has
# no nested arrays). "guideline" reproduces the pre-0.19.0 default look
# exactly. "colorblind" avoids the red/green pair (deuteranopia) and
# leans on the blue-yellow axis plus lightness differences.
# GARBAGE (0.49.0) is the flood row of the "Hochwasser" mode: grey in
# every theme, because it is the one thing on the board that is not a
# piece and should read as dead weight rather than as a color of its own.
# In the mono theme that is the same grey the pieces have; the glyph the
# renderer prints on it (GARBAGE_GLYPH in lib/render.sh) is what keeps
# the two apart there, exactly as it does in the no-color mode.
declare -A THEME_COLOR=(
    [guideline:I]="cyan"  [guideline:O]="yellow" [guideline:T]="magenta"
    [guideline:S]="green" [guideline:Z]="red"    [guideline:J]="blue"
    [guideline:L]="orange" [guideline:GOLD]="gold" [guideline:SILVER]="silver"
    [guideline:GARBAGE]="grey"

    [classic:I]="cyan"  [classic:O]="yellow" [classic:T]="white"
    [classic:S]="green" [classic:Z]="red"    [classic:J]="blue"
    [classic:L]="magenta" [classic:GOLD]="gold" [classic:SILVER]="silver"
    [classic:GARBAGE]="grey"

    [mono:I]="grey"  [mono:O]="grey" [mono:T]="grey"
    [mono:S]="grey"  [mono:Z]="grey" [mono:J]="grey"
    [mono:L]="grey"  [mono:GOLD]="gold" [mono:SILVER]="silver"
    [mono:GARBAGE]="grey"

    [colorblind:I]="sky"  [colorblind:O]="yellow" [colorblind:T]="purple"
    [colorblind:S]="white" [colorblind:Z]="amber" [colorblind:J]="blue"
    [colorblind:L]="orange" [colorblind:GOLD]="gold" [colorblind:SILVER]="silver"
    [colorblind:GARBAGE]="grey"
)

# Two-character fallback glyph per piece type for the no-color mode
# (--no-color / NO_COLOR). Without color every settled block used to look
# the same ("[]"), so pieces became indistinguishable once they locked
# and planning gold (mono) / silver (mixed) squares was impossible. Each
# type now keeps its own marker - the doubled type letter, which makes
# the mapping self-evident. The gold/silver squares use non-letter glyphs
# (SQ_*_GLYPH in lib/render.sh) so a square never collides with a piece.
declare -A PIECE_GLYPH=(
    [I]="II" [O]="OO" [T]="TT" [S]="SS" [Z]="ZZ" [J]="JJ" [L]="LL"
)

# The bag of upcoming pieces (bag randomizer state).
PIECE_TYPES=(I O T S Z J L)
BAG=()

# How many complete sets of the seven types make up one bag. Nine sets,
# so a bag holds 63 pieces (since 1.0.4): the guarantee stays the same -
# over a full bag every type comes up equally often - but within the bag
# the order is far freer than with a single set of seven, where a type
# that has just been drawn can be twelve pieces away at most. That
# freedom is what the square system needs: building a 4x4 square takes
# four pieces that fit each other, and with a bag of seven the sequence
# hands them out too evenly for a square to ever be a lucky find. The
# longer bag brings back both the run of same-type pieces that makes a
# gold square possible and the drought that makes it a decision.
BAG_SETS=9

# --- The generator behind the bag (since 2.1.1) ---------------------------
# The shuffle draws from a generator of its own, written out in shell
# arithmetic, and no longer from bash's RANDOM. The reason is what a seed
# is for: "--seed N" promises a sequence, and a multiplayer round gives
# every participant the hub's SEED so that all of them play the same
# pieces (CLAUDE.md 5.1). RANDOM cannot keep either promise, because the
# generator behind it is not the same in every bash the game runs on
# (>= 4.3, CLAUDE.md 4.1) - measured for issue #115 with one seed on the
# real shells, there are three of them:
#   bash 4.3, 4.4  Park-Miller on an unsigned long, the correction of a
#                  negative intermediate value compiled out ("#if 0" in
#                  brand(), variables.c).
#   bash 5.0       the same step on 32 bits, with that correction.
#   bash 5.1+      the 5.0 step, and the result folded:
#                  (state >> 16) ^ (state & 65535).
# Two machines with different shells in one session therefore played
# different pieces from one SEED, with nothing on screen to say so - and
# a recording of a round carries one sequence for all of its seats, the
# recorder's own (lib/demo.sh).
#
# The generator here is the one of bash 5.1 and later, reproduced exactly
# (intrand32 and brand in lib/sh/random.c, get_random_number in
# variables.c), not a new one: every seed keeps the sequence it had on
# those shells and only the older ones move - to the sequence everybody
# else already had. It also gives the test something to be held against
# that is not this code: RANDOM itself. Its three parts:
#   1. The step, "minimal standard" of Park and Miller with Schrage's
#      split so nothing overflows 32 bits:
#        h = state / 127773;  l = state % 127773
#        t = 16807 * l - 2836 * h;  if t < 0 then t += 2147483647
#        state = t
#      A state of 0 is replaced by 123459876 before the step.
#   2. The value: ((state >> 16) ^ (state & 65535)) & 32767.
#   3. A value equal to the one handed out before is thrown away and the
#      step is taken again; seeding sets that memory to 0.
# Bash evaluates arithmetic in intmax_t, 64 bits wide on the platforms
# the game runs on, so the sums above are exact here without any masking
# (the largest is below 2^31); the mask in bag_seed only repeats what
# bash does to a seed that does not fit 32 bits.
# tools/seed-check.sh holds this to fixed vectors and, on a bash that has
# the original, to RANDOM itself; the CI runs it on bash 4.3 to 5.3.
#
# BAG_RNG is the state, BAG_RNG_LAST the value handed out last and
# BAG_RAND the result of bag_rand - passed in a global like NEXT_TYPE, to
# keep a fork out of the game loop. All three are session state and not
# round state (lib/state.sh), exactly as RANDOM was: one stream runs
# through the session, and a round is the part of it that it draws.
BAG_RNG=1
BAG_RNG_LAST=0
BAG_RAND=0

# bag_seed N
# Start the piece sequence over from seed N. N is decimal digits only -
# every caller has checked that (the option check in rowhammer.sh, the
# number field of the protocol for the hub's SEED). It is read as base 10
# explicitly: plain arithmetic takes a leading zero for octal, so "010"
# would be eight and "08" an arithmetic error, which throws the shell out
# of the whole command it is in the middle of.
bag_seed() {
    BAG_RNG=$(( 10#${1} & 0xFFFFFFFF ))
    BAG_RNG_LAST=0
    return 0
}

# bag_rand
# The next number of the generator, 0..32767, into BAG_RAND.
bag_rand() {
    local h l t
    while :; do
        if [ "${BAG_RNG}" -eq 0 ]; then
            BAG_RNG=123459876
        fi
        h=$(( BAG_RNG / 127773 ))
        l=$(( BAG_RNG % 127773 ))
        t=$(( 16807 * l - 2836 * h ))
        if [ "${t}" -lt 0 ]; then
            t=$(( t + 0x7FFFFFFF ))
        fi
        BAG_RNG="${t}"
        BAG_RAND=$(( ((t >> 16) ^ (t & 65535)) & 32767 ))
        if [ "${BAG_RAND}" -ne "${BAG_RNG_LAST}" ]; then
            break
        fi
    done
    BAG_RNG_LAST="${BAG_RAND}"
    return 0
}

# Refill the bag with BAG_SETS complete sets of the seven piece types and
# shuffle it in place (Fisher-Yates). bag_rand drives the shuffle, so
# seeding it (bag_seed) makes the whole piece sequence reproducible (used
# by --seed and by the SEED of a multiplayer round).
# CHANGE 2.1.1: this drew from RANDOM, and seeding RANDOM was what made
# the sequence reproducible - on one bash version, see above.
bag_refill() {
    local i j tmp
    BAG=()
    for (( i = 0; i < BAG_SETS; i++ )); do
        BAG+=("${PIECE_TYPES[@]}")
    done
    # Shuffled across the whole bag, not set by set: shuffling each set
    # on its own would only reorder seven pieces at a time and keep
    # exactly the even distribution this is meant to loosen up.
    for (( i = ${#BAG[@]} - 1; i > 0; i-- )); do
        bag_rand
        j=$(( BAG_RAND % (i + 1) ))
        tmp="${BAG[i]}"
        BAG[i]="${BAG[j]}"
        BAG[j]="${tmp}"
    done
    debug_event "bag refill (${#BAG[@]} pieces): ${BAG[*]}"
}

# Queue of upcoming pieces drawn from the bag. It always holds at least
# PREVIEW_COUNT + 1 entries so the HUD can show three previews plus the
# piece that spawns next.
QUEUE=()
PREVIEW_COUNT=3

# queue_fill: top the queue up from the bag (refilling the bag as needed).
# This is the one place pieces enter a round, which makes it the place the
# demo layer (lib/demo.sh) hooks into: while a demo is being replayed the
# pieces come from its recorded stream instead of the bag, and while a
# round is being recorded every piece drawn here is noted for that stream.
# Storing the pieces themselves rather than an RNG seed is deliberate -
# the generator is seeded once per session, not per round, so a seed
# would not name the round it was drawn in.
# CHANGE 2.1.1: the second reason given here was that the generator of
# RANDOM differs between bash versions, so a seed would not replay
# reliably. The bag has a generator of its own now (bag_rand above) and
# that one is the same everywhere; the first reason stands, and a stored
# sequence stays independent of BAG_SETS as well (CLAUDE.md 3.1).
queue_fill() {
    # A plain variable instead of indexing the queue back, so the code
    # stays within the bash 4.0 the game asks for (negative array indices
    # need 4.2).
    local piece
    while [ "${#QUEUE[@]}" -lt $(( PREVIEW_COUNT + 1 )) ]; do
        if [ "${DEMO_PLAYING}" -eq 1 ] && demo_next_piece; then
            QUEUE+=("${DEMO_NEXT_PIECE}")
            continue
        fi
        if [ "${#BAG[@]}" -eq 0 ]; then
            bag_refill
        fi
        piece="${BAG[0]}"
        QUEUE+=("${piece}")
        BAG=("${BAG[@]:1}")
        demo_record_piece "${piece}"
    done
}

# bag_next: pop the next piece type into the global NEXT_TYPE and keep the
# preview queue topped up. The result is passed via a global instead of
# command substitution to avoid forking a subshell in the game loop.
bag_next() {
    queue_fill
    NEXT_TYPE="${QUEUE[0]}"
    QUEUE=("${QUEUE[@]:1}")
    queue_fill
}
