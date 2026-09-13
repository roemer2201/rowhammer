#!/usr/bin/env bash
#
# lib/screensaver.sh
#
# Description:
#   Full-screen attract mode for rowhammer. Tetromino pieces rain down
#   the whole terminal the way the glyphs do in the "Matrix" screen
#   saver: every lane carries one piece, drawn as a bright block at its
#   head and as a fading trail of the positions it came from, and each
#   piece turns a quarter rotation every few rows on its way down. The
#   pieces fall at a medium pace by default; the up/down arrows and
#   "+"/"-" step the speed the way they do in a demo replay, every other
#   key ends it.
#   Unlike the play screen this is not the fixed 48x22 block (CLAUDE.md
#   3.4): the picture is built cell by cell over the full terminal and
#   follows a resize.
#   Reached with --screensaver (ROWHAMMER_SCREENSAVER=1) and on purpose
#   not mentioned in the menu, the manual or --help - it is a hidden
#   extra to be found, not a documented feature, so a missing help entry
#   is the intent here and not an oversight to be fixed.
#
#   Flow:
#     1. screensaver_run: resolve the speed, start the clocks, build the
#        geometry, then loop.
#     2. Per tick: read a key through the shared input layer (which also
#        applies a pending resize), rebase the frame deadline if the
#        wall clock moved backwards, then update and draw.
#     3. screensaver_update: advance the scaled clock, fade the trail
#        cells one step per fall interval, move and rotate every drop
#        that is due, respawn one that left the screen at the bottom.
#     4. screensaver_draw: rebuild the rows that changed and write them
#        with their cursor positioning in one go.
#
#   Library file: sourced by rowhammer.sh, not meant to be executed
#   directly.
#
# Version: 1.0.1  (2026-09-13)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/screensaver.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# --- Tunables -------------------------------------------------------------
# How many brightness steps a cell goes through before it is gone. Three
# is what the three looks below (head, body, ghost) can tell apart; with
# a piece four rows tall and one fade step per fall interval the visible
# tail ends up roughly seven rows long.
SS_TRAIL_STEPS=3
# Width of one lane in cells: the 4 cells of a piece box plus one blank
# column, so two neighbouring lanes never touch.
SS_LANE_W=5
# Milliseconds a piece takes per row at 1.00x, before the per-drop
# variation below. The "medium" default speed is this value; like
# LEVEL_SPEEDS or FLOOD_INTERVAL_MS it is a feel constant to be adjusted
# after watching it, not a per-call option.
SS_FALL_MS=110
# Per-drop variation of that interval in percent, so the lanes do not
# fall in lockstep: 70% (faster) to 149% (slower) of SS_FALL_MS.
SS_STEP_MIN_PCT=70
SS_STEP_PCT_RANGE=80
# Rows between two quarter rotations, drawn per drop from this range.
SS_ROT_MIN=2
SS_ROT_RANGE=3
# Upper bound of the random pause before a lane sends its next piece.
# Short against the three to six seconds a piece takes to cross the
# screen: a lane that rests for long is a lane that is visibly empty.
SS_RESPAWN_MS=800
# Longest a lane holds its first piece back (see SPREAD in
# screensaver_drop_reset). One crossing of the picture is the natural
# window, but on a very tall terminal that is a lane standing empty for
# the better part of ten seconds, so it is capped.
SS_SPREAD_MAX_MS=5000
# How far above the top edge a piece starts beyond its own box height,
# at most. Every row of it is time the lane stands dark, so it is kept
# short - four rows are enough for the piece to slide in rather than to
# appear. It is also the range the initial fill reaches above the picture
# (see SPREAD in screensaver_drop_reset), so a lane can begin its first
# run just off screen as well as halfway down.
SS_SPAWN_LEAD=4
# Largest clock step one frame may apply. Everything that can stall the
# loop for longer - a resize, the too-small overlay, a machine under load
# - would otherwise arrive as one huge jump and rain a screenful of
# pieces at once; past this the picture simply carries on from where it
# was. It has to stay well above a frame interval at the slowest frame
# rate that is still meant to move properly.
SS_DELTA_MAX_MS=500
# Rows a single drop may advance within one update, as a backstop behind
# the clamp above: with the slowest fall interval a clamped step is about
# six rows, so this never cuts into normal motion.
SS_STEP_MAX=8
# Minimum real time between two drawn frames, derived in screensaver_run
# from SCREENSAVER_FPS (--screensaver-fps, default 15). The picture
# covers the whole terminal, so unlike the game block its cost grows with
# the terminal size, which is why the rate is capped at all. The variable
# belongs to rowhammer.sh and is only read here - the modules are sourced
# after the arguments are parsed, so a default of its own would overwrite
# what the command line just set (same as RENDER_MODE, CLAUDE.md 4.3).
SS_FRAME_MS=66

