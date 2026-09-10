#!/usr/bin/env bash
#
# lib/datadir.sh
#
# Description:
#   Relocating the rowhammer data directory (CLAUDE.md 4.12). Everything
#   the game persists lives together in one directory (${DATA_DIR},
#   default ~/.config/rowhammer, see CLAUDE.md 4.5); until now that
#   directory could only be changed per invocation with --data-dir, which
#   the /usr/games starter cannot pass. This module makes the choice
#   permanent: the data is moved to the new place and the default path
#   keeps a link file naming it, which every later start reads.
#
#   The link file is the one thing that cannot live in the data directory
#   itself - it is what says where that directory is. It holds a single
#   validated "data_dir=<path>" line and is parsed, not sourced, like the
#   savegame and the statistics (only rowhammer.conf is sourced, and only
#   because the settings menu writes it).
#
#   Flow of a relocation (driven by menu_datadir in lib/menu.sh):
#     1. datadir_path_check   - validate and resolve the typed path
#     2. datadir_target_state - new / empty / foreign / config / blocked
#     3. depending on that: move straight away, refuse with a reason, or
#        let the player pick between keeping the current data, keeping
#        the data already at the target, or overwriting the target
#     4. datadir_backup       - tar.gz of the side that is about to be
#                               overwritten, written into that very
#                               directory
#     5. datadir_move / datadir_wipe, then datadir_link_write
#     6. datadir_reload       - re-read config, highscores, savegame and
#                               statistics from the new place
#
#   The backup is a tar.gz rather than a zip: CLAUDE.md 4.1 allows no hard
#   dependency beyond coreutils, and tar is everywhere while zip is not.
#   Archives already present are excluded from a new one, so backups never
#   nest.
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 1.0.0  (2026-09-09)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/datadir.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# --- Names and patterns ---------------------------------------------------

# The link file, always in DATA_DIR_DEFAULT (~/.config/rowhammer) and
# never in the target: it is the fixed place every start looks at. Its
# name is deliberately free of a suffix, so it cannot be mistaken for one
# of the data files a reset backs up ("<file>-<stamp>.bak", CLAUDE.md 4.8).
DATADIR_LINK_NAME="datadir"
# The single line the file has to carry. Read loosely and handed to
# datadir_path_check afterwards, so the path rules live in exactly one
# place - a hand-edited link file is user input like any other.
DATADIR_LINK_RE='^data_dir=(.*)$'

# What a typed path may consist of before the leading "~" is expanded.
# Spaces are in, because a path may legitimately contain one and every
# use below is quoted; everything that could make a shell or a tar option
# out of the string is out.
DATADIR_INPUT_RE='^[A-Za-z0-9_.+ /~-]+$'

# Backup archive: "backup-YYYYMMDD-HHMMSS.tar.gz" in the directory whose
# content it holds (user request). Built under the temp name first, so
# the archive can never pack itself, and moved into place afterwards.
DATADIR_ARCHIVE_PREFIX="backup-"
DATADIR_ARCHIVE_SUFFIX=".tar.gz"
DATADIR_TMP_NAME=".rowhammer-backup.tmp"
# How often datadir_backup retries when an archive of the current second
# is already there - same reasoning and the same limit as the reset in
# rowhammer.sh: one wait normally frees the name, and a clock that stands
# still must not turn this into a loop.
DATADIR_STAMP_ATTEMPTS=3

# --- Results of the functions below ---------------------------------------
# Plain globals rather than stdout: the callers run inside the menu, where
# a command substitution would cost a subshell per step.
DATADIR_TARGET=""       # resolved absolute path (datadir_path_check)
DATADIR_ERROR=""        # why a check failed, as an i18n key suffix
DATADIR_STATE=""        # new|empty|foreign|config|blocked
DATADIR_COLLISION=""    # entry name that already exists at the target
DATADIR_FAILED=""       # entry (or path) a move/wipe stumbled over
DATADIR_ARCHIVE=""      # path of the archive just written
DATADIR_SHORT=""        # shortened path for the menu (datadir_short)
DATADIR_ENTRIES=()      # what "the content" of a directory is
# Path of the link file read at startup, for the debug session header -
# the counterpart of CONFIG_LOADED_FILES in lib/config.sh.
DATADIR_LINK_LOADED=""

# --- Path handling --------------------------------------------------------

