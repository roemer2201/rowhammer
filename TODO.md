# TODO.md - rowhammer

Diese Datei fuehrt die **offenen** Punkte des Projekts: was noch gebaut
wird (Abschnitt 1) und was noch zu entscheiden oder nach Playtesting
nachzujustieren ist (Abschnitt 2).

**Wo steht was:**

| Datei | Inhalt |
| --- | --- |
| **TODO.md** (diese) | offene Punkte - Roadmap und Entscheidungen |
| [CLAUDE.md](CLAUDE.md) | technisches Konzept und Arbeitskonventionen |
| [HISTORY.md](HISTORY.md) | Archiv der erledigten Punkte, nach Version |
| [README.md](README.md) | Anleitung fuer Spielerinnen und Spieler |

Nackte Abschnittsnummern in dieser Datei ("siehe 5.20") verweisen auf
**CLAUDE.md**, wo das Konzept zum jeweiligen Punkt ausformuliert ist.
Ein Punkt wird hier nicht ausgeschrieben, wenn CLAUDE.md ihn schon
beschreibt - dann steht hier die Aufgabe und dort das Warum.

## Arbeitsregeln fuer diese Liste

Die verbindlichen Regeln stehen in [CLAUDE.md, Abschnitt 6](CLAUDE.md);
fuer diese Liste sind drei davon einschlaegig:

- **Ein erledigter Punkt wandert nach HISTORY.md**, samt seiner
  Begruendung - und wer ihn verschiebt, zieht CLAUDE.md 1-5 und (soweit
  spielersichtbar) die README nach.
- **Aenderungen an dieser Liste duerfen direkt auf `main`** vorgenommen
  werden, ohne Feature-Branch und Pull Request. Dasselbe gilt fuer
  HISTORY.md, soweit nur Erledigtes dorthin wandert.
- **`2.0.0` ist fuer den fertigen Mehrspieler reserviert.** Bis dahin
  laeuft alles unten in der **`1.x`-Reihe** - die offenen
  Einzelspieler-Punkte ebenso wie der Rest der Phase 5; eine
  Minor-Version je Zuwachs, eine Patch-Version je Korrektur. Die
  Server-Phase 6 beginnt hinter `2.0.0`.

## 1. Offene Roadmap-Punkte

Die abgeschlossenen Phasen 1 bis 4 sowie der Mehrspieler-Kern (Phase 5,
Schritte 1-8 und 10-12) stehen mit ihrer Begruendung in
[HISTORY.md](HISTORY.md); dessen Uebersichtstabelle listet jede Version
mit ihrem Thema.

### 1.1 Paketierung (`1.x.x`)

Debian-Paket (0.17.0), RPM-Paket (0.37.0) und die Release-Struktur samt
CI-Paketbau (0.40.0) sind erledigt. Offen:

- [ ] Lauffaehigkeit fuer abgespeckte Shells pruefen (z. B. `ash`/BusyBox
      auf OpenWrt/Embedded-Systemen); nur bei positivem Ergebnis den
      naechsten Punkt angehen.
- [ ] opkg-Paketierung implementieren (fuer OpenWrt/Embedded-Systeme,
      analog zur Debian-Paketierung, nutzt ebenfalls `make install`) -
      vorausgesetzt die Shell-Kompatibilitaetspruefung faellt positiv
      aus.
- [ ] Lizenz festlegen und `debian/copyright` aktualisieren. Daran
      haengt mehr als die beiden Dateien: solange es keine Lizenz gibt,
      werden die Release-Pakete bewusst unsigniert gebaut und es gibt
      keine oeffentliche Paketquelle (siehe 4.7, 4.9). Ein
      Signier-Schritt im Release-Workflow (Schluessel als Secret) waere
      der naechste Schritt, sobald die Lizenzfrage entschieden ist.

### 1.2 Politur (`1.x.x`)

- [ ] **Weltwunder-Animation** (Nutzerwunsch, Konzept in 5.18): Der
      Wunder-Bildschirm deckt die ASCII-Art bislang nur statisch
      zeilenweise auf. Kurze, von Hand aus asciinema-Voraufnahmen
      abgeleitete Frame-Tabellen sollen die Uebergaenge (neue Baustufe,
      Fertigstellung) mit einem Animationsschritt versehen, ueber das
      bestehende `FRAME_LINES`-Rendering (4.3) und ohne neue
      Abhaengigkeit. Gilt fuer den lokalen wie den spaeteren
      serverweiten Wunder-Bildschirm (5.17) gleichermassen und ist damit
      unabhaengig von Phase 6 umsetzbar.

