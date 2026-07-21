#!/usr/bin/env bash
#
# lib/save.sh
#
# Description:
#   Persistent savegame for rowhammer: the all-time weighted row credit
#   ("Rows") that drives the wonder construction (lib/wonders.sh). The
#   counter is kept in ${DATA_DIR}/save (default
#   ~/.config/rowhammer/save) as a
#   single "total_rows=N" line plus comment lines. The file is parsed
#   and validated, not sourced: it is one number, and a corrupted file
#   must fall back to zero progress instead of breaking the game.
#   Saving is atomic (temp file + mv). The round credit is banked into
#   the counter exactly once per finished round (record_round in
#   rowhammer.sh calls save_write).
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 0.1.2  (2026-07-20)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/save.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# File name below DATA_DIR and the accepted counter line format. The
# regex caps the digits so arithmetic can never overflow bash integers.
SAVE_FILE_NAME="save"
SAVE_LINE_RE='^total_rows=([0-9]{1,15})$'

# The all-time weighted row credit across every round ever played. Loaded
# on startup, extended by record_round, read by lib/wonders.sh.
TOTAL_ROW_CREDIT=0

# save_load
# Read the savegame into TOTAL_ROW_CREDIT. A missing file means a fresh
# start; a file without a valid counter line (manual edit, corruption)
# falls back to zero and is reported, because losing wonder progress is
# worth a visible note even though the game keeps working.
save_load() {
    TOTAL_ROW_CREDIT=0
    local f="${DATA_DIR}/${SAVE_FILE_NAME}" line found=0
    if [ ! -e "${f}" ]; then
        debug_event "save: no savegame at ${f}, starting at 0 rows"
        return 0
    fi
    if [ ! -r "${f}" ]; then
        printf '%s: savegame is not readable, starting at 0 rows: %s\n' \
            "${SCRIPT_NAME}" "${f}" >&2
        return 0
    fi
    while IFS= read -r line; do
        if [[ "${line}" =~ ${SAVE_LINE_RE} ]]; then
            TOTAL_ROW_CREDIT=$(( 10#${BASH_REMATCH[1]} ))
            found=1
            break
        fi
    done < "${f}"
    if [ "${found}" -eq 0 ]; then
        printf '%s: savegame has no valid total_rows line, starting at 0 rows: %s\n' \
            "${SCRIPT_NAME}" "${f}" >&2
    fi
    debug_event "save: loaded total_rows=${TOTAL_ROW_CREDIT} from ${f}"
    return 0
}

# save_write
# Write TOTAL_ROW_CREDIT atomically: into a temp file in the target
# directory, then mv over the real file, so a crash can never leave a
# half-written savegame behind.
save_write() {
    local f="${DATA_DIR}/${SAVE_FILE_NAME}" tmp
    mkdir -p -- "${DATA_DIR}"
    tmp="$(mktemp -- "${DATA_DIR}/.${SAVE_FILE_NAME}.XXXXXX")"
    {
        printf '# rowhammer savegame: all-time weighted row credit.\n'
        printf '# Written after every finished round; edits are validated on load.\n'
        printf 'total_rows=%d\n' "${TOTAL_ROW_CREDIT}"
    } > "${tmp}"
    mv -f -- "${tmp}" "${f}"
    debug_event "save: wrote total_rows=${TOTAL_ROW_CREDIT} to ${f}"
    return 0
}
