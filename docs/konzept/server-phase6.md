# rowhammer - Konzept: Geplanter Server-Betrieb, Phase 6 (5.11 bis 5.19)

Teil des technischen Konzepts von rowhammer. Die Abschnittsnummern sind
die aus [CLAUDE.md](../../CLAUDE.md) und bleiben stabil
(Arbeitsregel 6.1): ein Verweis der Form `CLAUDE.md 5.13` im Code meint
den gleichnamigen Abschnitt hier. Die Datei fuehrt den **aktuellen**
Stand samt seiner Begruendung; was abgeloest wurde, steht in
[HISTORY.md](../../HISTORY.md), was noch fehlt, in
[TODO.md](../../TODO.md).

---

**Ab hier: Phase 6 - der geplante Server-Betrieb.** Die folgenden neun
Unterabschnitte (5.11 bis 5.19) beschreiben **Absichten**, nicht
Gebautes: einen dedizierten Spiel-Server, Accounts, Server-Persistenz,
Web-Highscore und was daran haengt. Sie setzen einen fertigen,
per Playtesting bewaehrten Mehrspieler-Kern voraus. Die Arbeitsschritte
dazu stehen in [TODO.md](../../TODO.md), die noch offenen Grundsatzfragen
ebenfalls (dort Abschnitt 2.3). 5.20 gehoert wieder zu Phase 5 und
steht nur deshalb dahinter, damit diese Nummerierung stabil bleibt.

### 5.11 Deployment: dedizierter Server mit SSH-ForceCommand

- **Zielbild (Nutzerentscheidung):** rowhammer laeuft nicht nur
  gelegentlich auf einer Maschine mit, auf der ohnehin mehrere Leute
  eingeloggt sind (das urspruengliche Szenario aus 5.2), sondern es gibt
  einen **dedizierten Spiel-Server**. Spieler verbinden sich per SSH; ein
  `ForceCommand` in `sshd_config` (bzw. `command="..."` vor dem Key in
  `authorized_keys`, praeziser pro Nutzer) startet direkt `rowhammer.sh`
  statt einer freien Shell. Die Transport- und Prozessarchitektur aus
  5.2/5.3 (Unix-Socket, Hub/Bridge/Client) bleibt dabei unveraendert
  gueltig - ForceCommand entscheidet nur, *wie* ein Client-Prozess
  gestartet wird, nicht *wie* er mit dem Hub redet.
- **Sicherheitsgewinn und -grenzen:** Eine per ForceCommand erzwungene
  Sitzung ist kein Ersatz fuer die Regeln aus 5.5, aber eine zusaetzliche
  Huerde: ein Spieler bekommt gar keine Shell, sondern landet direkt im
  Spiel. Empfehlenswerte `sshd_config`/`authorized_keys`-Haerten (spaeter,
  vor Schritt 1 dieser Phase zu pruefen und festzuschreiben):
  `no-port-forwarding,no-X11-forwarding,no-agent-forwarding` (PTY bleibt
  noetig, das Spiel braucht ein Terminal), eigener Systembenutzer ohne
  Zugriff auf fremde Daten, restriktive Dateisystemrechte auf
  `${DATA_DIR}`/`${MP_DIR}` (siehe 4.5, 5.2). Ein ausbrechender Spieler
  darf ueber `rowhammer.sh` und seine Module (siehe 5.5) so wenig
  erreichen wie ueber die Shell, die ihm fehlt - das ist keine neue Regel,
  sondern die bestehende Regel aus 5.5 unter schaerferen Vorzeichen.
- **Ablauf fuer den Spieler:** SSH-Verbindung -> ForceCommand startet
  rowhammer -> (spaeter, siehe 5.12) Login/Identifikation -> Hauptmenue
  mit Mehrspieler-Lobby ("Spiel eroeffnen" / "Spiel beitreten", wie in
  5.10 beschrieben) -> Runde -> Rueckkehr ins Menue oder Verbindungsende.
  Fuer den Einzelspieler-Betrieb (lokal installiert, siehe 4.7) aendert
  sich nichts.

### 5.12 Accounts und Authentifizierung

- **Ausgangslage:** Ohne Accounts kann sich jeder einen beliebigen Namen
  geben (Missbrauchspotenzial: Namen faelschen, Highscore-Spam) und es
  gibt keinen Ort, an dem persoenliche Highscores, Tastenbelegung und
  Farbschema (heute lokal in `rowhammer.conf`, siehe 4.5) ueber
  verschiedene Server-Sitzungen hinweg ueberleben.
