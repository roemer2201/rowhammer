#!/usr/bin/env bash
#
# build-deb.sh
#
# Description:
#   Builds the Debian binary package for rowhammer from the debian/
#   directory in this repository and collects the build artifacts
#   (.deb, .changes, .buildinfo) in an output directory, keeping the
#   parent directory of the working tree clean. Intended for local
#   builds and CI; the package itself is defined in debian/.
#
# Program flow:
#   1. Parse arguments and resolve configuration (CLI > env > default).
#   2. Verify prerequisites (dpkg-buildpackage, debhelper, debian/ dir).
#   3. Read package name and version from debian/changelog.
#   4. Run dpkg-buildpackage (binary-only, unsigned).
#   5. Move the artifacts from the parent directory into the output
#      directory and report the result.
#
# Usage:
#   build-deb.sh [-o|--output-dir DIR] [-v|--verbose] [-s|--silent] [-h|--help]
#
# Version: 1.0.0  (2026-07-18)

set -euo pipefail

# Script name, used as logger tag and in messages.
SCRIPT_NAME="$(basename -- "${0}")"
# The repository root is where this script lives; the build must run there
# because dpkg-buildpackage operates on the current directory.
REPO_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"

# --- Defaults seeded from environment variables ---------------------------
# Precedence: command-line argument > environment variable > built-in default.
OUTPUT_DIR="${ROWHAMMER_DEB_OUTPUT_DIR:-${REPO_DIR}/dist}"
VERBOSE="${ROWHAMMER_DEB_VERBOSE:-0}"
SILENT="${ROWHAMMER_DEB_SILENT:-0}"

# Print usage information.
usage() {
    cat <<'EOF'
Usage: build-deb.sh [OPTIONS]

Builds the Debian binary package for rowhammer and moves the artifacts
(.deb, .changes, .buildinfo) into the output directory.

Options:
  -o, --output-dir DIR  Directory for the build artifacts.
                        Env: ROWHAMMER_DEB_OUTPUT_DIR  Default: <repo>/dist
  -v, --verbose         Enable verbose (debug) output.
                        Env: ROWHAMMER_DEB_VERBOSE     Default: 0
  -s, --silent          Suppress all non-error output.
                        Env: ROWHAMMER_DEB_SILENT      Default: 0
  -h, --help            Show this help and exit.

Silent and verbose are mutually exclusive; setting both is an error.
Precedence for every option: command-line argument > environment variable
> built-in default.

Build dependencies: dpkg-dev (dpkg-buildpackage) and debhelper.

Example:
  ./build-deb.sh --output-dir /tmp/rowhammer-packages --verbose
EOF
}

# log LEVEL MESSAGE...
# Always records the entry in syslog/journal via logger so CI/automated
# runs leave a trace; additionally prints to the console when STDOUT is a
# terminal (errors/warnings to STDERR, debug only in verbose mode, silent
# mode limits console output to errors).
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
    logger -t "${SCRIPT_NAME}" -p "${priority}" -- "${message}"
    if [ -t 1 ]; then
        if [ "${SILENT}" -eq 1 ] && [ "${level}" != "error" ]; then
            return 0
        fi
        if [ "${level}" = "error" ] || [ "${level}" = "warn" ]; then
            printf '%s: %s\n' "${level}" "${message}" >&2
        else
            printf '%s: %s\n' "${level}" "${message}"
        fi
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
        -o|--output-dir)
            if [ "$#" -lt 2 ]; then
                printf '%s: option %s requires an argument\n' "${SCRIPT_NAME}" "${1}" >&2
                exit 2
            fi
            OUTPUT_DIR="${2}"
            shift 2
            ;;
        --output-dir=*)
            OUTPUT_DIR="${1#*=}"
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

# --- Prerequisites --------------------------------------------------------
# Fail early with a clear message instead of letting dpkg-buildpackage
# abort halfway through with a less obvious error.
check_prerequisites() {
    local tool
    for tool in dpkg-buildpackage dpkg-parsechangelog dh; do
        if ! command -v -- "${tool}" >/dev/null 2>&1; then
            die "Required tool not found: ${tool} (install dpkg-dev and debhelper)"
        fi
    done
    if [ ! -f "${REPO_DIR}/debian/changelog" ]; then
        die "Not a packaging tree, missing file: ${REPO_DIR}/debian/changelog"
    fi
}

# --- Build ----------------------------------------------------------------
main() {
    check_prerequisites

    # Package name and version come from debian/changelog, which is the
    # single source of truth for the artifact file names.
    local source_name version
    source_name="$(dpkg-parsechangelog -l "${REPO_DIR}/debian/changelog" -S Source)"
    version="$(dpkg-parsechangelog -l "${REPO_DIR}/debian/changelog" -S Version)"
    log info "Building ${source_name} ${version}"
    log debug "Repository: ${REPO_DIR}"
    log debug "Output directory: ${OUTPUT_DIR}"

    mkdir -p -- "${OUTPUT_DIR}"

    # Binary-only (-b) and unsigned (-us -uc): this is a local/CI build,
    # not a signed upload. dpkg-buildpackage writes its artifacts into the
    # parent directory of the source tree; they are collected below.
    # Its own output goes to the terminal so native error messages stay
    # visible; in verbose mode the full build log is shown, otherwise it
    # is captured and only shown on failure.
    cd -- "${REPO_DIR}"
    if [ "${VERBOSE}" -eq 1 ]; then
        dpkg-buildpackage -us -uc -b
    else
        local build_log
        build_log="$(mktemp)"
        # Capture the build log; on failure replay it so the native error
        # messages are not lost (STDERR must never be swallowed).
        if ! dpkg-buildpackage -us -uc -b >"${build_log}" 2>&1; then
            cat -- "${build_log}" >&2
            rm -f -- "${build_log}"
            die "dpkg-buildpackage failed, see build log above"
        fi
        rm -f -- "${build_log}"
    fi

    # Collect the artifacts (.deb, .changes, .buildinfo) from the parent
    # directory so the working tree's surroundings stay clean.
    local moved=0 artifact
    for artifact in "${REPO_DIR}/.."/"${source_name}_${version}"_*; do
        if [ -e "${artifact}" ]; then
            mv -f -- "${artifact}" "${OUTPUT_DIR}/"
            log debug "Collected artifact: $(basename -- "${artifact}")"
            moved=$((moved + 1))
        fi
    done
    if [ "${moved}" -eq 0 ]; then
        die "Build reported success but no artifacts ${source_name}_${version}_* were found"
    fi

    log info "Done: ${moved} artifact(s) in ${OUTPUT_DIR}"
    log info "Install with: sudo apt install ${OUTPUT_DIR}/${source_name}_${version}_all.deb"
}

main
