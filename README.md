# rowhammer

**Version:** 1.3.0

Ein Tetris-artiges Spiel fuer das Terminal - komplett in **Bash**.

Vorbild ist **"The New Tetris"** (Nintendo 64): Mit jeder abgebauten Reihe
arbeitest du am Aufbau eines **Weltwunders**, das ueber alle Runden hinweg
Stueck fuer Stueck aus ASCII-Art entsteht. Auch das Quadrat-System des
Originals ist Teil des Konzepts: Wer aus vier Bausteinen ein 4x4-Quadrat baut,
erhaelt **Gold-** (sortenrein) oder **Silber-Bloecke** (gemischt), die beim
Abbau kraeftige Bonus-Reihen liefern.

Der Name ist ein Wortspiel: Hier werden Reihen (rows) gehaemmert - mit dem
gleichnamigen Hardware-Angriff hat das Spiel nichts zu tun.

## Vorschau

Kurze, echte Spielsequenzen - aufgenommen mit
[asciinema](https://asciinema.org/) und als GIF eingebettet. Die
zugehoerigen `.cast`-Dateien liegen unter [`docs/demo/`](docs/demo) und
lassen sich im Terminal abspielen, z. B.
`asciinema play docs/demo/gold.cast`.

<table>
  <tr>
    <td align="center" width="50%">
      <b>Tetris - vier Reihen auf einmal</b><br>
      <img src="docs/demo/tetris.gif" alt="Tetris: vier Reihen auf einmal werden abgebaut" width="420"><br>
      <sub>Neun Spalten fuellen, die Luecke rechts lassen - der stehende I-Stein raeumt vier Reihen (+1 Bonuszeile).</sub>
    </td>
    <td align="center" width="50%">
      <b>Silber-Quadrat</b><br>
      <img src="docs/demo/silver.gif" alt="Ein Silber-Quadrat entsteht aus vier gemischten Teilen" width="420"><br>
      <sub>Vier <em>gemischte</em> Teile fuellen ein 4x4-Feld - es wird zum Silber-Quadrat (+5 je Reihe beim Abbau).</sub>
    </td>
  </tr>
  <tr>
    <td align="center" width="50%">
      <b>Gold-Quadrat</b><br>
      <img src="docs/demo/gold.gif" alt="Ein Gold-Quadrat entsteht aus vier gleichen Teilen" width="420"><br>
      <sub>Vier <em>gleiche</em> Teile (hier vier O) im 4x4-Feld - das Gold-Quadrat bringt +10 je Reihe.</sub>
    </td>
    <td align="center" width="50%">
      <b>Weltwunder-Baustelle</b><br>
      <img src="docs/demo/wonder.gif" alt="Die Weltwunder-Baustelle mit der fast fertigen Sphinx" width="420"><br>
      <sub>Der ueber alle Runden gesammelte Reihenstand baut Stueck fuer Stueck ein Weltwunder auf.</sub>
    </td>
  </tr>
</table>

## Installation

Der schnellste Weg: unter
[Releases](https://github.com/roemer2201/rowhammer/releases) haengt an
jeder Version ein fertiges Paket.

```
sudo apt install ./rowhammer_<version>_all.deb      # Debian, Ubuntu
sudo dnf install ./rowhammer-<version>-*.noarch.rpm # Fedora, RHEL, openSUSE
```

Dort liegen ausserdem das RPM-Quellpaket, ein Quell-Tarball und
`SHA256SUMS` mit den Pruefsummen aller Dateien. Beide Pakete installieren
das Spiel nach `/usr/share/rowhammer/` und legen den Starter
`/usr/games/rowhammer` an.

**Ohne Installation** laeuft es direkt aus dem Repository:

```
./rowhammer.sh
```

**Selbst bauen:**

```
./build-deb.sh && sudo apt install ./dist/rowhammer_*.deb   # braucht dpkg-dev, debhelper, build-essential
./build-rpm.sh && sudo dnf install ./dist/rowhammer-*.rpm   # braucht rpm-build, make, tar
```

Beide Skripte legen ihre Ergebnisse in `dist/` ab und kennen `--help`.
Alternativ geht auch eine Installation ohne Paket per `sudo make install`
(Standard-Praefix `/usr/local`, entfernen mit `sudo make uninstall`).

## Voraussetzungen

- **Bash >= 4.3** (empfohlen: Bash 5)
- Ein Terminal mit ANSI-Farbunterstuetzung, **mindestens 48x22 Zeichen**.
  Kleiner startet das Spiel nicht; wird das Fenster waehrend einer Runde
  zu klein, pausiert sie hinter einem Hinweis, bis wieder Platz da ist
- Keine weiteren Abhaengigkeiten ausser Coreutils
- Fuer den **Mehrspieler** zusaetzlich `socat` (Debian/Ubuntu:
  `apt install socat`, Fedora/RHEL: `dnf install socat`). Es ist in
  beiden Paketen nur *empfohlen*: ohne socat laeuft das
  Einzelspieler-Spiel unveraendert, und der Menuepunkt sagt, welches
  Paket fehlt

## Spielen

```
rowhammer          # installiert
./rowhammer.sh     # aus dem Repository
```

Das Startmenue:

- **Fortsetzen** - erscheint nur, solange eine ueber das Pausenmenue
  ins Hauptmenue gelegte Runde wartet, und nimmt sie wieder auf; der
  Eintrag steht dann auch im Einzelspieler-Menue an erster Stelle
- **Einzelspieler** - waehlt den Spielmodus (siehe unten)
- **Mehrspieler** - eine Runde im lokalen Netz gegen zwei bis fuenf
  Leute (siehe [unten](#mehrspieler-im-lokalen-netz))
- **Highscores** - die Bestenlisten, eine je Modus
- **Weltwunder** - die aktuelle Baustelle
- **Statistik** - Zaehler ueber alle Runden oder je Modus
- **Demos** - die aufgezeichneten Runden noch einmal ansehen
- **Einstellungen** - Sprache, Farbschema, Tastenbelegung, Spielername,
  Demo-Aufzeichnung
- **Anleitung** - zehn Bildschirme Spielerklaerung, mit den Pfeiltasten
  links/rechts durchblaetterbar

### Spielmodi

| Modus | Ziel | Ende | Ergebnis |
|---|---|---|---|
| **Marathon** | endlos spielen | Game Over | Rows |
| **Ultra** | 150 Rows so schnell wie moeglich | Ziel erreicht | Spielzeit |
| **Sprint** | in 3 Minuten moeglichst viele Rows | Zeit abgelaufen | Rows |
| **Time Attack** | 1 Minute Restzeit, je Row +1 Sekunde | Uhr auf 00:00 oder Game Over | Rows |
| **Hochwasser** | Marathon, aber alle 20 Sekunden schiebt sich von unten eine Reihe mit einem Loch ins Feld | Game Over | Rows |

Gewertet werden ueberall die **Rows** - die gewichtete Reihenwertung, nicht
die physischen Reihen. Gold- und Silberquadrate sind damit in jedem Modus
die Abkuerzung, bei Time Attack zugleich die Waehrung, mit der Spielzeit
gekauft wird.

In den vier Modi neben Marathon zeigt der Spielbildschirm zwei
zusaetzliche Zeilen: bei Ultra das Ziel und die noch fehlenden Rows, bei
Sprint das Zeitlimit und die Restzeit, bei Time Attack die bisher
erspielte Gesamtzeit und den Rest davon, bei Hochwasser den Flut-Abstand
und die Zeit bis zur naechsten Reihe.

### Punkte und Weltwunder

Nur abgebaute Reihen bringen Punkte - Drops und das Bauen eines Quadrats
nicht. Jede geraeumte Reihe zaehlt **1**, plus **+10** je Gold- und
**+5** je Silber-Quadrat, das durch sie hindurchlaeuft (additiv); ein
Tetris bringt **+1** extra. Das Maximum in einem Zug sind **85** Rows -
vier Reihen durch zwei komplette Gold-Quadrate.

Dieselben Rows bauen ueber alle Runden hinweg an sieben **Weltwundern**
(Maya-Tempel, Stonehenge, Sphinx, Pantheon, Chinesische Mauer, Taj Mahal,
Basilius-Kathedrale). Jedes entsteht als ASCII-Art Baustufe fuer Baustufe
von unten; der Fortschritt wird dauerhaft gespeichert und nach jeder
Runde sowie im Hauptmenue angezeigt. Dort blaettern die Pfeiltasten
links/rechts zu den bereits fertigen Wundern zurueck.

### Bestenlisten

Jeder Modus hat seine eigene Liste mit den besten 10 Runden - die
Ultra-Liste sortiert nach der kuerzesten Zeit (auf die Millisekunde
genau), alle anderen nach den meisten Rows. Ein Eintrag ist zwei Zeilen
hoch: Name, Rows, Spielzeit und Datum in der ersten, Gold- und
Silberquadrate, Rowhammer ("RH"), abgelegte Teile ("PCS") und Teile je
Minute ("PPM") in der zweiten.

Bei **Ultra und Sprint** wird nur ein Lauf eingetragen, der sein Ziel
bzw. die volle Zeit erreicht hat; bei **Marathon, Time Attack,
Hochwasser und Mehrspieler** zaehlt jede Runde. Die Reihen eines nicht
eingetragenen Laufs zaehlen trotzdem fuer Weltwunder und Statistik.

**Wer in der Liste steht, fragt das Spiel am Ende jeder Runde**, die
wirklich einen Platz bekommt: Der Spielername aus den Einstellungen steht
vormarkiert da - Enter uebernimmt ihn, das erste getippte Zeichen ersetzt
ihn, eine Pfeiltaste hebt die Markierung auf, wenn der Name nur ergaenzt
werden soll. Der eingegebene Name gilt nur fuer diese Runde. Ueber der
Eingabezeile steht auch der Platz, den sie einnehmen wird; verfehlt sie
die Top 10, wird gar nicht erst gefragt.

### Demos

Jede Runde wird mitgeschnitten und laesst sich unter **Demos** noch
einmal ansehen - aufgezeichnet werden die Zuege, nicht der Bildschirm,
die Wiedergabe spielt die Runde also wirklich noch einmal durch. Sie
laesst sich anhalten (`p` oder Leertaste) und zwischen 0.25x und 4x Tempo
abspielen (Pfeiltasten); gewertet wird sie nie.

Aufbewahrt werden die 10 neuesten Runden. Aufnahmen, die noch einen
Highscore-Eintrag halten, sind mit `*` markiert und bleiben darueber
hinaus erhalten. Umgekehrt startet **Enter** in einer Bestenliste die
Aufnahme des dort ausgewaehlten Eintrags.

Eine **Mehrspieler-Runde** wird ebenfalls aufgezeichnet, mit den Zuegen
aller Teilnehmer. Beim Abspielen laeuft jedes Feld seine Runde noch
einmal ab; der Fokus laesst sich noch nicht umschalten - das ist der
naechste Schritt.

### Statistik

Persistente Zaehler ueber alle Runden: abgebaute Reihen, Bonusreihen (der
Gold-/Silber-/Tetris-Anteil), gebaute Gold- und Silberbloecke, die Zahl
der "Rowhammer" (vier Reihen auf einmal - der Namensgeber des Spiels),
abgelegte Teile, Spielzeit und die daraus berechneten Steine je Minute.
Dazu das **Verhaeltnis von abgebauten Reihen zu Bonusreihen** ("1:2.34"
heisst: eine abgebaute Reihe war 2.34 Bonusreihen wert), also wie viel
der Wertung aus den Quadraten kam.

Der Menuepunkt fragt zuerst nach der Sicht: **Gesamt** zeigt die Zaehler
ueber alle Runden, die Ergebnisse der letzten drei Spiele und die
gespielten Runden je Modus; **jeder einzelne Modus** zeigt dieselben
Zahlen nur fuer sich, dazu die Rows je Runde und - bei den Zeitmodi - die
Erfolgsquote.

## Steuerung

Standardbelegung. Die Buchstabentasten sind im Einstellungsmenue
aenderbar, die Pfeiltasten sowie Leertaste (Hard-Drop) und `w` (Hold)
bleiben als feste Sekundaerbelegung immer aktiv. Gedreht wird also mit
der linken Hand (`a`/`d`), bewegt mit den Pfeiltasten.

| Taste | Aktion |
|---|---|
| Pfeil links / rechts | Links / Rechts |
| `d` | Rotation im Uhrzeigersinn |
| `a` | Rotation gegen Uhrzeigersinn |
| `s` / Pfeil runter | Soft-Drop |
| Leertaste, Pfeil hoch | Hard-Drop |
| `c` / `w` | Hold / Tauschen |
| `p` | Pause |
| `Esc` / `x` | Pausenmenue (Fortsetzen / Neustarten / Ins Hauptmenue / Runde beenden) |
| `r` | Neustart (im Game-Over-Bild) |

Links, Rechts und Hard-Drop haben in der Standardbelegung bewusst keine
Buchstabentaste (`a`, `d` und `w` werden fuer Drehen und Hold gebraucht);
im Einstellungsmenue laesst sich jederzeit wieder eine vergeben. Die
Belegung ist zusaetzlich per `ROWHAMMER_KEY_*` uebersteuerbar (siehe
`--help`); erlaubt sind `a`-`z`, `0`-`9`, `SPACE` und `NONE`.

**Waehrend der Wiedergabe einer Demo:**

| Taste | Aktion |
|---|---|
| `p` / Leertaste | Anhalten / weiter |
| Pfeil links / rechts | Tempo (0.25x bis 4x) |
| `x` / `Esc` | Zurueck zur Liste |
| `r` | Noch einmal (am Ende) |

**In einer Bestenliste:**

| Taste | Aktion |
|---|---|
| Pfeil hoch / runter | Eintrag waehlen |
| Pfeil links / rechts | Seite vor / zurueck |
| Enter | Demo des Eintrags ansehen |
| `x` / `Esc` | Zurueck |

In den Menues gelten Pfeiltasten bzw. `w`/`s` zum Waehlen, Enter oder
Leertaste zum Bestaetigen und `Esc` fuer Zurueck.

## Mehrspieler im lokalen Netz

**Zwei bis fuenf Leute**, jeder an seinem eigenen Feld, alle mit
**derselben Steinfolge** - wer gewinnt, entscheidet das Spiel und nicht
das Glueck. Wer oben aus dem Feld baut, scheidet aus und schaut den
anderen zu.

**Der Gastgeber legt die Regeln fest**, und sie stehen in der Lobby jedes
Spielers:

| Modus | Wer gewinnt |
|---|---|
| **Ueberleben** (Vorgabe) | wer als Letzter im Feld ist |
| **Sprint** | wer nach 3 Minuten die meisten Rows hat |
| **Ultra** | wer zuerst 150 Rows abgebaut hat |

Dazu ein Schalter fuer die **Stoerreihen** (Vorgabe: **aus**). Ist er an,
schickt jeder Reihenabbau dem Gegner eine volle Reihe mit genau einem
Loch, die dessen Stapel nach oben drueckt - und ein eigener Abbau raeumt
zuerst die eigene Warteschlange, sodass sich der Gegenangriff gegenueber
reiner Abwehr lohnt. Gold- und Silberquadrate sind dabei die staerksten
Angriffe.

**Eine Runde spielen:**

1. Einer eroeffnet die Sitzung: Hauptmenue -> *Mehrspieler* -> *Spiel
   eroeffnen*. Die Lobby zeigt die eigene Adresse samt Port.
2. Die anderen gehen auf *Mehrspieler* -> *Spiel beitreten*: die Sitzung
   erscheint in der Liste, sobald ihr Beacon ankommt. Kommen im Netz
   keine Broadcasts durch (WLAN mit Client-Isolation, getrennte VLANs,
   manche Container-Netze), nimmt man *Direkt verbinden* und tippt die
   Adresse aus der Lobby ein - ein gleichwertiger zweiter Weg, kein
   Notnagel.
3. Der Gastgeber stellt ueber *Einstellungen* Modus und Stoerreihen ein -
   alle sehen die Aenderung sofort in ihrer Lobby - und startet, sobald
   genug Leute da sind. Ab dem zweiten Spieler ist der Eintrag frei; auf
   eine vorher verabredete Zahl wartet niemand.

Ohne Menue geht es auch direkt:

```
rowhammer --mp-host                                  # Gastgeber
rowhammer --mp-host --mp-mode sprint --mp-garbage on # ... mit festen Regeln
rowhammer --mp-join 192.168.1.23                     # Beitreten
```

**Was waehrend der Runde anders ist:** Es gibt **keine Pause** - die
anderen warten nicht. `Esc`/`x` oeffnet ein kleines Menue mit
*Fortsetzen* und *Runde verlassen*; die Verbindung laeuft dabei weiter.
Im HUD stehen links das Ziel des Modus (bei Sprint und Ultra), die
wartenden Stoerreihen ("Muell", nur wenn sie eingeschaltet sind) und die
Zahl der Spieler, die noch im Rennen sind ("Gegner").

**Die Mitspieler sitzen um das eigene Feld herum:** der erste rechts
daneben, der zweite links, der dritte weiter rechts, der vierte weiter
links - das eigene Feld bleibt in der Mitte. Ist das Terminal breit
genug, hat ein Gegnerfeld dieselbe Breite wie das eigene (140 Spalten bei
vier Gegnern); sonst werden daraus halb so breite Felder (100 Spalten bei
vieren). Reicht auch das nicht, werden aus den Gegnern zwei Zeilen bzw.
eine Zeile je Gegner, sodass eine Runde auch im 48x22-Minimum laeuft
(`--mp-view`).

**Wenn der Gastgeber geht:** Verlaesst er die **Lobby**, uebernimmt der
Spieler, der **zuerst beigetreten** ist - die Sitzung laeuft unter
demselben Namen weiter, alle anderen werden automatisch mitgenommen und
behalten ihren Platz. Die Bereit-Haken werden dabei zurueckgesetzt (der
neue Gastgeber darf die Regeln aendern), und jeder bekommt eine Meldung
mit dem neuen Gastgeber, die er mit `Enter` bestaetigt. Ist niemand mehr
da, der uebernehmen kann, meldet das Spiel die Sitzung als geschlossen.
Waehrend einer **laufenden Runde** ist das Weggehen des Gastgebers
dagegen ein gewoehnliches Ausscheiden - die Runde wird zu Ende gespielt.
Hoert eine Sitzung ganz ohne Abschied auf (Rechner aus, Netz weg), merken
das die Clients nach sechs Sekunden von selbst und kehren ins Menue
zurueck.

**Gewertet wird nur die eigene Leistung:** die eigenen Rows kommen in
eine eigene Bestenliste (*Highscores -> Mehrspieler*), zaehlen als
eigener Modus in der Statistik (mit den Siegen als Erfolgsquote) und
bauen am Weltwunder mit wie in jeder anderen Runde. Von den Mitspielern
fliesst nichts ein, und der Sieg selbst bringt keine Reihen.

**Auf einem gemeinsamen Rechner** (alle per SSH auf derselben Maschine)
spart `--mp-transport unix` die Netzwerkschicht: die Sitzung laeuft dann
ueber einen Unix-Socket im Sitzungsverzeichnis.

**Testen ohne mehrere Terminals:** `--mp-bot` ist ein Client ohne
Bildschirm, der einer Sitzung beitritt und zufaellig spielt:

```
rowhammer --mp-bot --mp-join 127.0.0.1
```

## Einstellungen und Optionen

Alle Spieldaten - Konfiguration, die sechs Bestenlisten,
Weltwunder-Spielstand, Statistik und die Demo-Aufzeichnungen im
Unterverzeichnis `demos` - liegen im Datenverzeichnis
`~/.config/rowhammer`, aenderbar per `--data-dir`.

| Option           | Umgebungsvariable        | Wirkung                                  |
|------------------|--------------------------|------------------------------------------|
| `--seed N`       | `ROWHAMMER_SEED`         | Reproduzierbare Teilfolge                |
| `--name NAME`    | `ROWHAMMER_PLAYER_NAME`  | Spielername fuer die Bestenlisten        |
| `--lang CODE`    | `ROWHAMMER_LANG`         | Sprache: `auto` (Standard, folgt der Locale), `de`, `en` |
| `--data-dir DIR` | `ROWHAMMER_DATA_DIR`     | Datenverzeichnis                         |
| `--no-color`     | `ROWHAMMER_NO_COLOR`     | Keine ANSI-Farben, je Steinsorte ein eigenes Zeichen |
| `--color-mode M` | `ROWHAMMER_COLOR_MODE`   | Farbpalette: `auto` (Standard), `basic`, `extended` |
| `--color-theme N`| `ROWHAMMER_COLOR_THEME`  | Farbschema: `guideline` (Standard), `classic`, `mono`, `colorblind` |
| `--render-mode M`| `ROWHAMMER_RENDER_MODE`  | Bildaufbau: `partial` (Standard), `full` |
| `--demo-record on\|off` | `ROWHAMMER_DEMO_RECORD` | Runden als Demo mitschneiden (Standard: `on`) |
| `--reset ZIEL`   | `ROWHAMMER_RESET`        | Gespeicherte Daten zuruecksetzen und beenden |
| `--force`        | `ROWHAMMER_FORCE`        | Sicherheitsabfragen automatisch mit "ja" beantworten |
| `--debug`        | `ROWHAMMER_DEBUG`        | Session-Trace in Log-Dateien             |
| `--debug-dir DIR`| `ROWHAMMER_DEBUG_DIR`    | Zielverzeichnis fuer die Debug-Logs      |
| `-h`, `--help`   | -                        | Hilfe mit allen Optionen und Tasten      |

Dazu die Mehrspieler-Optionen `--mp-host`, `--mp-join`, `--mp-session`,
`--mp-transport`, `--mp-port`, `--mp-dir`, `--mp-max`, `--mp-view`,
`--mp-target`, `--mp-mode`, `--mp-garbage` und `--mp-bot` - `--help`
zeigt sie alle.

### Sprache

Die gesamte Oberflaeche gibt es auf **Deutsch** und **Englisch** - Menues,
Anleitung, HUD, der Kasten am Rundenende, alle Tabellen und `--help`.
Gewaehlt wird sie im Einstellungsmenue (wirkt sofort, ohne Neustart), per
`--lang de|en|auto` oder per `ROWHAMMER_LANG`; gespeichert wird sie in der
Konfigurationsdatei. Der Standard `auto` nimmt die Sprache aus den
Locale-Variablen (`LC_ALL`, `LC_MESSAGES`, `LANG`) und faellt auf Deutsch
zurueck, wenn dort keine unterstuetzte Sprache steht.

```
rowhammer --lang en
LANG=en_US.UTF-8 rowhammer      # nimmt automatisch Englisch
```

Fehlermeldungen bleiben englisch - sie muessen auch dann lesbar sein, wenn
gerade die Sprache das Problem ist.

### Farben

Vier Farbschemata stehen zur Wahl: `guideline` (Standard), `classic`,
`mono` und `colorblind` (meidet das Rot/Gruen-Paar). Im
Einstellungsmenue gibt es zu jedem eine Farbvorschau. Auf
256-Farben-Terminals wird automatisch die satte Palette verwendet.

**Ohne Farben** (`--no-color`) bekommt jede Steinsorte ein eigenes
Zwei-Zeichen-Symbol (`II OO TT SS ZZ JJ LL`), damit sich die Steine auch
nach dem Ablegen unterscheiden lassen - Voraussetzung, um gezielt Gold-
und Silber-Quadrate zu bauen. Die Quadrate heben sich mit eigenen
Symbolen ab: Gold als `##`, Silber als `%%`. Die Flutreihen des
Hochwasser-Modus erscheinen als `::` - dieses Symbol auch mit Farben,
weil eine Reihe, die niemand gelegt hat, in jedem Schema erkennbar
bleiben soll.

Zusaetzlich wird die De-facto-Standardvariable
[`NO_COLOR`](https://no-color.org/) beachtet: ist sie gesetzt und nicht
leer, startet rowhammer ohne Farben. Das projekteigene
`ROWHAMMER_NO_COLOR` hat Vorrang - mit `ROWHAMMER_NO_COLOR=0` laesst sich
ein global exportiertes `NO_COLOR` fuer rowhammer wieder ueberschreiben,
und `--no-color` gewinnt in jedem Fall.

### Daten zuruecksetzen

`--reset ZIEL` setzt gezielt gespeicherte Daten zurueck und beendet das
Spiel, ohne es zu starten. Ziele: `config` (die Konfigurationsdatei),
`stats` (die Statistik), `highscore` (alle Bestenlisten), `save` (der
Weltwunder-Fortschritt), `demo` (die Aufzeichnungen) oder `all`.

**Geloescht wird dabei nichts:** jede betroffene Datei wandert nach
`<datei>-YYYYMMDDhhmmss.bak` im selben Verzeichnis, ein Reset laesst sich
also mit einem `mv` rueckgaengig machen.

Am Terminal werden die betroffenen Dateien erst aufgelistet und dann
abgefragt; die Vorgabe ist "nein", verschoben wird nur nach einem
ausdruecklichen `y`. `--force` beantwortet die Abfrage automatisch mit
"ja"; ohne Terminal (Skript, CI) laeuft der Reset ohnehin ohne
Rueckfrage durch. Bereits fehlende Dateien sind kein Fehler.

```
rowhammer --reset highscore
rowhammer --reset all --force
```

### Fehler melden

`--debug` zeichnet die komplette Sitzung in drei Log-Dateien auf
(Standardziel: `~/.local/state/rowhammer/debug/<Zeitstempel>.<PID>`):
jede Bildschirmausgabe, jeder Tastendruck und alle Spielaktionen. Das
hilft, Fehlverhalten im Nachhinein exakt nachzuvollziehen - haeng die
Logs einem Bug-Report an.

## Mitmachen / Entwicklung

Vier Dateien, vier Rollen:

| Datei | Inhalt |
| --- | --- |
| [CLAUDE.md](CLAUDE.md) | technisches Konzept, Architektur und die verbindlichen Skript-Konventionen - der Startpunkt fuer jede Weiterentwicklung |
| [TODO.md](TODO.md) | was noch offen ist: Roadmap und ungeklaerte Entscheidungen |
| [HISTORY.md](HISTORY.md) | was bereits umgesetzt ist, je Version und mit der Begruendung von damals |
| README.md (diese) | die Anleitung fuer Spielerinnen und Spieler |

Jeder Push und jeder Pull Request laeuft durch den CI-Workflow
(`.github/workflows/ci.yml`); den Release-Ablauf beschreibt
[docs/release-process.md](docs/release-process.md). Lokal nachvollziehen
lassen sich die Pruefungen so:

```
./tools/key-scan.sh              # Regressionstest der Eingabeschicht
./tools/key-scan.sh --gap 0.06   # dasselbe mit zerrissenen Sequenzen
./tools/state-check.sh           # Regressionstest des Rundenzustands
./tools/net-fuzz.sh              # Fuzz-Test der Mehrspieler-Parser
./tools/release.sh --mode check  # stimmen alle Versionsangaben ueberein?
```

Das Repository hat noch **keine Lizenzdatei**; solange die Lizenzfrage
offen ist, werden die Release-Pakete unsigniert gebaut und es gibt keine
oeffentliche Paketquelle.