# Playback speeds in percent of real time and their labels, indexed
# together - the same five steps a demo replay offers (lib/demo.sh), so
# the two places that let the player scale time behave alike. Index 2 is
# 1.00x: the medium pace this starts at.
SS_SPEEDS=(25 50 100 200 400)
SS_SPEED_DEFAULT=2
SS_SPEED_IDX="${SS_SPEED_DEFAULT}"
SS_SPEED=100

# --- State ----------------------------------------------------------------
# Geometry in cells: a cell is two terminal columns wide (like a board
# cell) and one row high.
SS_COLS=0
SS_ROWS=0
SS_LANES=0

# The scaled clock everything is timed against, its real-time anchor and
# the next due fade pass. Scaling the clock rather than every interval is
# what makes a speed change take effect immediately (same approach as
# DEMO_CLOCK_MS).
SS_CLOCK_MS=0
SS_REAL_MS=0
SS_FADE_NEXT=0

# One drop per lane, all indexed by lane number.
declare -a SS_TYPE=()      # piece type of the falling piece
declare -a SS_ROT=()       # its rotation state, 0..3
declare -a SS_X=()         # left cell column of its 4x4 box
declare -a SS_Y=()         # top cell row of its 4x4 box, negative above
declare -a SS_STEP=()      # milliseconds per row
declare -a SS_NEXT=()      # clock time of its next row
declare -a SS_ROTN=()      # rows left until the next rotation
declare -a SS_ROTEVERY=()  # rows between two rotations

# The picture itself: piece type and remaining brightness per cell,
# keyed "x,y", plus the cells a frame has to rewrite. All three are
# sparse on purpose - only the cells a piece has touched exist, which
# keeps both the fade pass and the frame proportional to what moved
# rather than to the terminal size.
# CHANGE 2026-09-12: SS_DIRTY collects cells, not rows. Rebuilding whole
# rows cost SS_COLS lookups per row and about 30 ms per frame on a 100
# column terminal, which held the frame rate at roughly 20 no matter what
# was asked for. Between two fade passes a frame usually changes only the
# handful of cells the drops have just moved into, and each cell carries
# its own cursor positioning anyway.
declare -A SS_CELL=()
declare -A SS_LVL=()
declare -A SS_DIRTY=()

# The three looks of a cell, per piece type: the head is the solid block
# the board uses, the body a colored outline, the ghost a dim remnant.
# Without color the head keeps the type glyph (PIECE_GLYPH), so the rain
# stays readable as pieces there too.
declare -A SS_HEAD=()
declare -A SS_BODY=()
declare -A SS_GHOST=()

# screensaver_colors_init
# Build the three looks above from the active theme and color mode. Runs
# once at the start; the settings menu cannot be reached from here, so
# the palette cannot change underneath it.
screensaver_colors_init() {
    local t name fg dim
    for t in "${PIECE_TYPES[@]}"; do
        if [ "${USE_COLOR}" -eq 0 ]; then
            SS_HEAD["${t}"]="${PIECE_GLYPH[${t}]}"
            SS_BODY["${t}"]="[]"
            SS_GHOST["${t}"]=".."
            continue
        fi
        name="${THEME_COLOR[${COLOR_THEME}:${t}]}"
        if [ "${COLOR_MODE}" = "extended" ]; then
            fg=$'\e[38;5;'"${COLOR_EXT[${name}]}m"
            dim=$'\e[2;38;5;'"${COLOR_EXT[${name}]}m"
        else
            fg=$'\e['"${COLOR_BASIC[${name}]}m"
            dim=$'\e[2;'"${COLOR_BASIC[${name}]}m"
        fi
        SS_HEAD["${t}"]="${PIECE_SGR[${t}]}  ${RESET_SGR}"
        SS_BODY["${t}"]="${fg}[]${RESET_SGR}"
        SS_GHOST["${t}"]="${dim}..${RESET_SGR}"
    done
    return 0
}

