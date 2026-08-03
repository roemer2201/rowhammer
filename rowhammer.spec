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
Version:        0.39.0
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
* Mon Aug 03 2026 roemer2201 <r.oliver@web.de> - 0.39.0-1
- New game mode "Sprint" (as many rows as possible in 3 minutes) with a
  highscore list of its own and a manual page explaining the game modes.

* Sun Aug 02 2026 roemer2201 <r.oliver@web.de> - 0.38.0-1
- Show the Ultra highscore list, reached through a mode picker under the
  "Highscores" main menu entry.

* Sun Aug 02 2026 roemer2201 <r.oliver@web.de> - 0.37.0-1
- Initial RPM packaging, reusing the Makefile install target shared with
  the Debian package.
