#!/usr/bin/env bash
#
# release.sh
#
# Description:
#   Release helper for rowhammer. The repository carries the version
#   number in three places (rowhammer.sh, debian/changelog and
#   rowhammer.spec); this script is the single tool that knows about all
#   of them. It verifies that they agree, extracts the release notes for
#   a version from debian/changelog, and creates the annotated git tag
#   "v<version>" that the release workflow reacts to. The same script is
#   used by hand and by the GitHub Actions workflows in .github/workflows,
#   so the local and the automated release follow identical rules.
#
# Program flow:
#   1. Parse arguments and resolve configuration (CLI > env > default).
#   2. Verify prerequisites (repository layout, git for mode "tag").
#   3. Read the version from rowhammer.sh (or take it from --expect).
#   4. Run the requested mode:
#      check   - compare the version across all three files and make sure
#                debian/changelog and the spec %changelog have an entry
#      version - print the version
#      notes   - extract the changelog stanza as markdown release notes
#      tag     - run "check", then create (and optionally push) the tag
#   5. Report the result via logging.
#
# Usage:
#   release.sh [-m|--mode check|version|notes|tag] [-e|--expect VERSION]
#              [-o|--output FILE] [-p|--push] [-r|--remote NAME]
#              [-v|--verbose] [-s|--silent] [-h|--help]
#
# Version: 1.0.0  (2026-08-03)

set -euo pipefail

# Script name, used as logger tag and in messages.
SCRIPT_NAME="$(basename -- "${0}")"
# The repository root is the parent of the tools/ directory this script
# lives in. Symlinks are resolved so a link in ~/bin still finds the tree.
REPO_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)"

# The three files that carry the version. rowhammer.sh is the reference:
# it is the version the game reports about itself, the other two label the
# packages built from it.
VERSION_SCRIPT="${REPO_DIR}/rowhammer.sh"
DEB_CHANGELOG="${REPO_DIR}/debian/changelog"
RPM_SPEC="${REPO_DIR}/rowhammer.spec"

# Tags are the version with a leading "v" (v0.39.0). The release workflow
# triggers on this pattern, so the prefix is part of the interface.
TAG_PREFIX="v"

# --- Defaults seeded from environment variables ---------------------------
# Precedence: command-line argument > environment variable > built-in default.
MODE="${ROWHAMMER_RELEASE_MODE:-check}"
EXPECT_VERSION="${ROWHAMMER_RELEASE_EXPECT:-}"
OUTPUT_FILE="${ROWHAMMER_RELEASE_OUTPUT:-}"
PUSH_TAG="${ROWHAMMER_RELEASE_PUSH:-0}"
REMOTE="${ROWHAMMER_RELEASE_REMOTE:-origin}"
VERBOSE="${ROWHAMMER_RELEASE_VERBOSE:-0}"
SILENT="${ROWHAMMER_RELEASE_SILENT:-0}"

# Print usage information.
usage() {
    cat <<'EOF'
Usage: release.sh [OPTIONS]

Release helper for rowhammer: checks that the version agrees across
rowhammer.sh, debian/changelog and rowhammer.spec, extracts the release
notes for a version from debian/changelog, and creates the release tag.

Options:
  -m, --mode MODE       What to do. One of:
                          check   - verify the version across all files
                                    (default; exits non-zero on mismatch)
                          version - print the version and exit
                          notes   - print the release notes as markdown
                          tag     - check, then create the annotated tag
                                    v<version> with the notes as message
                        Env: ROWHAMMER_RELEASE_MODE    Default: check
  -e, --expect VERSION  Version that is expected, e.g. the one taken from
                        a pushed git tag. Every mode then works on this
                        version and "check" additionally fails when
                        rowhammer.sh disagrees with it.
                        Env: ROWHAMMER_RELEASE_EXPECT  Default: (none)
  -o, --output FILE     Write the release notes to FILE instead of STDOUT
                        (mode "notes" only).
                        Env: ROWHAMMER_RELEASE_OUTPUT  Default: (stdout)
  -p, --push            Push the tag to the remote after creating it
                        (mode "tag" only).
                        Env: ROWHAMMER_RELEASE_PUSH    Default: 0
  -r, --remote NAME     Remote to push the tag to.
                        Env: ROWHAMMER_RELEASE_REMOTE  Default: origin
  -v, --verbose         Enable verbose (debug) output.
                        Env: ROWHAMMER_RELEASE_VERBOSE Default: 0
  -s, --silent          Suppress all non-error output.
                        Env: ROWHAMMER_RELEASE_SILENT  Default: 0
  -h, --help            Show this help and exit.

Silent and verbose are mutually exclusive; setting both is an error.
Precedence for every option: command-line argument > environment variable
> built-in default.

The release notes go to STDOUT, all status messages to STDERR, so the
output of "--mode notes" and "--mode version" can be piped safely.

Examples:
  ./tools/release.sh --mode check
  ./tools/release.sh --mode notes --output /tmp/notes.md
  ./tools/release.sh --mode tag --push
EOF
}

