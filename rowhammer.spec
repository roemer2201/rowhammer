# rowhammer.spec
#
# RPM packaging for the rowhammer terminal game.
#
# The spec deliberately contains no install logic of its own: it calls the
# repository's Makefile ("make install"), exactly like debian/rules does, so
# both packages install the identical layout and only one place has to be
# touched when that layout changes.
#
# Build it with ./build-rpm.sh (creates the source tarball, runs rpmbuild in
# a private tree and collects the artifacts in dist/), or by hand:
#   tar czf ~/rpmbuild/SOURCES/rowhammer-<version>.tar.gz rowhammer-<version>/
#   rpmbuild -bb rowhammer.spec
#
# Version: keep the Version tag in sync with ROWHAMMER_VERSION in
# rowhammer.sh; build-rpm.sh refuses to build when the two drift apart.

# Release number, overridable for rebuilds of an unchanged version:
#   rpmbuild --define "rowhammer_release 2" -bb rowhammer.spec
%{!?rowhammer_release: %global rowhammer_release 1}

Name:           rowhammer
Version:        0.48.0
Release:        %{rowhammer_release}%{?dist}
Summary:        Tetris-like terminal game written in pure bash

# The upstream repository does not declare a license yet, so the package is
# all-rights-reserved and must not be redistributed publicly. This mirrors
# debian/copyright; update both once a license has been chosen.
License:        LicenseRef-UNLICENSED
URL:            https://github.com/roemer2201/rowhammer
Source0:        %{name}-%{version}.tar.gz

BuildArch:      noarch
BuildRequires:  make
Requires:       bash >= 4.0
# tput is optional: the game falls back to fixed ANSI sequences without it.
Recommends:     ncurses

%description
rowhammer is a Tetris-like game that runs entirely in the terminal and is
modeled after "The New Tetris" (N64). It offers a classic 10x20 board, the
seven standard tetrominoes with a 7-bag randomizer, gravity with a
level-based speed curve, line clearing, soft/hard drop, lock delay, pause
and restart, plus a start menu with configurable key bindings, color themes
and player name.

The square system builds gold and silver bonus blocks from four complete
tetrominoes in a 4x4 area, which pay extra rows when cleared. Those rows
feed a persistent counter that raises seven world wonders across sessions.
Highscores and all-time statistics are kept as well. Network multiplayer is
planned for a later release.

The name is a pun on hammering rows of blocks; the game is unrelated to the
hardware attack of the same name.

%prep
%setup -q

%build
# Nothing to build; the game is plain bash.

%install
# Plain "make install" rather than the %%make_install macro: the macro is not
# defined on every rpm build host, and this is the exact call debian/rules
# makes. PREFIX is needed because the Makefile defaults to /usr/local for
# manual installs. The game lands in %%{_datadir}/rowhammer and is exposed
# through a relative symlink in %%{_prefix}/games - the same layout the Debian
# package uses. Distributions that place games in %%{_bindir} would differ
# here, but parity between the two packages was the explicit project decision.
make install DESTDIR=%{buildroot} PREFIX=%{_prefix}

%files
%doc README.md
%{_datadir}/%{name}/
# Co-owned with the filesystem package on distributions that ship the
# directory; owning it here keeps the package installable where they do not.
%dir %{_prefix}/games
%{_prefix}/games/%{name}

%changelog
* Tue Aug 04 2026 roemer2201 <r.oliver@web.de> - 0.48.0-1
- Multi-language user interface: every player-visible text (menus,
  manual, HUD labels, result box, highscore and statistics tables,
  wonder screen, demo list, reset dialog and --help) comes from a
  translation table instead of the code.
- Ships German and English; a language is one file below lib/lang/.
- New option --lang de|en|auto (ROWHAMMER_LANG), also in the settings
  menu and stored in the config file; "auto" follows the locale and
  falls back to German. Switching applies without a restart.
- Several German screen texts that overflowed a 48-column terminal were
  rewrapped.
* Tue Aug 04 2026 roemer2201 <r.oliver@web.de> - 0.47.0-1
- Statistics per game mode: every all-time counter (cleared rows, bonus
  rows, gold and silver squares, rowhammers, pieces placed, play time)
  is now also counted for Marathon, Ultra, Sprint and Time Attack
  separately, next to the rounds played per mode and the runs that
  reached their goal.
- The all-time counters stay as they were and are not summed from the
  per-mode ones, so they remain the complete picture.
- The "Statistik" menu entry asks which set to show, the way
  "Highscores" asks which list; the per-mode screen adds the rows per
  round and the goal rate.
