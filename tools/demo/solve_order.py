#!/usr/bin/env python3
"""Seed-selection helper (documents how the demo seeds were chosen).

For a fixed arrival order of four piece types it finds hard-drop
placements (rot, px) that build them into an exact 4x4 fill of the well in
cols 0-3 - i.e. a square. Run it to rediscover the silver seed used by the
demos (first four pieces = a distinct set {I,O,J,L} tiling a 4x4 -> silver).

Usage:
  python3 solve_order.py                 # scan seeds for a silver opening
  python3 solve_order.py I O L J         # solve one explicit order
"""
import sys
from sim import W, H, cells, EMPTY, probe_stream

REGION = {(x, y) for x in range(0, 4) for y in range(H - 4, H)}


def _can(board, t, rot, px, py):
    for cx, cy in cells(t, rot):
        x, y = px + cx, py + cy
        if x < 0 or x >= W or y < 0 or y >= H or board[y * W + x] != EMPTY:
            return False
    return True


def _drop(board, t, rot, px):
    if not _can(board, t, rot, px, 0):
        return None
    y = 0
    while _can(board, t, rot, px, y + 1):
        y += 1
    return y


def solve_order(types):
    """Return placements [(rot, px), ...] tiling the well in this exact
    piece order, or None."""
    n = len(types)
    board0 = [EMPTY] * (W * H)

    def rec(board, i, filled, acc):
        if i == n:
            return list(acc) if filled == REGION else None
        t = types[i]
        for rot in range(4):
            for px in range(-2, 4):
                py = _drop(board, t, rot, px)
                if py is None:
                    continue
                cs = [(px + cx, py + cy) for cx, cy in cells(t, rot)]
                cset = set(cs)
                if not cset <= REGION or cset & filled:
                    continue
                nb = board[:]
                for (x, y) in cs:
                    nb[y * W + x] = t
                acc.append((rot, px))
                r = rec(nb, i + 1, filled | cset, acc)
                if r is not None:
                    return r
                acc.pop()
        return None

    return rec(board0, 0, set(), [])


def scan_silver(limit=400):
    """Find seeds whose first four pieces are the distinct set {I,O,J,L}
    and tile a 4x4 in arrival order (a direct 4-piece silver square)."""
    target = set("IOJL")
    for seed in range(1, limit + 1):
        st = probe_stream(seed, 4)
        if set(st[:4]) != target:
            continue
        sol = solve_order(st[:4])
        if sol:
            yield seed, st[:4], sol


if __name__ == "__main__":
    if len(sys.argv) > 1:
        types = sys.argv[1:]
        print(types, "->", solve_order(types))
    else:
        for seed, types, sol in scan_silver():
            print(f"seed {seed}: {types} -> {sol}")
