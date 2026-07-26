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
- **Lock Delay (seit 0.18.0):** Ein Stein, der nicht mehr fallen kann,
  wird nicht sofort festgesetzt, sondern ruht ein kurzes Gnadenfenster
  (`LOCK_DELAY_MS`, 250 ms), in dem er weiter nach links/rechts
  verschoben und gedreht werden kann. Der Touchdown-Timer wird **nur**
  zurueckgesetzt, wenn eine Verschiebung/Drehung den Stein wieder ins
  Fallen bringt (dann faellt er normal weiter); eine Bewegung, die ihn
  weiter aufliegen laesst, behaelt die urspruengliche Frist, sodass ein
  Stein nicht endlos am Boden gehalten werden kann. Nur der
  Transitions-Moment ins Aufliegen setzt die Frist; wiederholte
  Gravitations-Ticks oder ein Soft-Drop auf einen bereits ruhenden Stein
  verschieben sie nicht. Der Hard-Drop setzt weiterhin sofort fest, und
  das Fenster laeuft weder in der Pause noch im Pausenmenue
  (Umsetzung: `lock_touchdown`, `lock_delay_recheck`, `step_down` und der
  Game-Loop in `rowhammer.sh`; Wert justierbar in `LOCK_DELAY_MS`).
- **Blink-Effekt beim Reihenabbau (seit 0.20.0):** Vervollstaendigt ein
  Lock eine oder mehrere Reihen, blinken diese Reihen erst kurz auf und
  werden dann entfernt. Die Reihen werden vor dem Abbau ermittelt
  (`board_full_rows` in `lib/board.sh`), die Animation wechselt
  `FLASH_CYCLES`-mal zwischen hell hervorgehobener und normaler
  Darstellung (`FLASH_ROWS`/`FLASH_STATE` in `lib/render.sh`, gesteuert
  von `flash_rows` in `rowhammer.sh`; Standard 2 Zyklen a 2x70 ms =
  rund 280 ms, justierbar in `FLASH_MS`/`FLASH_CYCLES`,
  `FLASH_CYCLES=0` schaltet die Animation ab). Die Quadrat-Erkennung
  laeuft vorher, sodass eine Reihe durch ein frisch gebildetes Quadrat
  bereits in ihrer Gold-/Silber-Wertigkeit blinkt. Die Animation haelt
  den Game-Loop fuer ihre Dauer an (das naechste Teil erscheint erst
  danach); Tastendruecke waehrend des Blinkens werden bewusst verworfen,
  damit sie nicht gesammelt auf dem neuen Stein losgehen. Das Warten
  nutzt wie der uebrige Loop ein `read` mit Timeout (kein `sleep`-Fork).

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
- Original-Regel bewusst nicht umgesetzt: Ein "Spin Move" beim Abraeumen
  laesst Gold-/Silber-Bloecke vorher in normale Einzelbloecke zerfallen
  (Nutzerentscheidung: soll nicht zur Anwendung kommen).

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
- Reihenabbau: die betroffenen Reihen blinken kurz auf, bevor sie
  verschwinden (siehe 3.1).
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
    net.sh             # (Phase 5) Transport: Unix-Socket, Zeilenrahmung, Limits
    proto.sh           # (Phase 5) Nachrichtentabelle, Parser mit Validierung
    hub.sh             # (Phase 5) Sitzungslogik des Hubs (Lobby, Garbage, KO)
    mp.sh              # (Phase 5) Client-Seite: Lobby, Peer-Zustaende, Anbindung
  assets/
    wonders/           # ASCII-Art je Wunder und Baustufe
  Makefile             # install/uninstall-Ziele (genutzt von deb, spaeter rpm)
  build-deb.sh         # Baut das Debian-Paket, Artefakte nach dist/
  debian/              # Debian-Paketierung (debhelper, natives Paket)
  CLAUDE.md
  README.md
