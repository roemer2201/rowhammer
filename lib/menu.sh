#!/usr/bin/env bash
#
# lib/menu.sh
#
# Description:
#   Menu system for rowhammer: a generic list-selection widget plus the
#   application menus (main menu, singleplayer with its game modes,
#   multiplayer placeholder,
#   settings with key bindings, interface language, color theme, player
#   name and demo recording, and the demo list). Since 0.22.0 no label
#   is written into this file any more: every text comes from the
#   translation table (lib/i18n.sh), which is also what menu_language
#   switches at runtime. Code and comments stay English per the script
#   conventions. All screen output goes through
#   screen_write (lib/render.sh) and selections, rebinds and name
#   changes are logged as debug events, so debug sessions capture the
#   menus 1:1 as well. Leaving a game session shows the wonder
#   construction site (lib/wonders.sh) with the round's credit banked.
#   The pause menu (menu_pause, issue #12) opens on the quit key during
#   a round and offers to resume, to restart the round (since 0.18.0,
#   user request), to suspend the round into the main
#   menu (resumable via the "Fortsetzen" entry shown in the main menu
#   and in the singleplayer menu) or to end the round. menu_confirm
#   (since 0.8.0) asks a yes/no question with the declining option
#   preselected; it guards leaving the game while a round is still
#   suspended and, since 0.18.0, the two pause menu entries that
#   discard the running round.
#   menu_pages (since 0.10.0) shows a table that outgrew one
#   screen as a sequence of info screens with a repeated table head, which
#   is what the two-line highscore entries need. menu_help (since
#   0.12.0, user request) is the "Anleitung" main menu entry: eight info
#   screens explaining the game, the controls, hold and preview, the
#   gold/silver squares, the wonder construction, the game modes, how
#   their highscore lists are kept and (since 0.20.0) the demos,
#   with the key bindings, the wonder costs, the mode goals and the
#   playback keys read from
#   the live state instead of spelled out. Since 0.13.0 (user request)
#   its pages are browsed with
#   the left/right arrow keys instead of "any key advances" - built from
#   one case switch (menu_help_body) indexed by page instead of a fixed
#   sequence of menu_message calls, so any page can be jumped to
#   directly in either direction. All wait loops
#   repaint on REDRAW_PENDING so a terminal resize (handled in read_key)
#   does not leave a menu or info screen blank (since 0.7.0).
#   Since 0.14.0 (user request) menu_singleplayer offers the game modes:
#   the endless "Marathon" (renamed from "Normales Spiel" in 0.14.1, user
#   decision), "Ultra", the race for ULTRA_TARGET_ROWS rows against the
#   clock, since 0.16.0 (user request) "Sprint", as many rows as
#   possible within SPRINT_TIME_MS, and since 0.17.0 (user request)
#   "Time Attack", a countdown starting at TIME_ATTACK_START_MS that
#   every row of credit extends by TIME_ATTACK_ROW_MS. The entry picked
#   is handed to
#   game_run as its mode name.
#   Since 0.15.0 (user request) menu_highscores picks the mode of the
#   list to show as well: the modes rank by different numbers and
#   live in separate files (lib/highscore.sh), so the "Highscores" entry
#   asks which one before drawing it. The Anleitung explains all four
#   on a "Spielmodi" page of its own (menu_help_body, since 0.16.0),
#   with their highscore rules on the page after it (since 0.17.0).
#   Since 0.19.0 (user request) the two places that ask for a name share
#   one editor, menu_text_input: the settings entry and the new prompt at
#   the end of a round (prompt_round_name), which asks which name the
#   finished round enters its highscore list under. Both start with the
#   name from the settings preselected the way a graphical text field
#   would be - the first character typed replaces it, Enter keeps it -
#   which is why the editor draws and reads the line itself instead of
#   handing the terminal back into line mode as the old prompt did.
#   Since 0.20.0 menu_demos is the "Demos" main menu entry: the recorded
#   rounds (lib/demo.sh) newest first, each of them to watch again or to
#   delete, the ones still backing a highscore entry marked with a "*".
#   It refuses to start a replay while a round is suspended in
#   the main menu, because a replay runs through the same game state.
#   That list is also the first menu that can outgrow the screen, so
#   menu_run scrolls its window with the selection since 0.20.0
#   (MENU_LIST_MAX).
#   Since 0.21.0 (user request) menu_stats does the same for the
#   "Statistik" entry: the all-time counters as before, or one game
#   mode's own counters (lib/stats.sh keeps both, the totals are not
#   summed from the modes).
#   Since 0.11.0 every screen here is built as an array of plain content
#   lines and handed to render_menu_frame (lib/render.sh), which draws it
#   centered like the play screen instead of into the top left corner;
#   the repaint after a resize rebuilds the frame, because its cursor
#   positions belong to the terminal size they were computed for.
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.23.0  (2026-08-04)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/menu.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# The display label of a key binding comes from the translation table
# (lib/i18n.sh), keyed by the binding variable itself: "keylabel_KEY_HOLD"
# for KEY_HOLD. That keeps the settings list table-driven off the single
# KEY_ACTIONS list in lib/config.sh, the way the fixed KEY_LABELS array
# next to it did before 0.22.0 - only without a second array that has to
# be kept in the same order, and without a German label baked into the
# code.

MENU_CHOICE=-1

# How many entries a selection list shows at once. A menu spends four
# terminal rows on its frame (title, blank, blank, footer), so this is
# what the smallest supported terminal leaves for the entries themselves.
# A longer list scrolls with the selection instead of running off the
# screen (see menu_run); the two outermost rows then carry the "there is
# more above / below" markers, which is why the window is two smaller.
# Added 0.20.0 with the demo list, which is the first menu that can
# outgrow the screen: recordings backing a highscore entry are kept
# beyond DEMO_MAX (lib/demo.sh), so its length is not bounded by a
# constant any more.
MENU_LIST_MAX=$(( MIN_TERM_ROWS - 4 ))
MENU_LIST_WINDOW=$(( MENU_LIST_MAX - 2 ))

