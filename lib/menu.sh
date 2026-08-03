#!/usr/bin/env bash
#
# lib/menu.sh
#
# Description:
#   Menu system for rowhammer: a generic list-selection widget plus the
#   application menus (main menu, singleplayer with its game modes,
#   multiplayer placeholder,
#   settings with key bindings, color theme and player name). Menu labels are German
#   on purpose (requested UI language); code and comments stay English
#   per the script conventions. All screen output goes through
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
#   0.12.0, user request) is the "Anleitung" main menu entry: seven info
#   screens explaining the game, the controls, hold and preview, the
#   gold/silver squares, the wonder construction, the game modes and how
#   their highscore lists are kept,
#   with the key bindings, the wonder costs and the mode goals read from
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
#   Since 0.11.0 every screen here is built as an array of plain content
#   lines and handed to render_menu_frame (lib/render.sh), which draws it
#   centered like the play screen instead of into the top left corner;
#   the repaint after a resize rebuilds the frame, because its cursor
#   positions belong to the terminal size they were computed for.
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.19.0  (2026-08-03)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/menu.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# German display labels for the key binding variables in KEY_ACTIONS
# (same order; both live side by side so rebinding stays table-driven).
KEY_LABELS=("Links" "Rechts" "Drehen rechts" "Drehen links"
            "Soft-Drop" "Hard-Drop" "Pause" "Zurueck ins Menue" "Hold")

MENU_CHOICE=-1

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
    local n="${#entries[@]}" sel=0 dirty=1 i
    while :; do
        if [ "${dirty}" -eq 1 ]; then
            lines=("  ${title}" "")
            for (( i = 0; i < n; i++ )); do
                if (( i == sel )); then
                    lines+=($'  \e[7m '"${entries[i]}"$' \e[0m')
                else
                    lines+=("   ${entries[i]} ")
                fi
            done
            lines+=("" "  Pfeile/w/s: waehlen   Enter: OK   ESC: zurueck")
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
    lines+=("" "  Beliebige Taste druecken...")
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
    local total rest pages p from i
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
            menu_message "${title} (Seite $(( p + 1 ))/${pages})" "${body[@]}"
        else
            menu_message "${title}" "${body[@]}"
        fi
    done
    return 0
}

