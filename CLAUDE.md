# CLAUDE.md - rowhammer

Diese Datei gibt Claude Code (und menschlichen Mitwirkenden) den Kontext,
das Konzept und die Arbeitsregeln fuer dieses Repository.

## 1. Projektueberblick

**rowhammer** ist ein Tetris-artiges Spiel, das vollstaendig in **Bash** im
Terminal laeuft. Vorbild ist **"The New Tetris"** fuer das Nintendo 64:

- Ueber alle Runden hinweg wird an einem **Weltwunder** gebaut. Der Baufortschritt
  richtet sich nach der **Gesamtzahl der abgebauten Reihen**.
- Das **Quadrat-System** des Originals ist enthalten: Aus Tetrominos gebildete
  4x4-Quadrate werden zu **Gold-** (sortenrein) bzw. **Silber-Bloecken**
  (gemischt) und liefern beim Abbau Bonus-Reihen.
- Eine **Multiplayer-Funktion** ist geplant, wird aber erst in einer spaeteren
  Phase umgesetzt (siehe Roadmap).

Der Repo-Name "rowhammer" ist ein Wortspiel: Es geht ums "Hammern" von Reihen
(rows), nicht um den gleichnamigen Hardware-Angriff.

## 2. Vorbild: The New Tetris (N64)

Die fuer uns relevanten Merkmale des Originals:

- **Wonders-Modus:** Jede abgebaute Reihe zahlt auf einen persistenten
  Gesamtzaehler ein. Mit steigendem Zaehler werden nacheinander Weltwunder
  Stueck fuer Stueck aufgebaut und schliesslich freigeschaltet.
- **Quadrate (Squares):** Wer aus **genau vier vollstaendigen Tetrominos** ein
  4x4-Quadrat legt, erhaelt einen Bonusblock:
  - **Gold-Quadrat (Mono-Square):** vier Teile der **gleichen** Sorte.
  - **Silber-Quadrat (Multi-Square):** vier Teile **gemischter** Sorten.
  - Teile, die bereits durch einen Reihenabbau zerschnitten wurden, zaehlen
    nicht mehr fuer ein Quadrat.
- **Bonus-Reihen:** Wird eine Reihe abgebaut, die durch ein Quadrat verlaeuft,
  zaehlt sie mehrfach fuer den Reihenzaehler (Silber deutlich mehr als eine
  normale Reihe, Gold noch einmal doppelt so viel wie Silber).
- Komfortfunktionen: Vorschau auf kommende Teile, Hold-Funktion, Soft-/Hard-Drop.

## 3. Spielkonzept

### 3.1 Kernregeln

- Spielfeld: **10 Spalten x 20 Zeilen** (klassisch), plus unsichtbare
  Spawn-Zeilen oberhalb.
- Die 7 Standard-Tetrominos (I, O, T, S, Z, J, L) mit **7-Bag-Randomizer**
  (jede Sorte genau einmal pro 7er-Beutel, dann neu mischen).
- Steuerung (Standardbelegung; ueber das Einstellungsmenue aenderbar und
  in der Nutzer-Konfigurationsdatei gespeichert, siehe 4.5):
  - Links/Rechts: `a`/`d` und Pfeiltasten
  - Rotation: `e` (im Uhrzeigersinn), `q` (gegen Uhrzeigersinn)
  - Soft-Drop: `s` bzw. Pfeil runter
  - Hard-Drop: `w`, Pfeil hoch und Leertaste
  - Hold: `c` bzw. `2`
  - Pause: `p`; `Esc`/`x` oeffnet das Pausenmenue (seit 0.12.0, Issue
    #12): Fortsetzen, Ins Hauptmenue (Runde pausiert, wieder aufnehmbar
    ueber den Eintrag "Fortsetzen", der dann im Hauptmenue und im
    Einzelspieler-Menue an erster Stelle steht) oder Runde beenden
- Vorschau: die naechsten 3 Teile. Hold: genau ein Teil, einmal pro Zug tauschbar.
- Level/Geschwindigkeit: Fallgeschwindigkeit steigt mit der Zahl abgebauter
  Reihen der laufenden Runde.

### 3.2 Quadrat-System (Gold/Silber)

- Jeder gelegte Stein behaelt eine **Identitaet** (welches Tetromino, welche
  Instanz), solange er unversehrt ist.
- Nach jedem Lock pruefen: Existiert ein 4x4-Bereich, der aus **genau vier
  vollstaendigen, unversehrten** Tetrominos besteht und exakt gefuellt ist?
  - Ja, alle vier gleiche Sorte -> Zellen werden zum **Gold-Quadrat**.
  - Ja, gemischte Sorten -> **Silber-Quadrat**.
- Quadrate werden farblich hervorgehoben (Gold/Gelb bzw. Silber/Weiss) und
  verhalten sich physikalisch wie normale Bloecke.
- **Reihenwertung beim Abbau** (per Recherche gegen das Original
  verifiziert): keine Multiplikation, sondern feste Bonuszeilen pro
  Quadrat in der geraeumten Reihe:
  - Basis: jede abgebaute Reihe zaehlt **1** Reihe Baufortschritt
  - je **Silber-Quadrat** in der Reihe: **+5** Bonuszeilen
  - je **Gold-Quadrat** in der Reihe: **+10** Bonuszeilen
  - Boni sind **additiv** bei mehreren Quadraten in einer Reihe
  - **Tetris** (4 Reihen auf einmal): **+1** Bonuszeile zusaetzlich
  - Beispiele: Tetris durch ein komplettes Gold-Quadrat = 4 + 1 + 4x10 =
    **45**; durch ein Silber-Quadrat = **25**; durch zwei komplette
    Gold-Quadrate = 4 + 1 + 8x10 = die beruehmten **85**.