# screensaver_drop_reset IDX [SPREAD]
# Send a fresh piece down lane IDX: new type, rotation, fall interval and
# rotation rate, starting above the top edge after a short random pause.
# Used for a drop that has left the screen at the bottom, and with
# SPREAD=1 for the initial fill.
# CHANGE 2026-09-12: SPREAD exists because without it the rain arrived in
# waves. Every lane started within the same couple of seconds, so the
# first pieces crossed the screen as one front and the lanes stayed in
# step behind it - a lane is only ever free of its predecessor once that
# one has reached the bottom. SPREAD=1 gives the lane a random phase of
# its own cycle by holding its first piece back for anything up to the
# time a piece needs to cross the whole picture; the per-drop fall
# interval below (70% to 149% of SS_FALL_MS, redrawn on every respawn)
# then keeps the phases apart from there on.
# The phase is deliberately spent waiting above the edge rather than
# dropped in at a random height: it starts on an empty screen with the
# pieces coming in from the top, which is how it is meant to begin. The
# picture is at its normal density after about one crossing.
screensaver_drop_reset() {
    local idx="${1}" spread="${2:-0}"
    local lane_x=$(( idx * SS_LANE_W ))
    local jitter=$(( SS_LANE_W - 4 ))
    local x
    if [ "${jitter}" -gt 0 ]; then
        x=$(( lane_x + RANDOM % (jitter + 1) ))
    else
        x="${lane_x}"
    fi
    # A piece box is four cells wide; keep it inside the picture even
    # when the last lane sits at the right edge.
    if [ $(( x + 4 )) -gt "${SS_COLS}" ]; then
        x=$(( SS_COLS - 4 ))
    fi
    if [ "${x}" -lt 0 ]; then
        x=0
    fi
    SS_TYPE[idx]="${PIECE_TYPES[RANDOM % ${#PIECE_TYPES[@]}]}"
    SS_ROT[idx]=$(( RANDOM % 4 ))
    SS_X[idx]="${x}"
    SS_STEP[idx]=$(( SS_FALL_MS * (SS_STEP_MIN_PCT + RANDOM % SS_STEP_PCT_RANGE) / 100 ))
    SS_ROTEVERY[idx]=$(( SS_ROT_MIN + RANDOM % SS_ROT_RANGE ))
    SS_ROTN[idx]="${SS_ROTEVERY[idx]}"
    # Above the top edge in both cases, so the piece slides in instead of
    # appearing. What differs is the wait: a moment for the next piece of
    # a running lane, a random share of a whole crossing for the first
    # one (see SPREAD above).
    SS_Y[idx]=$(( -4 - RANDOM % SS_SPAWN_LEAD ))
    if [ "${spread}" -eq 1 ]; then
        local window=$(( SS_ROWS * SS_FALL_MS ))
        if [ "${window}" -gt "${SS_SPREAD_MAX_MS}" ]; then
            window="${SS_SPREAD_MAX_MS}"
        fi
        SS_NEXT[idx]=$(( SS_CLOCK_MS + RANDOM % window ))
    else
        SS_NEXT[idx]=$(( SS_CLOCK_MS + RANDOM % SS_RESPAWN_MS ))
    fi
    return 0
}