### 1.3 Mehrspieler (Phase 5, `1.x.x`)

Der Kern laeuft seit 1.1.0, der Gastgeberwechsel seit 1.2.0, die
Sitzordnung mit fuenf Spielern seit 1.3.0 (siehe Abschnitt 5). Offen
sind zwei Punkte:

- [ ] **Schritt 9 - Demo-Aufzeichnung der Mehrspieler-Runde**
      (Zielanforderung und Architektur in 5.20). Vollausbau: die Zuege
      aller Teilnehmer werden verteilt und mitgeschrieben, die
      Wiedergabe simuliert alle Felder gleichzeitig, und der Fokus
      wechselt waehrend der Wiedergabe frei mit den Pfeiltasten.
      **Stand:** die Teilschritte 9.1 bis 9.10 sind erledigt (siehe
      HISTORY.md) - eine Runde wird aufgezeichnet, wieder gelesen, und
      beim Abspielen spielt jeder Sitzplatz seine Runde wirklich noch
      einmal. Es fehlen die Bedienung, der Kasten am Ende und die
      Gegenprobe.
      **Gesamtabnahme:** die Wiedergabe einer Vier-Spieler-Runde zeigt
      fuer jeden der vier denselben Verlauf wie die Runde selbst, in
      jeder Detailstufe aufgenommen, und laesst sich waehrend des Laufs
      zwischen ihnen umschalten.
      Die Version bleibt waehrend der Arbeit auf `1.3.0` und steigt erst
      mit Schritt 9.14 auf `1.4.0`.
  - [ ] **9.11 Wiedergabe: Fokuswechsel.** Pfeiltasten waehlen den Slot,
        Tempo auf `-`/`+`, HUD-Zeile nennt beides, `RENDER_FULL` beim
        Wechsel. Abnahme: waehrend des Laufs umschalten; das gewaehlte
        Feld steht mittig mit HUD, Hold und Next.
  - [ ] **9.12 Rundenende.** Ausscheiden, Verbindungsverlust und Sieger
        in der Anzeige, Platzierung im Kasten (er hat genau acht
        Innenzeilen - die fuehrende Leerzeile bezahlt sie), `end=lost`
        mit eigenem Text. Abnahme: der Kasten nennt Platz und Grund,
        alle vier `end`-Werte sehen richtig aus.
  - [ ] **9.13 Gegenprobe und Randfaelle.** Simulation gegen die
        `v=`-Pruefpunkte mit Meldung ins Debug-Log; Verbindungsverlust,
        Aufnahme aus Detailstufe 0/1, Sperre bei pausierter Runde,
        EXIT-`trap`, Verknuepfung aus der Versus-Bestenliste ueber den
        Runden-Hash. Abnahme: eine Vier-Spieler-Aufnahme laeuft ohne
        eine einzige Abweichungsmeldung durch.
  - [ ] **9.14 Doku, Texte, Version.** 5.20 auf den gebauten Zustand,
        4.10 (Format 3), 5.4 (Protokoll 4), 5.6 (Fokus), 4.1 (Bash) und
        diese Liste nachziehen; README, Anleitungsseiten 9 und 10;
        Punkt nach HISTORY.md; Version `1.4.0` an allen vier Stellen
        samt Changelog-Strophen. Abnahme: `tools/release.sh --mode
        check` ist gruen.

- [ ] **Rest aus Schritt 1 - Entkopplung der Rundenlogik** (siehe 5.3).
      Der Mehrspieler brauchte davon nur, was er benutzt, und laeuft
      damit; vollstaendig entkoppelt ist die Rundenlogik aber nicht:
      `flash_rows` haelt den Loop weiterhin an (es leert im Mehrspieler
      immerhin die Leitung mit) und `record_round` verbucht und zeigt
      noch in einem. Das ist Aufraeumarbeit ohne sichtbare Wirkung und
      steht deshalb hinter allem anderen. `2.0.0` ist dem Stand nach
      dieser Entkopplung vorbehalten.

### 1.4 Server-Betrieb, Accounts, Web (Phase 6, `2.x.x`)

Spezifiziert in 5.11 bis 5.19, noch nicht umgesetzt. Diese Phase beginnt
hinter `2.0.0` und setzt einen fertigen, per Playtesting bewaehrten
Mehrspieler-Kern voraus. Die Reihenfolge ist in 5.11-5.19 begruendet:
Deployment zuerst (ohne Server kein Bedarf fuer Accounts), Accounts vor
dem Persistenz-Umbau (das Datenbankschema haengt vom Kontomodell ab),
serverweite Statistik und gemeinsames Weltwunder direkt danach (sie
brauchen nur Accounts und die Datenbank und lassen sich vor der Webseite
fertig testen), Web-Frontend, Kontoverknuepfung und Abzeichen
anschliessend, Liga und Multi-Server zuletzt.

