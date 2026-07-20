# rowhammer

Ein Tetris-artiges Spiel fuer das Terminal - komplett in **Bash**.

Vorbild ist **"The New Tetris"** (Nintendo 64): Mit jeder abgebauten Reihe
arbeitest du am Aufbau eines **Weltwunders**, das ueber alle Runden hinweg
Stueck fuer Stueck aus ASCII-Art entsteht. Auch das Quadrat-System des
Originals ist Teil des Konzepts: Wer aus vier Tetrominos ein 4x4-Quadrat baut,
erhaelt **Gold-** (sortenrein) oder **Silber-Bloecke** (gemischt), die beim
Abbau kraeftige Bonus-Reihen liefern.

Der Name ist ein Wortspiel: Hier werden Reihen (rows) gehaemmert - mit dem
gleichnamigen Hardware-Angriff hat das Spiel nichts zu tun.

## Status

**Phasen 1 bis 3 sind umgesetzt** (spielbarer Kern, Startmenue, die
The-New-Tetris-Mechaniken und der Weltwunder-Modus): Spielfeld,
7-Bag-Randomizer mit Vorschau auf
3 Teile, Hold, Gravitation mit Levelkurve, Reihenabbau, Soft-/Hard-Drop,
Pause, Game Over mit Neustart - und das **Quadrat-System**: Wer ein
4x4-Feld aus genau vier unversehrten Tetrominos baut, erhaelt ein Gold-
(sortenrein) oder Silber-Quadrat (gemischt); jede abgebaute Reihe bringt
+10 Bonuszeilen je Gold- und +5 je Silber-Quadrat (ein Tetris +1 extra)
fuer den "Rows"-Zaehler. Dieser Zaehler baut ueber alle Runden hinweg
sieben **Weltwunder** aus ASCII-Art auf, die Stueck fuer Stueck von
unten nach oben entstehen; der Fortschritt wird dauerhaft gespeichert
und im HUD, nach jeder Runde und im Hauptmenue angezeigt. Die
Anwendung startet in einem Menue mit Einzelspieler,
Mehrspieler (Platzhalter), Highscores, Weltwunder, Statistik und
Einstellungen;
die besten
10 Runden werden dauerhaft gespeichert. Das vollstaendige Konzept
und die Roadmap stehen in [CLAUDE.md](CLAUDE.md).

## Spielen

```
./rowhammer.sh
```

Das Startmenue bietet:

- **Fortsetzen** - erscheint nur, solange eine ueber das Pausenmenue
  ins Hauptmenue gelegte Runde wartet, und nimmt sie wieder auf; der
  Eintrag steht dann auch im Einzelspieler-Menue an erster Stelle
- **Einzelspieler** - vorerst nur "Normales Spiel"
- **Mehrspieler** - Platzhalter, folgt in einer spaeteren Phase
- **Highscores** - die besten 10 Runden mit Name, Score, Rows und
  Level; ein Game Over zeigt den erreichten Rang direkt an
- **Weltwunder** - die aktuelle Baustelle mit Baustufe, Reihenstand
  und Gesamtfortschritt
- **Statistik** - Gesamtzaehler ueber alle Runden: abgebaute Reihen,
  Bonusreihen sowie gebaute Gold- und Silberbloecke; dazu die
  Ergebnisse der letzten drei Spiele
- **Einstellungen** - Tastenbelegung aendern und Spielernamen setzen;
  beides wird in der Konfigurationsdatei gespeichert (Standard:
  `~/.config/rowhammer/rowhammer.conf`)

Alle Spieldaten (Konfiguration, Highscores, Weltwunder-Spielstand,
Statistik) liegen im Datenverzeichnis
`~/.config/rowhammer`, aenderbar per `--data-dir`.

Optionen:

| Option           | Umgebungsvariable        | Wirkung                                  |
|------------------|--------------------------|------------------------------------------|
| `--seed N`       | `ROWHAMMER_SEED`         | Reproduzierbare Teilfolge                |
| `--name NAME`    | `ROWHAMMER_PLAYER_NAME`  | Spielername im HUD                       |
| `--data-dir DIR` | `ROWHAMMER_DATA_DIR`     | Datenverzeichnis (Config, Scores, Save)  |
| `--no-color`     | `ROWHAMMER_NO_COLOR`     | Keine ANSI-Farben, Bloecke als `[]`      |
| `--color-mode M` | `ROWHAMMER_COLOR_MODE`   | Farbpalette: `auto` (Standard), `basic`, `extended` |
| `--debug`        | `ROWHAMMER_DEBUG`        | Session-Trace in Log-Dateien (s. unten)  |
| `--debug-dir DIR`| `ROWHAMMER_DEBUG_DIR`    | Zielverzeichnis fuer die Debug-Logs      |
| `-h/--help`      | -                        | Hilfe mit allen Optionen und Tasten      |

Der Debug-Modus zeichnet die komplette Session in drei korrelierte
Log-Dateien auf (Standardziel:
`~/.local/state/rowhammer/debug/<Zeitstempel>.<PID>`): `frames.log`
(jede Bildschirmausgabe 1:1), `input.log` (jeder Tastendruck) und
`events.log` (alle Spielaktionen samt Board-Snapshots). Das hilft,
Fehlverhalten oder Spielsituationen im Nachhinein exakt
nachzuvollziehen - z. B. fuer einen Bug-Report.

