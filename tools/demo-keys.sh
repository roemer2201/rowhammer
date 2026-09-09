#!/usr/bin/env bash
#
# tools/demo-keys.sh
#
# Description:
#   Regression test for the key bindings of the demo player (demo_play in
#   lib/demo.sh) and the four places that document them. The binding is
#   spread over code, the in-game help page and two language files, and
#   that is exactly how it drifted apart once already: 1.4.0 moved the
#   left and right arrows from the replay speed to the seat of a
#   multiplayer recording, the help page was updated, and both --help
#   texts kept claiming the old binding for three releases (see
#   HISTORY.md, 1.4.3). Nothing could notice, because no test looked at
#   the two together.
#   This one does. It reads the case branches out of demo_play and
#   compares each against the intended mapping, then checks that the
#   help page builds its lines from the matching key labels and that the
#   demo paragraph of every language names the same keys. It also
#   measures the rendered help lines against the width the 48-column
#   minimum terminal leaves (CLAUDE.md 3.4) - the German speed line sat
#   one character short of it before 1.4.3.
#   Headless by design, like tools/key-scan.sh and tools/state-check.sh:
#   it reads the sources and sources the language files, never starts the
#   game and needs no terminal, so the CI can run it on every push.
#   What it deliberately does NOT do is replay the loop: driving
#   demo_play needs the whole game stubbed out - clock, renderer, input -
#   and a harness like that breaks on every refactor while catching a
#   class of fault (a key that does the wrong thing) that has never
#   occurred here. The fault that did occur is documentation drift, and
#   that is what this test is pointed at.
#
# Program flow:
#   1. Parse arguments and resolve the repository root.
#   2. Read the key branches of demo_play and compare each branch that
#      has an effect against the keys that are meant to trigger it.
#   3. Check that the help page in lib/menu.sh builds its focus and speed
#      lines from the matching key labels.
#   4. Per language file: the labels exist, the two rendered help lines
#      stay within the body width, and the demo paragraph of the usage
#      text names the same keys.
#   5. Report the number of checks and exit non-zero on any failure.
#
# Usage:
#   demo-keys.sh [-v|--verbose] [-s|--silent] [-h|--help]
#
# Version: 1.0.0  (2026-09-09)

set -euo pipefail

SCRIPT_NAME="$(basename -- "${0}")"
REPO_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)"

# --- Defaults seeded from environment variables ---------------------------
# Precedence: command-line argument > environment variable > default.
VERBOSE="${ROWHAMMER_DEMOKEYS_VERBOSE:-0}"
SILENT="${ROWHAMMER_DEMOKEYS_SILENT:-0}"

# Width of the menu indent that menu_info puts in front of every body
# line ("  ${line}" in lib/menu.sh). The body width is the block width
# minus this; the block width itself is read from lib/render.sh below, so
# a changed layout moves this limit along with it instead of silently
# leaving the test behind.
MENU_INDENT=2

usage() {
    cat <<'EOF'
Usage: demo-keys.sh [OPTIONS]

Check the demo player's key bindings against the help page, the language
files and the width the menu body has. Catches the drift between code and
documentation that 1.4.0 introduced and 1.4.3 fixed.

Options:
  -v, --verbose    Print every check as it runs.
                   Env: ROWHAMMER_DEMOKEYS_VERBOSE  Default: 0
  -s, --silent     Print errors only.
                   Env: ROWHAMMER_DEMOKEYS_SILENT   Default: 0
  -h, --help       Show this help and exit.

Exit code 0 when every check passed, 1 on a failure, 2 on a usage error.
EOF
}

log() {
    if [ "${SILENT}" -eq 0 ]; then
        printf '%s\n' "${1}"
    fi
}

vlog() {
    if [ "${VERBOSE}" -eq 1 ] && [ "${SILENT}" -eq 0 ]; then
        printf '  %s\n' "${1}"
    fi
}

# --- Argument parsing (highest precedence) --------------------------------
while [ "$#" -gt 0 ]; do
    case "${1}" in
        -v|--verbose) VERBOSE=1; shift ;;
        -s|--silent)  SILENT=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        *)
            printf '%s: unknown option: %s\n' "${SCRIPT_NAME}" "${1}" >&2
            printf 'Try "%s --help".\n' "${SCRIPT_NAME}" >&2
            exit 2
            ;;
    esac
done

if [ "${VERBOSE}" -eq 1 ] && [ "${SILENT}" -eq 1 ]; then
    printf '%s: --verbose and --silent are mutually exclusive\n' \
        "${SCRIPT_NAME}" >&2
    exit 2
fi

