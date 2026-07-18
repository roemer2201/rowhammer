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
  - Rotation: `w` bzw. Pfeil hoch (im Uhrzeigersinn), `q` (gegen Uhrzeigersinn)
  - Soft-Drop: `s` bzw. Pfeil runter
  - Hard-Drop: Leertaste
  - Hold: `c`
  - Pause: `p`, Beenden: `Esc`/`x`
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
- **Reihenwertung beim Abbau** (Startwerte, spielbar abstimmbar):
  - normale Reihe: **1** Reihe Baufortschritt
  - Reihe durch ein Silber-Quadrat: **5** Reihen
  - Reihe durch ein Gold-Quadrat: **10** Reihen
  - TODO: Werte gegen das Original verifizieren und per Playtesting justieren.
- Umgesetzt seit 0.3.0 (`lib/squares.sh`): Werte liegen justierbar in
  `ROWS_NORMAL`/`ROWS_SILVER`/`ROWS_GOLD`; verlaeuft eine Reihe durch
  mehrere Quadrat-Typen, gilt Gold vor Silber. Ein angeschnittenes
  Quadrat behaelt seine Gold-/Silber-Zellen und liefert weiter Bonus.

### 3.3 Weltwunder-Aufbau

- Es gibt eine feste Abfolge von Weltwundern. Vorschlag fuer die erste Version
  (Liste gegen das Original pruefen, ggf. anpassen):
  1. Stonehenge
  2. Pyramiden von Gizeh
  3. Haengende Gaerten von Babylon
  4. Kolosseum
  5. Chinesische Mauer
  6. Maya-Pyramide (Chichen Itza)
  7. Taj Mahal
- Jedes Wunder ist als **ASCII-Art** in mehreren Baustufen hinterlegt
  (z. B. 10 Stufen). Der persistente Gesamt-Reihenzaehler bestimmt Wunder und
  Baustufe; nach Fertigstellung folgt das naechste Wunder.
- Der Baufortschritt wird **ueber Sitzungen hinweg gespeichert** (Savegame,
  siehe 4.5) und nach jeder Runde sowie auf einem Fortschrittsbildschirm
  angezeigt.

### 3.4 Anzeige / HUD

- Hauptbereich: Spielfeld mit Rahmen.
- Seitenleiste: Naechste Teile, Hold, Reihen (Runde), Reihen (gesamt),
  aktuelles Wunder + Baufortschritt (Miniatur oder Prozent), Level, Punkte.
- Nach Rundenende: Bildschirm mit dem aktuellen Wunder in seiner neuen Baustufe.

## 4. Technisches Konzept

### 4.1 Rahmenbedingungen

- **Bash >= 4.0** (assoziative Arrays), Ziel: uebliche Linux-Distributionen.
- Keine harten Abhaengigkeiten ausser Coreutils; `tput` optional (Fallback auf
  feste ANSI-Sequenzen).
- Farben ueber ANSI-Escape-Sequenzen (8/16 Farben als Basis, 256-Farben als
  Verbesserung wenn verfuegbar).

### 4.2 Architektur und Dateistruktur

Ein Hauptskript, Logik in sourcebaren Modulen:

```
rowhammer/
  tetris.sh            # Hauptskript: Argumente, Init, Game-Loop
  lib/
    board.sh           # Spielfeld-Zustand, Kollision, Reihenabbau
    pieces.sh          # Tetromino-Definitionen und Rotationstabellen
    squares.sh         # Erkennung und Verwaltung von Gold-/Silber-Quadraten
    render.sh          # Rendering (Double-Buffering, ANSI)
    input.sh           # Nicht-blockierende Tastatureingabe
    menu.sh            # Startmenue (Einzel-/Mehrspieler, Einstellungen)
    config.sh          # Laden/Speichern der Nutzer-Konfiguration
    wonders.sh         # Weltwunder-Logik, Baustufen, Fortschritt
    save.sh            # Laden/Speichern des Spielstands
  assets/
    wonders/           # ASCII-Art je Wunder und Baustufe
  CLAUDE.md
  README.md
```

Stand (Version 0.3.0): `tetris.sh` sowie `lib/pieces.sh`, `lib/board.sh`,
`lib/squares.sh`, `lib/input.sh`, `lib/render.sh`, `lib/menu.sh` und
`lib/config.sh` existieren. `wonders.sh`, `save.sh` und `assets/` folgen
in Phase 3. Die Anwendung startet in einem Menue (Einzelspieler /
Mehrspieler-Platzhalter / Einstellungen / Beenden); die Menue-Beschriftung
ist bewusst Deutsch (ASCII), Code und Code-Ausgaben bleiben Englisch.
Das Spielfeld haelt je Zelle drei parallele Arrays (Sorte `BOARD`,
Instanz-ID `BOARD_ID`, Quadrat-Status `BOARD_SQ`); der HUD-Zaehler
"Rows" ist die gewichtete Reihenwertung (1/5/10), die in Phase 3 den
Weltwunder-Fortschritt speist, "Lines" zaehlt physische Reihen und
treibt das Level. CLI-Optionen bisher: `--seed N` (`ROWHAMMER_SEED`)
fuer reproduzierbare Teilfolgen, `--name NAME` (`ROWHAMMER_PLAYER_NAME`),
`--no-color` (`ROWHAMMER_NO_COLOR`), `-h/--help`. Tastenbelegung
zusaetzlich per `ROWHAMMER_KEY_*`-Umgebungsvariablen uebersteuerbar.