- **Entwicklungsphase (Nutzerentscheidung):** freier Login mit frei
  waehlbarem Namen bleibt bis auf Weiteres der Standard - identisch zum
  heutigen `--name`/`ROWHAMMER_PLAYER_NAME` (siehe 4.2). Ein konkretes
  Account-System wird erst nachgezogen, sobald ein oeffentlicher Server
  ansteht.
- **Empfehlung fuer das spaetere Account-System** (zu bestaetigen,
  siehe TODO.md 2.3): rowhammer-Accounts **nicht** eins-zu-eins auf
  Unix-Systembenutzer abbilden. Unix-Accounts je Spieler bedeuten
  Root-Rechte fuer jede Neuregistrierung, keinen Bezug zu
  Web-Identitaeten (Apple/Google/Facebook-Login ist ein Web-OAuth-Flow,
  keine Unix-Anmeldung) und ein Auseinanderlaufen von "wer darf sich per
  SSH verbinden" und "welchem Spielkonto das zugeordnet ist". Stattdessen:
  - **SSH-Zugang bleibt technisch getrennt vom Spielkonto.** Ob per
    einzelnem Systembenutzer je Spieler, einem gemeinsamen Spiel-Benutzer
    mit `command=`-eingeschraenkten `authorized_keys`-Eintraegen oder SSH
    Certificates entschieden wird, ist ein Ops-Detail und beeinflusst das
    Spielkonto nicht.
  - **Das Spielkonto ist Anwendungslogik** des neuen Server-Backends
    (siehe 5.13/5.15): Benutzername, Passwort-Hash (falls Passwort-Login
    gewuenscht) oder - einfacher und dem SSH-Kontext angemessener -
    Bindung an den bereits durch `sshd` geprueften SSH-Public-Key
    (Fingerprint als Kontoschluessel; kein zusaetzliches Passwort noetig,
    keine Passwort-Eingabe im Terminal, kein Passwort-Handling im Spiel).
    Erste Anmeldung eines unbekannten Keys fragt einen Kontonamen ab und
    legt das Konto an; ein bekannter Key wird automatisch erkannt.
  - **Verknuepfung mit Google/Apple/Facebook & Co. ist ein Web-Flow und
    gehoert auf die Webseite** (siehe 5.14), nicht in die
    Terminal-Sitzung: ein Browser-OAuth-Flow laesst sich in einer
    TTY-Sitzung nicht sauber abbilden. Vorschlag: der Spieler meldet sich
    auf der (spaeteren) Webseite per OAuth an, bekommt dort einen
    kurzlebigen Verknuepfungscode angezeigt und gibt diesen einmalig im
    Spiel ein (Menuepunkt "Konto verknuepfen"); das Backend ordnet danach
    SSH-Key und Web-Identitaet demselben Spielkonto zu.
  - Tastenbelegung und Farbschema (heute in `rowhammer.conf`, 4.5) werden
    mit dem Spielkonto **serverseitig** gespeichert, sobald eines
    existiert; lokal bleibt die Config-Datei der Fallback ohne Konto bzw.
    fuer die lokale Installation.
- **Missbrauchsschutz:** Namensmuster wie in 5.5 (`^[A-Za-z0-9_-]{1,16}$`)
  gelten unveraendert; ein Spielkonto aendert daran nichts, verhindert
  aber Namenskollisionen/-diebstahl, weil ein Name erst beim jeweiligen
  Konto reserviert ist.

### 5.13 Server-Persistenz und Highscore-Datenbank

- **Ausgangslage:** Die heutige Highscore-Liste (`lib/highscore.sh`, Top
  10, Flatfile, siehe 4.5) ist fuer einen Einzelspieler-Rechner gedacht.
  Ein Server mit vielen Konten braucht eine laengere, nach Konto
  durchsuchbare Liste; ab einer gewissen Groesse ist lineares
  Text-Parsing nicht mehr das richtige Werkzeug.