# Number of screens menu_help walks through; used both to number the
# titles ("Anleitung (2/7)") and to wrap the left/right paging
# (menu_help below), so the pages stay self-describing.
MENU_HELP_PAGES=7

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
        SPACE) key="Leertaste" ;;
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
            HELP_BODY=("rowhammer ist ein Tetris-Spiel fuers Terminal," \
                  "Vorbild ist \"The New Tetris\" (N64)." \
                  "" \
                  "Bausteine muessen so gestapelt werden, dass sich" \
                  "Reihen komplett fuellen: volle Reihen werden" \
                  "abgebaut und als \"Rows\" gewertet - das ist" \
                  "zugleich der Punktestand der Runde." \
                  "" \
                  "Die Steine kommen aus einem 7er-Beutel: Jede" \
                  "der sieben Sorten genau einmal, dann wird" \
                  "neu gemischt." \
                  "" \
                  "Mit jeder abgebauten Reihe steigt das Level," \
                  "und die Steine fallen schneller. Ist kein" \
                  "Platz mehr fuer einen neuen Stein, ist die" \
                  "Runde vorbei.")
            ;;
        1)
            HELP_BODY=("Steuerung im Spiel (die Buchstabentasten" \
                  "sind unter Einstellungen aenderbar):" \
                  "")
            menu_help_keys "Pfeil links" KEY_LEFT
            printf -v line '%-17s %s' "Nach links" "${MENU_HELP_KEYS}"
            HELP_BODY+=("${line}")
            menu_help_keys "Pfeil rechts" KEY_RIGHT
            printf -v line '%-17s %s' "Nach rechts" "${MENU_HELP_KEYS}"
            HELP_BODY+=("${line}")
            menu_help_keys "" KEY_ROT_CW
            printf -v line '%-17s %s' "Drehen rechts" "${MENU_HELP_KEYS}"
            HELP_BODY+=("${line}")
            menu_help_keys "" KEY_ROT_CCW
            printf -v line '%-17s %s' "Drehen links" "${MENU_HELP_KEYS}"
            HELP_BODY+=("${line}")
            menu_help_keys "Pfeil runter" KEY_SOFT
            printf -v line '%-17s %s' "Soft-Drop" "${MENU_HELP_KEYS}"
            HELP_BODY+=("${line}")
            # Space and arrow up always drop hard, w always holds - the
            # game wires both in regardless of the bindings (handle_key).
            menu_help_keys "Leertaste, Pfeil hoch" KEY_HARD
            printf -v line '%-17s %s' "Hard-Drop" "${MENU_HELP_KEYS}"
            HELP_BODY+=("${line}")
            menu_help_keys "[w]" KEY_HOLD
            printf -v line '%-17s %s' "Hold / Tauschen" "${MENU_HELP_KEYS}"
            HELP_BODY+=("${line}")
            menu_help_keys "" KEY_PAUSE
            printf -v line '%-17s %s' "Pause" "${MENU_HELP_KEYS}"
            HELP_BODY+=("${line}")
            menu_help_keys "ESC" KEY_QUIT
            printf -v line '%-17s %s' "Pausenmenue" "${MENU_HELP_KEYS}"
            HELP_BODY+=("${line}")
            HELP_BODY+=("" \
                   "Soft-Drop laesst den Stein schneller fallen," \
                   "Hard-Drop setzt ihn sofort fest." \
                   "Neustart: [r] im Game Over oder Pausenmenue." \
                   "In den Menues: Pfeile oder w/s waehlen," \
                   "Enter bestaetigt, ESC geht zurueck.")
            ;;
        2)
            menu_help_keys "[w]" KEY_HOLD
            HELP_BODY=("Vorschau und Hold" \
                  "" \
                  "Oben rechts (\"Next\") stehen die naechsten" \
                  "drei Steine - genug Vorlauf, um den Stapel" \
                  "zu planen." \
                  "" \
                  "Links oben liegt der Hold-Speicher. Mit" \
                  "${MENU_HELP_KEYS} wandert der aktuelle Stein dorthin;" \
                  "liegt dort schon einer, tauschen die beiden" \
                  "die Plaetze und der geholdete Stein faellt" \
                  "in seiner Startlage neu ein." \
                  "" \
                  "Pro Zug ist nur ein Tausch erlaubt - erst" \
                  "nach dem naechsten Ablegen kann erneut getauscht" \
                  "werden. So laesst sich ein I-Stein fuer den" \
                  "grossen Abbau aufheben oder ein unpassendes" \
                  "Teil kurz parken.")
            ;;
        3)
            HELP_BODY=("Vier vollstaendige, unversehrte Steine, die" \
                  "zusammen ein 4x4-Quadrat exakt ausfuellen," \
                  "werden zu einem Bonusblock:" \
                  "")
            printf -v line '  %sGold%s   - alle vier Steine gleicher Sorte' \
                "${TXT_GOLD_SGR}" "${TXT_RESET_SGR}"
            HELP_BODY+=("${line}")
            printf -v line '  %sSilber%s - vier gemischte Sorten' \
                "${TXT_SILVER_SGR}" "${TXT_RESET_SGR}"
            HELP_BODY+=("${line}")
            HELP_BODY+=("" \
                   "Ein Stein, den ein Reihenabbau bereits" \
                   "zerschnitten hat, zaehlt nicht mehr mit." \
                   "" \
                   "Beim Abbau einer Reihe zaehlt (in Rows):")
            # The bonus values are right aligned as whole strings ("+5",
            # not "+ 5"), so the plus sign stays glued to its number.
            printf -v line '  %-31s %s%3s%s' "Grundwert je Reihe" \
                "${TXT_ACCENT_SGR}" "${ROWS_NORMAL}" "${TXT_RESET_SGR}"
            HELP_BODY+=("${line}")
            printf -v line '  %-31s %s%3s%s' "je Silber-Quadrat in der Reihe" \
                "${TXT_SILVER_SGR}" "+${ROWS_SILVER}" "${TXT_RESET_SGR}"
            HELP_BODY+=("${line}")
            printf -v line '  %-31s %s%3s%s' "je Gold-Quadrat in der Reihe" \
                "${TXT_GOLD_SGR}" "+${ROWS_GOLD}" "${TXT_RESET_SGR}"
            HELP_BODY+=("${line}")
            printf -v line '  %-31s %s%3s%s' "Rowhammer (4 Reihen auf einmal)" \
                "${TXT_WARN_SGR}" "+${ROWS_TETRIS}" "${TXT_RESET_SGR}"
            HELP_BODY+=("${line}")
            HELP_BODY+=("" \
                   "Ein Rowhammer quer durch zwei komplette" \
                   "Gold-Quadrate bringt so 4+1+80 = 85 Rows.")
            ;;
        4)
            HELP_BODY=("Alle abgebauten Reihen zaehlen ueber die" \
                  "Runden hinweg zusammen (auch die einer" \
                  "abgebrochenen Runde) und bauen nacheinander" \
                  "sieben Weltwunder auf." \
                  "" \
                  "Gewertete Reihen je Weltwunder:")
            for (( i = 0; i < ${#WONDER_NAMES_DE[@]}; i++ )); do
                printf -v line '  %d. %-28s %5d' "$(( i + 1 ))" \
                    "${WONDER_NAMES_DE[i]}" "${WONDER_COSTS[i]}"
                HELP_BODY+=("${line}")
            done
            HELP_BODY+=("" \
                   "Der Menuepunkt \"Weltwunder\" zeigt die" \
                   "aktuelle Baustelle: das Bauwerk waechst von" \
                   "unten Zeile fuer Zeile und steht bei 100" \
                   "Prozent fertig da - ebenso nach jeder Runde.")
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
            # moved to a page of its own (page 6 below). It is the part
            # that is about the modes' scoring rather than about how
            # they are played, and with four modes it had grown past a
            # closing paragraph anyway.
            fmt_duration $(( SPRINT_TIME_MS / 1000 ))
            HELP_BODY=("Spielmodi (Menuepunkt \"Einzelspieler\"):" \
                  "" \
                  "Marathon - die endlose Runde. Sie endet," \
                  "  wenn kein neuer Stein mehr Platz hat." \
                  "")
            printf -v line 'Ultra - %s Rows so schnell wie moeglich.' \
                "${ULTRA_TARGET_ROWS}"
            HELP_BODY+=("${line}")
            HELP_BODY+=("  Ergebnis ist die Spielzeit; die Runde" \
                   "  endet, sobald das Ziel erreicht ist." \
                   "")
            printf -v line 'Sprint - in %s Minuten so viele Rows' \
                "${FMT_DURATION}"
            HELP_BODY+=("${line}")
            HELP_BODY+=("  wie moeglich. Ergebnis sind die Rows;" \
                   "  die Runde endet mit Ablauf der Zeit." \
                   "")
            fmt_duration $(( TIME_ATTACK_START_MS / 1000 ))
            printf -v line 'Time Attack - %s Minuten Restzeit, die' \
                "${FMT_DURATION}"
            HELP_BODY+=("${line}")
            printf -v line '  rueckwaerts laeuft; jede Row bringt %s Sek.' \
                "$(( TIME_ATTACK_ROW_MS / 1000 ))"
            HELP_BODY+=("${line}")
            HELP_BODY+=("  dazu. Ergebnis sind die Rows; die Runde" \
                   "  endet bei 00:00 - oder frueher im Game Over.")
            ;;
        6)
            # Split off page 5 in 0.17.0 (see there): how the modes are
            # scored, in one place. The rule differs by mode, and the
            # Time Attack exception in particular needs its reason
            # spelled out - otherwise it reads like an oversight next to
            # the other two timed modes.
            HELP_BODY=("Bestenlisten (Menuepunkt \"Highscores\"):" \
                  "" \
                  "Jeder Modus hat eine eigene Liste. Marathon," \
                  "Sprint und Time Attack ranken nach Rows," \
                  "Ultra nach der kuerzesten Zeit." \
                  "" \
                  "Bei Ultra und Sprint zaehlt nur ein Lauf, der" \
                  "sein Ziel bzw. die volle Zeit erreicht hat -" \
                  "ein Game Over davor wird nicht gewertet." \
                  "" \
                  "Bei Time Attack zaehlt dagegen jeder Lauf: die" \
                  "Rows sind so oder so dieselbe Leistung, und" \
                  "wer vorzeitig oben rausbaut, hat schlicht" \
                  "weniger davon." \
                  "" \
                  "Reihen und Zaehler einer abgebrochenen Runde" \
                  "fliessen immer in Weltwunder und Statistik" \
                  "ein.")
            ;;
    esac
    return 0
}

# menu_help
# The "Anleitung" main menu entry (added 0.12.0, user request): a short
# tour through the game on six info screens - what the game is about,
# the controls, hold and preview, the gold/silver squares, the wonder
# construction and the game modes (menu_help_body builds each page's
# content). Three things are read from the live state
# instead of being spelled out: the control page prints the current
# bindings (menu_help_keys), the wonder page lists the names and costs
# from lib/wonders.sh, and the modes page names the Ultra row target and
# the Sprint time limit - a rebind, a retuned
# WONDER_COSTS or a retuned goal must never leave the manual lying.
# Text is German like
# the rest of the menus and ASCII only (script conventions); every line
# stays within the 46 characters the 48-column minimum leaves next to
# the two-column menu indent, and every page within MENU_BODY_MAX lines.
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
            lines=("  Anleitung ($(( page + 1 ))/${MENU_HELP_PAGES})" "")
            for l in "${HELP_BODY[@]}"; do
                lines+=("  ${l}")
            done
            lines+=("" "  Pfeil li/re: Seite   Enter/ESC: zurueck")
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
            lines+=("" "  Pfeile/w/s: waehlen   Enter: OK   ESC: abbrechen")
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
    while :; do
        menu_run "Pause" \
            "Fortsetzen" \
            "Neustarten" \
            "Ins Hauptmenue (Runde pausiert)" \
            "Runde beenden"
        case "${MENU_CHOICE}" in
            1)
                # The counters come from the round state in rowhammer.sh;
                # showing them is what makes the question answerable - a
                # round worth keeping is recognized by them, not by the
                # board, which the confirmation covers up.
                if menu_confirm "Wirklich neu starten?" \
                    "Ja, neu starten" "Nein, zurueck" \
                    "Die laufende Runde wird aufgegeben:" \
                    "${CLEARED_TOTAL} Lines, ${ROW_CREDIT} Rows, Level ${LEVEL}." \
                    "" \
                    "Sie wird gewertet (Weltwunder und Statistik)" \
                    "und danach im selben Modus neu gestartet."; then
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
                if menu_confirm "Runde wirklich beenden?" \
                    "Ja, beenden" "Nein, zurueck" \
                    "Die laufende Runde wird beendet:" \
                    "${CLEARED_TOTAL} Lines, ${ROW_CREDIT} Rows, Level ${LEVEL}." \
                    "" \
                    "Sie wird gewertet und ist danach nicht mehr" \
                    "fortsetzbar."; then
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

