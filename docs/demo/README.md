# Demo-Clips

Kurze, echte Spielsequenzen aus rowhammer, aufgenommen mit
[asciinema](https://asciinema.org/). Jeder Clip liegt doppelt vor:

- als **`.cast`** (asciinema-v2-Aufnahme, im Terminal abspielbar) und
- als **`.gif`** (fuer die Einbettung im README).

| Clip            | Zeigt                                                     |
|-----------------|----------------------------------------------------------|
| `tetris`        | Vier Reihen auf einmal (Tetris, +1 Bonuszeile)           |
| `silver`        | Ein Silber-Quadrat aus vier gemischten Teilen (I/O/L/J)  |
| `gold`          | Ein Gold-Quadrat aus vier gleichen Teilen (vier O)       |
| `wonder`        | Die Weltwunder-Baustelle (Sphinx, fast fertig)           |

Im Terminal abspielen:

```
asciinema play docs/demo/gold.cast
```

Die Aufnahmen sind mit festem `--seed` entstanden (reproduzierbare
Teilfolge) und laufen im Standard-Layout (58x24, erweiterter Farbmodus).
