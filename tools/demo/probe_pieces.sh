#!/usr/bin/env bash
#
# probe_pieces.sh
#
# Description:
#   Print the first N pieces of rowhammer's 7-bag stream for a given seed
#   by sourcing the game's own randomizer (lib/pieces.sh). The bag order
#   is fully determined by the seed, so this reproduces the exact piece
#   sequence a run with "--seed SEED" would draw, without playing a single
#   move. The demo planner (sim.py) uses it to know which pieces arrive.
#
# Usage:
#   probe_pieces.sh SEED [N]
#     SEED   integer seed (as passed to rowhammer.sh --seed)
#     N      how many pieces to print (default 60)
#
# Version: 1.1.0  (2026-08-03)
set -u

seed="${1:?usage: probe_pieces.sh SEED [N]}"
n="${2:-60}"

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

RANDOM="${seed}"
NEXT_TYPE=""
out=()
for (( i = 0; i < n; i++ )); do
    bag_next
    out+=("${NEXT_TYPE}")
done
echo "${out[*]}"
