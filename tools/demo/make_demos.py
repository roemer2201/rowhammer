#!/usr/bin/env python3
"""Regenerate every demo clip end to end:

  record (real game, verified via events.log)  ->  build/<name>.cast
  render GIF (trim menu intro, end on payoff)   ->  docs/demo/<name>.gif
  trim  cast (keep intro, drop quit/tail)        ->  docs/demo/<name>.cast

Usage:
  python3 tools/demo/make_demos.py [name ...]     # default: all four

Requires pyte and Pillow (see requirements.txt). asciinema is optional
(only for playing the resulting .cast files).
"""
import os, sys
import paths
import record
import render
import trim

# One spec per clip drives all three stages.
#   play scenarios: seed + planner + recording pace + render/trim markers
#   wonder:         a pre-seeded savegame and menu navigation
# The start/end markers are matched against the rendered screen, so they
# have to spell the HUD exactly. Since 0.26.0 the counters sit in the
# left pane as "<label><value right aligned in 5>" and the player name
# is gone from the play screen, which is why "Hold" (the pane heading,
# unique to the play screen) marks the start now.
SCEN = {
    "tetris": dict(kind="play", seed=13, plan="tetris",
                   settle=0.42, tail=1.4, predrop=1.3,
                   start_text="Hold", end_text="Lines     4",
                   speed=1.1, hold=1.8,
                   verify=[r"cleared 4 row", r"credit=\+5"]),
    "silver": dict(kind="play", seed=121, plan="silver",
                   settle=0.5, tail=1.6, predrop=1.3,
                   start_text="Hold", end_text="Silver    1",
                   speed=1.0, hold=1.8,
                   verify=[r"silver square formed"]),
    "gold":   dict(kind="play", seed=16, plan="gold",
                   settle=0.30, tail=1.8, predrop=1.3,
                   start_text="Hold", end_text="Gold      1",
                   speed=1.5, hold=1.8,
                   verify=[r"gold square formed"]),
    "wonder": dict(kind="wonder", seed=7, save_total=690, menu_down=3,
                   stop_text="written to", cast_end="Baustufe",
                   speed=1.0, hold=2.0),
}


def build(name):
    cfg = SCEN[name]
    os.makedirs(paths.BUILD_DIR, exist_ok=True)
    os.makedirs(paths.DEMO_DIR, exist_ok=True)
    gif = os.path.join(paths.DEMO_DIR, f"{name}.gif")
    cast_out = os.path.join(paths.DEMO_DIR, f"{name}.cast")
    if cfg["kind"] == "play":
        raw = record.record_play(name, cfg)
        render.render(raw, gif, start_text=cfg["start_text"],
                      end_text=cfg["end_text"], speed=cfg["speed"],
                      hold=cfg["hold"])
        trim.trim(raw, cast_out, cfg["end_text"])
    else:
        raw = record.record_wonder(name, cfg)
        render.render(raw, gif, stop_text=cfg["stop_text"],
                      speed=cfg["speed"], hold=cfg["hold"])
        trim.trim(raw, cast_out, cfg["cast_end"])


if __name__ == "__main__":
    names = sys.argv[1:] or ["tetris", "silver", "gold", "wonder"]
    for n in names:
        if n not in SCEN:
            raise SystemExit(f"unknown clip {n!r}; choose from {list(SCEN)}")
        build(n)
    print("done ->", paths.DEMO_DIR)
