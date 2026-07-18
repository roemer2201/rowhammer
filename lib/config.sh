#!/usr/bin/env bash
#
# lib/config.sh
#
# Description:
#   User configuration for rowhammer: player name and key bindings.
#   Loading follows the organization-based lookup from the script
#   conventions (system scope /etc, then user scope ${HOME}/.config, the
#   more specific file wins within a scope, user overrides system).
#   Saving from the settings menu writes atomically (temp file + mv) to
#   the user-scope file. Values are written single-quoted and validated
#   after loading, because the file is sourced on startup.
#   Library file: sourced by tetris.sh, not meant to be executed directly.
#
# Version: 0.2.0  (2026-07-18)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/config.sh is a library; source it from tetris.sh\n' >&2
    exit 2
fi

# Name of the configuration file this game understands.
CONFIG_NAME="rowhammer.conf"

# The configurable key binding variables. Shared by the settings menu
# (rebinding), validation and config_save, so new bindings only need to
# be added here, in KEY_LABELS (lib/menu.sh) and in the defaults/env
# blocks of tetris.sh.
KEY_ACTIONS=(KEY_LEFT KEY_RIGHT KEY_ROT_CW KEY_ROT_CCW
             KEY_SOFT KEY_HARD KEY_PAUSE KEY_QUIT KEY_HOLD)

# Resolve ORGANIZATION from /etc/org.conf. Sourced in a subshell with
# errexit disabled there, so a missing file or a faulty line cannot abort
# the game; only ORGANIZATION is extracted. /etc/org.conf is
# root-controlled, so sourcing it is acceptable.
ORGANIZATION=""
if [ -r /etc/org.conf ]; then
    ORGANIZATION="$( set +e; . /etc/org.conf >/dev/null 2>&1; printf '%s' "${ORGANIZATION:-}" )"
fi

# config_load
# Source the first matching config file per scope: system scope (/etc)
# first, then user scope (${HOME}/.config) which overrides it. Config
# values override built-in defaults but are themselves overridden by
# environment variables and CLI arguments (applied later in tetris.sh).
config_load() {
    local -a sys_files=() user_files=()
    [ -n "${ORGANIZATION}" ] && sys_files+=("/etc/${ORGANIZATION}/${CONFIG_NAME}")
    sys_files+=("/etc/orgdefault/${CONFIG_NAME}" "/etc/${CONFIG_NAME}")
    [ -n "${ORGANIZATION}" ] && user_files+=("${HOME}/.config/${ORGANIZATION}/${CONFIG_NAME}")
    user_files+=("${HOME}/.config/orgdefault/${CONFIG_NAME}" "${HOME}/.config/${CONFIG_NAME}")

    local f
    for f in "${sys_files[@]}"; do
        if [ -r "${f}" ]; then
            # shellcheck source=/dev/null
            . "${f}"
            break
        fi
    done
    for f in "${user_files[@]}"; do
        if [ -r "${f}" ]; then
            # shellcheck source=/dev/null
            . "${f}"
            break
        fi
    done
}

# config_resolve_write_path
# Put the file the settings menu should write to into CONFIG_WRITE_PATH:
# the first existing user-scope candidate, so an organization-specific
# file keeps winning on the next load; otherwise the plain user file
# ${HOME}/.config/rowhammer.conf.
config_resolve_write_path() {
    local -a candidates=()
    [ -n "${ORGANIZATION}" ] && candidates+=("${HOME}/.config/${ORGANIZATION}/${CONFIG_NAME}")
    candidates+=("${HOME}/.config/orgdefault/${CONFIG_NAME}")

    CONFIG_WRITE_PATH="${HOME}/.config/${CONFIG_NAME}"
    local f
    for f in "${candidates[@]}"; do
        if [ -e "${f}" ]; then
            CONFIG_WRITE_PATH="${f}"
            return 0
        fi
    done
    return 0
}

# config_save
# Write the current settings atomically: into a temp file in the target
# directory, then mv over the real file, so a crash can never leave a
# half-written config behind. Values are single-quoted; the input
# validation in the settings menu guarantees they contain no quotes.
config_save() {
    local path dir tmp var
    config_resolve_write_path
    path="${CONFIG_WRITE_PATH}"
    dir="$(dirname -- "${path}")"
    mkdir -p -- "${dir}"
    tmp="$(mktemp -- "${dir}/.${CONFIG_NAME}.XXXXXX")"
    {
        printf '# rowhammer user configuration.\n'
        printf '# Written by the in-game settings menu; sourced on startup.\n'
        printf "PLAYER_NAME='%s'\n" "${PLAYER_NAME}"
        for var in "${KEY_ACTIONS[@]}"; do
            printf "%s='%s'\n" "${var}" "${!var}"
        done
    } > "${tmp}"
    mv -f -- "${tmp}" "${path}"
}
