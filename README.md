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

**Phase 1 (spielbarer Kern) ist umgesetzt.** Klassisches Tetris laeuft:
Spielfeld, 7-Bag-Randomizer, Gravitation mit Levelkurve, Reihenabbau,
Soft-/Hard-Drop, Pause und Game Over mit Neustart. Das vollstaendige Konzept
und die Roadmap stehen in [CLAUDE.md](CLAUDE.md).

## Spielen

```
./tetris.sh
```

Optionen:

| Option       | Umgebungsvariable    | Wirkung                                  |
|--------------|----------------------|------------------------------------------|
| `--seed N`   | `ROWHAMMER_SEED`     | Reproduzierbare Teilfolge                |
| `--no-color` | `ROWHAMMER_NO_COLOR` | Keine ANSI-Farben, Bloecke als `[]`      |
| `-h/--help`  | -                    | Hilfe mit allen Optionen und Tasten      |

## Features

Umgesetzt (Phase 1):

- Klassisches 10x20-Spielfeld, 7 Tetrominos, 7-Bag-Randomizer
- Soft-/Hard-Drop, Rotation mit einfachen Wall-Kicks, Pause, Neustart
- Farbige Darstellung ueber ANSI-Sequenzen, flackerfreies Rendering
  (Double-Buffering), sauberes Terminal-Restore beim Beenden

Geplant:

- Vorschau auf die naechsten Teile, Hold
- **Quadrat-System:** Gold- und Silber-Quadrate mit Bonus-Reihenwertung
- **Weltwunder-Modus:** persistenter Reihenzaehler baut nacheinander
  Weltwunder in mehreren Baustufen auf (Fortschritt wird gespeichert)
- Spaeter: **Multiplayer** ueber das Netzwerk mit Garbage-Reihen

## Voraussetzungen

- Bash >= 4.0 (empfohlen: Bash 5)
- Ein Terminal mit ANSI-Farbunterstuetzung, mindestens ca. 80x24 Zeichen
- Keine weiteren Abhaengigkeiten ausser Coreutils

## Steuerung

| Taste             | Aktion                      |
|-------------------|-----------------------------|
| `a` / `d`, Pfeile | Links / Rechts              |
| `w` / Pfeil hoch  | Rotation im Uhrzeigersinn   |
| `q`               | Rotation gegen Uhrzeigersinn|
| `s` / Pfeil runter| Soft-Drop                   |
| Leertaste         | Hard-Drop                   |
| `c`               | Hold (ab Phase 2)           |
| `p`               | Pause                       |
| `Esc` / `x`       | Beenden                     |
| `r`               | Neustart (im Game-Over-Bild)|

## Mitmachen / Entwicklung

Konzept, Architektur, Roadmap und die verbindlichen Skript-Konventionen sind
in [CLAUDE.md](CLAUDE.md) dokumentiert. Diese Datei ist der Startpunkt fuer
jede Weiterentwicklung.