DEMO_FILE="${REPO_DIR}/lib/demo.sh"
MENU_FILE="${REPO_DIR}/lib/menu.sh"
RENDER_FILE="${REPO_DIR}/lib/render.sh"
for f in "${DEMO_FILE}" "${MENU_FILE}" "${RENDER_FILE}"; do
    if [ ! -r "${f}" ]; then
        printf '%s: missing library file: %s\n' "${SCRIPT_NAME}" "${f}" >&2
        exit 1
    fi
done

CHECKS=0
FAILURES=0

# check DESCRIPTION EXPECTED ACTUAL
# One comparison. Counted either way, reported only when it fails - a
# passing run should say how much it checked, not what.
check() {
    local what="${1}" want="${2}" got="${3}"
    CHECKS=$(( CHECKS + 1 ))
    if [ "${want}" = "${got}" ]; then
        vlog "ok: ${what}"
        return 0
    fi
    printf '%s: FAIL %s\n  expected: %s\n  actual:   %s\n' \
        "${SCRIPT_NAME}" "${what}" "${want}" "${got}" >&2
    FAILURES=$(( FAILURES + 1 ))
    return 0
}

# --- 2. The key branches of demo_play -------------------------------------
# The case is read as pattern/body pairs rather than matched line by line,
# so the test says what a key does and not how the branch is written: the
# body identifies the effect, the pattern says which keys reach it. That
# keeps "UP|+" and "+|UP" the same answer and survives reindentation.
case_pairs() {
    awk '
        /^demo_play\(\) \{/            { in_fn = 1 }
        in_fn && /case "\$\{KEY\}" in/ { in_case = 1; next }
        !in_case                       { next }
        {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            sub(/[[:space:]]+$/, "", line)
        }
        line == "esac"                 { exit }
        line == "" || line ~ /^#/      { next }
        !collecting && line ~ /\)$/ {
            pattern = substr(line, 1, length(line) - 1)
            body = ""
            collecting = 1
            next
        }
        collecting && line == ";;" {
            print pattern "\t" body
            collecting = 0
            next
        }
        collecting { body = body " " line }
    ' "${DEMO_FILE}"
}

# keys_for EFFECT
# The keys of the one branch whose body contains EFFECT, as a sorted,
# comma-separated set. "none" when no branch has that effect, "ambiguous"
# when more than one does - both are failures, and both are more useful
# in the report than an empty string.
keys_for() {
    local effect="${1}" pair pattern hits=0 keys=""
    while IFS= read -r pair; do
        case "${pair#*$'\t'}" in
            *"${effect}"*) ;;
            *) continue ;;
        esac
        hits=$(( hits + 1 ))
        pattern="${pair%%$'\t'*}"
        keys="$(printf '%s\n' "${pattern//|/$'\n'}" | LC_ALL=C sort \
            | paste -sd, -)"
    done < <(case_pairs)
    if [ "${hits}" -eq 0 ]; then
        printf 'none\n'
    elif [ "${hits}" -gt 1 ]; then
        printf 'ambiguous\n'
    else
        printf '%s\n' "${keys}"
    fi
}

# The intended mapping, in the words of CLAUDE.md 3.8 and 5.20: the
# horizontal arrows walk the seats, the vertical ones and "+"/"-" carry
# the speed. The speed keys are checked as a pair on purpose - dropping
# one of the two is precisely the regression this file exists for.
check "left arrow steps the focus back" \
    "LEFT" "$(keys_for 'demo_focus_step -1')"
check "right arrow steps the focus on" \
    "RIGHT" "$(keys_for 'demo_focus_step 1')"
check "up arrow and + raise the speed" \
    "+,UP" "$(keys_for 'DEMO_SPEED_IDX + 1')"
check "down arrow and - lower the speed" \
    "-,DOWN" "$(keys_for 'DEMO_SPEED_IDX - 1')"

# The two branches that were there before the arrows meant anything. They
# are checked so a refactor cannot quietly drop them while the four above
# still pass.
# shellcheck disable=SC2016  # these are source texts to match, not expansions
check "the pause key and space toggle the replay" \
    '"${KEY_PAUSE}",SPACE' "$(keys_for 'PAUSED=$(( 1 - PAUSED ))')"
# shellcheck disable=SC2016  # same: the literal pattern as demo_play spells it
check "the quit key and ESC leave the replay" \
    '"${KEY_QUIT}",ESC' "$(keys_for 'demo_play_states_release')"

# --- 3. The help page reads the matching labels ---------------------------
# menu_help_body builds each line from a description and a key label on
# the following line; the label is what has to match the code above.
label_of() {
    local entry="${1}"
    awk -v entry="${entry}" '
        found { print; exit }
        index($0, "I18N[" entry "]") { found = 1 }
    ' "${MENU_FILE}"
}

