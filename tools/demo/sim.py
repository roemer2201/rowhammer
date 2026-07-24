#!/usr/bin/env python3
"""Faithful re-implementation of rowhammer's board rules for offline
planning. Mirrors lib/board.sh, lib/squares.sh and the spawn / hard-drop /
hold logic in rowhammer.sh. It is used only to design keystroke plans; the
real bash game is always the ground truth (each recording is verified
against the game's own events.log, see record.py)."""
import subprocess
import paths

W, H = 10, 22
EMPTY = "."

# SRS cell layout copied verbatim from lib/pieces.sh (PIECE_SHAPE).
SHAPE = {
    "I0": "0,1 1,1 2,1 3,1", "I1": "2,0 2,1 2,2 2,3",
    "I2": "0,2 1,2 2,2 3,2", "I3": "1,0 1,1 1,2 1,3",
    "O0": "1,0 2,0 1,1 2,1", "O1": "1,0 2,0 1,1 2,1",
    "O2": "1,0 2,0 1,1 2,1", "O3": "1,0 2,0 1,1 2,1",
    "T0": "1,0 0,1 1,1 2,1", "T1": "1,0 1,1 2,1 1,2",
    "T2": "0,1 1,1 2,1 1,2", "T3": "1,0 0,1 1,1 1,2",
    "S0": "1,0 2,0 0,1 1,1", "S1": "1,0 1,1 2,1 2,2",
    "S2": "1,1 2,1 0,2 1,2", "S3": "0,0 0,1 1,1 1,2",
    "Z0": "0,0 1,0 1,1 2,1", "Z1": "2,0 1,1 2,1 1,2",
    "Z2": "0,1 1,1 1,2 2,2", "Z3": "1,0 0,1 1,1 0,2",
    "J0": "0,0 0,1 1,1 2,1", "J1": "1,0 2,0 1,1 1,2",
    "J2": "0,1 1,1 2,1 2,2", "J3": "1,0 1,1 0,2 1,2",
    "L0": "2,0 0,1 1,1 2,1", "L1": "1,0 1,1 1,2 2,2",
    "L2": "0,1 1,1 2,1 0,2", "L3": "0,0 1,0 1,1 1,2",
}
# Row credit values copied from lib/squares.sh (ROWS_*).
ROWS_NORMAL, ROWS_SILVER, ROWS_GOLD, ROWS_TETRIS = 1, 5, 10, 1


def cells(t, rot):
    return [tuple(int(v) for v in c.split(","))
            for c in SHAPE[t + str(rot)].split()]


def probe_stream(seed, n=80):
    """The exact piece stream a run with --seed SEED draws (via the game's
    own randomizer, see probe_pieces.sh)."""
    out = subprocess.check_output(
        ["bash", paths.PROBE, str(seed), str(n)], text=True)
    return out.split()