- [ ] **Schritt 1 - SSH-ForceCommand-Deployment** (siehe 5.11).
      `sshd_config`/`authorized_keys`-Vorlage mit `ForceCommand` bzw.
      `command=`, Haertung (`no-port-forwarding` usw.), eigener
      Systembenutzer, Rechte auf `${DATA_DIR}`/`${MP_DIR}` geprueft.
      Laeuft zunaechst weiter mit freiem Login (siehe 5.12).
      Abnahme: mehrere SSH-Sitzungen landen direkt im Spiel, keine Shell
      erreichbar.
- [ ] **Schritt 2 - Konto-Grundlage: SSH-Key-Bindung** (siehe 5.12).
      Spielkonto an SSH-Public-Key-Fingerprint gebunden, Erstanmeldung
      fragt Kontonamen ab, Namensmuster wie 5.5. Noch ohne Passwort-
      oder OAuth-Login. Abnahme: derselbe Key wird bei jeder Sitzung
      demselben Konto zugeordnet, ein fremder Key kann einen belegten
      Namen nicht kapern.
- [ ] **Schritt 3 - Server-Persistenz auf SQLite umstellen** (siehe
      5.13). Highscore, Stats und Konten in SQLite-Tabellen statt
      Flatfiles, `sqlite3`-Zugriff aus Bash mit gebundenen Parametern,
      Migration der Formate ohne Altdaten-Uebernahme (Arbeitsregel
      "keine Abwaertskompatibilitaet", CLAUDE.md 6). Abnahme:
      identisches Verhalten wie die bisherigen Flatfiles, aber per SQL
      abfragbar (z. B. Rang eines Kontos ueber alle Runden).
- [ ] **Schritt 4 - Erweiterte Server-Highscore-Liste** (siehe 5.13).
      Laengere Liste (mehr als Top 10), Filter/Suche nach Konto,
      weiterhin im Spiel ueber "Highscores" abrufbar. Abnahme: die Liste
      bleibt bei vielen Konten performant und uebersichtlich
      (seitenweise wie heute, siehe 4.5).
- [ ] **Schritt 5 - Serverweite Statistik** (siehe 5.16).
      Kontounabhaengiger Aggregat-Zaehler zusaetzlich zum
      Account-Eintrag bei jeder verbuchten Runde (`server_stats`), neuer
      Menuepunkt "Server-Statistik". Abnahme: der Zaehler summiert
      sichtbar ueber mehrere Accounts hinweg korrekt auf, unabhaengig
      von Highscore und persoenlicher Statistik.
- [ ] **Schritt 6 - Gemeinsamer Weltwunder-Fortschritt** (siehe 5.17).
      Zusaetzlicher serverweiter Reihenzaehler mit eigener, deutlich
      groesserer Kostentabelle (`SERVER_WONDER_COSTS`), zweiter
      Wunder-Bildschirm fuer den Server-Fortschritt. Abnahme: Reihen
      mehrerer Accounts zahlen sichtbar auf denselben Server-Fortschritt
      ein, der Account-eigene Fortschritt bleibt davon unberuehrt.
- [ ] **Schritt 7 - Web-Highscore (read-only)** (siehe 5.14).
      Separates, schlankes Web-Backend liest die Datenbank aus Schritt 3
      und zeigt Highscore und Statistik (inklusive der Server-Statistik
      aus Schritt 5) im Browser. Kein Schreibzugriff vom Web aus.
      Abnahme: die Highscore-Liste ist ohne SSH-Zugang einsehbar.
- [ ] **Schritt 8 - OAuth-Kontoverknuepfung** (siehe 5.12, 5.14).
      Login mit Google/Apple/Facebook & Co. auf der Webseite, Anzeige
      eines kurzlebigen Verknuepfungscodes, Eingabe im Spiel
      ("Konto verknuepfen") bindet SSH-Key und Web-Identitaet an
      dasselbe Konto. Abnahme: die Anmeldung ueber einen der Anbieter
      fuehrt zum selben Spielkonto wie der bisherige SSH-Key-Login.