- **Empfehlung** (zu bestaetigen, siehe TODO.md 2.3): kein Sprung direkt auf einen separaten
  Datenbankserver. Ein guter Zwischenschritt ist **SQLite**: eine echte
  SQL-Datenbank, aber ein einzelner Dateipfad ohne eigenen Serverprozess,
  aus Bash ueber die `sqlite3`-Kommandozeile ansprechbar (neue optionale
  Abhaengigkeit analog `socat`, siehe 5.2/5.10) - der bestehende
  Bash-Stil (siehe 5.15) muss dafuer nicht verlassen werden. Migration
  der Flatfile-Formate (Highscore, Stats, Accounts) auf Tabellen gemaess
  der Arbeitsregel "keine Abwaertskompatibilitaet" (Abschnitt 6): kein
  Altdaten-Import noetig, nur ein sauberer Schnitt. Ein "richtiger"
  Datenbankserver (Postgres o. ae.) wird erst relevant, wenn
  Multi-Server-Betrieb (5.14) mehrere Prozesse/Hosts gegen dieselben
  Daten schreiben laesst - SQLite ist fuer nebenlaeufige Schreiber von
  mehreren Hosts aus nicht das richtige Werkzeug.
- **Sicherheit:** SQL-Statements werden ausschliesslich mit gebundenen
  Parametern gebaut (kein String-Zusammenbau aus Netz-/Spielerdaten in
  ein SQL-Kommando) - dieselbe Injektions-Vorsicht wie in 5.5 fuer
  Arithmetik und `eval`, nur auf SQL uebertragen.

### 5.14 Endausbaustufe: Web-Highscore, Liga-System, Multi-Server

Diese drei Punkte sind bewusst nur grob skizziert - sie stehen am Ende
der Roadmap (Phase 6, siehe TODO.md) und werden erst konkretisiert, wenn
Server-Deployment (5.11), Accounts (5.12) und Server-Persistenz (5.13)
stehen.

- **Web-Highscore:** eine schreibgeschuetzte Webseite, die dieselbe
  Datenbank (5.13) liest wie das Spiel schreibt. Kein Bash-Webserver
  (siehe 5.15) - ein schlankes, separates Web-Backend liest nur, das
  Spiel bleibt der einzige Schreiber.
- **Liga-System:** Saisons/Ranglisten oberhalb der reinen
  Highscore-Liste; Regeln (Saisonlaenge, Punkteverfall, Ranglisten je
  Spielmodus) sind noch offen und folgen erst nach Playtesting des
  Mehrspieler-Kerns (Phase 5) - ein Liga-System ohne stabile
  Mehrspieler-Wertung waere verfrueht.
- **Multi-Server-Faehigkeit:** mehrere Spiel-Server (je eigener
  Hub-Pool, eigenes `MP_DIR`, siehe 5.2), die gegen ein gemeinsames
  Backend fuer Accounts und Highscores sprechen. Setzt voraus, dass
  Accounts (5.12) und Persistenz (5.13) bereits serverunabhaengig sind -
  sonst muesste ein Spieler auf jedem Server ein eigenes Konto fuehren.

### 5.15 Backend-Technologie: Bash vs. andere Systeme

- **Frage:** Wird das serverseitige Backend (Accounts, Highscore-Web,
  Liga, Multi-Server) ebenfalls in Bash geschrieben, oder kommuniziert
  Bash mit einem in einer anderen Sprache geschriebenen Dienst?
- **Empfehlung** (zu bestaetigen, siehe TODO.md 2.3): kein Bruch,
  sondern eine klare Grenze entlang dessen, was Bash gut kann und was nicht:
  - **Spiel-Engine und lokale Mehrspieler-Sitzung bleiben Bash** - Hub,
    Bridge, Client, Protokoll (`lib/net.sh`, `lib/proto.sh`,
    `lib/hub.sh`, `lib/mp.sh`, siehe 5.3) sind bereits so entworfen und
    funktionieren lokal ueber Unix-Sockets gut; ein Sprachwechsel hier
    waere ein Neubau ohne Not.
  - **SSH/ForceCommand-Login und Konto-Bindung (5.12) bleiben Bash** -
    das ist im Kern derselbe Umgang mit Fremdeingaben wie das bestehende
    Protokoll und profitiert von denselben Regeln aus 5.5
    (Zeichensatzfilter, Whitelist, keine Injektion).
  - **Alles, was HTTP/TLS, JSON-APIs oder gleichzeitige Schreibzugriffe
    von mehreren Hosts braucht (Web-Highscore, Liga, Multi-Server-Sync,
    5.14), ist in Bash unangemessen aufwendig und fehleranfaellig**
    (kein sicheres TLS, keine echte Nebenlaeufigkeit, JSON-Parsing in
    Bash ist Bastelei). Dafuer ein schlanker, separater Dienst in einer
    Sprache mit vernuenftiger HTTP-/JSON-/DB-Unterstuetzung (Sprache
    selbst noch offen) - er liest/schreibt dieselbe Datenbank (5.13)
    bzw. bekommt Rundenergebnisse ueber einen schmalen, validierten
    Kanal vom Bash-Server zugestellt (analog der Bridge-Rolle in 5.3:
    ein kleiner Uebersetzer statt eines Sprachwechsels im Kern).
  - Damit bleibt die in 5.5 verbindliche Regel unangetastet, egal welche
    Sprache spaeter dazukommt: kein `eval`, keine Kommandosubstitution
    und keine Interpolation von Fremddaten in auszufuehrenden Code -
    weder in Bash noch im neuen Dienst (dort: keine dynamisch gebauten
    SQL-Strings oder Shell-Aufrufe aus Nutzereingaben, siehe 5.13).

