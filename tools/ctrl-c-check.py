#!/usr/bin/env python3
"""Check the Ctrl-C guard, hint repainting and terminal restoration.

Run with python3 tools/ctrl-c-check.py; unittest accepts -v and -h.
ROWHAMMER_CTRL_C_TEST_ROOT optionally selects another source tree.
Uses the real input and rendering modules with a controlled clock; the
terminal check uses an isolated pseudo-terminal, never the user's tty.

Program flow: load real modules, exercise key/timing and frame contracts,
then verify raw input and cleanup against saved pseudo-terminal settings.
Version: 1.0.0 (2026-10-24)
"""

import os
from pathlib import Path
import pty
import subprocess
import termios
import unittest


ROOT = Path(os.environ.get("ROWHAMMER_CTRL_C_TEST_ROOT",
                           Path(__file__).resolve().parent.parent))
SETUP = r'''
source "${1}/lib/input.sh"
source "${1}/lib/render.sh"
declare -A I18N=()
source "${1}/lib/lang/en.sh"
debug_event() { :; }
debug_input() { :; }
debug_frame() { :; }
die() { printf '%s\n' "$*" >&2; exit 1; }
TEST_MS=1000
now_ms() { NOW_MS="${TEST_MS}"; }
TERM_ACTIVE=1 TERM_TOO_SMALL=0 TERM_RESIZED=0 TERM_COLS=80 TERM_ROWS=24
LAYOUT_ROW=2 LAYOUT_COL=17 REDRAW_PENDING=0 REDRAW_KEEP_CLOCK=0
NET_LINK_UP=0 RENDER_MODE=partial KEY=""
'''


def bash(code, *, stdin=None, data=None):
    """Run under the game's strict flags with deterministic time."""
    return subprocess.run(
        ["bash", "-euo", "pipefail", "-c", SETUP + code,
         "ctrl-c-check", str(ROOT)],
        stdin=stdin, input=data, text=True, capture_output=True,
        timeout=5, check=False,
    )


class CtrlCChecks(unittest.TestCase):
    def test_single_press_is_not_a_text_key(self):
        result = bash(r'''
KEY_TEXT=1
key_feed $'\x03'
[ -z "${KEY}" ] && [ "${CTRL_C_COUNT}" -eq 1 ]
key_feed A
[ "${KEY}" = A ]
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Ctrl+C 2x", result.stdout)

    def test_singleplayer_window_boundary(self):
        for gap, expected in ((499, 130), (500, 130), (501, 0)):
            with self.subTest(gap=gap):
                result = bash(r'''
key_feed $'\x03'
TEST_MS=$(( TEST_MS + ''' + str(gap) + r''' ))
key_feed $'\x03'
[ "${CTRL_C_COUNT}" -eq 1 ]
''')
                self.assertEqual(result.returncode, expected, result.stderr)

    def test_multiplayer_needs_three_presses_in_lobby_and_round(self):
        for active in (0, 1):
            with self.subTest(active=active):
                result = bash(f"MP_ACTIVE={active}\n" + r'''
NET_LINK_UP=1
key_feed $'\x03'
TEST_MS=1400
key_feed $'\x03'
printf 'still running\n'
TEST_MS=1800
key_feed $'\x03'
printf 'unreachable\n'
''')
                self.assertEqual(result.returncode, 130, result.stderr)
                self.assertIn("Ctrl+C 3x", result.stdout)
                self.assertIn("still running", result.stdout)
                self.assertNotIn("unreachable", result.stdout)

    def test_hint_survives_full_partial_and_menu_frames(self):
        for mode, full in (("full", 0), ("partial", 0), ("partial", 1)):
            with self.subTest(mode=mode, full=full):
                result = bash(f"RENDER_MODE={mode}\n" + r'''
ctrl_c_press >/dev/null
for (( i = 0; i < LAYOUT_H; i++ )); do FRAME_LINES[i]=border; done
PREV_LINES=()
RENDER_FULL=''' + str(full) + r'''
render_flush
render_menu_frame menu
screen_write "${RENDER_MENU_FRAME}"
''')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.count("Ctrl+C 2x"), 2)
                self.assertTrue(result.stdout.endswith("\x1b[0m"))

    def test_hint_expiry_redraws_without_resetting_clocks(self):
        result = bash(r'''
ctrl_c_press >/dev/null
TEST_MS=2500
read_key
[ "${CTRL_C_HINT_UNTIL}" -eq 0 ]
[ "${REDRAW_PENDING}" -eq 1 ] && [ "${REDRAW_KEEP_CLOCK}" -eq 1 ]
screen_write after-expiry
''', data="a")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "after-expiry")

    def test_hint_is_suppressed_on_small_and_inactive_terminals(self):
        for state in ("TERM_TOO_SMALL=1", "TERM_ACTIVE=0"):
            with self.subTest(state=state):
                result = bash("ctrl_c_press >/dev/null\n" + state
                              + '\nscreen_write frame\n')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "frame")

    def test_multiplayer_hint_after_small_terminal_recovers(self):
        result = bash(r'''
NET_LINK_UP=1 TERM_TOO_SMALL=1
ctrl_c_press
TERM_TOO_SMALL=0
screen_write recovered
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Ctrl+C 3x", result.stdout)

    def test_hint_repositions_after_resize_and_matches_debug_log(self):
        result = bash(r'''
ctrl_c_press >/dev/null
TERM_COLS=100 LAYOUT_ROW=4
debug_frame() { [ "${1}" = "${EXPECTED}" ]; }
EXPECTED=$'frame\e[25;28H\e[7m To quit, press Ctrl+C 2x in quick succession \e[0m'
screen_write frame
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("\x1b[25;28H", result.stdout)

    def test_raw_ctrl_c_and_cleanup_restore_terminal(self):
        master, slave = pty.openpty()
        try:
            original = termios.tcgetattr(slave)
            # The subprocess gets a tty on stdin and a pipe on stdout,
            # allowing exact inspection of the final cleanup sequence.
            # Prequeue a real Ctrl-C only after raw mode has been set.
            proc = subprocess.Popen(
                ["bash", "-euo", "pipefail", "-c", SETUP + r'''
SAVED_STTY="$(stty -g)"
trap term_restore EXIT
term_input_raw
printf 'ready\n'
IFS= read -rsn1 -t 2 byte
[ "${byte}" = $'\x03' ]
key_feed "${byte}"
key_feed "${byte}"
''', "ctrl-c-check", str(ROOT)], stdin=slave,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            )
            try:
                self.assertEqual(proc.stdout.readline(), b"ready\n")
                raw = termios.tcgetattr(slave)
                self.assertEqual(raw[6][termios.VINTR], b"\x00")
                os.write(master, b"\x03")
                output, error = proc.communicate(timeout=5)
                self.assertEqual(proc.returncode, 130, error)
                self.assertTrue(output.endswith(b"\x1b[?1049l"), output)
                self.assertEqual(output.count(b"Ctrl+C 2x"), 1)
                self.assertEqual(termios.tcgetattr(slave), original)
            finally:
                if proc.poll() is None:
                    proc.kill()
                    proc.communicate()
        finally:
            os.close(master)
            os.close(slave)


if __name__ == "__main__":
    unittest.main()
