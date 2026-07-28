#!/usr/bin/env python3
"""Trim a recorded .cast so it ends shortly after the payoff, dropping the
quit navigation (and, for debug runs, the debug-path print) while keeping
the intro. The result plays cleanly with `asciinema play`."""
import json
import pyte


def trim(src, dst, end_text, hold=2.5):
    with open(src) as f:
        header = json.loads(f.readline())
        events = [json.loads(l) for l in f if l.strip()]
    screen = pyte.Screen(header["width"], header["height"])
    stream = pyte.Stream(screen)
    end_idx = None
    for i, (t, _, data) in enumerate(events):
        stream.feed(data)
        text = "\n".join("".join(c.data for c in screen.buffer[y].values())
                         for y in range(header["height"]))
        if end_text in text:
            end_idx = i
            break
    if end_idx is None:
        raise SystemExit(f"end_text {end_text!r} not found in {src}")
    kept = events[:end_idx + 1]
    kept.append([round(kept[-1][0] + hold, 6), "o", ""])   # hold last frame
    with open(dst, "w") as f:
        f.write(json.dumps(header) + "\n")
        for ev in kept:
            f.write(json.dumps(ev) + "\n")
    import os
    print(f"  cast {os.path.basename(dst)}: {len(kept)} events, "
          f"{kept[-1][0]:.1f}s")