# datadir_path_check INPUT
# Validate a typed (or stored) path and resolve it into DATADIR_TARGET.
# A leading "~" becomes the home directory, duplicate and trailing
# slashes are folded away, and the result has to be absolute and free of
# ".." components: nothing legitimate needs one when a fresh directory is
# named, and a path that walks upwards is exactly what a relocation must
# not do by accident. Returns 1 with DATADIR_ERROR set to the reason.
datadir_path_check() {
    local raw="${1}" path
    DATADIR_TARGET=""
    DATADIR_ERROR=""
    if [ -z "${raw}" ]; then
        DATADIR_ERROR="empty"
        return 1
    fi
    if ! [[ "${raw}" =~ ${DATADIR_INPUT_RE} ]]; then
        DATADIR_ERROR="chars"
        return 1
    fi
    # The tilde is expanded here by hand and deliberately stays literal in
    # the patterns: the string came from a prompt or a file, so the shell
    # never saw it as a word and would not have expanded it anyway.
    # shellcheck disable=SC2088
    case "${raw}" in
        '~')   path="${HOME}" ;;
        '~/'*) path="${HOME}/${raw#\~/}" ;;
        *)     path="${raw}" ;;
    esac
    while [[ "${path}" == *"//"* ]]; do
        path="${path//\/\///}"
    done
    while [ "${#path}" -gt 1 ] && [ "${path}" != "${path%/}" ]; do
        path="${path%/}"
    done
    if [ "${path#/}" = "${path}" ]; then
        DATADIR_ERROR="relative"
        return 1
    fi
    if [ "${path}" = "/" ]; then
        DATADIR_ERROR="root"
        return 1
    fi
    # The path starts with "/", so appending one covers a ".." at the
    # start, in the middle and at the end with a single test.
    case "${path}/" in
        *"/../"*)
            DATADIR_ERROR="dotdot"
            return 1
            ;;
    esac
    DATADIR_TARGET="${path}"
    return 0
}

# datadir_inside PARENT CHILD
# True when CHILD is PARENT itself or lies below it. Used to refuse a
# relocation into the directory being moved (and the other way round) -
# a directory cannot travel into itself, and the entry loop would chase
# its own tail.
datadir_inside() {
    local parent="${1}" child="${2}"
    if [ "${parent}" = "${child}" ]; then
        return 0
    fi
    if [ "${child#"${parent}"/}" != "${child}" ]; then
        return 0
    fi
    return 1
}

# datadir_short PATH WIDTH
# Shorten PATH for a menu line into DATADIR_SHORT: the home directory
# becomes "~", and anything still too long is cut from the left with a
# leading "<" - the tail of a path is the telling half.
datadir_short() {
    local path="${1}" width="${2}"
    DATADIR_SHORT="${path}"
    # The tilde here is a character on the screen, not an expansion: this
    # builds the short form a player reads, and it is never used as a path
    # again.
    # shellcheck disable=SC2088
    if [ -n "${HOME}" ]; then
        if [ "${path}" = "${HOME}" ]; then
            DATADIR_SHORT="~"
        elif [ "${path#"${HOME}"/}" != "${path}" ]; then
            DATADIR_SHORT="~/${path#"${HOME}"/}"
        fi
    fi
    if [ "${#DATADIR_SHORT}" -gt "${width}" ] && [ "${width}" -gt 1 ]; then
        DATADIR_SHORT="<${DATADIR_SHORT: -$(( width - 1 ))}"
    fi
    return 0
}

# --- The content of a data directory --------------------------------------

# datadir_entries DIR
# Fill DATADIR_ENTRIES with every name in DIR - hidden ones included -
# except the link file and any archive already lying there. This is the
# one place that defines what "the content" of a data directory is; the
# move, the backup, the wipe and the emptiness test all read it, so they
# can never disagree about it.
# Deliberately not a list of the known file names (rowhammer.conf, the six
# highscore lists, save, stats, demos/): the ".bak" files a reset leaves
# behind (CLAUDE.md 4.8) and whatever a later version adds belong to the
# player just as much, and a list would quietly leave them behind.
datadir_entries() {
    local dir="${1}" entry name
    local had_dotglob=0 had_nullglob=0
    DATADIR_ENTRIES=()
    if [ ! -d "${dir}" ]; then
        return 0
    fi
    shopt -q dotglob && had_dotglob=1
    shopt -q nullglob && had_nullglob=1
    shopt -s dotglob nullglob
    for entry in "${dir}"/*; do
        name="${entry##*/}"
        case "${name}" in
            "${DATADIR_LINK_NAME}"|"${DATADIR_TMP_NAME}") continue ;;
            # Archives are left where they are: the backup of a previous
            # relocation (and, per the user's request, any zip that ended
            # up here) must not be packed into the next one, and moving
            # it along would carry it away from the directory it
            # describes.
            *.zip|*.tar.gz) continue ;;
        esac
        DATADIR_ENTRIES+=("${name}")
    done
    if [ "${had_dotglob}" -eq 0 ]; then
        shopt -u dotglob
    fi
    if [ "${had_nullglob}" -eq 0 ]; then
        shopt -u nullglob
    fi
    return 0
}

