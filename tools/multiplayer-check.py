#!/usr/bin/env python3
"""Regressions for multiplayer EOF, recording holds and final standings.

Since format 5 also the final places in the header of a versus recording,
and the standings a replay shows once its timeline has run out.

Run with python3 tools/multiplayer-check.py; unittest accepts -v, -q and -h.
ROWHAMMER_MULTIPLAYER_TEST_ROOT optionally selects another source tree.
The real Bash modules run with the game's strict flags, controlled input
and a deterministic recording clock. No terminal or socat is required.

Version: 1.1.0 (2026-09-23)
"""

import os
from pathlib import Path
import subprocess
import unittest


ROOT = Path(os.environ.get("ROWHAMMER_MULTIPLAYER_TEST_ROOT",
                           Path(__file__).resolve().parent.parent))


def bash(code, *args, data=""):
    """Feed a closed input pipe to the real modules, collecting diagnostics."""
    return subprocess.run(
        ["bash", "-euo", "pipefail", "-c", code, "multiplayer-check",
         str(ROOT), *map(str, args)],
        input=data, text=True, capture_output=True, timeout=5, check=False,
    )


NET_SETUP = r'''
source "${1}/lib/net.sh"
net_log() { :; }
debug_event() { :; }
NET_LINK_IN=0
NET_LINK_UP=1
'''

DEMO_SETUP = r'''
source "${1}/lib/demo.sh"
MP_MAX=2
DEMO_RECORDING=1
DEMO_MP=1
DEMO_MP_SLOT=0
DEMO_SLOT_LAST_MS=(0 0)
DEMO_SLOT_SPAWNS=(1 1)
TEST_MS=0
demo_stamp() { DEMO_STAMP_MS="${TEST_MS}"; }
'''

SCORE_SETUP = r'''
source "${1}/lib/render.sh"
MP_PEER_COUNT=2
MP_PEER_SLOTS=(1 2)
MP_PEER_NAME=(self out alive)
MP_PEER_STATE=(play ko play)
MP_PEER_ROWS=(100 75 50)
MP_PEER_PLACE=(1 2 3)
MP_STATE=play
MP_SLOT=0
MP_ENDED=1
MP_WINNER=0
ROW_CREDIT=100
PEER_PANE_ROW=0
PANE_W=16
'''

# A sprint duel of three decided for seat 0: seat 1 topped out with more
# rows than seat 2, which was still standing when the clock ran out.
# The writer runs for real into a private data directory; "cat" hands
# the file on to the reader tests below.
RECORD_SETUP = r'''
source "${1}/lib/demo.sh"
debug_event() { :; }
demo_prune() { :; }
DATA_DIR="$(mktemp -d)"
trap 'rm -rf -- "${DATA_DIR}"' EXIT
DEMO_TMP_FILE="${DATA_DIR}/rec.tmp"
printf 'p=%s 10h\n' 0 1 2 > "${DEMO_TMP_FILE}"
DEMO_RECORDING=1
DEMO_MP=1
DEMO_MP_SLOT=0
DEMO_BUF=()
DEMO_END_MS=5000
DEMO_PIECES=IOTSZJL
DEMO_SLOT_SPAWNS=(1 1 1)
PREVIEW_COUNT=3
MP_MAX=3
MP_MODE=sprint
MP_GARBAGE=1
MP_WINNER=0
MP_PEER_NAME=(self out alive)
MP_PEER_PLACE=(0 2 3)
GAME_MODE=versus
ROWHAMMER_VERSION=0.0.0
PLAYER_NAME=self
PLAY_MS=5000
CLEAR_PAUSE_MS=280
CLEARED_TOTAL=1
ROW_CREDIT=100
LEVEL=1
GOLD_COUNT=0
SILVER_COUNT=0
ROWHAMMER_COUNT=0
PIECE_COUNT=7
GOAL_REACHED=0
'''

RECORD_CAT = r'''
demo_record_finish over
files=("${DATA_DIR}"/demos/*.demo)
cat -- "${files[0]}"
'''

