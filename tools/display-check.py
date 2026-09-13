#!/usr/bin/env python3
"""Check full-screen frame-rate parsing and recovery from clock jumps.

Run with python3 tools/display-check.py; unittest accepts -v and -h.
ROWHAMMER_DISPLAY_TEST_ROOT optionally selects another source tree.
The parser is taken from the entry point, and the real display loop and
simulation run with deterministic clock, input and output adapters.
No terminal or third-party modules are needed.

Version: 1.0.0 (2026-09-13)
"""

import os
from pathlib import Path
import subprocess
import unittest


ROOT = Path(os.environ.get("ROWHAMMER_DISPLAY_TEST_ROOT",
                           Path(__file__).resolve().parent.parent))
ENTRY = (ROOT / "rowhammer.sh").read_text(encoding="ascii")
FPS_CHECK = ENTRY.split("# 120 is the upper end", 1)[1].split(
    "# Multiplayer options.", 1
)[0]
# Restore the first comment line after cutting at its marker.
FPS_CHECK = "# 120 is the upper end" + FPS_CHECK


def bash(code, *args):
    """Run source checks with the same strict shell flags as the game."""
    return subprocess.run(
        ["bash", "-euo", "pipefail", "-c", code, "display-check", *args],
        text=True, capture_output=True, timeout=5, check=False,
    )


class DisplayChecks(unittest.TestCase):
    def test_decimal_frame_rates(self):
        for value in ("1", "001", "08", "009", "010", "015", "099", "120"):
            with self.subTest(value=value):
                result = bash(
                    'SCRIPT_NAME=rowhammer.sh\nSCREENSAVER_FPS="${1}"\n'
                    + FPS_CHECK
                    + '\nprintf "%s %s\\n" "${SCREENSAVER_FPS}" '
                      '"$(( 1000 / SCREENSAVER_FPS ))"\n', value,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                fps = int(value)
                self.assertEqual(result.stdout.strip(), f"{fps} {1000 // fps}")

    def test_invalid_frame_rates(self):
        for value in ("", "0", "000", "121", "999", "1000", "-1",
                      "+8", "1.5", "1+1", "abc"):
            with self.subTest(value=value):
                result = bash(
                    'SCRIPT_NAME=rowhammer.sh\nSCREENSAVER_FPS="${1}"\n'
                    + FPS_CHECK, value,
                )
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn("expects a frame rate in 1..120", result.stderr)

    def run_clock(self, times):
        result = bash(r'''
source "${1}/lib/screensaver.sh"
SCREENSAVER_FPS=15
TICK_S=0.020
REDRAW_PENDING=0
TEST_TIME=100000
TEST_TICK=0
shift
TEST_TIMES=("$@")
now_ms() { NOW_MS="${TEST_TIME}"; }
debug_event() { :; }
screensaver_colors_init() { :; }
screensaver_geometry() { :; }
read_key() {
    KEY=""
    if [ "${TEST_TICK}" -ge "${#TEST_TIMES[@]}" ]; then
        KEY=q
        return 0
    fi
    TEST_TIME="${TEST_TIMES[TEST_TICK]}"
    TEST_TICK=$(( TEST_TICK + 1 ))
}
screensaver_draw() {
    printf '%s %s\n' "${NOW_MS}" "${SS_CLOCK_MS}"
}
screensaver_run
[ "${TICK_S}" = 0.020 ]
''', str(ROOT), *(str(value) for value in times))
        self.assertEqual(result.returncode, 0, result.stderr)
        return [tuple(map(int, line.split()))
                for line in result.stdout.splitlines()]

    def test_normal_deadlines(self):
        self.assertEqual(self.run_clock([100010, 100030, 100066, 100131, 100132]),
                         [(100010, 10), (100066, 66), (100132, 132)])

    def test_backward_jump_recovers_immediately(self):
        self.assertEqual(self.run_clock([100010, 90000, 90020, 90066]),
                         [(100010, 10), (90000, 10), (90066, 76)])

    def test_backward_jump_between_frames(self):
        # 100030 is still newer than the last simulation update, but is
        # older than the preceding input tick. It must rebase the deadline.
        self.assertEqual(self.run_clock([100010, 100050, 100030, 100096]),
                         [(100010, 10), (100030, 10), (100096, 76)])

    def test_repeated_backward_jumps(self):
        self.assertEqual(self.run_clock([100010, 90000, 80000, 80066]),
                         [(100010, 10), (90000, 10), (80000, 10), (80066, 76)])

    def test_forward_jump_keeps_existing_delta_cap(self):
        self.assertEqual(self.run_clock([100010, 120000, 120066]),
                         [(100010, 10), (120000, 510), (120066, 576)])


if __name__ == "__main__":
    unittest.main()