# datadir_target_state DIR
# Classify the chosen target in DATADIR_STATE:
#   new      - does not exist yet, can be created
#   empty    - exists and holds no content of its own
#   config   - holds a rowhammer.conf, so somebody played here before
#   foreign  - not empty, but no config of ours
#   blocked  - exists as a non-directory, or cannot be written to
# The config file is what the question in menu_datadir hangs on (user
# request): it is the one entry that says "these are somebody's game
# data" rather than "some files happen to sit here".
datadir_target_state() {
    local dir="${1}"
    DATADIR_STATE=""
    if [ -e "${dir}" ] && [ ! -d "${dir}" ]; then
        DATADIR_STATE="blocked"
        return 0
    fi
    if [ ! -d "${dir}" ]; then
        DATADIR_STATE="new"
        return 0
    fi
    if [ ! -w "${dir}" ] || [ ! -x "${dir}" ]; then
        DATADIR_STATE="blocked"
        return 0
    fi
    if [ -e "${dir}/${CONFIG_NAME}" ]; then
        DATADIR_STATE="config"
        return 0
    fi
    datadir_entries "${dir}"
    if [ "${#DATADIR_ENTRIES[@]}" -eq 0 ]; then
        DATADIR_STATE="empty"
    else
        DATADIR_STATE="foreign"
    fi
    return 0
}

# datadir_collision SRC DST
# Report the first entry of SRC that already exists in DST in
# DATADIR_COLLISION (returns 1 then). A move must never silently
# overwrite something, so a target that is not ours and not empty is only
# accepted when nothing bumps into anything.
datadir_collision() {
    local src="${1}" dst="${2}" name
    local -a names=()
    DATADIR_COLLISION=""
    if [ ! -d "${dst}" ]; then
        return 0
    fi
    datadir_entries "${src}"
    # Copied out: the checks below call datadir_entries again for DST.
    if [ "${#DATADIR_ENTRIES[@]}" -gt 0 ]; then
        names=("${DATADIR_ENTRIES[@]}")
    fi
    for name in "${names[@]+"${names[@]}"}"; do
        if [ -e "${dst}/${name}" ]; then
            DATADIR_COLLISION="${name}"
            return 1
        fi
    done
    return 0
}

# --- Backup, move, wipe ---------------------------------------------------
# STDERR of the commands below goes to /dev/null and the diagnosis into
# the debug log instead. That is the rule this game follows wherever it
# owns the terminal (CLAUDE.md 4.10): a message from tar or mv would be
# written into the middle of the centered menu block, and in the default
# render mode it would stay there, because unchanged lines are not
# rewritten.

