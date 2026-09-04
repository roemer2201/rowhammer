# HISTORY.md - rowhammer

Diese Datei ist das **Archiv der erledigten Punkte** aus
[TODO.md](TODO.md). Ein Punkt wird hierher verschoben, sobald er
umgesetzt ist; TODO.md fuehrt damit nur noch, was tatsaechlich offen ist.

**Wo steht was:**

| Datei | Inhalt |
| --- | --- |
| **HISTORY.md** (diese) | Archiv der erledigten Punkte, nach Version |
| [TODO.md](TODO.md) | offene Punkte - Roadmap und Entscheidungen |
| [CLAUDE.md](CLAUDE.md) | technisches Konzept und Arbeitskonventionen |
| [README.md](README.md) | Anleitung fuer Spielerinnen und Spieler |

**Lesehinweis - was hier steht und was nicht:**

- Jeder Eintrag beschreibt den Stand **zum Zeitpunkt seiner Umsetzung**,
  samt der damaligen Begruendung. Das ist der Zweck dieser Datei: sie
  bewahrt das "warum", das aus einem Diff nicht mehr hervorgeht. Ein
  _"Vorzustand: ..."_ nennt dabei, was die Version abgeloest hat - die
  Beschreibung in CLAUDE.md fuehrt nur den heutigen Stand.
- Der **aktuelle** Zustand einer Funktion steht **nicht hier**, sondern in
  CLAUDE.md (Abschnitte 1 bis 5: Spielkonzept, technisches Konzept,
  Mehrspieler-Spezifikation) und - fuer alles Spielersichtbare - in der
  README.md. Wo eine spaetere Version einen Eintrag ueberholt hat, steht
  darunter eine Zeile _"Spaeter ueberholt: ..."_ mit dem Verweis auf die
  abloesende Version.
- **Nackte Abschnittsnummern** ("siehe 3.1", "siehe 5.20") verweisen
  immer auf **CLAUDE.md**.
- Im Zweifel gilt CLAUDE.md/README.md, nicht diese Datei.

Arbeitsregel dazu (siehe CLAUDE.md Abschnitt 6): Wer einen Punkt aus
TODO.md abschliesst, verschiebt ihn hierher **und** prueft, ob CLAUDE.md
1-5 und die README.md den neuen Zustand richtig beschreiben.

## Uebersicht

