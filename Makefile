# Makefile
#
# Description:
#   Install and uninstall targets for the rowhammer terminal game. Used
#   directly (make install) and by the packaging (debian/rules calls
#   "make install DESTDIR=... PREFIX=/usr"; a future RPM spec is expected
#   to reuse the same target).
#
# Layout:
#   ${PREFIX}/share/rowhammer/rowhammer.sh      main script (real location)
#   ${PREFIX}/share/rowhammer/lib/*.sh          library modules
#   ${PREFIX}/share/rowhammer/assets/wonders/   wonder ASCII art
#   ${PREFIX}/games/rowhammer                   relative symlink to rowhammer.sh
#
# Usage:
#   make install [DESTDIR=/staging] [PREFIX=/usr]
#   make uninstall [DESTDIR=/staging] [PREFIX=/usr]
#
# Version: 1.1.0  (2026-07-21)

PREFIX  ?= /usr/local
DESTDIR ?=
DATADIR  = $(PREFIX)/share/rowhammer
# Games belong in ${PREFIX}/games per Debian policy (section "games").
GAMESDIR = $(PREFIX)/games

INSTALL      = install
INSTALL_DATA = $(INSTALL) -m 0644
INSTALL_PROG = $(INSTALL) -m 0755

LIB_FILES    = $(wildcard lib/*.sh)
WONDER_FILES = $(wildcard assets/wonders/*.txt)

.PHONY: all install uninstall

# There is nothing to build; the game is plain bash.
all:

# Install the game under DATADIR and expose it via a relative symlink in
# GAMESDIR. The relative link target assumes both directories share PREFIX,
# which holds for the layouts used here (/usr and /usr/local).
install:
	$(INSTALL) -d "$(DESTDIR)$(DATADIR)/lib"
	$(INSTALL) -d "$(DESTDIR)$(DATADIR)/assets/wonders"
	$(INSTALL_PROG) rowhammer.sh "$(DESTDIR)$(DATADIR)/rowhammer.sh"
	$(INSTALL_DATA) $(LIB_FILES) "$(DESTDIR)$(DATADIR)/lib/"
	$(INSTALL_DATA) $(WONDER_FILES) "$(DESTDIR)$(DATADIR)/assets/wonders/"
	$(INSTALL) -d "$(DESTDIR)$(GAMESDIR)"
	ln -sf ../share/rowhammer/rowhammer.sh "$(DESTDIR)$(GAMESDIR)/rowhammer"

# Remove everything the install target created.
uninstall:
	rm -f "$(DESTDIR)$(GAMESDIR)/rowhammer"
	rm -rf "$(DESTDIR)$(DATADIR)"