- The per-mode data is stored as "mode_<mode>_<field>=N" lines in
  <data-dir>/stats, replacing the "rounds_<mode>[_goal]" keys of 0.42.0.

* Tue Aug 04 2026 roemer2201 <r.oliver@web.de> - 0.46.0-1
- Demo recording and playback: every round is recorded as its moves,
  gravity steps and piece stream (not as screen output) and can be
  watched again from the new "Demos" menu entry, paused and played
  between 0.25x and 4x speed. Recording goes to a RAM disk while the
  round runs; the ten newest recordings are kept in <data-dir>/demos,
  and recordings backing a highscore entry are kept beyond that.
- Highscore entries carry a hash of the round, which the matching
  recording takes into its file name.
- New option --demo-record on|off (ROWHAMMER_DEMO_RECORD) and new reset
  target --reset demo.

* Mon Aug 03 2026 roemer2201 <r.oliver@web.de> - 0.45.0-1
- The end of a round asks for the name its highscore entry is filed
  under; the player name from the settings comes preselected, so Enter
  keeps it and typing replaces it. The name applies to that round only.
- Asked only for a round that really enters a list (cleared rows, and
  for Ultra and Sprint a run that reached its goal).
- Both name prompts share one line editor that draws and reads the
  input itself, so the session-wide raw input mode has no exception
  left; only valid name characters can be entered, at most 16.

* Mon Aug 03 2026 roemer2201 <r.oliver@web.de> - 0.44.0-1
- Retuned the wonder goals: every WONDER_COSTS entry multiplied by 100, so
  a wonder costs 10000 to 640000 weighted rows instead of 100 to 6400
  (1270000 for all seven instead of 12700) - the order of magnitude of the
  original, where a wonder is a long-term goal again.
- The wonder page of the manual widened its cost column to six digits.
- Existing savegames keep their row total, but it buys less progress: the
  construction site falls back to an earlier wonder and build stage.

* Mon Aug 03 2026 roemer2201 <r.oliver@web.de> - 0.43.0-1
- The pause menu (Esc/x) gained a "Neustarten" entry below "Fortsetzen":
  it gives up the running round and starts a fresh one in the same mode.
- Such a given-up round is recorded before the fresh one replaces it, so
  its rows keep counting toward wonder progress and statistics.
- Both pause menu entries that discard the round ("Neustarten" and
  "Runde beenden") are confirmed first, showing the round's lines, rows
  and level; declining returns to the pause menu.
- The controls block of --help listed the key bindings from before
  0.31.0; it now matches the actual defaults (arrows move, d/a rotate,
  space or arrow up hard-drops, c or w holds).

* Mon Aug 03 2026 roemer2201 <r.oliver@web.de> - 0.42.0-1
- New game mode "Time Attack": the round starts with one minute of play
  time counting down and every row of credit scored adds a second back,
  so the run lasts as long as it is kept fed; the rows are its score.
- Own highscore list highscore-timeattack, ranked by rows. Unlike Ultra
  and Sprint every run is recorded, finished or topped out - the rows
  are the same achievement either way.
- The statistics now count the rounds played per game mode and, for the
  three timed modes, how many of them reached their goal; shown on a
  third statistics screen.

* Mon Aug 03 2026 roemer2201 <r.oliver@web.de> - 0.41.0-1
- Switchable render mode --render-mode partial|full
  (ROWHAMMER_RENDER_MODE, default partial): the incremental line diff of
  0.22.0 or a full rewrite of the play screen per frame, the latter as a
  fallback for terminals that draw the incremental update incorrectly.

* Mon Aug 03 2026 roemer2201 <r.oliver@web.de> - 0.40.0-1
- Release structure on GitHub (tag v<version>, release notes from
  debian/changelog, packages as release assets) plus the CI and release
  workflows that build and publish them; tools/release.sh keeps the
  version in sync across rowhammer.sh, debian/changelog and this spec.

* Mon Aug 03 2026 roemer2201 <r.oliver@web.de> - 0.39.0-1
- New game mode "Sprint" (as many rows as possible in 3 minutes) with a
  highscore list of its own and a manual page explaining the game modes.

* Sun Aug 02 2026 roemer2201 <r.oliver@web.de> - 0.38.0-1
- Show the Ultra highscore list, reached through a mode picker under the
  "Highscores" main menu entry.

* Sun Aug 02 2026 roemer2201 <r.oliver@web.de> - 0.37.0-1
- Initial RPM packaging, reusing the Makefile install target shared with
  the Debian package.
