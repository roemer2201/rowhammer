#!/usr/bin/env python3
"""Shared paths for the demo-clip toolchain. Everything is resolved
relative to this file, so the tools work from any working directory and
regardless of where the repository is checked out."""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))

GAME = os.path.join(REPO, "rowhammer.sh")          # the game under test
PROBE = os.path.join(HERE, "probe_pieces.sh")      # 7-bag stream probe
DEMO_DIR = os.path.join(REPO, "docs", "demo")      # shipped .cast + .gif
BUILD_DIR = os.path.join(HERE, ".build")           # intermediate (gitignored)