- [ ] **Schritt 9 - Account-Abzeichen** (siehe 5.19).
      Feste Abzeichen-Liste mit pruefbaren Bedingungen, Freischaltung
      bei `record_round`, Anzeige im Account-Bereich und spaeter auf der
      Highscore-Webseite. Abnahme: ein erfuelltes Kriterium schaltet das
      passende Abzeichen zuverlaessig und dauerhaft frei.
- [ ] **Schritt 10 - Liga-System** (siehe 5.14).
      Saisons und Ranglisten oberhalb der Highscore-Liste; die Regeln
      sind noch offen (siehe 2.3), erst nach Playtesting des
      Mehrspieler-Kerns und im Zusammenspiel mit den Abzeichen aus
      Schritt 9 zu konkretisieren.
- [ ] **Schritt 11 - Multi-Server-Faehigkeit** (siehe 5.14).
      Mehrere Spiel-Server gegen ein gemeinsames Accounts- und
      Highscore-Backend, Kontosynchronisation ueber Server-Grenzen
      hinweg. Abnahme: ein Konto behaelt Highscore und Einstellungen
      beim Wechsel des Servers.

## 2. Offene Entscheidungen und Justierungen

Alles hier ist **keine** Bauaufgabe, sondern eine Frage, die vor oder
waehrend der zugehoerigen Arbeit zu beantworten ist. Was bereits
entschieden **und** umgesetzt ist, steht nicht hier, sondern als
Festlegung samt Begruendung in CLAUDE.md 3 bis 5.

### 2.1 Spielbalance (nach Playtesting)

Alle Werte sind justierbare Konstanten - sie gehoeren zum Spielgefuehl
und werden nach Playtesting nachgezogen, nicht je Runde gewaehlt.

- [ ] **Weltwunder-Kosten** (`WONDER_COSTS`, `lib/wonders.sh`, siehe
      3.3): Die Reihe 10.000..640.000 liegt seit 0.44.0 in der
      Groessenordnung des Originals. Offen ist die Feinjustierung.
- [ ] **Ziele der Zeitmodi** (`ULTRA_TARGET_ROWS`, `SPRINT_TIME_MS`,
      `TIME_ATTACK_START_MS`/`TIME_ATTACK_ROW_MS`, siehe 3.6): Sind 150
      Rows die richtige Distanz, 3 Minuten die richtige Dauer und
      1 Minute Startzeit bei 1 Sekunde je Row die richtige Waehrung?
      Mit den Quadrat-Boni ist die Ultra-Strecke deutlich kuerzer als
      150 physische Reihen - das ist so gewollt, und aus demselben Grund
      verlaengert ein Rowhammer durch zwei Gold-Quadrate eine
      Time-Attack-Runde gleich um 85 Sekunden.
- [ ] **Flut-Abstand des Hochwasser-Modus** (`FLOOD_INTERVAL_MS`, siehe
      3.6): 20 Sekunden je Flutreihe sind eine Nutzervorgabe "vorerst";
      ob das auf Dauer die richtige Steigung ist, entscheidet
      Playtesting.
- [ ] **Garbage-Werte des Mehrspielers** (`GARBAGE_*`, `lib/hub.sh`,
      siehe 5.7): 0/1/2/4 Reihen, +2 je Silber-, +4 je Gold-Quadrat,
      Deckel 10. Sie sind aus der Reihenwertung abgeleitet und nicht aus
      dem Original - "The New Tetris" hat keinen vergleichbaren
      Versus-Modus. Bislang nur gerechnet, nicht gespielt.

### 2.2 Mehrspieler

- [ ] **Zielwahl ab 3 Spielern** (siehe 5.7): Standard ist `random`. Ob
      eine **manuelle** Zielauswahl per Taste gewuenscht ist, bleibt
      offen - die Tastenbelegung ist voll und die Bedienung skaliert
      schlecht.
- [ ] **Fuenf Spieler auf schwacher Hardware** (siehe 5.1, 5.6):
      Gemessen wurde bisher gegen Test-Bots auf einem Rechner, nicht in
      einem Raum voller Terminals. Die volle Zellenbreite verdoppelt die
      Zeichenmenge je Gegnerfeld - dort wird es zuerst auffallen.
- [ ] **Weitere Sitzungsmodi** (siehe 5.1): `survival`, `sprint` und
      `ultra` sind die drei, die sich in der Siegbedingung
      unterscheiden. Ob nach Playtesting einer dazukommt oder wegfaellt,
      ist offen.
- [ ] **Kein Reconnect in v1** (siehe 5.8): Haeufen sich Abbrueche im
      Alltag, waere ein Wiedereinstieg mit vollstaendiger
      Zustandsuebertragung ein eigener spaeterer Punkt.