# menu_singleplayer: the game modes. "Marathon" is the endless
# round, "Ultra" the race for ULTRA_TARGET_ROWS rows against the clock
# (0.14.0, user request), "Sprint" its mirror image - as many rows as
# possible within SPRINT_TIME_MS (0.16.0, user request) - and
# "Time Attack" the countdown a run extends by TIME_ATTACK_ROW_MS per
# row of credit (0.17.0, user request). The chosen entry
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
    local choice sprint_label
    while :; do
        entries=()
        if [ "${GAME_SUSPENDED}" -eq 1 ]; then
            entries+=("Fortsetzen")
        fi
        # The three timed modes name their target in the entry, so the
        # difference between them is readable without the manual. All
        # read the live constants (fmt_duration for the two time
        # limits), which keeps the menu honest if any is retuned.
        fmt_duration $(( SPRINT_TIME_MS / 1000 ))
        sprint_label="${FMT_DURATION}"
        fmt_duration $(( TIME_ATTACK_START_MS / 1000 ))
        entries+=("Marathon" \
                  "Ultra (${ULTRA_TARGET_ROWS} Rows auf Zeit)" \
                  "Sprint (${sprint_label} Minuten auf Rows)" \
                  "Time Attack (${FMT_DURATION} + $(( TIME_ATTACK_ROW_MS / 1000 ))s je Row)" \
                  "Zurueck")
        menu_run "Einzelspieler" "${entries[@]}"
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
    local sprint_label
    while :; do
        fmt_duration $(( SPRINT_TIME_MS / 1000 ))
        sprint_label="${FMT_DURATION}"
        fmt_duration $(( TIME_ATTACK_START_MS / 1000 ))
        menu_run "Highscores" \
            "Marathon" \
            "Ultra (${ULTRA_TARGET_ROWS} Rows auf Zeit)" \
            "Sprint (${sprint_label} Minuten auf Rows)" \
            "Time Attack (${FMT_DURATION} + $(( TIME_ATTACK_ROW_MS / 1000 ))s je Row)" \
            "Zurueck"
        case "${MENU_CHOICE}" in
            0) highscore_screen ;;
            1) highscore_ultra_screen ;;
            2) highscore_sprint_screen ;;
            3) highscore_timeattack_screen ;;
            *) return 0 ;;
        esac
    done
}