### 5.16 Serverweite Statistik

- **Ausgangslage:** `lib/stats.sh` (4.5) fuehrt heute genau eine
  Statistik je Installation (lokal oder - nach 5.12 - je Account
  serverseitig gespeichert). Auf einem Mehrspieler-Server mit vielen
  Accounts fehlt ein Blick auf das Ganze: wie viele Reihen hat der
  Server insgesamt abgebaut, wie viele Gold-/Silberquadrate insgesamt,
  wie viele Rowhammer, wie viele Runden wurden gespielt.
- **Vorschlag:** ein zusaetzlicher, kontounabhaengiger Aggregat-Zaehler
  in der Server-Datenbank (5.13), der bei jedem `record_round` (siehe
  3.3, 4.5) neben dem Account-Eintrag mitgefuehrt wird (`server_stats`,
  dieselben Felder wie die persoenliche Statistik, dazu Anzahl aktiver
  Accounts und Anzahl gespielter Mehrspieler-Runden). Anzeige: neuer
  Menuepunkt "Server-Statistik" (nur im Server-Betrieb sichtbar - lokal
  entfaellt er mangels Server) analog zum bestehenden
  "Statistik"-Bildschirm (4.5), spaeter moeglicherweise auch auf der
  Web-Highscore-Seite (5.14).
- **Abgrenzung zur Wertung:** die serverweite Statistik ist reine
  Anzeige, kein Bestandteil von Highscore oder Account-Fortschritt -
  sie zaehlt nur mit, veraendert aber nicht die individuelle Wertung
  einer Runde.

### 5.17 Gemeinsamer Weltwunder-Fortschritt auf dem Server

- **Idee** (Nutzervorschlag, zu bestaetigen, siehe TODO.md 2.3): auf
  einem Server bauen nicht nur einzelne Accounts an ihrem eigenen
  Weltwunder (siehe 3.3, das bleibt fuer den lokalen
  Einzelspieler-Betrieb unveraendert bestehen), sondern **alle Spieler
  gemeinsam** zusaetzlich an einem serverweiten Weltwunder. Jede
  abgebaute Reihe jedes Accounts zahlt dann doppelt ein: auf den
  eigenen (Account-)Zaehler und auf einen gemeinsamen Server-Zaehler.
- **Konsequenz fuer die Kostentabelle:** Die bestehende
  `WONDER_COSTS`-Reihe (seit 0.44.0 10.000..640.000, insgesamt 1.270.000
  Reihen, siehe 3.3) ist auf einen einzelnen Spieler ausgelegt und waere
  von vielen
  gleichzeitig spielenden Accounts durchgespielt, lange bevor ein
  gemeinsames Wunder etwas Gemeinsames haette. Der
  Server-Fortschritt braucht deshalb weiterhin **eine eigene, deutlich
  groessere Kostentabelle** (`SERVER_WONDER_COSTS`) - die Umstellung in
  0.44.0 hat den Abstand nur verkleinert, nicht aufgehoben: sie bringt
  die Einzelspieler-Reihe erst auf die Original-Groessenordnung (2.500
  bis 500.000 Zeilen je Wunder, siehe 3.3), die Server-Reihe muss
  darueber liegen, je nach erwarteter Serverlast. Beide
  Tabellen nutzen dieselbe Wunder-Liste und -Logik (`lib/wonders.sh`),
  nur mit unterschiedlichem Kosten-Array und unterschiedlichem
  Zaehlerstand.
- **Anzeige:** der bestehende Weltwunder-Bildschirm bekommt im
  Server-Betrieb einen zweiten Bildschirm fuer den Server-Fortschritt
  (eigenes Bauwerk, eigene Baustufe); die Rundenwertung fuer den
  Account (Highscore, persoenliche Statistik, 4.5) bleibt davon
  unberuehrt.