- Umgesetzt seit 0.4.0 (`lib/squares.sh`, `lib/board.sh`): Werte
  justierbar in `ROWS_NORMAL`/`ROWS_SILVER`/`ROWS_GOLD`/`ROWS_TETRIS`.
  Die Quadrat-Anzahl je Reihe ergibt sich aus Gold-/Silber-Zellen / 4
  (Reihenabbau entfernt nur ganze Zeilen, Quadrate bleiben horizontal
  immer 4 Zellen breit). Ein angeschnittenes Quadrat behaelt seine
  Gold-/Silber-Zellen und liefert weiter Bonus.
- **Die Reihenwertung ist zugleich das Punktesystem** (seit 0.16.0,
  Nutzerentscheidung): abgebaute Reihen sind die einzige Punktquelle,
  der "Rows"-Zaehler ist der Score der Runde. Es gibt keine separaten
  Punkte mehr fuer Soft-/Hard-Drop, fuer die Quadrat-Bildung (der Bonus
  faellt erst beim Abbau der Reihen an) oder fuer Spins, und keine
  Level-Skalierung. Beispiele fuer eine einzelne Reihe: 2x Silber =
  1 + 2x5 = 11, 1x Silber + 1x Gold = 1 + 5 + 10 = 16, 2x Gold =
  1 + 2x10 = 21; Maximum pro Zug bleibt der Tetris durch zwei komplette
  Gold-Quadrate mit 85.
- Original-Regel bewusst noch nicht umgesetzt: Ein "Spin Move" beim
  Abraeumen laesst Gold-/Silber-Bloecke vorher in normale Einzelbloecke
  zerfallen (siehe Offene Punkte).

### 3.3 Weltwunder-Aufbau (umgesetzt, Version 0.8.0)

- Feste Abfolge von sieben Weltwundern (`lib/wonders.sh`). Der Abgleich
  mit dem Original ergab (Recherche, Quellen nur teilweise erreichbar):
  Die Wunder des Originals sind reale Bauwerke, belegt sind u. a.
  Maya-Tempel, Stonehenge, Sphinx, Pantheon und Basilius-Kathedrale;
  das erste Wunder (Maya) ist dort bei 2.500 Zeilen fertig, das letzte
  bei 500.000. Finale Liste (Reihen-Kosten je Wunder in Klammern,
  justierbar in `WONDER_COSTS`):
  1. Maya-Tempel / Chichen Itza (100)
  2. Stonehenge (200)
  3. Sphinx von Gizeh (400)
  4. Pantheon, Rom (800)
  5. Chinesische Mauer (1600)
  6. Taj Mahal (3200)
  7. Basilius-Kathedrale, Moskau (6400)
  Chinesische Mauer und Taj Mahal fuellen die zwei nicht verifizierbaren
  Plaetze. Die Kosten verdoppeln sich je Wunder (grob geometrisch wie im
  Original), sind aber auf Einzelrechner-Spielzeit herunterskaliert
  (12.700 gewichtete Reihen insgesamt statt 500.000 Zeilen).
- Jedes Wunder ist **eine** ASCII-Art-Datei (`assets/wonders/`, 12
  Zeilen, max. 44 Spalten, reines ASCII). Die Baustufen werden nicht als
  separate Dateien gepflegt, sondern durch **zeilenweises Aufdecken von
  unten** proportional zum Baufortschritt abgeleitet (12 Zeilen = 12
  Baustufen); die oberste Zeile erscheint erst bei 100 %. Der
  persistente Gesamt-Reihenzaehler bestimmt Wunder und Baustufe; nach
  Fertigstellung folgt das naechste Wunder, nach dem letzten zaehlt der
  Zaehler weiter und der Bildschirm meldet "Alle Weltwunder errichtet".