FOCUS_LINE="$(label_of help_demo_focus)"
SPEED_LINE="$(label_of help_demo_speed)"

case "${FOCUS_LINE}" in
    *key_arrows_lr*) got="yes" ;;
    *) got="no: ${FOCUS_LINE}" ;;
esac
check "the help page names the horizontal arrows for the focus" "yes" "${got}"

case "${SPEED_LINE}" in
    *key_arrows_ud*) got="yes" ;;
    *) got="no: ${SPEED_LINE}" ;;
esac
check "the help page names the vertical arrows for the speed" "yes" "${got}"

case "${SPEED_LINE}" in
    *key_minus_plus*) got="yes" ;;
    *) got="no: ${SPEED_LINE}" ;;
esac
check "the help page still names + and - for the speed" "yes" "${got}"

# --- 4. Every language: labels, widths and the usage paragraph ------------
# The body width comes from the layout instead of a number of its own, so
# a changed block width moves the limit with it (CLAUDE.md 3.4).
LAYOUT_W="$(sed -n 's/^LAYOUT_W=\([0-9]\{1,\}\).*/\1/p' "${RENDER_FILE}")"
if [ -z "${LAYOUT_W}" ]; then
    printf '%s: could not read LAYOUT_W from %s\n' \
        "${SCRIPT_NAME}" "${RENDER_FILE}" >&2
    exit 1
fi
BODY_W=$(( LAYOUT_W - MENU_INDENT ))
vlog "body width: ${BODY_W} columns (LAYOUT_W ${LAYOUT_W} - indent ${MENU_INDENT})"

# words_of LABEL
# The key words of a label, without its decoration: "Pfeil hoch/runter"
# and "arrow up/down" both become the two words that a prose sentence has
# to use if it means those keys. Taking them from the label instead of
# writing them here per language is what lets a third language be checked
# without touching this file.
words_of() {
    printf '%s\n' "${1}" | tr '/' '\n' | awk '{ print $NF }'
}

declare -A I18N=()

for lang_file in "${REPO_DIR}"/lib/lang/*.sh; do
    lang="$(basename -- "${lang_file}" .sh)"
    # shellcheck source=/dev/null
    . "${lang_file}"

    for entry in key_arrows_lr key_arrows_ud key_minus_plus \
                 help_demo_focus help_demo_speed; do
        if [ -n "${I18N[${entry}]:-}" ]; then
            got="set"
        else
            got="missing"
        fi
        check "${lang}: ${entry} is translated" "set" "${got}"
    done

    # The two lines as menu_help_body renders them. Compared against the
    # body width, not against a fixed number of characters of their own.
    printf -v focus_line '%-17s %s' "${I18N[help_demo_focus]}" \
        "${I18N[key_arrows_lr]}"
    printf -v speed_line '%-17s %s' "${I18N[help_demo_speed]}" \
        "${I18N[key_arrows_ud]}, ${I18N[key_minus_plus]}"
    for rendered in "${focus_line}" "${speed_line}"; do
        if [ "${#rendered}" -le "${BODY_W}" ]; then
            got="fits"
        else
            got="${#rendered} columns: ${rendered}"
        fi
        check "${lang}: help line fits ${BODY_W} columns" "fits" "${got}"
    done

    # The demo paragraph of the long --help text. It is prose, so it is
    # checked for the key words of the labels rather than for a wording:
    # the point is that it cannot go on naming keys the code no longer
    # binds, which is exactly what it did between 1.4.0 and 1.4.3.
    paragraph="$(awk '
        /^Demos:/  { in_par = 1 }
        in_par && /^[[:space:]]*$/ { exit }
        in_par     { print }
    ' "${lang_file}")"
    if [ -z "${paragraph}" ]; then
        check "${lang}: the usage text has a demo paragraph" "found" "missing"
        continue
    fi
    for label in "${I18N[key_arrows_ud]}" "${I18N[key_arrows_lr]}"; do
        while IFS= read -r word; do
            case "${paragraph}" in
                *"${word}"*) got="named" ;;
                *) got="absent" ;;
            esac
            check "${lang}: the demo paragraph names \"${word}\"" \
                "named" "${got}"
        done < <(words_of "${label}")
    done
done

# --- 5. Result ------------------------------------------------------------
if [ "${FAILURES}" -gt 0 ]; then
    printf '%s: %d failure(s) in %d checks\n' \
        "${SCRIPT_NAME}" "${FAILURES}" "${CHECKS}" >&2
    exit 1
fi
log "${SCRIPT_NAME}: ${CHECKS} checks, no failures"
exit 0
