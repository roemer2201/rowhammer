# rowhammer

**Version:** 2.0.0

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
`asciinema play docs/demo/gold.cast`. Neu erzeugen (aus echtem Spiel,
gegen das Debug-Log verifiziert) lassen sie sich mit der Toolchain unter
[`tools/demo/`](tools/demo): `python3 tools/demo/make_demos.py`.

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

## Status

**Phasen 1 bis 3 sind umgesetzt** (spielbarer Kern, Startmenue, die
The-New-Tetris-Mechaniken und der Weltwunder-Modus): Spielfeld,
Bag-Randomizer mit Vorschau auf
3 Teile, Hold, Gravitation mit Levelkurve, Reihenabbau, Soft-/Hard-Drop,
Pause, Game Over mit Neustart - und das **Quadrat-System**: Wer ein
4x4-Feld aus genau vier unversehrten Bausteinen baut, erhaelt ein Gold-
(sortenrein) oder Silber-Quadrat (gemischt); jede abgebaute Reihe bringt
+10 Bonuszeilen je Gold- und +5 je Silber-Quadrat (ein Tetris +1 extra)
fuer den "Rows"-Zaehler. Dieser Zaehler baut ueber alle Runden hinweg
sieben **Weltwunder** aus ASCII-Art auf, die Stueck fuer Stueck von
unten nach oben entstehen; der Fortschritt wird dauerhaft gespeichert
und nach jeder Runde sowie im Hauptmenue angezeigt. Die
Anwendung startet in einem Menue mit Einzelspieler,
Mehrspieler, Highscores, Weltwunder, Statistik, Demos,
Einstellungen und einer kurzen Anleitung;
die besten
10 Runden werden dauerhaft gespeichert. Seit 2.0.0 ist der
**Mehrspieler** kein Platzhalter mehr, sondern eine Runde gegen zwei bis
sechs Leute im lokalen Netz (siehe unten). Dazu kommen die Politur-Schritte
aus Phase 4 - unter anderem waehlbare Farbschemata, Spielmodi
(Marathon/Ultra/Sprint/Time Attack/Hochwasser), Anleitung, Lock Delay,
der
gezielte Reset
gespeicherter Daten, die Demo-Aufzeichnung mit Wiedergabe und die
**mehrsprachige Oberflaeche** (Deutsch und Englisch, umschaltbar im
Spiel). Das vollstaendige Konzept
und die offene Roadmap stehen in [CLAUDE.md](CLAUDE.md), die bereits
abgeschlossenen Entwicklungsschritte je Version in
[HISTORY.md](HISTORY.md).

Der **Mehrspieler-Modus** ist die Arbeit an **Version 2.x.x**: der
Kern - Sitzung eroeffnen und beitreten, gemeinsame Steinfolge,
Stoerreihen, Ausscheiden und Sieger - laeuft seit 2.0.0. Offen bleiben
die Demo-Aufzeichnung einer Mehrspieler-Runde und der Server-Betrieb
darum herum (Phase 6: Accounts, Web-Highscore, Liga; siehe Roadmap in
[CLAUDE.md](CLAUDE.md)).

## Spielen

Direkt aus dem Repository:

```
./rowhammer.sh
```

Oder als Debian-Paket installieren (siehe unten), dann:

```
rowhammer
```

Das Startmenue bietet:

- **Fortsetzen** - erscheint nur, solange eine ueber das Pausenmenue
  ins Hauptmenue gelegte Runde wartet, und nimmt sie wieder auf; der
  Eintrag steht dann auch im Einzelspieler-Menue an erster Stelle
- **Einzelspieler** - die Spielmodi: **Marathon** (endlos, Ende
  durch Game Over), **Ultra** - 150 Rows so schnell wie moeglich
  abbauen -, **Sprint** - in 3 Minuten so viele Rows wie moeglich -,
  **Time Attack** - 1 Minute Restzeit, die rueckwaerts laeuft, und je
  abgebauter Row eine Sekunde dazu - und **Hochwasser** - alle 20
  Sekunden schiebt sich von unten eine volle Reihe mit einem einzigen
  Loch ins Feld.
  Die Ultra-Runde endet in dem Moment, in dem das Ziel
  erreicht ist; das Ergebnis ist die Spielzeit. Die Sprint-Runde endet,
  wenn die Zeit abgelaufen ist; das Ergebnis sind die Rows. Die
  Time-Attack-Runde dauert genau so lange, wie sie sich selbst am Leben
  haelt, und endet bei 00:00 - oder vorher im Game Over; das Ergebnis
  sind ebenfalls die Rows. Die Hochwasser-Runde ist sonst Marathon: sie
  endet, wenn der steigende Stapel oben ankommt, gewertet werden die
  Rows. In allen vier
  Modi zeigt der HUD zwei zusaetzliche Zeilen - bei Ultra Ziel
  ("Goal") und die noch fehlenden Rows ("Left"), bei Sprint das
  Zeitlimit und die verbleibende Zeit, bei Time Attack die bisher
  erspielte Gesamtzeit und den Rest davon, bei Hochwasser den
  Flut-Abstand ("Flut") und die Zeit bis zur naechsten Reihe ("Rest").
  Gewertete
  Rows
  zaehlen, nicht physische Reihen - Gold- und Silberquadrate sind also
  ueberall die Abkuerzung, bei Time Attack zugleich die Waehrung, mit
  der Spielzeit gekauft wird. Jeder Modus hat seine
  eigene Bestenliste
  (`~/.config/rowhammer/highscore-ultra`, schnellster Lauf
  zuerst, `~/.config/rowhammer/highscore-sprint`,
  `~/.config/rowhammer/highscore-timeattack` bzw.
  `~/.config/rowhammer/highscore-flood`, meiste Rows
  zuerst), die die 10 besten endlosen Runden unberuehrt laesst. Bei
  Ultra und Sprint wird ein Versuch, der vorher im Game Over endet,
  nicht eingetragen (seine
  Reihen zaehlen aber weiter fuer Weltwunder und Statistik); bei Time
  Attack und Hochwasser zaehlt dagegen jede Runde - die Rows sind so
  oder so dieselbe
  Leistung, und wer vorzeitig oben rausbaut, hat schlicht weniger
  davon
