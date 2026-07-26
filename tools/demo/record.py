#!/usr/bin/env python3
"""Turn a verified plan into timed keystrokes, drive the real bash game and
record its .cast (see driver.py). Playable scenarios are checked against
the game's own events.log so a recording can never silently drift from what
the game actually did."""
import os, re
import sim, planner, driver
from driver import K
import paths


def steps_for(acts, key_gap=0.09, settle=0.42, tail=1.4, predrop=1.3):
    """Menu intro, then one piece per action; the final piece is positioned,
    paused for a beat, then dropped so the payoff is not instantaneous."""
    S = [(1.2, None), (0.5, K["enter"]), (0.5, K["enter"]), (0.8, None)]
    for i, a in enumerate(acts):
        last = (i == len(acts) - 1)
        ks = ["hold"] if a == "H" else sim.keys_for(a[0], a[1])
        if last and ks and ks[-1] == "hard":
            for k in ks[:-1]:
                S.append((key_gap, K[k]))
            S.append((predrop, None))
            S.append((key_gap, K["hard"]))
        else:
            for k in ks:
                S.append((key_gap, K[k]))
        S.append((settle, None))
    S.append((tail, None))
    # quit path (rendered/trimmed away, but leaves the game in a clean exit)
    S += [(0.5, K["quit"]), (0.5, K["down"]), (0.4, K["down"]),
          (0.5, K["enter"]), (1.2, None),
          (0.5, K["enter"]), (0.5, K["back"]), (0.5, K["back"])]
    return S


def verify(dbg_dir, patterns):
    """True iff every required pattern appears in the game's events.log."""
    log = open(os.path.join(dbg_dir, "events.log")).read()
    missing = [p for p in patterns if not re.search(p, log)]
    # A blocked spawn (top-out) means a live keystroke glitched mid-run.
    topout = "blocked - game over" in log
    if missing or topout:
        why = "top-out" if topout else f"missing {missing}"
        print(f"  verify  FAIL ({why})")
        return False
    for p in patterns:
        print(f"  verify  ok: {re.search(p, log).group(0)[:64]}")
    return True


def record_play(name, cfg, attempts=6):
    """Record a playable scenario (silver/tetris/gold), retrying until the
    game's events.log confirms the payoff. Live recording of a long piece
    sequence glitches now and then, so a few retries make it reliable."""
    stream = sim.probe_stream(cfg["seed"], 90)
    res = planner.PLANS[cfg["plan"]](stream)
    if not res:
        raise SystemExit(f"planner failed for {name}")
    g, acts, r = res
    print(f"[{name}] seed={cfg['seed']} actions={len(acts)} "
          f"payoff={r.get('square') or r.get('cleared')}")
    steps = steps_for(acts, settle=cfg.get("settle", 0.42),
                      tail=cfg.get("tail", 1.4), predrop=cfg.get("predrop", 1.3))
    data_dir = os.path.join(paths.BUILD_DIR, f"data_{name}")
    dbg_dir = os.path.join(paths.BUILD_DIR, f"dbg_{name}")
    cast = os.path.join(paths.BUILD_DIR, f"{name}.cast")
    for att in range(1, attempts + 1):
        os.system(f"rm -rf {data_dir!r} {dbg_dir!r}")
        driver.run(seed=cfg["seed"], steps=steps, out_cast=cast,
                   data_dir=data_dir, debug_dir=dbg_dir,
                   title=f"rowhammer - {name}")
        if verify(dbg_dir, cfg["verify"]):
            print(f"  cast(raw) {os.path.basename(cast)} (attempt {att})")
            return cast
        print(f"  retry {name} ({att}/{attempts})")
    raise SystemExit(f"{name}: no clean take after {attempts} attempts")


def record_wonder(name, cfg):
    """Record the world-wonder screen from a pre-seeded savegame (no play)."""
    data_dir = os.path.join(paths.BUILD_DIR, f"data_{name}")
    cast = os.path.join(paths.BUILD_DIR, f"{name}.cast")
    os.system(f"rm -rf {data_dir!r}")
    os.makedirs(data_dir, exist_ok=True)
    with open(os.path.join(data_dir, "save"), "w") as f:
        f.write(f"total_rows={cfg['save_total']}\n")
    steps = [(1.6, None)]
    steps += [(0.6, K["down"])] * cfg["menu_down"]        # move to Weltwunder
    steps += [(0.6, K["enter"]), (4.5, None)]             # open + admire, then end
    print(f"[{name}] save total_rows={cfg['save_total']}")
    driver.run(seed=cfg["seed"], steps=steps, out_cast=cast,
               data_dir=data_dir, debug_dir=os.path.join(paths.BUILD_DIR, "dbg_wonder"),
               title=f"rowhammer - {name}", debug=False)
    print(f"  cast(raw) {os.path.basename(cast)}")
    return cast
