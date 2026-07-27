#!/usr/bin/env bash
#
# lib/menu.sh
#
# Description:
#   Menu system for rowhammer: a generic list-selection widget plus the
#   application menus (main menu, singleplayer, multiplayer placeholder,
#   settings with key bindings, color theme and player name). Menu labels are German
#   on purpose (requested UI language); code and comments stay English
#   per the script conventions. All screen output goes through
#   screen_write (lib/render.sh) and selections, rebinds and name
#   changes are logged as debug events, so debug sessions capture the
#   menus 1:1 as well. Leaving a game session shows the wonder
#   construction site (lib/wonders.sh) with the round's credit banked.
#   The pause menu (menu_pause, issue #12) opens on the quit key during
#   a round and offers to resume, to suspend the round into the main
#   menu (resumable via the "Fortsetzen" entry shown in the main menu
#   and in the singleplayer menu) or to end the round. menu_confirm
#   (since 0.8.0) asks a yes/no question with the declining option
#   preselected; it guards leaving the game while a round is still
#   suspended. All wait loops
#   repaint on REDRAW_PENDING so a terminal resize (handled in read_key)
#   does not leave a menu or info screen blank (since 0.7.0).
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.9.0  (2026-07-27)

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
# CHANGE 2026-07-26: every screen here starts with \e[H\e[K instead of
# plain \e[H, because homing and then moving down with \n leaves the
# first screen line untouched - it kept showing the top line of whatever
# was drawn before (with the centered play screen that is the hold/next
# header row, which looked like a rendering glitch).
menu_run() {
    local title="${1}"
    shift
    local -a entries=("$@")
    local n="${#entries[@]}" sel=0 dirty=1 frame i
    while :; do
        if [ "${dirty}" -eq 1 ]; then
            frame=$'\e[H\e[K\n'"  ${title}"$'\e[K\n\e[K\n'
            for (( i = 0; i < n; i++ )); do
                if (( i == sel )); then
                    frame+=$'  \e[7m '"${entries[i]}"$' \e[0m\e[K\n'
                else
                    frame+="   ${entries[i]} "$'\e[K\n'
                fi
            done
            frame+=$'\e[K\n'"  Pfeile/w/s: waehlen   Enter: OK   ESC: zurueck"$'\e[K\n\e[J'
            screen_write "${frame}"
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
    local frame line
    frame=$'\e[H\e[K\n'"  ${title}"$'\e[K\n\e[K\n'
    for line in "$@"; do
        frame+="  ${line}"$'\e[K\n'
    done
    frame+=$'\e[K\n'"  Beliebige Taste druecken..."$'\e[K\n\e[J'
    screen_write "${frame}"
    KEY=""
    while [ -z "${KEY}" ]; do
        read_key
        # Repaint after a resize (read_key cleared the screen); the frame
        # is still in scope, so re-emitting it restores the message.
        if [ "${REDRAW_PENDING}" -eq 1 ]; then
            REDRAW_PENDING=0
            screen_write "${frame}"
        fi
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
    local sel=0 dirty=1 frame line
    while :; do
        if [ "${dirty}" -eq 1 ]; then
            frame=$'\e[H\e[K\n'"  ${title}"$'\e[K\n\e[K\n'
            for line in "${body[@]}"; do
                frame+="  ${line}"$'\e[K\n'
            done
            frame+=$'\e[K\n'
            if [ "${sel}" -eq 0 ]; then
                frame+=$'  \e[7m '"${no_label}"$' \e[0m\e[K\n'
                frame+="   ${yes_label} "$'\e[K\n'
            else
                frame+="   ${no_label} "$'\e[K\n'
                frame+=$'  \e[7m '"${yes_label}"$' \e[0m\e[K\n'
            fi
            frame+=$'\e[K\n'"  Pfeile/w/s: waehlen   Enter: OK   ESC: abbrechen"$'\e[K\n\e[J'
            screen_write "${frame}"
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
# chooses to resume, to suspend the round and go to the main menu
# (where it stays resumable via the "Fortsetzen" entry, offered in the
# main menu and in the singleplayer menu) or to end the
# round for good; ESC/back counts as resume. Only sets GAME_EXIT and
# GAME_SUSPENDED - recording the round stays with game_run, so the
# books close only when the round really ends.
menu_pause() {
    menu_run "Pause" \
        "Fortsetzen" \
        "Ins Hauptmenue (Runde pausiert)" \
        "Runde beenden"
    case "${MENU_CHOICE}" in
        1)
            GAME_SUSPENDED=1
            GAME_EXIT=1
            ;;
        2)
            GAME_EXIT=1
            ;;
        *)
            # "Fortsetzen" or ESC: straight back into the round.
            :
            ;;
    esac
    return 0
}

