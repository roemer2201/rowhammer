# Demo-Clip-Toolchain

Diese Werkzeuge erzeugen die Vorschau-Clips im Haupt-README
(`docs/demo/*.gif` und `*.cast`). Sie spielen dazu **das echte
`rowhammer.sh`** in einem Pseudo-Terminal und zeichnen es auf - es werden
keine Frames "gefaelscht". Jede gespielte Sequenz wird gegen das
spieleigene Debug-Log (`events.log`) geprueft, damit die Aufnahme nie von
dem abweicht, was das Spiel wirklich getan hat.

## Warum ueberhaupt Werkzeuge?

Das Spiel hat keine "Board-laden"-Funktion, und einige Situationen sind
von Hand kaum reproduzierbar (ein Gold-Quadrat braucht z. B. vier
O-Steine aus vier verschiedenen Beuteln). Deshalb:

1. **`sim.py`** bildet die Spielregeln exakt nach (Formen, Kollision,
   Hard-Drop, Quadrat-Erkennung, Reihenabbau - 1:1 zu `lib/board.sh`,
   `lib/squares.sh`, `rowhammer.sh`).
2. **`planner.py`** plant damit die Zugfolgen fuer die vier Szenen und
   verifiziert sie im Simulator.
3. **`driver.py`** fuettert die echten Tastendruecke ins echte Spiel und
   nimmt es als asciinema-`.cast` auf.
4. **`record.py`** prueft die Aufnahme gegen `events.log`
   (`gold square formed`, `cleared 4 row(s): credit=+5`, ...).
5. **`render.py`** rendert die `.cast` zu einem GIF (pyte + Pillow).
6. **`trim.py`** schneidet die `.cast` fuer die Auslieferung sauber zu.

Der feste `--seed` je Szene macht die Teilfolge reproduzierbar (die Seeds
wurden mit `solve_order.py` bzw. kurzen Scans gewaehlt, siehe die
Kommentare in `planner.py`).

## Alles neu erzeugen

```
pip install -r tools/demo/requirements.txt
python3 tools/demo/make_demos.py            # tetris, silver, gold, wonder
python3 tools/demo/make_demos.py gold       # nur eine Szene
```

Ergebnis landet in `docs/demo/` (`<name>.gif` + `<name>.cast`).
Zwischendateien liegen in `tools/demo/.build/` (per `.gitignore`
ausgeschlossen).

## Dateien

| Datei              | Aufgabe                                                     |
|--------------------|-------------------------------------------------------------|
| `probe_pieces.sh`  | Exakte 7-Bag-Teilfolge eines Seeds (sourct `lib/pieces.sh`) |
| `sim.py`           | Regel-Nachbau + Tastenfolgen-Helfer                          |
| `plan.py`          | Greedy-Packer (Tetris-Wand, Gold-Deponie)                    |
| `planner.py`       | Die vier Szenen-Planer (silver/tetris/gold)                  |
| `solve_order.py`   | Seed-Auswahl-Helfer (4x4-Kachelung fuer Silber)              |
| `driver.py`        | Pty-Aufnahme -> `.cast`                                       |
| `record.py`        | Aufnahme + Verifikation gegen `events.log`                   |
| `render.py`        | `.cast` -> animiertes GIF                                     |
| `trim.py`          | `.cast` fuer die Auslieferung zuschneiden                     |
| `make_demos.py`    | Orchestriert alles (Szenen-Konfiguration)                    |
| `paths.py`         | Repo-relative Pfade                                          |

## Szenen (in `make_demos.py`)

- **tetris** (Seed 13): neun Spalten fuellen, Luecke rechts, stehender
  I-Stein raeumt vier Reihen.
- **silver** (Seed 121): erste vier Teile I,O,L,J kacheln direkt ein
  4x4-Feld (gemischt -> Silber).
- **gold** (Seed 16): vier O-Steine in Spalte 0-3; alles andere wird in
  Spalte 4-8 abgeladen, Spalte 9 bleibt leer (keine vorzeitige
  Reihenraeumung, die die O-Instanzen "zerschneiden" wuerde).
- **wonder** (Seed 7): Weltwunder-Bildschirm aus einem vorbelegten
  Spielstand (`total_rows=690` -> Sphinx zu ~97 % gebaut).