# log LEVEL MESSAGE...
# Always records the entry in syslog/journal via logger so automated runs
# leave a trace; additionally prints to the console when STDOUT is a
# terminal or when running under CI (errors/warnings to STDERR, debug only
# in verbose mode, silent mode limits console output to errors).
#
# All console output goes to STDERR, including info and debug: the payload
# of this script (release notes, version number) is written to STDOUT and
# must stay free of status messages so it can be piped or redirected.
log() {
    local level="${1}"
    shift
    local message="$*"
    local priority="user.notice"
    case "${level}" in
        error) priority="user.err" ;;
        warn)  priority="user.warning" ;;
        info)  priority="user.info" ;;
        debug) priority="user.debug" ;;
    esac
    if [ "${level}" = "debug" ] && [ "${VERBOSE}" -ne 1 ]; then
        return 0
    fi
    # logger is part of util-linux and present on the usual systems, but a
    # slim CI container may lack it; a missing system log must not abort a
    # release check, so the call is guarded instead of relied upon.
    if command -v logger >/dev/null 2>&1; then
        logger -t "${SCRIPT_NAME}" -p "${priority}" -- "${message}"
    fi
    # A CI runner has no terminal and no journal a human would ever read,
    # so its console log is the only trace of what happened. Without this
    # the script would fail silently in the workflow.
    if [ -t 1 ] || [ -n "${CI:-}" ]; then
        if [ "${SILENT}" -eq 1 ] && [ "${level}" != "error" ]; then
            return 0
        fi
        printf '%s: %s\n' "${level}" "${message}" >&2
    fi
}

# die MESSAGE...  Report an explicit failure and exit non-zero.
die() {
    log error "$*"
    exit 1
}

# --- Argument parsing (highest precedence) --------------------------------
while [ "$#" -gt 0 ]; do
    case "${1}" in
        -m|--mode)
            if [ "$#" -lt 2 ]; then
                printf '%s: option %s requires an argument\n' "${SCRIPT_NAME}" "${1}" >&2
                exit 2
            fi
            MODE="${2}"
            shift 2
            ;;
        --mode=*)
            MODE="${1#*=}"
            shift
            ;;
        -e|--expect)
            if [ "$#" -lt 2 ]; then
                printf '%s: option %s requires an argument\n' "${SCRIPT_NAME}" "${1}" >&2
                exit 2
            fi
            EXPECT_VERSION="${2}"
            shift 2
            ;;
        --expect=*)
            EXPECT_VERSION="${1#*=}"
            shift
            ;;
        -o|--output)
            if [ "$#" -lt 2 ]; then
                printf '%s: option %s requires an argument\n' "${SCRIPT_NAME}" "${1}" >&2
                exit 2
            fi
            OUTPUT_FILE="${2}"
            shift 2
            ;;
        --output=*)
            OUTPUT_FILE="${1#*=}"
            shift
            ;;
        -p|--push)
            PUSH_TAG=1
            shift
            ;;
        -r|--remote)
            if [ "$#" -lt 2 ]; then
                printf '%s: option %s requires an argument\n' "${SCRIPT_NAME}" "${1}" >&2
                exit 2
            fi
            REMOTE="${2}"
            shift 2
            ;;
        --remote=*)
            REMOTE="${1#*=}"
            shift
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -s|--silent)
            SILENT=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf '%s: unknown option or argument: %s\n' "${SCRIPT_NAME}" "${1}" >&2
            usage >&2
            exit 2
            ;;
    esac
done

# Silent and verbose are mutually exclusive.
if [ "${SILENT}" -eq 1 ] && [ "${VERBOSE}" -eq 1 ]; then
    printf '%s: --silent and --verbose are mutually exclusive\n' "${SCRIPT_NAME}" >&2
    exit 2
fi

# Reject an unknown mode here rather than falling through to a default,
# so a typo does not silently do something else than intended.
case "${MODE}" in
    check|version|notes|tag) ;;
    *)
        printf '%s: unknown mode: %s (expected check, version, notes or tag)\n' \
            "${SCRIPT_NAME}" "${MODE}" >&2
        exit 2
        ;;
esac