# menu_singleplayer: for now only the normal game; more modes (for
# example a sprint mode) can be added as further entries later. After a
# game session the wonder construction site is shown with the freshly
# banked row total (the round credit was banked by record_round).
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
            entries+=("Fortsetzen")
        fi
        entries+=("Normales Spiel" "Zurueck")
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
        if [ "${choice}" -eq 0 ]; then
            game_run
            if [ "${GAME_SUSPENDED}" -eq 1 ]; then
                return 0
            fi
            wonder_screen "${TOTAL_ROW_CREDIT}"
        else
            return 0
        fi
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
# CHANGE 2026-07-27 (merge): start the frame with \e[H\e[K like every
# other screen in this file, and repaint on REDRAW_PENDING - this loop
# had neither, so a stale top line or a resize could leave the picker
# blank, unlike every sibling menu here.
menu_colors() {
    local n sel=0 i dirty=1 frame mark label
    n="${#COLOR_THEMES[@]}"
    for (( i = 0; i < n; i++ )); do
        if [ "${COLOR_THEMES[i]}" = "${COLOR_THEME}" ]; then
            sel="${i}"
        fi
    done
    while :; do
        if [ "${dirty}" -eq 1 ]; then
            frame=$'\e[H\e[K\n'"  Farbschema waehlen"$'\e[K\n\e[K\n'
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
                    frame+=$'  \e[7m '"${label}"$' \e[0m  '"${RENDER_SWATCH}"$'\e[K\n'
                else
                    frame+="   ${label}  ${RENDER_SWATCH}"$'\e[K\n'
                fi
            done
            frame+=$'\e[K\n'"  Pfeile/w/s: waehlen   Enter: OK   ESC: zurueck"$'\e[K\n\e[J'
            screen_write "${frame}"
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
    local var="${1}" label="${2}" other frame
    printf -v frame '\e[H\e[K\n  Tasten konfigurieren\e[K\n\e[K\n  Neue Taste fuer "%s" druecken\e[K\n  (aktuell: %s, ESC = abbrechen)\e[K\n\e[J' \
        "${label}" "${!var}"
    screen_write "${frame}"
    KEY=""
    while [ -z "${KEY}" ]; do
        read_key
        # Repaint the prompt after a resize (read_key cleared the screen).
        if [ "${REDRAW_PENDING}" -eq 1 ]; then
            REDRAW_PENDING=0
            screen_write "${frame}"
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
    # The HUD key legend is built once from the bindings, not per frame.
    hud_keys_build
    config_save
    return 0
}

# prompt_player_name
# Line-based name input (canonical mode, so backspace editing works).
# An empty input keeps the current name; valid input is persisted.
prompt_player_name() {
    local frame name=""
    printf -v frame '\e[H\e[K\n  Spielername\e[K\n\e[K\n  Aktueller Name: %s\e[K\n\e[K\n  Neuer Name (leer = unveraendert, max. 16 Zeichen,\e[K\n  erlaubt: A-Z a-z 0-9 Leerzeichen _ -)\e[K\n\e[J\n  > ' \
        "${PLAYER_NAME}"
    screen_write "${frame}"
    # Show the cursor while typing, hide it again afterwards.
    screen_write $'\e[?25h'
    IFS= read -r name || name=""
    screen_write $'\e[?25l'
    if [ -z "${name}" ]; then
        return 0
    fi
    local re='^[A-Za-z0-9_ -]{1,16}$'
    if [[ "${name}" =~ ${re} ]]; then
        PLAYER_NAME="${name}"
        debug_event "player name changed to '${name}'"
        config_save
    else
        menu_message "Spielername" \
            "Ungueltiger Name: ${name}" \
            "Erlaubt sind max. 16 Zeichen aus A-Z a-z 0-9 Leerzeichen _ -"
    fi
    return 0
}
