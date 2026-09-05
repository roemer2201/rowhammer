# CODEX Singleplayer Code Review

Review scope: current `main` codebase, focusing on singleplayer gameplay and its supporting state/board/scoring/highscore/demo paths. Multiplayer-only code is excluded except where shared code can affect singleplayer.

## Findings

### SP-001 — `now_ms()` is not portable to the documented Bash baseline
**Severity:** High

`rowhammer.sh` states that the game verifies Bash `>= 4`, while `now_ms()` uses Bash 5's `EPOCHREALTIME` when available and otherwise falls back to `date +%s%N`. The fallback is not portable to all platforms supported by a Bash-4 baseline because `%N` is not required by POSIX `date`, and the code explicitly documents the project as Bash 4-compatible. On systems where `%N` is unsupported, arithmetic receives a non-numeric value and `set -euo pipefail` can terminate the game during normal timekeeping.

**Evidence:** `now_ms()` in `rowhammer.sh`; the source also describes the fallback as the older-Bash path. The current tree still contains a Bash >=4 compatibility claim while game timing depends on `%N` when `EPOCHREALTIME` is absent.

**Recommendation:** Either raise the supported Bash minimum to a version that guarantees the chosen timing primitive, or implement a genuinely portable millisecond fallback. A safer fallback would be a verified external clock source with explicit validation and a controlled error path.

### SP-002 — Singleplayer square detection can accept a square containing flood cells if reused through shared board helpers
**Severity:** Medium

`square_check_at()` rejects `BOARD_ID == 0`, so current flood cells are rejected correctly. However, the invariant is implicit and fragile: `board_flood_row()` uses `BOARD_ID=0` for flood cells while the square code determines validity solely from the ID. Any future singleplayer board cell type with ID zero would become square-ineligible by convention rather than by an explicit cell-type rule.

This is not a presently demonstrated gameplay failure in the current implementation, but it is a correctness risk in the shared rule boundary because `square_check_at()` is the authoritative square predicate and its validity rules are described as "all 16 cells filled" plus instance checks.

**Recommendation:** Make the predicate explicitly reject `GARBAGE_CELL` (and any non-piece cell type) before instance checks. This keeps the rule correct even if another zero-ID cell type is introduced later.

### SP-003 — `fmt_ppm()` can overflow Bash integer arithmetic for large persisted/corrupted counters before input validation catches them
**Severity:** Low

`fmt_ppm()` calculates `pieces * 600 / secs` without a range check. The highscore/save loaders cap numeric fields in their file regexes, but the function itself is reusable and also receives live round counters. A sufficiently large hand-edited highscore/stats value that passes the field-specific grammar but approaches Bash's signed integer limit can overflow during this multiplication and produce an invalid rate.

This is defensive rather than a likely normal-play failure, but the project deliberately validates persistent data to prevent arithmetic overflow elsewhere, so the same invariant should be enforced here too.

**Recommendation:** Bound the multiplicands before multiplication or divide/reduce the operands first, and reject impossible persisted values consistently with the other numeric parsers.

## Review notes / non-findings

The following areas were inspected and did not yield a confirmed singleplayer defect from the current source:

- Board bounds and line-clear compaction in `lib/board.sh`.
- Hidden-row top-out detection in `board_top_out()` and its singleplayer call path.
- Hold spawning checks in `hold_piece()`.
- Lock-delay recheck behavior after movement/rotation.
- Weighted row-credit calculation and Tetris bonus.
- Mode-specific ranking conditions in `round_is_ranked()` / `record_round()`.
- Atomic savegame replacement in `lib/save.sh`.
- Singleplayer demo replay structure in `lib/demo.sh`.

## Scope limitation

This review is source-level. I did not claim runtime reproduction for findings that depend on platform-specific behavior or extremely large crafted state; those are explicitly marked as robustness findings rather than confirmed gameplay regressions.