class Game:
    """Minimal board model. place(rot, px) hard-drops the current piece and
    returns what happened (square formed, rows cleared, credit)."""

    def __init__(self, stream):
        self.b = [EMPTY] * (W * H)
        self.id = [0] * (W * H)
        self.sq = [""] * (W * H)
        self.cut = set()
        self.squared = set()
        self.next_id = 1
        self.stream = stream
        self.si = 0
        self.hold = ""
        self.gold = 0
        self.silver = 0
        self.lines = 0
        self.credit = 0
        self.cur = self.stream[self.si]; self.si += 1
        self.log = []

    def can_place(self, t, rot, px, py):
        for cx, cy in cells(t, rot):
            x, y = px + cx, py + cy
            if x < 0 or x >= W or y < 0 or y >= H:
                return False
            if self.b[y * W + x] != EMPTY:
                return False
        return True

    def drop_y(self, t, rot, px):
        if not self.can_place(t, rot, px, 0):
            return None
        y = 0
        while self.can_place(t, rot, px, y + 1):
            y += 1
        return y

    def _spawn(self):
        self.cur = self.stream[self.si]; self.si += 1

    def do_hold(self):
        if self.hold == "":
            self.hold = self.cur
            self._spawn()
        else:
            self.cur, self.hold = self.hold, self.cur

    def place(self, rot, px, hold=False):
        if hold:
            self.do_hold()
        t = self.cur
        py = self.drop_y(t, rot, px)
        if py is None:
            raise RuntimeError(f"cannot place {t} rot={rot} px={px} (blocked)")
        pid = self.next_id; self.next_id += 1
        for cx, cy in cells(t, rot):
            idx = (py + cy) * W + (px + cx)
            self.b[idx] = t
            self.id[idx] = pid
        sqr = self._detect_square(px, py)
        cl, cr = self._clear_lines()
        if cl:
            self.lines += cl
            self.credit += cr
        res = dict(type=t, rot=rot, px=px, py=py, id=pid,
                   square=sqr, cleared=cl, credit=cr)
        self.log.append(res)
        self._spawn()
        return res

    def _square_at(self, x0, y0):
        ids = {}
        for y in range(y0, y0 + 4):
            for x in range(x0, x0 + 4):
                idx = y * W + x
                if self.b[idx] == EMPTY:
                    return None
                i = self.id[idx]
                if i == 0 or i in self.cut or i in self.squared:
                    return None
                ids[i] = 1
                if len(ids) > 4:
                    return None
        if len(ids) != 4:
            return None
        t0 = self.b[y0 * W + x0]
        mark = "G"
        for y in range(y0, y0 + 4):
            for x in range(x0, x0 + 4):
                if self.b[y * W + x] != t0:
                    mark = "S"
        for y in range(y0, y0 + 4):
            for x in range(x0, x0 + 4):
                self.sq[y * W + x] = mark
        for i in ids:
            self.squared.add(i)
        return mark

    def _detect_square(self, lx, ly):
        x_min = max(0, lx - 3); x_max = min(W - 4, lx + 3)
        y_min = max(0, ly - 3); y_max = min(H - 4, ly + 3)
        for y0 in range(y_min, y_max + 1):
            for x0 in range(x_min, x_max + 1):
                m = self._square_at(x0, y0)
                if m:
                    if m == "G":
                        self.gold += 1
                    else:
                        self.silver += 1
                    return m
        return None

    def _clear_lines(self):
        cleared = credit = 0
        nb = [EMPTY] * (W * H)
        nid = [0] * (W * H)
        nsq = [""] * (W * H)
        write_y = H - 1
        for y in range(H - 1, -1, -1):
            full = all(self.b[y * W + x] != EMPTY for x in range(W))
            if full:
                cleared += 1
                g = s = 0
                for x in range(W):
                    idx = y * W + x
                    if self.sq[idx] == "G":
                        g += 1
                    elif self.sq[idx] == "S":
                        s += 1
                    if self.id[idx] != 0:
                        self.cut.add(self.id[idx])
                credit += ROWS_NORMAL + ROWS_GOLD * (g // 4) + ROWS_SILVER * (s // 4)
            else:
                for x in range(W):
                    src = y * W + x
                    dst = write_y * W + x
                    nb[dst] = self.b[src]
                    nid[dst] = self.id[src]
                    nsq[dst] = self.sq[src]
                write_y -= 1
        self.b, self.id, self.sq = nb, nid, nsq
        if cleared == 4:
            credit += ROWS_TETRIS
        return cleared, credit

    def show(self, top=2):
        rows = []
        for y in range(top, H):
            line = "".join(self.b[y * W + x] for x in range(W))
            sql = "".join(self.sq[y * W + x] or "." for x in range(W))
            rows.append(f"{y:2d} |{line}| {sql}")
        return "\n".join(rows)


def keys_for(rot, px):
    """Keystroke names to reach (rot, px) from the spawn (x=3, rot=0) then
    hard-drop. Valid while the spawn rows on the slide path are clear (the
    demo builds keep them clear); rotations kick 0 at the empty spawn area."""
    seq = []
    if rot == 1:
        seq += ["cw"]
    elif rot == 2:
        seq += ["cw", "cw"]
    elif rot == 3:
        seq += ["ccw"]
    dx = px - 3
    seq += (["right"] * dx) if dx > 0 else (["left"] * (-dx))
    seq += ["hard"]
    return seq