# menu_run TITLE ENTRY...
# Draw a selection list and navigate it with the arrow keys (plus w/s).
# Enter or space selects, ESC (or x) goes back. The chosen entry index
# lands in MENU_CHOICE, -1 means "back". Redraws only after a key press;
# read_key's timeout paces the loop, so the menu does not busy-wait.
# CHANGE 2026-07-28: the screen is no longer written as one homed block of
# lines but handed to render_menu_frame (lib/render.sh), which places it
# centered like the game block - the play screen has been centered since
# 0.22.0 and the menus looked disconnected in the top left corner. Every
# screen in this file is built the same way now, as an array of plain
# content lines; positioning, erasing and the leading screen clear all
# live in the renderer. That also replaced the explicit \e[H\e[K of
# 2026-07-26 (homing and moving down with \n left the first screen line
# untouched, showing the top line of whatever was drawn before): the
# renderer erases every line it writes and clears the whole screen
# whenever a non-menu screen was there before.
menu_run() {
    local title="${1}"
    shift
    local -a entries=("$@")
    local -a lines
    local n="${#entries[@]}" sel=0 dirty=1 i first last marker
    while :; do
        if [ "${dirty}" -eq 1 ]; then
            lines=("  ${title}" "")
            # Which slice of the list is on screen. Everything fits in
            # the common case; a longer list shows a window that follows
            # the selection, with the marker rows always present so the
            # menu does not change height while scrolling.
            first=0
            last=$(( n - 1 ))
            if [ "${n}" -gt "${MENU_LIST_MAX}" ]; then
                first=$(( sel - MENU_LIST_WINDOW / 2 ))
                if [ "${first}" -lt 0 ]; then
                    first=0
                fi
                if [ "${first}" -gt $(( n - MENU_LIST_WINDOW )) ]; then
                    first=$(( n - MENU_LIST_WINDOW ))
                fi
                last=$(( first + MENU_LIST_WINDOW - 1 ))
                if [ "${first}" -gt 0 ]; then
                    printf -v marker "${I18N[menu_more_up]}" "${first}"
                    lines+=("${marker}")
                else
                    lines+=("")
                fi
            fi
            for (( i = first; i <= last; i++ )); do
                if (( i == sel )); then
                    lines+=($'  \e[7m '"${entries[i]}"$' \e[0m')
                else
                    lines+=("   ${entries[i]} ")
                fi
            done
            if [ "${n}" -gt "${MENU_LIST_MAX}" ]; then
                if [ "${last}" -lt $(( n - 1 )) ]; then
                    printf -v marker "${I18N[menu_more_down]}" \
                        "$(( n - 1 - last ))"
                    lines+=("${marker}")
                else
                    lines+=("")
                fi
            fi
            lines+=("" "  ${I18N[menu_nav]}")
            render_menu_frame "${lines[@]}"
            screen_write "${RENDER_MENU_FRAME}"
            dirty=0
        fi
        read_key
        # A terminal resize handled inside read_key clears the screen and
        # raises REDRAW_PENDING; repaint the menu so it does not vanish.
        if [ "${REDRAW_PENDING}" -eq 1 ]; then
            REDRAW_PENDING=0
            dirty=1
        fi
        case "${KEY}" in
            UP|w)        sel=$(( (sel + n - 1) % n )); dirty=1 ;;
            DOWN|s)      sel=$(( (sel + 1) % n )); dirty=1 ;;
            ENTER|SPACE)
                MENU_CHOICE="${sel}"
                debug_event "menu '${title}': selected '${entries[sel]}'"
                return 0
                ;;
            ESC|x)
                MENU_CHOICE=-1
                debug_event "menu '${title}': back"
                return 0
                ;;
        esac
    done
}

# menu_message TITLE LINE...
# Show an informational screen and wait for any key.
menu_message() {
    local title="${1}"
    shift
    local -a lines
    local line
    lines=("  ${title}" "")
    for line in "$@"; do
        lines+=("  ${line}")
    done
    lines+=("" "  ${I18N[menu_any_key]}")
    render_menu_frame "${lines[@]}"
    screen_write "${RENDER_MENU_FRAME}"
    KEY=""
    while [ -z "${KEY}" ]; do
        read_key
        # Repaint after a resize (read_key cleared the screen). The frame
        # is rebuilt rather than re-emitted: it carries absolute cursor
        # positions computed for the old terminal size.
        if [ "${REDRAW_PENDING}" -eq 1 ]; then
            REDRAW_PENDING=0
            render_menu_frame "${lines[@]}"
            screen_write "${RENDER_MENU_FRAME}"
        fi
    done
}

# Body lines an info screen may use. menu_message spends four terminal
# rows on its frame (title, blank, blank, footer), and the smallest
# supported terminal is MIN_TERM_ROWS high (rowhammer.sh), so anything
# beyond this would not fit on such a terminal (the frame is centered, so
# it would be cut off at both ends rather than scroll off the bottom).
# A fixed budget on purpose: paging computed from the live TERM_ROWS
# would renumber the pages under the player's hands on every resize.
MENU_BODY_MAX=$(( MIN_TERM_ROWS - 4 ))

# menu_pages TITLE HEAD PAGE LINE...
# Show a table too tall for one screen as a sequence of info screens.
# The first HEAD lines are the table head and are repeated on every page,
# the remaining lines are dealt out PAGE at a time; the title carries a
# "Seite p/n" marker as soon as there is more than one page. Each page
# waits for a key like menu_message does. Callers pick PAGE as a whole
# multiple of their entry height, so an entry is never torn apart, and
# keep HEAD + PAGE within MENU_BODY_MAX.
# Added 0.27.0: the highscore list grew a second line per entry (pieces
# and PCS/min) and no longer fits a single 22-row screen.
menu_pages() {
    local title="${1}" head="${2}" page="${3}"
    shift 3
    local -a lines=("$@")
    local -a body=()
    local total rest pages p from i paged
    total="${#lines[@]}"
    rest=$(( total - head ))
    if [ "${rest}" -lt 0 ]; then
        rest=0
    fi
    # Ceiling division; a head-only call still shows one page.
    pages=$(( (rest + page - 1) / page ))
    if [ "${pages}" -lt 1 ]; then
        pages=1
    fi
    for (( p = 0; p < pages; p++ )); do
        body=()
        for (( i = 0; i < head; i++ )); do
            body+=("${lines[i]}")
        done
        from=$(( head + p * page ))
        for (( i = from; i < from + page && i < total; i++ )); do
            body+=("${lines[i]}")
        done
        if [ "${pages}" -gt 1 ]; then
            printf -v paged "${I18N[menu_page]}" "${title}" \
                "$(( p + 1 ))" "${pages}"
            menu_message "${paged}" "${body[@]}"
        else
            menu_message "${title}" "${body[@]}"
        fi
    done
    return 0
}

# Number of screens menu_help walks through; used both to number the
# titles ("Anleitung (2/9)") and to wrap the left/right paging
# (menu_help below), so the pages stay self-describing.
MENU_HELP_PAGES=9

# menu_help_keys FIXED VAR
# Build the key list for one action as the help screen shows it:
# FIXED is the wording for the keys wired in unconditionally (arrows,
# space, the fixed secondary hold key), VAR the name of the configurable
# binding variable. The bound key leads the list as "[k]" - it is the
# primary key, the one the settings menu rebinds - and is left out when
# it is NONE (the action has no letter key, see rowhammer.sh) or already
# part of FIXED: KEY_HARD defaults to SPACE, which the fixed part
# already names, and a rebind could put the hold action on the fixed w.
# Result in MENU_HELP_KEYS, so the caller needs no subshell.
menu_help_keys() {
    # The binding name goes through a variable of its own: "${!2}" is not
    # an indirect expansion of the second argument, it looks for a
    # variable named after the positional parameter.
    local fixed="${1}" var="${2}" key
    key="${!var}"
    case "${key}" in
        NONE)  key="" ;;
        SPACE) key="${I18N[key_space]}" ;;
        *)     key="[${key}]" ;;
    esac
    if [ -z "${key}" ]; then
        MENU_HELP_KEYS="${fixed}"
        return 0
    fi
    if [ -z "${fixed}" ]; then
        MENU_HELP_KEYS="${key}"
        return 0
    fi
    # Quoted on purpose: an unquoted "[c]" would be read as a glob
    # character class and never match.
    case "${fixed}" in
        *"${key}"*) MENU_HELP_KEYS="${fixed}" ;;
        *)          MENU_HELP_KEYS="${key}, ${fixed}" ;;
    esac
    return 0
}