- Der Baufortschritt wird **ueber Sitzungen hinweg gespeichert**
  (Savegame `${DATA_DIR}/save`, siehe 4.5). Der Rundenkredit ("Rows")
  wird genau einmal je Runde verbucht, und zwar beim echten Rundenende:
  Game Over, "Runde beenden" im Pausenmenue oder - falls noch eine
  pausierte Runde wartet - beim Start einer neuen Runde bzw. beim
  Beenden des Programms (auch abgebrochene Runden zaehlen, wie im
  Original). Eine ueber das Pausenmenue ins Hauptmenue gelegte Runde
  ist noch nicht beendet und wird nicht verbucht (seit 0.12.0, Issue
  #12). Anzeige:
  im HUD laufend (aktuelles Wunder + Prozent, inkl. der laufenden
  Runde), als Baustellen-Bildschirm nach jedem Spiel beim Verlassen ins
  Menue sowie jederzeit ueber den Hauptmenuepunkt "Weltwunder".

### 3.4 Anzeige / HUD

- Hauptbereich: Spielfeld mit Rahmen.
- Seitenleiste: Naechste Teile, Hold, Lines (physische Reihen der
  Runde), Rows (gewertete Reihen = Punkte der Runde, siehe 3.2),
  aktuelles Wunder + Baufortschritt (Miniatur oder Prozent), Level,
  Gold-/Silberzaehler sowie die Spielzeit der laufenden Runde (Time,
  Format MM:SS; seit 0.17.0). Eine separate Score-Zeile gibt es seit
  0.16.0 nicht mehr.
- Spielzeit-Counter (seit 0.17.0): Die Anzeige "Time" zaehlt nur die
  aktive Spielzeit der laufenden Runde. Pausen (Taste `p` und das
  Pausenmenue) sowie der Game-Over-Bildschirm zaehlen nicht; die Zeit
  wird im Game-Loop analog zur Fallzeit ueber `${EPOCHREALTIME}`
  (Millisekunden, `now_ms`) akkumuliert und bei jedem Wiederaufnehmen
  neu angesetzt (`play_clock_resume`), sodass Leerlaufphasen nie
  mitzaehlen. Eine ueber das Pausenmenue ins Hauptmenue gelegte Runde
  behaelt ihre bis dahin gezaehlte Zeit und setzt sie beim Fortsetzen
  fort. Beim Rundenende wird die Spielzeit (in ganzen Sekunden) mit dem
  Highscore-Eintrag gespeichert (siehe 4.5).
- Nach Rundenende: Bildschirm mit dem aktuellen Wunder in seiner neuen Baustufe.

## 4. Technisches Konzept

### 4.1 Rahmenbedingungen

- **Bash >= 4.0** (assoziative Arrays), Ziel: uebliche Linux-Distributionen.
- Keine harten Abhaengigkeiten ausser Coreutils; `tput` optional (Fallback auf
  feste ANSI-Sequenzen).
- Farben ueber ANSI-Escape-Sequenzen (8/16 Farben als Basis, 256-Farben als
  Verbesserung wenn verfuegbar). Umgesetzt seit 0.9.0: `--color-mode`
  mit `auto` (Erkennung ueber `tput colors`, `TERM`, `COLORTERM`),
  `basic` und `extended`; die 256-Farben-Palette liegt in
  `lib/pieces.sh` (`PIECE_COLOR_EXT`), die vorberechneten SGR-Sequenzen
  baut `render_colors_init` in `lib/render.sh`.

### 4.2 Architektur und Dateistruktur

Ein Hauptskript, Logik in sourcebaren Modulen:

```
rowhammer/
  rowhammer.sh         # Hauptskript: Argumente, Init, Game-Loop
  lib/
    board.sh           # Spielfeld-Zustand, Kollision, Reihenabbau
    pieces.sh          # Tetromino-Definitionen und Rotationstabellen
    squares.sh         # Erkennung und Verwaltung von Gold-/Silber-Quadraten
    render.sh          # Rendering (Double-Buffering, ANSI)
    input.sh           # Nicht-blockierende Tastatureingabe
    menu.sh            # Startmenue (Einzel-/Mehrspieler, Einstellungen)
    config.sh          # Laden/Speichern der Nutzer-Konfiguration
    debug.sh           # Debug-Modus: Session-Trace in Log-Dateien
    highscore.sh       # Persistente Highscore-Liste (Top 10)
    wonders.sh         # Weltwunder-Logik, Baustufen, Fortschritt
    save.sh            # Laden/Speichern des Spielstands
    stats.sh           # Persistente Spielstatistik (Reihen, Bonusreihen, Bloecke)
  assets/
    wonders/           # ASCII-Art je Wunder und Baustufe
  Makefile             # install/uninstall-Ziele (genutzt von deb, spaeter rpm)
  build-deb.sh         # Baut das Debian-Paket, Artefakte nach dist/
  debian/              # Debian-Paketierung (debhelper, natives Paket)
  CLAUDE.md
  README.md
```

Stand (Version 0.16.0): alle Module aus dem Baum oben existieren
(`rowhammer.sh`, `lib/*.sh` inklusive `wonders.sh`, `save.sh` und
`stats.sh` sowie
`assets/wonders/` mit einer Art-Datei je Wunder). Die Anwendung
startet in einem Menue (Einzelspieler / Mehrspieler-Platzhalter /
Highscores / Weltwunder / Statistik / Einstellungen / Beenden;
solange eine pausierte Runde wartet, zusaetzlich "Fortsetzen" an
erster Stelle, ebenso im Einzelspieler-Untermenue); die
Menue-Beschriftung
ist bewusst Deutsch (ASCII), Code und Code-Ausgaben bleiben Englisch.
Das Spielfeld haelt je Zelle drei parallele Arrays (Sorte `BOARD`,
Instanz-ID `BOARD_ID`, Quadrat-Status `BOARD_SQ`); der HUD-Zaehler
"Rows" ist die gewichtete Reihenwertung (1/5/10), die den
Weltwunder-Fortschritt speist und seit 0.16.0 zugleich der Score der
Runde ist (siehe 3.2), "Lines" zaehlt physische Reihen und
treibt das Level. CLI-Optionen bisher: `--seed N` (`ROWHAMMER_SEED`)
fuer reproduzierbare Teilfolgen, `--name NAME` (`ROWHAMMER_PLAYER_NAME`),
`--data-dir DIR` (`ROWHAMMER_DATA_DIR`) fuer das Datenverzeichnis,
`--no-color` (`ROWHAMMER_NO_COLOR`), `--color-mode auto|basic|extended`
(`ROWHAMMER_COLOR_MODE`, Standard `auto`; `--no-color` gewinnt),
`--debug` (`ROWHAMMER_DEBUG`),
`--debug-dir DIR` (`ROWHAMMER_DEBUG_DIR`), `-h/--help`. Tastenbelegung
zusaetzlich per `ROWHAMMER_KEY_*`-Umgebungsvariablen uebersteuerbar.

### 4.3 Game-Loop, Input, Rendering

- **Game-Loop:** feste Tick-Rate; Fall-Intervall abhaengig vom Level.
  Zeitmessung ueber `${EPOCHREALTIME}` (Bash 5) mit Fallback.
- **Input:** nicht-blockierend ueber `read -rsn1 -t <timeout>`;
  Escape-Sequenzen der Pfeiltasten sauber einlesen. Terminal-Modus mit `stty`
  setzen und ueber einen `trap`-Handler (EXIT/INT/TERM) garantiert
  wiederherstellen. Seit 0.16.1 (Issue #7) werden Escape-Sequenzen
  byteweise bis zu ihrem Endbyte gelesen (grosszuegigeres
  Fortsetzungs-Timeout `ESC_SUFFIX_T`, 50 ms): laengere Sequenzen
  (Shift-/Ctrl-Pfeile, Entf, F-Tasten, Alt-Chords) werden komplett
  konsumiert und verworfen statt Restbytes als Tastendruecke
  fehlzudeuten; ausserdem wird ein Byte, das Bash (beobachtet mit 5.1)
  im Timeout-Moment zusammen mit dem Timeout-Status liefert, nicht
  mehr verworfen (beides zusammen loeste ungewollte Hold-Wechsel durch
  den Schwanz zerrissener Pfeiltasten-Sequenzen aus).
- **Rendering:** pro Frame den kompletten Bildschirm in einen String puffern
  und mit **einem** `printf` ausgeben (Double-Buffering gegen Flackern);
  Cursor verstecken, alternativen Screen-Buffer nutzen (`tput smcup`/`rmcup`).
- **Datenmodell:** Spielfeld als eindimensionales Bash-Array (Index
  `y * Breite + x`); Zelle enthaelt Sorte, Stein-Instanz-ID und
  Quadrat-Status (keins/Silber/Gold), damit `squares.sh` und die
  Reihenwertung effizient arbeiten koennen.

### 4.4 Quadrat-Erkennung (Skizze)

1. Jede gelegte Stein-Instanz bekommt eine eindeutige ID; jede Zelle kennt
   ihre ID. Beim Reihenabbau werden betroffene Instanzen als "zerschnitten"
   markiert.
2. Nach jedem Lock: Fuer jede moegliche 4x4-Position (begrenzt auf die Umgebung
   des neuen Steins) pruefen, ob genau 4 unzerschnittene Instanzen den Bereich
   exakt fuellen und keine Zelle dieser Instanzen ausserhalb liegt.
3. Bei Treffer: Zellen als Gold/Silber markieren; die Instanzen sind damit
   verbraucht (ein Stein kann nur zu einem Quadrat gehoeren).

### 4.5 Persistenz

- Alle persistenten Spieldaten liegen gemeinsam im Datenverzeichnis
  `${HOME}/.config/rowhammer` (seit 0.13.0, vorher `${HOME}/rowhammer`;
  aenderbar per `--data-dir DIR` bzw.
  `ROWHAMMER_DATA_DIR`): die Konfiguration `rowhammer.conf`, die
  Highscore-Liste `highscore`, der Spielstand `save` und die
  Statistik `stats`.
- Bewusste Abweichung von den Script-Konventionen (Abschnitt 11,
  organisationsbasierte Suche unter `/etc` und `${HOME}/.config`):
  seit 0.7.0 gibt es genau eine Config-Datei im Datenverzeichnis
  (Nutzerentscheidung). Alte Pfade werden gemaess der Arbeitsregel
  "keine Abwaertskompatibilitaet" nicht mehr beruecksichtigt - das
  gilt auch fuer den Umzug des Datenverzeichnisses nach
  `${HOME}/.config/rowhammer` in 0.13.0 (keine Migration von
  `${HOME}/rowhammer`).
- Alle Dateien werden atomar geschrieben (Tempdatei + `mv`).
- `lib/config.sh` (seit 0.2.0, Pfad seit 0.7.0): das Einstellungsmenue
  (Spielername, Tastenbelegung) schreibt `${DATA_DIR}/rowhammer.conf`;
  Werte werden validiert und single-quoted geschrieben, da die Datei
  gesourct wird.
- `lib/highscore.sh` (seit 0.7.0): Top 10 abgeschlossener Runden in
  `${DATA_DIR}/highscore`, eine Zeile je Eintrag im Format
  `rows|lines|level|name|date|gold|silver|time`, absteigend nach Rows
  sortiert. Seit dem Punktesystem-Umbau (0.16.0) ist die gewichtete
  Reihenwertung der einzige Score: das fruehere fuehrende
  `score`-Feld entfaellt, Rows bestimmt die Rangfolge und den Rang
  im Game-Over-Bild. Das abschliessende Feld `time` (seit 0.17.0) ist
  die Spielzeit der Runde in ganzen Sekunden. Zeilen im falschen
  (nicht achtfeldrigen) Format fallen gemaess der
  Arbeitsregel "keine Abwaertskompatibilitaet" bei der Validierung
  einfach heraus.
  Die Datei wird geparst und validiert (nicht gesourct); defekte
  Zeilen werden beim Laden uebersprungen. Eine Runde wird beim
  echten Rundenende genau einmal gewertet (Game Over oder endgueltiges
  Beenden der Runde, siehe 3.3; 0 Rows zaehlt nicht, gleiche Rows
  rangieren hinter dem aelteren Eintrag). Der erreichte Rang erscheint im Game-Over-Bild,
  die Liste unter "Highscores" im Hauptmenue. Angezeigt werden je
  Eintrag Rang, Name, Rows, Gold- und Silberquadrate, die Spielzeit
  (Spalte "Zeit", MM:SS; seit 0.17.0) sowie das Datum
  (seit 0.14.0; die Score-Spalte wurde in 0.15.0 auf Nutzerwunsch aus
  der Anzeige und in 0.16.0 auch aus dem Dateiformat entfernt; Lines
  und Level bleiben gespeichert, werden aber nicht angezeigt).
  Damit das Layout (mit dem Zwei-Zeichen-Menue-Einzug) exakt ins
  48-Spalten-Minimum passt, wird der Name in der Anzeige seit der
  Zeit-Spalte (0.17.0) auf 8 Zeichen gekuerzt (vorher 13; gespeichert
  bleiben weiterhin bis zu 16 Zeichen).
- `lib/save.sh` (seit 0.8.0): der Gesamt-Reihenzaehler in
  `${DATA_DIR}/save`, eine validierte Zeile `total_rows=N` (geparst,
  nicht gesourct; eine defekte Datei faellt mit Meldung auf 0 zurueck).
  Nur der Zaehler wird gespeichert; aktuelles Wunder und Baustufe
  werden daraus deterministisch abgeleitet (`lib/wonders.sh`), damit
  Spielstand und Wunder-Tabellen nie auseinanderlaufen koennen.
- `lib/stats.sh` (seit 0.10.0): persistente Gesamt-Statistik in
  `${DATA_DIR}/stats` als validierte `key=value`-Zeilen (geparst,
  nicht gesourct; defekte Zeilen fallen auf 0 zurueck): abgebaute
  Reihen (`lines`), Bonusreihen (`bonus_rows`, der Gold-/Silber-/
  Tetris-Anteil der Reihenwertung, also Rows minus Lines) sowie
  gebaute Gold- (`gold_squares`) und Silberquadrate
  (`silver_squares`). Seit 0.11.0 zusaetzlich die Ergebnisse der
  letzten drei Runden (`recent=`-Zeilen, neueste zuerst; seit 0.16.0
  im Format `lines|bonus|gold|silver|date` mit dem Spieldatum
  als `YYYY-MM-DD` - das fruehere fuehrende `score`-Feld entfiel mit
  dem Punktesystem-Umbau, die Punkte einer Runde sind Lines + Bonus
  und werden bei der Anzeige abgeleitet statt gespeichert; alte
  Zeilen im falschen Format werden gemaess der
  Arbeitsregel "keine Abwaertskompatibilitaet" beim Laden verworfen).
  Eine Runde wird
  beim Rundenende genau einmal
  verbucht (gemeinsam mit Highscore und Savegame in
  `record_round`); Anzeige ueber den Hauptmenuepunkt
  "Statistik", inklusive der gewichteten Gesamtsumme
  (Lines + Bonus) und der letzten drei Spiele samt Datum.

### 4.6 Debug-Modus (umgesetzt, Version 0.6.0)

Zweck: Ein Problem oder eine Frage zum Spielverlauf soll anhand von
Log-Dateien nachvollziehbar sein, ohne die Situation live reproduzieren
zu muessen (z. B. fuer Bug-Reports an Claude Code).

- Aktivierung: `--debug` bzw. `ROWHAMMER_DEBUG=1`; Zielverzeichnis
  `--debug-dir DIR` bzw. `ROWHAMMER_DEBUG_DIR` (Standard:
  `${XDG_STATE_HOME:-~/.local/state}/rowhammer/debug/<Zeitstempel>.<PID>`,
  ein Verzeichnis pro Lauf; der Pfad wird beim Beenden ausgegeben).
- Drei korrelierte Log-Dateien (`lib/debug.sh`); jede Zeile traegt die
  Millisekunden seit Sessionstart und den Bildschirm-Update-Zaehler
  ("f N" = nach Update N, vor N+1):
  - `frames.log`: jede Terminal-Ausgabe 1:1 (Byte fuer Byte, inklusive
    ANSI-Sequenzen). Moeglich durch den zentralen Ausgabe-Trichter
    `screen_write` in `lib/render.sh`, durch den seit 0.6.0 alle Module
    (Spiel, Menues, Prompts, Terminal-Setup) schreiben.
  - `input.log`: jeder Tastendruck mit Rohbytes (`printf %q`-quotiert)
    und gemapptem Symbol; auch nicht zuordenbare Escape-Sequenzen.
  - `events.log`: Session-Header (Version, Bash, Terminal, Seed,
    Spieler, Tastenbelegung, geladene Config-Dateien) und alle
    Aktionen: Spawns samt Queue, Bewegungen/Rotationen (inklusive
    blockierter Versuche), Gravitations-Fall, Locks, Quadrat-Bildung
    mit Instanz-IDs, Reihenabbau mit Credit-Aufschluesselung je Reihe,
    Hold, Pause, Bag-Refills, Menuewahl, Config-Speicherungen, fatale
    Fehler sowie ein Board-Snapshot (Typ- und Quadrat-Gitter plus
    cut/squared-Instanzlisten) nach jedem Lock.
- Ohne `--debug` sind alle Logging-Helfer No-Ops (ein Guard am
  Funktionsanfang); der Spiel-Loop bleibt frei von Zusatzkosten.
- Die Logs koennen in langen Sessions mehrere MB gross werden; es gibt
  bewusst keine Rotation (ein Verzeichnis je Lauf, manuell loeschbar).

### 4.7 Paketierung

- **Debian (umgesetzt):** klassische debhelper-Paketierung im `debian/`-
  Verzeichnis, natives Quellformat "3.0 (native)"; die Paketversion in
  `debian/changelog` folgt der Skriptversion von `rowhammer.sh`.
  Installations-Layout: Spiel, Module und `assets/` nach
  `/usr/share/rowhammer/`,
  Starter als relativer Symlink `/usr/games/rowhammer` (Debian-Policy:
  Spiele nach `/usr/games`). `rowhammer.sh` loest deshalb beim Bestimmen
  von `SCRIPT_DIR` Symlinks per `readlink -f` auf. Die Installationslogik
  liegt zentral im `Makefile` (`make install`, `DESTDIR`/`PREFIX`),
  `debian/rules` ruft es mit `PREFIX=/usr` auf. Bequemer Build ueber
  `./build-deb.sh` (Artefakte in `dist/`, per `.gitignore`
  ausgeschlossen); Build-Abhaengigkeiten: `dpkg-dev`, `debhelper`.
- **RPM (geplant):** Spec-Datei soll dasselbe `make install`
  wiederverwenden; gleiche Pfade (`/usr/share/rowhammer`, `/usr/games`).
- Hinweis: Das Repository hat noch keine Lizenzdatei;
  `debian/copyright` ist entsprechend als "UNLICENSED" markiert und muss
  nachgezogen werden, sobald eine Lizenz festgelegt ist.

## 5. Multiplayer (spaetere Phase)

Bewusst **nicht** Teil der ersten Versionen. Grobkonzept fuer spaeter:

- **Modus:** 2 Spieler, jeder mit eigenem Feld; abgebaute Mehrfach-Reihen
  senden Stoer-Reihen ("Garbage") an den Gegner.
- **Transport:** Netzwerk ueber TCP; Kandidaten sind `nc`/`ncat` oder Bashs
  eingebautes `/dev/tcp`. Ein Spieler hostet, der andere verbindet sich.
- **Protokoll:** zeilenbasierte Textnachrichten (Versionscheck, Seed-Austausch
  fuer identische 7-Bag-Folgen, Garbage-Events, Feld-Snapshots fuer die
  Gegneranzeige, Ping/Timeout).
- Architektur-Konsequenz schon heute: Spiellogik strikt von Rendering und
  Input trennen, damit ein zweites Feld und Netz-Events spaeter andockbar sind.

## 6. Konventionen fuer alle Skripte

Fuer **jedes** Bash-Skript in diesem Repo gelten verbindlich die
**Script-Konventionen** (Skill `script-conventions`). Insbesondere:

- Header-Kommentarblock mit Beschreibung, Programmablaufplan (bei laengeren
  Skripten), Nutzung und SemVer-Version mit Datum.
- Kommentare, Strings und Ausgaben in **Englisch**, **nur ASCII**.
- `-h`/`--help` mit allen Parametern; jeder Parameter zusaetzlich per
  Umgebungsvariable setzbar (Praefix `ROWHAMMER_`, Praezedenz
  Standard < Config < Env < CLI).
- Variablen immer als `"${var}"` schreiben.
- Fehler mit aussagekraeftiger Meldung nach STDERR; STDERR von Befehlen nicht
  unterdruecken; Exit-Code 0/!=0, Aufruffehler 2.
- Begruendungskommentare bei spaeteren Aenderungen bewahren.

Hinweis: Das Spiel ist interaktiv; die Logging-Regeln fuer cron/systemd sind
hier nachrangig, die uebrigen Regeln gelten uneingeschraenkt.
Diese CLAUDE.md (Konzept, Roadmap) ist bei jeder inhaltlichen Aenderung
mitzupflegen.

Arbeitsregel: **Keine Abwaertskompatibilitaet noetig.** Das Projekt wird
sequenziell entwickelt und war nie anderswo installiert; Migrationslogik
fuer alte Config-/Savegame-Formate oder alte Schnittstellen ist unnoetig
und soll weggelassen werden. Formate duerfen bei Bedarf einfach brechen.

## 7. Roadmap / Todo-Liste

### Phase 1 - Spielbarer Kern (umgesetzt, Version 0.1.0)

- [x] Projektgeruest anlegen (`rowhammer.sh`, `lib/`-Module, Header nach Konvention)
- [x] Terminal-Handling: Raw-Mode, alternativer Screen-Buffer, sauberes
      Aufraeumen per `trap`
- [x] Nicht-blockierender Input inkl. Pfeiltasten-Escape-Sequenzen
- [x] Spielfeld-Datenmodell und Kollisionspruefung
- [x] Tetromino-Definitionen mit Rotationstabellen, 7-Bag-Randomizer
- [x] Game-Loop mit Gravitation, Lock, Reihenabbau
- [x] Rendering mit Double-Buffering und Farben
- [x] Soft-/Hard-Drop, Pause, Game Over (mit Neustart per `r`)

### Zwischenschritt - Menue und Konfiguration (umgesetzt, Version 0.2.0)

- [x] Startmenue: Einzelspieler / Mehrspieler / Einstellungen / Beenden
- [x] Einzelspieler-Untermenue mit "Normales Spiel" (weitere Modi spaeter)
- [x] Mehrspieler als Platzhalter ohne Funktion (Hinweis-Bildschirm)
- [x] Einstellungen: Tastenbelegung im Spiel aenderbar, Spielername
- [x] Nutzer-Konfigurationsdatei (`rowhammer.conf`) nach Konvention,
      atomar geschrieben, Praezedenz Standard < Config < Env < CLI

### Zwischenschritt - Paketierung (deb umgesetzt, Version 0.17.0)

- [x] `Makefile` mit install/uninstall (DESTDIR/PREFIX, deb/rpm-tauglich)
- [x] Debian-Paketierung (`debian/` mit debhelper, natives Paket,
      Launcher-Symlink `/usr/games/rowhammer`)
- [x] Build-Skript `build-deb.sh` nach Script-Konventionen
- [ ] RPM-Paketierung (Spec-Datei, nutzt `make install`)
- [ ] Lizenz festlegen und `debian/copyright` aktualisieren

### Phase 2 - The-New-Tetris-Mechaniken (umgesetzt, Version 0.3.0)

- [x] Stein-Instanz-Tracking (IDs, "zerschnitten"-Markierung)
- [x] 4x4-Quadrat-Erkennung nach jedem Lock
- [x] Gold-/Silber-Darstellung und Bonus-Reihenwertung (1/5/10, justierbar
      in `lib/squares.sh`)
- [x] Vorschau (3 Teile) und Hold-Funktion (Taste `c`, konfigurierbar)
- [x] Level-/Geschwindigkeitskurve (Tabelle `LEVEL_SPEEDS`), Punktesystem
      (urspruenglich: Reihen skalieren mit Level, Quadrat-Bonus
      2000/1000; in 0.16.0 durch die Reihenwertung als einziges
      Punktesystem ersetzt, siehe 3.2)
- [x] Bonus-Werte gegen das Original verifiziert (Recherche, siehe 3.2:
      additiv je Quadrat, Tetris +1) und in 0.4.0 umgesetzt

### Zwischenschritt - Debug-Modus (umgesetzt, Version 0.6.0)

- [x] `--debug`/`--debug-dir` mit Session-Verzeichnis und drei
      korrelierten Log-Dateien (`frames.log`, `input.log`, `events.log`),
      Konzept siehe 4.6
- [x] Zentraler Ausgabe-Trichter `screen_write` (Frames 1:1 auch fuer
      Menues und Terminal-Setup)
- [x] Instrumentierung aller Spielaktionen inkl. blockierter Versuche,
      Board-Snapshots nach jedem Lock

### Phase 3 - Weltwunder (umgesetzt, Version 0.8.0)

- [x] Wunder-Liste final festgelegt (Abgleich mit dem Original per
      Recherche; verifizierte Bauwerke uebernommen, Kosten skaliert,
      siehe 3.3)
- [x] ASCII-Art je Wunder (`assets/wonders/`, eine Datei je Wunder;
      Baustufen durch zeilenweises Aufdecken von unten, siehe 3.3)
- [x] Persistenter Gesamt-Reihenzaehler und Savegame (`save.sh`, atomar)
- [x] Fortschrittsanzeige im HUD, Wunder-Bildschirm nach Rundenende
      und Hauptmenuepunkt "Weltwunder"
- [x] Freischalt-Logik: naechstes Wunder nach Fertigstellung; nach dem
      letzten Wunder "Alle Weltwunder errichtet"

### Phase 4 - Politur

- [ ] Konfigurierbare Farben (Config-Datei nach Konvention;
      Tastenbelegung ist seit 0.2.0 umgesetzt)
- [x] Standard-Tastenbelegung geaendert (siehe 3.1, Version 0.5.0):
      `w`/Pfeil hoch **und** Leertaste fuer Hard-Drop, `e` fuer Rotation
      im Uhrzeigersinn, `c`/`2` fuer Hold/Tauschen. Pfeil hoch und
      Leertaste liegen als feste Sekundaerbelegung auf dem Hard-Drop,
      `2` fest auf Hold; `w`, `e` und `c` sind die konfigurierbaren
      Primaertasten.
- [x] Highscore-Liste (Version 0.7.0: Top 10 im Datenverzeichnis,
      Anzeige im Hauptmenue, Rang im Game-Over-Bild; siehe 4.5)
- [x] 256-Farben-Modus (Version 0.9.0: `--color-mode auto|basic|extended`,
      `auto` erkennt 256-Farben-Terminals selbst; erweiterte Palette mit
      Guideline-Farben inkl. echtem Orange fuer L sowie satterem
      Gold/Silber, siehe 4.1)
- [x] Spielstatistik (Version 0.10.0: persistente Zaehler fuer
      abgebaute Reihen, Bonusreihen und gebaute Gold-/Silberquadrate
      in `${DATA_DIR}/stats`, Anzeige im Hauptmenuepunkt "Statistik";
      seit 0.11.0 zusaetzlich die Ergebnisse der letzten drei Spiele,
      siehe 4.5)
- [x] Pausenmenue und fortsetzbare Runden (Version 0.12.0, Issue #12):
      `Esc`/`x` im Spiel oeffnet ein Pausenmenue (Fortsetzen / Ins
      Hauptmenue / Runde beenden); eine ins Hauptmenue gelegte Runde
      bleibt ueber den Eintrag "Fortsetzen" (im Hauptmenue und im
      Einzelspieler-Menue) wieder aufnehmbar
      und wird erst beim echten Rundenende gewertet (siehe 3.1, 3.3)
- [ ] Anpassung an Terminalgroesse
- [ ] Performance-Optimierung des Renderings (nur geaenderte Zellen zeichnen)
- [ ] Layout anpassen: Rendering zentriert im Terminal; Stats unten,
      naechste drei Steine oben rechts, Hold-Stein links
- [ ] README mit Screenshots/Asciinema aktualisieren
- [x] Spielzeit-Counter fuer die aktuelle Runde einbauen (Version
      0.17.0: Anzeige im HUD als "Time" MM:SS, Zeitmessung analog zum
      Game-Loop ueber `${EPOCHREALTIME}`/`now_ms`; nur aktive Spielzeit
      zaehlt, Pausen und Game-Over-Bildschirm nicht; die Spielzeit wird
      zusaetzlich mit dem Highscore-Eintrag gespeichert, siehe 3.4/4.5)
- [x] Highscore-Liste um Anzahl erzeugter Silber- und Gold-Bloecke
      erweitern (Version 0.15.0: zusaetzliche Felder im Zeilenformat,
      siehe 4.5; bei Eintraegen ohne diese Felder gilt als
      Standardwert 0. Gold/Silber werden als Spalten angezeigt, die
      Score-Spalte ist dafuer auf Nutzerwunsch aus der Anzeige
      entfernt - der Score bleibt gespeichert und bestimmt weiterhin
      die Rangfolge)
- [ ] "Wollen Sie wirklich beenden?"-Abfrage beim Schliessen des Spiels
      einbauen, falls noch eine laufende Runde im Zwischenspeicher liegt
- [x] Anzeige des Datums in der Highscore-Liste nachruesten (Version
      0.14.0: das gespeicherte Feld `date` wird als eigene Spalte
      angezeigt, Name in der Anzeige auf 14 Zeichen gekuerzt; die
      Statistik speichert und zeigt seither ebenfalls das Datum der
      letzten drei Spiele, siehe 4.5)
- [x] Fehlinterpretierte Tastendruecke behoben (Version 0.16.1,
      Issue #7): zerrissen zugestellte Pfeiltasten-Sequenzen loesten
      ueber ihre Restbytes (`[`, `C` -> Taste `c`) ungewollte
      Hold-Wechsel aus; per Debug-Log nachgewiesen. `read_key` liest
      Escape-Sequenzen jetzt byteweise bis zum Endbyte mit
      grosszuegigerem Timeout und wertet auch ein im Timeout-Moment
      geliefertes Byte aus (siehe 4.3)
- [x] Punktesystem-Umbau (Version 0.16.0, Nutzerentscheidung):
      abgebaute Reihen sind die einzige Punktquelle, der Score ist
      identisch mit der gewichteten Reihenwertung "Rows" (1 je Reihe,
      +5 je Silber-, +10 je Gold-Streifen, +1 je Tetris, siehe 3.2).
      Entfallen sind Drop-Punkte, Quadrat-Bildungs-Boni (2000/1000)
      und die Level-Skalierung; Highscore (Rangfolge nach Rows) und
      Statistik speichern kein separates Score-Feld mehr (siehe 4.5)

### Phase 5 - Multiplayer (spaeter)

- [ ] Spiellogik vollstaendig von Rendering/Input entkoppeln
- [ ] Netzwerk-Transport waehlen und Protokoll spezifizieren
- [ ] Host-/Join-Modus, Seed-Austausch, Garbage-Regeln
- [ ] Gegner-Feldanzeige, Verbindungsabbruch-Handling

## 8. Offene Punkte

- Bonus-Reihenwertung ist verifiziert und umgesetzt (siehe 3.2); seit
  dem Punktesystem-Umbau in 0.16.0 ist sie zugleich der Score. Die
  frueher offene Frage nach den Punkten fuer die Quadrat-Bildung hat
  sich damit erledigt (es gibt bewusst keine Bildungs-Punkte mehr).
- "Spin Move"-Regel des Originals umsetzen? Beim Abraeumen mit einem
  Spin zerfallen Gold-/Silber-Bloecke vorher in normale Einzelbloecke
  und verlieren ihren Bonus. Erfordert Erkennung, ob der letzte Zug ein
  Spin war - Aufwand/Nutzen vor Umsetzung abwaegen.
- Weltwunder-Liste und Baustufen sind seit 0.8.0 festgelegt (siehe
  3.3). Offen bleibt: Die Reihen-Kosten je Wunder (100..6400) sind
  gegenueber dem Original bewusst herunterskaliert und sollten nach
  Playtesting ggf. nachjustiert werden (`WONDER_COSTS`).
- Mindest-Terminalgroesse: seit 0.1.0 als 48x24 implementiert (Pruefung
  nur beim Start). Offen: Verhalten bei Groessenaenderung waehrend des
  Spiels (SIGWINCH) - gehoert zu Phase 4 "Anpassung an Terminalgroesse".
- Punktesystem-Feinschliff (Kombos, Back-to-Back?): Nach dem Umbau in
  0.16.0 (nur abgebaute Reihen zaehlen) waeren solche Extras eine
  bewusste Abweichung vom Konzept "Punkte = Reihenwertung" - nur nach
  expliziter Nutzerentscheidung wieder aufgreifen.
- UI-Sprache: Menues sind Deutsch (ASCII), In-Game-HUD und --help
  Englisch (Konvention). Entscheiden, ob das so bleibt oder das UI
  einheitlich einsprachig werden soll.
