# CODEX-REVIEW

**Stand:** 2026-10-10

**Repository:** `roemer2201/rowhammer`, Branch `main`

**Geprüfter Commit:** `4384724fbddaaa1c990fbd4304b11f6c3cd3ce98`

**Spielversion:** 2.0.3

Dieser Bericht ersetzt die älteren, teilweise überholten Bewertungen der
Mehrspieler-Aufzeichnung und des Singleplayers. Die Zeilenangaben beziehen
sich auf den oben genannten Commit. Geprüft wurden die Spielsteuerung,
Rundenzustände, Eingabe und Anzeige, Persistenz und Datenverzeichniswechsel,
Mehrspieler-Protokoll und Hub sowie Demo-Aufzeichnung und Wiedergabe.
Die Befunde unten wurden mit den echten Bash-Funktionen beziehungsweise
der echten CLI nachvollzogen. Bei Funktionsprüfungen wurden Uhr, Oberfläche
oder Transport gezielt durch Testadapter ersetzt; es wurde keine Systemuhr
verstellt und ausschließlich in temporären Datenverzeichnissen gearbeitet.

## Offene Befunde

| ID | Priorität | Befund |
| --- | --- | --- |
| DATA-01 | P1 / hoch | Verlegen auf einen Pfadalias kann die eigenen aktiven Daten löschen |
| RESET-01 | P2 / mittel | `--reset all` lässt die Versus-Bestenliste stehen |
| SP-01 | P2 / mittel | Bestenliste und Demo verwenden unterschiedliche Spielernamen |
| SP-02 | P2 / mittel | Systemuhrsprünge verändern Spielzeit und Fristen |
| MP-03 | P2 / mittel | Nach einem Top-out wird Zuschauerzeit als Spielzeit gebucht |
| MP-04 | P2 / mittel | Protokollzahlen mit führender Null werden als Oktalzahlen verarbeitet |
| DEMO-01 | P2 / mittel | Eine kurz abgebrochene Versus-Aufnahme kann vom eigenen Loader abgelehnt werden |

### DATA-01: Ein Pfadalias umgeht den Schutz vor dem Verlegen in dasselbe Verzeichnis

**Stellen:** `lib/datadir.sh:101-161`; `lib/menu.sh:1117-1129, 1213-1247`.

`datadir_path_check` normalisiert doppelte und abschließende Schrägstriche,
löst aber keine Symlinks oder `.`-Komponenten auf.
`datadir_inside` und der Gleichheitsvergleich im Menü vergleichen nur die
Pfadstrings. Zwei unterschiedlich geschriebene Pfade können deshalb als
getrennte Verzeichnisse gelten, obwohl sie dieselben Dateien enthalten.

Beispiel: Das aktuelle Datenverzeichnis ist `/tmp/test/current`;
`/tmp/test/alias` ist ein Symlink darauf. Beim Verlegen auf `alias`
erkennt das Menü eine vorhandene Konfiguration und bietet an, die eigenen
Daten mitzunehmen und die Zieldaten zu ersetzen. Nach Bestätigung wird
zwar ein Backup angelegt, aber anschließend löscht
`datadir_wipe(target)` auch den Inhalt von `current`.
`datadir_move(current, target)` findet danach nichts mehr zum Verschieben.
Das Menü meldet dennoch einen erfolgreichen Wechsel.

**Nachweis:** Der tatsächliche Ablauf über `menu_datadir` wurde mit
ersetzter Texteingabe und bestätigender Testoberfläche ausgeführt.
Vorher enthielt `current` eine Konfiguration und `save` mit
`total_rows=123`. Danach blieben nur das Backup und die Zeigerdatei
`datadir`; die Oberfläche meldete „Location changed“.
Die Daten sind aus dem Backup wiederherstellbar, aber nicht mehr als
aktive Spielstände vorhanden.

**Korrektur:** Vor Klassifikation, Backup und Löschen die physische
Identität von Quelle und Ziel prüfen. Bestehende Pfade kanonisieren,
Symlinks und `.` auflösen und die Gleichheits-/Verschachtelungsprüfung
auf diese Pfade anwenden. Die Prüfung sollte auch die ausführende
Verlegefunktion absichern.

**Regression:** Gleiches Verzeichnis über Symlink und über eine
`.`-Komponente auswählen; beide Abläufe müssen vor jedem Schreib- oder
Löschschritt abgewiesen werden. Konfiguration, Savegame und Bestenlisten
müssen unverändert bleiben.

### RESET-01: Der vollständige Reset vergisst `highscore-versus`

**Stelle:** `rowhammer.sh:1027-1043` (`reset_run`).

