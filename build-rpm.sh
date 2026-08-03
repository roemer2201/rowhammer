#!/usr/bin/env bash
#
# build-rpm.sh
#
# Description:
#   Builds the RPM package for rowhammer from rowhammer.spec in this
#   repository and collects the build artifacts (.rpm, optionally the
#   source .src.rpm) in an output directory. rpmbuild runs in a private
#   build tree inside that output directory, so neither the working tree
#   nor the caller's ~/rpmbuild is touched. The counterpart to
#   build-deb.sh; the package layout itself comes from the shared
#   Makefile install target.
#
# Program flow:
#   1. Parse arguments and resolve configuration (CLI > env > default).
#   2. Verify prerequisites (rpmbuild, rpmspec, make, tar, spec file).
#   3. Read name and version from the spec and cross-check the version
#      against ROWHAMMER_VERSION in rowhammer.sh.
#   4. Create the source tarball <name>-<version>.tar.gz in a private
#      rpmbuild tree.
#   5. Run rpmbuild (binary package, optionally the source package too).
#   6. Collect the artifacts into the output directory, drop the build
#      tree unless it is to be kept, and report the result.
#
# Usage:
#   build-rpm.sh [-o|--output-dir DIR] [-r|--release N] [-S|--srpm]
#                [-k|--keep-build] [-v|--verbose] [-s|--silent] [-h|--help]
#
# Version: 1.1.0  (2026-08-03)

set -euo pipefail

# Script name, used as logger tag and in messages.
SCRIPT_NAME="$(basename -- "${0}")"
# The repository root is where this script lives; the tarball is built from
# there and the spec file is expected next to it.
REPO_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
# The spec file is the single source of truth for the package name and
# version, the same role debian/changelog plays for the Debian package.
SPEC_FILE="${REPO_DIR}/rowhammer.spec"

# --- Defaults seeded from environment variables ---------------------------
# Precedence: command-line argument > environment variable > built-in default.
OUTPUT_DIR="${ROWHAMMER_RPM_OUTPUT_DIR:-${REPO_DIR}/dist}"
RELEASE="${ROWHAMMER_RPM_RELEASE:-1}"
BUILD_SRPM="${ROWHAMMER_RPM_SRPM:-0}"
KEEP_BUILD="${ROWHAMMER_RPM_KEEP_BUILD:-0}"
VERBOSE="${ROWHAMMER_RPM_VERBOSE:-0}"
SILENT="${ROWHAMMER_RPM_SILENT:-0}"

# Print usage information.
usage() {
    cat <<'EOF'
Usage: build-rpm.sh [OPTIONS]

Builds the RPM package for rowhammer and moves the artifacts (.rpm, with
--srpm also the .src.rpm) into the output directory.

Options:
  -o, --output-dir DIR  Directory for the build artifacts.
                        Env: ROWHAMMER_RPM_OUTPUT_DIR  Default: <repo>/dist
  -r, --release N       Release number of the package (rebuilds of an
                        unchanged version).
                        Env: ROWHAMMER_RPM_RELEASE     Default: 1
  -S, --srpm            Build the source package (.src.rpm) as well.
                        Env: ROWHAMMER_RPM_SRPM        Default: 0
  -k, --keep-build      Keep the private rpmbuild tree for inspection
                        instead of removing it after a successful build.
                        Env: ROWHAMMER_RPM_KEEP_BUILD  Default: 0
  -v, --verbose         Enable verbose (debug) output.
                        Env: ROWHAMMER_RPM_VERBOSE     Default: 0
  -s, --silent          Suppress all non-error output.
                        Env: ROWHAMMER_RPM_SILENT      Default: 0
  -h, --help            Show this help and exit.

Silent and verbose are mutually exclusive; setting both is an error.
Precedence for every option: command-line argument > environment variable
> built-in default.

Status messages go to the system log and, when STDOUT is a terminal, to
the console. A set CI environment variable enables the console output as
well, so the build is visible in a CI log.

Build dependencies: rpm-build (rpmbuild, rpmspec), make and tar.

Example:
  ./build-rpm.sh --output-dir /tmp/rowhammer-packages --release 2 --verbose
EOF
}