Bewusst **kein** offener Punkt: vollstaendige Cheat-Sicherheit. Der Hub
ist autoritativ fuer Garbage-Mengen, Lochspalten, KO-Reihenfolge und
Rundenende; ein manipulierter Client kann weiterhin falsche
`CLEAR`-Meldungen abgeben. Eine serverseitige Vollsimulation ist kein
Ziel (siehe das Vertrauensmodell in 5.5) - die dortigen
Sicherheitsregeln zum Schutz von Prozess und Terminal sind dagegen nicht
verhandelbar.

### 2.3 Server-Betrieb (Phase 6)

Fuenf Empfehlungen stehen in CLAUDE.md ausformuliert und warten auf
Bestaetigung, bevor der jeweilige Roadmap-Schritt beginnt:

- [ ] **Kontomodell** (5.12): Empfehlung ist ein vom SSH-Login
      entkoppeltes Spielkonto, gebunden an den SSH-Key-Fingerprint -
      **keine** Unix-Accounts je Spieler.
- [ ] **Backend-Sprache** (5.15): Empfehlung ist, Spiel-Engine und
      lokales Mehrspieler-Protokoll bei Bash zu belassen und fuer Web,
      Liga und Multi-Server einen schlanken separaten Dienst in einer
      HTTP-/JSON-/DB-tauglicheren Sprache vorzusehen. Die Sprache selbst
      ist offen.
- [ ] **Server-Persistenz** (5.13): Empfehlung ist SQLite als
      Zwischenschritt vor einem eigenstaendigen Datenbankserver (der
      erst bei Multi-Server-Bedarf relevant wird, 5.14).
- [ ] **Serverweites Weltwunder** (5.17): Nutzervorschlag, zu
      bestaetigen. Offen dabei: eigene, groessere Wunder-Liste oder
      dieselbe Liste mit hoeherer Kostentabelle
      (`SERVER_WONDER_COSTS`); und ob ein fertiggestelltes
      Server-Wunder allen verbundenen Clients angekuendigt wird.
- [ ] **Account-Abzeichen** (5.19): Nutzerwunsch. Offen sind die
      konkrete Abzeichen-Liste und ihre Bedingungen sowie das
      Verhaeltnis zum spaeteren Liga-System.
- [ ] **Liga-Regeln** (5.14): vollstaendig offen - Saisonlaenge,
      Punkteverfall, Ranglisten je Spielmodus.

### 2.4 Sonstiges

- [ ] **Weitere Sprachen** (siehe 4.11): Deutsch und Englisch sind da,
      technisch ist eine weitere Sprache eine Datei unter `lib/lang/`
      plus ein Eintrag in `I18N_LANGS`. Ob welche dazukommen sollen, ist
      offen.
- [ ] **Weg der Weltwunder-Animation** (siehe 5.18, Bauaufgabe in 1.2):
      eigener `.cast`-Player zur Laufzeit oder eine von Hand aus einer
      asciinema-Voraufnahme abgeleitete Frame-Tabelle. Letzteres ist der
      Vorschlag, weil es ohne neue Abhaengigkeit auskommt.
- [ ] **Punktesystem-Feinschliff** (Kombos, Back-to-Back): Nach dem
      Umbau in 0.16.0 zaehlen ausschliesslich abgebaute Reihen (siehe
      3.2). Solche Extras waeren eine bewusste Abweichung vom Konzept
      "Punkte = Reihenwertung" und nur nach ausdruecklicher
      Nutzerentscheidung wieder aufzugreifen.

## 3. Externe Review

[MISTRAL.md](MISTRAL.md) ist eine Code-Review von Mistral AI vom
30. Juli 2026 mit rund fuenfzig Vorschlaegen. Sie ist eine **fremde
Momentaufnahme und wird nicht gepflegt**: viele ihrer Punkte sind
inzwischen umgesetzt (Farbschemata und Monochrom-Modus, das
Datenverzeichnis unter `~/.config`, RPM-Paketierung, konfigurierbare
Tastenbelegung, Spielmodi, Demo-Aufzeichnung, Netzwerk-Mehrspieler),
andere widersprechen bewusst getroffenen Entscheidungen dieses Projekts.
Ihre Haken bleiben deshalb ungesetzt.

Wer etwas daraus aufgreifen will, traegt es als eigenen Punkt in die
Listen oben ein - dann gilt dafuer, was fuer jeden anderen Punkt gilt.