# menu_help_body PAGE
# Fill the global array HELP_BODY (an array cannot be a function's return
# value, hence the global - the same convention FRAME_LINES/RENDER_MINI
# etc. use) with the content lines of one Anleitung page (0-based, see
# MENU_HELP_PAGES). Kept as one case switch per page instead of one
# function per page so menu_help can jump to any page directly (needed
# for the left/right paging added in 0.13.0; the previous version only
# ever moved forward, one menu_message call per page).
menu_help_body() {
    local page="${1}"
    local line i
    HELP_BODY=()
    case "${page}" in
        0)
            i18n_lines help_p0
            HELP_BODY=("${I18N_LINES[@]}")
            ;;
        1)
            i18n_lines help_p1_head
            HELP_BODY=("${I18N_LINES[@]}")
            # One line per action: its name, then the keys that trigger
            # it - the configurable one first, the ones wired in behind
            # it (menu_help_keys). Both halves come from the language
            # table; the loop is what keeps the two in the same order.
            menu_help_keys "${I18N[key_arrow_left]}" KEY_LEFT
            printf -v line '%-17s %s' "${I18N[help_key_left]}" "${MENU_HELP_KEYS}"
            HELP_BODY+=("${line}")
            menu_help_keys "${I18N[key_arrow_right]}" KEY_RIGHT
            printf -v line '%-17s %s' "${I18N[help_key_right]}" "${MENU_HELP_KEYS}"
            HELP_BODY+=("${line}")
            menu_help_keys "" KEY_ROT_CW
            printf -v line '%-17s %s' "${I18N[help_key_rot_cw]}" "${MENU_HELP_KEYS}"
            HELP_BODY+=("${line}")
            menu_help_keys "" KEY_ROT_CCW
            printf -v line '%-17s %s' "${I18N[help_key_rot_ccw]}" "${MENU_HELP_KEYS}"
            HELP_BODY+=("${line}")
            menu_help_keys "${I18N[key_arrow_down]}" KEY_SOFT
            printf -v line '%-17s %s' "${I18N[help_key_soft]}" "${MENU_HELP_KEYS}"
            HELP_BODY+=("${line}")
            # Space and arrow up always drop hard, w always holds - the
            # game wires both in regardless of the bindings (handle_key).
            menu_help_keys "${I18N[key_space_up]}" KEY_HARD
            printf -v line '%-17s %s' "${I18N[help_key_hard]}" "${MENU_HELP_KEYS}"
            HELP_BODY+=("${line}")
            menu_help_keys "[w]" KEY_HOLD
            printf -v line '%-17s %s' "${I18N[help_key_hold]}" "${MENU_HELP_KEYS}"
            HELP_BODY+=("${line}")
            menu_help_keys "" KEY_PAUSE
            printf -v line '%-17s %s' "${I18N[help_key_pause]}" "${MENU_HELP_KEYS}"
            HELP_BODY+=("${line}")
            menu_help_keys "ESC" KEY_QUIT
            printf -v line '%-17s %s' "${I18N[help_key_quit]}" "${MENU_HELP_KEYS}"
            HELP_BODY+=("${line}")
            i18n_lines help_p1_tail
            HELP_BODY+=("${I18N_LINES[@]}")
            ;;
        2)
            # The hold key is named inside the running text, so the page
            # is one format string with the key list as its argument.
            menu_help_keys "[w]" KEY_HOLD
            printf -v line "${I18N[help_p2]}" "${MENU_HELP_KEYS}"
            mapfile -t HELP_BODY <<< "${line}"
            ;;
        3)
            i18n_lines help_p3_head
            HELP_BODY=("${I18N_LINES[@]}")
            # The two square kinds share one format, so a translation
            # cannot line them up differently from one another.
            printf -v line '  %s%-6s%s - %s' \
                "${TXT_GOLD_SGR}" "${I18N[help_sq_gold]}" "${TXT_RESET_SGR}" \
                "${I18N[help_sq_gold_text]}"
            HELP_BODY+=("${line}")
            printf -v line '  %s%-6s%s - %s' \
                "${TXT_SILVER_SGR}" "${I18N[help_sq_silver]}" "${TXT_RESET_SGR}" \
                "${I18N[help_sq_silver_text]}"
            HELP_BODY+=("${line}")
            i18n_lines help_p3_mid
            HELP_BODY+=("${I18N_LINES[@]}")
            # The bonus values are right aligned as whole strings ("+5",
            # not "+ 5"), so the plus sign stays glued to its number.
            printf -v line '  %-31s %s%3s%s' "${I18N[help_row_base]}" \
                "${TXT_ACCENT_SGR}" "${ROWS_NORMAL}" "${TXT_RESET_SGR}"
            HELP_BODY+=("${line}")
            printf -v line '  %-31s %s%3s%s' "${I18N[help_row_silver]}" \
                "${TXT_SILVER_SGR}" "+${ROWS_SILVER}" "${TXT_RESET_SGR}"
            HELP_BODY+=("${line}")
            printf -v line '  %-31s %s%3s%s' "${I18N[help_row_gold]}" \
                "${TXT_GOLD_SGR}" "+${ROWS_GOLD}" "${TXT_RESET_SGR}"
            HELP_BODY+=("${line}")
            printf -v line '  %-31s %s%3s%s' "${I18N[help_row_hammer]}" \
                "${TXT_WARN_SGR}" "+${ROWS_TETRIS}" "${TXT_RESET_SGR}"
            HELP_BODY+=("${line}")
            i18n_lines help_p3_tail
            HELP_BODY+=("${I18N_LINES[@]}")
            ;;
        4)
            i18n_lines help_p4_head
            HELP_BODY=("${I18N_LINES[@]}")
            for (( i = 0; i < ${#WONDER_FILES[@]}; i++ )); do
                # Six digits since 0.44.0 (costs multiplied by 100, see
                # lib/wonders.sh): with %5d the six-digit entries would
                # push out of their field and break the column. The name
                # field grew from 28 to 29 columns with the translation
                # layer (0.48.0): the longest English name needs 29, and
                # the line still ends well inside the 46 a page has.
                wonder_name "${i}"
                printf -v line '  %d. %-29s %6d' "$(( i + 1 ))" \
                    "${WONDER_NAME}" "${WONDER_COSTS[i]}"
                HELP_BODY+=("${line}")
            done
            i18n_lines help_p4_tail
            HELP_BODY+=("${I18N_LINES[@]}")
            ;;
        5)
            # Added 0.16.0 with the Sprint mode: the manual predates the
            # game modes entirely (it was written when there was only the
            # endless round), and with three of them a page explaining
            # what they are was overdue. Ziel and time limit come from
            # the live constants for the same reason the wonder page
            # reads WONDER_COSTS - a retuned goal must not leave the
            # manual lying.
            # CHANGE 2026-08-03 (0.17.0, with the Time Attack mode): the
            # fourth mode filled this page to the last of its
            # MENU_BODY_MAX lines, so the note about the highscore lists
            # moved to a page of its own (page 7 below). It is the part
            # that is about the modes' scoring rather than about how
            # they are played, and with four modes it had grown past a
            # closing paragraph anyway.
            # CHANGE 2026-08-04 (0.23.0, with the Hochwasser mode): with
            # nothing left to move off it, the fifth mode split the page
            # itself. Three modes here, two on page 6 - the cut runs
            # between the modes that are played against a goal or a
            # clock and the two whose clock is the round itself.
            i18n_lines help_p5_head
            HELP_BODY=("${I18N_LINES[@]}")
            printf -v line "${I18N[help_p5_ultra]}" "${ULTRA_TARGET_ROWS}"
            mapfile -t -O "${#HELP_BODY[@]}" HELP_BODY <<< "${line}"
            fmt_duration $(( SPRINT_TIME_MS / 1000 ))
            printf -v line "${I18N[help_p5_sprint]}" "${FMT_DURATION}"
            mapfile -t -O "${#HELP_BODY[@]}" HELP_BODY <<< "${line}"
            ;;
        6)
            # The second half of the modes page (see page 5).
            i18n_lines help_p6_head
            HELP_BODY=("${I18N_LINES[@]}")
            fmt_duration $(( TIME_ATTACK_START_MS / 1000 ))
            printf -v line "${I18N[help_p6_timeattack]}" "${FMT_DURATION}" \
                "$(( TIME_ATTACK_ROW_MS / 1000 ))"
            mapfile -t -O "${#HELP_BODY[@]}" HELP_BODY <<< "${line}"
            printf -v line "${I18N[help_p6_flood]}" \
                "$(( FLOOD_INTERVAL_MS / 1000 ))"
            mapfile -t -O "${#HELP_BODY[@]}" HELP_BODY <<< "${line}"
            ;;
        7)
            # Split off the modes page in 0.17.0 (see page 5): how the
            # modes are scored, in one place. The rule differs by mode,
            # and the Time Attack exception in particular needs its
            # reason spelled out - otherwise it reads like an oversight
            # next to the other two timed modes.
            i18n_lines help_p7
            HELP_BODY=("${I18N_LINES[@]}")
            ;;
        8)
            # Added 0.20.0 with the demo feature. The count and the
            # playback keys are read from the live state (DEMO_MAX,
            # KEY_PAUSE, KEY_QUIT) for the same reason as the pages
            # before: a retuned constant or a rebound key must not leave
            # the manual lying.
            i18n_lines help_p8_head
            HELP_BODY=("${I18N_LINES[@]}")
            printf -v line "${I18N[help_p8_kept]}" "${DEMO_MAX}"
            HELP_BODY+=("${line}")
            i18n_lines help_p8_mid
            HELP_BODY+=("${I18N_LINES[@]}")
            menu_help_keys "${I18N[key_space]}" KEY_PAUSE
            printf -v line '%-17s %s' "${I18N[help_demo_pause]}" "${MENU_HELP_KEYS}"
            HELP_BODY+=("${line}")
            printf -v line '%-17s %s' "${I18N[help_demo_speed]}" \
                "${I18N[key_arrows_lr]}"
            HELP_BODY+=("${line}")
            menu_help_keys "ESC" KEY_QUIT
            printf -v line '%-17s %s' "${I18N[help_demo_back]}" "${MENU_HELP_KEYS}"
            HELP_BODY+=("${line}")
            ;;
    esac
    return 0
}

