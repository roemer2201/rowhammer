#!/usr/bin/env python3
"""Check corrected elapsed time and personal time after top-out.

Run with python3 tools/clock-check.py; unittest accepts -v and -h.
ROWHAMMER_CLOCK_TEST_ROOT optionally selects another source tree.
Uses the real Bash clock module and game-loop functions with controlled
wall/boot readers and transport adapters; never changes the system clock.
Since 1.1.0 it also checks that the repaint after the Ctrl-C hint
(REDRAW_KEEP_CLOCK) leaves the lock delay running, unlike a resize.

Version: 1.1.0 (2026-10-24)
"""

import os
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(os.environ.get("ROWHAMMER_CLOCK_TEST_ROOT",
                           Path(__file__).resolve().parent.parent))
ENTRY = (ROOT / "rowhammer.sh").read_text(encoding="ascii")


def function(name, source=ENTRY):
    """Extract the real function, including its top-level closing brace."""
    return re.search(r"^" + name + r"\(\) \{\n.*?^\}", source,
                     re.M | re.S).group(0) + "\n"


PLAY = "".join(function(n) for n in (
    "play_clock_tick", "play_clock_stop", "play_clock_resume",
    "round_clock_tick", "round_finish"))
STAMP = function("demo_stamp", (ROOT / "lib/demo.sh").read_text("ascii"))
MP_CLOCK = function("mp_round_ms", (ROOT / "lib/mp.sh").read_text("ascii"))
SETUP = r'''
source "${1}/lib/clock.sh"
debug_event() { :; }
die() { printf '%s\n' "$*" >&2; exit 1; }
clock_wall_source_init() { CLOCK_SRC=epochrealtime; }
TEST_WALL=1000000
TEST_LO=10000
TEST_HI=10000
TEST_READ=0
clock_wall_read() { CLOCK_WALL_MS="${TEST_WALL}"; }
clock_boot_read() {
    if [ "${TEST_READ}" -eq 0 ]; then
        CLOCK_BOOT_MS="${TEST_LO}"
        TEST_READ=1
    else
        CLOCK_BOOT_MS="${TEST_HI}"
        TEST_READ=0
    fi
}
clock_source_init
'''


def bash(code):
    """Execute with the same strict flags as the game."""
    return subprocess.run(["bash", "-euo", "pipefail", "-c", code,
                           "clock-check", str(ROOT)], text=True,
                          capture_output=True, timeout=10, check=False)