```

Stand (Version 0.16.0): alle Module aus dem Baum oben existieren mit
Ausnahme der vier mit "(Phase 5)" markierten Mehrspieler-Module, die
bislang nur spezifiziert sind (siehe Abschnitt 5)
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
  Zeitmessung ueber `${EPOCHREALTIME}` (Bash 5) mit Fallback. Ruht ein
  Stein (Lock Delay scharf, `LOCK_PENDING`), pausiert die Gravitation und
  der Loop lockt erst nach Ablauf von `LOCK_DELAY_MS` seit `TOUCHDOWN_MS`
  (siehe 3.1).
- **Input:** nicht-blockierend ueber `read -rsn1 -t <timeout>`;
  Escape-Sequenzen der Pfeiltasten sauber einlesen. Terminal-Modus mit `stty`
  setzen und ueber einen `trap`-Handler (EXIT/INT/TERM) garantiert
  wiederherstellen. Escape-Sequenzen laufen seit 0.21.0 (Issue #7,
  Analyse in `docs/input-analysis.md`) durch einen **Zustandsautomaten**
  (`key_feed` und die `key_in_*`-Helfer in `lib/input.sh`), dessen
  Zustand in Globals liegt und damit ueber `read_key`-Aufrufe und
  Spiel-Ticks hinweg erhalten bleibt: eine vom Terminal in Stuecken
  zugestellte Sequenz (SSH, tmux/screen, Last) wird unabhaengig von der
  Luecke zwischen ihren Bytes als eine Sequenz zusammengesetzt. Bis
  0.20.0 musste die Entscheidung innerhalb eines Aufrufs fallen, und
  spaet eintreffende Bytes wurden als eigene Tastendruecke angewandt
  (der Schwanz `C` einer Rechts-Pfeiltaste wurde zur Hold-Taste `c`);
  das Hochsetzen des Fortsetzungs-Timeouts auf 50 ms in 0.16.1 hatte
  das nur unwahrscheinlicher gemacht, ab rund 45 ms Byte-Abstand riss
  eine Pfeiltaste weiterhin auseinander. Derselbe Automat konsumiert
  die Sequenzklassen, die zuvor ihre Nutzlast als Tastendruecke
  durchreichten: X10-Mausmeldungen (drei Rohbytes nach `ESC [ M`),
  OSC-/DCS-Terminalantworten, 8-Bit-CSI (`0x9b`), ueberlange
  CSI-Sequenzen und Bracketed Paste (in `term_setup` eingeschaltet,
  Mausmeldungen werden dort zugleich abgeschaltet). Bytes ausserhalb
  des druckbaren ASCII werden verworfen statt gemeldet. Zeitabhaengig
  ist nur noch, wann ein einzelnes `Esc` gemeldet wird
  (`ESC_LONE_MS`, 300 ms); trifft der Rest der Sequenz danach doch noch
  ein, faengt ihn der Zustand `esc_late` ab, sodass auch dann kein
  Schwanz-Byte zur Taste wird. Ein Byte, das Bash (beobachtet mit 5.1)
  im Timeout-Moment zusammen mit dem Timeout-Status liefert, wird
  weiterhin ausgewertet statt verworfen. Regressionstest:
  `tools/key-scan.sh` (72 Faelle, auch mit kuenstlicher Byte-Luecke
  ueber `--gap`). Seit 0.19.0
  behandelt der Input-Layer auch Terminal-Groessenaenderungen: ein
  SIGWINCH-Trap (scharf ab `term_setup`) setzt nur das Flag
  `TERM_RESIZED`; `read_key` wendet es beim naechsten Tick ueber
  `term_resize_apply` an (neu messen mit `term_measure`, Bildschirm
  loeschen, `REDRAW_PENDING` fuer die aufrufende Schleife setzen) und
  blockiert bei Unterschreitung des 48x24-Minimums hinter der
  "resize me"-Overlay, bis das Terminal wieder gross genug ist (siehe
  Phase 4 "Anpassung an Terminalgroesse").
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

## 5. Multiplayer (Phase 5, spezifiziert - noch nicht umgesetzt)

Dieser Abschnitt ist die **Spezifikation**; im Code existiert bislang nur
der Platzhalter-Menuepunkt. Die Umsetzung erfolgt schrittweise nach der
Reihenfolge in Abschnitt 7, Phase 5. Jeder Schritt dort verweist auf die
hier festgelegten Regeln.

Leitentscheidung: **lokales Mehrspieler-Spiel auf einem gemeinsamen Host**
ueber einen **Unix-Domain-Socket** (Nutzerwunsch). Typisches Szenario:
mehrere Leute sind per SSH auf derselben Maschine angemeldet und spielen
gegeneinander. Ein Netzwerk-Transport (TCP) ist damit ausdruecklich **nicht**
Teil von Phase 5; das Protokoll wird aber so entworfen, dass ein
TCP-Transport spaeter nur eine weitere Implementierung derselben
Transport-Schnittstelle ist (siehe 5.3).

### 5.1 Spielerzahl und Spielmodus

- **Standard: 2 bis 4 Spieler**, technisches Maximum **6**
  (`--mp-max N`, Standard 4). Begruendung fuer die Obergrenze:
  - Rechenaufwand: Bash rendert jeden Frame als String; jedes zusaetzliche
    Gegnerfeld kostet ~200 Zellen pro Frame. Ab etwa 6 Feldern ist die
    Framerate auf schwachen Terminals/Hosts nicht mehr zu halten.
  - Bildschirmbreite: ein Mini-Feld braucht 13 Spalten (siehe 5.6);
    bei 4 Gegnern sind das 87 Spalten - schon mehr als die uebliche
    80-Spalten-Breite.
  - Garbage-Zielwahl wird ab ~4 Spielern ohne Zielauswahl-UI beliebig.
  - Mehr als 6 Spieler waeren nur noch als reines Scoreboard sinnvoll;
    das ist bewusst kein Ziel.
- **Modus:** "Versus" - jeder Spieler hat sein eigenes 10x20-Feld, alle
  starten mit demselben Seed (identische 7-Bag-Folge, Fairness).
  Abgebaute Reihen erzeugen Stoerreihen ("Garbage") beim Gegner
  (siehe 5.7). Wer oben rausbaut (Top-Out), scheidet aus und wird
  Zuschauer; wer als Letzter uebrig ist, gewinnt (siehe 5.8).
- Das Quadrat-System bleibt unveraendert die Kernmechanik: Gold- und
  Silber-Quadrate sind im Versus-Modus die staerksten Angriffe.
- Ein spaeterer kooperativer Modus oder ein reiner "Race"-Modus (wer
  zuerst N Reihen hat) ist denkbar, aber nicht Teil dieser Spezifikation.

### 5.2 Transport: Unix-Domain-Socket

- **Socket-Pfad:** `${MP_DIR}/<sitzung>.sock`. `MP_DIR` ist
  standardmaessig `${XDG_RUNTIME_DIR:-/tmp/rowhammer-${UID}}/rowhammer`,
  umstellbar per `--mp-dir DIR` / `ROWHAMMER_MP_DIR`.
  - **Privat (Standard):** Verzeichnis mit `mkdir -m 0700`, nur eigene
    Sitzungen (mehrere Terminals/SSH-Sessions desselben Kontos).
  - **Geteilt (mehrere Konten auf einem Host):** ein Verzeichnis mit
    gemeinsamer Gruppe, `0770`, Socket `mode=0660`. Der Pfad muss vom
    Administrator angelegt werden (z. B. `/var/games/rowhammer`); das
    Spiel legt ein solches Verzeichnis **nicht** selbst an und weigert
    sich, ein world-writable Verzeichnis ohne Sticky-Bit zu benutzen
    (siehe 5.5).
- **Bash kann kein AF_UNIX.** `/dev/tcp` deckt nur TCP ab, es gibt kein
  eingebautes Socket-Primitiv. Deshalb braucht der Mehrspieler-Modus
  **genau ein** externes Hilfsprogramm, in dieser Reihenfolge gesucht:
  1. `socat` (bevorzugt: `UNIX-LISTEN:...,fork` und `UNIX-CONNECT:...`)
  2. `ncat --unixsock` (nmap)
  3. `nc -U` (OpenBSD-netcat; BusyBox-nc kann es nicht)
  Fehlt alles drei, bleibt der Menuepunkt sichtbar, zeigt aber einen
  Hinweis mit den Paketnamen und kehrt zurueck. Der Einzelspieler bleibt
  ohne jede neue Abhaengigkeit lauffaehig; im Debian-Paket wird `socat`
  als `Recommends` eingetragen (kein `Depends`).
- **Alternative ohne Fremdprogramm (dokumentiert, nicht Standard):**
  benannte Pipes (`mkfifo`, Coreutils) - ein Inbox-FIFO fuer den Hub
  plus ein Downstream-FIFO je Client. Funktioniert lokal genauso, ist
  aber fragiler (mehrere Schreiber auf einem FIFO sind nur bis
  `PIPE_BUF` = 4096 Byte atomar, kein sauberes EOF beim Absturz eines
  Clients). Wird nur aufgegriffen, falls sich die Hilfsprogramm-
  Abhaengigkeit als Problem herausstellt. Die Nachrichtenlaenge wird
  trotzdem auf 512 Byte begrenzt (siehe 5.4), damit dieser Fallback
  ohne Protokollaenderung moeglich bleibt.

### 5.3 Prozessmodell

Drei Rollen, strikt getrennt:

- **Client** (`rowhammer.sh`, ein Prozess je Spieler und Terminal):
  spielt die eigene Runde, rendert, sendet den eigenen Zustand, empfaengt
  Gegnerzustand und Garbage. Der Client haelt die Verbindung als
  **Coprocess**: `coproc MP_LINK { socat UNIX-CONNECT:"${sock}" -; }`.
  Damit sind Lese- und Schreib-FD normale Bash-FDs; Lesen erfolgt
  nicht-blockierend mit `read -t 0` (Datenpruefung) plus `read -r -t 0.01`
  (Zeile holen) einmal pro Tick. Die Taktung des Game-Loops bleibt
  unveraendert beim `read`-Timeout auf STDIN - Bash kann nicht auf zwei
  FDs gleichzeitig warten, deshalb bleibt die Tastatur der Taktgeber und
  der Socket wird pro Tick nur geleert (max. N Zeilen pro Tick, damit ein
  fluteter Socket den Frame nicht anhaelt, siehe 5.5).
- **Hub** (`rowhammer.sh --mp-hub`, ein Prozess je Sitzung, headless):
  autoritative Sitzungslogik. Kein Terminal, kein Rendering, kein
  `stty`, keine Signal-Handler des Spiels. Er haelt die Spielerliste,
  verteilt Seed und Startsignal, verrechnet Garbage, verteilt
  Zustandsupdates und erkennt Timeouts. Der Host-Client startet ihn im
  Hintergrund (`setsid`-artig entkoppelt), damit ein haengender Client
  nie den Hub blockiert und umgekehrt.
- **Bridge** (`rowhammer.sh --mp-bridge`, ein kurzlebiger Prozess je
  Verbindung): wird von `socat UNIX-LISTEN:...,fork` gestartet, hat die
  Socket-Enden auf STDIN/STDOUT und uebersetzt zwischen Socket und den
  FIFOs des Hubs (Client -> `inbox`-FIFO mit vorangestellter Client-ID,
  Hub -> privates `down.<id>`-FIFO -> Socket). So spricht der Hub nur
  mit FIFOs (Bash-nativ) und `socat` nur mit dem Socket; ein Wechsel des
  Transports (TCP, FIFO-Only) tauscht ausschliesslich die Bridge aus.

Modulschnitt (neue Dateien, siehe auch 4.2):

- `lib/net.sh` - Transport und Rahmung: Hilfsprogramm-Erkennung,
  Verbindungsauf-/abbau, Zeilen senden/empfangen, Laengen- und
  Zeichensatzpruefung, Debug-Mitschnitt. Kennt **keine** Spielregeln.
- `lib/proto.sh` - Nachrichtentabelle, Serialisierung und
  **Validierung** (Whitelist der Verben, Feldtypen, Wertebereiche).
  Kennt keine Sockets und keinen Bildschirm.
- `lib/hub.sh` - Sitzungs- und Rundenlogik des Hubs (Lobby, Start,
  Garbage-Verrechnung, KO-Reihenfolge, Timeouts).
- `lib/mp.sh` - Client-Seite: Lobby-Menue, Sitzungssuche, Anbindung des
  Game-Loops, Puffer fuer Gegnerzustaende.
- Gegner-Darstellung kommt in `lib/render.sh` dazu (`render_peer`,
  `draw_frame`-Erweiterung), damit alles Zeichnen an einer Stelle bleibt.

Voraussetzung im bestehenden Code: die Rundenlogik muss ohne Rendering
und ohne Tastatur laufen koennen (Roadmap-Punkt "Spiellogik entkoppeln").
Konkret: `game_reset`, `step_down`, `lock_and_next`, `hold_piece`,
`try_move`, `try_rotate` duerfen weder zeichnen noch lesen; `DIRTY`
markiert nur. Das ist ohnehin fast erreicht - offen sind die Stellen, an
denen `flash_rows` den Loop anhaelt und `record_round` Bildschirme zeigt.

### 5.4 Protokoll v1

- **Rahmen:** eine Nachricht = eine Zeile, `\n`-terminiert, reines
  druckbares ASCII (0x20-0x7E), maximal **512 Byte** inklusive Zeilenende.
  Felder durch **ein Leerzeichen** getrennt, erstes Feld ist das Verb in
  Grossbuchstaben. Unbekannte Verben werden ignoriert (Vorwaerts-
  kompatibilitaet), fehlerhafte Zeilen fuehren zum Verbindungsabbruch
  (siehe 5.5).
- **Versionierung:** `PROTO_VERSION=1`. Der Hub lehnt abweichende
  Versionen im `HELLO` mit `ERR proto ...` ab. Gemaess der Arbeitsregel
  "keine Abwaertskompatibilitaet" wird das Protokoll bei Bedarf
  hochgezaehlt statt kompatibel erweitert.
- **Client -> Hub**

  | Nachricht | Felder | Bedeutung |
  | --- | --- | --- |
  | `HELLO` | `<proto> <name> <caps>` | Anmeldung; `caps` = Komma-Liste (z. B. `board`) |
  | `READY` | `<0 oder 1>` | Bereitschaft in der Lobby |
  | `STATE` | `<lines> <rows> <level> <gold> <silver> <height> <pending>` | eigener Zaehlerstand, bei Aenderung, max. 10/s |
  | `BOARD` | `<200 Zeichen>` | Feld-Snapshot, nur wenn der Hub `NEEDBOARD 1` gesetzt hat, max. 5/s |
  | `CLEAR` | `<lines> <silver> <gold>` | ein Reihenabbau als Angriffs-Meldung (Hub rechnet daraus die Garbage aus) |
  | `TOPOUT` | - | eigenes Game Over |
  | `PONG` | `<token>` | Antwort auf `PING` |
  | `BYE` | - | geordnetes Verlassen |

- **Hub -> Client**

  | Nachricht | Felder | Bedeutung |
  | --- | --- | --- |
  | `WELCOME` | `<slot> <proto> <maxplayers>` | Anmeldung akzeptiert |
  | `ROSTER` | `<slot> <name> <ready> <state>` | eine Zeile je Spieler, bei jeder Aenderung |
  | `SEED` | `<seed>` | gemeinsamer Seed fuer die 7-Bag-Folge |
  | `START` | `<countdown_ms>` | Rundenstart |
  | `PEER` | `<slot> <lines> <rows> <level> <gold> <silver> <height> <pending> <state>` | Zustand eines Mitspielers |
  | `PEERBOARD` | `<slot> <200 Zeichen>` | Feld-Snapshot eines Mitspielers |
  | `NEEDBOARD` | `<0 oder 1>` | ob dieser Client Snapshots senden soll (spart Last, wenn niemand Stufe 2 anzeigt) |
  | `GARBAGE` | `<count> <hole>` | eingehende Stoerreihen, Lochspalte 0-9 |
  | `KO` | `<slot> <platz>` | Spieler ausgeschieden |
  | `END` | `<siegerslot>` | Runde vorbei |
  | `PING` | `<token>` | Lebendpruefung, alle 2 s |
  | `ERR` | `<code> <text>` | Ablehnung/Fehler, danach ggf. Abbruch |

- **Feld-Snapshot (`BOARD`/`PEERBOARD`):** genau **200 Zeichen**, Zeile
  fuer Zeile von oben (y=HIDDEN_ROWS) nach unten, je Zelle ein Zeichen
  aus `.IOTSZJLgsx`: `.` leer, Grossbuchstabe = Tetromino-Sorte,
  `g` Gold-Quadrat, `s` Silber-Quadrat, `x` Garbage. Feste Laenge statt
  Lauflaengenkodierung, weil die Validierung dadurch trivial und
  lueckenlos ist (Laenge + Zeichensatz); 200 Byte bei max. 5 Hz und 6
  Spielern sind lokal unkritisch (~6 kB/s). Der aktive, noch fallende
  Stein wird **nicht** mitgesendet (er waere veraltet, sobald er ankommt);
  optional spaeter als eigenes `PIECE`-Verb.
- **Autoritaet:** der Hub ist die einzige Quelle fuer Garbage-Mengen,
  Lochspalten, KO-Reihenfolge und Rundenende. Clients melden nur
  Ereignisse (`CLEAR`, `TOPOUT`); sie berechnen nie selbst, wie viel
  Garbage der Gegner bekommt. Damit ist der offensichtlichste Cheat
  ("ich sende einfach 20 Reihen") ausgeschlossen. Ein manipulierter
  Client kann weiterhin falsche `CLEAR`-Meldungen abgeben - vollstaendige
  Cheat-Sicherheit ist ohne serverseitige Simulation nicht erreichbar und
  ist **kein** Ziel (siehe Vertrauensmodell in 5.5).
- **Zeitverhalten:** `PING` alle 2 s, Timeout nach 6 s ohne Lebenszeichen
  -> Spieler gilt als abgestuerzt (siehe 5.8). Der Hub laeuft mit einem
  eigenen Tick von 50 ms (`read -t` auf dem Inbox-FIFO, kein `sleep`).

### 5.5 Sicherheit

Bedrohungsmodell: Mitspieler auf demselben Host sind **halb
vertrauenswuerdig**. Sie duerfen im Spiel schummeln koennen (das ist
hinnehmbar), aber unter keinen Umstaenden

1. Code im Prozess eines anderen Spielers ausfuehren,
2. dessen Terminal uebernehmen oder Dateien beschaedigen,
3. den fremden Prozess zum Absturz oder Haengen bringen.

Regeln, verbindlich fuer `lib/net.sh`, `lib/proto.sh`, `lib/hub.sh` und
jede Stelle, die Empfangenes anfasst:

- **Kein `eval`, kein `source`, keine Kommandosubstitution auf
  Empfangenem.** Nie einen Befehlsstring aus Netzdaten bauen. Empfangene
  Werte landen ausschliesslich in Variablen und werden ausschliesslich
  als `"${var}"` benutzt.
- **Arithmetik ist ein Injektionsziel.** `$(( ))` und `((  ))` werten
  ihren Inhalt rekursiv aus: `$(( x ))` mit `x='a[$(rm -rf ~)]'` fuehrt
  den Befehl aus. Deshalb: jedes Zahlenfeld **vor** der ersten Rechnung
  gegen `^[0-9]{1,9}$` pruefen und auf den erlaubten Bereich begrenzen.
  Dasselbe gilt fuer alles, was als Array-Index oder als Schluessel eines
  assoziativen Arrays benutzt wird.
- **Zeichensatzfilter vor allem anderen.** Jede empfangene Zeile wird
  verworfen, wenn sie ein Byte ausserhalb 0x20-0x7E enthaelt. Das ist die
  wichtigste Einzelmassnahme: ein Spielername mit ANSI-Escapes koennte
  sonst den Bildschirm des Gegners umschreiben, den Fenstertitel setzen
  oder - je nach Terminal - ueber Antwort-Sequenzen Text in dessen
  Eingabepuffer schreiben. Der Filter greift im Empfangspfad, also
  einmal zentral, nicht erst beim Zeichnen.
- **Whitelist statt Blacklist.** Zerlegen mit `read -r verb rest`,
  danach `case "${verb}"` mit genau den Verben aus 5.4; jedes Feld hat
  ein eigenes Muster (`^[A-Za-z0-9_-]{1,16}$` fuer Namen,
  `^[0-9]{1,9}$` fuer Zahlen, `^[.IOTSZJLgsx]{200}$` fuer Snapshots,
  `^[0-9]$` fuer die Lochspalte). Ein Feld, das nicht passt, macht die
  ganze Nachricht ungueltig.
- **Harte Grenzen gegen Ressourcen-Angriffe:** Zeilenlaenge 512 Byte
  (Lesen mit `read -r -N` bzw. Laengenpruefung, ueberlange Zeilen werden
  bis zum naechsten `\n` verworfen), max. 64 Nachrichten pro Sekunde und
  Client (danach Verbindungsabbruch), max. `--mp-max` Verbindungen, max.
  16 Nachrichten pro Tick aus dem Socketpuffer, damit ein Fluter den
  Frame nicht anhaelt. Ein Client, der dreimal in Folge Muell schickt,
  wird getrennt (`ERR proto`), nicht toleriert.
- **Kein Absturz durch Fremddaten:** Der Empfangspfad laeuft nicht unter
  `set -e`-Annahmen; jede Pruefung endet in einem definierten "Nachricht
  verwerfen"-Zweig. Ein Verbindungsabbruch (EOF, `EPIPE`) beendet die
  Runde geordnet, nie das Terminal-Setup (der bestehende `trap` bleibt
  zustaendig).
- **Dateisystem:** `umask 0077` fuer alle Sitzungsdateien; das
  Sitzungsverzeichnis muss dem Aufrufer oder root gehoeren und darf nicht
  world-writable ohne Sticky-Bit sein - sonst Abbruch mit Meldung
  (Schutz gegen Socket-Squatting und Symlink-Fallen in `/tmp`). Vor dem
  Anlegen: vorhandenen Pfad pruefen (kein Symlink, kein fremder
  Eigentuemer), `unlink-early` beim Listener, Aufraeumen des Sockets im
  bestehenden EXIT-`trap`. Sitzungsnamen werden gegen
  `^[A-Za-z0-9_-]{1,16}$` geprueft, bevor sie in einen Pfad eingehen
  (kein `..`, kein `/`).
- **Ausgehende Daten sind ebenfalls zu pruefen:** der eigene Spielername
  stammt aus der Config und kann exotisch sein; er wird beim Senden auf
  das Namensmuster reduziert, damit ein Client nicht unbeabsichtigt
  Muell erzeugt, den der Hub dann verwerfen muss.
- **Gegenprobe beim Rendern:** Namen und Zahlen werden vor der Ausgabe
  ein zweites Mal auf Laenge und Zeichensatz geprueft und hart
  abgeschnitten (Verteidigung in der Tiefe - auch der Hub gilt nicht als
  vertrauenswuerdig, er koennte ein fremdes Programm sein).
- **Debug-Modus:** der komplette Verkehr wird in `net.log`
  (`printf %q`-quotiert, wie `input.log`) mitgeschnitten, damit
  Protokollfehler und Angriffsversuche nachvollziehbar sind.
- **Testbarkeit:** ein Fuzz-Skript (`tools/net-fuzz.sh`) speist zufaellige
  und gezielt boesartige Zeilen (ANSI-Escapes, `$(...)`, Backticks,
  `../`-Pfade, 100-kB-Zeilen, Nullbytes, halbe Zeilen ohne `\n`) in
  Hub- und Client-Parser. Abnahmekriterium: kein Prozess stirbt, kein
  Befehl wird ausgefuehrt, kein Byte ausserhalb 0x20-0x7E erreicht das
  Terminal.

### 5.6 Darstellung der Mitspieler

Das bestehende Layout ist fest: Feld 22 Spalten + 2 Abstand + Seitenleiste
24 Spalten = 48 Spalten, 24 Zeilen Minimum. Die Mitspieler kommen
**rechts daneben**, das eigene Feld bleibt unveraendert links.

Drei Detailstufen, automatisch nach verfuegbarer Terminalgroesse und
Spielerzahl gewaehlt (`--mp-view auto|full|compact|score` erzwingt eine
Stufe):

- **Stufe 2 "full" - Mini-Feld je Gegner.** Ein Zeichen pro Zelle
  (das eigene Feld nutzt zwei), also 10 Spalten Inhalt + Rahmen = 12,
  plus 1 Spalte Abstand = **13 Spalten je Gegner**, 22 Zeilen hoch
  (Kopfzeile mit Name/Slot, 20 Feldzeilen, Fusszeile mit
  `Rows`/`pending`). Farben wie im eigenen Feld (Gold/Silber bleiben
  erkennbar, Garbage dunkelgrau). Bedarf: `48 + n*13` Spalten -
  61 (2 Spieler), 74 (3), 87 (4), 113 (6).
- **Stufe 1 "compact" - Textzeile je Gegner.** Kein Feld, sondern je
  Gegner zwei Zeilen in der Seitenleiste:
  `<name8> R<rows> L<lines>` und ein 10 Zeichen breiter Stapelhoehen-
  Balken plus Markierung fuer eingehende Garbage und KO-Status. Passt in
  die vorhandenen 24 Spalten der Seitenleiste, kostet dort aber Platz:
  ab 3 Gegnern entfaellt die Vorschau des dritten Next-Steins.
  Bedarf: unveraendert 48 Spalten, aber 2 Zeilen je Gegner.
- **Stufe 0 "score" - Scoreboard.** Eine Zeile je Gegner:
  `<platz> <name8> <rows>`, sortiert nach Rows, KO-Spieler grau und
  ans Ende. Braucht 1 Zeile je Gegner und passt immer in 48x24.

Auswahlregel fuer `auto` (bei jedem Resize neu ausgewertet, der
SIGWINCH-Pfad aus 0.19.0 ruft sie mit auf):

1. Reicht `48 + n*13` Spalten und 24 Zeilen -> Stufe 2.
2. Sonst: reichen `24 - belegte Seitenleistenzeilen` fuer `2*n` Zeilen
   -> Stufe 1.
3. Sonst -> Stufe 0. Unter 48x24 greift weiterhin die bestehende
   "resize me"-Overlay.

Nur in Stufe 2 sendet ein Client Feld-Snapshots; der Hub schaltet das je
Client per `NEEDBOARD` (siehe 5.4), sodass kleine Terminals keine
Snapshot-Last erzeugen. Genau das ist die Antwort auf "bei vielen
Spielern und kleinem Terminal nur Reihen und Bloecke": die Stufen 1 und 0
uebertragen und zeigen nur noch Zaehler.

Uebertragene und angezeigte Statistiken je Mitspieler (Stufe 2 zeigt
alle, Stufe 1 die ersten vier, Stufe 0 nur Name und Rows):
Name, Rows (gewichtete Reihen = Score), Lines, Stapelhoehe,
eingehende/ausstehende Garbage, Level, Gold- und Silberzaehler,
Status (`lobby`/`play`/`ko`/`gone`). Bewusst **nicht** uebertragen:
Next-Queue und Hold des Gegners (waere im Original nicht sichtbar und
kostet Bandbreite), die Spielzeit (der Hub kennt die Rundenzeit selbst),
Tastendruecke.

Jeder Slot bekommt eine feste Akzentfarbe fuer Name und Rahmen, damit
Zuordnung auch ohne Namenslesen funktioniert.

### 5.7 Garbage-Regeln

- **Angriffswert eines Reihenabbaus** (Hub-Berechnung aus `CLEAR`):
  - 1/2/3/4 Reihen -> 0/1/2/4 Garbage-Reihen (Tetris lohnt sich),
  - je **Silber-Quadrat** in den abgebauten Reihen: **+2**,
  - je **Gold-Quadrat**: **+4**,
  - Deckel: **10** Reihen pro Lock.
  Die Werte spiegeln die Reihenwertung aus 3.2 (1/+5/+10) in halbierter
  Form und sind justierbar (`GARBAGE_*` in `lib/hub.sh`). Nach
  Playtesting nachziehen.
- **Verrechnung (Cancel):** eingehende Garbage wird zunaechst in einer
  Warteschlange gehalten. Ein eigener Abbau reduziert erst die eigene
  Warteschlange, nur der Rest geht raus. Das belohnt Gegenangriffe statt
  reiner Reaktion.
- **Einspielen:** ausstehende Garbage wird **beim naechsten Lock nach dem
  Reihenabbau** von unten eingeschoben, nie waehrend ein Stein faellt.
  Damit bleibt der laufende Zug planbar; die Warteschlange ist im HUD
  als Balken neben dem Feld sichtbar (Vorwarnung).
- **Form der Garbage-Reihe:** volle Reihe mit **genau einem Loch**; die
  Lochspalte kommt vom Hub (`GARBAGE <count> <hole>`) und bleibt fuer
  alle Reihen eines Angriffs gleich. Der Hub zieht sie aus seinem
  eigenen RNG, damit kein Client sie beeinflussen kann.
- **Auswirkung auf das Quadrat-System:** Garbage-Zellen bekommen die
  eigene Sorte `x`, Instanz-ID 0 und gelten als "zerschnitten"; sie
  koennen also nie Teil eines Quadrats werden. Das Hochschieben
  verschiebt `BOARD`, `BOARD_ID` und `BOARD_SQ` zeilenweise gemeinsam -
  Instanzen bleiben unversehrt und behalten ihren Gold-/Silber-Status,
  nur ihre Koordinaten wandern. Faellt dabei eine belegte Zelle aus dem
  sichtbaren Bereich oder kollidiert der aktive Stein nach dem
  Verschieben, ist das ein Top-Out.
- **Zielwahl:**
  - 2 Spieler: der Gegner, trivial.
  - 3+ Spieler: Standard `random` (der Hub waehlt je Angriff einen
    lebenden Gegner), Alternativen `all` (jeder Gegner bekommt die volle
    Menge, sehr aggressiv) und `even` (gleichmaessig aufgeteilt, Rest an
    einen zufaelligen). Umschaltbar in der Lobby, vom Hub entschieden
    und in `KO`/`GARBAGE` nachvollziehbar geloggt. Eine manuelle
    Zielauswahl per Taste ist bewusst ausgeklammert (Tastenbelegung ist
    voll, und sie skaliert schlecht).

### 5.8 Rundenende, Ausscheiden, Verbindungsabbruch

- **Top-Out:** Der Client sendet `TOPOUT`, spielt nicht weiter und wird
  **Zuschauer** - er sieht die verbleibenden Felder bis zum Rundenende.
  Der Hub vergibt den Platz von hinten (erster Ausgeschiedener = letzter
  Platz) und meldet `KO <slot> <platz>`.
- **Sieg:** letzter lebender Spieler. Steigen alle bis auf einen aus, ist
  die Runde vorbei (`END <slot>`). Bei gleichzeitigem KO entscheidet die
  hoehere Rows-Zahl, danach der niedrigere Slot.
- **Verbindungsabbruch eines Clients:** EOF oder 6 s ohne `PONG` ->
  Status `gone`, gilt wie ein KO, die Runde laeuft weiter. Kein
  Reconnect in v1 (Zustandsuebertragung waere aufwendig; die Runde
  dauert wenige Minuten).
- **Ausfall des Hubs:** alle Clients bekommen EOF, zeigen "Verbindung
  verloren" und kehren ins Hauptmenue zurueck. Die Runde wird wie ein
  abgebrochenes Spiel behandelt und gemaess 3.3 gewertet (abgebrochene
  Runden zaehlen).
- **Verlassen ueber das Menue:** wie im Einzelspieler beendet "Runde
  beenden" die Runde; zusaetzlich geht ein `BYE` raus. Eine
  Mehrspieler-Runde kann **nicht** ins Hauptmenue gelegt und spaeter
  fortgesetzt werden (die anderen warten nicht) - der Eintrag "Ins
  Hauptmenue" fehlt im Mehrspieler-Pausenmenue.
- **Pause:** eine echte Pause gibt es im Mehrspieler nicht. `p` zeigt nur
  eine lokale Einblendung, das Spiel laeuft weiter; das Pausenmenue
  (`Esc`/`x`) bietet "Fortsetzen" und "Runde verlassen". Das muss im HUD
  deutlich stehen, sonst ist es eine Falle.
- **Wertung und Persistenz:** die abgebauten Reihen einer
  Mehrspieler-Runde zaehlen wie im Einzelspieler auf den
  Weltwunder-Zaehler und in die Statistik ein (es sind echte Reihen).
  Die Highscore-Liste bleibt dem Einzelspieler vorbehalten, damit
  Garbage-beeinflusste Runden die Bestenliste nicht verzerren; die
  Statistik bekommt stattdessen eigene Zaehler (Siege, Teilnahmen,
  gesendete/erhaltene Garbage). -> Entscheidung noch zu bestaetigen,
  siehe Abschnitt 8.

### 5.9 Auswirkungen auf bestehende Systeme

- **Rendering-Performance:** mit bis zu 6 Feldern reicht das heutige
  "kompletter Frame als String" nicht mehr. Der bestehende
  Phase-4-Punkt "nur geaenderte Zellen zeichnen" wird damit zur
  **Voraussetzung** und in der Reihenfolge vorgezogen.
- **Game-Loop:** pro Tick zusaetzlich Socket leeren, Peer-Puffer
  aktualisieren, eigenen Zustand senden (nur bei Aenderung). Der
  Sendepfad darf nie blockieren (voller Socketpuffer -> Nachricht
  verwerfen, ausser bei `CLEAR`/`TOPOUT`, die zuverlaessig zugestellt
  werden muessen).
- **`flash_rows`** haelt den Loop heute ~280 ms an. Im Mehrspieler darf
  das die Verbindung nicht verhungern lassen: waehrend der Animation
  wird der Socket weiter geleert (Tastendruecke bleiben wie bisher
  verworfen).
- **Seed:** `--seed` wird im Mehrspieler vom Hub-Seed uebersteuert; ein
  gesetzter `--seed` beim Host wird zum Sitzungs-Seed.
- **Terminalgroesse:** der SIGWINCH-Pfad waehlt zusaetzlich die
  Detailstufe neu (siehe 5.6).
- **Debug-Modus:** neue Datei `net.log`; `events.log` bekommt
  Mehrspieler-Ereignisse (Join/Leave, Garbage rein/raus, KO, Hub-Start).
- **Paketierung:** `socat` als `Recommends`; `make install` unveraendert.

### 5.10 CLI und Konfiguration

Neue Optionen (jeweils auch als Umgebungsvariable, Praezedenz
Standard < Config < Env < CLI, wie in Abschnitt 6 gefordert):

| Option | Umgebung | Bedeutung |
| --- | --- | --- |
| `--mp-host [NAME]` | `ROWHAMMER_MP_HOST` | Sitzung eroeffnen (Standardname = Benutzername) |
| `--mp-join NAME` | `ROWHAMMER_MP_JOIN` | Sitzung beitreten |
| `--mp-dir DIR` | `ROWHAMMER_MP_DIR` | Sitzungsverzeichnis (siehe 5.2) |
| `--mp-max N` | `ROWHAMMER_MP_MAX` | Spielerzahl 2..6, Standard 4 |
| `--mp-view MODE` | `ROWHAMMER_MP_VIEW` | `auto`, `full`, `compact`, `score` |
| `--mp-target MODE` | `ROWHAMMER_MP_TARGET` | `random`, `all`, `even` (nur Host) |
| `--mp-hub` | - | interner Modus: Hub-Prozess (nicht dokumentiert im Menue) |
| `--mp-bridge` | - | interner Modus: Socket-Bridge |
| `--mp-bot` | `ROWHAMMER_MP_BOT` | Testclient ohne Terminal, spielt zufaellig |

Menuefuehrung: "Mehrspieler" -> "Spiel eroeffnen" / "Spiel beitreten"
(Liste der gefundenen Sitzungen im `MP_DIR`, Name + Spielerzahl aus
einer `INFO`-Abfrage) / "Zurueck". Danach eine Lobby mit Spielerliste,
Bereitschaftsstatus und - fuer den Host - Zielwahl-Modus und Start.

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
- [x] Lock Delay einbauen (Version 0.18.0): ein aufsetzender Stein wird
      nicht sofort gelockt, sondern ruht ein Gnadenfenster
      (`LOCK_DELAY_MS`, 250 ms) und kann darin weiter verschoben/gedreht
      werden; der Touchdown-Timer wird nur zurueckgesetzt, wenn der Stein
      durch die Verschiebung wieder ins Fallen geraet (siehe 3.1)
- [x] Anpassung an Terminalgroesse (Version 0.19.0): das feste
      Layout braucht weiterhin mindestens 48x24, aber eine
      Groessenaenderung waehrend des Spiels wird jetzt live behandelt.
      Ein SIGWINCH-Trap (scharf ab `term_setup`) setzt nur ein Flag
      (`TERM_RESIZED`, signal-sicher), das `read_key` beim naechsten
      Tick ueber `term_resize_apply` anwendet: Groesse neu messen
      (`term_measure`), Bildschirm loeschen und die aufrufende Schleife
      neu zeichnen lassen (`REDRAW_PENDING`). Faellt das Terminal unter
      das Minimum, blockiert das Spiel hinter einer kompakten
      "resize me"-Overlay (`term_too_small_screen` in `lib/render.sh`,
      zeigt Soll- und Ist-Groesse), bis es wieder gross genug ist; im
      Spiel-Loop werden Fall- und Spielzeituhr nach dem Resize neu
      angesetzt (`play_clock_resume`), damit das blockierte Intervall
      weder als Fallzeit noch als Spielzeit zaehlt. Menues und
      Info-Bildschirme zeichnen nach einem Resize ebenfalls neu
      (`REDRAW_PENDING` in `menu_run`, `menu_message`, `prompt_rebind`
      und `wonder_screen`)
- [x] Blinkeffekt beim Reihenabbau (Version 0.20.0): abgebaute Reihen
      blinken kurz auf, bevor sie entfernt werden und das naechste Teil
      erscheint (`board_full_rows`, `flash_rows`, `FLASH_ROWS`/
      `FLASH_STATE`; Dauer ueber `FLASH_MS`/`FLASH_CYCLES`, siehe 3.1)
- [ ] Performance-Optimierung des Renderings (nur geaenderte Zellen zeichnen)
- [ ] Layout anpassen: Rendering zentriert im Terminal; Stats unten,
      naechste drei Steine oben rechts, Hold-Stein links
- [x] README mit Screenshots/Asciinema aktualisieren (Abschnitt
      "Vorschau" im README): vier kurze, echte Spielsequenzen als
      asciinema-Aufnahmen (`.cast`) und GIF unter `docs/demo/` - Tetris
      (Vierfach-Abbau), Silber-Quadrat (vier gemischte Teile),
      Gold-Quadrat (vier gleiche Teile) und die Weltwunder-Baustelle.
      Die Clips sind mit festem `--seed` reproduzierbar aufgenommen
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
- [x] Eingabeschicht gehaertet (Version 0.21.0, Nachfassen zu Issue #7,
      Analyse in `docs/input-analysis.md`): eine Vermessung aller
      Byte-Folgen, die ein Terminal senden kann (neues Werkzeug
      `tools/key-scan.sh`, 72 Faelle), zeigte 12 Folgen, die eine
      falsche Spielaktion ausloesten - zerrissene Pfeiltasten ab rund
      45 ms Byte-Abstand (der 0.16.1-Fix hatte das Fenster nur von
      20 ms auf 50 ms vergroessert, und `ESC` oeffnet seit 0.12.0
      zusaetzlich das Pausenmenue), X10-Mausklicks (drei Rohbytes nach
      `ESC [ M`, jeder Klick ein Hard-Drop), OSC-/DCS-Antworten des
      Terminals (ganze Nutzlast als Tasten), 8-Bit-CSI (`0x9b`),
      CSI-Sequenzen ueber der 16-Byte-Bremse und eingefuegter Text
      (Mittelklick-Paste). Umgesetzt sind die Vorschlaege L1-L6 aus dem
      Analyse-Dokument (Zustandsautomat ueber Tick-Grenzen, OSC/DCS,
      X10-Maus, Bracketed Paste, 8-Bit-CSI und groessere Laengenbremse,
      Verwerfen wirkungsloser Bytes; siehe 4.3). L7 (Burst-Bremse)
      wurde bewusst weggelassen, weil sie auch legitimes Autorepeat
      beschneiden wuerde. `tools/key-scan.sh` laeuft ohne Befund durch,
      auch mit `--gap 0.2`; jenseits von `ESC_LONE_MS` (300 ms
      Byte-Abstand) wird ein `Esc` gemeldet, der Sequenzschwanz aber
      weiterhin geschluckt - der Hold-Wechsel aus Issue #7 kann nicht
      mehr auftreten
- [x] Punktesystem-Umbau (Version 0.16.0, Nutzerentscheidung):
      abgebaute Reihen sind die einzige Punktquelle, der Score ist
      identisch mit der gewichteten Reihenwertung "Rows" (1 je Reihe,
      +5 je Silber-, +10 je Gold-Streifen, +1 je Tetris, siehe 3.2).
      Entfallen sind Drop-Punkte, Quadrat-Bildungs-Boni (2000/1000)
      und die Level-Skalierung; Highscore (Rangfolge nach Rows) und
      Statistik speichern kein separates Score-Feld mehr (siehe 4.5)

### Phase 5 - Multiplayer (spezifiziert in Abschnitt 5, noch nicht umgesetzt)

Die Schritte sind so sortiert, dass jeder fuer sich lauffaehig und
testbar ist und der Mehrspieler-Modus Stueck fuer Stueck waechst. Die
Details stehen jeweils im genannten Unterabschnitt.

- [ ] **Schritt 1 - Vorarbeit: Entkopplung und Render-Performance** (siehe 5.3, 5.9).
      Rundenlogik ohne Rendering/Input lauffaehig machen (`game_reset`,
      `step_down`, `lock_and_next`, `try_move`, `try_rotate`, `hold_piece`
      zeichnen nicht mehr selbst; `record_round` trennt Verbuchen und
      Anzeigen), und den Phase-4-Punkt "nur geaenderte Zellen zeichnen"
      vorziehen - mit bis zu sechs Feldern reicht der Voll-Frame nicht.
      Loesungsweg: Diff gegen den zuletzt gesendeten Frame-Puffer je
      Zelle, Cursor-Positionierung nur fuer geaenderte Bereiche;
      `screen_write` bleibt der einzige Ausgabekanal (Debug-Log!).
      Abnahme: Einzelspieler unveraendert spielbar, Frame-Kosten messbar
      gesunken.
- [ ] **Schritt 2 - Transportschicht `lib/net.sh`** (siehe 5.2, 5.3).
      Hilfsprogramm-Erkennung (`socat` > `ncat --unixsock` > `nc -U`) mit
      klarer Meldung, wenn nichts vorhanden ist; Verbindung als Coprocess,
      nicht-blockierendes Leeren des Sockets pro Tick, Zeilenrahmung mit
      512-Byte-Grenze, Aufraeumen im bestehenden EXIT-`trap`,
      Debug-Mitschnitt `net.log`. Abnahme: zwei Testprozesse tauschen
      ueber einen Socket Zeilen aus, ohne dass der Game-Loop stockt.
- [ ] **Schritt 3 - Protokoll v1 und Validierung `lib/proto.sh`** (siehe 5.4, 5.5).
      Nachrichtentabelle, Serialisierung, Whitelist-Parser mit
      Feldmustern, Zeichensatzfilter 0x20-0x7E, Ratenbegrenzung.
      Zusammen mit `tools/net-fuzz.sh` (boesartige Zeilen: ANSI-Escapes,
      `$(...)`, Backticks, `../`, Ueberlaenge, Nullbytes, halbe Zeilen).
      Abnahme: kein Prozess stirbt, kein Befehl laeuft, kein
      Steuerzeichen erreicht das Terminal.
- [ ] **Schritt 4 - Hub-Prozess und Lobby** (siehe 5.3, 5.10).
      `--mp-hub` headless, `--mp-bridge`, Sitzungsverzeichnis mit den
      Rechte- und Symlink-Pruefungen aus 5.5, Menue "Spiel eroeffnen /
      Spiel beitreten", Spielerliste, Bereitschaft, Seed-Verteilung,
      Countdown, Ping/Timeout, geordnetes Beenden. Noch **ohne**
      Interaktion im Spiel: alle spielen parallel ihre eigene Runde.
      Abnahme: vier Terminals treten bei, starten gemeinsam, ein
      `kill -9` auf einen Client stoert die anderen nicht.
- [ ] **Schritt 5 - Mitspieler-Anzeige Stufe 0 und 1** (siehe 5.6).
      `PEER`-Zustaende puffern, Scoreboard- und Kompaktansicht in der
      Seitenleiste, Detailstufen-Auswahl inklusive Neuberechnung beim
      Resize, `--mp-view`. Erstes sichtbares Mehrspieler-Erlebnis, laeuft
      im 48x24-Minimum. Abnahme: vier Spieler sehen gegenseitig ihre
      Rows/Lines live.
- [ ] **Schritt 6 - Mitspieler-Anzeige Stufe 2 (Mini-Felder)** (siehe 5.4, 5.6).
      Feld-Snapshot in 200 Zeichen kodieren/dekodieren, `NEEDBOARD`-
      Steuerung, Drosselung auf 5 Hz und "nur bei Aenderung", Layout
      rechts neben der Seitenleiste, Akzentfarbe je Slot. Abnahme: bei
      4 Spielern in einem 90x24-Terminal bleibt die Framerate stabil.
- [ ] **Schritt 7 - Garbage-Mechanik** (siehe 5.7).
      Zellsorte `x`, zeilenweises Hochschieben von `BOARD`/`BOARD_ID`/
      `BOARD_SQ`, Top-Out-Erkennung beim Schieben, Warteschlange mit
      Verrechnung, Hub-seitige Angriffsberechnung und Lochspalte,
      Vorwarn-Balken im HUD. Zuerst nur fuer 2 Spieler. Abnahme:
      Tetris und Gold-Quadrat erzeugen die spezifizierten Mengen,
      Quadrate ueberleben das Hochschieben.
- [ ] **Schritt 8 - Rundenende, KO-Reihenfolge, Zuschauermodus,
      Verbindungsabbruch** (siehe 5.8).
      `TOPOUT`/`KO`/`END`, Platzierung, Endbildschirm mit Rangliste,
      Timeout- und EOF-Behandlung, Mehrspieler-Pausenmenue ohne
      "Ins Hauptmenue", Verbuchung von Wunder-Fortschritt und Statistik.
      Abnahme: eine Runde laeuft sauber bis zum Sieger, ein abgestuerzter
      Client beendet sie nicht.
- [ ] **Schritt 9 - Drei bis sechs Spieler** (siehe 5.1, 5.6, 5.7).
      Zielwahl-Modi `random|all|even`, Layout-Raster fuer mehrere
      Mini-Felder, `--mp-max`, Lasttests. Abnahme: sechs Bots spielen
      eine Runde ohne Verbindungs- oder Renderprobleme durch.
- [ ] **Schritt 10 - Test-Bot, Dokumentation, Paketierung** (siehe 5.10, 5.9).
      `--mp-bot` (Client ohne Terminal, zufaellige Zuege) fuer
      reproduzierbare Mehrspieler-Tests ohne N Terminals; README-Kapitel
      mit Beispiel-Ablauf ueber SSH; asciinema-Clip mit zwei Feldern;
      `socat` als `Recommends` im Debian-Paket.
- [ ] **Schritt 11 - Sicherheits-Review vor der Freigabe** (siehe 5.5).
      Kompletter Durchgang durch alle Stellen, die Empfangenes anfassen:
      kein `eval`/`source`, keine ungeprueften Werte in `$(( ))` oder in
      Array-Indizes, Zeichensatzfilter, Pfadpruefungen, Grenzen. Erneuter
      Fuzz-Lauf gegen den fertigen Stand, dazu ein "boeser Client", der
      absichtlich das Protokoll verletzt.

## 8. Offene Punkte

- Bonus-Reihenwertung ist verifiziert und umgesetzt (siehe 3.2); seit
  dem Punktesystem-Umbau in 0.16.0 ist sie zugleich der Score. Die
  frueher offene Frage nach den Punkten fuer die Quadrat-Bildung hat
  sich damit erledigt (es gibt bewusst keine Bildungs-Punkte mehr).
- Weltwunder-Liste und Baustufen sind seit 0.8.0 festgelegt (siehe
  3.3). Offen bleibt: Die Reihen-Kosten je Wunder (100..6400) sind
  gegenueber dem Original bewusst herunterskaliert und sollten nach
  Playtesting ggf. nachjustiert werden (`WONDER_COSTS`).
- Mindest-Terminalgroesse: seit 0.1.0 als 48x24 implementiert, seit
  0.19.0 auch waehrend des Spiels ueberwacht (SIGWINCH, siehe Phase 4
  "Anpassung an Terminalgroesse"): ein Resize zeichnet sauber neu, ein
  Unterschreiten des Minimums pausiert die Runde hinter einer
  "resize me"-Overlay bis das Terminal wieder gross genug ist. Das feste
  Layout skaliert bewusst nicht mit; groessere Terminals zeigen das
  Spiel weiter oben links (ein zentriertes/mitwachsendes Layout ist der
  separate Phase-4-Punkt "Layout anpassen").
- Punktesystem-Feinschliff (Kombos, Back-to-Back?): Nach dem Umbau in
  0.16.0 (nur abgebaute Reihen zaehlen) waeren solche Extras eine
  bewusste Abweichung vom Konzept "Punkte = Reihenwertung" - nur nach
  expliziter Nutzerentscheidung wieder aufgreifen.
- UI-Sprache: Menues sind Deutsch (ASCII), In-Game-HUD und --help
  Englisch (Konvention). Entscheiden, ob das so bleibt oder das UI
  einheitlich einsprachig werden soll.

Offene Punkte zum Mehrspieler (Spezifikation siehe Abschnitt 5; alles
Uebrige dort ist entschieden):

- **Fremdabhaengigkeit `socat`/`ncat`/`nc -U`:** Bash kann kein AF_UNIX.
  Zu bestaetigen ist, dass ein `Recommends`-Paket akzeptabel ist - sonst
  bleibt nur die FIFO-Variante aus 5.2 mit ihren Nachteilen.
- **Wertung von Mehrspieler-Runden:** Vorschlag in 5.8 ist
  Weltwunder-Fortschritt und Statistik ja, Highscore-Liste nein (dafuer
  eigene Mehrspieler-Zaehler). Bestaetigung ausstehend; die Alternative
  waere ein `mode`-Feld in der Highscore-Zeile mit getrennter Anzeige.
- **Garbage-Werte** (0/1/2/4 Reihen, +2 Silber, +4 Gold, Deckel 10) sind
  aus der Reihenwertung abgeleitet, nicht aus dem Original - "The New
  Tetris" hat keinen vergleichbaren Versus-Modus. Nach Playtesting
  nachjustieren.
- **Zielwahl ab 3 Spielern:** Standard `random`. Ob eine manuelle
  Zielauswahl (Taste) gewuenscht ist, bleibt offen; die Tastenbelegung
  ist voll und die Bedienung skaliert schlecht.
- **Spielerzahl:** Standard 4, technisches Maximum 6 (Begruendung in
  5.1). Ob 6 in der Praxis noch fluessig laeuft, entscheidet der Lasttest
  im Roadmap-Schritt 9 (Phase 5).
- **Kein Reconnect in v1** (5.8). Falls sich Abbrueche im Alltag haeufen,
  waere ein Wiedereinstieg mit vollstaendiger Zustandsuebertragung ein
  eigener spaeterer Punkt.
- **Anti-Cheat:** bewusst nur Hub-Autoritaet ueber Garbage-Mengen und
  Rundenende (5.4). Ein manipulierter Client kann falsche `CLEAR`s
  melden; eine serverseitige Vollsimulation ist kein Ziel. Die
  Sicherheitsregeln in 5.5 schuetzen dagegen die Prozesse und Terminals
  der Mitspieler - dieser Teil ist nicht verhandelbar.