# menu_help
# The "Anleitung" main menu entry (added 0.12.0, user request): a short
# tour through the game on nine info screens - what the game is about,
# the controls, hold and preview, the gold/silver squares, the wonder
# construction, the game modes (two pages since the fifth one), how
# their highscore lists are kept and
# the demos (menu_help_body builds each page's
# content). Four things are read from the live state
# instead of being spelled out: the control page prints the current
# bindings (menu_help_keys), the wonder page lists the names and costs
# from lib/wonders.sh, the mode pages name the Ultra row target, the
# Sprint and Time Attack times and the Hochwasser interval, and the demo
# page the number of
# recordings kept plus the playback keys - a rebind, a retuned
# WONDER_COSTS or a retuned goal must never leave the manual lying.
# The text itself comes from the translation table
# (lib/i18n.sh, one block per paragraph); every line has to stay within
# the 46 characters the 48-column minimum leaves next to the two-column
# menu indent, and every page within MENU_BODY_MAX lines.
# CHANGE 2026-07-31 (user request): paging switched from "any key
# advances, no way back" (one menu_message call per page in sequence) to
# left/right arrow browsing that wraps at both ends, like menu_run's
# up/down. Enter, space, ESC and x all close the manual now instead of
# doubling as "next page" - with dedicated paging keys, overloading
# every other key as "advance" would only make it easy to fly past a
# page by accident while actually looking for something on it.
menu_help() {
    local -a lines
    local page=0 dirty=1 l
    while :; do
        if [ "${dirty}" -eq 1 ]; then
            menu_help_body "${page}"
            lines=("  ${I18N[help_title]} ($(( page + 1 ))/${MENU_HELP_PAGES})" "")
            for l in "${HELP_BODY[@]}"; do
                lines+=("  ${l}")
            done
            lines+=("" "  ${I18N[help_nav]}")
            render_menu_frame "${lines[@]}"
            screen_write "${RENDER_MENU_FRAME}"
            dirty=0
        fi
        read_key
        # Repaint after a resize (read_key cleared the screen); rebuilt
        # rather than re-emitted, like every other wait loop here - the
        # frame carries absolute cursor positions for the old size.
        if [ "${REDRAW_PENDING}" -eq 1 ]; then
            REDRAW_PENDING=0
            dirty=1
            continue
        fi
        case "${KEY}" in
            LEFT)  page=$(( (page + MENU_HELP_PAGES - 1) % MENU_HELP_PAGES )); dirty=1 ;;
            RIGHT) page=$(( (page + 1) % MENU_HELP_PAGES )); dirty=1 ;;
            ENTER|SPACE|ESC|x)
                debug_event "help screens closed on page $(( page + 1 ))/${MENU_HELP_PAGES}"
                return 0
                ;;
        esac
    done
}

# menu_confirm TITLE YES_LABEL NO_LABEL LINE...
# Ask a yes/no question: TITLE and the explanatory LINEs are shown above
# a two-entry selection. Returns 0 for "yes", 1 for "no". The declining
# entry is listed first, so it is preselected, and ESC counts as "no" too
# - a confirmation must never be the path of least resistance. Navigation
# and redraw behaviour match menu_run (arrows/w/s, repaint on
# REDRAW_PENDING after a terminal resize).
menu_confirm() {
    local title="${1}" yes_label="${2}" no_label="${3}"
    shift 3
    local -a body=("$@")
    local -a lines
    local sel=0 dirty=1 line
    while :; do
        if [ "${dirty}" -eq 1 ]; then
            lines=("  ${title}" "")
            for line in "${body[@]}"; do
                lines+=("  ${line}")
            done
            lines+=("")
            if [ "${sel}" -eq 0 ]; then
                lines+=($'  \e[7m '"${no_label}"$' \e[0m')
                lines+=("   ${yes_label} ")
            else
                lines+=("   ${no_label} ")
                lines+=($'  \e[7m '"${yes_label}"$' \e[0m')
            fi
            lines+=("" "  ${I18N[menu_nav_cancel]}")
            render_menu_frame "${lines[@]}"
            screen_write "${RENDER_MENU_FRAME}"
            dirty=0
        fi
        read_key
        if [ "${REDRAW_PENDING}" -eq 1 ]; then
            REDRAW_PENDING=0
            dirty=1
        fi
        case "${KEY}" in
            UP|DOWN|w|s) sel=$(( 1 - sel )); dirty=1 ;;
            ENTER|SPACE)
                if [ "${sel}" -eq 1 ]; then
                    debug_event "confirm '${title}': yes"
                    return 0
                fi
                debug_event "confirm '${title}': no"
                return 1
                ;;
            ESC|x)
                debug_event "confirm '${title}': cancelled"
                return 1
                ;;
        esac
    done
}