Der Zweig `highscore` enthält alle sechs Bestenlisten. Der Zweig `all`
enthält nur fünf: `HSV_FILE_NAME` fehlt. Dadurch bleiben
Mehrspieler-Ergebnisse nach einem vermeintlich vollständigen Reset erhalten.
Gleichzeitig wird das Demo-Verzeichnis zurückgesetzt, sodass die verbliebenen
Versus-Einträge ihre zugehörigen Aufnahmen verlieren können.

**Nachweis:** In einem temporären Datenverzeichnis wurden alle sechs
Bestenlistendateien angelegt. Der echte Aufruf
`rowhammer.sh --data-dir <temp> --reset all --force` endete mit Status 0.
Die fünf Singleplayer-Listen wurden in Backups verschoben;
`highscore-versus` blieb als aktive Datei stehen.

**Korrektur:** `HSV_FILE_NAME` in den Zweig `all` aufnehmen; idealerweise
die gemeinsame Dateiliste aus einer zentralen Definition ableiten.

**Regression:** Alle Reset-Dateien und `demos` vorgeben. Nach `--reset all`
darf keine dieser aktiven Dateien beziehungsweise das aktive Demo-Verzeichnis
mehr vorhanden sein; für jedes vorhandene Element muss ein Backup existieren.

### SP-01: Der gewählte Rundenname erreicht den Demo-Header nicht

**Stellen:** `rowhammer.sh:1829-1834, 1848-1862, 1975`;
`lib/demo.sh:1161-1162, 1221-1224`.

`record_round` übernimmt den Namen aus dem Abschlussdialog.
`round_book(name)` verwendet ihn für Bestenliste und Runden-Hash.
`demo_record_finish` bekommt hingegen nur Ende und Hash und schreibt
weiterhin `name=${PLAYER_NAME}` in den Header.

**Nachweis:** Die tatsächliche Funktion `round_book Alice` wurde mit
`PLAYER_NAME=Player` und dem echten Demo-Writer ausgeführt.
Der Bestenlistenadapter erhielt `Alice`; die gespeicherte Aufnahme
enthielt `name=Player`. Der Hash verbindet die Dateien weiterhin,
aber die Personenangabe widerspricht dem gebuchten Rundennamen.

**Korrektur:** Den tatsächlich gebuchten Namen an den Writer übergeben
und im Header verwenden. Bei Versus-Aufnahmen die Sitzungsnamen in
`peer=` weiterhin als eigenständige Angaben behandeln.

**Regression:** Eine platzierte Runde unter einem vom Einstellungsnamen
abweichenden Namen abschließen; Bestenliste, Hash-Verknüpfung und
Demo-Header gemeinsam prüfen.

### SP-02: Die Spieluhr übernimmt Sprünge der verstellbaren Systemzeit

**Stellen:** `rowhammer.sh:1495-1503, 1606-1610, 1649-1657, 2885-2920`;
`lib/demo.sh:650-661, 748-760`.

`now_ms` verwendet `EPOCHREALTIME` oder `date +%s%N`.
`play_clock_tick` addiert die Differenz zu `PLAY_LAST` ungeprüft.
Ein Rücksprung kann `PLAY_MS` negativ machen; ein Vorwärtssprung
kann Zeitlimits, Hochwasser, Gravity und Lock Delay vorzeitig auslösen.
Die Rücksprungbehandlung einzelner Anzeige-/Animationsfunktionen schützt
die zentrale Spieluhr nicht.

**Nachweis:** Mit der echten `play_clock_tick`-Funktion und einer
kontrollierten Uhr: `PLAY_MS=1000`, `PLAY_LAST=10000`,
nächster Zeitwert `8000` → `PLAY_MS=-1000`.
Der anschließende Zeitwert `600000` führte zu `PLAY_MS=591000`.
Die Systemzeit des Testsystems blieb unverändert.

**Korrektur:** Verstrichene Zeit und Fristen auf einer monotonen Zeitbasis
führen; Kalenderzeit nur für Datum und Dateinamen verwenden.
Bei einer Ersatzlösung müssen Vorwärts- und Rückwärtssprünge gemeinsam
für Spieluhr, Rundenuhr und Fristen behandelt werden.

**Regression:** Deterministische Uhrsprünge in laufenden Sprint-,
Time-Attack- und Hochwasser-Runden sowie während eines Lock Delays einspeisen.
Spielzeit darf nicht rückwärts laufen oder einen Uhrsprung als gespielte
Zeit buchen.

### MP-03: Warten nach dem eigenen Top-out verlängert die gebuchte Spielzeit

**Stellen:** `rowhammer.sh:1990-2025, 2777-2784, 2811-2819`;
`rowhammer.sh:1606-1610`.