# --- Prerequisites --------------------------------------------------------
# The script only makes sense inside the packaging tree; say which file is
# missing instead of failing later with an empty version.
check_prerequisites() {
    local file
    for file in "${VERSION_SCRIPT}" "${DEB_CHANGELOG}" "${RPM_SPEC}"; do
        if [ ! -f "${file}" ]; then
            die "Not a rowhammer packaging tree, missing file: ${file}"
        fi
    done
}

# Versions are plain MAJOR.MINOR.PATCH (see the SemVer rule in the script
# conventions). Validating the shape keeps a stray line in one of the
# files from turning into a tag name or a file path.
is_valid_version() {
    printf '%s' "${1}" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'
}

# --- Reading the version from the three files -----------------------------

# rowhammer.sh is the reference: ROWHAMMER_VERSION is what the game shows
# in --help and writes into the debug log header.
read_script_version() {
    sed -n 's/^ROWHAMMER_VERSION="\([^"]*\)".*/\1/p' "${VERSION_SCRIPT}" | head -n 1
}

# debian/changelog carries the version of the Debian package in the header
# line of its topmost stanza: "rowhammer (0.39.0) unstable; urgency=..."
read_deb_version() {
    sed -n '1s/^[^ ]* (\([^)]*\)).*$/\1/p' "${DEB_CHANGELOG}"
}

# rowhammer.spec carries it in its Version tag. Read by pattern rather
# than through rpmspec so the check also runs on a host without the rpm
# tooling (the CI lint job installs neither dpkg-dev nor rpm).
read_rpm_version() {
    sed -n 's/^Version:[[:space:]]*\([^[:space:]]*\).*$/\1/p' "${RPM_SPEC}" | head -n 1
}

# Resolve the version this run works on: --expect wins when given (that is
# the version taken from a pushed tag), otherwise rowhammer.sh decides.
resolve_version() {
    local version
    if [ -n "${EXPECT_VERSION}" ]; then
        version="${EXPECT_VERSION}"
    else
        version="$(read_script_version)"
        if [ -z "${version}" ]; then
            die "Could not read ROWHAMMER_VERSION from ${VERSION_SCRIPT}"
        fi
    fi
    if ! is_valid_version "${version}"; then
        die "Not a MAJOR.MINOR.PATCH version: ${version}"
    fi
    printf '%s' "${version}"
}

# --- Mode: check ----------------------------------------------------------
# Compare the version across all three files and make sure both changelogs
# actually document it. A package whose label contradicts its contents, or
# a release without release notes, is caught here rather than after the
# tag has been pushed.
mode_check() {
    local version="${1}"
    local script_version deb_version rpm_version
    script_version="$(read_script_version)"
    deb_version="$(read_deb_version)"
    rpm_version="$(read_rpm_version)"

    log debug "rowhammer.sh:      ${script_version:-<none>}"
    log debug "debian/changelog:  ${deb_version:-<none>}"
    log debug "rowhammer.spec:    ${rpm_version:-<none>}"

    local failures=0
    if [ "${script_version}" != "${version}" ]; then
        log error "Version mismatch: rowhammer.sh has '${script_version}', expected '${version}'"
        failures=$((failures + 1))
    fi
    if [ "${deb_version}" != "${version}" ]; then
        log error "Version mismatch: debian/changelog has '${deb_version}', expected '${version}' (add a new changelog stanza)"
        failures=$((failures + 1))
    fi
    if [ "${rpm_version}" != "${version}" ]; then
        log error "Version mismatch: rowhammer.spec has '${rpm_version}', expected '${version}' (update the Version tag)"
        failures=$((failures + 1))
    fi

    # The spec keeps its own %changelog. Forgetting the entry there is easy
    # because the Version tag alone still builds, so it is checked
    # explicitly; the entry line ends in "- <version>-<release>".
    if ! grep -Eq "^\*.* - ${version}-[0-9]+$" "${RPM_SPEC}"; then
        log error "No %changelog entry for ${version} in ${RPM_SPEC}"
        failures=$((failures + 1))
    fi

    # The release notes come from the changelog stanza, so an empty one
    # would produce an empty release.
    if [ -z "$(extract_notes_body "${version}")" ]; then
        log error "No changelog entry for ${version} in ${DEB_CHANGELOG}"
        failures=$((failures + 1))
    fi

    if [ "${failures}" -gt 0 ]; then
        die "Version check failed with ${failures} problem(s); see the messages above"
    fi
    log info "Version ${version} is consistent across rowhammer.sh, debian/changelog and rowhammer.spec"
}

# --- Mode: notes ----------------------------------------------------------

