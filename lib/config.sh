#!/usr/bin/env bash
#
# lib/config.sh
#
# Description:
#   User configuration for rowhammer: player name and key bindings.
#   The config file lives at ${DATA_DIR}/rowhammer.conf (default
#   ~/rowhammer/rowhammer.conf), the shared game data directory that
#   also holds the highscore list (lib/highscore.sh). Saving from the
#   settings menu writes atomically (temp file + mv). Values are written
#   single-quoted and validated after loading, because the file is
#   sourced on startup.
#   The loaded file path is recorded in CONFIG_LOADED_FILES so the
#   debug session header can report it (config_load runs before
#   debug_init); saves are logged as debug events at runtime.
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.4.0  (2026-07-18)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/config.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# Name of the configuration file this game understands.
# CHANGE 2026-07-18: the organization-based lookup (/etc and ~/.config,
# script conventions section 11) was replaced by exactly one file in the
# game data directory. Deliberate user decision: all rowhammer data
# (config, highscore, later the savegame) lives together in ~/rowhammer,
# and the project needs no backward compatibility (see CLAUDE.md).
CONFIG_NAME="rowhammer.conf"

# The configurable key binding variables. Shared by the settings menu
# (rebinding), validation and config_save, so new bindings only need to
# be added here, in KEY_LABELS (lib/menu.sh) and in the defaults/env
# blocks of rowhammer.sh.
KEY_ACTIONS=(KEY_LEFT KEY_RIGHT KEY_ROT_CW KEY_ROT_CCW
             KEY_SOFT KEY_HARD KEY_PAUSE KEY_QUIT KEY_HOLD)

# config_load
# Source the config file from the data directory if it exists. Config
# values override built-in defaults but are themselves overridden by
# environment variables and CLI arguments (applied later in rowhammer.sh).
# The file lives in the user's own home and is written by the settings
# menu, so its origin is trusted and sourcing it is acceptable and cheap.
# The loaded path is kept for the debug session header ("" = built-in
# defaults only).
CONFIG_LOADED_FILES=""

config_load() {
    local f="${DATA_DIR}/${CONFIG_NAME}"
    if [ -r "${f}" ]; then
        # shellcheck source=/dev/null
        . "${f}"
        CONFIG_LOADED_FILES="${f}"
    fi
    return 0
}

# config_save
# Write the current settings atomically: into a temp file in the target
# directory, then mv over the real file, so a crash can never leave a
# half-written config behind. Values are single-quoted; the input
# validation in the settings menu guarantees they contain no quotes.
config_save() {
    local path tmp var
    path="${DATA_DIR}/${CONFIG_NAME}"
    mkdir -p -- "${DATA_DIR}"
    tmp="$(mktemp -- "${DATA_DIR}/.${CONFIG_NAME}.XXXXXX")"
    {
        printf '# rowhammer user configuration.\n'
        printf '# Written by the in-game settings menu; sourced on startup.\n'
        printf "PLAYER_NAME='%s'\n" "${PLAYER_NAME}"
        for var in "${KEY_ACTIONS[@]}"; do
            printf "%s='%s'\n" "${var}" "${!var}"
        done
    } > "${tmp}"
    mv -f -- "${tmp}" "${path}"
    debug_event "config saved: ${path}"
}
