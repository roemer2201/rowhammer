#!/usr/bin/env python3
"""Scenario planners. Each returns an ACTIONS list where every action is
either 'H' (a hold-swap, no drop) or a (rot, px) hard-drop of the current
piece. Everything is verified purely in the sim; record.py then replays it
in the real bash game and confirms the payoff via events.log.

Seed choice (see solve_order.py / the notes in each planner):
  silver seed 121 - first four pieces are I,O,L,J and tile a 4x4 directly
  tetris seed 13  - shortest clean 9-wide wall + I-well found by scan
  gold   seed 16  - shortest, lowest-stacking four-O build found by scan
"""
from sim import Game, H
from plan import col_heights, count_holes, best_flat


def heights(g, cols):
    top = col_heights(g, cols)
    return {x: H - top[x] for x in cols}


def apply(g, actions):
    for a in actions:
        if a == 'H':
            g.do_hold()
        else:
            g.place(a[0], a[1])


def plan_silver(stream):
    """Four distinct pieces (I,O,L,J) tiling a 4x4 in cols 0-3 -> silver.
    The tiling was found with solve_order.py for the seed-121 opening."""
    acts = [(0, 0), (0, 0), (3, 2), (1, -1)]     # I0, O0, L3, J1
    g = Game(stream)
    apply(g, acts)
    if g.silver != 1 or g.gold != 0 or any(r['cleared'] for r in g.log):
        return None
    return g, acts, g.log[-1]


def plan_tetris(stream, maxsteps=40):
    """Fill cols 0-8 hole-free to height >= 4 (col 9 stays the well), then
    drop a vertical I into col 9 to clear four rows. An I is reserved via
    hold and deployed at the end."""
    g = Game(stream)
    acts = []
    wall = list(range(9))
    held = False
    ok = False
    for _ in range(maxsteps):
        hs = heights(g, wall)
        if min(hs.values()) >= 4 and count_holes(g, wall) == 0:
            ok = True
            break
        t = g.cur
        if t == 'I' and not held:
            g.do_hold(); acts.append('H'); held = True
            continue
        bf = best_flat(g, t, wall)
        if bf is None:
            return None
        g.place(bf[0], bf[1]); acts.append(bf)
        if any(r['cleared'] for r in g.log):
            return None
    if not ok:
        return None
    if held:
        g.do_hold(); acts.append('H')
    if g.cur != 'I':
        return None
    r = g.place(1, 7)                # I vertical, cells land in col 9
    acts.append((1, 7))
    if r['cleared'] != 4:
        return None
    return g, acts, r


def plan_gold(stream, maxsteps=80):
    """Four O pieces stacked into cols 0-3 form a gold square; every other
    piece is dumped hole-tolerantly into cols 4-8. Col 9 is left empty so
    no row ever completes -> no line clear cuts the O instances before the
    square forms (a clear would disqualify them)."""
    g = Game(stream)
    acts = []
    dump = list(range(4, 9))                     # cols 4..8; col 9 = empty well
    o_targets = [(0, -1), (0, 1), (0, -1), (0, 1)]
    oi = 0
    for _ in range(maxsteps):
        if g.gold >= 1:
            break
        t = g.cur
        if t == 'O' and oi < 4:
            rot, px = o_targets[oi]; oi += 1
            r = g.place(rot, px); acts.append((rot, px))
        else:
            bf = best_flat(g, t, dump, allow_holes=True)
            if bf is None:
                return None
            r = g.place(bf[0], bf[1]); acts.append(bf)
        if r['cleared']:
            return None
    if g.gold < 1:
        return None
    return g, acts, g.log[-1]


PLANS = {"silver": plan_silver, "tetris": plan_tetris, "gold": plan_gold}