| Version | Thema | Konzept in CLAUDE.md |
| --- | --- | --- |
| 0.1.0 | Spielbarer Kern (Phase 1) | 3.1, 4.3 |
| 0.2.0 | Startmenue und Nutzer-Konfiguration | 4.2, 4.5 |
| 0.3.0 | The-New-Tetris-Mechaniken (Phase 2) | 3.2, 4.4 |
| 0.4.0 | Bonus-Reihenwertung gegen das Original verifiziert | 3.2 |
| 0.5.0 | Standard-Tastenbelegung (`w`/`e`/`c`) | 3.1 |
| 0.6.0 | Debug-Modus | 4.6 |
| 0.7.0 | Highscore-Liste (Top 10) | 4.5 |
| 0.8.0 | Weltwunder-Aufbau (Phase 3) | 3.3 |
| 0.9.0 | 256-Farben-Modus | 4.1 |
| 0.10.0 | Spielstatistik | 4.5 |
| 0.12.0 | Pausenmenue und fortsetzbare Runden | 3.1, 3.3 |
| 0.14.0 | Datum in der Highscore-Liste | 4.5 |
| 0.15.0 | Gold-/Silberzaehler in der Highscore-Liste | 4.5 |
| 0.16.0 | Punktesystem-Umbau (Rows = Score) | 3.2 |
| 0.16.1 | Fehlinterpretierte Tastendruecke (Issue #7) | 4.3 |
| 0.17.0 | Spielzeit-Counter; Debian-Paketierung | 3.4, 4.7 |
| 0.18.0 | Lock Delay | 3.1 |
| 0.19.0 | Anpassung an Terminalgroesse (SIGWINCH); README-Democlips | 4.3 |
| 0.20.0 | Blinkeffekt beim Reihenabbau | 3.1 |
| 0.21.0 | Konfigurierbare Farben (Farbschemata) | 4.1 |
| 0.22.0 | Inkrementelles Rendering, zentriertes Layout, Beenden-Abfrage | 3.4, 4.3 |
| 0.23.0 | Eingabeschicht gehaertet | 4.3 |
| 0.24.0 | "rowhammer"-Zaehler (Runde und Statistik) | 4.5 |
| 0.25.0 | Rowhammer in HUD, `recent=` und Highscore; Wunder-Fortschritt raus aus dem HUD | 3.3, 3.4, 4.5 |
| 0.26.0 | HUD-Zaehler in die linke Spalte, Minimum 48x22 | 3.4 |
| 0.27.0 | Zaehler der abgelegten Teile, zweizeilige Tabellen | 3.4, 4.5 |
| 0.28.0 | Glyphen ohne Farbe, `NO_COLOR`, zentrierte Menues | 4.1, 4.3 |
| 0.28.1 | Rohmodus fuer die ganze Sitzung (Issue #33) | 4.3 |
| 0.29.0 | Highscore-Zeilen mit fehlenden Zaehlerfeldern | 4.5 |
| 0.30.0 | Farbige Highscore- und Statistik-Bildschirme | 4.5 |
| 0.31.0 | Standard-Tastenbelegung `a`/`d`/`w`, Bindungswert `NONE` | 3.1 |
| 0.32.0 | Anleitung im Hauptmenue | 3.5 |
| 0.33.0 | Anleitung mit den Pfeiltasten blaetterbar | 3.5 |
| 0.34.0 | Ultra-Modus samt eigener Bestenliste | 3.6, 4.5 |
| 0.34.1 | Endloser Modus heisst "Marathon" | 3.6 |
| 0.35.0 | `--reset config\|stats\|highscore\|save\|all` | 4.8 |
| 0.36.0 | Reset sichert statt zu loeschen, `--force` | 4.8 |
| 0.36.1 | Reset-Dialog auf Deutsch | 4.8 |
| 0.37.0 | RPM-Paketierung | 4.7 |
| 0.38.0 | Ultra-Bestenliste anzeigen, Modus-Auswahl unter "Highscores" | 4.5 |
| 0.39.0 | Sprint-Modus samt eigener Bestenliste, Anleitungsseite "Spielmodi" | 3.5, 3.6, 4.5 |
| 0.40.0 | Release-Struktur auf GitHub und CI-Paketbau | 4.7, 4.9 |
| 0.41.0 | Umschaltbarer Render-Modus (`partial`/`full`) | 4.3 |
| 0.42.0 | Time-Attack-Modus samt Bestenliste, Statistik je Modus | 3.5, 3.6, 4.5 |
| 0.43.0 | "Neustarten" im Pausenmenue | 3.1, 3.3 |
| 0.44.0 | Weltwunder-Kosten x100 (Groessenordnung des Originals) | 3.3 |
| 0.45.0 | Namensabfrage am Rundenende (vormarkierte Vorgabe) | 3.7, 4.3, 4.5 |
| 0.46.0 | Demo-Aufzeichnung und Demo-Player | 3.5, 3.8, 4.10 |
| 0.47.0 | Vollstaendige Statistik je Spielmodus | 4.5 |
| 0.48.0 | Mehrsprachige Oberflaeche (Deutsch/Englisch) | 4.11 |
| 0.49.0 | Hochwasser-Modus samt eigener Bestenliste | 3.5, 3.6, 4.5, 4.10 |
| 0.50.0 | Platz in der Bestenliste in der Namensabfrage | 3.7, 4.5 |
| 0.51.0 | Marathon-Bestenliste heisst `highscore-marathon` | 4.5, 4.8 |
| 0.52.0 | Bestenlisten mit Cursor, Blaettern und Demo-Wiedergabe | 3.5, 3.8, 4.5 |
| 0.53.0 | Modus-Eintraege mit ausgerichteter Beschreibung | 3.6, 4.2 |
| 0.54.0 | Wunder-Bildschirm blaettert zu den fertigen Wundern | 3.3, 3.5 |
| 0.55.0 | Verhaeltnis Reihen/Bonus in jeder Statistik | 4.5 |
| 1.0.1 | Namensabfrage nur noch bei einem Platz in der Liste | 3.7, 4.5 |
| 1.0.2 | Rundenende am oberen Feldrand | 3.1, 3.6 |
| 1.0.3 | Spielzeit der Namensabfrage auf die Millisekunde; Versionszeile in der README | 3.7, 4.9 |
| 1.0.4 | Beutel des Randomizers auf 63 Steine (Dynamik der Spezialbloecke) | 3.1 |
| 1.1.0 | Mehrspieler im lokalen Netz (Phase 5, Schritte 1-8 und 10-12) | 5.1-5.10 |
| 1.2.0 | Gastgeberwechsel: die Lobby ueberlebt ihren Gastgeber; Client-Timeouts | 5.1, 5.4, 5.8 |
| 1.3.0 | Fuenf Spieler, Sitzordnung um das eigene Feld, volle Zellenbreite; Unterbau und Aufzeichnung der Mehrspieler-Demo (Teilschritte 9.1-9.10) | 4.1, 4.10, 5.1, 5.4, 5.6, 5.20 |

## Phase 1 - Spielbarer Kern (umgesetzt, Version 0.1.0)

- [x] Projektgeruest anlegen (`rowhammer.sh`, `lib/`-Module, Header nach Konvention)
- [x] Terminal-Handling: Raw-Mode, alternativer Screen-Buffer, sauberes
      Aufraeumen per `trap`
- [x] Nicht-blockierender Input inkl. Pfeiltasten-Escape-Sequenzen
- [x] Spielfeld-Datenmodell und Kollisionspruefung
- [x] Baustein-Definitionen mit Rotationstabellen, 7-Bag-Randomizer
- [x] Game-Loop mit Gravitation, Lock, Reihenabbau
- [x] Rendering mit Double-Buffering und Farben
- [x] Soft-/Hard-Drop, Pause, Game Over (mit Neustart per `r`)

_Spaeter ueberholt: der Voll-Frame-Renderer wich in 0.22.0 dem
inkrementellen Rendering (siehe dort und CLAUDE.md 4.3); der Rohmodus
gilt erst seit 0.28.1 fuer die ganze Sitzung._

## Zwischenschritt - Menue und Konfiguration (umgesetzt, Version 0.2.0)

- [x] Startmenue: Einzelspieler / Mehrspieler / Einstellungen / Beenden
- [x] Einzelspieler-Untermenue mit "Normales Spiel" (weitere Modi spaeter)
- [x] Mehrspieler als Platzhalter ohne Funktion (Hinweis-Bildschirm)
- [x] Einstellungen: Tastenbelegung im Spiel aenderbar, Spielername
- [x] Nutzer-Konfigurationsdatei (`rowhammer.conf`) nach Konvention,
      atomar geschrieben, Praezedenz Standard < Config < Env < CLI

_Spaeter ueberholt: das Hauptmenue ist seither um Highscores (0.7.0),
Weltwunder (0.8.0), Statistik (0.10.0), Fortsetzen (0.12.0) und
Anleitung (0.32.0) gewachsen; das Einzelspieler-Menue waehlt seit 0.34.0
den Spielmodus (seit 0.39.0 drei), "Normales Spiel" heisst seit 0.34.1
"Marathon". Die
Einstellungen kennen seit 0.21.0 zusaetzlich das Farbschema. Der
Config-Pfad wanderte in 0.7.0 ins Datenverzeichnis und mit diesem in
0.13.0 nach `${HOME}/.config/rowhammer` (siehe CLAUDE.md 4.2, 4.5)._

## Zwischenschritt - Paketierung (deb umgesetzt 0.17.0, rpm 0.37.0, Release/CI 0.40.0)

- [x] `Makefile` mit install/uninstall (DESTDIR/PREFIX, deb/rpm-tauglich)
- [x] Debian-Paketierung (`debian/` mit debhelper, natives Paket,
      Launcher-Symlink `/usr/games/rowhammer`)
- [x] Build-Skript `build-deb.sh` nach Script-Konventionen
- [x] RPM-Paketierung (Version 0.37.0): Spec-Datei `rowhammer.spec` im
      Wurzelverzeichnis, die im `%install`-Abschnitt dasselbe
      `make install DESTDIR=... PREFIX=/usr` aufruft wie `debian/rules`,
      sodass beide Pakete dieselben Pfade liefern und ein Layout-Wechsel
      nur das `Makefile` betrifft. Dazu `build-rpm.sh` nach den
      Script-Konventionen als Gegenstueck zu `build-deb.sh`: baut das
      Quell-Tarball aus dem Arbeitsbaum, laesst `rpmbuild` in einem
      privaten `_topdir` unter `dist/` laufen (das `~/rpmbuild` des
      Aufrufers bleibt unberuehrt) und sammelt die Pakete in `dist/`;
      Optionen `--output-dir`, `--release N`, `--srpm`, `--keep-build`,
      `--verbose`, `--silent` je mit `ROWHAMMER_RPM_*`-Variable. Das
      Skript bricht ab, wenn die `Version` im Spec und
      `ROWHAMMER_VERSION` in `rowhammer.sh` auseinanderlaufen (siehe
      4.7). Getestet: gebautes Paket ist `noarch`, installiert
      `/usr/share/rowhammer/` plus Symlink `/usr/games/rowhammer`, und
      das Spiel startet ueber diesen Starter; das mit `--srpm`
      erzeugte Quellpaket laesst sich per `rpmbuild --rebuild`
      eigenstaendig neu bauen.
- [x] **Release-Struktur auf GitHub** (Version 0.40.0): ein Release ist
      das Tag `v<version>`, und mehr als dessen Push braucht es nicht.
      Werkzeug dafuer ist `tools/release.sh` nach den
      Script-Konventionen - das einzige Stueck Code, das alle drei
      Stellen kennt, an denen die Version steht (`ROWHAMMER_VERSION` in
      `rowhammer.sh`, die oberste Strophe von `debian/changelog`, die
      `Version` samt `%changelog` in `rowhammer.spec`). Es prueft, ob sie
      uebereinstimmen **und** ob beide Changelogs die Version wirklich
      dokumentieren, gibt die Release-Notes aus und legt das annotierte
      Tag mit diesen Notes als Nachricht an.
      Drei Entscheidungen dabei: (1) **Die Release-Notes sind die
      Changelog-Strophe**, kein eigener Text - die Strophe muss fuers
      Debian-Paket ohnehin geschrieben werden, und ein zweiter,
      unabhaengiger Text wuerde frueher oder spaeter etwas anderes
      erzaehlen als das Paket, das danebenliegt. (2) **Keine
      Vorab-Tags** wie `v0.40.0-rc1`: rowhammer ist ein *natives*
      Debian-Paket, dessen Version keinen Bindestrich tragen darf - ein
      solches Tag liesse sich gar nicht als `.deb` bauen und wird
      deshalb sofort abgewiesen statt spaet in `dpkg-buildpackage`.
      (3) **Assets sind `.deb`, `.rpm`, `.src.rpm`, Quell-Tarball und
      `SHA256SUMS`**; die `.changes`- und `.buildinfo`-Dateien bleiben
      draussen, weil sie Build-Metadaten sind, die niemand herunterlaedt.
      Der Ablauf ist in `docs/release-process.md` dokumentiert.
- [x] **Paketierung GitHub-seitig automatisch bauen** (Version 0.40.0):
      zwei Workflows unter `.github/workflows/` (siehe CLAUDE.md 4.9).
      `ci.yml` laeuft bei jedem Push und Pull Request und prueft
      Bash-Syntax, ShellCheck, die ASCII-Regel, die Versions-Konsistenz,
      den Eingabe-Regressionstest `tools/key-scan.sh` (auch mit
      Byte-Luecke, dem Fall aus Issue #7) und baut beide Pakete.
      `release.yml` reagiert auf ein `v*`-Tag, baut dieselben Pakete plus
      Quell-Tarball und Pruefsummen und veroeffentlicht das GitHub-
      Release.
      Vier Entscheidungen: (1) **ShellCheck blockiert nur auf Stufe
      `error`** - dort ist der Baum sauber, waehrend die 75 verbleibenden
      Warnungen Fehlalarme der Modul-Architektur sind (`lib/*.sh` wird
      gesourct, seine Variablen wirken einzeln geprueft ungenutzt und
      seine Arrays wie Skalare: SC2034, SC2128, SC2178); der volle
      Bericht wird trotzdem ausgegeben. (2) **Die Pakete werden nicht nur
      gebaut, sondern installiert und aufgerufen** - der Starter ist ein
      relativer Symlink nach `/usr/share`, ein falscher Pfad faellt also
      erst nach der Installation auf. Als Spielprogramm laeuft rowhammer
      im CI nur so weit, wie es ohne Terminal geht; das sind `--help` und
      `--reset`, und genau die nutzen die Smoke-Tests. (3) **Das RPM wird
      zusaetzlich in einem Fedora-Container installiert**: nur dort wird
      der `%files`-Abschnitt wirklich geprueft, samt des bewusst
      mitbesessenen Verzeichnisses `/usr/games` (siehe 4.7). (4) **Das
      Release entsteht mit der `gh`-CLI des Runners** statt mit einer
      fremden Action - eine Abhaengigkeit weniger in einem Workflow mit
      Schreibrechten aufs Repository.
      Dabei fiel ein Fehler auf: `build-deb.sh` und `build-rpm.sh` gaben
      ihre Meldungen nur bei erkanntem Terminal aus (`[ -t 1 ]`, gemaess
      der Logging-Regel der Script-Konventionen). Ein CI-Runner hat weder
      Terminal noch ein Journal, in das jemand schaut - beide Skripte
      scheiterten dort also vollstaendig lautlos, Fehlermeldungen
      inklusive. Seit 0.40.0 schaltet ein gesetztes `CI` die
      Konsolenausgabe zusaetzlich frei (beide Skripte auf 1.1.0).
      Der erste CI-Lauf brachte noch einen zweiten Fund: der Debian-Bau
      braucht `build-essential`. rowhammer uebersetzt nichts, aber
      `dpkg-checkbuilddeps` fordert das Paket als *implizite*
      Bau-Abhaengigkeit jedes Debian-Pakets ein, und das Runner-Image
      bringt es nicht mit - beides Gruende, aus denen es lokal nie
      auffiel. Es steht seither in beiden Workflows und in der
      Abhaengigkeitsliste von `build-deb.sh --help` und der README.

Die offenen Punkte dieses Zwischenschritts (Shell-Kompatibilitaet, opkg,
Lizenz) stehen weiterhin in der Roadmap.

## Phase 2 - The-New-Tetris-Mechaniken (umgesetzt, Version 0.3.0)

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

## Zwischenschritt - Debug-Modus (umgesetzt, Version 0.6.0)

- [x] `--debug`/`--debug-dir` mit Session-Verzeichnis und drei
      korrelierten Log-Dateien (`frames.log`, `input.log`, `events.log`),
      Konzept siehe 4.6
- [x] Zentraler Ausgabe-Trichter `screen_write` (Frames 1:1 auch fuer
      Menues und Terminal-Setup)
- [x] Instrumentierung aller Spielaktionen inkl. blockierter Versuche,
      Board-Snapshots nach jedem Lock

## Phase 3 - Weltwunder (umgesetzt, Version 0.8.0)

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

_Spaeter ueberholt: der Baufortschritt hat den HUD in 0.25.0 verlassen
und steht seither nur noch auf dem Weltwunder-Bildschirm (siehe
CLAUDE.md 3.3, 3.4). Die hier skalierten Reihen-Kosten (100..6400) sind
in 0.44.0 auf Nutzerentscheidung mit 100 multipliziert worden
(10.000..640.000, siehe CLAUDE.md 3.3)._

## Phase 4 - Politur (erledigte Punkte, nach Version sortiert)

- [x] Standard-Tastenbelegung geaendert (siehe 3.1, Version 0.5.0):
      `w`/Pfeil hoch **und** Leertaste fuer Hard-Drop, `e` fuer Rotation
      im Uhrzeigersinn, `c`/`2` fuer Hold/Tauschen. Pfeil hoch und
      Leertaste liegen als feste Sekundaerbelegung auf dem Hard-Drop,
      `2` fest auf Hold; `w`, `e` und `c` sind die konfigurierbaren
      Primaertasten.
      _Spaeter ueberholt: 0.31.0 (siehe unten) legt Rotation auf `a`/`d`
      und Hold-Sekundaertaste auf `w`._
- [x] Highscore-Liste (Version 0.7.0: Top 10 im Datenverzeichnis,
      Anzeige im Hauptmenue, Rang im Game-Over-Bild; siehe 4.5)
      _Spaeter ueberholt: die Datei hiess bis 0.50.0 `highscore` und
      heisst seit 0.51.0 `highscore-marathon` (siehe dort)._
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
- [x] Anzeige des Datums in der Highscore-Liste nachruesten (Version
      0.14.0: das gespeicherte Feld `date` wird als eigene Spalte
      angezeigt, Name in der Anzeige auf 14 Zeichen gekuerzt; die
      Statistik speichert und zeigt seither ebenfalls das Datum der
      letzten drei Spiele, siehe 4.5)
- [x] Highscore-Liste um Anzahl erzeugter Silber- und Gold-Bloecke
      erweitern (Version 0.15.0: zusaetzliche Felder im Zeilenformat,
      siehe 4.5; bei Eintraegen ohne diese Felder gilt als
      Standardwert 0. Gold/Silber werden als Spalten angezeigt, die
      Score-Spalte ist dafuer auf Nutzerwunsch aus der Anzeige
      entfernt - der Score bleibt gespeichert und bestimmt weiterhin
      die Rangfolge)
      _Spaeter ueberholt: das separate Score-Feld entfiel mit 0.16.0
      ganz; die Rangfolge macht seither die Reihenwertung "Rows"._
- [x] Punktesystem-Umbau (Version 0.16.0, Nutzerentscheidung):
      abgebaute Reihen sind die einzige Punktquelle, der Score ist
      identisch mit der gewichteten Reihenwertung "Rows" (1 je Reihe,
      +5 je Silber-, +10 je Gold-Streifen, +1 je Tetris, siehe 3.2).
      Entfallen sind Drop-Punkte, Quadrat-Bildungs-Boni (2000/1000)
      und die Level-Skalierung; Highscore (Rangfolge nach Rows) und
      Statistik speichern kein separates Score-Feld mehr (siehe 4.5)
- [x] Fehlinterpretierte Tastendruecke behoben (Version 0.16.1,
      Issue #7): zerrissen zugestellte Pfeiltasten-Sequenzen loesten
      ueber ihre Restbytes (`[`, `C` -> Taste `c`) ungewollte
      Hold-Wechsel aus; per Debug-Log nachgewiesen. `read_key` liest
      Escape-Sequenzen jetzt byteweise bis zum Endbyte mit
      grosszuegigerem Timeout und wertet auch ein im Timeout-Moment
      geliefertes Byte aus (siehe 4.3)
      _Spaeter ueberholt: der groessere Timeout war nur ein
      Zwischenschritt - 0.23.0 ersetzt ihn durch den Zustandsautomaten,
      der ueber Tick-Grenzen hinweg zusammensetzt._
- [x] Spielzeit-Counter fuer die aktuelle Runde einbauen (Version
      0.17.0: Anzeige im HUD als "Time" MM:SS, Zeitmessung analog zum
      Game-Loop ueber `${EPOCHREALTIME}`/`now_ms`; nur aktive Spielzeit
      zaehlt, Pausen und Game-Over-Bildschirm nicht; die Spielzeit wird
      zusaetzlich mit dem Highscore-Eintrag gespeichert, siehe 3.4/4.5)
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
      _Spaeter ueberholt: das Minimum ist seit 0.26.0 48x22, nicht mehr
      48x24 (siehe CLAUDE.md 3.4)._
- [x] README mit Screenshots/Asciinema aktualisieren (Abschnitt
      "Vorschau" im README; ohne eigenen Versionssprung, Stand 0.19.0):
      vier kurze, echte Spielsequenzen als
      asciinema-Aufnahmen (`.cast`) und GIF unter `docs/demo/` - Tetris
      (Vierfach-Abbau), Silber-Quadrat (vier gemischte Teile),
      Gold-Quadrat (vier gleiche Teile) und die Weltwunder-Baustelle.
      Die Clips sind mit festem `--seed` reproduzierbar aufgenommen
- [x] Blinkeffekt beim Reihenabbau (Version 0.20.0): abgebaute Reihen
      blinken kurz auf, bevor sie entfernt werden und das naechste Teil
      erscheint (`board_full_rows`, `flash_rows`, `FLASH_ROWS`/
      `FLASH_STATE`; Dauer ueber `FLASH_MS`/`FLASH_CYCLES`, siehe 3.1)
- [x] Konfigurierbare Farben (Version 0.21.0: benannte Farbschemata
      `guideline`/`classic`/`mono`/`colorblind`, Auswahl im
      Einstellungsmenue mit Live-Vorschau, `--color-theme` bzw.
      `ROWHAMMER_COLOR_THEME`, gespeichert als `COLOR_THEME` in der
      Config; symbolische Farbnamen mit Basic- und Extended-Bedeutung,
      siehe 4.1)
- [x] Performance-Optimierung des Renderings (Version 0.22.0): der
      Frame wird in `FRAME_LINES` gebaut, `render_flush` schreibt nur
      die geaenderten Zeilen mit eigener Cursor-Positionierung, und die
      liegenden Feldreihen liegen in einem Cache, der nur nach echten
      Brettaenderungen verfaellt (`render_board_dirty`). Ein bewegter
      Stein kostet damit hoechstens vier Reihen statt aller 200 Zellen;
      gemessen rund halbe Frame-Zeit und ein Vierzehntel der
      Terminal-Ausgabe (siehe 4.3)
- [x] Layout anpassen (Version 0.22.0): der feste 48x24-Block wird
      mittig im Terminal ausgerichtet (`layout_update`), Hold-Stein und
      Tastenlegende stehen links, das Spielfeld in der Mitte, die
      naechsten drei Steine oben rechts und die Rundenzaehler auf den
      zwei unteren Statuszeilen; Pause und Game Over erscheinen als
      Kasten ueber dem Spielfeld (siehe 3.4)
      _Spaeter ueberholt: 0.26.0 verlegt die Rundenzaehler in die linke
      Spalte, streicht Tastenlegende und Statuszeilen und macht aus dem
      Block 48x22._
- [x] "Wollen Sie wirklich beenden?"-Abfrage beim Schliessen des Spiels
      (Version 0.22.0): liegt beim Verlassen ueber "Beenden" oder `Esc`
      im Hauptmenue noch eine pausierte Runde im Zwischenspeicher, fragt
      `menu_confirm` (lib/menu.sh) vorher nach und zeigt deren Stand
      (Lines/Rows/Level); die ablehnende Antwort ist vorausgewaehlt und
      `Esc` gilt ebenfalls als Ablehnung. Erst nach Bestaetigung wird die
      Runde beendet und gewertet
- [x] Eingabeschicht gehaertet (Version 0.23.0, Nachfassen zu Issue #7,
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
- [x] "rowhammer"-Zaehler einbauen (Version 0.24.0): zaehlt, wie oft
      vier Reihen auf einmal abgebaut wurden (der Tetris, hier nach dem
      Projekt benannt). Hochgezaehlt wird er dort, wo `clear_lines`
      (`lib/board.sh`) den Fall ohnehin ueber `CLEARED -eq 4` erkennt
      und `ROWS_TETRIS` addiert; der Rundenzaehler `ROWHAMMER_COUNT`
      liegt bei `GOLD_COUNT`/`SILVER_COUNT` in `rowhammer.sh` und wird
      in `game_reset` zurueckgesetzt (Rundenzustand - kein
      `ROWHAMMER_*`-Einstellungsparameter, trotz des Namens).
      Aufnahme in die Statistik (Nutzerfrage, bejaht): neuer
      Gesamtzaehler `rowhammers` als weitere `key=value`-Zeile in
      `lib/stats.sh` (`STATS_LINE_RE` erweitert, `STATS_ROWHAMMERS`,
      fuenfter Parameter an `stats_add_round`, uebergeben in
      `record_round`) und eine eigene Zeile "Rowhammer (4 Reihen)" im
      "Statistik"-Bildschirm unter den Gold-/Silberbloecken.
      Mit 0.25.0 (Nutzerentscheidung) kam der Zaehler an die drei
      Stellen, die 0.24.0 noch offen gelassen hatte - jede davon
      bezahlt mit vorhandenem Platz, weil alle drei Layouts am
      48-Spalten-Minimum sitzen:
      - **HUD:** der Weltwunder-Fortschritt raeumt seinen Platz auf der
        zweiten Statuszeile (`render_status` in `lib/render.sh`, Feld
        unveraendert 17 Zeichen breit); das Wunder bleibt auf dem
        Weltwunder-Bildschirm. Der Wunder-Zustand wird dadurch nicht
        mehr je Reihenabbau nachgerechnet (`wonders_update` faellt in
        `lock_and_next` weg, siehe 3.3).
      - **`recent=`-Liste:** neues Feld vor dem Datum
        (`lines|bonus|gold|silver|rowhammers|date`, `STATS_RECENT_RE`
        auf vier Zahlenfelder erweitert), Anzeige als Spalte "RH" aus
        den letzten vier freien Spalten der Tabelle.
      - **Highscore:** neues Feld am Zeilenende
        (`...|time|rowhammers`, `HS_LINE_RE` um ein Zahlenfeld
        erweitert), Anzeige als Spalte "RH"; dafuer wurde der Name in
        der Anzeige von 8 auf 6 Zeichen gekuerzt und "Silber" zu
        "Silb".
      Alte Highscore- und `recent=`-Zeilen fallen gemaess der
      Arbeitsregel "keine Abwaertskompatibilitaet" bei der Validierung
      heraus.
      _Spaeter ueberholt: die Statuszeilen unter dem Feld gibt es seit
      0.26.0 nicht mehr - der Rundenzaehler steht seither als "Hammer"
      in der linken Spalte. Die `recent=`-Zeile und die Highscore-Zeile
      wuchsen mit 0.27.0 um Pieces und Zeit (siehe CLAUDE.md 4.5)._
- [x] Weltwunder-Fortschritt aus der Ingame-Statusanzeige entfernen:
      umgesetzt als Teil des Rowhammer-Zaehlers in Version 0.25.0 (siehe
      vorigen Punkt) - der freigewordene Platz auf der zweiten
      Statuszeile ist genau der Grund, warum der Zaehler dort Platz
      fand.
- [x] HUD-Zaehler in die linke Spalte verlegen (Version 0.26.0,
      Nutzerentscheidung): die Rundenzaehler stehen jetzt untereinander
      unter dem Hold-Stein (`pane_stat`/`render_pane_left` in
      `lib/render.sh`, Label 6 Zeichen + Wert 5 Zeichen), die
      Tastenlegende ist ersatzlos entfallen (`hud_keys_build` samt
      seinen Aufrufen in `rowhammer.sh` und `prompt_rebind`), ebenso
      der Spielername (12 Spalten sind fuer bis zu 16 Namenszeichen zu
      schmal; er bleibt in der Highscore-Liste). Damit fallen die zwei
      Statuszeilen unter dem Feld weg (`render_status`, `STATUS_ROW_*`):
      der Block ist nur noch 22 Zeilen hoch (`LAYOUT_H`), und das
      Terminal-Minimum sinkt entsprechend auf 48x22 (`MIN_TERM_ROWS`;
      der hoechste Menuebildschirm, die Weltwunder-Baustelle, braucht
      20 Zeilen) (siehe 3.4)
- [x] Zaehler der abgelegten Teile einbauen (Version 0.27.0,
      Nutzerentscheidung): Rundenzaehler `PIECE_COUNT` in
      `rowhammer.sh`, hochgezaehlt in `lock_and_next` - der einzigen
      Stelle, an der ein Stein wirklich festgesetzt wird - und in
      `game_reset` zurueckgesetzt. Anzeige im HUD als "Pieces" in der
      linken Spalte unter der Spielzeit (Zeile 13, siehe 3.4); in
      Statistik und Highscore zusammen mit der Spielzeit als PCS und
      PCS/Minute (`fmt_ppm` rechnet in Zehnteln, weil Bash keine
      Fliesskommazahlen kennt). Dateiformate wachsen entsprechend
      (siehe 4.5): Highscore-Zeile um ein abschliessendes `pieces`,
      `recent=`-Zeile um `pieces` und `time` vor dem Datum, Statistik
      um die Gesamtzaehler `pieces` und `play_time`; alte Zeilen fallen
      gemaess der Arbeitsregel "keine Abwaertskompatibilitaet" bei der
      Validierung heraus. Beide Tabellen waren am 48-Spalten-Minimum
      randvoll, deshalb (Nutzerentscheidung: die Anzeige darf
      mehrzeilig werden) je Eintrag zwei Zeilen - und weil das die
      17 Zeilen eines 22-Zeilen-Terminals sprengt, zeigt `menu_pages`
      (`lib/menu.sh`) die Highscore-Liste seitenweise und die
      Statistik auf zwei Bildschirmen.
      _Nachtrag: fuer die Highscore-Liste lockert 0.29.0 die
      Feldzahl-Pruefung wieder - dort steht, warum._
- [x] Steine im farblosen Modus unterscheidbar machen (Version 0.28.0):
      `--no-color` zeichnete zuvor jede Sorte als `[]`, sodass abgelegte
      Steine ununterscheidbar wurden und Gold-/Silber-Quadrate nicht
      planbar waren. Jede Sorte hat jetzt ein eigenes Zwei-Zeichen-Glyph
      (`PIECE_GLYPH`), Gold-/Silber-Quadrate eigene Nicht-Buchstaben-
      Glyphen (`##`/`%%`, siehe 4.1)
- [x] Standard-`NO_COLOR`-Umgebungsvariable beachten (Version 0.28.0):
      neben `--no-color`/`ROWHAMMER_NO_COLOR` schaltet auch das
      De-facto-Standardsignal `NO_COLOR` (https://no-color.org/) die
      Farben ab, wenn es gesetzt und nicht leer ist; Praezedenz
      Standard-`NO_COLOR` < `ROWHAMMER_NO_COLOR` < `--no-color`
      (siehe 4.2)
- [x] Hauptmenue ebenfalls zentriert darstellen (Version 0.28.0): das
      Spielfeld-Layout wird seit 0.22.0 per `layout_update` mittig im
      Terminal ausgerichtet (siehe 3.4, 4.3), das Hauptmenue
      (`lib/menu.sh`) blieb aber oben links. Umgesetzt ueber
      `render_menu_frame` (`lib/render.sh`): jeder Menue-, Info- und
      Eingabebildschirm wird jetzt als Liste reiner Inhaltszeilen
      gebaut und von dieser einen Funktion platziert - linke Kante wie
      der Spielblock (Zentrierung von `LAYOUT_W`), vertikal nach der
      eigenen Hoehe zentriert. Betroffen sind alle Bildschirme aus
      `lib/menu.sh` (`menu_run`, `menu_message`/`menu_pages`,
      `menu_confirm`, `menu_colors`, `prompt_rebind`,
      `prompt_player_name`) und der Weltwunder-Bildschirm
      (`wonder_screen` in `lib/wonders.sh`), damit nicht ausgerechnet
      der Bildschirm nach jeder Runde aus der Reihe faellt (siehe 4.3).
- [x] Tastendruck-Artefakte auf dem Bildschirm behoben (Version 0.28.1,
      Issue #33): Neben dem Spielfeld standen echote Tastenbytes
      (`^[[C`, einzelne Buchstaben), die auf dem Pause- und
      Game-Over-Bildschirm dauerhaft blieben. Ursache war der fehlende
      Terminal-Modus: das Spiel verliess sich auf den Modus, den
      `read -rsn1` je Read kurz setzt, sodass zwischen zwei Reads Echo
      und kanonischer Modus aktiv waren - und seit dem inkrementellen
      Rendering (0.22.0) uebermalt kein Voll-Frame das Echo mehr.
      `term_setup` schaltet den Rohmodus jetzt einmal fuer die ganze
      Sitzung (`term_input_raw`), die Namensabfrage holt sich fuer ihren
      `read` per `term_input_line` kurz das Zeilen-Echo zurueck (siehe
      4.3)
      _Spaeter ueberholt: diese eine Ausnahme entfiel mit 0.45.0 - die
      Namensabfragen zeichnen ihre Zeile selbst und lesen sie im
      Textmodus der Eingabeschicht, `term_input_line` gibt es nicht
      mehr._
- [x] Highscore-Eintraege ueberleben fehlende Zaehlerfelder (Version
      0.29.0, Nutzerentscheidung): `highscore_load` verlangte bislang
      alle zehn Felder und verwarf jede kuerzere Zeile ganz - jede
      Formaterweiterung (Gold/Silber in 0.4.0, Zeit in 0.5.0,
      Rowhammer in 0.6.0, Pieces in 0.7.0, jeweils Versionsstand von
      `lib/highscore.sh`) liess dadurch bestehende Eintraege beim
      naechsten Laden-und-wieder-Speichern still verschwinden. Akzeptiert
      werden jetzt 5, 7, 8, 9 oder 10 Felder (`HS_FIELD_COUNTS`,
      `highscore_parse_line`), fehlende Zaehler werden als `0` ergaenzt.
      Zeilen von vor dem Punktesystem-Umbau (fuehrendes `score`-Feld,
      Rows an dritter statt erster Stelle) bleiben aussen vor, da deren
      andere Spaltenreihenfolge sonst den alten Score als Rows
      einordnen wuerde (siehe 4.5).
- [x] Highscores und Statistik farbig darstellen (Version 0.30.0):
      beide Bildschirme waren reiner Text, obwohl das Spiel laengst ein
      Theme-System fuer Farben hat (0.21.0, siehe 4.1). `render_colors_init`
      (`lib/render.sh`) leitet jetzt zusaetzlich reine Text-SGR-Farben aus
      dem aktiven Theme ab (`TXT_GOLD_SGR`, `TXT_SILVER_SGR`,
      `TXT_ACCENT_SGR`, `TXT_WARN_SGR`, `TXT_BOLD_SGR`, `TXT_RESET_SGR`);
      `highscore_screen` und `stats_screen` faerben damit Rang 1/2
      (Gold-/Silber-Medaille), die Rows-/Gesamtsumme-Spalte sowie die
      Gold-/Silber-/Rowhammer-Werte. Die Warnfarbe greift bewusst auf die
      Z-Stein-Farbe des Themas zurueck statt auf ein festes Rot, damit
      `colorblind` (das Rot/Gruen meidet) konsistent bleibt. In
      `--no-color`/`NO_COLOR` bleiben alle `TXT_*`-Variablen leer, die
      Anzeige bleibt dann byteidentisch zur bisherigen Fassung; eine
      Zeile, die trotz der 46-Zeichen-Grenze zu lang wuerde, faellt auf
      unkolorierten, abgeschnittenen Text zurueck statt eine
      Escape-Sequenz zu zerschneiden (siehe 4.5).
- [x] Standard-Tastenbelegung erneut geaendert (siehe 3.1, Version
      0.31.0, Nutzerentscheidung): Rotation liegt jetzt auf `a` (gegen
      den Uhrzeigersinn) und `d` (im Uhrzeigersinn), die feste
      Hold-Sekundaertaste ist `w` statt `2`. Links/Rechts und der
      Hard-Drop geben ihre Buchstabentasten dafuer ab und laufen ueber
      ihre festen Sekundaertasten (Pfeile bzw. Leertaste/Pfeil hoch);
      neu ist der Bindungswert `NONE` fuer "keine Buchstabentaste"
      (Standard fuer `KEY_LEFT`/`KEY_RIGHT`, von der Dubletten-Pruefung
      ausgenommen).
- [x] Anleitung im Hauptmenue (Version 0.32.0, Nutzerwunsch): neuer
      Menuepunkt "Anleitung" zwischen "Einstellungen" und "Beenden",
      der das Spiel auf fuenf Info-Bildschirmen erklaert - Spielprinzip,
      Steuerung, Vorschau/Hold, Gold-/Silber-Quadrate mit ihrer
      Reihenwertung und zum Schluss den Weltwunderbau (`menu_help`,
      `menu_help_keys` in `lib/menu.sh`, siehe 3.5). Tastenbelegung und
      Wunder-Kosten stammen aus dem laufenden Zustand, damit ein Rebind
      oder ein justiertes `WONDER_COSTS` die Anleitung nicht veralten
      laesst.
      _Spaeter ueberholt: seit 0.39.0 sind es sechs Bildschirme - die
      Spielmodi kamen als eigene Seite dazu -, seit 0.42.0 sieben mit
      der Seite ueber die Bestenlisten._
- [x] Anleitung mit den Pfeiltasten blaetterbar machen (Version 0.33.0,
      Nutzerwunsch, siehe 3.5): zuvor fuehrte jede beliebige Taste zur
      naechsten der fuenf Seiten, ohne Weg zurueck (eine feste Folge von
      `menu_message`-Aufrufen). `menu_help` (`lib/menu.sh`) ist jetzt
      eine eigene Warteschleife: Pfeil links/rechts blaettert umlaufend
      zwischen den Seiten, Enter/Leertaste/`x`/`ESC` schliessen die
      Anleitung. Der Seiteninhalt kommt aus `menu_help_body`, einem
      `case`-Switch je Seitenindex, damit jede Seite direkt angesprungen
      werden kann statt nur der Reihe nach.
      _Spaeter ueberholt: seit 0.39.0 blaettert die Schleife durch sechs
      statt fuenf Seiten, seit 0.42.0 durch sieben._
- [x] **Ultra-Modus** einbauen (Version 0.34.0, Nutzerwunsch): im Menue
      "Einzelspieler" steht neben "Normales Spiel" jetzt "Ultra" -
      `ULTRA_TARGET_ROWS` (150) Rows so schnell wie moeglich abbauen,
      die Runde endet im Zielmoment und die Spielzeit ist das Ergebnis
      (`GAME_MODE`, `GOAL_REACHED`, Zielpruefung in `lock_and_next`,
      siehe 3.6). Die drei offen gelassenen Punkte sind dort
      entschieden: gemessen werden **Rows** (nicht Lines), ein vor dem
      Ziel abgebrochener Versuch kommt **nicht** in die Bestenliste
      (seine Reihen zaehlen aber wie bei jeder abgebrochenen Runde in
      Weltwunder und Statistik), und der HUD zeigt den Fortschritt in
      zwei der acht freien Zeilen der linken Spalte ("Goal"/"Left", nur
      im Ultra-Modus). Speicherung in einer eigenen Liste
      `${DATA_DIR}/highscore-ultra` mit eigener Rangordnung (kuerzeste
      Zeit zuerst, Zeit in Millisekunden), damit ein zeitlich
      begrenzter Lauf die Top 10 der endlosen Liste nicht verdraengt
      (`HSU_*` in `lib/highscore.sh`, siehe 4.5).
      _Spaeter ueberholt: "Normales Spiel" heisst seit 0.34.1
      "Marathon"; die Ultra-Bestenliste ist seit 0.38.0 auch anzeigbar.
      Seit 0.39.0 steht mit "Sprint" ein dritter Modus daneben, der die
      HUD-Zeilen 15/16 mitbenutzt._
- [x] **Endlosen Modus in "Marathon" umbenannt** (Version 0.34.1,
      Nutzerentscheidung): der bisherige Menuepunkt "Normales Spiel"
      heisst jetzt "Marathon" (`lib/menu.sh`), der interne Modusname
      `GAME_MODE` wechselt entsprechend von `normal` zu `marathon`
      (Standardwert und `game_run`-Argument in `rowhammer.sh`, siehe
      3.6). Reine Umbenennung ohne Verhaltensaenderung: `GAME_MODE`
      wird nicht persistiert (siehe 4.5), betrifft also weder Savegame
      noch Highscore-Dateien; einzig `events.log` des Debug-Modus
      protokolliert den neuen Namen.
- [x] `--reset config|stats|highscore|save|all` eingebaut (Version
      0.35.0, siehe 4.8): setzt gezielt persistente Daten im
      Datenverzeichnis (`${DATA_DIR}`, siehe 4.5) zurueck und beendet
      sich mit einer Bilanz auf STDOUT, statt ins Menue zu starten. Am
      Terminal
      werden die betroffenen Pfade vorher aufgelistet und bestaetigt
      ("nein" ist wie bei `menu_confirm` die Vorgabe), ohne TTY laeuft
      der Reset direkt durch, damit ein wartendes `read` kein Skript
      haengen laesst; nicht vorhandene Dateien sind kein Fehler.
      Nachgezogen in 0.36.0 (Nutzerentscheidung): der Reset **loescht
      nicht mehr**, sondern verschiebt jede Datei nach
      `<datei>-YYYYMMDDhhmmss.bak` (bei einem Backup derselben Sekunde
      `sleep 1` und neuer Zeitstempel statt Ueberschreiben), und der
      neue Schalter `--force`
      (`ROWHAMMER_FORCE`) beantwortet sie automatisch mit "ja" - frei
      mit anderen Optionen kombinierbar und ueberall wirkungslos, wo
      nichts gefragt wird.
      Zusaetzlich per `ROWHAMMER_RESET` setzbar, Praezedenz Standard <
      Env < CLI: bewusst **ohne** die Config-Stufe, weil die
      Config-Datei selbst ein Reset-Ziel ist (sie koennte sich sonst bei
      jedem Start selbst loeschen lassen). Die beiden offen gelassenen
      Fragen sind in 4.8 entschieden - `all` nimmt das Savegame mit
      (das eigene Ziel `save` deckt den Fall "nur der
      Weltwunder-Fortschritt" ab), `highscore` trifft beide
      Bestenlisten (seit 0.39.0 alle drei - die Sprint-Liste kam dazu). Umsetzung: `reset_run` in `rowhammer.sh`, direkt
      nach dem Sourcen der Module (fuer deren Dateinamen-Konstanten) und
      vor der dorthin verschobenen TTY-Pruefung. In 0.36.1
      (Nutzerentscheidung) wurde der Dialog auf Deutsch umgestellt:
      `Bist du sicher, dass du <ziel> zuruecksetzen moechtest? [N/y]`
      und nach dem Verschieben `Reset erfolgreich` (ASCII wie die
      Menues, siehe 4.8).
- [x] **Ultra-Bestenliste anzeigen** (Version 0.38.0, Nutzerwunsch):
      0.34.0 hatte die Liste bewusst nur gespeichert - der Bildschirm
      fehlte, und der erreichte Rang stand allein im Rundenende-Kasten.
      `highscore_ultra_screen` (`lib/highscore.sh`) zeigt sie jetzt im
      Layout der Marathon-Liste (zwei Zeilen je Eintrag, seitenweise
      ueber `menu_pages`, dieselben Spaltenbreiten und Farbregeln), nur
      nach Zeit sortiert und mit der Zeit-Spalte in der Akzentfarbe -
      sie ist hier der Score, wo es in der Marathon-Liste die Rows sind
      (`fmt_duration_ms`, MM:SS.mmm; PPM aus den auf Sekunden
      heruntergerechneten Millisekunden). Weil damit zwei Listen mit
      zwei Rangordnungen nebeneinander stehen, fragt der Menuepunkt
      "Highscores" ueber `menu_highscores` (`lib/menu.sh`) zuerst den
      Modus ab (Marathon / Ultra / Zurueck) und behaelt die Auswahl,
      bis "Zurueck" oder `ESC` kommt; die Bildschirmtitel nennen ihren
      Modus. Umgesetzt wurde die in der Roadmap vorgeschlagene
      Modus-Auswahl und nicht die Alternative "Seitenlogik aus
      `menu_pages` je Modus": eine durchgeblaetterte Doppelliste haette
      die zweite Rangordnung hinter den Seiten der ersten versteckt
      (siehe 4.5).
- [x] **Sprint-Modus** (Version 0.39.0, Nutzerwunsch): der dritte
      Spielmodus und das Spiegelbild von Ultra - in `SPRINT_TIME_MS`
      (180000 ms = 3 Minuten) Spielzeit moeglichst viele Rows abbauen,
      die Runde endet mit Ablauf der Zeit und die Rows sind das Ergebnis
      (`GAME_MODE=sprint`, `sprint_time_up` in `rowhammer.sh`, siehe
      3.6). Weil der Modus die Umkehrung von Ultra ist, sind dessen
      Entscheidungen eins zu eins gespiegelt: gewertet werden **Rows**
      (nicht Lines), ein vorzeitig im Game Over gescheiterter Versuch
      kommt **nicht** in die Bestenliste (seine Reihen zaehlen wie bei
      jeder abgebrochenen Runde in Weltwunder und Statistik), und der
      HUD zeigt Ziel und Rest in denselben zwei Zeilen der linken Spalte
      wie Ultra ("Goal" = das Zeitlimit, "Left" = die auf die naechste
      ganze Sekunde aufgerundete Restzeit; die Modi laufen nie
      gleichzeitig). Die Zielpruefung sitzt im Game-Loop direkt hinter
      `play_clock_tick` und **vor** der Gravitation des Ticks: die Uhr
      ist hier das Ziel, so wie die Reihenwertung es bei Ultra ist, und
      auf abgelaufener Zeit soll kein Stein mehr fallen oder festgesetzt
      werden. Der Rundenende-Kasten (`render_status_box`) bekam zwei
      weitere Ausgaenge - "SPRINT END" mit Rows und Sprint-Rang sowie
      das Game Over des gescheiterten Versuchs mit der gespielten Zeit
      ("Time 01:23/03:00") -, alle fuenf mit denselben acht Innenzeilen,
      damit die Rahmen stehen bleiben.
      Speicherung in einer eigenen Liste `${DATA_DIR}/highscore-sprint`
      (`HSS_*` in `lib/highscore.sh`, siehe 4.5): Zeilenformat und
      Rangordnung wie die Marathon-Liste (dieselbe Zahl in derselben
      Einheit - ein zweites Layout waere nur ein zweites zu pflegendes),
      aber eine eigene Datei, weil ein auf drei Minuten begrenzter Lauf
      und eine erst beim Game Over endende Runde nicht dasselbe messen.
      `highscore_sprint_screen` zeigt sie im Layout der beiden anderen
      Listen; einzige Abweichung ist die Spalte an der Stelle der
      Spielzeit, die hier die physischen Reihen ("Lines") traegt - jeder
      Eintrag hat dieselben drei Minuten gespielt, eine Zeitspalte
      stuende zehnmal gleich da. Der Menuepunkt "Highscores"
      (`menu_highscores`) und `--reset highscore` (siehe 4.8) decken die
      dritte Liste mit ab.
- [x] **Anleitungsseite "Spielmodi"** (Version 0.39.0, zusammen mit dem
      Sprint-Modus): die Anleitung (0.32.0) stammte aus der Zeit, als es
      nur die endlose Runde gab, und kannte die Spielmodi nicht. Die
      sechste Seite (`menu_help_body` in `lib/menu.sh`, siehe 3.5)
      erklaert Marathon, Ultra und Sprint mit ihrem jeweiligen Ende und
      Ergebnis und weist auf die eigene Bestenliste je Modus hin.
      _Spaeter ueberholt: seit 0.42.0 nennt die Seite auch Time Attack,
      und der Hinweis auf die Bestenlisten steht auf einer eigenen
      siebten Seite._ Sie
      kam bewusst erst jetzt: mit Sprint liessen sich alle drei Modi in
      einem Zug erklaeren, statt die Seite zweimal umzubauen. Ziel und
      Zeitlimit liest die Seite aus `ULTRA_TARGET_ROWS` bzw.
      `SPRINT_TIME_MS`, aus demselben Grund, aus dem die Wunder-Seite
      ihre Kosten aus `lib/wonders.sh` liest.
- [x] **Umschaltbar zwischen Voll-Frame- und Partial-Rendering**
      (Version 0.41.0): `--render-mode partial|full`
      (`ROWHAMMER_RENDER_MODE`, Standard `partial`) waehlt, wie der
      Spielbildschirm ans Terminal geht - der Zeilen-Diff aus 0.22.0
      oder der Voll-Aufbau, den der Renderer davor hatte (siehe 4.3).
      `partial` bleibt der Standard, weil es die ressourcenschonende
      Variante ist (rund die Haelfte der Zeit je Frame und etwa ein
      Vierzehntel der Terminal-Ausgabe); `full` ist der
      Kompatibilitaets-Rueckfall fuer Terminals und Multiplexer, bei
      denen sich das inkrementelle Update falsch darstellt, und der
      Debugging-Fall, in dem das Frame-Log ganze Frames statt einzelner
      geaenderter Zeilen zeigen soll. Der Schalter folgt wie in der
      Roadmap vorgesehen dem Muster von `--color-mode` und ist damit
      **kein Config-Wert** (Praezedenz Standard < Env < CLI): er ist
      eine Eigenschaft des benutzten Terminals, keine Geschmacksfrage,
      und muss ohne das Bearbeiten einer Datei erreichbar bleiben, wenn
      gerade die Bildausgabe das Defekte ist.
      Zwei Punkte weichen von der Skizze in der Roadmap ab, beide aus
      der Umsetzung heraus:
      1. Die Roadmap schlug vor, im Full-Modus einfach `RENDER_FULL`
         dauerhaft auf 1 zu halten. Dieses Flag loescht aber zusaetzlich
         den Bildschirm (`\e[2J`), was pro Frame ein Loeschen bedeutet
         haette - der Rueckfallmodus haette also geflackert, das
         Gegenteil dessen, wozu er da ist. Stattdessen entscheidet in
         `render_flush` eine eigene lokale Variable (`write_all`)
         darueber, ob alle Zeilen geschrieben werden, waehrend das
         Loeschen weiterhin allein an `RENDER_FULL` haengt (Menue,
         Resize, Rundenstart).
      2. `lib/render.sh` bekam bewusst **keinen** eigenen Vorgabewert
         fuer `RENDER_MODE`. Die Module werden erst nach dem Parsen der
         Argumente gesourct; eine Zuweisung im Modul ueberschrieb den
         gerade gesetzten CLI-Wert (im ersten Anlauf genau so
         passiert). Die Variable gehoert damit wie `COLOR_MODE` zu
         `rowhammer.sh`, das Modul liest sie nur.
      Der Sitzungskopf des Debug-Modus nennt den Modus jetzt mit
      (`# render:` in `events.log`, siehe 4.6) - ohne ihn ist nicht zu
      entscheiden, ob ein Eintrag im Frame-Log einen ganzen Frame oder
      nur dessen geaenderte Zeilen enthaelt.
- [x] **Time-Attack-Modus** (Version 0.42.0, Nutzerwunsch): der vierte
      Spielmodus und der erste, dessen Uhr vom Spiel selbst gefuettert
      wird - die Runde startet mit `TIME_ATTACK_START_MS` (60000 ms =
      1 Minute) rueckwaerts laufender Restzeit, und jede gewertete Row
      schreibt `TIME_ATTACK_ROW_MS` (1000 ms) gut; sie endet bei 00:00
      oder vorher im Game Over, das Ergebnis sind die Rows
      (`GAME_MODE=timeattack`, `time_attack_budget` und
      `time_attack_time_up` in `rowhammer.sh`, siehe 3.6). Das
      Zeitguthaben ist bewusst kein eigener Zaehler, sondern wird aus
      `ROW_CREDIT` abgeleitet: die Reihenwertung ist ohnehin die eine
      Zahl, um die sich der Modus dreht, und ein zweiter, bei jedem
      Abbau fortgeschriebener Zaehler koennte von ihr nur abweichen.
      Die Zielpruefung sitzt an derselben Stelle im Game-Loop wie die
      von Sprint (hinter `play_clock_tick`, vor der Gravitation), aus
      demselben Grund: auf abgelaufener Zeit soll kein Stein mehr
      fallen oder festgesetzt werden.
      **Die Nutzerfrage "was ist hier der Highscore?" ist mit den Rows
      beantwortet.** Die zweite denkbare Wertung, die ueberlebte Zeit,
      ist keine Alternative, sondern dieselbe Rangfolge: ein an der Uhr
      endender Lauf spielt exakt Startzeit + Rows x Gutschrift, seine
      Zeit ist also eine Funktion seiner Rows. Den Ausschlag gaben die
      Rows, weil sie im ganzen Spiel die Punktwaehrung sind (siehe 3.2)
      und auch fuer den vorzeitig gescheiterten Lauf aussagekraeftig
      bleiben, wo die Gleichung nicht mehr gilt; die Zeit steht in der
      Liste daneben, weil genau sie einen solchen Lauf ausweist.
      Bewusste Abweichung von Ultra und Sprint: **jeder** Lauf kommt in
      die Bestenliste. Die beiden anderen Zeitmodi kennen einen
      Zustand "abgebrochen", der sich mit einem vollen Lauf nicht
      vergleichen laesst; Time Attack kennt ihn nicht - die Rows sind
      so oder so dieselbe Leistung, wer vorzeitig oben rausbaut hat
      schlicht weniger davon, und damit liegt der Modus beim Marathon,
      dessen Runden ebenfalls im Game Over enden und trotzdem gewertet
      werden.
      Speicherung in einer eigenen vierten Liste
      `${DATA_DIR}/highscore-timeattack` (`HSA_*` in
      `lib/highscore.sh`, siehe 4.5): Zeilenformat und Rangordnung wie
      die Marathon-Liste, aber eine eigene Datei, weil ein Lauf auf
      einer selbst erspielten Minute nicht die Leistung einer endlosen
      Runde ist. `highscore_timeattack_screen` zeigt sie im Layout der
      drei anderen Listen, mit der Spielzeit-Spalte der Marathon-Liste
      statt der Lines-Spalte des Sprint-Bildschirms - hier ist die Zeit
      nicht bei jedem Eintrag dieselbe, sondern das Erkennungsmerkmal
      des vorzeitig beendeten Laufs. Der Menuepunkt "Highscores"
      (`menu_highscores`) und `--reset highscore` (siehe 4.8) decken
      die vierte Liste mit ab.
      Der Rundenende-Kasten (`render_status_box`) bekam zwei weitere
      Ausgaenge - "TIME UP" und das Game Over, beide mit Rows und
      Time-Attack-Rang -, womit er sieben traegt; anders als bei Ultra
      und Sprint traegt auch der Game-Over-Ausgang einen Rang, weil
      beide Laeufe gewertet werden. Der HUD nutzt die beiden Zeilen von
      Ultra und Sprint (Zeile 15/16 der linken Spalte) fuer die
      mitwachsende Gesamtzeit ("Goal") und die Restzeit ("Left"); der
      Wert wird in `render_pane_left` neu berechnet statt aus dem
      Game-Loop uebernommen, weil ein Abbau nach dessen Aktualisierung
      passiert und ausgerechnet der Frame, in dem der Spieler die
      Gutschrift sehen will, sonst den alten Stand zeigte. Die
      Anleitung erklaert den Modus auf der Seite "Spielmodi" (jetzt
      Seite 6 von 7); deren Schlussabsatz ueber die Bestenlisten ist
      dabei auf eine eigene siebte Seite gewandert, weil der vierte
      Modus die Seite bis auf die letzte Zeile fuellte (siehe 3.5).
- [x] **Statistik je Modus** (Version 0.42.0, zusammen mit dem
      Time-Attack-Modus; der letzte offene Teil des Modus-Themas):
      `lib/stats.sh` zaehlt die verbuchten Runden je Modus
      (`rounds_marathon`, `rounds_ultra`, `rounds_sprint`,
      `rounds_timeattack`) und fuer die drei Zeitmodi zusaetzlich, wie
      viele davon im regulaeren Ende des Modus ausgingen statt im Game
      Over (`rounds_*_goal`: Ziel erreicht / volle Zeit gespielt / Uhr
      abgelaufen). `record_round` reicht dafuer `GAME_MODE` und
      `GOAL_REACHED` an `stats_add_round` durch - die beiden einzigen
      Rundenangaben, die sich aus den vorhandenen Zaehlern nicht
      rekonstruieren lassen; die Erfolgsquote der Zeitmodi steht
      nirgends sonst, weil ein gescheiterter Lauf in seiner
      Bestenliste fehlt.
      Der Punkt kam bewusst erst jetzt: die Roadmap hielt fest, dass
      Zaehler ohne Anzeige tote Daten waeren und die Statistik-
      Bildschirme schon zweiseitig sind. Mit Time Attack war ein
      vierter Modus da, dessen Erfolgsquote ohne diese Zaehler gar
      nicht sichtbar waere - und die noetige **dritte Seite**
      ("Statistik (3/3)") ist der Anlass, sie fuer alle Modi
      einzufuehren. Ein Umbau der ersten Seite war keine Alternative:
      sie ist mit zehn Zeilen Zaehlern voll, und die sieben neuen
      Zaehler samt Ueberschriften passen nicht in die 18 Zeilen, die
      `MENU_BODY_MAX` laesst.
      Gezaehlt wird hinter derselben Null-Pruefung wie alles andere
      (eine Runde ohne einen einzigen abgelegten Stein ist keine
      gespielte Runde), und ein unbekannter Modusname wird nirgends
      gezaehlt statt Marathon zugeschlagen - lieber eine Luecke als
      eine falsche Zuordnung.
      _Spaeter ueberholt: 0.47.0 fuehrt **jeden** Zaehler je Modus und
      loest die `rounds_*`-Schluessel durch das Schema
      `mode_<modus>_<feld>` ab (siehe dort und 4.5)._
- [x] **"Neustarten" im Pausenmenue** (Version 0.43.0, Nutzerwunsch):
      Das Pausenmenue (`Esc`/`x`) hatte drei Eintraege, von denen zwei
      die Runde verlassen; wer eine verkorkste Runde einfach noch
      einmal spielen wollte, musste sie beenden, den
      Weltwunder-Bildschirm wegdruecken und den Modus im
      Einzelspieler-Menue erneut waehlen. Der neue Eintrag macht daraus
      zwei Tastendruecke: er gibt die laufende Runde auf und startet
      sofort eine frische im selben Modus (`menu_pause` setzt
      `GAME_RESTART`, `handle_key` fuehrt es aus - erst `record_round`,
      dann `game_reset` ohne Argument, siehe 3.1).
      Drei Entscheidungen dahinter:
      - **Erst verbuchen, dann zuruecksetzen.** Eine aufgegebene Runde
        zaehlt wie jede abgebrochene fuer Weltwunder-Fortschritt und
        Statistik (3.3), und `game_reset` loescht genau die Zaehler,
        die `record_round` liest. Es ist dieselbe Reihenfolge, mit der
        `game_run` eine noch pausierte Runde verbucht, bevor eine neue
        startet. Die Taste `r` im Game-Over-Bild kommt ohne den Aufruf
        aus, weil die Runde dort beim Game Over schon verbucht wurde -
        `record_round` waere ueber `ROUND_RECORDED` ohnehin ein No-Op.
      - **Ein Flag statt eines `game_reset` im Menue.** `lib/menu.sh`
        entscheidet, `rowhammer.sh` handelt - wie schon bei `GAME_EXIT`
        und `GAME_SUSPENDED`. Das Menue kennt die Rundenzaehler nicht
        und soll die Reihenfolge oben nicht kennen muessen.
      - **Der Eintrag steht direkt unter "Fortsetzen"**, weil er der
        andere Weg ist weiterzuspielen; die beiden Eintraege, die die
        Runde verlassen, bleiben unten, wo sie im bisherigen
        Dreier-Menue standen.
      - **Sicherheitsabfrage fuer beide Eintraege, die die Runde
        wegwerfen** (Nutzerwunsch, in zwei Schritten gewachsen): Der
        erste Anlauf hatte ganz auf sie verzichtet, weil "Runde
        beenden" die Runde ebenso ohne Rueckfrage verwarf. Auf
        Nutzerwunsch bekam zuerst "Neustarten" eine Abfrage - es ist
        der einzige Ausgang, der die Runde wegwirft, ohne das Spiel zu
        verlassen: der Bildschirm zeigt danach eine leere Wanne und den
        naechsten Stein, ein Fehlgriff waere also verschwunden, bevor
        er auffaellt. Auf den zweiten Nutzerwunsch hin fragt jetzt auch
        "Runde beenden" zurueck; das ist die konsequentere Loesung,
        denn der Eintrag sitzt direkt unter dem, der die Runde nur
        pausiert - eine Zeile daneben und die Runde ist vorbei, statt
        im Hauptmenue zu warten. "Fortsetzen" und "Ins Hauptmenue"
        fragen weiterhin nicht: keiner von beiden verliert etwas.
        Beide Abfragen nutzen `menu_confirm`
        (vorausgewaehltes "Nein", `ESC` lehnt ab) und zeigen den Stand
        der Runde - Lines, Rows und Level sind das, woran eine Runde
        haengt, und genau die deckt der Kasten gerade zu. Ein "Nein"
        fuehrt zurueck ins Pausenmenue statt in die Runde, weil ein
        Spieler, der den Eintrag nicht wollte, meist trotzdem etwas
        aus diesem Menue wollte; `menu_pause` ist dafuer von einem
        einmaligen `menu_run` zu einer Schleife geworden.
      Der Wunder-Bildschirm erscheint beim Neustart bewusst nicht: er
      gehoert ans Ende einer Spielsitzung (`menu_singleplayer` zeigt
      ihn, wenn `game_run` zurueckkehrt), nicht zwischen zwei Runden.
      Verbucht ist der Fortschritt trotzdem.
      Die Anleitungsseite "Steuerung" nennt jetzt beide Wege zum
      Neustart in einer Zeile ("Neustart: [r] im Game Over oder
      Pausenmenue") statt nur `r`: die Seite sitzt mit 18 Zeilen genau
      auf `MENU_BODY_MAX` und vertraegt keine zusaetzliche.
      Mitgenommen: der Controls-Block von `--help` fuehrte noch die
      Belegung vor 0.31.0 (`e`/`q` drehen, `w` Hard-Drop, `2` Hold) und
      damit fuer drei Aktionen die falschen Tasten; er nennt jetzt die
      tatsaechlichen Vorgaben (Pfeiltasten bewegen, `d`/`a` drehen,
      Leertaste bzw. Pfeil hoch setzt fest, `c`/`w` holdet) samt der
      Unterscheidung zwischen der konfigurierbaren Buchstabentaste und
      den fest verdrahteten Sekundaertasten. Dieselbe veraltete Angabe
      stand im Kopfkommentar von `handle_key` ("2 for hold").
- [x] **Namensabfrage am Rundenende** (Version 0.45.0, Nutzerwunsch):
      Am Ende einer Runde fragt das Spiel nach dem Namen, unter dem sie
      in ihre Bestenliste kommt; die Vorgabe ist der Spielername aus den
      Einstellungen und steht **vormarkiert** in der Eingabezeile, sodass
      ein einziges getipptes Zeichen sie ersetzt (aktueller Stand:
      CLAUDE.md 3.7). Bis dahin trug jeder Eintrag den Namen aus den
      Einstellungen, und wer ihn fuer eine Runde aendern wollte, musste
      vorher ins Einstellungsmenue.
      Fuenf Entscheidungen dahinter:
      - **Die Abfrage sitzt in `record_round`.** Das ist der eine
        Trichter, durch den jedes echte Rundenende laeuft (Game Over,
        "Runde beenden", "Neustarten", Programmende mit wartender
        Runde) und der ueber `ROUND_RECORDED` genau einmal je Runde
        ausgefuehrt wird - eine Abfrage an jedem einzelnen dieser Wege
        haette dieselbe Logik viermal gebraucht. Sie laeuft **vor** dem
        Listeneintrag, denn dort geht der Name hinein und dort entsteht
        der Rang, den der Rundenende-Kasten anschliessend zeigt.
      - **Gefragt wird nur, wenn die Runde wirklich in eine Liste
        kommt** (`round_is_ranked`): Die Funktion spiegelt die
        Modus-Regeln aus 3.6 (nur ein erfolgreicher Ultra-/Sprint-Lauf
        wird gelistet) und die Null-Pruefungen der Listenfunktionen
        selbst. Eine Runde, die nirgends abgelegt wird, hat keinen
        Namen zu erfragen - Weltwunder-Fortschritt und Statistik, die
        sie weiterhin speist, sind namenlos. Ohne diese Bedingung
        haette jede versehentlich gestartete und sofort beendete Runde
        einen Dialog gezeigt.
      - **Der Name gilt fuer die Runde, nicht fuer die Einstellung.**
        `record_round` haelt ihn in einer lokalen Variablen und reicht
        ihn an die `highscore_*_add`-Funktionen weiter, statt
        `PLAYER_NAME` zu ueberschreiben. Das ist genau der Fall, fuer
        den die Abfrage da ist (jemand anderes spielt eine Runde mit),
        und es laesst den Einstellungs-Eintrag die eine Stelle sein,
        die die Vorgabe bestimmt; ein Zurueckschreiben haette die
        Einstellung stattdessen zum Protokoll der letzten Runde
        gemacht.
      - **Ein gemeinsamer Zeileneditor** (`menu_text_input`) fuer die
        neue Abfrage und die im Einstellungsmenue. Zwei verschiedene
        Eingabefelder fuer dieselbe Sache waeren schwer zu erklaeren,
        und die alte Abfrage konnte das Verlangte gar nicht: sie liess
        das Terminal die Zeile einlesen und anzeigen
        (`term_input_line`, kanonischer Modus mit Echo), und ein
        Terminal kann keine vormarkierte Vorgabe darstellen. Der Editor
        zeichnet die Zeile jetzt selbst als regulaeren, zentrierten
        Menue-Frame. Mitgenommen: `term_input_line` und
        `render_menu_dirty` sind ersatzlos entfallen - beide gab es nur
        wegen des Echos der alten Abfrage -, und die Eingabe ist damit
        die letzte Stelle, an der der Rohmodus der Sitzung noch eine
        Ausnahme hatte (Issue #33, 0.28.1).
      - **Textmodus in der Eingabeschicht statt eines zweiten Lesers**
        (`KEY_TEXT`, `lib/input.sh`): Die Flagge aendert allein die
        Behandlung einfacher Bytes in `key_plain` - Gross-/Kleinschreibung
        bleibt erhalten, die Loeschbytes werden zur Taste `BACKSPACE`.
        Escape-Sequenzen laufen unveraendert durch den Zustandsautomaten
        aus 0.23.0, sodass die Haertung gegen Issue #7 (in Stuecken
        zugestellte Sequenzen, Mausmeldungen, Terminalantworten, Paste)
        auch fuer die Eingabe gilt, statt neben ihr noch einmal
        entstehen zu muessen. Gesetzt wird sie nur um den einzelnen
        `read_key`-Aufruf, damit sie kein Rueckgabepfad in den
        Game-Loop traegt.
      Gefiltert wird beim Tippen: nur Zeichen, die dem Namensmuster
      genuegen, und hoechstens 16 davon kommen ueberhaupt in die Zeile
      (`MENU_INPUT_RE`, `MENU_INPUT_MAX`). Der Editor kann damit keinen
      ungueltigen Namen erzeugen, und die frueher noetige Fehlermeldung
      nach der Eingabe entfaellt.

- [x] **Demo-Aufzeichnung und Demo-Player** (Version 0.46.0): eigene
      Runden werden mitgeschnitten und lassen sich ueber den neuen
      Hauptmenuepunkt "Demos" noch einmal ansehen (`lib/demo.sh`,
      `menu_demos` in `lib/menu.sh`; aktueller Stand siehe 3.8 und
      4.10). Die drei Punkte, die die Roadmap offen gelassen hatte, samt
      der Groessenabschaetzung, die sie vor der Formatwahl verlangt hat:
      1. **Aufzeichnungsformat: Zuege statt Bildschirm, Steinfolge statt
         Seed.** Aufgezeichnet werden die Tastenaktionen, die
         Gravitationsschritte, das Ablaufen des Lock Delays und die
         Steinfolge; die Wiedergabe fuettert sie in dieselben
         Spielfunktionen, die eine echte Runde benutzt. Gemessen an
         echten Runden kostet das rund **2 kB je Spielminute** (etwa
         4 Ereignisse/s a 9 Byte plus ein Byte je Stein und ein knapp
         300 Byte grosser Kopf) - ein Frame-Mitschnitt haette je
         Bildschirmaenderung den halben Bildschirm gekostet. Zwei
         weitere Gruende sprachen dagegen: eine Bildaufzeichnung haette
         Terminalgroesse, Farben und - seit 0.41.0 - den Render-Modus
         festgeschrieben und zwingend im Full-Modus laufen muessen,
         waehrend eine Zug-Aufzeichnung kein einziges ANSI-Byte
         enthaelt und in jeder Kombination abspielbar ist. Und der in
         der Roadmap skizzierte **Seed** kam bewusst nicht: `RANDOM`
         wird einmal je Sitzung gesetzt, nicht je Runde, und sein
         Generator hat sich zwischen Bash-Versionen geaendert - ein Byte
         je Stein macht die Frage gegenstandslos.
      2. **Obergrenze: eine Stueckzahl, keine Gesamtgroesse.**
         `DEMO_MAX` = 10 wie die Bestenlisten; bei ~20 kB fuer eine
         lange Runde waere ein Groessenbudget Aufwand ohne Gegenwert.
         Zehn Eintraege plus "Zurueck" passen ausserdem mit Luft in ein
         22-Zeilen-Terminal, was eine groessere Zahl nicht taete.
      3. **Abspielgeschwindigkeit: Pause, Vorspulen und Zeitlupe.**
         Pausetaste bzw. Leertaste haelt an (ueber denselben
         "PAUSED"-Kasten wie im Spiel), Pfeil links/rechts stellt fuenf
         Stufen von 0.25x bis 4x, `r` spielt eine durchgelaufene Demo
         noch einmal. Moeglich wird das dadurch, dass die Wiedergabe
         eine eigene Uhr gegen absolute Zeitstempel laufen laesst,
         statt je Ereignis zu schlafen: kein Fehler summiert sich auf,
         und ein Tempowechsel wirkt sofort.
      Die uebrigen Vorgaben der Roadmap wurden wie beschrieben
      umgesetzt: waehrend der Runde wird **ausschliesslich auf eine
      RAM-Disk** geschrieben (`XDG_RUNTIME_DIR`, sonst `/dev/shm`),
      gepuffert in Bloecken von 64 Ereignissen, und erst beim echten
      Rundenende (`record_round`) wandert die fertige Aufnahme atomar
      ins Datenverzeichnis; die **Demo-Verwaltung** ist ein eigener
      Menuepunkt mit Datum, Modus, Spielzeit und Rows je Eintrag,
      Abspielen und einzelnem Loeschen.
      **Nachgereicht auf Nutzerwunsch (gleiche Version):** jeder
      Highscore-Eintrag bekam einen Hash aus den Ergebnissen seiner
      Runde (`round_hash`), der als letztes Feld in allen vier Listen
      und im Dateinamen der zugehoerigen Aufnahme steht. Damit weiss das
      Aufraeumen, welche Aufnahme zu einem noch gueltigen Highscore
      gehoert, und laesst sie stehen; verliert der Eintrag seinen Platz,
      endet der Schutz von selbst. Drei Entscheidungen dazu:
      `DEMO_MAX` zaehlt nur die ungeschuetzten Aufnahmen (sonst waere
      das Budget bei zehn Highscore-Demos aufgebraucht und jede neue
      Runde haette ihre Aufnahme sofort wieder verloren - genau das
      brachte der Test ans Licht); der Hash steht im Dateinamen statt in
      der Datei, damit Liste und Pruning ohne Dateizugriffe auskommen;
      und er ist FNV-1a in reinem Bash statt eines `cksum`-Aufrufs.
      Weil die Demo-Liste damit laenger als der Bildschirm werden kann,
      blaettert `menu_run` seither mit der Auswahl durch lange Listen.
      Die vier Listenformate wurden dafuer um ein Feld erweitert und
      akzeptieren beide Laengen - dieselbe Kulanz, die die
      Marathon-Liste seit 0.29.0 hat, aus demselben Grund.
      Drei Dinge kamen bei der Umsetzung dazu, die die Roadmap nicht
      vorgesehen hatte:
      - Eine **Wiedergabe wird nie gewertet** (Guard in `record_round`
        selbst, weil eine Wiedergabe die Funktion durch genau die
        Spielfunktionen erreicht, die sie nachspielt) und ist waehrend
        einer ueber das Pausenmenue geparkten Runde **gesperrt** - sie
        laeuft durch denselben Rundenzustand und wuerde ihn verwerfen.
      - Die **Blink-Animation skaliert** mit dem Abspieltempo
        (`flash_rows`), sonst verschluckt sie bei 4x nach jedem
        Reihenabbau ein Stueck Demo-Zeit.
      - `DEMO_RECORD` (`--demo-record on|off`, Einstellungsmenue) ist
        anders als `--render-mode` ein **Config-Wert**: ob
        mitgeschnitten wird, ist Geschmack und keine Eigenschaft des
        Terminals. Dazu kam das Reset-Ziel `demo` (siehe 4.8) - das
        einzige, das ein Verzeichnis statt einer Datei beiseite legt.
      Nebenbefund: `tools/demo/probe_pieces.sh` sourct `lib/pieces.sh`
      allein und brauchte deshalb einen Stub fuer die neue
      Demo-Anbindung in `queue_fill` (analog dem bereits vorhandenen
      Stub fuer `debug_event`).

- [x] **Vollstaendige Statistik je Spielmodus** (Version 0.47.0,
      Nutzerwunsch; aktueller Stand siehe 4.5): 0.42.0 hatte je Modus
      nur die **Runden** gezaehlt. Seither fuehrt `lib/stats.sh` jeden
      Zaehler ein zweites Mal je Modus - abgebaute Reihen, Bonusreihen,
      Gold- und Silberbloecke, Rowhammer, abgelegte Teile und Spielzeit,
      neben den Runden und den Laeufen, die ihr Modus-Ziel erreicht
      haben. Die Entscheidungen dahinter:
      - **Die Gesamtstatistik bleibt, was sie war** (ausdrueckliche
        Nutzervorgabe) - und zwar als eigene Zaehler, nicht als Summe
        der Modus-Zaehler. Der Unterschied wird an genau einer Stelle
        sichtbar: eine Runde in einem unbekannten Modus (nur aus einem
        kuenftigen Modus ohne Eintrag in `STATS_MODES` erreichbar) geht
        in die Gesamtzahlen ein und sonst nirgends. Die Gesamtsicht
        bleibt damit vollstaendig, waehrend die Modus-Bildschirme wie
        seit 0.42.0 lieber eine Luecke zeigen als eine falsche
        Zuordnung.
      - **Ein Menuepunkt mit Auswahl statt weiterer Bildschirme in der
        Folge.** "Statistik" fragt jetzt wie "Highscores" zuerst nach
        der Sicht (`menu_stats` in `lib/menu.sh`, Eintraege wortgleich
        mit dem Einzelspieler- und dem Highscore-Menue): Gesamt oder
        einer der vier Modi. Vier weitere Bildschirme an die drei
        vorhandenen anzuhaengen haette bedeutet, sich durch sieben
        Bildschirme zu druecken, um den letzten zu sehen.
      - **Ein Bildschirm je Modus, gelesen wie der Gesamtbildschirm**
        (gleiche Reihenfolge, gleiche Beschriftungen, gleiche
        Faerbung), plus die beiden Zahlen, die Modi erst vergleichbar
        machen: **Rows je Runde** und - bei den Zeitmodi - die
        **Erfolgsquote**. Beide sind abgeleitet und nicht gespeichert,
        wie die gewichtete Gesamtsumme und die PCS/min es schon waren;
        ohne eine einzige Runde stehen sie auf "-". Mit 16 Zeilen im
        laengsten Fall bleibt der Bildschirm in `MENU_BODY_MAX`.
      - **Die Modus-Uebersicht ("Statistik 3/3") bleibt** und ist jetzt
        zugleich der Ueberblick vor der Auswahl - der eine Bildschirm,
        der die vier Modi nebeneinander stellt.
      - **Ein flacher Schluessel je Modus und Feld**
        (`mode_<modus>_<feld>=N`) loest die `rounds_<modus>[_goal]`-
        Schluessel von 0.42.0 ab, deren zwei Zahlen nun Felder desselben
        Schemas sind: eine Namensregel statt zweier. Im Code liegen die
        Werte in einem assoziativen Array (`STATS_MODE`) statt in 36
        Globals; die feste Feldliste hat dabei die Rolle uebernommen,
        die vorher die Variablennamen hatten - einzige Quelle dessen,
        was in der Datei stehen darf. Eine bestehende Statistik-Datei
        verliert damit ihre Runden je Modus (Arbeitsregel "keine
        Abwaertskompatibilitaet") und behaelt alles andere; ein
        fehlender Schluessel faellt einzeln auf 0 zurueck.


- [x] **Mehrsprachige Oberflaeche** (Version 0.48.0, Roadmap-Punkt aus
      Phase 4; aktueller Stand siehe 4.11): Bis dahin standen die
      Menuetexte deutsch und die HUD-Beschriftungen samt `--help`
      englisch im Code - eine feste Mischung, die die damals offene
      Frage "UI-Sprache" nur konservierte. Seither kommt jeder
      spielersichtbare Text aus einer Tabelle, und die Sprache ist eine
      Laufzeit-Entscheidung. Die Entscheidungen dahinter:
      - **Ein assoziatives Array statt einer Lookup-Funktion.** Die
        Texte liegen in `I18N` und werden als `${I18N[key]}` gelesen.
        Eine Funktion `t KEY` haette pro HUD-Beschriftung einen
        Funktionsaufruf je Frame gekostet; das Array kostet eine
        Expansion. Formatstrings (`%s`, `%d`) stehen mit in der Tabelle
        und werden von ihrem Aufrufer mit `printf -v` gefuellt - so
        bleibt die Wortstellung Sache der Uebersetzung und nicht des
        Codes.
      - **Eine Datei je Sprache** (`lib/lang/<code>.sh`), geladen wird
        nur die aktive. Eine Sprache dazuzunehmen ist damit eine Datei
        plus ein Eintrag in `I18N_LANGS` (`lib/i18n.sh`); kein anderer
        Code kennt einen Sprachcode. Die Datei weist das ganze Array zu
        (statt einzelne Schluessel zu setzen), womit ein Wechsel zur
        Laufzeit keinen Text der vorherigen Sprache stehen lassen kann.
      - **Mehrzeilige Bloecke statt nummerierter Zeilenschluessel.** Die
        acht Anleitungsseiten waeren als `help1_1`, `help1_2` ... nicht
        mehr lesbar gewesen; sie stehen als ein Block je Absatz in der
        Sprachdatei und werden mit `i18n_lines` zerlegt. Die Seiten, die
        Text und generierte Zeilen mischen (Tastenbelegung,
        Wunder-Kosten, Modus-Ziele), setzen die Bloecke davor und
        dahinter.
      - **`--help` ist eine Funktion, kein Tabelleneintrag.** Der Text
        ist lang, enthaelt Anfuehrungszeichen und Prozentzeichen und
        wird genau einmal ausgegeben; ein `i18n_usage_text` mit
        gequotetem Heredoc je Sprachdatei ist dafuer das richtige
        Werkzeug. Damit `--help` uebersetzt sein kann, setzt `-h/--help`
        beim Parsen nur noch ein Flag: Config-Datei, Umgebung und der
        Rest der Kommandozeile muessen erst gelesen sein, bevor
        feststeht, in welcher Sprache zu antworten ist. Aus demselben
        Grund wandert `config_load` vor den Reset-Block - die
        Sprachwahl steht in der Config, und der Reset-Dialog ist
        ebenfalls uebersetzt.
      - **Eine falsche Option wirft nicht mehr den ganzen Hilfetext
        aus.** Sie stand vorher als `usage >&2` unter der Fehlermeldung;
        an dieser Stelle gibt es die uebersetzte Fassung noch nicht, und
        der Hinweis auf `--help` ist ohnehin das, was der Leser braucht.
      - **Standard `auto`, Rueckfall Deutsch.** Ein Spiel, das zwei
        Sprachen mitbringt und die Locale ignoriert, unterstuetzt keine
        von beiden richtig; also entscheiden `LC_ALL`, `LC_MESSAGES`
        bzw. `LANG` (nur ihr Sprachteil, `de_DE.UTF-8` -> `de`). Nennen
        sie keine bekannte Sprache, bleibt es bei Deutsch - der Sprache,
        in der die Menues geschrieben wurden, sodass eine Sitzung ohne
        brauchbare Locale genau so aussieht wie bisher.
      - **Die Sprache ist ein Config-Wert** (Praezedenz Standard <
        Config < `ROWHAMMER_LANG` < `--lang`), anders als Farb- und
        Render-Modus: welche Sprache jemand liest, ist eine Eigenschaft
        der Person und keine des Terminals. Gespeichert wird die
        **Auswahl**, also auch `auto` - wer "folge der Locale" gewaehlt
        hat, will das weiter, nicht die Sprache von damals.
      - **Umschalten wirkt sofort.** `menu_language` laedt die Tabelle
        neu und setzt `RENDER_FULL=1`: die HUD-Beschriftungen stehen im
        Frame-Cache des Diff-Renderers, und genau sie haben sich
        geaendert.
      - **Fehlermeldungen nach STDERR bleiben englisch** (Konvention aus
        Abschnitt 6). Sie treten teils auf, bevor die Sprache ueberhaupt
        aufgeloest ist - und wenn die Sprachwahl selbst das Defekte ist,
        waere eine uebersetzte Meldung der falsche Ort, das zu zeigen.
        Uebersetzt ist alles, was auf einem Bildschirm des Spiels steht,
        einschliesslich des Reset-Dialogs (0.36.1) und `--help`.
      - **Die Tabellen ohne Anzeige-Namen.** `KEY_LABELS` (menu.sh),
        `COLOR_THEME_LABEL` (pieces.sh), `STATS_MODE_LABEL` und
        `STATS_MODE_GOAL_LABEL` (stats.sh) sowie `WONDER_NAMES_DE`/
        `WONDER_NAMES_HUD` (wonders.sh) sind entfallen. Sie wurden beim
        Sourcen der Module gefuellt, also bevor die Sprache feststeht;
        ihre Eintraege liegen jetzt unter einem aus dem Bezeichner
        gebauten Schluessel in der Tabelle (`keylabel_KEY_HOLD`,
        `theme_mono`, `mode_ultra`, `wonder_stonehenge`). Das erspart
        zugleich die zweite Tabelle, die in derselben Reihenfolge
        gepflegt werden musste; der Debug-Log nennt ein Wunder jetzt bei
        seinem Dateinamen, der in jeder Sprache derselbe ist.
      Nebenbefund: Beim Vermessen der Texte gegen die 46 Spalten, die
      ein 48-Spalten-Terminal einem Menue laesst, fielen sechs deutsche
      Texte auf, die schon vorher zu lang waren und dort abgeschnitten
      wurden - der Mehrspieler-Platzhalter, die drei Meldungen des
      Rebind-Dialogs, die Abbrechen-Fusszeile einer Sicherheitsabfrage
      und je eine Zeile der ersten und dritten Anleitungsseite. Sie sind
      umbrochen; die Breitengrenzen stehen jetzt im Kopf der
      Sprachdateien.

- [x] **Hochwasser-Modus** (Version 0.49.0, Nutzerwunsch; aktueller
      Stand siehe 3.6): der fuenfte Spielmodus und der erste, in dem
      das Spielfeld sich von selbst fuellt. Alle `FLOOD_INTERVAL_MS`
      (20000 ms = 20 Sekunden, Nutzervorgabe "vorerst 20") Spielzeit
      schiebt sich von unten eine volle Reihe mit genau einem Loch ins
      Feld und das ganze Feld rueckt eine Zeile nach oben; sonst ist die
      Runde Marathon - sie endet im Game Over, gewertet werden die Rows,
      ein Ziel gibt es nicht (`GAME_MODE=flood`, `flood_raise` in
      `rowhammer.sh`, `board_flood_row` in `lib/board.sh`).
      Die Entscheidungen dahinter:
      - **Die Flutreihe ist eine Zellsorte fuer sich** (`GARBAGE_CELL`,
        `x`), keine Steinsorte: Instanz-ID 0, damit nie Teil eines
        Quadrats. Das ist genau die Festlegung, die die
        Mehrspieler-Spezifikation fuer ihre Stoerreihen trifft (5.7) -
        der Modus nimmt sie vorweg, statt eine zweite Art Stoerreihe zu
        erfinden, und liefert damit die Vorarbeit fuer Phase 5,
        Schritt 7 gleich mit.
      - **Das Hochschieben laesst die Steine heil.** `BOARD`,
        `BOARD_ID` und `BOARD_SQ` wandern zeilenweise gemeinsam nach
        oben, sodass Instanzen ihre ID und ihre Gold-/Silber-Markierung
        behalten - ein Quadrat ueberlebt die Flut wie einen Reihenabbau
        unter sich. Eine belegte oberste Zeile beendet die Runde, statt
        eine Zelle aus dem Feld zu druecken.
        _Spaeter ueberholt: seit 1.0.2 endet die Runde eine Zeile
        frueher - sobald der Anstieg den Stapel in die verdeckten Zeilen
        ueber dem Feld schiebt (`board_top_out`), dieselbe Regel, an der
        seither auch ein festgesetzter Stein gemessen wird._
      - **Der fallende Stein bleibt stehen, wo er ist**, und rueckt nur
        mit hoch, wenn er sonst im gestiegenen Stapel steckte: er lag
        auf dem, was sich bewegt hat. Ist auch das blockiert, ist die
        Runde vorbei. Ein scharfes Lock-Delay wird nur geprueft, nicht
        neu gestellt - die Regel aus 3.1 bleibt, wie sie ist.
      - **Die naechste Flut wird vom Eintreffen der letzten an
        gerechnet**, nicht von ihrem Soll-Zeitpunkt: ein spaet
        gekommener Tick (Resize, Blink-Animation) haette sonst mehrere
        faellige Reihen auf einmal eingeschoben. Dieselbe Ueberlegung,
        aus der die Gravitation `LAST_FALL` auf "jetzt" setzt.
      - **Die Fluthoehe steht im Game-Loop in einem eigenen `if`**, vor
        der Gravitationskette: ein Anstieg ist kein Rundenende und darf
        dem Tick sein Fallen nicht nehmen. Beendet er die Runde, faengt
        ein `GAME_OVER`-Zweig vor der Kette das ab.
      - **Jede Runde kommt in die Bestenliste**, wie bei Time Attack:
        einen Zustand "abgebrochen" gibt es hier nicht, jede Runde
        dieses Modus endet im Game Over. Eigene, fuenfte Datei
        `${DATA_DIR}/highscore-flood` (`HSF_*` in `lib/highscore.sh`),
        Rangordnung und Zeilenformat der Marathon-Liste, aber ohne deren
        Kulanz gegenueber kuerzeren Zeilen: die Liste ist mit dem
        Runden-Hash entstanden und hatte nie eine Fassung ohne ihn.
      - **Im HUD teilt sich der Modus die beiden Zeilen der Zeitmodi**
        (Zeile 15/16 der linken Spalte), mit eigenem Label: "Flut" fuer
        den Abstand, "Rest" fuer die Zeit bis zur naechsten Reihe. Kein
        "Ziel", weil es keines gibt.
      - **Die Demo-Aufzeichnung bekam ihr erstes Ereignis mit
        Nutzlast** (`w<spalte>`) und damit Formatversion 2: der Anstieg
        folgt der Uhr, die Lochspalte aber `RANDOM` - eine Wiedergabe,
        die sie raet, spielte eine andere Runde (siehe 4.10).
      - **Grau mit eigenem Glyph (`::`), auch im Farbmodus.** Im Thema
        `mono` haben die Steine dasselbe Grau, und eine Reihe, die
        niemand gelegt hat, soll immer als solche zu erkennen sein.
      Nebenbefund: die Anleitungsseite "Spielmodi" fasste den fuenften
      Modus nicht mehr (sie sass mit vier Modi schon auf
      `MENU_BODY_MAX`) und ist in zwei Seiten geteilt - Marathon, Ultra
      und Sprint auf der einen, Time Attack und Hochwasser auf der
      anderen; die Anleitung hat damit neun Seiten.

- [x] **Platz in der Bestenliste in der Namensabfrage** (Version 0.50.0,
      Nutzerwunsch; aktueller Stand siehe 3.7): Die Namensabfrage am
      Rundenende (0.45.0) nennt ueber der Eingabezeile jetzt auch den
      Platz, den die Runde in der Bestenliste ihres Modus einnehmen wird
      - "Bestenliste: Platz 3 von 10" bzw. "Bestenliste: kein Platz
      (Top 10)", wenn sie die Liste verfehlt. Die Entscheidungen dahinter:
      - **Der Platz wird vorhergesagt, nicht abgelesen.** Der
        Listeneintrag entsteht erst, wenn die Abfrage einen Namen
        zurueckgegeben hat (`record_round` in `rowhammer.sh`: der Name
        geht in den Eintrag *und* in den Runden-Hash), also **nach** dem
        Bildschirm, der den Platz zeigen soll. Die Abfrage dahinter zu
        schieben waere der kuerzere Weg gewesen und haette genau diese
        Reihenfolge umgedreht. Stattdessen leitet
        `highscore_rank_preview` (`lib/highscore.sh`) den Platz aus der
        geladenen Liste ab, ohne sie anzufassen.
      - **Eine Funktion fuer alle fuenf Listen** statt fuenf Kopien der
        Einfuegeregel: sie unterscheiden sich nur darin, welches Array
        sie befragen und ob der kleinere Wert der bessere ist (Ultra
        rangiert nach Zeit, alle anderen nach Rows). Der Platz ist
        derselbe, den die `*_add`-Funktion vergeben wuerde - eins hinter
        der Zahl der mindestens gleich guten Eintraege, und kein Platz,
        wenn das ueber die Laenge der Liste hinausgeht. Zwischen Vorschau
        und Eintrag aendert nichts die Liste, beide koennen also nicht
        auseinanderlaufen; ein Zufallstest ueber 180 Runden hat das gegen
        die drei Einfuegefunktionen geprueft.
      - **Welche Zahl die Runde rangiert, weiss `round_rank_preview`**
        (`rowhammer.sh`) - dieselbe Modus-Fallunterscheidung, die
        gleich darueber schon `round_is_ranked` trifft. Ein kuenftiger
        Modus wird damit an einer Stelle eingetragen, nicht an zweien.
      - **Auch die verfehlte Liste steht dort.** Eine Runde wird nach
        dem Namen gefragt, sobald sie ueberhaupt in eine Liste kommen
        koennte (`round_is_ranked`) - ob sie die Top 10 dann wirklich
        erreicht, ist eine andere Frage, und sie unbeantwortet zu lassen
        waere die einzige Stelle, an der der Bildschirm schweigt.

- [x] **Umbenennung der Marathon-Bestenliste** (Version 0.51.0,
      Nutzerwunsch; aktueller Stand siehe 4.5): die Datei der
      Marathon-Liste heisst `highscore-marathon` statt `highscore` und
      passt damit ins Schema der vier Modus-Listen, die mit 0.34.0
      bis 0.49.0 dazugekommen sind (`highscore-ultra`,
      `highscore-sprint`, `highscore-timeattack`, `highscore-flood`).
      Der schlichte Name war ein Rest aus 0.7.0, als sie die einzige
      Liste war.
      Die Entscheidungen dahinter:
      - **Eine vorhandene alte Datei wird umbenannt statt fallen
        gelassen** (`highscore_migrate_legacy` in `lib/highscore.sh`,
        ein `mv`, ausdruecklicher Nutzerwunsch). Das ist eine bewusste
        Ausnahme von der Arbeitsregel "keine Abwaertskompatibilitaet"
        (CLAUDE.md, Abschnitt 6) und eine sehr billige: am Inhalt der
        Datei aendert sich kein Byte, nur am Namen - eine Top Ten
        dafuer wegzuwerfen waere ein Verlust ohne Gegenwert. Der alte
        Name lebt einzig als `HS_LEGACY_FILE_NAME` fuer diese eine
        Funktion weiter.
      - **Sie laeuft vor dem Reset-Block** in `rowhammer.sh`, nicht
        etwa in `highscore_load`. `--reset highscore` (siehe 4.8)
        arbeitet mit den Dateinamen, die die Module besitzen; eine noch
        unter dem alten Namen liegende Datei waere dort als "nicht
        vorhanden" gemeldet worden und haette ihren eigenen Reset
        ueberlebt.
      - **Eine schon vorhandene Zieldatei wird nie ueberschrieben**
        (die Umbenennung hat dann bereits stattgefunden, und der alte
        Name ist etwas von Hand Zurueckgelegtes): sie bleibt liegen und
        meldet sich auf STDERR. Ein fehlgeschlagenes `mv` ist dagegen
        ein harter Fehler - das Datenverzeichnis ist dann nicht
        beschreibbar, das Spiel koennte dort ohnehin keine Liste
        speichern, und weiterzumachen hiesse stillschweigend mit einer
        leeren Marathon-Liste zu starten.
      - **Die Meldung der Umbenennung ist uebersetzt**
        (`highscore_renamed`, siehe 4.11) und geht wie der
        Reset-Dialog auf STDOUT, bevor der Alternate-Screen aufgeht;
        nur die beiden Fehlerfaelle bleiben englisch auf STDERR.

- [x] **Bestenlisten mit Cursor, Blaettern und Demo-Wiedergabe**
      (Version 0.52.0, Nutzerwunsch; aktueller Stand siehe 4.5): die
      fuenf Highscore-Listen waren bis dahin schreibgeschuetzte
      Info-Bildschirme, die `menu_pages` seitenweise ausgab - eine Taste
      je Seite, immer nur vorwaerts und ohne Weg zurueck. Sie sind jetzt
      ein Browser mit Cursor (`highscore_browse` in `lib/highscore.sh`):
      Pfeil hoch/runter waehlt den Eintrag und blaettert dabei die Seite
      mit, Pfeil links/rechts blaettert direkt, beides umlaufend,
      `ESC`/`x` geht zurueck - und **Enter spielt die
      Demo-Aufzeichnung des ausgewaehlten Eintrags ab**.
      Die Entscheidungen dahinter:
      - **Die Frage "gibt es zu diesem Eintrag eine Aufnahme?"
        beantwortet der Runden-Hash aus 0.46.0.** Er steht als letztes
        Feld im Highscore-Eintrag und im Dateinamen der Aufnahme; die
        Verknuepfung existierte also schon, sie wurde bisher nur in der
        Gegenrichtung benutzt (das Aufraeumen fragt, welche Aufnahme
        noch einen Highscore haelt). `demo_hash_map` (`lib/demo.sh`) ist
        die Umkehrung von `highscore_hash_set`: Hash auf Dateipfad, ein
        Glob und kein einziger Dateizugriff, bei jedem Oeffnen eines
        Listen-Bildschirms neu gebaut, weil eine zwischendurch gespielte
        Runde oder eine geloeschte Aufnahme genau dieses Ergebnis
        aendert.
      - **Der Cursor ist ein `>`, keine Invertierung.** Eine
        Eintragszeile besteht aus SGR-Sequenzen, die auf einen Reset
        enden - die Invertierung, mit der `menu_run` seine Eintraege
        markiert, waere darin mittendrin abgeschnitten worden. Die
        zweite Zeile eines Eintrags laesst die Cursor-Spalte leer: ein
        zweites `>` laese sich wie eine zweite Auswahl.
      - **Zwei Spalten der Zeile bezahlen das** (`HS_LINE_MAX` 44 statt
        46): eine fuer den Cursor, eine fuer die `*`-Markierung der
        Eintraege mit Aufnahme. Die zweite Zeile eines Eintrags nutzt
        ihre 44 Zeichen im Vollausbau genau aus, die erste bleibt
        darunter - das Layout passt damit weiterhin exakt in das
        48-Spalten-Minimum.
      - **Ein Eintrag ohne Aufnahme sagt das auf Enter**, statt nichts
        zu tun: die Markierung sagt nur, welche Eintraege eine haben,
        nicht warum die anderen keine haben (geloescht, Aufzeichnung
        war aus, oder aelter als die Demo-Funktion).
      - **Waehrend eine pausierte Runde im Hauptmenue wartet, ist die
        Wiedergabe gesperrt** - dieselbe Regel und dieselbe Meldung wie
        im Demo-Menue (3.8): eine Wiedergabe laeuft durch genau den
        Rundenzustand, in dem diese Runde parkt.
      - **`menu_pages` ist ersatzlos entfallen.** Die fuenf Listen waren
        seine einzigen Aufrufer; ein Widget ohne Aufrufer
        stehenzulassen, waere toter Code. Sein Seitenzaehler-Text
        (`I18N[menu_page]`) lebt im Browser weiter.
      - **Die fuenf Listenbildschirme teilen sich jetzt zwei Helfer**
        (`highscore_row2` fuer die zweite Zeile, `highscore_rank_sgr`
        fuer die Medaillenfarbe): sie waren in allen fuenf Funktionen
        wortgleich kopiert, und der Umbau haette die Kopie sonst ein
        fuenftes Mal angefasst.
      Nebenbefund und mitbehoben: `menu_demos` rief nach einer
      Wiedergabe `render_menu_dirty` auf - eine Funktion, die mit ihrem
      anderen Aufrufer in 0.45.0 entfallen war. Unter `set -e` beendete
      dieser Aufruf das Spiel, sobald man eine ueber das Demo-Menue
      gestartete Wiedergabe verliess ("command not found"). Die Stelle
      setzt `MENU_FULL=1` jetzt direkt, so wie es die Stellen in
      `lib/render.sh` und `lib/input.sh` tun, die den Bildschirm
      uebernehmen.

- [x] **Aufgeraeumtes Einzelspieler-Menue: Beschreibung je Modus,
      ausgerichtet** (Version 0.53.0, Nutzerwunsch; aktueller Stand
      siehe 3.6): die Modus-Eintraege nannten hinter dem Namen in
      Klammern, wogegen der Modus laeuft - aber nur vier von fuenf, und
      jede Klammer begann dort, wo ihr Name zufaellig endete. Jetzt
      traegt jeder Eintrag eine Beschreibung, und alle beginnen in
      derselben Spalte. Die Entscheidungen dahinter:
      - **Die Breite wird gemessen, nicht festgeschrieben.**
        `menu_mode_entries` (`lib/menu.sh`) fuellt jeden Namen auf den
        laengsten der fuenf auf. Eine feste Zahl waere in der Sprache
        richtig gewesen, in der sie gezaehlt wurde, und in der naechsten
        falsch - der Hochwasser-Modus allein heisst "Hochwasser" oder
        "Flood" (4.11).
      - **Die Texttabelle traegt die Klammern, nicht den Namen.** Die
        `entry_*`-Eintraege sind seither die Beschreibung allein; Name
        und Auffuellung setzt der Code davor. So gehoert die
        Formulierung weiterhin der Uebersetzung und die Ausrichtung dem
        Code, statt beides in einem String zu vermischen, in dem eine
        Uebersetzung sie nur wieder zerstoeren koennte.
      - **Marathon bekommt "endlos, bis Game Over".** Er war der
        einzige Eintrag ohne Klammer - was sich wie ein vergessener
        Text las statt wie der eine Modus ohne Ziel. Dass er keines
        hat, ist selbst die Auskunft, die dort fehlte.
      - **Alle drei Modus-Auswahlen aendern sich mit** (Einzelspieler,
        "Highscores", "Statistik"): sie bauen ihre Eintraege seit
        0.48.0 aus demselben Helfer, und genau dafuer gibt es ihn -
        derselbe Modus soll sich ueberall gleich lesen.

- [x] **Weltwunder-Bildschirm blaettert zu den fertigen Wundern**
      (Version 0.54.0, Nutzerwunsch; aktueller Stand siehe 3.3): der
      Bildschirm zeigte immer nur die laufende Baustelle - ein fertig
      gebautes Wunder war nach dem naechsten Reihenabbau nicht mehr zu
      sehen, obwohl es die Arbeit vieler Runden war. Pfeil links/rechts
      schaltet jetzt zwischen den fertigen Wundern und der aktuellen
      Baustelle um. Die Entscheidungen dahinter:
      - **Der Bereich endet bei der laufenden Baustelle**
        (0..`WONDER_INDEX`). Ein noch nicht begonnenes Wunder waere ein
        leerer Rahmen und naehme dem Weiterbauen die Ueberraschung;
        gezeigt wird, was erreicht ist. Geblaettert wird umlaufend wie
        in jeder anderen Liste des Spiels.
      - **Ein fertiges Wunder wird aus der Kostentabelle gerechnet**,
        nicht aus einem gespeicherten Stand: `wonder_screen_lines`
        (`lib/wonders.sh`) zeigt es vollstaendig aufgedeckt und mit
        `WONDER_COSTS` als erreichtem Stand (100 %). Gespeichert ist
        allein der Gesamtzaehler (4.5), und die Reihen, die dieses
        Wunder gebaut haben, stecken laengst in den Wundern danach - ein
        zweiter, je Wunder mitgefuehrter Zaehler koennte von ihm nur
        abweichen.
      - **Ohne ein fertiges Wunder bleibt der Bildschirm, was er war:**
        jede Taste schliesst ihn, die Fusszeile sagt genau das. Es gibt
        dann nichts zu blaettern, und der Ablauf nach einer Runde
        erwartet es so. Erst als Blaetterer nennt die Fusszeile die
        Tasten und schliesst nur noch auf `Enter`, Leertaste, `x` oder
        `ESC` - dieselbe Aufteilung, die die Anleitung seit 0.33.0 hat,
        und aus demselben Grund: die Pfeile bedeuten jetzt etwas
        anderes.
      - **Der Bildschirm nach einer Runde blaettert mit.** Es ist
        derselbe Bildschirm und dieselbe Funktion; ein zweiter, nur
        fuers Zurueckschauen, waere dieselbe Anzeige ein zweites Mal.
      - **Die Anleitungsseite zum Wunderbau nennt die Tasten**
        (Seite 5). Eine Zeile mehr war dort nicht zu haben - die Seite
        sitzt mit 18 Zeilen auf `MENU_BODY_MAX` -, also ist ihr
        Schlussabsatz enger formuliert und sagt in denselben vier Zeilen
        jetzt beides.
- [x] **Verhaeltnis von abgebauten Reihen zu Bonusreihen in jeder
      Statistik** (Version 0.55.0, Nutzerwunsch; aktueller Stand siehe
      4.5): "Abgebaute Reihen" und "Bonusreihen" standen auf jedem
      Statistik-Bildschirm direkt untereinander - was sie zueinander
      sagen, naemlich wie viel der Reihenwertung aus den Gold- und
      Silber-Quadraten kam statt aus den Reihen selbst, musste man sich
      dazu im Kopf teilen. Jeder dieser Bildschirme nennt das
      Verhaeltnis jetzt selbst: der Gesamtbildschirm, jede der drei
      letzten Runden und jeder der fuenf Modus-Bildschirme. Die
      Entscheidungen dahinter:
      - **Die Form ist "1:X.XX"**, nicht ein Prozentsatz und nicht ein
        blosser Quotient: genau das sind die beiden Zahlen - eine Reihe
        des Feldes und der Bonus, den sie getragen hat. Zwei
        Nachkommastellen, weil die interessanten Unterschiede zweier
        Spielweisen in der zweiten stehen; gerechnet wird wie bei
        `fmt_ppm` in Hundertsteln, weil Bash keine Fliesskommazahlen
        kennt.
      - **Ohne eine abgebaute Reihe steht "-".** Es ist der einzige
        Division-durch-0-Fall und zugleich der einzige, in dem die Zahl
        ohnehin nichts sagen wuerde - ohne Reihe gibt es keinen Bonus.
      - **Der Platz ist zwischen den beiden Zaehlern und der
        gewichteten Gesamtsumme.** Das Verhaeltnis setzt die rohen
        Zahlen zueinander, waehrend Gesamtsumme und Rows je Runde aus
        ihnen abgeleitet sind. Ohne Faerbung, weil die Akzentfarbe auf
        diesen Bildschirmen der Gesamtsumme gehoert - der Zahl, die die
        Wunder baut.
      - **Bei den letzten Spielen kostet es eine dritte Zeile je
        Runde.** Die beiden vorhandenen sind mit 44 der 46 verfuegbaren
        Zeichen voll; eine ihrer Spalten fuer eine ableitbare Zahl
        herzugeben waere der falsche Tausch gewesen. Mit drei Zeilen je
        Runde landet der Bildschirm bei 14 der 18 Zeilen aus
        `MENU_BODY_MAX`, der laengste Modus-Bildschirm (Zeitmodus) bei
        17.
      - **`stats_ratio` liegt in `lib/stats.sh`**, nicht neben
        `fmt_ppm` in `rowhammer.sh`: `fmt_ppm` teilen sich Statistik
        und Bestenlisten, dieses Verhaeltnis ist eine reine
        Statistik-Zahl.
      - **Ein absurdes Verhaeltnis wird gekappt** ("1:>9999"). In einer
        gespielten Runde bleibt der ganzzahlige Teil unter 21 (ein
        Tetris durch zwei Gold-Quadrate sind 4 Reihen und 81
        Bonusreihen); groessere Werte koennen nur aus einer von Hand
        bearbeiteten Datei kommen und wuerden bloss die Zeile ueber ihre
        46 Zeichen hinaus schieben - dieselbe Vorsicht, mit der die
        Runden-Zeilen daneben bei Ueberlaenge auf Farbe verzichten.

- [x] **Namensabfrage nur noch fuer eine Runde mit Platz in der
      Bestenliste** (Version 1.0.1, Nutzerwunsch; aktueller Stand siehe
      3.7): Gefragt wurde bis 0.55.0, sobald eine Runde ueberhaupt in
      eine der fuenf Listen kommen konnte - also auch dann, wenn sie die
      Top 10 verfehlte. Der Bildschirm sagte das zwar ("kein Platz
      (Top 10)"), verlangte aber trotzdem einen Namen fuer einen
      Eintrag, der nie geschrieben wurde. Jetzt entscheidet der Platz
      selbst, ob gefragt wird; eine Runde ohne Platz behaelt den
      Spielernamen aus den Einstellungen und geht direkt zum
      Rundenende-Kasten ihres Modus. Die Entscheidungen dahinter:
      - **Die Bedingung wandert in `round_is_ranked`** (`rowhammer.sh`),
        die einzige Stelle, die ueber die Abfrage entscheidet. Sie
        spiegelte bereits die Modus-Regeln und die Null-Pruefungen der
        Listenfunktionen; die Top 10 ist die dritte Regel derselben
        Frage "kommt diese Runde in eine Liste?" und gehoert deshalb
        dorthin und nicht als zweite Pruefung an die Aufrufstelle.
      - **Gefragt wird `round_rank_preview`** - dieselbe Vorschau, die
        der Bildschirm schon fuer seine Rangzeile nutzt (0.50.0). Ein
        neuer Weg, den Platz zu bestimmen, waere ein zweiter, der vom
        spaeteren Eintrag abweichen koennte.
      - **Erst die Modus-Regeln, dann die Vorschau.** Ein gescheiterter
        Ultra- oder Sprint-Lauf wird nie eingetragen; ihn vorher gegen
        die Liste zu ranken haette einen Platz gemeldet, den er nie
        bekommt.
      - **Die Vorschau laeuft damit zweimal** je gefragter Runde, einmal
        in `round_is_ranked` und einmal in `prompt_round_name`. Das ist
        eine Abfrage in einer bereits geladenen Liste und laesst beide
        Stellen fuer sich lesbar - die Alternative waere ein
        Vorschau-Ergebnis, das die eine Funktion fuer die andere
        stehen laesst.
      - **Die Meldung "kein Platz (Top 10)" ist entfallen**
        (`round_rank_none` in beiden Sprachdateien): Sie hatte keinen
        Fall mehr, und ein Text ohne Fall waere genau die Art toter
        Zweig, die spaeter niemand mehr einordnen kann.
- [x] **Rundenende am oberen Feldrand** (Version 1.0.2, Nutzerreport;
      aktueller Stand siehe 3.1): Ein Testspiel zeigte, dass sich auf der
      obersten Reihe des Feldes noch ein Stein festsetzen liess, der
      darueber hinausragte, ohne dass die Runde verloren war. Grund war,
      dass das Spiel nur einen einzigen Top-Out kannte - die blockierte
      Spawn-Position. Damit endete eine Runde erst, wenn der Stapel dem
      naechsten Stein den Platz zum Einfallen nahm, und alles, was in den
      beiden verdeckten Spawn-Zeilen darueber liegen blieb, war
      unsichtbar geduldet. Das Feld ist 20 Reihen hoch; was darueber
      stehen bleibt, gehoert nicht mehr dazu. Die Entscheidungen dahinter:
      - **Gefragt wird das Brett, nicht der Stein** (`board_top_out` in
        `lib/board.sh`: liegt eine Zelle in den verdeckten Zeilen?). Eine
        Pruefung der gerade festgesetzten Zellen haette den Reihenabbau
        nachrechnen muessen, der sie verschiebt, und sie haette die
        zweite Stelle, an der etwas dort hinkommen kann - das steigende
        Wasser des Hochwasser-Modus -, mit einer eigenen Regel
        zurueckgelassen. So misst eine Funktion beide.
      - **Geprueft wird nach dem Reihenabbau** (`lock_and_next` in
        `rowhammer.sh`). Ein Stein, der oben heraussteht, aber Reihen
        mitnimmt, zieht den Stapel wieder ins Feld zurueck; dieser
        Rettungszug wird belohnt statt bestraft. Aus demselben Grund
        steht die Pruefung **hinter** der Ultra-Zielpruefung: ein Lauf,
        der mit genau diesem Stein sein Ziel erreicht, hat gewonnen, wie
        hoch der Stein auch sass.
      - **Im Hochwasser-Modus endet die Runde am Anstieg selbst**
        (`flood_raise`), nicht erst beim naechsten Lock - sonst waeren
        die beiden Wege ueber die Feldkante verschieden streng. Das
        Rundenende faellt damit eine Zeile frueher als die bisherige
        Pruefung in `board_flood_row`, die eine Zelle erst dann nicht
        mehr schieben wollte, wenn sie vom Brett gefallen waere. Jene
        Pruefung bleibt als Eigensicherung der Funktion stehen: sie ist
        das Einzige, was ueberhaupt verhindert, dass eine Zelle aus dem
        Brett geschoben wird, und die Mehrspieler-Garbage (5.7) wird
        dort spaeter mehrere Reihen auf einmal durchschieben.
      - **Die Anleitung sagt es** (Seite 1, beide Sprachen): das
        Rundenende hat jetzt zwei Ausloeser statt einem.
      Mit derselben Version kam die Arbeitsregel dazu, dass **jede
      Aenderung am Mehrspieler-Modus Arbeit an Version 2.x.x** ist
      (Nutzerentscheidung; CLAUDE.md, Abschnitt 6): das
      Einzelspieler-Spiel behaelt seine laufende Versionsreihe, und der
      erste Schritt in die Phasen 5 und 6 ist der Sprung auf `2.0.0`.
      _Spaeter ueberholt: 1.1.0 - der Mehrspieler waechst bis zu seiner
      Fertigstellung in der `1.x`-Reihe, und `2.0.0` ist fuer den Stand
      reserviert, an dem Phase 5 wirklich abgeschlossen ist._
- [x] **Spielzeit der Namensabfrage auf die Millisekunde; Versionszeile
      in der README** (Version 1.0.3, Nutzerwunsch; aktueller Stand
      siehe 3.7 und 4.9).
      - Der Bildschirm der Namensabfrage zeigt die Spielzeit seither mit
        `fmt_duration_ms` (MM:SS.mmm), und zwar **in jedem Modus**.
        _Vorzustand: er zeigte `fmt_duration` (MM:SS) und schnitt damit
        ausgerechnet die Stellen ab, die im Ultra ueber den Platz
        entscheiden, den derselbe Bildschirm eine Zeile tiefer nennt -
        zwei Versuche auf dasselbe Ziel landen oft in derselben Sekunde,
        weshalb die Ultra-Liste Millisekunden speichert._ Fuer alle Modi
        gleich, weil ein Bildschirm eine Zahl nicht in zwei Formen
        zeigen soll, je nachdem welcher Modus lief. Der
        Rundenende-Kasten blieb unberuehrt: dort ist die Zeit im Ultra
        ohnehin schon millisekundengenau, und in den anderen Modi ist
        sie nicht die Wertung, sondern eine Randnotiz.
      - Die README nennt ihre Version in einer eigenen Zeile
        `**Version:** X.Y.Z` unter der Ueberschrift, und
        `tools/release.sh --mode check` prueft sie mit - eine von Hand
        gepflegte Nummer in einer Doku-Datei ist die erste, die
        veraltet, und ein Besucher glaubt ihr. Damit kennt das Werkzeug
        vier Stellen mit der Version statt drei.
- [x] **Beutel des Randomizers auf 63 Steine** (Version 1.0.4,
      Nutzerentscheidung; aktueller Stand siehe 3.1): neun vollstaendige
      Saetze der sieben Sorten, als Ganzes gemischt (`BAG_SETS` in
      `lib/pieces.sh`).
      _Vorzustand: ein Beutel aus sieben Steinen. Dessen gleichmaessige
      Ausgabe - zwei gleiche Sorten liegen hoechstens zwoelf Steine
      auseinander - ist genau das, was ein Quadrat schwer macht, denn es
      braucht vier zueinander passende Teile._ Der lange Beutel bringt
      beides zurueck: die Haeufung gleicher Sorten, aus der ein
      Gold-Quadrat ueberhaupt erst wird, und die Duerre, die es zu einer
      Entscheidung macht. Die Garantie bleibt dieselbe - ueber einen
      vollen Beutel kommt jede Sorte gleich oft.


## Phase 5 - Mehrspieler (umgesetzt, Version 1.1.0)

Die Schritte 1 bis 8 sowie 10 bis 12 der Roadmap sind mit `1.1.0`
umgesetzt; offen bleibt allein Schritt 9 (Demo-Aufzeichnung einer
Mehrspieler-Runde, siehe CLAUDE.md 5.20) und die Entkopplung aus
Schritt 1, soweit sie ueber das hinausgeht, was der Mehrspieler
brauchte. Der aktuelle Zustand steht in CLAUDE.md 5.1 bis 5.10 und in
der README; hier steht, was umgesetzt wurde und warum es so und nicht
anders aussieht.

- [x] **Transport, Discovery, Protokoll** (Schritte 2 und 3, `lib/net.sh`,
      `lib/proto.sh`). socat traegt beides: die Sitzung ueber
      `TCP4-LISTEN`/`TCP4` im lokalen Netz oder ueber `UNIX-LISTEN`/
      `UNIX-CONNECT` auf einem gemeinsamen Rechner, und den Beacon ueber
      `UDP4-DATAGRAM` an die limitierte Broadcast-Adresse. Der Client
      haelt seine Verbindung als **Coprocess**, sodass Lesen und
      Schreiben gewoehnliche Bash-Deskriptoren sind und `net_poll` je
      Tick hoechstens `MP_POLL_MAX` Zeilen abraeumt, ohne je zu
      blockieren. Entscheidungen, die beim Bauen dazukamen:
      - **Ein Beacon nennt seine Adresse nicht.** Sie kommt aus der
        Absenderadresse des Datagramms (`SOCAT_PEERADDR`), die nur einem
        von socat gestarteten Kind zur Verfuegung steht - daher der
        Sammler `--mp-discover`. Ein gefaelschter Beacon kann damit
        hoechstens auf seinen eigenen Absender zeigen.
      - **Eine Adresse wird nie als Zeichenkette weitergereicht**:
        `net_addr_tcp` zerlegt sie in vier Oktette und einen Port,
        prueft jedes Stueck einzeln und baut die socat-Adresse aus den
        Zahlen neu. Das ist der Weg, auf dem eine Netzwerk-Discovery am
        ehesten zur Codeausfuehrung wuerde.
      - **Ein halb angekommenes Paket geht nicht verloren.** TCP darf
        mitten in einer Zeile trennen; `net_poll` haelt den Rest in
        `NET_PART` und setzt ihn beim naechsten Mal davor - ohne das
        waeren aus einer Nachricht zwei ungueltige geworden.
      - **Der Zeichensatzfilter fixiert die Locale.** Ein Bereich wie
        `[\x01-\x1f]` folgt der Kollationsreihenfolge und trifft in
        einer UTF-8-Locale auch den Punkt; `net_line_ok` setzt daher
        `LC_ALL=C` fuer die Dauer der Pruefung. Gefunden hat das der
        Fuzz-Lauf (Schritt 12), noch bevor die erste Runde lief.
- [x] **Hub, Bridge und Lobby** (Schritt 4, `lib/hub.sh`, `lib/mp.sh`).
      Der Hub laeuft als eigener, terminalloser Prozess, den der Client
      des Gastgebers im Hintergrund startet; socat nimmt die
      Verbindungen an und startet je Verbindung eine **Bridge**, die
      Socket und FIFOs verbindet. Der Hub spricht damit nur mit FIFOs
      (kann Bash nativ), socat nur mit Sockets, und der Wechsel zwischen
      den Transporten kostet genau eine geaenderte Adresszeile.
      - **Die Bridge haelt ihre eigene Down-FIFO offen** (`exec 8<>`).
        Ohne das ging die erste Nachricht verloren: ein FIFO-Puffer
        existiert nur, solange jemand die Datei offen hat, und der Hub
        oeffnet sie je Nachricht nur kurz. Das war der einzige Fehler,
        der die erste Sitzung nicht zustande kommen liess.
      - **Der Start gehoert dem Gastgeber**, und er braucht dafuer keine
        eigene Nachricht: Slot 0 ist die erste Verbindung und damit der
        Gastgeber, und sein `READY 1` ist der Start (ab dem zweiten
        Spieler; allein bekommt er ein `ERR alone`). Fuer ihn ist der
        Lobby-Eintrag ohnehin der Startknopf.
      - **Die Lobby ist kein `menu_run`.** Sie muss neu zeichnen, wenn
        sich die Spielerliste aendert, und dabei die Leitung leeren -
        ein Menue, das nur auf Tasten reagiert, liesse die Verbindung
        in den Ping-Timeout laufen. Aus demselben Grund hat auch das
        Pausenmenue der Runde eine eigene, leerende Variante.
- [x] **Mitspieler-Anzeige, alle drei Stufen** (Schritte 5 und 6).
      Stufe 2 zeichnet je Gegner ein Mini-Feld (ein Zeichen je Zelle,
      13 Spalten) rechts neben dem Spielblock, Stufe 1 zwei Zeilen und
      Stufe 0 eine Zeile in der rechten Seitenleiste; `auto` nimmt die
      ausfuehrlichste, fuer die das Terminal Platz hat, und rechnet bei
      jedem Resize neu.
      - **Die Stufen 1 und 0 kosten keine Breite.** Sie nutzen die
        freien Zeilen unter der Vorschau, weshalb eine Sechs-Spieler-
        Runde auch im 48x22-Minimum laeuft - genau der Fall, fuer den
        die Stufen erfunden wurden.
      - **Feld-Schnappschuesse fliessen nur, wenn jemand hinsieht.** Der
        Client meldet mit `VIEW 0|1`, ob er Stufe 2 zeichnet; der Hub
        leitet daraus je Client ab, ob er senden soll (`NEEDBOARD`).
        Beides sind Nachrichten, die die Spezifikation so nicht hatte:
        sie schrieb `NEEDBOARD` vor, ohne zu sagen, woher der Hub weiss,
        wer zeichnet.
- [x] **Garbage** (Schritt 7). Die Zellsorte, das zeilenweise
      Hochschieben und die Top-Out-Pruefung gab es seit 0.49.0 aus dem
      Hochwasser-Modus; dazu kamen die Warteschlange, die Verrechnung
      und die Hub-Seite. Ein Abbau meldet nur das Ereignis
      (`CLEAR <Reihen> <Silber> <Gold>`), der Hub rechnet daraus den
      Angriff (0/1/2/4 Reihen, +2 je Silber, +4 je Gold, Deckel 10),
      verrechnet ihn zuerst gegen die eigene Warteschlange des
      Angreifers und schickt nur den Rest.
      - **Die Warteschlange gehoert dem Hub.** Er schickt sie dem
        Client mit `QUEUE` nach, wenn ein Abbau sie gekuerzt hat, und
        der Client meldet mit `APPLIED`, was er eingeschoben hat. Zwei
        Kopien derselben Zahl auf beiden Seiten koennten nur
        auseinanderlaufen - und die Verrechnung ist genau die Stelle,
        an der ein manipulierter Client sich sonst bedienen koennte.
      - **Eingeschoben wird beim naechsten Lock ohne Abbau.** Ein Lock,
        der Reihen geraeumt hat, hat gerade seinen `CLEAR` gemeldet;
        die Verrechnung laeuft davor, und das ist es, was den
        Gegenangriff gegenueber reiner Abwehr belohnt.
- [x] **Sitzungseinstellungen des Gastgebers** (Nutzerwunsch, kam beim
      Bauen dazu und ist in CLAUDE.md 5.1 beschrieben). Der Gastgeber
      legt in der Lobby fest, **wie gewonnen wird** - `survival` (wer
      uebrig bleibt, Vorgabe), `sprint` (die meisten Rows in der Zeit)
      oder `ultra` (wer zuerst am Ziel ist) - und ob **Stoerreihen**
      ueberhaupt fliegen; beides steht in der Lobby jedes Spielers.
      - **Drei Modi, weil es drei Siegbedingungen gibt.** Ein Modus, der
        nur anders aussieht, waere eine Einstellung; einer, der die
        Frage "wer gewinnt" anders beantwortet, ist ein Modus. Time
        Attack und Hochwasser sind aus genau diesem Grund nicht dabei:
        im Duell endeten beide wie `survival`.
      - **Stoerreihen sind anfangs aus** (Nutzervorgabe). Sie machen die
        anspruchsvollere Runde und sollen etwas sein, das man
        einschaltet. Ausgeschaltet bleibt ein Abbau ein Abbau - er
        zaehlt fuer die Rows -, er reist nur nicht, weshalb es ein
        Schalter neben dem Modus ist und kein vierter Modus.
      - **In `sprint` und `ultra` endet die Runde nicht am vorletzten
        Ausscheiden**, und die Plaetze werden am Ende nach Rows neu
        vergeben: wer schon draussen ist, kann trotzdem vorn liegen.
      - Umgesetzt als eine Nachricht in beide Richtungen (`SETUP`, wie
        `ROSTER`); der Hub nimmt sie nur von Slot 0 und nur ausserhalb
        der Runde an. Damit ging die Protokollversion auf 2.
- [x] **Rundenende, Zuschauermodus, Verbindungsabbruch** (Schritt 8).
      Wer oben rausbaut, meldet `TOPOUT`, bleibt als Zuschauer im Bild
      und bekommt den hoechsten noch freien Platz; der letzte im Feld
      gewinnt (`END`). Ein Abbruch zaehlt wie ein K.O., die Runde laeuft
      weiter.
      - **Die Runde wird erst verbucht, wenn der Hub sie beendet.**
        `round_finish` unterscheidet das vom Einzelspieler: dort ist der
        volle Stapel das Rundenende, hier nur das eigene Ausscheiden.
      - **Es gibt keine Pause** (die anderen warten nicht) und kein
        "Ins Hauptmenue": eine pausierte Mehrspieler-Runde koennte
        nirgendwohin zurueckkehren.
  Die Siegbedingung war bis dahin der letzte offene Punkt aus Abschnitt
  8 gewesen ("bleibt es beim letzten Ueberlebenden, oder kommt ein
  reiner Rows-Wettkampf dazu?"); mit den Sitzungseinstellungen ist er
  beantwortet, ohne dass eine Seite die andere verdraengt.

- [x] **Drei bis sechs Spieler** (Schritt 10): Zielwahl `random|all|even`
      im Hub, `--mp-max` als Obergrenze, Layout-Raster fuer mehrere
      Mini-Felder.
- [x] **Test-Bot, Doku, Paketierung** (Schritt 11). `--mp-bot` ist ein
      Client ohne Terminal, der ueber dieselben Spielfunktionen spielt
      wie ein Mensch - er laeuft nur nicht durch `game_run`, dessen Takt
      am Terminal haengt. `socat` ist in beiden Paketen ein
      `Recommends`; README und Anleitung (zehnte Seite) beschreiben den
      Ablauf.
- [x] **Sicherheits-Review und Fuzzing** (Schritt 12, `tools/net-fuzz.sh`).
      Gepruefte Eigenschaften: kein Befehl aus Eingaben wird ausgefuehrt
      (Kanarienvogel-Datei), kein Byte ausserhalb 0x20-0x7E kommt durch,
      kein Fall bringt einen Prozess zum Absturz oder Haengen. Der
      Beacon-Sammler ist mit gefuzzt - er ist der erste Parser, den ein
      Fremder ohne jede Verbindung erreicht. Der Lauf ist Teil der CI.

Bewusst **nicht** umgesetzt und zu diesem Zeitpunkt offen: die
Aufzeichnung einer Mehrspieler-Runde als Demo (Schritt 9). Sie braucht
das Format 3 aus 5.20 mit den Peer-Ereignissen; eine Runde in
Formatversion 2 zu schreiben, waere schlimmer als keine - sie liefe als
Runde ab, in der aus dem Nichts Stoerreihen erscheinen.
`demo_record_start` lehnt einen unbekannten Modus deshalb ausdruecklich
ab.

_Spaeter ueberholt: 1.3.0 (siehe unten) baut den Unterbau und schreibt
das Format 3; aufgezeichnet und gelesen wird eine Mehrspieler-Runde
seitdem._


## Gastgeberwechsel im Mehrspieler (umgesetzt, Version 1.2.0)

Nutzerwunsch, in zwei Schritten praezisiert: erst "gib die Lobby an den
ersten beigetretenen Spieler weiter, setze die Bereit-Haken zurueck und
lass die anderen den neuen Gastgeber mit Enter bestaetigen", dann - noch
waehrend der Arbeit daran - "wenn der Host die Lobby verlaesst, muss auch
dessen Hub beendet werden; der zweite Spieler wird zum Hub" und "bitte
baue auch Timeouts ein, damit Clients eine Lobby von selbst als
geschlossen erkennen". Der aktuelle Zustand steht in CLAUDE.md 5.1
(Ablauf), 5.4 (Nachrichten und Zeiten) und 5.8 (Rundenende und
Abbruch).

- [x] **Die Sitzung zieht um, statt dass der Hub weiterlaeuft.** Die
      erste Fassung liess den Hub des weggegangenen Gastgebers stehen
      und reichte nur die Rolle weiter - der kuerzere Weg, aber der
      falsche: die Sitzung laege dann als Prozess auf der Maschine von
      jemandem, der sich von ihr abgewandt hat, und nichts wuerde sie je
      beenden ausser dem Weggehen des letzten Spielers. Jetzt bittet der
      alte Hub den Nachfolger zu uebernehmen (`PROMOTE`), der startet
      einen **eigenen** Hub und nennt dessen Port (`PROMOTED <port>`),
      alle anderen werden dorthin geschickt (`MIGRATE <adresse> <port>`)
      - und erst dann stellt sich der alte Hub ab.
- [x] **Nachfolger ist, wer am laengsten da ist** (`HUB_JOINED`, eine je
      Verbindung hochgezaehlte Beitrittsnummer), nicht der niedrigste
      freie Slot: nach ein paar Kommen und Gehen ist die
      Slot-Reihenfolge fuer niemanden im Raum mehr eine Reihenfolge.
- [x] **Die Sitzung behaelt ihren Namen.** Sonst liefe sie beim
      Nachfolger unter dessen Namen weiter und erschiene im Beacon als
      eine andere. `WELCOME` traegt dafuer seit dieser Version den
      Sitzungsnamen als viertes Feld; jeder Client merkt ihn sich
      (`MP_SESSION_NAME`) und gibt ihn seinem Hub mit, falls er einmal
      selbst uebernehmen muss. Damit ging die Protokollversion auf 3.
- [x] **Alle Bereit-Haken fallen** (Nutzerwunsch). Sie galten dem alten
      Gastgeber und seinen Einstellungen; ausserdem *ist* das
      Bereit-Zeichen des Gastgebers der Startknopf, ein geerbter Haken
      koennte also eine Runde starten, die niemand wollte.
- [x] **Die Meldung wird mit Enter bestaetigt** (Nutzerwunsch), nicht
      mit einer beliebigen Taste wie sonst im Spiel: sie faellt mitten
      in eine Lobby, in der gerade jemand auf den Pfeiltasten war, und
      soll gelesen und nicht weggetippt werden.
- [x] **Klappt der Wechsel nicht, sagt der Hub das.** Kein Nachfolger da
      (`CLOSED host`), oder der Gefragte antwortet nicht binnen
      `HUB_PROMOTE_MS` (3000 ms) bzw. bekommt keinen Hub hoch
      (`CLOSED failed`). Eine ausgesprochene Absage ist besser als eine
      Lobby, die stumm bleibt, bis ein Timeout greift.
- [x] **Der Hub endet nicht im selben Atemzug** (`hub_stop_soon`,
      `HUB_STOP_GRACE_MS`): die eben geschriebenen Nachrichten liegen
      noch in den Down-FIFOs, die die Bridges erst durch ihre Sockets
      schieben muessen. Ein Hub, der sofort aufhoerte, naehme sein
      letztes Wort mit - `hub_cleanup` raeumt genau diese FIFOs weg.
- [x] **Nur in der Lobby.** Geht der Gastgeber waehrend der Runde, ist
      das ein gewoehnliches Ausscheiden und die Runde spielt sich zu
      Ende; ein Umzug mitten im Spiel muesste den ganzen Rundenzustand
      mitnehmen.
- [x] **Client-Timeout** (Nutzerwunsch). Bis dahin erkannte ein Client
      nur, was ihm gesagt wurde - ein Hub, dessen Rechner ausgeschaltet
      wird, sagt aber nichts mehr und schickt auch kein EOF. Jeder
      Client stempelt deshalb jede empfangene Zeile (`MP_LAST_RX_MS`)
      und gibt nach `MP_TIMEOUT_MS` (6000 ms) Stille auf
      (`mp_link_silent`) - derselbe Wert, mit dem der Hub seine Clients
      fuer abgestuerzt haelt. Der `PING` des Hubs alle 2000 ms ist damit
      nicht nur eine Frage, sondern das Lebenszeichen, auf das der
      Client wartet: drei ausgefallene reichen. Gefragt wird an jeder
      Stelle, an der ein Client auf den Hub wartet - Lobby,
      Einstellungsmenue, Namensabfrage, Countdown und Game-Loop -,
      sodass eine tote Sitzung nirgends stehen bleibt.
- [x] **Der Nachfolger bekommt einen Vorsprung.** Der neue Hub gibt die
      Lobby dem, der sich zuerst meldet; auf einer Maschine - zwei
      Terminals und ein Test-Bot auf der Loopback-Adresse - entschied
      das eine Handvoll Millisekunden, und der Falsche gewann sie
      ungefaehr so oft wie der Richtige. Der alte Hub haelt das
      `MIGRATE` an die anderen deshalb `HUB_MIGRATE_DELAY_MS` (500 ms)
      zurueck, waehrend der Nachfolger nach seinem `PROMOTED` nur
      `MP_HANDOFF_FLUSH_MS` (250 ms) wartet - gerade genug, damit socat
      die Zeile noch hinausbekommt, bevor `net_close` es beendet.
- [x] **Die FIFOs eines Hubs tragen seine Prozessnummer.** Zwei Hubs
      desselben Sitzungsnamens auf einer Maschine sind mit dem Umzug der
      Normalfall geworden; unter dem alten Namensschema loeschte der
      zweite das Postfach des ersten, und dessen Bruecken schrieben von
      da an in ein Postfach, an dem niemand wartete - die Nachricht des
      Nachfolgers kam nie an und die Sitzung wurde fuer gescheitert
      erklaert, obwohl alles funktioniert hatte. `hub_sweep_stale`
      raeumt beim Start die FIFOs von Hubs weg, deren Prozess es nicht
      mehr gibt.
- [x] **Die Sitzungsgroesse zieht mit um** (`MP_SESSION_MAX` aus
      `WELCOME`), nach oben begrenzt durch das eigene `--mp-max` des
      Nachfolgers: seine Peer-Tabellen haben so viele Plaetze, wie er
      selbst angemeldet hat.
- [x] **Ein fehlgeschlagener Sendeversuch schreibt nichts mehr auf den
      Bildschirm.** Stirbt der Hub, schliesst Bash die Deskriptoren des
      Coprozesses, und die naechste Umleitung darauf meldet "Bad file
      descriptor" - eine Shell-Meldung, die `2>/dev/null` am Befehl
      nicht abfaengt und die im Standard-Render-Modus mitten im
      Spielfeld stehen bleibt (CLAUDE.md 4.3). `net_send` umleitet
      deshalb die Fehlerausgabe der ganzen Gruppe und behaelt dabei den
      Fehlerstatus.


## Fuenf Spieler und Sitzordnung (umgesetzt, Version 1.3.0)

Zwei Nutzerentscheidungen zur Darstellung der Mitspieler, die zusammen
gehoeren: eine kleinere Sitzung, dafuer groessere Felder. Der aktuelle
Zustand steht in CLAUDE.md 5.1 (Spielerzahl) und 5.6 (Darstellung).

- [x] **Eine Sitzung fasst fuenf statt sechs Spieler** - man selbst und
      vier Mitspieler; `--mp-max` nimmt 2..5 und steht standardmaessig
      auf 5. Vier Gegner sind genau das, was sich noch symmetrisch um
      das eigene Feld setzen laesst, und ein Feld weniger bezahlt die
      breiteren Zellen darunter.
      _Vorzustand: bis 1.2.0 waren es sechs Spieler (`MP_MAX` bis 6);
      die Begruendung fuer die Obergrenze - Rechenaufwand,
      Bildschirmbreite, Zielwahl - steht unveraendert in 5.1._
- [x] **Die Mitspieler sitzen um das eigene Feld herum**
      (Nutzerwunsch), nicht mehr alle rechts davon: der erste rechts,
      der zweite links, der dritte weiter rechts, der vierte weiter
      links, sodass der Bildschirm `[5][3][selbst][2][4]` liest. Das
      eigene Feld behaelt die Mitte, wie viele Mitspieler auch
      dazukommen - der Blick liegt die ganze Runde auf dem eigenen
      Stapel, und ein Feld, das mit jedem Beitritt weiter nach links
      rutschte, muesste jedes Mal neu gesucht werden. Die Reihenfolge
      ist die des Beitritts (`MP_PEER_SLOTS`), damit waehrend der Runde
      kein Feld den Platz wechselt.
- [x] **Ein Gegnerfeld hat die volle Zellenbreite, wenn das Terminal sie
      hergibt** (Nutzerwunsch): zwei Zeichen je Zelle, exakt wie das
      eigene Feld und mit denselben Glyphen, also 23 Spalten je Gegner
      (140 bei vier Gegnern). Passt das nicht, faellt die Anzeige auf
      die bisherige halbe Breite zurueck (ein Zeichen je Zelle, 13
      Spalten je Gegner, 100 bei vieren). **Das eigene Feld wird dafuer
      nie verkleinert** - auf seinen 48 Spalten steht das ganze feste
      Layout (Seitenleisten, Rundenende-Kasten, Menues, das
      Terminal-Minimum, siehe 3.4).
- [x] **Eine geaenderte Gesamtbreite zeichnet den Block vollstaendig
      neu** (`RENDER_FULL`) - ein Resize, ein Beitritt in der Lobby, ein
      erzwungener Modus, der erst jetzt passt. Der Zeilen-Diff (4.3)
      ueberschreibt nur, was er schreibt; ohne das bliebe beim
      Schrumpfen die alte Ausgabe in den aufgegebenen Spalten stehen -
      und weil die Gegner jetzt auch nach links wachsen, wandert dabei
      die linke Kante selbst.

## Mehrspieler-Demo: Unterbau und Aufzeichnung (umgesetzt, Version 1.3.0)

Die Teilschritte 9.1 bis 9.10 des Punkts "Demo-Aufzeichnung der
Mehrspieler-Runde" (Zielanforderung und Architektur in 5.20). Die
restlichen Teilschritte 9.11 bis 9.14 - Fokuswechsel, Kasten am Ende,
Gegenprobe, Doku - stehen weiter in [TODO.md](TODO.md); erst sie heben
die Version auf `1.4.0`.

- [x] **9.1 Rundenzustand benennen.** Neues Modul `lib/state.sh` mit der
      Liste des Rundenzustands (`STATE_VARS`) und `state_new`,
      `state_bind`, `state_release`; beim Bauen kamen `state_unbind` und
      `state_release_all` dazu. Noch ohne Nutzer - die Runde lief
      weiter auf den Globals. Abnahme: `tools/state-check.sh` legt fuenf
      Zustaende an, schreibt aus einer Funktion heraus in jeden und
      liest alle fuenf zurueck; ausserdem liest es die Zuweisungen aus
      `game_reset` und verlangt, dass jede in `STATE_VARS` steht oder in
      der kurzen Liste der Sitzungszustaende.
- [x] **9.2 Bash-Minimum auf 4.3.** Startcheck mit klarer Meldung,
      `debian/control`, `rowhammer.spec`, CLAUDE.md 4.1 und README
      nachgezogen. Abnahme: Start und `--help` unveraendert, die Meldung
      erscheint bei kuenstlich gesetzter Bedingung.
      _Vorzustand: das Minimum war Bash 4.0 (assoziative Arrays); die
      Namerefs von `lib/state.sh` heben es auf 4.3 (2014). Einen
      Rueckfallweg gibt es nicht - die Alternative waere, den ganzen
      Rundenzustand je Frame hin- und herzukopieren._
- [x] **9.3 Protokoll 4, Teil 1: `ACT`/`PEERACT`.** Nachrichtentabelle
      und Muster in `lib/proto.sh`, Sammeln und Senden in `lib/mp.sh`
      (`MP_ACT_MS`), Weiterreichen im Hub. Die zehn Stellen, an denen
      einer Runde etwas zustoesst, rufen seither `round_event`
      (`rowhammer.sh`) statt `demo_record_event` - ein Trichter, der das
      Ereignis an beide Verbraucher desselben Alphabets weitergibt.
      Abnahme: Runde mit drei `--mp-bot`, `net.log` zeigt die Stroeme,
      `tools/net-fuzz.sh` bleibt sauber, die Runde spielt sich
      unveraendert.
- [x] **9.4 Protokoll 4, Teil 2: `GARBAGE`/`QUEUE` mit Slot an alle.**
      Abnahme: Stoerreihen kommen unveraendert an, und jeder Client
      sieht auch die der anderen im `net.log`.
      _Vorzustand: beide Nachrichten gingen ohne Slot nur an den
      Betroffenen. Ein Version-3-Client wuerde den vorangestellten Slot
      als Reihenzahl lesen und die falsche Menge Stoerreihen
      einschieben - genau dafuer wurde die Protokollversion
      hochgezaehlt._
- [x] **9.5 Lastprobe.** Fuenf Teilnehmer in Detailstufe 2 - ein
      zeichnender Client in einem 200x50-Terminal, der als Einziger
      Schnappschuesse anfordert (und sie damit fuer alle einschaltet),
      dazu vier Test-Bots -, je drei Laeufe mit und ohne die neuen
      Nachrichten:

      | Groesse | Protokoll 3 | Protokoll 4 | Grenze |
      | --- | --- | --- | --- |
      | Nachrichten je Client und Sekunde (Spitze) | 10 | 17 | `MP_RATE_MAX` 64 |
      | empfangene Zeilen je Client und Sekunde (Spitze) | 45 | 63 | 800 (16 je Tick x 50 Ticks) |
      | Nachrichten des Hubs je Sekunde (Spitze, alle Clients) | 144 | 221 | - |
      | `PING`-Abstand des Hubs | 2000-2049 ms | 2001-2058 ms | Soll 2000 ms |
      | Bilder je Sekunde beim zeichnenden Client | 7,4-8,0 | 6,7-9,1 | - |
      | verworfene Nachrichten / Raten-Abschaltungen | 0 / 0 | 0 / 0 | 0 |

      Der Zugstrom kostet gut zwei Drittel mehr Nachrichten und bleibt
      bei einem Viertel der Ratengrenze; die Empfangsseite liegt unter
      einem Zehntel dessen, was ein Tick abraeumen kann. **Keine der
      beiden Grenzen wurde nachgezogen** - eine Zahl, die nicht
      annaehernd erreicht wird, enger zu ziehen bringt nichts, und
      weiter zu ziehen gaebe nur einem Fluter mehr Raum. Der Hub-Tick
      von 50 ms haelt mit. Die Bildrate liegt im selben Streubereich wie
      vorher (Mittel 7,5 gegen 7,7 bei drei Laeufen je Seite, der beste
      Einzellauf ist einer der neuen) - eine Verschlechterung ist nicht
      messbar, die Stichprobe ist aber klein: die Test-Bots bauen sich
      nach 4 bis 7 Sekunden selbst tot, und so lang ist das
      Vollast-Fenster je Lauf.
- [x] **Ein Seed, den jeder Client verwarf** - der Fehler, den die
      Lastprobe gefunden hat. Er stand im Code, seit es den gemeinsamen
      Seed gibt: die Maske `0x3FFFFFFF` reicht bis 1.073.741.823 und war
      damit in rund **7 % aller Runden** zehnstellig, `--seed` nimmt
      Ziffern beliebiger Laenge. Beides passte nicht in das neunstellige
      Zahlenfeld des Protokolls (`PROTO_NUM_RE`), also wies **jeder**
      Client die `SEED`-Nachricht als fehlerhaft ab, behielt sein
      eigenes `RANDOM` und spielte eine **andere Steinfolge** - genau
      die Fairness, fuer die der gemeinsame Seed da ist, und auf dem
      Bildschirm stand nichts davon. `hub_start_round` nimmt den Seed
      seither modulo 1.000.000.000: ein Seed, der vom gewuenschten
      abweicht, ist das erheblich kleinere Uebel als einer, den niemand
      bekommt.
- [x] **9.6 Format 3 schreiben.** Kopf, `p=`- und `v=`-Zeilen, neue
      Ereignisbuchstaben, Demo-Uhr als Rundenuhr im Versus, `versus` in
      `DEMO_MODE_RE`, `end=lost`, und `--mp-bot` zeichnet nicht auf.
      Noch keine Wiedergabe. Abnahme an einer Runde mit zwei Test-Bots:
      Kopf, Ereignisstroeme, Pruefpunkte und die Plaetze der
      Ausgeschiedenen decken sich mit dem `events.log` des
      aufzeichnenden Clients. Der Sitzungsblock ist auf eine
      Versus-Aufnahme beschraenkt, damit eine Einzelspieler-Aufnahme
      bleibt, was sie war. Eine Versus-Aufnahme stand in der Demo-Liste
      und wurde beim Abspielen mit einer Meldung abgewiesen, bis 9.8 sie
      lesen konnte.
- [x] **9.7 Steinfolge fuer alle.** Die Folge aus dem eigenen Beutel
      nachfuellen, solange irgendein Spieler noch Steine braucht - auch
      nach dem eigenen Ausscheiden (`demo_pieces_topup`, gezaehlt je
      Slot in `demo_slot_event`). Abnahme an einer Drei-Spieler-Runde
      mit zwei Test-Bots, in der der aufzeichnende Client als Erster
      ausschied: er selbst hatte 12 Steine verbraucht, der
      Weiterspielende 14, und in der Datei stehen 18 (14 + Vorschau) -
      dieselben 18, die der Beutel des Bots aus dem gemeinsamen Seed
      gezogen hatte, Buchstabe fuer Buchstabe.
- [x] **9.8 Format 3 lesen.** Neue Kopfschluessel (`peer=` ist der erste
      wiederholbare), fuenf Ereignisstroeme ueber Namerefs, ein Muster je
      Feld, Version 2 weiter akzeptiert. Abnahme an der Aufnahme aus 9.7
      (drei Stroeme, 146 Ereignisse, Pruefpunkte an ihrer Position) und
      an 29 praeparierten Dateien - Sitzungsblock in beiden Richtungen
      falsch, Slots ausserhalb der Sitzung, verstuemmelte Tokens,
      Kopfzeilen hinter dem Strom, Version zu alt und zu neu sowie
      ANSI-Sequenzen, `$(...)`, Backticks und eine 100-kB-Zeile: jede
      mit ihrem Grund im Debug-Log abgewiesen, kein Befehl ausgefuehrt.
      Eine Format-2-Aufnahme und eine Einzelspieler-Aufnahme der Version
      3 spielen unveraendert.
- [x] **9.9 Wiedergabe: Zustaende aufbauen.** Je Sitzplatz ein Zustand,
      initialisiert von genau dem `game_reset`, mit dem eine echte Runde
      beginnt; Aufbau innerhalb der Neustart-Schleife (Taste `r`),
      Rueckbau auf beiden Rueckgabepfaden (`demo_seats_scan`,
      `demo_play_states_build`, `demo_play_states_release`,
      `demo_play_peers_begin`/`_end` in `lib/demo.sh`). Abnahme an einer
      echten Drei-Spieler-Runde (ein Client, zwei Test-Bots, Stoerreihen
      an): die Aufnahme startet, zeigt das eigene Feld in der Mitte und
      die beiden Mitspieler mit Namen auf ihren Plaetzen der Runde,
      laeuft ihre 5882 ms ab und endet im Demo-Kasten; `events.log`
      nennt drei Rundenstarts, einen je Sitzplatz. Dieselbe Aufnahme mit
      `--mp-max 2` zeigt weiterhin beide Mitspieler (`MP_SEATS`).
      Rueckbau geprueft, indem im selben Prozess hinterher eine
      Marathon-Runde gespielt wurde - Brett, Beutel und Instanztabellen
      arbeiten wie zuvor. Aufgeraeumt: `state_unbind` stellt die Globals
      wieder her, und `tools/state-check.sh` prueft das mit.
- [x] **9.10 Wiedergabe: Ereignisse anwenden.** Ein Cursor je Sitzplatz,
      Kontextwechsel, `MP_PEER_*` aus der Simulation gefuellt (Brett
      samt fallendem Stein), `flash_rows` nur fuer den Fokus
      (`demo_step`, `demo_peer_publish`, `demo_cursors_reset`,
      `demo_events_left` und die vier Hub-Buchstaben in
      `demo_apply`/`demo_apply_out`). Abnahme an einer echten
      Drei-Spieler-Runde: beim Abspielen stapeln sich die beiden
      Bot-Bretter genau wie in der Runde, sie scheiden mit ihren
      Plaetzen 3 und 2 aus, der Sieger bleibt stehen, und die Wiedergabe
      endet auf ihrer Zeitachse. Dazu eine von Hand gebaute Aufnahme mit
      den drei Ereignissen, die kein Zug erzeugt: die zwei Stoerreihen
      (`y023`) stehen mit ihrem Loch in Spalte 3 im Brett des Fokus, die
      Warteschlangenlaenge folgt dem `q`-Ereignis und der
      Ausgeschiedene traegt "K.O. 3" in seiner Fusszeile. Die
      Detailstufen 1 und 0 zeigen dieselbe Simulation als Zaehler und
      Hoehenbalken, eine Einzelspieler-Aufnahme laeuft unveraendert, und
      die Runde nach einer Wiedergabe hat weder Gegner noch fremden
      Zustand. Aufgeraeumt: die Guards in `round_finish`,
      `mp_act_event`, `mp_send_clear` und `mp_apply_garbage`, die eine
      Wiedergabe davon abhalten, ihr simuliertes Rundenende als eigenes
      zu melden.