# screensaver_geometry
# Measure the terminal in cells, lay out the lanes and start over with an
# empty picture. Called at the start and after every resize, where the
# old coordinates are worthless and the screen has been cleared anyway.
screensaver_geometry() {
    local i
    SS_COLS=$(( TERM_COLS / 2 ))
    SS_ROWS="${TERM_ROWS}"
    SS_LANES=$(( SS_COLS / SS_LANE_W ))
    if [ "${SS_LANES}" -lt 1 ]; then
        SS_LANES=1
    fi
    SS_CELL=()
    SS_LVL=()
    SS_DIRTY=()
    SS_TYPE=(); SS_ROT=(); SS_X=(); SS_Y=()
    SS_STEP=(); SS_NEXT=(); SS_ROTN=(); SS_ROTEVERY=()
    for (( i = 0; i < SS_LANES; i++ )); do
        screensaver_drop_reset "${i}" 1
    done
    screen_write $'\e[2J\e[H'
    # The screen belongs to this picture now; whatever draws next has to
    # start from a cleared terminal (see MENU_FULL/RENDER_FULL in
    # lib/render.sh).
    MENU_FULL=1
    RENDER_FULL=1
    debug_event "screensaver: ${SS_COLS}x${SS_ROWS} cells, ${SS_LANES} lanes"
    return 0
}

# screensaver_speed_apply
# Take the interval scale and its label from the current SS_SPEED_IDX.
screensaver_speed_apply() {
    SS_SPEED="${SS_SPEEDS[SS_SPEED_IDX]}"
    return 0
}

# screensaver_stamp IDX
# Draw the piece of lane IDX into the picture at full brightness. The
# cells it covered before are not erased - they are left to fade, which
# is what forms the trail.
# Called on every frame, not only when the piece moved: a drop's fall
# interval can be longer than the fade interval, and such a piece got
# dimmed where it stands and lost the bright head that says where it
# currently is. Writing a cell that already holds this value would be
# output for nothing, so a cell is only marked for redraw when it really
# changes - which is what makes calling this per frame cheap.
screensaver_stamp() {
    local idx="${1}"
    local type="${SS_TYPE[idx]}"
    local cell cx cy gx gy key
    # Deliberately unquoted: the shape is a space separated list of
    # "x,y" offsets and word splitting is how it is read (same as in
    # lib/squares.sh).
    # shellcheck disable=SC2086
    for cell in ${PIECE_SHAPE["${type}${SS_ROT[idx]}"]}; do
        cx="${cell%,*}"
        cy="${cell#*,}"
        gx=$(( SS_X[idx] + cx ))
        gy=$(( SS_Y[idx] + cy ))
        if [ "${gy}" -lt 0 ] || [ "${gy}" -ge "${SS_ROWS}" ]; then
            continue
        fi
        if [ "${gx}" -lt 0 ] || [ "${gx}" -ge "${SS_COLS}" ]; then
            continue
        fi
        key="${gx},${gy}"
        if [ "${SS_LVL[${key}]:-0}" -ne "${SS_TRAIL_STEPS}" ] \
            || [ "${SS_CELL[${key}]:-}" != "${type}" ]; then
            SS_DIRTY["${key}"]=1
        fi
        SS_CELL["${key}"]="${type}"
        SS_LVL["${key}"]="${SS_TRAIL_STEPS}"
    done
    return 0
}

# screensaver_fade
# Take one brightness step off every cell of the picture and drop the
# ones that reached the bottom. Every touched row is marked for redraw.
screensaver_fade() {
    local key lvl
    for key in "${!SS_LVL[@]}"; do
        lvl=$(( SS_LVL["${key}"] - 1 ))
        SS_DIRTY["${key}"]=1
        if [ "${lvl}" -le 0 ]; then
            unset "SS_CELL[${key}]"
            unset "SS_LVL[${key}]"
        else
            SS_LVL["${key}"]="${lvl}"
        fi
    done
    return 0
}