# log LEVEL MESSAGE...
# Always records the entry in syslog/journal via logger so CI/automated
# runs leave a trace; additionally prints to the console when STDOUT is a
# terminal or the environment variable CI is set (errors/warnings to
# STDERR, debug only in verbose mode, silent mode limits console output to
# errors).
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
    # package build, so the call is guarded instead of relied upon.
    if command -v logger >/dev/null 2>&1; then
        logger -t "${SCRIPT_NAME}" -p "${priority}" -- "${message}"
    fi
    # CHANGE 2026-08-03: console output also when CI is set. A CI runner
    # has no terminal and no journal anybody will ever read, so its
    # console log is the only trace of what the build did - without this
    # the script failed there completely silently, error messages
    # included.
    if [ -t 1 ] || [ -n "${CI:-}" ]; then
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
        -r|--release)
            if [ "$#" -lt 2 ]; then
                printf '%s: option %s requires an argument\n' "${SCRIPT_NAME}" "${1}" >&2
                exit 2
            fi
            RELEASE="${2}"
            shift 2
            ;;
        --release=*)
            RELEASE="${1#*=}"
            shift
            ;;
        -S|--srpm)
            BUILD_SRPM=1
            shift
            ;;
        -k|--keep-build)
            KEEP_BUILD=1
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

# The release number ends up in the package file name and in an rpm macro,
# so reject anything that is not a plain number before it gets there.
if ! printf '%s' "${RELEASE}" | grep -Eq '^[0-9]+$'; then
    printf '%s: --release must be a non-negative integer: %s\n' "${SCRIPT_NAME}" "${RELEASE}" >&2
    exit 2
fi

# --- Prerequisites --------------------------------------------------------
# Fail early with a clear message instead of letting rpmbuild abort halfway
# through with a less obvious error.
check_prerequisites() {
    local tool
    for tool in rpmbuild rpmspec make tar; do
        if ! command -v -- "${tool}" >/dev/null 2>&1; then
            die "Required tool not found: ${tool} (install rpm-build, make and tar)"
        fi
    done
    if [ ! -f "${SPEC_FILE}" ]; then
        die "Not a packaging tree, missing file: ${SPEC_FILE}"
    fi
    if [ ! -f "${REPO_DIR}/Makefile" ]; then
        die "Missing the shared install logic: ${REPO_DIR}/Makefile"
    fi
}

# Query a single tag from the spec file. rpmspec resolves the macros in it,
# so the values match exactly what rpmbuild will use for the same --define.
spec_tag() {
    local tag="${1}"
    rpmspec --define "rowhammer_release ${RELEASE}" \
            --srpm --queryformat "%{${tag}}\n" -q "${SPEC_FILE}"
}

