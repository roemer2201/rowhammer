#!/usr/bin/env python3
"""Drive rowhammer.sh inside a pty, feed timed keystrokes and record an
asciinema v2 .cast file. With debug=True the game also writes its
events.log, which record.py parses to confirm each scenario really
happened in the real game (the sim is only a planner)."""
import os, pty, fcntl, termios, struct, select, time, json, signal, errno
import paths

# symbolic key name -> byte(s). Letters map to the game's default bindings;
# ENTER is a carriage return (ICRNL maps it to the read delimiter).
K = {"left": "a", "right": "d", "cw": "e", "ccw": "q", "soft": "s",
     "hard": " ", "hold": "c", "quit": "x", "up": "w", "down": "s",
     "enter": "\r", "back": "x"}


def run(seed, steps, out_cast, data_dir, debug_dir,
        rows=24, cols=58, color_mode="extended", title="rowhammer",
        name="DEMO", debug=True, idle_tail=1.5):
    """steps: list of (delay_seconds, data_or_None). delay is waited BEFORE
    sending data; data None is a pure pause (recorded as idle time)."""
    os.makedirs(data_dir, exist_ok=True)
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    env["COLORTERM"] = "truecolor"
    env["LINES"] = str(rows)
    env["COLUMNS"] = str(cols)
    args = [paths.GAME, "--seed", str(seed), "--color-mode", color_mode,
            "--data-dir", data_dir, "--name", name]
    if debug:
        args += ["--debug", "--debug-dir", debug_dir]

    pid, fd = pty.fork()
    if pid == 0:                                   # child
        os.execve("/bin/bash", ["bash"] + args, env)
        os._exit(127)

    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))

    events = []
    t0 = time.monotonic()

    def drain(timeout):
        try:
            r, _, _ = select.select([fd], [], [], timeout)
        except select.error:
            return True
        if r:
            try:
                data = os.read(fd, 65536)
            except OSError as e:
                if e.errno == errno.EIO:
                    return False                   # child closed the pty
                raise
            if not data:
                return False
            events.append([round(time.monotonic() - t0, 6), "o",
                           data.decode("utf-8", "replace")])
        return True

    alive = True
    for delay, data in steps:
        end = time.monotonic() + delay
        while time.monotonic() < end:
            if not drain(min(0.02, end - time.monotonic())):
                alive = False
                break
        if not alive:
            break
        if data is not None:
            try:
                os.write(fd, data.encode("latin-1"))
            except OSError:
                break

    end = time.monotonic() + idle_tail
    while time.monotonic() < end:
        if not drain(0.05):
            break
    try:
        os.kill(pid, signal.SIGTERM)               # clean exit restores the tty
    except ProcessLookupError:
        pass
    end = time.monotonic() + 0.6
    while time.monotonic() < end:
        if not drain(0.05):
            break
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass
    try:
        os.close(fd)
    except OSError:
        pass

    os.makedirs(os.path.dirname(out_cast), exist_ok=True)
    header = {"version": 2, "width": cols, "height": rows,
              "timestamp": int(time.time()),
              "env": {"TERM": "xterm-256color", "SHELL": "/bin/bash"},
              "title": title}
    with open(out_cast, "w") as f:
        f.write(json.dumps(header) + "\n")
        for ev in events:
            f.write(json.dumps(ev) + "\n")
    return out_cast
