#!/usr/bin/env python3
"""Greedy placement helpers on top of the sim: pack pieces into a column
range for the Tetris wall and the gold-square dump area."""
from sim import W, H, cells, EMPTY


def col_heights(g, cols):
    """Topmost filled y per column (H when the column is empty)."""
    h = {}
    for x in cols:
        top = H
        for y in range(H):
            if g.b[y * W + x] != EMPTY:
                top = y
                break
        h[x] = top
    return h


def count_holes(g, cols):
    n = 0
    for x in cols:
        seen = False
        for y in range(H):
            if g.b[y * W + x] != EMPTY:
                seen = True
            elif seen:
                n += 1
    return n


def _options(g, t, cols):
    """All (rot, px) whose cells stay inside `cols` and are placeable."""
    out = []
    cset = set(cols)
    for rot in range(4):
        for px in range(-2, W):
            py = g.drop_y(t, rot, px)
            if py is None:
                continue
            cs = [(px + cx, py + cy) for cx, cy in cells(t, rot)]
            if all(x in cset for (x, y) in cs):
                out.append((rot, px, cs))
    return out


def best_flat(g, t, cols, allow_holes=False):
    """Pick a placement minimizing (new holes, tallest column, bumpiness).
    With allow_holes=False a hole-creating placement is rejected (Tetris
    wall must stay hole-free); with allow_holes=True holes are only a
    tie-breaker (the gold dump never clears, so its holes are harmless).
    Returns (rot, px) or None."""
    base_holes = count_holes(g, cols)
    best = None
    for rot, px, cs in _options(g, t, cols):
        nb = g.b[:]
        for (x, y) in cs:
            nb[y * W + x] = t
        nh = _holes(nb, cols)
        if (not allow_holes) and nh > base_holes:
            continue
        hs = _heights(nb, cols)
        height = H - min(hs.values())       # tallest filled column
        bump = _bump(hs, cols)
        key = (nh, height, bump)
        if best is None or key < best[0]:
            best = (key, rot, px)
    return None if best is None else (best[1], best[2])


def _heights(b, cols):
    h = {}
    for x in cols:
        top = H
        for y in range(H):
            if b[y * W + x] != EMPTY:
                top = y
                break
        h[x] = top
    return h


def _holes(b, cols):
    n = 0
    for x in cols:
        seen = False
        for y in range(H):
            if b[y * W + x] != EMPTY:
                seen = True
            elif seen:
                n += 1
    return n


def _bump(hs, cols):
    cl = sorted(cols)
    return sum(abs(hs[cl[i]] - hs[cl[i + 1]]) for i in range(len(cl) - 1))