# menu_pause: opened by the quit key (ESC/x) during a running round
# (issue #12: quitting used to end the round on the spot). The player
# chooses to resume, to restart the round (since 0.18.0, user request),
# to suspend the round and go to the main menu
# (where it stays resumable via the "Fortsetzen" entry, offered in the
# main menu and in the singleplayer menu) or to end the
# round for good; ESC/back counts as resume. The two entries that
# discard the round are confirmed first (see below). Only sets GAME_EXIT,
# GAME_RESTART and
# GAME_SUSPENDED - recording the round and starting the fresh one stay
# with the caller (rowhammer.sh), so the
# books close only when the round really ends.
# "Neustarten" sits right below "Fortsetzen" because it is the other
# way to keep playing; the two entries that leave the round stay at the
# bottom, where the muscle memory of the previous three-entry menu
# expects them.
# The two entries that discard the round - "Neustarten" and "Runde
# beenden" - ask back before they act (user request); "Fortsetzen" and
# "Ins Hauptmenue" do not, because neither loses anything (a suspended
# round waits in the main menu). Declining returns to this menu rather
# than to the round, because a player who did not mean to discard it
# usually still meant to pick something here; hence the loop.
menu_pause() {
    local round_line
    # The state of the round, shown in both questions below: it is what
    # makes them answerable - a round worth keeping is recognized by its
    # counters, not by the board the confirmation covers up.
    printf -v round_line "${I18N[round_state]}" \
        "${CLEARED_TOTAL}" "${ROW_CREDIT}" "${LEVEL}"
    while :; do
        menu_run "${I18N[pause_title]}" \
            "${I18N[main_resume]}" \
            "${I18N[pause_restart]}" \
            "${I18N[pause_to_menu]}" \
            "${I18N[pause_end]}"
        case "${MENU_CHOICE}" in
            1)
                i18n_lines restart_tail
                if menu_confirm "${I18N[restart_title]}" \
                    "${I18N[restart_yes]}" "${I18N[confirm_no]}" \
                    "${I18N[restart_head]}" \
                    "${round_line}" \
                    "" \
                    "${I18N_LINES[@]}"; then
                    GAME_RESTART=1
                    return 0
                fi
                # Declined: back to the pause menu.
                ;;
            2)
                GAME_SUSPENDED=1
                GAME_EXIT=1
                return 0
                ;;
            3)
                # Confirmed like the restart (user request): both throw
                # the round away, and "Runde beenden" sits right below
                # the entry that only suspends it - one line off and the
                # round is over instead of waiting in the main menu.
                i18n_lines end_tail
                if menu_confirm "${I18N[end_title]}" \
                    "${I18N[end_yes]}" "${I18N[confirm_no]}" \
                    "${I18N[end_head]}" \
                    "${round_line}" \
                    "" \
                    "${I18N_LINES[@]}"; then
                    GAME_EXIT=1
                    return 0
                fi
                # Declined: back to the pause menu.
                ;;
            *)
                # "Fortsetzen" or ESC: straight back into the round.
                return 0
                ;;
        esac
    done
}

# menu_mode_entries
# Fill the global array MENU_MODE_ENTRIES with the five game modes as the
# three pickers (singleplayer, highscores, statistics) offer them: every
# mode but Marathon names what it is up against - a goal, a time limit or
# the flood interval - read from the live constants, so a retuned value
# cannot leave a menu lying. One builder for all three, so
# the same mode reads the same way wherever it is picked - which used to
# be three copies of the same four strings.
MENU_MODE_ENTRIES=()
menu_mode_entries() {
    local entry
    MENU_MODE_ENTRIES=("${I18N[mode_marathon]}")
    printf -v entry "${I18N[entry_ultra]}" "${ULTRA_TARGET_ROWS}"
    MENU_MODE_ENTRIES+=("${entry}")
    fmt_duration $(( SPRINT_TIME_MS / 1000 ))
    printf -v entry "${I18N[entry_sprint]}" "${FMT_DURATION}"
    MENU_MODE_ENTRIES+=("${entry}")
    fmt_duration $(( TIME_ATTACK_START_MS / 1000 ))
    printf -v entry "${I18N[entry_timeattack]}" "${FMT_DURATION}" \
        "$(( TIME_ATTACK_ROW_MS / 1000 ))"
    MENU_MODE_ENTRIES+=("${entry}")
    printf -v entry "${I18N[entry_flood]}" \
        "$(( FLOOD_INTERVAL_MS / 1000 ))"
    MENU_MODE_ENTRIES+=("${entry}")
    return 0
}

# menu_singleplayer: the game modes. "Marathon" is the endless
# round, "Ultra" the race for ULTRA_TARGET_ROWS rows against the clock
# (0.14.0, user request), "Sprint" its mirror image - as many rows as
# possible within SPRINT_TIME_MS (0.16.0, user request) -,
# "Time Attack" the countdown a run extends by TIME_ATTACK_ROW_MS per
# row of credit (0.17.0, user request) and "Hochwasser" Marathon with a
# flood row rising every FLOOD_INTERVAL_MS (0.23.0, user request). The chosen entry
# is passed to game_run as the mode name, so adding one is a matter of
# an entry plus its case branch. After a
# game session the wonder construction site is shown with the freshly
# banked row total (the round credit was banked by record_round) -
# regardless of the mode, because every cleared row builds the wonder.
# A round suspended via the pause menu skips that screen and returns to
# the main menu instead, where its "Fortsetzen" entry picks it up.
# While a suspended round waits, this menu offers the same "Fortsetzen"
# entry at the top as the main menu (the other entries shift down by
# one, so the selection is normalized before the dispatch).
menu_singleplayer() {
    local -a entries
    local choice
    while :; do
        entries=()
        if [ "${GAME_SUSPENDED}" -eq 1 ]; then
            entries+=("${I18N[main_resume]}")
        fi
        menu_mode_entries
        entries+=("${MENU_MODE_ENTRIES[@]}" "${I18N[menu_back]}")
        menu_run "${I18N[sp_title]}" "${entries[@]}"
        choice="${MENU_CHOICE}"
        if [ "${GAME_SUSPENDED}" -eq 1 ]; then
            if [ "${choice}" -eq 0 ]; then
                game_run resume
                if [ "${GAME_SUSPENDED}" -eq 1 ]; then
                    return 0
                fi
                wonder_screen "${TOTAL_ROW_CREDIT}"
                continue
            elif [ "${choice}" -gt 0 ]; then
                choice=$(( choice - 1 ))
            fi
        fi
        case "${choice}" in
            0) game_run marathon ;;
            1) game_run ultra ;;
            2) game_run sprint ;;
            3) game_run timeattack ;;
            4) game_run flood ;;
            *) return 0 ;;
        esac
        if [ "${GAME_SUSPENDED}" -eq 1 ]; then
            return 0
        fi
        wonder_screen "${TOTAL_ROW_CREDIT}"
    done
}

# menu_highscores: the "Highscores" main menu entry. Since 0.15.0 (user
# request) there is a list per game mode to choose from - the endless
# Marathon rounds ranked by rows, the Ultra runs ranked by the shortest
# time, since 0.16.0 the Sprint runs ranked by the rows scored in
# three minutes and, since 0.17.0, the Time Attack runs ranked by the
# rows scored on a clock they had to keep feeding
# (lib/highscore.sh keeps them in separate files with
# separate orders, because they are not comparable). Hence a picker in
# front of them rather than one screen: merging them would mean several
# orderings in one table, and appending one list to another would bury
# it behind the pages of the other.
# The entries mirror the singleplayer menu's, down to the wording of the
# goals, so the same mode reads the same way wherever it is picked.
# Loops instead of returning after one list, so comparing them costs
# no walk back through the main menu; ESC or "Zurueck" leaves.
menu_highscores() {
    while :; do
        menu_mode_entries
        menu_run "${I18N[hs_title]}" "${MENU_MODE_ENTRIES[@]}" \
            "${I18N[menu_back]}"
        case "${MENU_CHOICE}" in
            0) highscore_screen ;;
            1) highscore_ultra_screen ;;
            2) highscore_sprint_screen ;;
            3) highscore_timeattack_screen ;;
            4) highscore_flood_screen ;;
            *) return 0 ;;
        esac
    done
}