# datadir_backup DIR
# Write DIR's content to DIR/backup-YYYYMMDD-HHMMSS.tar.gz and report the
# path in DATADIR_ARCHIVE. Built under DATADIR_TMP_NAME in that same
# directory and moved into place afterwards, so a failed run leaves no
# half-written file under a name that looks finished, and the move is a
# rename on one filesystem rather than a copy.
#
# What goes in are the entries datadir_entries names - the same list the
# move and the wipe work on, so the archive holds exactly what is about
# to be given up, and an archive already lying there stays out of the new
# one (user request). Deliberately not "tar -C dir ." with --exclude
# patterns: that packs the directory itself as a member, and writing the
# temp file into it while tar reads it makes tar stop with "file changed
# as we read it". Naming the members leaves the directory unread.
# A directory with no content writes no archive at all (DATADIR_ARCHIVE
# stays empty): there is nothing to save, and tar refuses to create an
# empty archive anyway.
datadir_backup() {
    local dir="${1}" stamp="" try attempt archive tmp
    local -a names=()
    DATADIR_ARCHIVE=""
    DATADIR_FAILED=""
    if [ ! -d "${dir}" ] || [ ! -w "${dir}" ]; then
        DATADIR_FAILED="${dir}"
        return 1
    fi
    datadir_entries "${dir}"
    if [ "${#DATADIR_ENTRIES[@]}" -eq 0 ]; then
        debug_event "datadir: nothing to back up in ${dir}"
        return 0
    fi
    names=("${DATADIR_ENTRIES[@]}")
    for (( attempt = 1; attempt <= DATADIR_STAMP_ATTEMPTS; attempt++ )); do
        try="$(date +%Y%m%d-%H%M%S)"
        if [ ! -e "${dir}/${DATADIR_ARCHIVE_PREFIX}${try}${DATADIR_ARCHIVE_SUFFIX}" ]; then
            stamp="${try}"
            break
        fi
        # Same second, same name: an archive of this very second is
        # already there. Waiting for the next one frees the name instead
        # of overwriting a backup - which is the one thing a backup must
        # never do.
        sleep 1
    done
    if [ -z "${stamp}" ]; then
        DATADIR_FAILED="${dir}"
        return 1
    fi
    archive="${dir}/${DATADIR_ARCHIVE_PREFIX}${stamp}${DATADIR_ARCHIVE_SUFFIX}"
    tmp="${dir}/${DATADIR_TMP_NAME}"
    rm -f -- "${tmp}" 2>/dev/null || :
    if ! tar -czf "${tmp}" -C "${dir}" -- "${names[@]}" 2>/dev/null; then
        rm -f -- "${tmp}" 2>/dev/null || :
        DATADIR_FAILED="${archive}"
        debug_event "datadir: backup failed for ${dir}"
        return 1
    fi
    if ! mv -- "${tmp}" "${archive}" 2>/dev/null; then
        rm -f -- "${tmp}" 2>/dev/null || :
        DATADIR_FAILED="${archive}"
        debug_event "datadir: could not place backup ${archive}"
        return 1
    fi
    DATADIR_ARCHIVE="${archive}"
    debug_event "datadir: backup written ${archive}"
    return 0
}

# datadir_wipe DIR
# Remove DIR's content (datadir_entries, so archives and the link file
# stay). Used by the two answers that give up one side of a relocation -
# always after datadir_backup, never on its own.
datadir_wipe() {
    local dir="${1}" name
    local -a names=()
    DATADIR_FAILED=""
    datadir_entries "${dir}"
    if [ "${#DATADIR_ENTRIES[@]}" -eq 0 ]; then
        return 0
    fi
    names=("${DATADIR_ENTRIES[@]}")
    for name in "${names[@]}"; do
        # Both halves are checked before an "rm -rf" is built from them.
        # Neither can be empty as things stand (the names come from a
        # glob, the directory from a validated path), and that is exactly
        # why the guard costs nothing - while an empty one would turn
        # this line into a recursive delete of "/".
        if [ -z "${dir}" ] || [ -z "${name}" ]; then
            DATADIR_FAILED="${dir}/${name}"
            return 1
        fi
        # shellcheck disable=SC2115  # the emptiness guard above is the check
        if ! rm -rf -- "${dir}/${name}" 2>/dev/null; then
            DATADIR_FAILED="${name}"
            debug_event "datadir: could not remove ${dir}/${name}"
            return 1
        fi
    done
    debug_event "datadir: wiped ${#names[@]} entries in ${dir}"
    return 0
}

# datadir_move SRC DST
# Move SRC's content into DST, creating DST if needed. Entry by entry
# rather than renaming the directory itself: the three answers of
# menu_datadir all end here, and only this form works when DST already
# exists.
# A failure halfway through stops and names the entry (DATADIR_FAILED)
# instead of rolling back: an undo would have to move files back into a
# directory that just refused to give them up, which is the more
# dangerous of the two.
datadir_move() {
    local src="${1}" dst="${2}" name
    local -a names=()
    DATADIR_FAILED=""
    if ! mkdir -p -- "${dst}" 2>/dev/null; then
        DATADIR_FAILED="${dst}"
        debug_event "datadir: could not create ${dst}"
        return 1
    fi
    if [ ! -w "${dst}" ] || [ ! -x "${dst}" ]; then
        DATADIR_FAILED="${dst}"
        return 1
    fi
    datadir_entries "${src}"
    if [ "${#DATADIR_ENTRIES[@]}" -eq 0 ]; then
        debug_event "datadir: nothing to move from ${src}"
        return 0
    fi
    names=("${DATADIR_ENTRIES[@]}")
    for name in "${names[@]}"; do
        if ! mv -- "${src}/${name}" "${dst}/${name}" 2>/dev/null; then
            DATADIR_FAILED="${name}"
            debug_event "datadir: move failed at ${name} (${src} -> ${dst})"
            return 1
        fi
    done
    debug_event "datadir: moved ${#names[@]} entries ${src} -> ${dst}"
    return 0
}