Die Tastenbelegung laesst sich zusaetzlich per Umgebungsvariablen
`ROWHAMMER_KEY_*` uebersteuern (siehe `--help`). Praezedenz:
CLI > Umgebungsvariable > Konfigurationsdatei > Standardwert.

## Features

Umgesetzt:

- Klassisches 10x20-Spielfeld, 7 Tetrominos, 7-Bag-Randomizer
- Vorschau auf die naechsten 3 Teile und Hold (einmal pro Zug)
- **Quadrat-System:** Gold- (sortenrein) und Silber-Quadrate (gemischt)
  aus je vier unversehrten Teilen; jede geraeumte Reihe zaehlt 1 plus
  +10 je Gold- und +5 je Silber-Quadrat in der Reihe (additiv), ein
  Tetris bringt +1 extra ("Rows" im HUD) - bis zu 85 in einem Zug
- Soft-/Hard-Drop, Rotation mit einfachen Wall-Kicks, Pause, Neustart
- **Pausenmenue statt hartem Abbruch:** `Esc`/`x` unterbricht die
  Runde; sie kann ins Hauptmenue gelegt und dort ueber "Fortsetzen"
  wieder aufgenommen werden - gewertet wird erst beim echten Rundenende
- Levelkurve (schneller je 10 Reihen) und Punktesystem
- Farbige Darstellung ueber ANSI-Sequenzen, flackerfreies Rendering
  (Double-Buffering), sauberes Terminal-Restore beim Beenden
- **Erweiterter Farbmodus:** auf 256-Farben-Terminals (automatisch
  erkannt, umschaltbar per `--color-mode`) eine satte xterm-Palette mit
  den Guideline-Teilfarben - inklusive echtem Orange fuer das L-Teil
  und kraeftigerem Gold/Silber fuer die Quadrate
- Startmenue mit Einzelspieler, Mehrspieler-Platzhalter, Highscores,
  Weltwunder, Statistik und Einstellungen
- Persistente Highscore-Liste: die besten 10 Runden in
  `~/.config/rowhammer/highscore`, Ranganzeige im Game-Over-Bild
- **Statistik:** persistente Gesamtzaehler in `~/.config/rowhammer/stats` -
  abgebaute Reihen, Bonusreihen (der Gold-/Silber-/Tetris-Anteil der
  Reihenwertung) und gebaute Gold-/Silberbloecke sowie die Ergebnisse
  der letzten drei Spiele, einsehbar im
  Hauptmenue
- **Weltwunder-Modus:** der "Rows"-Zaehler baut ueber alle Runden
  hinweg sieben Weltwunder (Maya-Tempel, Stonehenge, Sphinx, Pantheon,
  Chinesische Mauer, Taj Mahal, Basilius-Kathedrale) als ASCII-Art
  Baustufe fuer Baustufe von unten auf; Fortschritt persistent in
  `~/.config/rowhammer/save`, Anzeige im HUD, nach jeder Runde und im Menue
- Konfigurierbare Tastenbelegung und Spielername, gespeichert in
  `~/.config/rowhammer/rowhammer.conf`

Geplant:

- Spaeter: **Multiplayer** ueber das Netzwerk mit Garbage-Reihen

## Voraussetzungen

- Bash >= 4.0 (empfohlen: Bash 5)
- Ein Terminal mit ANSI-Farbunterstuetzung, mindestens ca. 80x24 Zeichen
- Keine weiteren Abhaengigkeiten ausser Coreutils

## Steuerung

Standardbelegung; die Buchstabentasten (`w`, `e`, `c` usw.) sind im
Einstellungsmenue aenderbar, waehrend die Pfeiltasten sowie Leertaste
(Hard-Drop) und `2` (Hold) als feste Sekundaerbelegung immer aktiv
bleiben:

| Taste                     | Aktion                      |
|---------------------------|-----------------------------|
| `a` / `d`, Pfeile         | Links / Rechts              |
| `e`                       | Rotation im Uhrzeigersinn   |
| `q`                       | Rotation gegen Uhrzeigersinn|
| `s` / Pfeil runter        | Soft-Drop                   |
| `w`, Pfeil hoch, Leertaste| Hard-Drop                   |
| `c` / `2`                 | Hold / Tauschen             |
| `p`                       | Pause                       |
| `Esc` / `x`               | Pausenmenue (Fortsetzen / Ins Hauptmenue / Runde beenden) |
| `r`                       | Neustart (im Game-Over-Bild)|

In den Menues gelten Pfeiltasten bzw. `w`/`s` zum Waehlen, Enter oder
Leertaste zum Bestaetigen und `Esc` fuer Zurueck.

## Mitmachen / Entwicklung

Konzept, Architektur, Roadmap und die verbindlichen Skript-Konventionen sind
in [CLAUDE.md](CLAUDE.md) dokumentiert. Diese Datei ist der Startpunkt fuer
jede Weiterentwicklung.