Nach dem Top-out ist `GAME_OVER=1`. Der normale Game-Loop zählt für
diesen Spieler keine weitere Zeit, verarbeitet aber weiter die Nachrichten
der anderen Teilnehmer. `PLAY_LAST` bleibt dabei auf dem letzten
aktiven Spielzeitpunkt stehen. Beim späteren `END` führt der Loop
unbedingt noch einmal `play_clock_tick` aus und bucht dadurch die gesamte
Wartezeit nach.

Das trifft besonders Sprint-/Ultra-Sitzungen oder Survival-Runden mit
mindestens drei Spielern: Die übrigen Teilnehmer können nach dem eigenen
Ausscheiden noch lange weiterspielen. Bestenliste, Gesamtstatistik,
Ablegerate und Demo-Feld `time=` verwenden anschließend die vergrößerte
Spielzeit. `length=` ist für die Dauer der gesamten Aufnahme bereits
separat vorgesehen.

**Nachweis:** Die echte Funktion `game_run` wurde mit einem bereits
ausgeschiedenen Spieler (`PLAY_MS=10000`, `PLAY_LAST=10000`) gestartet.
Ein Transportadapter lieferte `END` beim Uhrwert `60000`.
Der Buchungsadapter erhielt `PLAY_MS=60000` statt der eingefrorenen
`10000`.

**Korrektur:** Die persönliche Spielzeit beim Top-out finalisieren und
danach eingefroren lassen. Beim Sitzungsende nur für einen bis dahin
aktiven Spieler den letzten Zeitabschnitt buchen; die gesamte Rundendauer
weiter separat ermitteln.

**Regression:** Drei Spieler, eigener Top-out nach zehn Sekunden,
Rundenende nach einer Minute. Persönliche Spielzeit und Statistiken
müssen zehn Sekunden, die Demo-Gesamtlänge ungefähr eine Minute ergeben.

### MP-04: Die Zahlen-Whitelist verhindert keine Oktalinterpretation

**Stellen:** `lib/proto.sh:87, 278-281, 354-360`;
`lib/hub.sh:974-979, 1114-1119`;
`lib/mp.sh:453-464`.

`PROTO_NUM_RE` akzeptiert Zahlen mit führenden Nullen.
`proto_parse` gibt sie unverändert an die Handler weiter.
Bash-Arithmetik interpretiert solche Werte als Oktalzahlen.
Damit stimmen die dezimalen Vergleiche mit `test` und die anschließende
Arithmetik nicht überein.

**Nachweis:** `proto_parse 'APPLIED 010'` akzeptierte die Nachricht.
Mit `HUB_PENDING[0]=20` setzte der echte `hub_msg_applied 0` die
Warteschlange auf `12` statt auf `10`.
`APPLIED 08` und `CLEAR 1 08 0` wurden ebenfalls vom Parser akzeptiert,
lösten im jeweiligen Handler aber „value too great for base“ aus.
Dies ist kein Nachweis einer vollständigen Hub-Abschaltung; bestätigt
sind falsche Queue-Arithmetik und ein Abbruch des betroffenen Handlers.
Die normalen Clients senden unaufgefüllte Zahlen, aber die Empfangsseite
soll auch fremde Protokollnachrichten validieren.

**Korrektur:** Zahlenfelder nach erfolgreicher Formprüfung zentral in
Dezimalzahlen normalisieren (`10#`) oder führende Nullen mit einer
kanonischen Zahlenregel ablehnen. Die Entscheidung muss für sämtliche
numerischen Nachrichtentypen gelten.

**Regression:** Nicht nur den Parser, sondern auch die Handler mit
`0`, `8`, `08`, `010` und der maximal zulässigen Zahl testen.
Zulässige Eingaben müssen dezimal wirken; abgelehnte Eingaben dürfen
weder Zustand ändern noch Arithmetikdiagnosen erzeugen.

### DEMO-01: Writer und Loader widersprechen sich bei Sitzen ohne Ereignis

**Stellen:** `lib/demo.sh:1175-1180, 1247-1251, 1269-1274, 1934-1950`.

Der Writer speichert eine Versus-Aufnahme, sobald die gemeinsame
temporäre Ereignisdatei nicht leer ist. Er führt alle benannten Sitze
im Header auf, ohne zu prüfen, ob jeder Sitz bereits ein Ereignis hat.
Der Loader verlangt hingegen für jeden benannten Sitz mindestens ein
Ereignis.

Ein besetzter Sitz ohne Ereignis ist nach einem sehr frühen lokalen
Abbruch möglich: Ein Spieler hat sich bereits bewegt, ein anderer noch
nicht, und die Aufnahme endet vor dessen erstem Gravity-Schritt oder
vor dem Eintreffen seines Zugfensters. Der Sitz hat trotzdem einen
gültigen Anfangszustand und gehört zur Runde.