# --- The link file --------------------------------------------------------

# datadir_link_file
# Path of the link file. A function, not a constant: DATA_DIR_DEFAULT is
# built from HOME, and the modules are sourced before the argument
# parsing has had its say.
datadir_link_file() {
    printf '%s/%s' "${DATA_DIR_DEFAULT}" "${DATADIR_LINK_NAME}"
    return 0
}

# datadir_link_load
# Point DATA_DIR at the stored location. Called once at startup and only
# when neither --data-dir nor ROWHAMMER_DATA_DIR had something to say -
# precedence default < link file < env < CLI.
# A missing file is the normal case (nothing was ever relocated). A file
# that is unreadable or holds no valid path falls back to the default
# with a note on STDERR: this runs before the alternate screen, and a
# player whose link file broke should learn why the highscores look empty
# rather than be locked out of the game.
datadir_link_load() {
    local f line target=""
    f="$(datadir_link_file)"
    DATADIR_LINK_LOADED=""
    if [ ! -e "${f}" ]; then
        return 0
    fi
    if [ ! -r "${f}" ]; then
        printf '%s: data directory link is not readable, using %s: %s\n' \
            "${SCRIPT_NAME}" "${DATA_DIR_DEFAULT}" "${f}" >&2
        return 0
    fi
    while IFS= read -r line; do
        if [[ "${line}" =~ ${DATADIR_LINK_RE} ]]; then
            target="${BASH_REMATCH[1]}"
            break
        fi
    done < "${f}"
    if [ -z "${target}" ]; then
        printf '%s: data directory link has no valid data_dir line, using %s: %s\n' \
            "${SCRIPT_NAME}" "${DATA_DIR_DEFAULT}" "${f}" >&2
        return 0
    fi
    # Validated with the same rules as a typed path: a hand-edited link
    # file is user input, and the value goes into every later file path.
    if ! datadir_path_check "${target}"; then
        printf '%s: data directory link names an invalid path (%s), using %s: %s\n' \
            "${SCRIPT_NAME}" "${DATADIR_ERROR}" "${DATA_DIR_DEFAULT}" "${f}" >&2
        return 0
    fi
    DATA_DIR="${DATADIR_TARGET}"
    DATADIR_LINK_LOADED="${f}"
    return 0
}

# datadir_link_probe
# Make sure the link file could be written before anything irreversible
# happens. The relocation ends in datadir_link_write, and a failure there
# would leave the data in its new place while every later start looks in
# the old one - so the question is asked first, while nothing has moved
# yet and an answer of "no" costs nothing.
datadir_link_probe() {
    local f
    f="$(datadir_link_file)"
    DATADIR_FAILED="${f}"
    if ! mkdir -p -- "${DATA_DIR_DEFAULT}" 2>/dev/null; then
        return 1
    fi
    if [ ! -w "${DATA_DIR_DEFAULT}" ] || [ ! -x "${DATA_DIR_DEFAULT}" ]; then
        return 1
    fi
    if [ -e "${f}" ] && [ ! -w "${f}" ]; then
        return 1
    fi
    DATADIR_FAILED=""
    return 0
}

# datadir_link_write PATH
# Record PATH as the data directory, atomically (temp file + mv) like
# every other file this game writes. Pointing back at the default path
# removes the link file instead of writing one: the default needs no
# note, and a link file saying "the data is where it always was" would
# only be one more thing that can rot.
datadir_link_write() {
    local path="${1}" f tmp
    f="$(datadir_link_file)"
    if [ "${path}" = "${DATA_DIR_DEFAULT}" ]; then
        datadir_link_remove
        return "${?}"
    fi
    if ! mkdir -p -- "${DATA_DIR_DEFAULT}" 2>/dev/null; then
        DATADIR_FAILED="${DATA_DIR_DEFAULT}"
        return 1
    fi
    if ! tmp="$(mktemp -- "${DATA_DIR_DEFAULT}/.${DATADIR_LINK_NAME}.XXXXXX" 2>/dev/null)"; then
        DATADIR_FAILED="${f}"
        return 1
    fi
    {
        printf '# rowhammer data directory link.\n'
        printf '# Written by the settings menu; parsed, not sourced.\n'
        printf 'data_dir=%s\n' "${path}"
    } > "${tmp}" 2>/dev/null || {
        rm -f -- "${tmp}" 2>/dev/null || :
        DATADIR_FAILED="${f}"
        return 1
    }
    if ! mv -f -- "${tmp}" "${f}" 2>/dev/null; then
        rm -f -- "${tmp}" 2>/dev/null || :
        DATADIR_FAILED="${f}"
        return 1
    fi
    debug_event "datadir: link written ${f} -> ${path}"
    return 0
}