# Print the body of the changelog stanza for a version: everything between
# the "rowhammer (<version>) ..." header and the " -- maintainer" trailer,
# with the two leading spaces of the Debian format removed. The result is
# already valid markdown ("  * text" becomes "* text", continuation lines
# keep their relative indent and stay part of the list item).
extract_notes_body() {
    local version="${1}"
    awk -v want="${version}" '
        # Stanza header: "rowhammer (0.39.0) unstable; urgency=medium".
        /^[a-z0-9][a-z0-9+.-]* \(/ {
            stanza = $0
            sub(/^[^(]*\(/, "", stanza)
            sub(/\).*$/, "", stanza)
            in_stanza = (stanza == want)
            next
        }
        # Trailer line " -- Name <mail>  Date" closes the stanza.
        /^ -- / { if (in_stanza) exit; next }
        in_stanza { sub(/^  /, ""); print }
    ' "${DEB_CHANGELOG}" | sed -e '/./,$!d' | awk '
        # Drop trailing blank lines without buffering the whole text: hold
        # back empty lines and only emit them once real content follows.
        /^[[:space:]]*$/ { blanks++; next }
        { while (blanks > 0) { print ""; blanks-- } ; print }
    '
}

# Assemble the markdown release notes: a heading, the changelog body and a
# short installation block. The block names no file names on purpose - the
# rpm file name carries the release number and the distribution tag, so a
# hard-coded example would go stale on the first rebuild.
build_notes() {
    local version="${1}"
    local body
    body="$(extract_notes_body "${version}")"
    if [ -z "${body}" ]; then
        die "No changelog entry for ${version} in ${DEB_CHANGELOG}"
    fi
    cat <<EOF
## rowhammer ${version}

${body}

### Installation

Download the package for your distribution from the assets below:

* Debian/Ubuntu: \`sudo apt install ./rowhammer_${version}_all.deb\`
* Fedora/RHEL/openSUSE: \`sudo dnf install ./rowhammer-${version}-*.noarch.rpm\`
* Any other system: unpack the source tarball and run \`sudo make install PREFIX=/usr\`

Start the game with \`rowhammer\`. The checksums of all assets are in
\`SHA256SUMS\`.
EOF
}

# Write the notes to STDOUT or to the file given with --output.
mode_notes() {
    local version="${1}"
    local notes
    notes="$(build_notes "${version}")"
    if [ -n "${OUTPUT_FILE}" ]; then
        printf '%s\n' "${notes}" >"${OUTPUT_FILE}"
        log info "Release notes for ${version} written to ${OUTPUT_FILE}"
    else
        printf '%s\n' "${notes}"
    fi
}

# --- Mode: tag ------------------------------------------------------------
# Create the annotated tag that the release workflow reacts to. The notes
# are the tag message, so the tag itself carries what the release says.
mode_tag() {
    local version="${1}"
    local tag="${TAG_PREFIX}${version}"

    if ! command -v git >/dev/null 2>&1; then
        die "git is required to create a tag but was not found"
    fi
    if ! git -C "${REPO_DIR}" rev-parse --git-dir >/dev/null 2>&1; then
        die "Not a git repository: ${REPO_DIR}"
    fi

    # A tag must point at a state that exists in the history; tagging a
    # dirty tree would label a commit that does not contain the changes.
    if [ -n "$(git -C "${REPO_DIR}" status --porcelain)" ]; then
        die "Working tree has uncommitted changes; commit them before tagging"
    fi
    # Never move an existing tag: it may already have produced a release,
    # and rewriting it would silently change what that release refers to.
    if git -C "${REPO_DIR}" rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
        die "Tag ${tag} already exists; delete it explicitly if it really has to be redone"
    fi

    local notes
    notes="$(build_notes "${version}")"
    printf '%s\n' "${notes}" | git -C "${REPO_DIR}" tag -a "${tag}" -F -
    log info "Created annotated tag ${tag}"

    if [ "${PUSH_TAG}" -eq 1 ]; then
        git -C "${REPO_DIR}" push "${REMOTE}" "${tag}"
        log info "Pushed ${tag} to ${REMOTE}; the release workflow builds the packages"
    else
        log info "Push it with: git push ${REMOTE} ${tag}"
    fi
}

# --- Main -----------------------------------------------------------------
main() {
    check_prerequisites

    local version
    version="$(resolve_version)"
    log debug "Repository: ${REPO_DIR}"
    log debug "Mode: ${MODE}, version: ${version}"

    case "${MODE}" in
        check)
            mode_check "${version}"
            ;;
        version)
            printf '%s\n' "${version}"
            ;;
        notes)
            mode_notes "${version}"
            ;;
        tag)
            # Tagging an inconsistent tree would publish packages whose
            # labels disagree, so the check is not optional here.
            mode_check "${version}"
            mode_tag "${version}"
            ;;
    esac
}

main