# menu_stats: the "Statistik" main menu entry. Picks between the
# all-time statistics - the counters over every round ever played, on
# three screens - and one game mode's own counters (lib/stats.sh, per
# mode since 0.21.0, user request). A picker in front of them for the
# same reason menu_highscores has one: the modes are played for
# different things, so their counters only mean something next to the
# label of the mode they were scored in, and putting four more tables on
# the sequence of screens the "Statistik" entry already walks through
# would bury the all-time figures behind them.
# The mode entries are worded exactly like the ones in menu_highscores
# and in the singleplayer menu, so a mode reads the same way wherever it
# is picked. Loops instead of returning after one screen, so comparing
# the modes costs no walk back through the main menu; ESC or "Zurueck"
# leaves.
menu_stats() {
    while :; do
        menu_mode_entries
        menu_run "${I18N[stats_title]}" "${I18N[stats_all]}" \
            "${MENU_MODE_ENTRIES[@]}" "${I18N[menu_back]}"
        case "${MENU_CHOICE}" in
            0) stats_screen ;;
            1) stats_mode_screen "marathon" ;;
            2) stats_mode_screen "ultra" ;;
            3) stats_mode_screen "sprint" ;;
            4) stats_mode_screen "timeattack" ;;
            5) stats_mode_screen "flood" ;;
            *) return 0 ;;
        esac
    done
}

# menu_demos: the "Demos" main menu entry. Lists the recorded rounds
# (lib/demo.sh) newest first and offers to watch or delete the one
# picked. The list is rebuilt on every pass, so a deleted entry is gone
# from it at once and a round played in between shows up.
# Playing is refused while a round is suspended in the main menu: a
# replay runs through the very game state that round is parked in
# (board, counters, queue), so starting one would silently throw the
# suspended round away. Refusing is the honest way around that - the
# round is only ever a "Fortsetzen" away from being finished.
menu_demos() {
    local -a entries lines
    local n choice file title hint
    while :; do
        demo_scan
        n="${#DEMO_LIST_FILE[@]}"
        if [ "${n}" -eq 0 ]; then
            if [ "${DEMO_RECORD}" = "on" ]; then
                printf -v hint "${I18N[demos_none_on]}" "${DEMO_MAX}"
                mapfile -t lines <<< "${hint}"
            else
                i18n_lines demos_none_off
                lines=("${I18N_LINES[@]}")
            fi
            menu_message "${I18N[demos_title]}" \
                "${I18N[demos_none]}" "" "${lines[@]}"
            return 0
        fi
        entries=("${DEMO_LIST_LABEL[@]}" "${I18N[menu_back]}")
        # The count is not "n of DEMO_MAX" any more: a recording that
        # backs a highscore entry is kept beyond that cap, so the list
        # can legitimately be longer. The legend explains the marker
        # those entries carry; it only appears when there is one.
        if [ "${DEMO_LIST_KEPT}" -gt 0 ]; then
            printf -v title "${I18N[demos_title_kept]}" "${n}"
        else
            printf -v title "${I18N[demos_title_count]}" "${n}" "${DEMO_MAX}"
        fi
        menu_run "${title}" "${entries[@]}"
        choice="${MENU_CHOICE}"
        if [ "${choice}" -lt 0 ] || [ "${choice}" -ge "${n}" ]; then
            return 0
        fi
        file="${DEMO_LIST_FILE[choice]}"
        menu_run "${I18N[demo_title]}" \
            "${I18N[demo_play]}" \
            "${I18N[demo_delete]}" \
            "${I18N[menu_back]}"
        case "${MENU_CHOICE}" in
            0)
                if [ "${GAME_SUSPENDED}" -eq 1 ]; then
                    i18n_lines demo_busy
                    menu_message "${I18N[demo_title]}" "${I18N_LINES[@]}"
                    continue
                fi
                demo_play "${file}"
                # The replay owned the whole screen; the next menu frame
                # has to clear it before drawing.
                render_menu_dirty
                ;;
            1)
                # A protected recording can still be deleted - it is an
                # explicit choice on a single entry, not the sweeping
                # pruning - but it says so first, because that recording
                # is the one the pruning would have kept.
                if [ "${DEMO_LIST_MARKED[choice]}" = "*" ]; then
                    hint="${I18N[demo_del_hint]}"
                else
                    hint=""
                fi
                i18n_lines demo_del_body
                if menu_confirm "${I18N[demo_del_title]}" \
                    "${I18N[demo_del_yes]}" "${I18N[demo_del_no]}" \
                    "${DEMO_LIST_LABEL[choice]}" \
                    "${hint}" \
                    "" \
                    "${I18N_LINES[@]}"; then
                    if ! demo_delete "${file}"; then
                        i18n_lines demo_del_failed
                        menu_message "${I18N[demo_title]}" \
                            "${I18N_LINES[@]}" \
                            "" \
                            "${file}"
                    fi
                fi
                ;;
        esac
    done
}

# menu_settings: key bindings, color theme, player name and whether
# rounds are recorded as demos; every change is written to the user
# config file immediately.
menu_settings() {
    local demo_label theme_entry name_entry demo_entry lang_entry
    while :; do
        if [ "${DEMO_RECORD}" = "on" ]; then
            demo_label="${I18N[on]}"
        else
            demo_label="${I18N[off]}"
        fi
        printf -v theme_entry "${I18N[set_theme]}" \
            "${I18N[theme_${COLOR_THEME}]}"
        printf -v name_entry "${I18N[set_name]}" "${PLAYER_NAME}"
        printf -v demo_entry "${I18N[set_demo]}" "${demo_label}"
        # The language entry names the language it is currently set to,
        # and for "auto" the one that setting resolves to right now
        # (i18n_lang_label) - which is the only thing "automatic" does
        # not say by itself.
        i18n_lang_label "${LANGUAGE}"
        printf -v lang_entry "${I18N[set_lang]}" "${I18N_LABEL}"
        menu_run "${I18N[set_title]}" \
            "${I18N[set_keys]}" \
            "${lang_entry}" \
            "${theme_entry}" \
            "${name_entry}" \
            "${demo_entry}" \
            "${I18N[menu_back]}"
        case "${MENU_CHOICE}" in
            0) menu_keys ;;
            1) menu_language ;;
            2) menu_colors ;;
            3) prompt_player_name ;;
            4)
                # A plain toggle rather than a picker: there are two
                # states and the entry above names the current one.
                if [ "${DEMO_RECORD}" = "on" ]; then
                    DEMO_RECORD="off"
                else
                    DEMO_RECORD="on"
                fi
                debug_event "settings: demo recording ${DEMO_RECORD}"
                config_save
                ;;
            *) return 0 ;;
        esac
    done
}