# datadir_link_remove
# Drop the link file, back to the built-in default.
datadir_link_remove() {
    local f
    f="$(datadir_link_file)"
    if [ ! -e "${f}" ]; then
        return 0
    fi
    if ! rm -f -- "${f}" 2>/dev/null; then
        DATADIR_FAILED="${f}"
        return 1
    fi
    debug_event "datadir: link removed ${f}"
    return 0
}

# --- Taking the new directory into use ------------------------------------

# datadir_reload
# Re-read everything persistent from the (new) DATA_DIR: the config file,
# the six highscore lists, the savegame with the wonder state and the
# statistics. Needed because the "use what is already there" answer takes
# over a foreign rowhammer.conf, which may name another language, color
# theme, player name or key binding than the running session has.
#
# The values from that file are validated leniently here, unlike at
# startup: an invalid entry keeps the value the session already had and
# says so in the debug log. Startup can afford to die on a broken config
# (nothing is lost yet); a running session cannot, and a relocation must
# not be the thing that ends it.
datadir_reload() {
    local prev_name="${PLAYER_NAME}" prev_lang="${LANGUAGE}"
    local prev_theme="${COLOR_THEME}" prev_demo="${DEMO_RECORD}"
    local -a prev_keys=()
    local var i theme ok
    local name_re='^[A-Za-z0-9_ -]{1,16}$'
    local key_re='^([a-z0-9]|SPACE|NONE)$'

    for var in "${KEY_ACTIONS[@]}"; do
        prev_keys+=("${!var}")
    done

    # The Marathon list may still sit under its pre-0.51.0 name in a
    # directory somebody relocated from an older installation, so the
    # rename runs here for the same reason it runs at startup.
    highscore_migrate_legacy
    config_load

    if ! [[ "${PLAYER_NAME}" =~ ${name_re} ]]; then
        debug_event "datadir: config has an invalid player name, keeping '${prev_name}'"
        PLAYER_NAME="${prev_name}"
    fi
    if ! i18n_is_valid "${LANGUAGE}"; then
        debug_event "datadir: config has an invalid language, keeping '${prev_lang}'"
        LANGUAGE="${prev_lang}"
    fi
    ok=0
    for theme in "${COLOR_THEMES[@]}"; do
        if [ "${theme}" = "${COLOR_THEME}" ]; then
            ok=1
            break
        fi
    done
    if [ "${ok}" -eq 0 ]; then
        debug_event "datadir: config has an invalid color theme, keeping '${prev_theme}'"
        COLOR_THEME="${prev_theme}"
    fi
    case "${DEMO_RECORD}" in
        on|off) : ;;
        *)
            debug_event "datadir: config has an invalid demo setting, keeping '${prev_demo}'"
            DEMO_RECORD="${prev_demo}"
            ;;
    esac
    # Only the character set is checked, not the duplicate rule: a
    # binding taken twice makes one action unreachable, which is the
    # player's own doing and repairable in the settings menu, while
    # refusing the whole file over it would throw away the other eight.
    for i in "${!KEY_ACTIONS[@]}"; do
        var="${KEY_ACTIONS[i]}"
        if ! [[ "${!var}" =~ ${key_re} ]]; then
            debug_event "datadir: config has an invalid ${var}, keeping '${prev_keys[i]}'"
            printf -v "${var}" '%s' "${prev_keys[i]}"
        fi
    done

    i18n_init
    render_colors_init
    highscore_load
    highscore_ultra_load
    highscore_sprint_load
    highscore_timeattack_load
    highscore_flood_load
    highscore_versus_load
    save_load
    wonders_update "${TOTAL_ROW_CREDIT}"
    stats_load
    # Language and theme may have changed with the config, and both sit
    # in the frame cache of the diff renderer (CLAUDE.md 4.3).
    RENDER_FULL=1
    debug_event "datadir: reloaded persistent state from ${DATA_DIR}"
    return 0
}