# The reader gets the file on standard input and reports the reason it
# refused it, if it did, from the debug line demo_reject writes.
READ_SETUP = r'''
source "${1}/lib/demo.sh"
debug_event() { printf 'debug: %s\n' "${1}"; }
work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT
cat > "${work}/round.demo"
if demo_header_read "${work}/round.demo"; then
    printf 'ok %s %s\n' "${DEMO_HDR_WINNER}" "${DEMO_HDR_PLACE[*]}"
else
    printf 'refused %s\n' "${DEMO_BAD_VERSION}"
fi
'''

# The end of a replay of that duel, watched from the winning seat. The
# places that come with "n" events are in; the standing seat has none.
REPLAY_SETUP = SCORE_SETUP + r'''
source "${1}/lib/demo.sh"
MP_PEER_STATE=(play ko play)
MP_PEER_PLACE=(0 2 0)
MP_ENDED=0
MP_WINNER=-1
DEMO_PLAYING=1
DEMO_ENDED=0
DEMO_HDR_MP=1
DEMO_HDR_SLOT=0
DEMO_HDR_WINNER=0
DEMO_HDR_PLACE=(1 2 3 0 0)
DEMO_SEATS=(0 1 2)
DEMO_FOCUS=0
'''


class MultiplayerChecks(unittest.TestCase):
    def run_bash(self, code, *args, data=""):
        result = bash(code, *args, data=data)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.splitlines()

    def test_eof_drains_all_batches_before_reporting_link_down(self):
        # Include no data, exactly one batch, several batches and more
        # than one read block. A final unterminated tail is never a line.
        for count in (0, 15, 16, 17, 40, 200):
            with self.subTest(count=count):
                messages = [f"PING {i}" for i in range(count)] + ["END 0"]
                output = self.run_bash(NET_SETUP + r'''
for (( pass=0; pass<30; pass++ )); do
    rc=0
    net_poll || rc=$?
    [ "${#NET_INBOX[@]}" -le "${MP_POLL_MAX}" ]
    for line in ${NET_INBOX[@]+"${NET_INBOX[@]}"}; do
        printf '%s\n' "${line}"
    done
    if [ "${rc}" -ne 0 ]; then
        [ "${NET_LINK_UP}" -eq 0 ]
        [ "${NET_LINK_ERROR}" = eof ]
        [ -z "${NET_BUF}" ]
        net_poll && exit 2
        [ "${#NET_INBOX[@]}" -eq 0 ]
        exit 0
    fi
done
exit 3
''', data="\n".join(messages) + "\npartial")
                self.assertEqual(output, messages)

    def test_send_after_eof_cannot_discard_pending_receive_batches(self):
        # A PING handler may answer while final receive batches still
        # wait. A failed write must not hide their END from the next poll.
        output = self.run_bash(NET_SETUP + r'''
net_poll
net_send 'PONG 1' && exit 2
[ "${NET_LINK_UP}" -eq 1 ]
rc=0
net_poll || rc=$?
[ "${rc}" -eq 1 ]
printf '%s\n' "${NET_INBOX[@]}"
''', data="PING 1\n" * 16 + "END 0\n")
        self.assertEqual(output, ["END 0"])

    def test_empty_eof_discards_unterminated_tail(self):
        output = self.run_bash(NET_SETUP + r'''
net_poll && exit 2
[ "${#NET_INBOX[@]}" -eq 0 ]
[ -z "${NET_BUF}" ]
''', data="END 0")
        self.assertEqual(output, [])

    def test_split_line_is_retained_until_complete(self):
        # A read-write FIFO stays open, so these polls exercise the live
        # link rather than EOF. Its path is private and removed on exit.
        output = self.run_bash(NET_SETUP + r'''
work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT
mkfifo "${work}/input"
exec 3<>"${work}/input"
NET_LINK_IN=3
printf 'PI' >&3
net_poll
[ "${#NET_INBOX[@]}" -eq 0 ]
printf 'NG 1\nEND 0\n' >&3
net_poll
printf '%s\n' "${NET_INBOX[@]}"
[ "${NET_LINK_UP}" -eq 1 ]
''')
        self.assertEqual(output, ["PING 1", "END 0"])

    def test_early_garbage_waits_for_its_mark(self):
        # The 1999 ms case also guards the -1 sentinel collision.
        for timestamp in (0, 500, 1999, 2000):
            with self.subTest(timestamp=timestamp):
                output = self.run_bash(DEMO_SETUP + r'''
TEST_MS="${2}"
demo_record_garbage 1 2 3
demo_hold_expire
printf '%s %s\n' "${DEMO_HOLD_N}" "${#DEMO_BUF[@]}"
''', timestamp)
                self.assertEqual(output, ["1 0"])

    def test_garbage_follows_the_peer_move_before_its_mark(self):
        output = self.run_bash(DEMO_SETUP + r'''
TEST_MS=500
demo_record_garbage 1 2 3
demo_hold_expire
demo_record_peer_act 1 400 0h150y
printf '%s\n' "${DEMO_BUF[@]}"
[ "${DEMO_HOLD_N}" -eq 0 ]
''')
        self.assertEqual(output, ["p=1 400h", "p=1 150y023"])

    def test_expiry_waits_two_seconds_from_each_event(self):
        output = self.run_bash(DEMO_SETUP + r'''
TEST_MS=500
demo_record_garbage 1 2 3
TEST_MS=2499
demo_hold_expire
[ "${DEMO_HOLD_N}" -eq 1 ]
TEST_MS=2500
demo_hold_expire
[ "${DEMO_HOLD_N}" -eq 0 ]
printf '%s\n' "${DEMO_BUF[@]}"
''')
        self.assertEqual(output, ["p=1 500y023"])

    def test_finish_releases_all_held_events(self):
        output = self.run_bash(DEMO_SETUP + r'''
TEST_MS=500
demo_record_garbage 1 2 3
TEST_MS=550
demo_record_queue 1 1
demo_hold_release 1 -1
[ "${DEMO_HOLD_N}" -eq 0 ]
printf '%s\n' "${DEMO_BUF[@]}"
''')
        self.assertEqual(output, ["p=1 500y023", "p=1 50q01"])

    def test_final_scoreboard_uses_hub_places_for_all_states(self):
        for state in ("ko", "gone"):
            with self.subTest(state=state):
                output = self.run_bash(SCORE_SETUP + r'''
MP_PEER_STATE[1]="${2}"
render_pane_scoreboard
printf '%s\n' "${PANE_RIGHT[@]}"
''', state)
                self.assertEqual([line.rstrip() for line in output],
                                 ["2.out     75", "3.alive   50"])

    def test_final_scoreboard_gets_peer_winner_from_end(self):
        # END names the winner; there is no separate KO assigning that
        # seat place 1. Its stored place may still be zero or an old KO.
        for state, old_place in (("play", 0), ("ko", 3)):
            with self.subTest(state=state):
                output = self.run_bash(SCORE_SETUP + r'''
MP_WINNER=1
MP_PEER_STATE[1]="${2}"
MP_PEER_PLACE[1]="${3}"
MP_PEER_PLACE[2]=2
render_pane_scoreboard
printf '%s\n' "${PANE_RIGHT[@]}"
''', state, old_place)
                self.assertEqual([line.rstrip() for line in output],
                                 ["1.out     75", "2.alive   50"])

    def test_live_scoreboard_keeps_provisional_standings(self):
        output = self.run_bash(SCORE_SETUP + r'''
MP_ENDED=0
MP_WINNER=-1
MP_PEER_PLACE[1]=3
render_pane_scoreboard
printf '%s\n' "${PANE_RIGHT[@]}"
''')
        self.assertEqual([line.rstrip() for line in output],
                         ["2.alive   50", "3.out     75"])

    def recording(self, winner=0):
        return "\n".join(self.run_bash(
            RECORD_SETUP + f"MP_WINNER={winner}\n" + RECORD_CAT)) + "\n"

    def read_header(self, text):
        return self.run_bash(READ_SETUP, data=text)

    def test_recording_names_the_place_of_every_seat(self):
        text = self.recording()
        self.assertIn("version=5\n", text)
        self.assertIn("place=0 1\nplace=1 2\nplace=2 3\n", text)
        self.assertEqual(self.read_header(text)[-1], "ok 0 1 2 3 0 0")

    def test_recording_with_places_loads_completely(self):
        # demo_load has a key list of its own behind demo_header_read.
        output = self.run_bash(RECORD_SETUP + r'''
debug_event() { printf 'debug: %s\n' "${1}"; }
demo_record_finish over
files=("${DATA_DIR}"/demos/*.demo)
demo_load "${files[0]}"
printf 'loaded %s\n' "${DEMO_HDR_PLACE[*]}"
''')
        self.assertEqual(output[-1], "loaded 1 2 3 0 0")

    def test_undecided_recording_names_no_places(self):
        text = self.recording(winner=-1)
        self.assertNotIn("place=", text)
        self.assertEqual(self.read_header(text)[-1], "ok -1 0 0 0 0 0")

    def test_older_format_is_refused_as_such(self):
        text = self.recording().replace("version=5\n", "version=4\n")
        output = self.read_header(text)
        self.assertEqual(output[-1], "refused 1")
        self.assertIn("format version 4", output[0])

    def test_places_that_do_not_add_up_are_refused(self):
        text = self.recording()
        cases = {
            "without winner": (text.replace("winner=0\n", ""),
                               "places without a winner"),
            "missing seat": (text.replace("place=2 3\n", ""),
                             "2 place lines for 3 players"),
            "seat twice": (text.replace("place=2 3\n", "place=1 3\n"),
                           "place slot 1 given twice"),
            "place twice": (text.replace("place=2 3\n", "place=2 2\n"),
                            "does not fit the session"),
            "beyond players": (text.replace("place=2 3\n", "place=2 4\n"),
                               "does not fit the session"),
            "not a seat": (text.replace("place=2 3\n", "place=3 3\n"),
                           "place slot 3 is not a seat"),
            "winner not first": (text.replace("place=0 1\nplace=1 2\n",
                                              "place=0 2\nplace=1 1\n"),
                                 "winner 0 does not hold place 1"),
            "place zero": (text.replace("place=2 3\n", "place=2 0\n"),
                           "bad place"),
        }
        for name, (changed, reason) in cases.items():
            with self.subTest(case=name):
                self.assertNotEqual(changed, text)
                output = self.read_header(changed)
                self.assertEqual(output[-1], "refused 0")
                self.assertIn(reason, output[0])

    def test_replay_end_shows_the_places_from_the_header(self):
        output = self.run_bash(REPLAY_SETUP + r'''
DEMO_ENDED=1
demo_finish_marks
render_pane_scoreboard
printf '%s\n' "${PANE_RIGHT[@]}"
''')
        self.assertEqual([line.rstrip() for line in output],
                         ["2.out     75", "3.alive   50"])

    def test_running_replay_keeps_provisional_standings(self):
        # Before the end, and at the end of a round nobody won.
        for ended, winner in ((0, 0), (1, -1)):
            with self.subTest(ended=ended, winner=winner):
                output = self.run_bash(REPLAY_SETUP + r'''
DEMO_ENDED="${2}"
DEMO_HDR_WINNER="${3}"
# The playback marks the end only when it gets there.
if [ "${DEMO_ENDED}" -eq 1 ]; then
    demo_finish_marks
fi
render_pane_scoreboard
printf '%s\n' "${PANE_RIGHT[@]}"
''', ended, winner)
                self.assertEqual([line.rstrip() for line in output],
                                 ["2.alive   50", "2.out     75"])

    def test_replay_end_box_names_the_place_of_a_standing_seat(self):
        output = self.run_bash(REPLAY_SETUP + r'''
DEMO_ENDED=1
demo_finish_marks
DEMO_FOCUS=2
demo_focus_outcome
printf '%s %s\n' "${DEMO_FOCUS_PLACE}" "${DEMO_FOCUS_END}"
''')
        self.assertEqual(output, ["3 end"])


if __name__ == "__main__":
    unittest.main()