# menu_language: pick the interface language (lib/i18n.sh). Lists
# "automatic" first and then every language this game speaks, each in
# its own name, with the active setting marked "*"; selecting applies it
# at once (i18n_init reloads the table) and persists it, so the menu
# behind this one is already drawn in the new language. ESC leaves the
# setting untouched.
# Added 0.48.0 with the translation layer. Deliberately menu_run rather
# than a picker of its own like menu_colors: the entries are plain text,
# so there is nothing here the generic list cannot draw - and menu_run
# is where the scrolling and the resize handling already live.
menu_language() {
    local -a entries=() codes=()
    local i code
    codes=(auto "${I18N_LANGS[@]}")
    for code in "${codes[@]}"; do
        i18n_lang_label "${code}"
        if [ "${code}" = "${LANGUAGE}" ]; then
            entries+=("* ${I18N_LABEL}")
        else
            entries+=("  ${I18N_LABEL}")
        fi
    done
    entries+=("${I18N[menu_back]}")
    menu_run "${I18N[lang_title]}" "${entries[@]}"
    i="${MENU_CHOICE}"
    if [ "${i}" -lt 0 ] || [ "${i}" -ge "${#codes[@]}" ]; then
        return 0
    fi
    if [ "${codes[i]}" = "${LANGUAGE}" ]; then
        return 0
    fi
    LANGUAGE="${codes[i]}"
    i18n_init
    debug_event "language set: ${LANGUAGE} (using ${I18N_LANG})"
    config_save
    # The board keeps HUD labels of the old language in the frame cache
    # (render_flush compares against it), and the labels are exactly what
    # just changed - so the next game frame has to be written in full.
    RENDER_FULL=1
    return 0
}

# menu_colors: pick the color theme (lib/pieces.sh). Lists every theme
# with a live color swatch (render_theme_swatch) so the palette is
# visible while browsing; the active theme is marked with "*". Selecting
# applies the theme at once (render_colors_init) and persists it. ESC
# leaves the current theme unchanged. Its own selection loop instead of
# menu_run, because the entries carry raw SGR swatches menu_run would not
# render.
# CHANGE 2026-07-27 (merge): repaint on REDRAW_PENDING - this loop did
# not, so a resize could leave the picker blank, unlike every sibling
# menu here. Its stale-first-line guard became obsolete on 2026-07-28
# when the screens moved to render_menu_frame (see menu_run).
menu_colors() {
    local -a lines
    local n sel=0 i dirty=1 mark label
    n="${#COLOR_THEMES[@]}"
    for (( i = 0; i < n; i++ )); do
        if [ "${COLOR_THEMES[i]}" = "${COLOR_THEME}" ]; then
            sel="${i}"
        fi
    done
    while :; do
        if [ "${dirty}" -eq 1 ]; then
            lines=("  ${I18N[theme_title]}" "")
            for (( i = 0; i < n; i++ )); do
                if [ "${COLOR_THEMES[i]}" = "${COLOR_THEME}" ]; then
                    mark="*"
                else
                    mark=" "
                fi
                printf -v label '%s %-11s' "${mark}" \
                    "${I18N[theme_${COLOR_THEMES[i]}]}"
                render_theme_swatch "${COLOR_THEMES[i]}"
                if (( i == sel )); then
                    lines+=($'  \e[7m '"${label}"$' \e[0m  '"${RENDER_SWATCH}")
                else
                    lines+=("   ${label}  ${RENDER_SWATCH}")
                fi
            done
            lines+=("" "  ${I18N[menu_nav]}")
            render_menu_frame "${lines[@]}"
            screen_write "${RENDER_MENU_FRAME}"
            dirty=0
        fi
        read_key
        # A terminal resize handled inside read_key clears the screen and
        # raises REDRAW_PENDING; repaint the picker so it does not vanish.
        if [ "${REDRAW_PENDING}" -eq 1 ]; then
            REDRAW_PENDING=0
            dirty=1
        fi
        case "${KEY}" in
            UP|w)   sel=$(( (sel + n - 1) % n )); dirty=1 ;;
            DOWN|s) sel=$(( (sel + 1) % n )); dirty=1 ;;
            ENTER|SPACE)
                COLOR_THEME="${COLOR_THEMES[sel]}"
                render_colors_init
                debug_event "color theme set: ${COLOR_THEME}"
                config_save
                return 0
                ;;
            ESC|x)
                return 0
                ;;
        esac
    done
}

# menu_keys: list every action with its current key and rebind on select.
menu_keys() {
    local -a entries
    local i ref
    while :; do
        entries=()
        for i in "${!KEY_ACTIONS[@]}"; do
            ref="${KEY_ACTIONS[i]}"
            entries+=("$(printf '%-18s [%s]' "${I18N[keylabel_${ref}]}" "${!ref}")")
        done
        entries+=("${I18N[menu_back]}")
        menu_run "${I18N[set_keys]}" "${entries[@]}"
        if [ "${MENU_CHOICE}" -ge 0 ] && [ "${MENU_CHOICE}" -lt "${#KEY_ACTIONS[@]}" ]; then
            ref="${KEY_ACTIONS[MENU_CHOICE]}"
            prompt_rebind "${ref}" "${I18N[keylabel_${ref}]}"
        else
            return 0
        fi
    done
}

# prompt_rebind VAR LABEL
# Capture one key for the given binding variable. Letters a-z, digits and
# space are allowed; arrows, Enter and ESC stay reserved for menus, "r"
# stays reserved for the game over restart. Refuses keys that are already
# bound to another action, then persists the new binding.
prompt_rebind() {
    local var="${1}" label="${2}" other ask current
    local -a lines
    printf -v ask "${I18N[rebind_ask]}" "${label}"
    printf -v current "${I18N[rebind_current]}" "${!var}"
    lines=("  ${I18N[set_keys]}" ""
           "  ${ask}"
           "  ${current}")
    render_menu_frame "${lines[@]}"
    screen_write "${RENDER_MENU_FRAME}"
    KEY=""
    while [ -z "${KEY}" ]; do
        read_key
        # Repaint the prompt after a resize (read_key cleared the screen);
        # rebuilt, because the frame holds absolute cursor positions.
        if [ "${REDRAW_PENDING}" -eq 1 ]; then
            REDRAW_PENDING=0
            render_menu_frame "${lines[@]}"
            screen_write "${RENDER_MENU_FRAME}"
        fi
    done
    case "${KEY}" in
        ESC)
            return 0
            ;;
        ENTER|UP|DOWN|LEFT|RIGHT)
            i18n_lines rebind_reserved_menu
            menu_message "${I18N[set_keys]}" "${I18N_LINES[@]}"
            return 0
            ;;
        r)
            i18n_lines rebind_reserved_r
            menu_message "${I18N[set_keys]}" "${I18N_LINES[@]}"
            return 0
            ;;
    esac
    local re='^([a-z0-9]|SPACE)$'
    if ! [[ "${KEY}" =~ ${re} ]]; then
        i18n_lines rebind_invalid
        menu_message "${I18N[set_keys]}" "${I18N_LINES[@]}"
        return 0
    fi
    for other in "${KEY_ACTIONS[@]}"; do
        if [ "${other}" != "${var}" ] && [ "${!other}" = "${KEY}" ]; then
            printf -v ask "${I18N[rebind_taken]}" "${KEY}"
            menu_message "${I18N[set_keys]}" "${ask}"
            return 0
        fi
    done
    printf -v "${var}" '%s' "${KEY}"
    debug_event "key rebind: ${var}=${KEY}"
    config_save
    return 0
}

