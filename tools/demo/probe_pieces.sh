#!/usr/bin/env bash
#
# probe_pieces.sh
#
# Description:
#   Print the first N pieces of rowhammer's bag stream for a given seed
#   by sourcing the game's own randomizer (lib/pieces.sh). The bag order
#   is fully determined by the seed, so this reproduces the exact piece
#   sequence a run with "--seed SEED" would draw, without playing a single
#   move. The demo planner (sim.py) uses it to know which pieces arrive.
#   Since 2.1.1 the randomizer has a generator of its own (bag_seed and
#   bag_rand), so the output for a seed no longer depends on the bash
#   version this runs under.
#
# Usage:
#   probe_pieces.sh SEED [N]
#     SEED   integer seed (as passed to rowhammer.sh --seed), at most
#            nine digits
#     N      how many pieces to print (default 60)
#
# Version: 1.2.0  (2026-11-09)
set -u

seed="${1:?usage: probe_pieces.sh SEED [N]}"
n="${2:-60}"

# The same rule as the option check in rowhammer.sh, so a seed this tool
# accepts is one the game accepts: bag_seed takes digits only and would
# answer anything else with an arithmetic error of the shell.
if ! [[ "${seed}" =~ ^[0-9]{1,9}$ ]]; then
    printf 'probe_pieces.sh: SEED expects a non-negative integer of at most nine digits, got: %s\n' "${seed}" >&2
    exit 2
fi
if ! [[ "${n}" =~ ^[0-9]{1,6}$ ]]; then
    printf 'probe_pieces.sh: N expects a non-negative integer, got: %s\n' "${n}" >&2
    exit 2
fi

# The library logs bag refills via debug_event; stub it out so sourcing
# the module stays silent and side-effect free. Since 0.42.0 queue_fill
# also talks to the demo layer (lib/demo.sh) - it notes every drawn piece
# for a running recording and takes its pieces from a recording while one
# is being replayed. Neither applies here, so the flag is off and the
# recorder is a stub as well.
debug_event() { :; }
DEMO_PLAYING=0
demo_record_piece() { :; }

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
# shellcheck source=/dev/null
source "${repo_root}/lib/pieces.sh"

bag_seed "${seed}"
NEXT_TYPE=""
out=()
for (( i = 0; i < n; i++ )); do
    bag_next
    out+=("${NEXT_TYPE}")
done
echo "${out[*]}"