# screensaver_update
# Advance the scaled clock, run the fade passes that came due and move
# every drop that is due, rotating it every few rows.
screensaver_update() {
    local delta i steps guard
    now_ms
    delta=$(( NOW_MS - SS_REAL_MS ))
    SS_REAL_MS="${NOW_MS}"
    if [ "${delta}" -lt 0 ]; then
        # A clock that jumped backwards costs one frame, not the run.
        delta=0
    elif [ "${delta}" -gt "${SS_DELTA_MAX_MS}" ]; then
        delta="${SS_DELTA_MAX_MS}"
    fi
    SS_CLOCK_MS=$(( SS_CLOCK_MS + delta * SS_SPEED / 100 ))

    # Fade passes. More than SS_TRAIL_STEPS of them in one frame would
    # only clear the picture over and over, so a frame that fell that
    # far behind (4.00x on a busy machine) resynchronizes instead.
    guard=0
    while [ "${SS_CLOCK_MS}" -ge "${SS_FADE_NEXT}" ]; do
        screensaver_fade
        SS_FADE_NEXT=$(( SS_FADE_NEXT + SS_FALL_MS ))
        guard=$(( guard + 1 ))
        if [ "${guard}" -ge "${SS_TRAIL_STEPS}" ]; then
            SS_FADE_NEXT=$(( SS_CLOCK_MS + SS_FALL_MS ))
            break
        fi
    done

    for (( i = 0; i < SS_LANES; i++ )); do
        steps=0
        while [ "${SS_CLOCK_MS}" -ge "${SS_NEXT[i]}" ]; do
            SS_Y[i]=$(( SS_Y[i] + 1 ))
            SS_NEXT[i]=$(( SS_NEXT[i] + SS_STEP[i] ))
            SS_ROTN[i]=$(( SS_ROTN[i] - 1 ))
            if [ "${SS_ROTN[i]}" -le 0 ]; then
                SS_ROT[i]=$(( (SS_ROT[i] + 1) % 4 ))
                SS_ROTN[i]="${SS_ROTEVERY[i]}"
            fi
            # Gone past the bottom edge: the lane rests a moment and
            # then sends the next piece.
            if [ "${SS_Y[i]}" -ge "${SS_ROWS}" ]; then
                screensaver_drop_reset "${i}"
                break
            fi
            steps=$(( steps + 1 ))
            if [ "${steps}" -ge "${SS_STEP_MAX}" ]; then
                SS_NEXT[i]=$(( SS_CLOCK_MS + SS_STEP[i] ))
                break
            fi
        done
        # Where the piece stands now, at full brightness - whether it
        # moved this frame or not (see screensaver_stamp).
        screensaver_stamp "${i}"
    done
    return 0
}

# screensaver_draw
# Write every cell that changed since the last frame, each with its own
# cursor positioning and all of them in a single call - the same idea as
# render_flush (4.3), only over the full terminal and per cell rather
# than per line, because this picture is sparse where the game block is
# dense. A cell that has faded away is written back as blank; there is no
# other way for it to disappear, since nothing else ever covers it.
screensaver_draw() {
    local out="" key x y type lvl cell
    for key in "${!SS_DIRTY[@]}"; do
        x="${key%,*}"
        y="${key#*,}"
        type="${SS_CELL[${key}]:-}"
        if [ -z "${type}" ]; then
            cell="  "
        else
            lvl="${SS_LVL[${key}]}"
            if [ "${lvl}" -ge "${SS_TRAIL_STEPS}" ]; then
                cell="${SS_HEAD[${type}]}"
            elif [ "${lvl}" -ge 2 ]; then
                cell="${SS_BODY[${type}]}"
            else
                cell="${SS_GHOST[${type}]}"
            fi
        fi
        out+=$'\e['"$(( y + 1 ));$(( x * 2 + 1 ))"'H'"${cell}"
    done
    SS_DIRTY=()
    if [ -n "${out}" ]; then
        screen_write "${out}"
    fi
    return 0
}

