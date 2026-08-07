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
#   complete sets of the seven types per bag, shuffled as a whole) and
#   the upcoming-piece queue that feeds the HUD preview. In debug mode
#   every bag refill is logged with the shuffled piece order.
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.10.0  (2026-08-07)

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

# Refill the bag with BAG_SETS complete sets of the seven piece types and
# shuffle it in place (Fisher-Yates). RANDOM drives the shuffle, so
# seeding RANDOM makes the whole piece sequence reproducible (used by
# --seed).
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
        j=$(( RANDOM % (i + 1) ))
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
# RANDOM is seeded once per session, not per round, and its generator
# differs between bash versions, so a seed would not replay reliably.
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
