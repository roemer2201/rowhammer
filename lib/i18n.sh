#!/usr/bin/env bash
#
# lib/i18n.sh
#
# Description:
#   Translation layer for rowhammer: every text a player gets to see -
#   menus, info screens, the manual, the HUD labels, the result box, the
#   highscore and statistics tables, the demo list, the reset dialog and
#   the --help output - is looked up here instead of being written into
#   the code. One associative array (I18N) holds the texts of the active
#   language, keyed by a short symbolic name; a language is one file
#   below lib/lang/ that fills that array, so adding a language is
#   adding a file plus its entry in I18N_LANGS below.
#   The language is a config-driven setting like the color theme:
#   precedence default < config file < ROWHAMMER_LANG < --lang, with the
#   default "auto" taking the language from the POSIX locale variables
#   (LC_ALL, LC_MESSAGES, LANG) and falling back to I18N_FALLBACK_LANG
#   when they name none this game speaks.
#   Deliberately not a lookup function but a plain array: some of these
#   texts are read once per frame in the HUD (render_pane_left), and an
#   array expansion costs less there than a function call per label.
#   Values with a %-placeholder are printf format strings and are used
#   with "printf -v" by their caller; values holding several lines are
#   split by i18n_lines, which is how the manual pages keep their text
#   in one readable block per page.
#   Library file: sourced by rowhammer.sh, not meant to be executed directly.
#
# Version: 1.0.0  (2026-08-04)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/i18n.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

# The languages this game speaks, in the order the settings menu offers
# them. One entry here plus one file lib/lang/<code>.sh is a complete
# language; nothing else in the code knows a language code.
I18N_LANGS=(de en)

# What the settings menu and the --help text call each language - in the
# language itself, the way every language picker does it, so it stays
# readable to somebody who ended up in the wrong one. Kept here rather
# than in the language files, because a picker has to show all of them
# while only one file is ever loaded.
declare -A I18N_LANG_LABEL=(
    [de]="Deutsch"
    [en]="English"
)

# Which language "auto" resolves to when the locale names none of the
# above (unset, "C", "POSIX", or a language this game does not speak).
# German, because that is the language this game's menus were written in
# before they were translatable: a session that cannot be matched to a
# locale keeps the wording it always had.
I18N_FALLBACK_LANG="de"

# The resolved language code (never "auto") and the active text table.
# I18N is filled by i18n_init from lib/lang/${I18N_LANG}.sh.
I18N_LANG=""
declare -A I18N=()

# i18n_auto
# Derive a language code from the POSIX locale environment into the
# global I18N_AUTO: the first of LC_ALL, LC_MESSAGES and LANG that is
# set and non-empty decides, and only its language part is looked at
# ("de_DE.UTF-8" -> "de"), because the game has no regional variants.
# An unknown or unset locale yields I18N_FALLBACK_LANG.
I18N_AUTO=""
i18n_auto() {
    local loc lang code
    loc="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
    # Strip the territory and the codeset: de_DE.UTF-8@euro -> de.
    lang="${loc%%.*}"
    lang="${lang%%@*}"
    lang="${lang%%_*}"
    # Lower case, so a "DE_DE" from a hand-set environment still matches.
    lang="${lang,,}"
    I18N_AUTO="${I18N_FALLBACK_LANG}"
    for code in "${I18N_LANGS[@]}"; do
        if [ "${code}" = "${lang}" ]; then
            I18N_AUTO="${code}"
            break
        fi
    done
    return 0
}

# i18n_is_valid CODE
# True for a code the settings accept: one of I18N_LANGS or the special
# "auto". Used to validate the config file, the environment variable and
# the command line, all three of which are user input.
i18n_is_valid() {
    local code
    if [ "${1}" = "auto" ]; then
        return 0
    fi
    for code in "${I18N_LANGS[@]}"; do
        if [ "${code}" = "${1}" ]; then
            return 0
        fi
    done
    return 1
}

# i18n_init
# Resolve LANGUAGE (which may be "auto") into I18N_LANG and load that
# language's texts into I18N. A missing language file is an installation
# defect and therefore fatal with the offending path in the message -
# the same treatment wonder_art_load gives a missing art file, and for
# the same reason: there is nothing sensible left to show.
# Callable again at runtime: the settings menu switches the language by
# assigning LANGUAGE and calling this, and the whole-array assignment in
# the language file replaces the previous table rather than merging with
# it, so no stale text of the old language can survive the switch.
i18n_init() {
    local f
    if [ "${LANGUAGE}" = "auto" ]; then
        i18n_auto
        I18N_LANG="${I18N_AUTO}"
    else
        I18N_LANG="${LANGUAGE}"
    fi
    f="${SCRIPT_DIR}/lib/lang/${I18N_LANG}.sh"
    if [ ! -r "${f}" ]; then
        die "Missing language file: ${f}"
    fi
    # shellcheck source=/dev/null
    . "${f}"
    return 0
}

# i18n_lines KEY
# Split a multi-line text into the global array I18N_LINES, one element
# per line, so a caller can append a whole block to a screen with
# "body+=("${I18N_LINES[@]}")". The manual pages use this: their static
# text stays one readable block per page in the language file instead of
# a numbered key per line, while the pages that mix text with generated
# lines (key bindings, wonder costs) append the blocks around them.
# An unknown or empty key yields an empty array rather than one empty
# line, so a block that a language leaves out simply takes no space.
I18N_LINES=()
i18n_lines() {
    local text="${I18N[${1}]:-}"
    I18N_LINES=()
    if [ -z "${text}" ]; then
        return 0
    fi
    mapfile -t I18N_LINES <<< "${text}"
    return 0
}

# i18n_lang_label CODE
# The name of a language as the settings menu shows it, in the global
# I18N_LABEL: the language's own name, and for "auto" the word for
# "automatic" of the *active* language plus the name of the language it
# currently resolves to - which is the one thing a player picking "auto"
# wants to know.
I18N_LABEL=""
i18n_lang_label() {
    if [ "${1}" = "auto" ]; then
        i18n_auto
        printf -v I18N_LABEL '%s (%s)' "${I18N[lang_auto]}" \
            "${I18N_LANG_LABEL[${I18N_AUTO}]}"
        return 0
    fi
    I18N_LABEL="${I18N_LANG_LABEL[${1}]:-${1}}"
    return 0
}