class ClockChecks(unittest.TestCase):
    def samples(self, readings, setup=SETUP):
        script = setup
        for wall, lo, hi in readings:
            script += (f"TEST_WALL={wall}; TEST_LO={lo}; TEST_HI={hi}\n"
                       "now_ms\n"
                       "printf '%s %s\\n' \"${NOW_MS}\" \"${CLOCK_OFFSET_MS}\"\n")
        result = bash(script)
        self.assertEqual(result.returncode, 0, result.stderr)
        return [tuple(map(int, line.split())) for line in result.stdout.splitlines()]

    def test_one_ms_steps_in_same_uptime_bucket(self):
        values = self.samples([(1000000 + n, 10000, 10000) for n in range(10)])
        self.assertEqual(values, [(1000000 + n, 0) for n in range(10)])

    def test_forward_backward_and_repeated_jumps(self):
        values = self.samples([(1500020, 10020, 10020),
                               (500040, 10040, 10040),
                               (2500060, 10060, 10060),
                               (2500061, 10060, 10060)])
        self.assertEqual([v[0] for v in values], [1000020, 1000040, 1000060, 1000061])

    def test_real_long_pause_is_elapsed_time(self):
        self.assertEqual(self.samples([(4600000, 3610000, 3610000)]), [(4600000, 0)])

    def test_descheduling_between_sample_reads(self):
        # Wall sampled somewhere inside a genuinely long boot interval.
        self.assertEqual(self.samples([(1000250, 10010, 10500),
                                       (1000500, 10500, 10500)]),
                         [(1000250, 0), (1000500, 0)])

    def test_improves_uncertain_startup_anchor(self):
        setup = SETUP.replace("TEST_HI=10000", "TEST_HI=10500")
        values = self.samples([(1000600, 10600, 10600),
                               (1500610, 10610, 10610)], setup)
        self.assertEqual(values[0], (1000600, 0))
        self.assertEqual(values[1][0], 1000610)

    def test_small_backward_step_never_subtracts_time(self):
        self.assertEqual([v[0] for v in self.samples([
            (1000008, 10000, 10000), (1000003, 10000, 10000),
            (1000009, 10000, 10000)])], [1000008, 1000008, 1000009])

    def test_small_changes_accumulate_against_anchor(self):
        values = self.samples([(1000010, 10000, 10000),
                               (1000020, 10000, 10000),
                               (1000030, 10000, 10000)])
        self.assertEqual([v[1] for v in values], [0, 0, 30])
        self.assertEqual([v[0] for v in values], [1000010, 1000020, 1000020])

    def test_real_debug_logging_does_not_reapply_correction(self):
        result = bash(SETUP + r'''
source "${1}/lib/debug.sh"
DEBUG_ACTIVE=1 DEBUG_T0_MS=1000000
exec 21>/dev/null
TEST_WALL=1500020 TEST_LO=10020 TEST_HI=10020
now_ms
[ "${NOW_MS}" -eq 1000020 ]
[ "${CLOCK_OFFSET_MS}" -eq 500000 ]
''')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_unavailable_control_clock_fails_closed(self):
        result = bash(SETUP + "clock_boot_read() { return 1; }\nnow_ms\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("/proc/uptime required", result.stderr)

    def test_startup_rejects_missing_uptime_and_unsupported_date(self):
        prefix = 'source "${1}/lib/clock.sh"\nunset EPOCHREALTIME\n'
        for output in ("1000000000N", "1000000000"):
            with self.subTest(output=output):
                code = prefix + ('date() { if [ "${1}" = +%s ]; then '
                                 'printf 1000000000; else '
                                 f'printf {output}; fi; }}\n')
                self.assertNotEqual(bash(code + 'clock_source_init\n').returncode, 0)
        result = bash(prefix + 'clock_boot_read() { return 1; }\nclock_source_init\n')
        self.assertNotEqual(result.returncode, 0)

    def test_stop_state_is_per_round(self):
        result = bash(r'''
source "${1}/lib/state.sh"
state_new 0
state_new 1
state_bind 0
PLAY_CLOCK_RUNNING=1
state_bind 1
PLAY_CLOCK_RUNNING=0
state_bind 0
[ "${PLAY_CLOCK_RUNNING}" -eq 1 ]
state_bind 1
[ "${PLAY_CLOCK_RUNNING}" -eq 0 ]
''')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_real_sources_and_date_fallback(self):
        for source in ("epochrealtime", "date"):
            with self.subTest(source=source):
                result = bash(r'''
source "${1}/lib/clock.sh"
die() { printf '%s\n' "$*" >&2; exit 1; }
debug_event() { :; }
clock_source_init
''' + f"CLOCK_SRC={source}\n" + r'''
previous="${NOW_MS}"
for (( i=0; i<20; i++ )); do
    now_ms
    (( NOW_MS >= previous ))
    previous="${NOW_MS}"
done
[ "${CLOCK_OFFSET_MS}" -eq 0 ]
''')
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_pause_and_resume_exclude_idle_time(self):
        result = bash(SETUP + PLAY + r'''
GAME_OVER=0 DEMO_PLAYING=0 PAUSED=0 LOCK_PENDING=1
PLAY_MS=0 PLAY_LAST=0 PLAY_CLOCK_RUNNING=0
play_clock_resume
TEST_WALL=1000100 TEST_LO=10100 TEST_HI=10100
play_clock_stop
PAUSED=1
TEST_WALL=1005100 TEST_LO=15100 TEST_HI=15100
play_clock_resume
play_clock_stop
[ "${PLAY_MS}" -eq 100 ]
PAUSED=0
play_clock_resume
[ "${TOUCHDOWN_MS}" -eq 1005100 ]
TEST_WALL=1005123 TEST_LO=15120 TEST_HI=15120
play_clock_tick
[ "${PLAY_MS}" -eq 123 ]
''')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_game_loop_topout_resize_and_end_keep_personal_time(self):
        for jump in (-3600000, 0, 3600000):
            with self.subTest(jump=jump):
                script = SETUP + PLAY + STAMP + MP_CLOCK + function("game_run")
                script += r'''
MP_ACTIVE=1 MP_MAX=3 MP_START_MS=1000000 DEMO_PLAYING=0 DEMO_MP=1
GAME_SUSPENDED=0 ROUND_RECORDED=0 MP_ENDED=0 MP_PLACE=2
LOCK_PENDING=0 PAUSED=0 DIRTY=0 REDRAW_PENDING=0 REDRAW_KEEP_CLOCK=0
GOAL_REACHED=0
CLEARED_TOTAL=0 ROW_CREDIT=0 LEVEL=1
mp_send_state() { :; }
mp_act_flush() { :; }
mp_send_topout() { :; }
mp_send_board() { :; }
mp_link_silent() { return 1; }
handle_key() { :; }
draw_frame() { DIRTY=0; }
game_reset() {
    GAME_MODE=versus GAME_OVER=0 PLAY_MS=0 PLAY_CLOCK_RUNNING=0
    play_clock_resume
    TEST_WALL=1010000 TEST_LO=20000 TEST_HI=20000
    GAME_OVER=1
    round_finish
}
TEST_PASS=0
read_key() {
    TEST_PASS=$(( TEST_PASS + 1 ))
    if [ "${TEST_PASS}" -eq 1 ]; then
        TEST_LO=70000 TEST_HI=70000
        TEST_WALL=$(( 1060000 + TEST_JUMP ))
        REDRAW_PENDING=1
    else
        TEST_LO=130000 TEST_HI=130000
        TEST_WALL=$(( 1120000 + TEST_JUMP ))
    fi
}
mp_poll() {
    if [ "${TEST_PASS}" -eq 2 ]; then MP_ENDED=1; fi
    return 0
}
record_round() {
    [ "${ROUND_RECORDED}" -eq 0 ] || return 0
    ROUND_RECORDED=1
    demo_stamp
    printf '%s %s\n' "${PLAY_MS}" "${DEMO_STAMP_MS}"
    GAME_EXIT=1
}
'''
                result = bash(script + f"TEST_JUMP={jump}\ngame_run versus\n")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), "10000 120000")

    def test_still_active_at_end_books_last_segment(self):
        result = bash(SETUP + PLAY + r'''
PLAY_MS=0 PLAY_LAST=1000000 PLAY_CLOCK_RUNNING=1
TEST_WALL=1060000 TEST_LO=70000 TEST_HI=70000
GAME_OVER=1
play_clock_stop
play_clock_stop
[ "${PLAY_MS}" -eq 60000 ]
''')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_singleplayer_stamp_stays_frozen(self):
        result = bash(SETUP + STAMP + r'''
DEMO_MP=0 PLAY_MS=10000 PLAY_LAST=1000000 PLAY_CLOCK_RUNNING=0
TEST_WALL=1060000 TEST_LO=70000 TEST_HI=70000
demo_stamp
[ "${DEMO_STAMP_MS}" -eq 10000 ]
''')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_new_round_restarts_a_stopped_clock(self):
        result = bash(SETUP + PLAY + function("game_reset") + r'''
GAME_EXIT=0 GAME_SUSPENDED=0 DEMO_PLAYING=0 PLAY_CLOCK_RUNNING=0
PLAY_MS=10000
board_init() { :; }
time_attack_budget() { :; }
demo_record_start() { :; }
update_speed() { :; }
spawn_piece() { :; }
FLOOD_INTERVAL_MS=7000
game_reset marathon
[ "${PLAY_MS}" -eq 0 ]
[ "${PLAY_CLOCK_RUNNING}" -eq 1 ]
''')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_singleplayer_jumps_do_not_expire_mode_or_lock_deadlines(self):
        for mode in ("sprint", "timeattack", "flood"):
            for jump in (-3600000, 3600000):
                with self.subTest(mode=mode, jump=jump):
                    script = SETUP + PLAY + function("game_run") + r'''
GAME_SUSPENDED=0 MP_ACTIVE=0 ROUND_RECORDED=0 DEMO_PLAYING=0
PAUSED=0 DIRTY=0 REDRAW_PENDING=0 REDRAW_KEEP_CLOCK=0 CLEAR_PENDING=0
GOAL_REACHED=0
CLEARED_TOTAL=0 ROW_CREDIT=0 LEVEL=1
LOCK_PENDING=1 LOCK_DELAY_MS=250 SPRINT_TIME_MS=180000
TIME_ATTACK_BUDGET_MS=60000 FLOOD_NEXT_MS=7000
handle_key() { :; }
draw_frame() { :; }
time_attack_budget() { :; }
# An unexpected timeout, flood rise or lock is a test failure.
sprint_time_up() { exit 9; }
time_attack_time_up() { exit 9; }
flood_raise() { exit 9; }
lock_and_next() { exit 9; }
round_event() { :; }
game_reset() {
    GAME_MODE="${1}" GAME_OVER=0 PLAY_MS=0 PLAY_CLOCK_RUNNING=0
    play_clock_resume
}
TEST_PASS=0
read_key() {
    TEST_PASS=$(( TEST_PASS + 1 ))
    TEST_LO=$(( 10000 + TEST_PASS * 20 ))
    TEST_HI="${TEST_LO}"
    TEST_WALL=$(( 1000000 + TEST_PASS * 20 ))
    if [ "${TEST_PASS}" -ge 2 ]; then
        TEST_WALL=$(( TEST_WALL + TEST_JUMP ))
    fi
    if [ "${TEST_PASS}" -eq 3 ]; then GAME_EXIT=1; fi
}
record_round() { printf '%s\n' "${PLAY_MS}"; }
'''
                    result = bash(script + f"TEST_JUMP={jump}\ngame_run {mode}\n")
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout.strip(), "60")

    def test_ctrl_c_hint_repaint_keeps_lock_delay(self):
        # A resting piece touched down at 1000000 with 250 ms lock delay;
        # each pass advances 150 ms and the first one raises a repaint.
        # The hint repaint (REDRAW_KEEP_CLOCK=1) must not restart the
        # delay, so the piece locks on pass 2 (300 ms); a resize repaint
        # restamps the touchdown to pass 1 and the lock moves to pass 3.
        for keep, expect in ((1, "locked 2"), (0, "locked 3")):
            with self.subTest(keep=keep):
                script = SETUP + PLAY + function("game_run") + r'''
GAME_SUSPENDED=0 MP_ACTIVE=0 ROUND_RECORDED=0 DEMO_PLAYING=0
PAUSED=0 DIRTY=0 REDRAW_PENDING=0 REDRAW_KEEP_CLOCK=0 CLEAR_PENDING=0
GOAL_REACHED=0 CLEARED_TOTAL=0 ROW_CREDIT=0 LEVEL=1
LOCK_PENDING=1 LOCK_DELAY_MS=250 CUR_X=4 CUR_Y=18
handle_key() { :; }
draw_frame() { :; }
round_event() { :; }
lock_and_next() { printf 'locked %s\n' "${TEST_PASS}"; GAME_EXIT=1; }
game_reset() {
    GAME_MODE="${1}" GAME_OVER=0 PLAY_MS=0 PLAY_CLOCK_RUNNING=0
    play_clock_resume
}
TEST_PASS=0
read_key() {
    TEST_PASS=$(( TEST_PASS + 1 ))
    TEST_WALL=$(( 1000000 + TEST_PASS * 150 ))
    TEST_LO=$(( 10000 + TEST_PASS * 150 ))
    TEST_HI="${TEST_LO}"
    if [ "${TEST_PASS}" -eq 1 ]; then
        REDRAW_PENDING=1
        REDRAW_KEEP_CLOCK="${TEST_KEEP}"
    fi
    if [ "${TEST_PASS}" -ge 5 ]; then GAME_EXIT=1; fi
}
record_round() { :; }
'''
                result = bash(script + f"TEST_KEEP={keep}\ngame_run marathon\n")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), expect)


if __name__ == "__main__":
    unittest.main()