- **Offen** (siehe TODO.md 2.3): ob der Server tatsaechlich eigene,
  groessere Wunder braucht (weitere, noch unverifizierte Bauwerke) oder
  dieselbe Liste nur mit anderen Kosten laufen soll; ob ein
  fertiggestelltes Server-Wunder ein sichtbares Server-Ereignis ist
  (Ankuendigung an alle verbundenen Clients, siehe Protokoll 5.4).

### 5.18 Weltwunder-Animation

- **Ausgangslage:** der Weltwunder-Bildschirm (3.3, seit 0.8.0
  umgesetzt) deckt die ASCII-Art zeilenweise von unten auf - statisch,
  ohne Bewegung. Nutzerwunsch: der Bildschirm soll "etwas mehr
  animiert" sein.
- **Vorschlag:** kurze **asciinema-Aufnahmen** (`.cast`-Dateien, wie
  bereits fuer die README-Democlips genutzt, siehe HISTORY.md, 0.19.0
  "README mit Screenshots/Asciinema aktualisieren") je Wunder-Uebergang, die beim
  Erreichen einer neuen Baustufe bzw. bei Fertigstellung eines Wunders
  einmalig abgespielt werden (z. B. ein kurzer Bau-Effekt oder ein
  Glanz-Effekt ueber der ASCII-Art). Zwei Umsetzungswege: entweder ein
  echter `.cast`-Player in Bash (Zeitstempel aus dem Cast-Format
  auswerten, neuer Formatparser) oder - einfacher und ohne neue
  Abhaengigkeit - eine kleine, von Hand aus einer asciinema-
  Voraufnahme abgeleitete Frame-Tabelle (analog den zwoelf
  Baustufen-Zeilen aus 3.3, nur als kurze Zwischenschritte statt eines
  Sprungs), abgespielt ueber das bestehende Rendering-Modell
  (`FRAME_LINES`, 4.3). Die Frame-Tabelle ist der einfachere und damit
  bevorzugte Weg; `asciinema rec` dient dabei nur als
  Entwicklungswerkzeug fuer die Vorschau, nicht als Laufzeitformat.
- **Geltungsbereich:** gilt fuer den lokalen Einzelspieler-Wunder-
  bildschirm ebenso wie fuer den serverweiten (5.17) - beide nutzen
  denselben Anzeige-Code (`wonder_screen`, `lib/wonders.sh`) und haben
  keine Server-Abhaengigkeit.
- **Nicht Ziel:** eine waehrend der laufenden Partie eingeblendete
  Animation (der Wunderbildschirm bleibt ein Bildschirm nach
  Rundenende bzw. ein Hauptmenuepunkt, siehe 3.3) - die Animation laeuft
  nur dort, nicht im HUD.

### 5.19 Account-Abzeichen (Achievements)

- **Nutzerwunsch:** persoenliche **Abzeichen** am Account, zusaetzlich
  zu Highscores und Statistiken (die es fuer den Account bereits gibt,
  siehe 5.12/4.5).
- **Vorschlag:** eine feste Liste von Abzeichen mit klaren, serverseitig
  bei jedem `record_round` pruefbaren Bedingungen (z. B. "erstes
  Rowhammer", "100 Gold-Quadrate insgesamt", "ein Wunder allein
  fertiggestellt", "am Server-Wunder mitgebaut" [5.17], "Sieger einer
  Mehrspieler-Runde", "1.000.000 Reihen Lebenszeit"). Jedes Abzeichen
  wird einmalig freigeschaltet und mit Datum am Account gespeichert
  (neue Tabelle in der Server-DB, siehe 5.13); ein Abzeichen wird nie
  wieder entzogen.
- **Anzeige:** eigener Bereich in der Account-Ansicht (Menuepunkt,
  analog "Statistik") mit freigeschalteten und - abgeblendet - noch
  offenen Abzeichen; auf der spaeteren Highscore-Webseite (5.14) als
  kleine Icons neben dem Namen.
- **Voraussetzung:** Abzeichen sind reine Server-Funktion (haengen an
  einem Account, siehe 5.12) und ergeben ohne Account/Server keinen
  Sinn; sie entfallen daher konsequent im lokalen Einzelspieler-Betrieb.
- **Offen** (siehe TODO.md 2.3): konkrete Abzeichen-Liste und ihre
  Bedingungen sind noch nicht festgelegt - erst nach Playtesting und
  zusammen mit dem Liga-System (5.14) sinnvoll auszuarbeiten, damit
  Abzeichen und Liga-Punkte sich nicht widersprechen.