# screensaver_run
# The loop. read_key paces it at TICK_S and is where a pending resize is
# applied (remeasure, clear, and block on the too-small overlay while the
# terminal is undersized), exactly as in the game loop; REDRAW_PENDING
# then says that the picture has to be laid out again. The up/down arrows
# and "+"/"-" step the speed, every other key ends the screensaver - it
# is a screensaver, and "any key" is how one is expected to stop.
screensaver_run() {
    local next_draw last_wall tick_saved tick_ms
    debug_event "screensaver: start (speed ${SS_SPEEDS[SS_SPEED_IDX]}%, ${SCREENSAVER_FPS} fps)"
    SS_SPEED_IDX="${SS_SPEED_DEFAULT}"
    screensaver_speed_apply
    # Validated in rowhammer.sh (1..120), so the division is safe here.
    SS_FRAME_MS=$(( 1000 / SCREENSAVER_FPS ))
    # read_key's timeout is what paces this loop, and at the game's 20 ms
    # it alone eats most of the budget of a fast frame rate - a requested
    # 30 fps came out as 20. A third of the frame interval leaves room
    # for the work of the frame itself and still notices a key press
    # within a frame; below 5 ms the reads would cost more than they
    # save. TICK_S is restored before returning, because it belongs to
    # the input layer and the game loop uses it too.
    tick_saved="${TICK_S}"
    tick_ms=$(( SS_FRAME_MS / 3 ))
    if [ "${tick_ms}" -lt 5 ]; then
        tick_ms=5
    elif [ "${tick_ms}" -gt 20 ]; then
        tick_ms=20
    fi
    printf -v TICK_S '%d.%03d' $(( tick_ms / 1000 )) $(( tick_ms % 1000 ))
    screensaver_colors_init
    now_ms
    SS_REAL_MS="${NOW_MS}"
    SS_CLOCK_MS=0
    SS_FADE_NEXT="${SS_FALL_MS}"
    screensaver_geometry
    now_ms
    next_draw="${NOW_MS}"
    last_wall="${NOW_MS}"
    while :; do
        read_key
        if [ "${REDRAW_PENDING}" -eq 1 ]; then
            REDRAW_PENDING=0
            screensaver_geometry
        fi
        case "${KEY}" in
            "")
                : ;;
            UP|+)
                if [ "${SS_SPEED_IDX}" -lt $(( ${#SS_SPEEDS[@]} - 1 )) ]; then
                    SS_SPEED_IDX=$(( SS_SPEED_IDX + 1 ))
                    screensaver_speed_apply
                fi
                ;;
            DOWN|-)
                if [ "${SS_SPEED_IDX}" -gt 0 ]; then
                    SS_SPEED_IDX=$(( SS_SPEED_IDX - 1 ))
                    screensaver_speed_apply
                fi
                ;;
            *)
                break
                ;;
        esac
        # Simulation and picture advance together, once per frame: the
        # state is derived from the clock, so updating it more often than
        # it is shown only costs time. Everything that could arrive as
        # one large step is capped (SS_DELTA_MAX_MS).
        now_ms
        # CHANGE 2026-09-13: detect a backward wall-clock jump before
        # testing the deadline. The negative-delta guard in update cannot
        # help while an old deadline keeps that function from running.
        # Compare every tick, including ticks between drawn frames, and
        # rebase both real-time anchors without changing simulation time.
        if [ "${NOW_MS}" -lt "${last_wall}" ]; then
            next_draw="${NOW_MS}"
            SS_REAL_MS="${NOW_MS}"
        fi
        last_wall="${NOW_MS}"
        if [ "${NOW_MS}" -ge "${next_draw}" ]; then
            screensaver_update
            screensaver_draw
            # Counted on from the due time, not from now: the loop wakes
            # on the grid of its key read, so a deadline is usually met a
            # few milliseconds late and adding the interval to "now"
            # would give away those milliseconds on every single frame.
            # Only a frame that took longer than the interval itself
            # resynchronizes, which is what keeps a slow terminal from
            # building up a backlog it can never work off.
            next_draw=$(( next_draw + SS_FRAME_MS ))
            if [ "${next_draw}" -le "${NOW_MS}" ]; then
                next_draw=$(( NOW_MS + SS_FRAME_MS ))
            fi
        fi
    done
    TICK_S="${tick_saved}"
    debug_event "screensaver: end"
    return 0
}