### 4.3 Game-Loop, Input, Rendering

- **Game-Loop:** feste Tick-Rate; Fall-Intervall abhaengig vom Level.
  Zeitmessung ueber `${EPOCHREALTIME}` (Bash 5) mit Fallback.
- **Input:** nicht-blockierend ueber `read -rsn1 -t <timeout>`;
  Escape-Sequenzen der Pfeiltasten sauber einlesen. Terminal-Modus mit `stty`
  setzen und ueber einen `trap`-Handler (EXIT/INT/TERM) garantiert
  wiederherstellen.
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

- Spielstand (Gesamt-Reihen, aktuelles Wunder, Baustufe, Highscores) unter
  `${XDG_DATA_HOME:-${HOME}/.local/share}/rowhammer/save`.
- Einfaches KEY=VALUE-Format, atomar schreiben (Tempdatei + `mv`).
- Konfiguration (Tastenbelegung, Farben) folgt den organisationsbasierten
  Konfigurationsregeln der Script-Konventionen (siehe Abschnitt 6).
- Umgesetzt seit 0.2.0: `lib/config.sh` laedt `rowhammer.conf` in der
  organisationsbasierten Suchreihenfolge (System `/etc`, dann Nutzer
  `${HOME}/.config`); das Einstellungsmenue (Spielername, Tastenbelegung)
  schreibt atomar in die Nutzer-Datei, Standardziel
  `${HOME}/.config/rowhammer.conf`. Werte werden validiert und
  single-quoted geschrieben, da die Datei gesourct wird.

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

## 7. Roadmap / Todo-Liste

### Phase 1 - Spielbarer Kern (umgesetzt, Version 0.1.0)

- [x] Projektgeruest anlegen (`tetris.sh`, `lib/`-Module, Header nach Konvention)
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

### Phase 2 - The-New-Tetris-Mechaniken (umgesetzt, Version 0.3.0)

- [x] Stein-Instanz-Tracking (IDs, "zerschnitten"-Markierung)
- [x] 4x4-Quadrat-Erkennung nach jedem Lock
- [x] Gold-/Silber-Darstellung und Bonus-Reihenwertung (1/5/10, justierbar
      in `lib/squares.sh`)
- [x] Vorschau (3 Teile) und Hold-Funktion (Taste `c`, konfigurierbar)
- [x] Level-/Geschwindigkeitskurve (Tabelle `LEVEL_SPEEDS`), Punktesystem
      (Reihen skalieren mit Level, Quadrat-Bonus 2000/1000)
- [ ] Bonus-Werte gegen das Original verifizieren, Playtesting

### Phase 3 - Weltwunder

- [ ] Wunder-Liste final festlegen (Abgleich mit dem Original)
- [ ] ASCII-Art je Wunder in Baustufen erstellen (`assets/wonders/`)
- [ ] Persistenter Gesamt-Reihenzaehler und Savegame (`save.sh`, atomar)
- [ ] Fortschrittsanzeige im HUD und Wunder-Bildschirm nach Rundenende
- [ ] Freischalt-Logik: naechstes Wunder nach Fertigstellung

### Phase 4 - Politur

- [ ] Konfigurierbare Farben (Config-Datei nach Konvention;
      Tastenbelegung ist seit 0.2.0 umgesetzt)
- [ ] Highscore-Liste
- [ ] 256-Farben-Modus, Anpassung an Terminalgroesse
- [ ] Performance-Optimierung des Renderings (nur geaenderte Zellen zeichnen)
- [ ] README mit Screenshots/Asciinema aktualisieren

### Phase 5 - Multiplayer (spaeter)

- [ ] Spiellogik vollstaendig von Rendering/Input entkoppeln
- [ ] Netzwerk-Transport waehlen und Protokoll spezifizieren
- [ ] Host-/Join-Modus, Seed-Austausch, Garbage-Regeln
- [ ] Gegner-Feldanzeige, Verbindungsabbruch-Handling

## 8. Offene Punkte

- Exakte Bonus-Werte fuer Gold/Silber-Reihen im Original recherchieren.
- Endgueltige Weltwunder-Liste und Anzahl der Baustufen je Wunder.
- Mindest-Terminalgroesse festlegen (Vorschlag: 80x24) und Verhalten bei
  kleineren Terminals.
- Punktesystem im Detail (Kombos, Back-to-Back?) - erst nach Phase 1 relevant.