**Nachweis:** Der echte Writer wurde mit drei besetzten Sitzen,
`MP_WINNER=-1` und Ereignissen nur für Sitze 0 und 1 ausgeführt.
Er speicherte eine Datei mit allen drei `peer=`-Zeilen.
Der echte `demo_load` lehnte genau diese Datei mit
`slot 2 has no events` ab.

**Korrektur:** Den gemeinsamen Vertrag festlegen: Ein gültiger Sitz ohne
Bewegung sollte aus seinem Anfangszustand wiedergegeben werden können.
Alternativ muss der Writer unvollständige Aufnahmen vor dem Speichern
verwerfen und das erkennbar behandeln. Besetzte Sitze einfach aus dem
Header zu entfernen würde die tatsächliche Teilnehmerliste verfälschen.

**Regression:** Eine Runde mit mehreren Sitzen vor dem ersten Ereignis
eines Peers abbrechen; jede tatsächlich gespeicherte Aufnahme muss
anschließend von `demo_load` akzeptiert werden.

## Korrektur der bisherigen Review-Aussagen

| Alter Befund | Aktueller Status | Beleg im geprüften Code |
| --- | --- | --- |
| Mehrspieler-Finding 1: verspätete PEERACT-Ereignisse hinter Hub-Ereignissen | Der beschriebene normale Empfangspfad ist seit 2.0.2 korrigiert | `demo_slot_hub_event` hält fremde Hub-Ereignisse zurück; `demo_record_peer_act` verarbeitet `y/q`-Empfangsmarker über `demo_hold_mark`. Der Empfangszeitpunkt des betroffenen Spielers bestimmt damit die Position im Stream. |
| Mehrspieler-Finding 2: fehlendes ROSTER verursacht falschen Top-out | Behoben seit 1.4.1 / Protokoll 5 | `hub_eliminate` sendet die Ursache mit `KO`; `mp_handle` reicht sie an `demo_record_ko(slot, place, state)` weiter. Die alte `demo_ko_flush`-Logik existiert nicht mehr. |
| SP-01: unterschiedlicher Runden-/Demo-Name | Weiterhin offen und jetzt reproduziert | Siehe SP-01 oben. |
| SP-02: Systemuhrsprünge | Weiterhin offen und jetzt reproduziert | Siehe SP-02 oben. |

Die Marker-Lösung besitzt weiterhin einen ausdrücklich vorgesehenen
Fallback: Nach `DEMO_HOLD_MS=2000` beziehungsweise beim Abschluss werden
nicht zugeordnete Hub-Ereignisse mit ihrer Empfangszeit freigegeben.
Die Bewertung des früheren Finding 1 bedeutet daher keine Garantie für
beliebig verspätete oder fehlende Zugfenster; dessen alte Beschreibung
als sofortiges Schreiben jedes Hub-Ereignisses entspricht aber nicht
mehr dem aktuellen Code.

## Durchgeführte Prüfungen und Grenzen

| Prüfung | Ergebnis |
| --- | --- |
| `bash -n` über alle 33 Shell-Dateien | bestanden |
| `tools/state-check.sh` | 68 Prüfungen bestanden |
| `tools/demo-keys.sh` | 31 Prüfungen bestanden |
| `python3 tools/display-check.py` | 7 Tests bestanden |
| `python3 tools/multiplayer-check.py` | 19 Tests bestanden |
| `tools/key-scan.sh --silent` | 72 Sequenzen, keine falsche Aktion oder durchgereichte inerte Taste |
| `tools/key-scan.sh --gap 0.06 --silent` | 69 Sequenzen, keine falsche Aktion oder durchgereichte inerte Taste |
| `tools/net-fuzz.sh --random 400` | 620 Fälle bestanden |
| `tools/release.sh --mode check` | Exit-Status 0 |
| `make install` in temporäres Staging, danach `--help` über den installierten Symlink | bestanden |
| Gezielte Funktions-/CLI-Reproduktionen der sieben offenen Befunde | oben beschrieben |

`tools/hub-check.sh` wurde aufgerufen, übersprang seine Sitzungsprüfungen
aber mangels `socat` und meldete dennoch Exit-Status 0. Das zählt hier
ausdrücklich **nicht** als bestandener Hub-Integrationstest.
ShellCheck war ebenfalls nicht verfügbar. Ein interaktiver vollständiger
Spiellauf, reale TCP-/Unix-Sitzungen sowie DEB-/RPM-Paketbauten wurden
in dieser Umgebung nicht durchgeführt.

Die bestehenden Prüfungen sind erfolgreich, decken die oben beschriebenen
Abläufe aber nicht ab. Geändert wurde ausschließlich dieser Bericht;
die offenen Fehler sind damit noch nicht im Spielcode behoben.