- **Mehrspieler** - eine Runde im lokalen Netz gegen zwei bis sechs
  Leute: Sitzung eroeffnen, einer gefundenen beitreten oder eine Adresse
  von Hand eingeben (siehe [unten](#mehrspieler-im-lokalen-netz))
- **Highscores** - fragt zuerst den Modus ab (**Marathon**, **Ultra**,
  **Sprint**, **Time Attack** oder **Hochwasser**) und zeigt danach
  dessen
  Bestenliste; die Auswahl
  bleibt
  stehen, bis "Zurueck" kommt, sodass sich die Listen vergleichen
  lassen. Je Liste die besten 10 Runden, je Eintrag zwei Zeilen und
  seitenweise geblaettert: Name, Rows (die Punkte der Runde), Spielzeit
  und Datum in der ersten, Gold-/Silberquadrate, Rowhammer ("RH"),
  abgelegte Teile ("PCS") und Teile je Minute ("PPM") in der zweiten.
  **Durch die Liste laeuft ein Cursor:** Pfeil hoch/runter waehlt den
  Eintrag (und blaettert dabei automatisch weiter), Pfeil links/rechts
  blaettert die Seiten vor und zurueck, `Esc` geht zurueck - beide
  Richtungen laufen um. Ein Eintrag, zu dem es noch eine
  **Demo-Aufzeichnung** gibt, ist mit `*` markiert; **Enter** spielt sie
  ab (siehe Menuepunkt "Demos"). Verknuepft sind Eintrag und Aufnahme
  ueber den Runden-Hash, den beide tragen.
  Die Ultra-Liste ist nach der kuerzesten Zeit sortiert und zeigt sie
  auf die Millisekunde genau (MM:SS.mmm) - dort ist die Zeit der Score,
  in den anderen vier Listen sind es die Rows. Die
  Sprint-Liste zeigt an der Stelle der Spielzeit die physischen Reihen
  ("Lines"): jeder Lauf dauert dieselben 3 Minuten, eine Zeitspalte
  stuende dort zehnmal gleich. Die Time-Attack- und die
  Hochwasser-Liste behalten die
  Zeitspalte dagegen - sie zeigt, wie lange sich ein Lauf am Leben
  gehalten bzw. das Wasser abgehalten hat. Ein Rundenende zeigt den
  erreichten Rang ausserdem direkt an.
  **Wer in der Liste steht, fragt das Spiel am Ende jeder Runde**, die
  wirklich einen Platz in einer der fuenf Listen bekommt: Der
  Spielername aus den Einstellungen
  steht dort vormarkiert - Enter uebernimmt ihn, das erste getippte
  Zeichen ersetzt ihn (eine Pfeiltaste hebt die Markierung auf, wenn
  der Name nur ergaenzt werden soll). Der eingegebene Name gilt fuer
  diese Runde; die Einstellung bleibt unveraendert. Ueber der
  Eingabezeile steht neben den Zahlen der Runde auch der **Platz, den
  sie in der Liste einnehmen wird** ("Bestenliste: Platz 3 von 10").
  Eine Runde, die die Top 10 verfehlt, wird nicht gefragt und geht
  direkt zum Rundenende-Bild
- **Weltwunder** - die aktuelle Baustelle mit Baustufe, Reihenstand
  und Gesamtfortschritt. Mit den **Pfeiltasten links/rechts** laesst
  sich zu den bereits **fertiggestellten** Weltwundern
  zurueckblaettern (umlaufend); `Enter`, Leertaste, `x` oder `ESC`
  schliessen den Bildschirm. Solange noch keines fertig ist, gibt es
  nichts zu blaettern und jede Taste schliesst ihn wie bisher
- **Statistik** - fragt zuerst, welche Sicht gezeigt werden soll:
  **Gesamt** oder einer der fuenf Spielmodi.
  **Gesamt** zeigt auf drei Bildschirmen die Zaehler ueber alle
  Runden (abgebaute Reihen, Bonusreihen, gebaute Gold- und
  Silberbloecke, die "Rowhammer" - vier Reihen auf einmal -, die
  abgelegten Teile, die Gesamtspielzeit und die daraus berechneten
  Steine/Minute), danach die Ergebnisse der letzten drei Spiele und
  zuletzt die gespielten Runden je Modus - bei Ultra, Sprint und Time
  Attack jeweils mit der Zahl der Laeufe, die ihr Ziel bzw. die volle
  Zeit erreicht haben.
  **Marathon**, **Ultra**, **Sprint**, **Time Attack** und
  **Hochwasser** zeigen
  dieselben Zaehler fuer nur diesen Modus, dazu seine Runden, die
  Rows je Runde und - bei den drei Zeitmodi - die Erfolgsquote seiner
  Laeufe.
  Jeder dieser Bildschirme - der Gesamtbildschirm, jede der letzten
  drei Runden und jeder Modus - nennt ausserdem das **Verhaeltnis von
  abgebauten Reihen zu Bonusreihen** ("1:2.34" heisst: eine abgebaute
  Reihe war 2.34 Bonusreihen wert), also wie viel der Reihenwertung aus
  den Gold- und Silber-Quadraten kam
- **Demos** - die aufgezeichneten Runden, neueste zuerst, mit Datum,
  Modus, Spielzeit und Rows. Die ausgewaehlte Aufnahme laesst sich
  **abspielen** oder **loeschen**. Aufbewahrt werden die 10 neuesten
  Runden; Aufnahmen, die noch einen Highscore-Eintrag belegen, sind mit
  `*` markiert und bleiben darueber hinaus erhalten (verknuepft ueber
  einen Hash im Dateinamen). Dieselbe Verknuepfung nutzt die
  Highscore-Liste in der Gegenrichtung: dort startet Enter die
  Aufzeichnung des ausgewaehlten Eintrags
- **Einstellungen** - Tastenbelegung aendern, **Sprache waehlen**
  (`Automatisch`, `Deutsch` oder `English`; die Auswahl gilt sofort,
  ohne Neustart), Farbschema waehlen
  (`guideline`, `classic`, `mono` oder `colorblind`, jeweils mit einer
  Farbvorschau in der Liste), Spielernamen setzen und die
  Demo-Aufzeichnung an- oder abschalten; alles fuenf wird in
  der Konfigurationsdatei gespeichert (Standard:
  `~/.config/rowhammer/rowhammer.conf`). Der Spielername ist die
  Vorgabe der Namensabfrage am Rundenende (siehe unten)
- **Anleitung** - kurze Spielerklaerung auf neun Bildschirmen, mit
  den Pfeiltasten links/rechts durchblaetterbar (umlaufend):
  Spielprinzip, Steuerung (mit der gerade eingestellten
  Tastenbelegung), Vorschau und Hold, Gold-/Silber-Quadrate mit ihrer
  Reihenwertung, der Weltwunderbau, die fuenf Spielmodi (auf zwei
  Seiten), die
  Bestenlisten und die Demos

Alle Spieldaten (Konfiguration, Highscores inklusive der Ultra-, der
Sprint-, der Time-Attack- und der Hochwasser-Liste,
Weltwunder-Spielstand,
Statistik, Demo-Aufzeichnungen im Unterverzeichnis `demos`)
liegen im Datenverzeichnis
`~/.config/rowhammer`, aenderbar per `--data-dir`.

Optionen:

| Option           | Umgebungsvariable        | Wirkung                                  |
|------------------|--------------------------|------------------------------------------|
| `--seed N`       | `ROWHAMMER_SEED`         | Reproduzierbare Teilfolge                |
| `--name NAME`    | `ROWHAMMER_PLAYER_NAME`  | Spielername fuer die Highscore-Liste     |
| `--lang CODE`    | `ROWHAMMER_LANG`         | Sprache der Oberflaeche: `auto` (Standard, folgt der Locale), `de`, `en` |
| `--data-dir DIR` | `ROWHAMMER_DATA_DIR`     | Datenverzeichnis (Config, Scores, Save)  |
| `--no-color`     | `ROWHAMMER_NO_COLOR`     | Keine ANSI-Farben, je Steinsorte ein eigenes Zeichen (auch Standard-`NO_COLOR`, s. u.) |
| `--color-mode M` | `ROWHAMMER_COLOR_MODE`   | Farbpalette: `auto` (Standard), `basic`, `extended` |
| `--color-theme N`| `ROWHAMMER_COLOR_THEME`  | Farbschema: `guideline` (Standard), `classic`, `mono`, `colorblind` |
| `--render-mode M`| `ROWHAMMER_RENDER_MODE`  | Bildaufbau: `partial` (Standard, nur geaenderte Zeilen), `full` (ganzer Block je Frame) |
| `--demo-record on\|off` | `ROWHAMMER_DEMO_RECORD` | Runden als Demo mitschneiden (Standard: `on`) |
| `--reset ZIEL`   | `ROWHAMMER_RESET`        | Persistente Daten zuruecksetzen und beenden (s. unten) |
| `--force`        | `ROWHAMMER_FORCE`        | Sicherheitsabfragen automatisch mit "ja" beantworten |
| `--debug`        | `ROWHAMMER_DEBUG`        | Session-Trace in Log-Dateien (s. unten)  |
| `--debug-dir DIR`| `ROWHAMMER_DEBUG_DIR`    | Zielverzeichnis fuer die Debug-Logs      |
| `-h/--help`      | -                        | Hilfe mit allen Optionen und Tasten      |

`--reset ZIEL` setzt gezielt gespeicherte Daten im Datenverzeichnis
zurueck und beendet das Spiel, ohne es zu starten. Moegliche Ziele:
`config` (die Konfigurationsdatei `rowhammer.conf`), `stats` (die
Statistik), `highscore` (alle Bestenlisten - `highscore-marathon`,
`highscore-ultra`, `highscore-sprint`, `highscore-timeattack` und
`highscore-flood`),
`save` (der
Weltwunder-Fortschritt), `demo` (das Verzeichnis `demos` mit den
Aufzeichnungen) oder `all`
(alles zusammen).

**Geloescht wird dabei nichts:** jede betroffene Datei wird nach
`<datei>-YYYYMMDDhhmmss.bak` im selben Verzeichnis verschoben, ein
Reset laesst sich also mit einem `mv` rueckgaengig machen. Wird
derselbe Reset zweimal in derselben Sekunde ausgefuehrt, wartet das
Spiel eine Sekunde und nimmt einen neuen Zeitstempel, statt das gerade
geschriebene Backup zu ueberschreiben.

Am Terminal werden die betroffenen Dateien erst aufgelistet und dann
abgefragt (`Bist du sicher, dass du <ziel> zuruecksetzen moechtest?
[N/y]`); die Vorgabe ist "nein", verschoben wird nur nach einem
ausdruecklichen `y` - danach meldet das Spiel `Reset erfolgreich`.
`--force`
beantwortet die Abfrage automatisch mit "ja" und laesst sich mit allen
anderen Optionen kombinieren; ohne Terminal (Skript, CI) laeuft der
Reset ohnehin ohne Rueckfrage durch. Bereits fehlende Dateien sind kein
Fehler.

```
rowhammer.sh --reset highscore
rowhammer.sh --reset all --force
```

Der Debug-Modus zeichnet die komplette Session in drei korrelierte
Log-Dateien auf (Standardziel:
`~/.local/state/rowhammer/debug/<Zeitstempel>.<PID>`): `frames.log`
(jede Bildschirmausgabe 1:1), `input.log` (jeder Tastendruck) und
`events.log` (alle Spielaktionen samt Board-Snapshots). Das hilft,
Fehlverhalten oder Spielsituationen im Nachhinein exakt
nachzuvollziehen - z. B. fuer einen Bug-Report.

Ohne Farben (`--no-color`) bekommt jede Steinsorte ein eigenes
Zwei-Zeichen-Symbol (`II OO TT SS ZZ JJ LL`), damit sich die Steine auch
nach dem Ablegen noch unterscheiden lassen - Voraussetzung, um gezielt
Gold- (sortenrein) und Silber-Quadrate (gemischt) zu bauen. Die Quadrate
selbst heben sich mit eigenen Symbolen ab: Gold als `##`, Silber als
`%%`. Die Flutreihen des Hochwasser-Modus erscheinen als `::` - dieses
Symbol auch mit Farben, weil eine Reihe, die niemand gelegt hat, in
jedem Farbschema erkennbar bleiben soll.

Zusaetzlich zu `--no-color`/`ROWHAMMER_NO_COLOR` wird die
De-facto-Standardvariable [`NO_COLOR`](https://no-color.org/) beachtet:
ist sie gesetzt und nicht leer, startet rowhammer ohne Farben. Das
projekteigene `ROWHAMMER_NO_COLOR` hat Vorrang - mit
`ROWHAMMER_NO_COLOR=0` laesst sich ein global exportiertes `NO_COLOR`
fuer rowhammer wieder ueberschreiben, und `--no-color` auf der
Kommandozeile gewinnt in jedem Fall.

**Sprache:** Die gesamte Oberflaeche gibt es auf **Deutsch** und
**Englisch** - Menues, Anleitung, HUD-Beschriftungen, der Kasten am
Rundenende, die Highscore- und Statistik-Tabellen, der
Weltwunder-Bildschirm, die Demo-Liste, der Reset-Dialog und `--help`.
Gewaehlt wird sie im Einstellungsmenue (wirkt sofort), per
`--lang de|en|auto` oder per `ROWHAMMER_LANG`; gespeichert wird sie in
der Konfigurationsdatei. Der Standard `auto` nimmt die Sprache aus den
Locale-Variablen (`LC_ALL`, `LC_MESSAGES`, `LANG`) und faellt auf
Deutsch zurueck, wenn dort keine unterstuetzte Sprache steht.
Fehlermeldungen nach STDERR bleiben englisch (Skript-Konvention) - sie
muessen auch dann lesbar sein, wenn gerade die Sprache das Problem ist.

```
rowhammer.sh --lang en
LANG=en_US.UTF-8 rowhammer.sh      # nimmt automatisch Englisch
```

Eine weitere Sprache ist eine Datei `lib/lang/<code>.sh` mit der
Texttabelle plus ein Eintrag in `I18N_LANGS` (`lib/i18n.sh`) - im
uebrigen Code steht kein einziger anzeigbarer Text mehr.

Die Tastenbelegung laesst sich zusaetzlich per Umgebungsvariablen
`ROWHAMMER_KEY_*` uebersteuern (siehe `--help`); erlaubt sind `a`-`z`,
`0`-`9`, `SPACE` und `NONE` (kein Buchstabe fuer diese Aktion).
Praezedenz: CLI > Umgebungsvariable > Konfigurationsdatei > Standardwert.

## Features

Umgesetzt:

- Klassisches 10x20-Spielfeld, 7 Bausteine, Bag-Randomizer mit einem
  Beutel aus **63 Steinen** (neun Saetze der sieben Sorten, als Ganzes
  gemischt): ueber einen vollen Beutel kommt jede Sorte gleich oft, die
  Reihenfolge darin ist aber frei genug fuer Haeufungen und Duerren -
  das ist es, was die Quadrat-Bildung dynamisch macht
- Vorschau auf die naechsten 3 Teile und Hold (einmal pro Zug)
- **Quadrat-System:** Gold- (sortenrein) und Silber-Quadrate (gemischt)
  aus je vier unversehrten Teilen; jede geraeumte Reihe zaehlt 1 plus
  +10 je Gold- und +5 je Silber-Quadrat in der Reihe (additiv), ein
  Tetris bringt +1 extra ("Rows" im HUD) - bis zu 85 in einem Zug.
  Diese Reihenwertung ist zugleich das Punktesystem: nur abgebaute
  Reihen bringen Punkte, Drops und Quadrat-Bildung nicht
- Soft-/Hard-Drop, Rotation mit einfachen Wall-Kicks, Pause, Neustart
- **Rundenende am oberen Feldrand:** Das Feld ist 20 Reihen hoch, und
  was darueber liegen bleibt, gehoert nicht mehr dazu - ein Stein, der
  in die verdeckten Spawn-Zeilen hineinragend festgesetzt wird, beendet
  die Runde, ebenso wie ein neuer Stein, der keinen Platz mehr findet.
  Geprueft wird nach dem Reihenabbau: wer oben heraussteht, aber dabei
  noch Reihen mitnimmt, holt den Stapel ins Feld zurueck und spielt
  weiter. Im Hochwasser-Modus gilt dieselbe Grenze fuer den steigenden
  Stapel
- **Lock Delay:** ein aufsetzender Stein wird nicht sofort festgesetzt,
  sondern laesst sich noch ein kurzes Gnadenfenster (250 ms) verschieben
  und drehen; der Hard-Drop setzt weiterhin sofort fest
- **Blinkende Reihen beim Abbau:** vollstaendige Reihen blinken kurz
  auf (zweimal hell/normal, zusammen rund 280 ms), bevor sie
  verschwinden und das naechste Teil erscheint
- **Pausenmenue statt hartem Abbruch:** `Esc`/`x` unterbricht die
  Runde; sie kann fortgesetzt, im selben Modus neu gestartet, ins
  Hauptmenue gelegt und dort ueber "Fortsetzen"
  wieder aufgenommen oder beendet werden - gewertet wird erst beim
  echten Rundenende (ein Neustart gibt die alte Runde auf, verbucht sie
  aber wie jede abgebrochene Runde). Die beiden Eintraege, die die Runde
  wegwerfen - "Neustarten" und "Runde beenden" -, fragen vorher mit dem
  Stand der Runde nach, ob es wirklich sein soll.
  Wer das Spiel verlaesst, waehrend noch eine pausierte Runde wartet,
  wird ebenfalls vorher gefragt
- Levelkurve (schneller je 10 Reihen)
- **Zentriertes Spielfeld-Layout:** ein festes 48x22-Feld, mittig im
  Terminal ausgerichtet - links der Hold-Stein und darunter die
  Rundenzaehler (Lines, Rows, Level, Gold, Silber, Rowhammer, Zeit,
  abgelegte Teile),
  das Spielfeld in der Mitte, die naechsten drei Steine oben rechts;
  Pause und Game Over erscheinen als Kasten ueber dem Spielfeld.
  Menues, Info-Bildschirme und die Weltwunder-Baustelle sind ebenfalls
  zentriert und buendig zum Spielfeld
- **Mehrsprachige Oberflaeche:** Deutsch und Englisch, waehlbar im
  Einstellungsmenue (wirkt sofort, ohne Neustart), per `--lang` oder
  `ROWHAMMER_LANG` und gespeichert in der Konfigurationsdatei; der
  Standard `auto` folgt der Locale. Uebersetzt ist alles Sichtbare -
  Menues, Anleitung, HUD, Rundenende-Kasten, Tabellen,
  Weltwunder-Bildschirm, Demo-Liste, Reset-Dialog und `--help`
- Farbige Darstellung ueber ANSI-Sequenzen, flackerfreies Rendering,
  sauberes Terminal-Restore beim Beenden
- **Inkrementelles Rendering:** je Frame werden nur die tatsaechlich
  geaenderten Zeilen neu geschrieben, unveraenderte Spielfeldreihen
  kommen aus einem Cache - rund 2x schnellerer Frame-Aufbau und ein
  Bruchteil der Terminal-Ausgabe gegenueber dem Voll-Frame.
  `--render-mode full` schaltet zurueck auf den Voll-Aufbau (jede Zeile
  je Frame) - gedacht als Rueckfalloption fuer Terminals oder
  Multiplexer, bei denen das inkrementelle Update falsch dargestellt
  wird, und um im Debug-Frame-Log ganze Frames zu sehen;
  `partial` bleibt der ressourcenschonende Standard
- **Reagiert auf Groessenaenderungen des Terminals** (SIGWINCH):
  zeichnet nach einem Resize sauber neu; wird das Terminal kleiner als
  das benoetigte 48x22, pausiert die Runde hinter einem Hinweis, bis
  wieder genug Platz da ist
- **Erweiterter Farbmodus:** auf 256-Farben-Terminals (automatisch
  erkannt, umschaltbar per `--color-mode`) eine satte xterm-Palette mit
  den Guideline-Teilfarben - inklusive echtem Orange fuer das L-Teil
  und kraeftigerem Gold/Silber fuer die Quadrate
- **Waehlbare Farbschemata:** `guideline` (Standard), `classic`, `mono`
  und `colorblind` (meidet das Rot/Gruen-Paar) - im Einstellungsmenue
  mit Farbvorschau waehlbar, per `--color-theme` setzbar und in der
  Konfiguration gespeichert; jedes Schema gilt in beiden Farbmodi.
  Highscore- und Statistik-Bildschirm nutzen dieselben Themenfarben
  (Gold/Silber fuer Rang 1 und 2, Akzentfarbe fuer den Score)
- Startmenue mit Einzelspieler, Mehrspieler, Highscores,
  Weltwunder, Statistik, Demos, Einstellungen und Anleitung
- **Mehrspieler im lokalen Netz** (seit 2.0.0): zwei bis sechs Spieler,
  gemeinsame Steinfolge, Stoerreihen durch abgebaute Reihen, Ausscheiden
  bei vollem Feld, letzter im Feld gewinnt; Sitzungssuche per
  UDP-Broadcast oder Verbindung ueber eine eingegebene Adresse, Anzeige
  der Mitspieler als Mini-Felder oder - bei schmalem Terminal - als
  Kurzzeilen; eigene Bestenliste und eigener Statistik-Modus. Braucht
  `socat`
- **Anleitung im Spiel:** zehn Bildschirme zu Spielprinzip,
  Steuerung,
  Vorschau/Hold, Gold- und Silberbloecken, Weltwunderbau, den
  Spielmodi (zwei Seiten), den Bestenlisten und den Demos; die
  Steuerungsseite zeigt immer die gerade eingestellte Tastenbelegung
- **Highscore-Eintraege mit Runden-Hash:** jede gewertete Runde bekommt
  einen kurzen Hash aus ihren eigenen Ergebnissen. Er steht im
  Highscore-Eintrag und im Dateinamen der zugehoerigen Demo - so ist die
  Aufnahme zu einem Highscore identifizierbar und wird beim Aufraeumen
  nie geloescht, solange der Eintrag in der Liste steht
- **Demo-Aufzeichnung und -Wiedergabe:** jede Runde wird mitgeschnitten
  und laesst sich ueber den Menuepunkt "Demos" noch einmal ansehen.
  Aufgezeichnet werden die Zuege, die Gravitationsschritte und die
  Steinfolge - nicht der Bildschirm: eine Wiedergabe spielt die Runde
  also wirklich noch einmal durch die echte Spiellogik. Das kostet rund
  2 kB je Spielminute und ist unabhaengig von Terminalgroesse, Farben
  und Render-Modus, in denen aufgenommen wurde. Waehrend der Runde wird
  ausschliesslich auf eine RAM-Disk geschrieben, erst am Rundenende
  wandert die fertige Aufnahme ins Datenverzeichnis (`demos/`, die 10
  neuesten). Die Wiedergabe laesst sich anhalten und zwischen 0.25x und
  4x Tempo abspielen; gewertet wird sie nie (kein Highscore, kein
  Weltwunder-Fortschritt, keine Statistik). Aufnahmen, die noch einen
  Highscore-Eintrag halten, sind in der Liste mit `*` markiert und
  bleiben ueber die 10 hinaus erhalten; umgekehrt startet Enter in der
  Highscore-Liste die Aufnahme des dort ausgewaehlten Eintrags
- **Spielmodi:** endloses **Marathon**, **Ultra** (150 Rows auf
  Zeit, eigene Bestenliste nach kuerzester Zeit), **Sprint**
  (3 Minuten auf Rows, eigene Bestenliste nach den meisten Rows),
  **Time Attack** (1 Minute Restzeit plus 1 Sekunde je Row, eigene
  Bestenliste nach den meisten Rows) und **Hochwasser** (alle 20
  Sekunden eine Flutreihe von unten, eigene Bestenliste nach den
  meisten Rows; siehe oben)
- Persistente Highscore-Listen: die besten 10 Marathon-Runden in
  `~/.config/rowhammer/highscore-marathon` (bis 0.50.0 hiess die Datei
  `highscore`; eine vorhandene wird beim naechsten Start einmalig
  umbenannt), die 10 schnellsten Ultra-Laeufe
  in `~/.config/rowhammer/highscore-ultra`, die 10 besten
  Sprint-Laeufe in `~/.config/rowhammer/highscore-sprint`, die 10
  besten Time-Attack-Laeufe in
  `~/.config/rowhammer/highscore-timeattack` und die 10 besten
  Hochwasser-Runden in `~/.config/rowhammer/highscore-flood`, im Menue
  ueber eine
  Modus-Auswahl erreichbar, Ranganzeige im Rundenende-Bild
- **Namensabfrage am Rundenende:** jede Runde, die einen Platz in einer
  Bestenliste bekommt, fragt vorher nach dem Namen fuer den Eintrag - mit
  dem
  Spielernamen aus den Einstellungen als vormarkierter Vorgabe, die ein
  einziger Tastendruck ersetzt. Der eingegebene Name gilt nur fuer diese
  Runde. Der Bildschirm nennt dabei den Platz, den die Runde in der
  Bestenliste ihres Modus einnehmen wird; verfehlt sie die Top 10, wird
  gar nicht erst gefragt. Die Spielzeit steht dort in jedem Modus auf
  die Millisekunde genau (MM:SS.mmm) - im Ultra ist sie die Wertung
- **Statistik:** persistente Gesamtzaehler in `~/.config/rowhammer/stats` -
  abgebaute Reihen, Bonusreihen (der Gold-/Silber-/Tetris-Anteil der
  Reihenwertung), gebaute Gold-/Silberbloecke, die Zahl der
  "Rowhammer" (vier Reihen auf einmal - der Namensgeber des Spiels)
  sowie abgelegte Teile und Spielzeit (daraus die Ablegerate in
  Teilen je Minute) und das Verhaeltnis von abgebauten Reihen zu
  Bonusreihen; dazu die Ergebnisse
  der letzten drei Spiele und die gespielten Runden je Modus (bei den
  drei Zeitmodi mit der Zahl der erfolgreichen Laeufe), einsehbar im
  Hauptmenue. **Jeder dieser Zaehler wird zusaetzlich je Spielmodus
  gefuehrt**, sodass sich dieselben Zahlen fuer Marathon, Ultra,
  Sprint, Time Attack oder Hochwasser allein ablesen lassen (samt Rows
  je Runde und Erfolgsquote); die Gesamtzaehler bleiben davon unberuehrt und werden
  weiter ueber alle Modi gefuehrt
- **Weltwunder-Modus:** der "Rows"-Zaehler baut ueber alle Runden
  hinweg sieben Weltwunder (Maya-Tempel, Stonehenge, Sphinx, Pantheon,
  Chinesische Mauer, Taj Mahal, Basilius-Kathedrale) als ASCII-Art
  Baustufe fuer Baustufe von unten auf; Fortschritt persistent in
  `~/.config/rowhammer/save`, Anzeige nach jeder Runde und im Menue -
  dort blaettern die Pfeiltasten links/rechts zu den bereits fertigen
  Wundern zurueck
- Konfigurierbare Tastenbelegung und Spielername, gespeichert in
  `~/.config/rowhammer/rowhammer.conf`
- **Gezielter Reset:** `--reset config|stats|highscore|save|all` setzt
  die gespeicherten Daten einzeln oder komplett zurueck - die alten
  Dateien wandern in ein `.bak` mit Zeitstempel statt geloescht zu
  werden, am Terminal mit Sicherheitsabfrage (`--force` beantwortet sie
  mit ja), im Skript ohne (s. o.)

Geplant:

- Spaeter: **Multiplayer** ueber das Netzwerk mit Garbage-Reihen

## Mehrspieler im lokalen Netz

Seit 2.0.0. **Zwei bis sechs Leute**, jeder an seinem eigenen Feld, alle
mit **derselben Steinfolge** - wer gewinnt, entscheidet das Spiel und
nicht das Glueck. Abgebaute Reihen schicken dem Gegner **Stoerreihen**
(eine volle Reihe mit genau einem Loch, die den Stapel nach oben
drueckt); wer oben aus dem Feld baut, scheidet aus und schaut den
anderen zu, und der letzte im Feld gewinnt.

**Eine Runde spielen:**

1. Einer eroeffnet die Sitzung: Hauptmenue -> *Mehrspieler* -> *Spiel
   eroeffnen*. Die Lobby zeigt die eigene Adresse samt Port.
2. Die anderen gehen auf *Mehrspieler* -> *Spiel beitreten*: die
   Sitzung erscheint in der Liste, sobald ihr Beacon ankommt. Kommen im
   Netz keine Broadcasts durch (WLAN mit Client-Isolation, getrennte
   VLANs, manche Container-Netze), nimmt man *Direkt verbinden* und
   tippt die Adresse aus der Lobby ein - ein gleichwertiger zweiter Weg,
   kein Notnagel.
3. Der Gastgeber startet, sobald genug Leute da sind. Ab dem zweiten
   Spieler ist der Eintrag frei; auf eine vorher verabredete Zahl wartet
   niemand.

Ohne Menue geht es auch direkt:

```
# Gastgeber
rowhammer --mp-host

# Beitreten
rowhammer --mp-join 192.168.1.23
```

**Was waehrend der Runde anders ist:** Es gibt **keine Pause** - die
anderen warten nicht. `Esc`/`x` oeffnet ein kleines Menue mit
*Fortsetzen* und *Runde verlassen*; die Verbindung laeuft dabei weiter.
Im HUD stehen links die wartenden Stoerreihen ("Muell") und die Zahl der
Spieler, die noch im Rennen sind ("Gegner"). Die Mitspieler zeigt das
Spiel rechts neben dem Feld als **Mini-Felder**; ist das Terminal dafuer
zu schmal, werden daraus zwei Zeilen bzw. eine Zeile je Gegner, sodass
eine Runde auch im 48x22-Minimum laeuft (`--mp-view`).

**Gewertet wird nur die eigene Leistung:** die eigenen Rows kommen in
eine eigene Bestenliste (*Highscores -> Mehrspieler*), zaehlen als
eigener Modus in der Statistik (mit den Siegen als Erfolgsquote) und
bauen am Weltwunder mit wie in jeder anderen Runde. Von den Mitspielern
fliesst nichts ein, und der Sieg selbst bringt keine Reihen.

**Auf einem gemeinsamen Rechner** (alle per SSH auf derselben Maschine)
spart `--mp-transport unix` die Netzwerkschicht: die Sitzung laeuft dann
ueber einen Unix-Socket im Sitzungsverzeichnis, und die Dateirechte sind
eine zusaetzliche Schranke.

**Testen ohne mehrere Terminals:** `--mp-bot` ist ein Client ohne
Bildschirm, der einer Sitzung beitritt und zufaellig spielt:

```
rowhammer --mp-bot --mp-join 127.0.0.1
```

## Installation aus einem Release

Der schnellste Weg: unter
[Releases](https://github.com/roemer2201/rowhammer/releases) haengt an
jeder Version ein fertiges Paket.

```
sudo apt install ./rowhammer_<version>_all.deb      # Debian, Ubuntu
sudo dnf install ./rowhammer-<version>-*.noarch.rpm # Fedora, RHEL, openSUSE
```

Ausserdem liegen dort das RPM-Quellpaket, ein Quell-Tarball und
`SHA256SUMS` mit den Pruefsummen aller Dateien. Wer lieber selbst baut,
findet die beiden Wege in den naechsten zwei Abschnitten.

## Installation als Debian-Paket

Das Repository enthaelt eine vollstaendige Debian-Paketierung (`debian/`,
`Makefile`). Bauen und installieren:

```
./build-deb.sh
sudo apt install ./dist/rowhammer_*.deb
```

Benoetigt werden `dpkg-dev`, `debhelper` und `build-essential` -
letzteres uebersetzt hier nichts, gilt `dpkg-checkbuilddeps` aber als
implizite Bau-Abhaengigkeit jedes Debian-Pakets. Das Paket installiert das
Spiel nach `/usr/share/rowhammer/` und legt den Starter
`/usr/games/rowhammer` an. Alternativ geht auch der klassische Weg mit
`dpkg-buildpackage -us -uc -b` oder eine Installation ohne Paket per
`sudo make install` (Standard-Praefix `/usr/local`, entfernen mit
`sudo make uninstall`).

## Installation als RPM-Paket

Fuer RPM-Distributionen (Fedora, RHEL, openSUSE) liegt die Spec-Datei
`rowhammer.spec` bei. Bauen und installieren:

```
./build-rpm.sh
sudo dnf install ./dist/rowhammer-*.noarch.rpm
```

Benoetigt werden `rpm-build`, `make` und `tar`. `build-rpm.sh` packt das
Quell-Tarball, laesst `rpmbuild` in einem eigenen Baum unterhalb von
`dist/` laufen (das `~/rpmbuild` des Aufrufers bleibt unangetastet) und
legt die fertigen Pakete in `dist/` ab. Nuetzliche Optionen:
`--srpm` baut zusaetzlich das Quellpaket, `--release N` setzt die
Release-Nummer fuer einen erneuten Bau derselben Version,
`--keep-build` behaelt den Build-Baum zum Nachsehen; `--help` zeigt alle
Optionen samt zugehoeriger `ROWHAMMER_RPM_*`-Umgebungsvariablen.

Das RPM installiert dieselben Pfade wie das Debian-Paket
(`/usr/share/rowhammer/` plus Starter `/usr/games/rowhammer`), weil beide
Pakete denselben `make install`-Aufruf nutzen. Die `Version` in
`rowhammer.spec` muss zu `ROWHAMMER_VERSION` in `rowhammer.sh` passen -
`build-rpm.sh` bricht bei Abweichung mit einer Meldung ab, statt ein
falsch beschriftetes Paket zu bauen.

## Voraussetzungen

- Bash >= 4.0 (empfohlen: Bash 5)
- Ein Terminal mit ANSI-Farbunterstuetzung, mindestens 48x22 Zeichen
  (kleiner wird nicht gestartet; eine Verkleinerung waehrend des Spiels
  pausiert bis wieder genug Platz da ist)
- Keine weiteren Abhaengigkeiten ausser Coreutils
- Fuer den **Mehrspieler** zusaetzlich `socat` (Debian/Ubuntu:
  `apt install socat`, Fedora/RHEL: `dnf install socat`). Es ist in
  beiden Paketen nur *empfohlen*: ohne socat laeuft das Einzelspieler-
  Spiel unveraendert, und der Menuepunkt sagt, welches Paket fehlt

## Steuerung

Standardbelegung; die Buchstabentasten (`a`, `d`, `c` usw.) sind im
Einstellungsmenue aenderbar, waehrend die Pfeiltasten sowie Leertaste
(Hard-Drop) und `w` (Hold) als feste Sekundaerbelegung immer aktiv
bleiben. Gedreht wird also mit der linken Hand (`a`/`d`), bewegt mit den
Pfeiltasten. Der Spielbildschirm zeigt die Belegung nicht mehr an - dort
stehen jetzt die Rundenzaehler:

| Taste                     | Aktion                      |
|---------------------------|-----------------------------|
| Pfeil links / rechts      | Links / Rechts              |
| `d`                       | Rotation im Uhrzeigersinn   |
| `a`                       | Rotation gegen Uhrzeigersinn|
| `s` / Pfeil runter        | Soft-Drop                   |
| Leertaste, Pfeil hoch     | Hard-Drop                   |
| `c` / `w`                 | Hold / Tauschen             |
| `p`                       | Pause                       |
| `Esc` / `x`               | Pausenmenue (Fortsetzen / Neustarten / Ins Hauptmenue / Runde beenden) |

Im Mehrspieler gibt es keine Pause: `p` bleibt wirkungslos, und
`Esc`/`x` oeffnet ein Menue mit nur zwei Eintraegen (Fortsetzen, Runde
verlassen), waehrend die Verbindung weiterlaeuft.
| `r`                       | Neustart (im Game-Over-Bild)|

Waehrend der Wiedergabe einer Demo (Menuepunkt "Demos"):

| Taste                     | Aktion                      |
|---------------------------|-----------------------------|
| `p` / Leertaste           | Anhalten / weiter           |
| Pfeil links / rechts      | Tempo (0.25x bis 4x)        |
| `x` / `Esc`               | Zurueck zur Demo-Liste      |
| `r`                       | Noch einmal (am Ende)       |

In einer Bestenliste (Menuepunkt "Highscores"):

| Taste                     | Aktion                      |
|---------------------------|-----------------------------|
| Pfeil hoch / runter       | Eintrag waehlen             |
| Pfeil links / rechts      | Seite vor / zurueck         |
| Enter                     | Demo des Eintrags ansehen   |
| `x` / `Esc`               | Zurueck                     |

Links, Rechts und Hard-Drop haben in der Standardbelegung bewusst keine
Buchstabentaste (`a`, `d` und `w` werden fuer Drehen und Hold gebraucht);
im Einstellungsmenue laesst sich jederzeit wieder eine vergeben.

In den Menues gelten Pfeiltasten bzw. `w`/`s` zum Waehlen, Enter oder
Leertaste zum Bestaetigen und `Esc` fuer Zurueck.

## Mitmachen / Entwicklung

Konzept, Architektur, Roadmap und die verbindlichen Skript-Konventionen sind
in [CLAUDE.md](CLAUDE.md) dokumentiert. Diese Datei ist der Startpunkt fuer
jede Weiterentwicklung. Was bereits umgesetzt ist - jeder erledigte
Roadmap-Punkt mit seiner Begruendung und der Version, in der er kam -
steht im Archiv [HISTORY.md](HISTORY.md); den *aktuellen* Zustand einer
Funktion beschreiben dagegen CLAUDE.md und diese README.

### Pruefungen und Releases

Jeder Push und jeder Pull Request laeuft durch den CI-Workflow
(`.github/workflows/ci.yml`): Bash-Syntax, ShellCheck, die
ASCII-Konvention, der Versions-Abgleich, der Eingabe-Regressionstest
`tools/key-scan.sh` sowie der Bau **und** die Installation von
Debian- und RPM-Paket. Vieles davon laesst sich lokal genauso aufrufen:

```
./tools/key-scan.sh              # Regressionstest der Eingabeschicht
./tools/key-scan.sh --gap 0.06   # dasselbe mit zerrissenen Sequenzen
./tools/release.sh --mode check  # stimmen alle Versionsangaben ueberein?
```

Ein Release ist das Tag `v<version>`; sein Push startet den
Release-Workflow, der die Pakete baut und das GitHub-Release mit seinen
Assets anlegt. Die Release-Notes sind die zugehoerige Strophe aus
`debian/changelog`. Den ganzen Ablauf - inklusive der vier Stellen, an
denen die Versionsnummer steht (die Zeile ganz oben in dieser README,
`ROWHAMMER_VERSION` in `rowhammer.sh` und die beiden Paketdateien) -
beschreibt [docs/release-process.md](docs/release-process.md).