# The spec carries the packaged version, rowhammer.sh the version the game
# reports about itself. Drifting apart would ship a package whose label
# contradicts its contents, so refuse to build instead of guessing which
# one is right.
check_version_sync() {
    local spec_version="${1}"
    local script_version
    script_version="$(sed -n 's/^ROWHAMMER_VERSION="\([^"]*\)".*/\1/p' "${REPO_DIR}/rowhammer.sh" | head -n 1)"
    if [ -z "${script_version}" ]; then
        die "Could not read ROWHAMMER_VERSION from ${REPO_DIR}/rowhammer.sh"
    fi
    if [ "${spec_version}" != "${script_version}" ]; then
        die "Version mismatch: rowhammer.spec has ${spec_version}, rowhammer.sh has ${script_version} (update the spec's Version tag and add a %changelog entry)"
    fi
    log debug "Version ${spec_version} confirmed against rowhammer.sh"
}

# Build the source tarball rpmbuild unpacks in %prep. It contains the files
# the Makefile installs plus the Makefile and README.md, all under a
# <name>-<version>/ prefix as %setup expects. The working tree is packaged
# as it is (not the last commit), matching how dpkg-buildpackage behaves in
# build-deb.sh, so a local change can be test-packaged without committing.
create_tarball() {
    local tarball="${1}" prefix="${2}"
    local sources=(Makefile README.md rowhammer.sh lib assets)
    local item
    for item in "${sources[@]}"; do
        if [ ! -e "${REPO_DIR}/${item}" ]; then
            die "Missing source for the tarball: ${REPO_DIR}/${item}"
        fi
    done
    log debug "Creating source tarball: ${tarball}"
    # --transform is a GNU tar extension; it adds the <name>-<version>/ prefix
    # without having to copy the tree into a staging directory first.
    tar czf "${tarball}" -C "${REPO_DIR}" \
        --transform "s,^,${prefix}/," -- "${sources[@]}"
}

# --- Build ----------------------------------------------------------------
main() {
    check_prerequisites

    local name version
    name="$(spec_tag NAME)"
    version="$(spec_tag VERSION)"
    if [ -z "${name}" ] || [ -z "${version}" ]; then
        die "Could not read name and version from ${SPEC_FILE}"
    fi
    check_version_sync "${version}"

    log info "Building ${name} ${version}-${RELEASE}"
    log debug "Repository: ${REPO_DIR}"
    log debug "Output directory: ${OUTPUT_DIR}"

    mkdir -p -- "${OUTPUT_DIR}"

    # Private rpmbuild tree inside the output directory: the build must not
    # write into the caller's ~/rpmbuild, and keeping it here means a single
    # directory holds everything the build produced.
    local top_dir="${OUTPUT_DIR}/rpmbuild"
    rm -rf -- "${top_dir}"
    mkdir -p -- "${top_dir}/SOURCES" "${top_dir}/SPECS" "${top_dir}/BUILD" \
                "${top_dir}/BUILDROOT" "${top_dir}/RPMS" "${top_dir}/SRPMS"

    create_tarball "${top_dir}/SOURCES/${name}-${version}.tar.gz" "${name}-${version}"

    # -bb builds the binary package only; -ba adds the source package.
    local build_mode="-bb"
    if [ "${BUILD_SRPM}" -eq 1 ]; then
        build_mode="-ba"
        log debug "Building the source package as well"
    fi

    # rpmbuild's output goes to the terminal so its native error messages
    # stay visible; in verbose mode the full build log is shown, otherwise
    # it is captured and only replayed on failure.
    # --nodeps: the spec's BuildRequires are resolved against the host's rpm
    # database, which on a non-RPM build host (this repository is developed
    # on Debian, see build-deb.sh) is empty and would fail the build even
    # though make and tar are installed. check_prerequisites above verifies
    # the very same tools with command -v, which works on any host; the
    # BuildRequires tag stays in the spec for mock/COPR and for plain
    # rpmbuild runs on RPM distributions, where it is enforced properly.
    local rpmbuild_args=(
        "${build_mode}"
        --nodeps
        --define "_topdir ${top_dir}"
        --define "rowhammer_release ${RELEASE}"
        "${SPEC_FILE}"
    )
    if [ "${VERBOSE}" -eq 1 ]; then
        rpmbuild "${rpmbuild_args[@]}"
    else
        local build_log
        build_log="$(mktemp)"
        if ! rpmbuild "${rpmbuild_args[@]}" >"${build_log}" 2>&1; then
            cat -- "${build_log}" >&2
            rm -f -- "${build_log}"
            die "rpmbuild failed, see build log above"
        fi
        rm -f -- "${build_log}"
    fi

    # Collect the packages from the build tree into the output directory so
    # the artifacts sit next to the ones build-deb.sh produces.
    local moved=0 artifact base package_path=""
    while IFS= read -r artifact; do
        base="$(basename -- "${artifact}")"
        mv -f -- "${artifact}" "${OUTPUT_DIR}/"
        # Remember the binary package for the install hint below; the source
        # package is not something one installs.
        case "${base}" in
            *.src.rpm) ;;
            *) package_path="${OUTPUT_DIR}/${base}" ;;
        esac
        log debug "Collected artifact: ${base}"
        moved=$((moved + 1))
    done < <(find "${top_dir}/RPMS" "${top_dir}/SRPMS" -type f -name '*.rpm' | sort)

    if [ "${moved}" -eq 0 ]; then
        die "Build reported success but no .rpm files were found under ${top_dir}"
    fi

    # The build tree is only of interest when something needs inspecting.
    if [ "${KEEP_BUILD}" -eq 1 ]; then
        log info "Keeping the build tree: ${top_dir}"
    else
        rm -rf -- "${top_dir}"
    fi

    log info "Done: ${moved} artifact(s) in ${OUTPUT_DIR}"
    log info "Install with: sudo dnf install ${package_path}"
}

main