# --- Name input -----------------------------------------------------------
# What a name may consist of and how long it may get. Both mirror the
# pattern the player name is validated against on startup and on loading
# the config (rowhammer.sh, lib/config.sh): the editor below refuses
# every key that would not pass that check, so it cannot produce an
# invalid name and no validation step is needed behind it.
MENU_INPUT_RE='^[A-Za-z0-9_ -]$'
MENU_INPUT_MAX=16
MENU_INPUT=""

# menu_text_input TITLE DEFAULT LINE...
# Ask for a short text with DEFAULT preselected. TITLE and the LINEs are
# shown above the input line; the result lands in MENU_INPUT. Returns 0
# when the player confirmed with Enter (MENU_INPUT may be empty then -
# what an empty input means is the caller's decision) and 1 when they
# left with ESC, in which case MENU_INPUT is not to be used.
#
# "Preselected" is meant as in a graphical text field (2026-08-03, user
# request): the default starts out marked (drawn in reverse video), and
# the first character typed replaces it as a whole instead of being
# appended - changing the name is typing it, keeping it is pressing
# Enter. Backspace on the marked default clears it; any cursor key lifts
# the marking and keeps the text, so the default can also be edited
# rather than replaced. Once the marking is gone the line behaves like an
# ordinary input: characters append, backspace erases the last one.
#
# The frame is drawn by this function rather than by the terminal (the
# session stays in raw mode, see lib/input.sh): a terminal-side line
# editor cannot show a marked default, and its echo would land wherever
# the cursor is instead of inside the centered menu block. The keys come
# from read_key in text mode (KEY_TEXT), which is what keeps upper case
# and reports backspace.
menu_text_input() {
    local title="${1}" value="${2}"
    shift 2
    local -a body=("$@")
    local -a lines
    local marked=1 dirty=1 line shown ins
    while :; do
        if [ "${dirty}" -eq 1 ]; then
            lines=("  ${title}" "")
            for line in "${body[@]}"; do
                lines+=("  ${line}")
            done
            # The marked default is shown in reverse video; once the
            # marking is gone a reverse-video block behind the text
            # stands in for the cursor, which stays hidden all session.
            if [ "${marked}" -eq 1 ] && [ -n "${value}" ]; then
                shown=$'\e[7m'"${value}"$'\e[0m'
            else
                shown="${value}"$'\e[7m \e[0m'
            fi
            lines+=("" "  > ${shown}" "")
            lines+=("  ${I18N[input_hint_type]}")
            lines+=("  ${I18N[input_hint_keys]}")
            render_menu_frame "${lines[@]}"
            screen_write "${RENDER_MENU_FRAME}"
            dirty=0
        fi
        # Text mode only for the read itself, so no return path can leave
        # it switched on for the game loop.
        KEY_TEXT=1
        read_key
        KEY_TEXT=0
        # Repaint after a resize (read_key cleared the screen); rebuilt
        # rather than re-emitted like in every other wait loop here.
        if [ "${REDRAW_PENDING}" -eq 1 ]; then
            REDRAW_PENDING=0
            dirty=1
            continue
        fi
        ins=""
        case "${KEY}" in
            ENTER)
                MENU_INPUT="${value}"
                debug_event "text input '${title}': '${value}'"
                return 0
                ;;
            ESC)
                MENU_INPUT=""
                debug_event "text input '${title}': cancelled"
                return 1
                ;;
            BACKSPACE)
                if [ "${marked}" -eq 1 ]; then
                    value=""
                    marked=0
                else
                    value="${value%?}"
                fi
                dirty=1
                ;;
            LEFT|RIGHT|UP|DOWN)
                # Editing instead of replacing: keep the text, drop the
                # marking. There is no cursor to move inside the text -
                # the line is at most MENU_INPUT_MAX characters long and
                # is edited from its end.
                if [ "${marked}" -eq 1 ]; then
                    marked=0
                    dirty=1
                fi
                ;;
            SPACE) ins=" " ;;
            # A single character is a typed character (the multi-character
            # symbols are all handled above), including the letters the
            # game binds elsewhere: in this prompt "x" is an x.
            ?) ins="${KEY}" ;;
        esac
        if [ -n "${ins}" ] && [[ "${ins}" =~ ${MENU_INPUT_RE} ]]; then
            if [ "${marked}" -eq 1 ]; then
                value="${ins}"
                marked=0
                dirty=1
            elif [ "${#value}" -lt "${MENU_INPUT_MAX}" ]; then
                value="${value}${ins}"
                dirty=1
            fi
        fi
    done
}

# prompt_player_name
# Change the player name kept in the settings (and in the config file).
# The current name is the preselected default, an unchanged or empty
# input leaves everything alone, and so does leaving with ESC.
prompt_player_name() {
    local -a body
    local line
    printf -v line "${I18N[name_current]}" "${PLAYER_NAME}"
    body=("${line}" "")
    printf -v line "${I18N[name_rules]}" "${MENU_INPUT_MAX}"
    mapfile -t -O "${#body[@]}" body <<< "${line}"
    if ! menu_text_input "${I18N[name_title]}" "${PLAYER_NAME}" "${body[@]}"; then
        return 0
    fi
    if [ -z "${MENU_INPUT}" ] || [ "${MENU_INPUT}" = "${PLAYER_NAME}" ]; then
        return 0
    fi
    PLAYER_NAME="${MENU_INPUT}"
    debug_event "player name changed to '${PLAYER_NAME}'"
    config_save
    return 0
}

# The name the round that just ended is filed under; set by
# prompt_round_name and read by record_round (rowhammer.sh).
ROUND_NAME=""

# prompt_round_name
# Ask at the end of a round which name it enters its highscore list
# under (2026-08-03, user request). The settings name is the preselected
# default, so keeping it is one Enter, and typing replaces it - see
# menu_text_input for the editing rules.
#
# The entered name applies to this one round; the settings name (and with
# it the default of the next round) stays untouched. That is what keeps
# the prompt useful for the case it exists for - somebody else playing a
# round on this machine - and it keeps the settings entry the one place
# that decides what the default is. Whoever wants to change the default
# changes it in the settings menu.
#
# Called from record_round, and only for a round that really enters one
# of the lists: a round nobody files anywhere has no name to ask for.
# Everything else the round feeds - wonder progress, statistics - is
# nameless anyway.
prompt_round_name() {
    local -a body
    local line
    fmt_duration "$(( PLAY_MS / 1000 ))"
    printf -v line "${I18N[round_mode]}" "${I18N[mode_${GAME_MODE}]}"
    body=("${line}")
    printf -v line "${I18N[round_rows]}" "${ROW_CREDIT}" "${CLEARED_TOTAL}"
    body+=("${line}")
    printf -v line "${I18N[round_level]}" "${LEVEL}" "${FMT_DURATION}"
    body+=("${line}" "" "${I18N[round_ask_name]}")
    ROUND_NAME="${PLAYER_NAME}"
    if menu_text_input "${I18N[round_title]}" "${PLAYER_NAME}" "${body[@]}"; then
        # An empty line means the same as ESC here: nothing to file the
        # round under, so it keeps the name from the settings.
        if [ -n "${MENU_INPUT}" ]; then
            ROUND_NAME="${MENU_INPUT}"
        fi
    fi
    debug_event "round name: '${ROUND_NAME}' (default '${PLAYER_NAME}')"
    # The prompt owned the whole screen; whatever the caller returns to -
    # the board with its result box, or another menu - has to be redrawn
    # in full. (A following menu frame needs no such flag: this was one.)
    RENDER_FULL=1
    return 0
}