# menu_settings: key bindings and player name; every change is written
# to the user config file immediately.
menu_settings() {
    while :; do
        menu_run "Einstellungen" \
            "Tasten konfigurieren" \
            "Farbschema (aktuell: ${COLOR_THEME_LABEL[${COLOR_THEME}]})" \
            "Spielername aendern (aktuell: ${PLAYER_NAME})" \
            "Zurueck"
        case "${MENU_CHOICE}" in
            0) menu_keys ;;
            1) menu_colors ;;
            2) prompt_player_name ;;
            *) return 0 ;;
        esac
    done
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
            lines=("  Farbschema waehlen" "")
            for (( i = 0; i < n; i++ )); do
                if [ "${COLOR_THEMES[i]}" = "${COLOR_THEME}" ]; then
                    mark="*"
                else
                    mark=" "
                fi
                printf -v label '%s %-11s' "${mark}" \
                    "${COLOR_THEME_LABEL[${COLOR_THEMES[i]}]}"
                render_theme_swatch "${COLOR_THEMES[i]}"
                if (( i == sel )); then
                    lines+=($'  \e[7m '"${label}"$' \e[0m  '"${RENDER_SWATCH}")
                else
                    lines+=("   ${label}  ${RENDER_SWATCH}")
                fi
            done
            lines+=("" "  Pfeile/w/s: waehlen   Enter: OK   ESC: zurueck")
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
            entries+=("$(printf '%-18s [%s]' "${KEY_LABELS[i]}" "${!ref}")")
        done
        entries+=("Zurueck")
        menu_run "Tasten konfigurieren" "${entries[@]}"
        if [ "${MENU_CHOICE}" -ge 0 ] && [ "${MENU_CHOICE}" -lt "${#KEY_ACTIONS[@]}" ]; then
            prompt_rebind "${KEY_ACTIONS[MENU_CHOICE]}" "${KEY_LABELS[MENU_CHOICE]}"
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
    local var="${1}" label="${2}" other
    local -a lines
    lines=("  Tasten konfigurieren" ""
           "  Neue Taste fuer \"${label}\" druecken"
           "  (aktuell: ${!var}, ESC = abbrechen)")
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
            menu_message "Tasten konfigurieren" \
                "Diese Taste ist fuer die Menuesteuerung reserviert."
            return 0
            ;;
        r)
            menu_message "Tasten konfigurieren" \
                "Die Taste 'r' ist fuer den Neustart im Game-Over-Bild reserviert."
            return 0
            ;;
    esac
    local re='^([a-z0-9]|SPACE)$'
    if ! [[ "${KEY}" =~ ${re} ]]; then
        menu_message "Tasten konfigurieren" \
            "Ungueltige Taste. Erlaubt sind a-z, 0-9 und die Leertaste."
        return 0
    fi
    for other in "${KEY_ACTIONS[@]}"; do
        if [ "${other}" != "${var}" ] && [ "${!other}" = "${KEY}" ]; then
            menu_message "Tasten konfigurieren" \
                "Die Taste [${KEY}] ist bereits belegt."
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
            lines+=("  Tippen ersetzt den markierten Text.")
            lines+=("  Enter: OK   ESC: unveraendert")
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
    body=("Aktueller Name: ${PLAYER_NAME}" ""
          "Erlaubt sind max. ${MENU_INPUT_MAX} Zeichen aus"
          "A-Z a-z 0-9 Leerzeichen _ -")
    if ! menu_text_input "Spielername" "${PLAYER_NAME}" "${body[@]}"; then
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
    local mode_label
    case "${GAME_MODE}" in
        ultra)      mode_label="Ultra" ;;
        sprint)     mode_label="Sprint" ;;
        timeattack) mode_label="Time Attack" ;;
        *)          mode_label="Marathon" ;;
    esac
    fmt_duration "$(( PLAY_MS / 1000 ))"
    body=("Modus: ${mode_label}"
          "Rows: ${ROW_CREDIT}   Lines: ${CLEARED_TOTAL}"
          "Level: ${LEVEL}   Zeit: ${FMT_DURATION}" ""
          "Name fuer die Bestenliste:")
    ROUND_NAME="${PLAYER_NAME}"
    if menu_text_input "Runde beendet" "${PLAYER_NAME}" "${body[@]}"; then
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
