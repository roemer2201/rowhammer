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

**Phase 1 (spielbarer Kern) plus Startmenue sind umgesetzt.** Klassisches
Tetris laeuft: Spielfeld, 7-Bag-Randomizer, Gravitation mit Levelkurve,
Reihenabbau, Soft-/Hard-Drop, Pause und Game Over mit Neustart. Die
Anwendung startet in einem Menue mit Einzelspieler, Mehrspieler
(Platzhalter) und Einstellungen. Das vollstaendige Konzept und die
Roadmap stehen in [CLAUDE.md](CLAUDE.md).

## Spielen

Direkt aus dem Repository:

```
./tetris.sh
```

Oder als Debian-Paket installieren (siehe unten), dann:

```
rowhammer
```

Das Startmenue bietet:

- **Einzelspieler** - vorerst nur "Normales Spiel"
- **Mehrspieler** - Platzhalter, folgt in einer spaeteren Phase
- **Einstellungen** - Tastenbelegung aendern und Spielernamen setzen;
  beides wird in einer Konfigurationsdatei gespeichert (Standard:
  `~/.config/rowhammer.conf`, organisationsbasierte Suche nach den
  Script-Konventionen)

Optionen:

| Option       | Umgebungsvariable        | Wirkung                                  |
|--------------|--------------------------|------------------------------------------|
| `--seed N`   | `ROWHAMMER_SEED`         | Reproduzierbare Teilfolge                |
| `--name NAME`| `ROWHAMMER_PLAYER_NAME`  | Spielername im HUD                       |
| `--no-color` | `ROWHAMMER_NO_COLOR`     | Keine ANSI-Farben, Bloecke als `[]`      |
| `-h/--help`  | -                        | Hilfe mit allen Optionen und Tasten      |

Die Tastenbelegung laesst sich zusaetzlich per Umgebungsvariablen
`ROWHAMMER_KEY_*` uebersteuern (siehe `--help`). Praezedenz:
CLI > Umgebungsvariable > Konfigurationsdatei > Standardwert.

## Features

Umgesetzt:

- Klassisches 10x20-Spielfeld, 7 Tetrominos, 7-Bag-Randomizer
- Soft-/Hard-Drop, Rotation mit einfachen Wall-Kicks, Pause, Neustart
- Farbige Darstellung ueber ANSI-Sequenzen, flackerfreies Rendering
  (Double-Buffering), sauberes Terminal-Restore beim Beenden
- Startmenue mit Einzelspieler, Mehrspieler-Platzhalter und Einstellungen
- Konfigurierbare Tastenbelegung und Spielername, gespeichert in
  `~/.config/rowhammer.conf`

Geplant:

- Vorschau auf die naechsten Teile, Hold
- **Quadrat-System:** Gold- und Silber-Quadrate mit Bonus-Reihenwertung
- **Weltwunder-Modus:** persistenter Reihenzaehler baut nacheinander
  Weltwunder in mehreren Baustufen auf (Fortschritt wird gespeichert)
- Spaeter: **Multiplayer** ueber das Netzwerk mit Garbage-Reihen

## Installation als Debian-Paket

Das Repository enthaelt eine vollstaendige Debian-Paketierung (`debian/`,
`Makefile`). Bauen und installieren:

```
./build-deb.sh
sudo apt install ./dist/rowhammer_*.deb
```

Benoetigt werden `dpkg-dev` und `debhelper`. Das Paket installiert das
Spiel nach `/usr/share/rowhammer/` und legt den Starter
`/usr/games/rowhammer` an. Alternativ geht auch der klassische Weg mit
`dpkg-buildpackage -us -uc -b` oder eine Installation ohne Paket per
`sudo make install` (Standard-Praefix `/usr/local`, entfernen mit
`sudo make uninstall`). Eine RPM-Paketierung ist geplant.

## Voraussetzungen

- Bash >= 4.0 (empfohlen: Bash 5)
- Ein Terminal mit ANSI-Farbunterstuetzung, mindestens ca. 80x24 Zeichen
- Keine weiteren Abhaengigkeiten ausser Coreutils

## Steuerung

Standardbelegung; die Buchstabentasten sind im Einstellungsmenue
aenderbar, die Pfeiltasten bleiben immer aktiv:

| Taste             | Aktion                      |
|-------------------|-----------------------------|
| `a` / `d`, Pfeile | Links / Rechts              |
| `w` / Pfeil hoch  | Rotation im Uhrzeigersinn   |
| `q`               | Rotation gegen Uhrzeigersinn|
| `s` / Pfeil runter| Soft-Drop                   |
| Leertaste         | Hard-Drop                   |
| `c`               | Hold (ab Phase 2)           |
| `p`               | Pause                       |
| `Esc` / `x`       | Zurueck ins Menue           |
| `r`               | Neustart (im Game-Over-Bild)|

In den Menues gelten Pfeiltasten bzw. `w`/`s` zum Waehlen, Enter oder
Leertaste zum Bestaetigen und `Esc` fuer Zurueck.

## Mitmachen / Entwicklung

Konzept, Architektur, Roadmap und die verbindlichen Skript-Konventionen sind
in [CLAUDE.md](CLAUDE.md) dokumentiert. Diese Datei ist der Startpunkt fuer
jede Weiterentwicklung.
