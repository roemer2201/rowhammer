# rowhammer - Konzept: Mehrspieler (5. Einleitung, 5.1 bis 5.10)

Teil des technischen Konzepts von rowhammer. Die Abschnittsnummern sind
die aus [CLAUDE.md](../../CLAUDE.md) und bleiben stabil
(Arbeitsregel 6.1): ein Verweis der Form `CLAUDE.md 5.5` im Code meint
den gleichnamigen Abschnitt hier. Die Datei fuehrt den **aktuellen**
Stand samt seiner Begruendung; was abgeloest wurde, steht in
[HISTORY.md](../../HISTORY.md), was noch fehlt, in
[TODO.md](../../TODO.md).

## 5. Mehrspieler und Server-Betrieb

Dieser Abschnitt hat zwei Teile: **5.1 bis 5.10 und 5.20** beschreiben
den **gebauten** Mehrspieler (Phase 5, seit 1.1.0), **5.11 bis 5.19**
den **geplanten** Server-Betrieb darum herum (Phase 6, noch nichts
davon umgesetzt); ein Trennabsatz vor 5.11 markiert die Stelle. Die
Nummerierung folgt der Entstehungsreihenfolge und bleibt deshalb stabil
(Arbeitsregel 6.1) - deshalb steht 5.20 hinter der Phase 6, obwohl es
zu Phase 5 gehoert.

**Gebaut ist der Mehrspieler damit vollstaendig**, seit 1.4.0
einschliesslich der Demo-Aufzeichnung einer Mehrspieler-Runde (5.20):
sie wird bei jedem Teilnehmer aufgezeichnet, wieder gelesen und
abgespielt, der Fokus wechselt waehrend der Wiedergabe mit den
Pfeiltasten, der Kasten am Ende nennt Platz und Grund, und die
Wiedergabe prueft sich gegen die Pruefpunkte der Aufnahme. Was
[TODO.md](../../TODO.md) an Phase 5 noch fuehrt, ist Aufraeumarbeit ohne
sichtbare Wirkung: die vollstaendige Entkopplung der Rundenlogik von
Bildschirm und Tastatur (5.3), der `2.0.0` vorbehalten ist.

Drei Nachrichten kamen beim Bauen hinzu, die die urspruengliche
Spezifikation nicht hatte; sie stehen in der Nachrichtentabelle 5.4 und
hier zusammen begruendet, weil sie alle drei dieselbe Luecke schliessen -
die Spezifikation nannte eine Wirkung, ohne zu sagen, woher der Absender
weiss, dass sie noetig ist:

- **`VIEW <0|1>`** (Client -> Hub): "ich zeichne die Gegnerfelder".
  `NEEDBOARD` war vorgesehen, aber der Hub kann nicht wissen, welche
  Detailstufe ein Terminal gerade zeigt.
- **`QUEUE`** (Hub -> Clients): die verbindliche Laenge einer
  Garbage-Warteschlange, nachdem ein Abbau sie gekuerzt hat.
- **`APPLIED <n>`** (Client -> Hub): "diese Reihen stehen jetzt in
  meinem Stapel". Zusammen halten die beiden die Warteschlange an genau
  einer Stelle - beim Hub, dem die Verrechnung gehoert; zwei Kopien
  derselben Zahl koennten nur auseinanderlaufen.

Leitentscheidung (ueberarbeitet mit dem Beginn der Lobby-Arbeit,
Nutzerentscheidung): **serverfreier Mehrspieler im LAN**. Es gibt keinen
zentralen Dienst, bei dem man sich anmeldet - ein Spieler eroeffnet eine
Sitzung, sein Rechner traegt den Hub, und die anderen **finden ihn ueber
einen UDP-Broadcast** im selben Netz oder **verbinden sich mit seiner
Adresse**, wo Broadcasts nicht durchkommen (beides siehe 5.2). Damit ist `socat`
gesetzt statt eine von drei moeglichen Abhaengigkeiten, und es ist
zugleich das Programm, ueber das die eigentliche Sitzungsverbindung
laeuft.

Das urspruengliche Szenario - **mehrere Leute per SSH auf demselben
Host**, Verbindung ueber einen **Unix-Domain-Socket** - bleibt als
zweiter Transport bestehen. Es ist genau der Fall, den Phase 6 mit dem
dedizierten Server ausbaut (5.11), es braucht keinen Broadcast (die
Sitzungen stehen als Dateien im gemeinsamen Verzeichnis) und es kostet
im Code nur eine andere socat-Adresse: Prozessmodell (5.3), Protokoll
(5.4) und Sicherheitsregeln (5.5) sind fuer beide dieselben.

### 5.1 Spielerzahl und Spielmodus

- **2 bis 5 Spieler** (Nutzerentscheidung, seit 1.3.0; bis 1.2.0 waren
  es 6): 2 ist das Minimum, 5 das
  Maximum - man selbst und vier Mitspieler -, und **eine Vorgabe
  dazwischen gibt es bewusst nicht** - der
  Host entscheidet, wann gestartet wird. Die Lobby fuellt sich also,
  bis er startet oder der fuenfte Platz belegt ist; der Starteintrag
  bleibt gesperrt (mit Hinweis), solange er allein dort sitzt. Eine
  erwartete Spielerzahl vorher festzulegen waere eine Zahl, die
  niemanden bindet: wer zu spaet kommt, findet die Sitzung ohnehin
  nicht mehr, und wer fehlt, haelt sonst alle auf.
  Umgesetzt ohne eigene Nachricht: der Host ist Slot 0 (die erste
  Verbindung), und sein `READY 1` **ist** der Start - fuer ihn ist der
  Lobby-Eintrag ohnehin der Startknopf, und solange er allein sitzt,
  antwortet der Hub mit `ERR alone`.
  `--mp-max N` bleibt als **Obergrenze**, die der Host enger setzen
  kann (2..5, Standard 5 = das technische Maximum) - etwa um eine
  Sitzung fuer genau drei Leute zuzumachen, statt den vierten von Hand
  wieder hinauszubitten. Begruendung fuer das Maximum 5:
  - Rechenaufwand: Bash rendert jeden Frame als String; jedes zusaetzliche
    Gegnerfeld kostet ~200 Zellen pro Frame, in voller Zellenbreite
    (siehe 5.6) sogar die doppelte Zeichenmenge. Ab etwa 5 Feldern ist
    die Framerate auf schwachen Terminals/Hosts nicht mehr zu halten.
  - Bildschirmbreite: ein Gegnerfeld in voller Breite braucht 23
    Spalten (siehe 5.6); bei 4 Gegnern sind das mit dem eigenen Feld
    140 Spalten - schon fuer ein sehr breites Terminal. Der Rueckfall
    auf die halbe Breite (13 Spalten je Gegner) kommt mit 100 Spalten
    aus.
  - Garbage-Zielwahl wird ab ~4 Spielern ohne Zielauswahl-UI beliebig.
  - Mehr als 5 Spieler waeren nur noch als reines Scoreboard sinnvoll;
    das ist bewusst kein Ziel. **Die Aenderung von 6 auf 5** (1.3.0)
    kommt aus derselben Ueberlegung: mit der vollen Zellenbreite ist
    ein Gegnerfeld fast doppelt so breit wie zuvor, und vier Gegner
    sind genau das, was sich noch symmetrisch um das eigene Feld
    setzen laesst (zwei je Seite, siehe 5.6).
- **Grundform:** "Versus" - jeder Spieler hat sein eigenes 10x20-Feld,
  alle starten mit demselben Seed (identische Steinfolge, Fairness).
  Wer oben rausbaut (Top-Out), scheidet aus und wird Zuschauer
  (siehe 5.8).
- Das Quadrat-System bleibt unveraendert die Kernmechanik: Gold- und
  Silber-Quadrate sind die staerksten Angriffe - und in jedem Modus der
  schnellste Weg zu Rows.

**Sitzungseinstellungen (seit 1.1.0, Nutzerwunsch).** Der Gastgeber legt
in der Lobby zwei Dinge fest, und **beide stehen in der Lobby jedes
Spielers**: den **Modus**, der die Siegbedingung bestimmt, und den
Schalter fuer die **Stoerreihen**. Umgesetzt als eigener Menuepunkt
"Einstellungen" in der Lobby (`mp_settings_menu`, `lib/mp.sh`), der die
Werte per `SETUP` an den Hub schickt; der Hub nimmt sie nur von Slot 0
und nur ausserhalb einer laufenden Runde an und schickt sie an alle
zurueck (`hub_msg_setup`, `lib/hub.sh`). Die Entscheidungen dazu:

- **Sichtbar fuer alle, aenderbar nur vom Gastgeber.** Die Einstellungen
  entscheiden, wofuer gespielt wird; wer sie nicht sieht, raet. Deshalb
  ist es *eine* Nachricht in beide Richtungen (wie `ROSTER`) und keine
  private Einstellung des Gastgebers.
- **Der Hub prueft die Herkunft ein zweites Mal.** Der Menuepunkt
  existiert nur beim Gastgeber, aber ein Client, der behauptet, der
  Gastgeber zu sein, ist keiner (5.5): `hub_msg_setup` weist alles
  ausser Slot 0 ab.
- **Waehrend der Runde nicht mehr.** Eine Regel, die sich mitten in der
  Runde aendert, ist keine.
- **Drei Modi, weil es drei Siegbedingungen gibt.** Der Modus ist keine
  Geschmacksfrage, sondern die Antwort auf "wer gewinnt":
  - `survival` (Standard) - **wer uebrig bleibt.** Die klassische
    Duellform; sie braucht keine Erklaerung und ist deshalb die Vorgabe.
  - `sprint` - **die meisten Rows,** wenn `SPRINT_TIME_MS` um sind. Die
    Uhr gehoert dem Hub (`HUB_ROUND_END_MS`), die Clients zaehlen
    dieselbe Grenze nur fuer ihre Anzeige herunter.
  - `ultra` - **wer zuerst `ULTRA_TARGET_ROWS` erreicht.** Der Hub sieht
    das an den `STATE`-Zaehlern und beendet die Runde in dem Moment.
  Die beiden Grenzen sind die Konstanten der gleichnamigen
  Einzelspieler-Modi, nicht neue: derselbe Sprint ist derselbe Sprint,
  ob allein oder zu fuenft.
- **In `sprint` und `ultra` endet die Runde nicht am vorletzten
  Ausscheiden.** Nur `survival` ist vorbei, sobald einer uebrig ist; in
  den beiden anderen entscheiden die Rows, und wer schon ausgeschieden
  ist, kann trotzdem vorn liegen - der Letzte im Feld spielt also
  weiter, bis die Uhr bzw. das Ziel es sagt oder auch er ausscheidet.
  Aus demselben Grund werden die Plaetze dort am Ende **nach Rows neu
  vergeben** (`hub_places_by_rows`): die Reihenfolge des Ausscheidens
  ist in diesen Modi nicht die Reihenfolge des Ergebnisses.
- **Stoerreihen sind anfangs aus** (Nutzerentscheidung). Eine Runde, in
  der jemand anders das eigene Feld fuellt, ist das anspruchsvollere
  Spiel; sie soll etwas sein, das der Gastgeber einschaltet, und nicht
  etwas, das einem beim ersten Mal ungefragt widerfaehrt. Ausgeschaltet
  bleibt ein Abbau ein Abbau - er zaehlt fuer die Rows, mit denen jeder
  Modus gewertet wird -, er reist nur nicht. Deshalb ist es ein
  Schalter neben dem Modus und kein vierter Modus.
- **Nicht angeboten werden Time Attack und Hochwasser.** Beide haetten
  im Duell dieselbe Siegbedingung wie `survival` (der Letzte gewinnt)
  und waeren damit Varianten desselben Modus statt eigener - und die
  Hochwasser-Flut waere neben eingeschalteten Stoerreihen eine zweite
  Quelle steigender Reihen, die dem Spieler nicht mehr zu erklaeren
  ist. Sie bleiben Einzelspieler-Modi.
- **Vorbelegt ueber die Kommandozeile:** `--mp-mode` und `--mp-garbage`
  (siehe 5.10) setzen, womit eine eroeffnete Sitzung startet - fuer
  jemanden, der immer dasselbe spielt, und fuer die Tests. Sie sind
  keine Config-Werte: was in einer Sitzung gilt, entscheidet die Lobby.
- Ein spaeterer kooperativer Modus ist denkbar, aber nicht Teil dieser
  Spezifikation.

**Gastgeberwechsel: die Sitzung zieht um (seit 1.2.0, Nutzerwunsch).**
Verlaesst der Gastgeber die **Lobby**, ist die Sitzung damit nicht zu
Ende: sie wandert zum **zuerst beigetretenen** der verbliebenen Spieler.
Der Ablauf ist eine kleine Kette aus vier Nachrichten (siehe 5.4):
`PROMOTE` an den Nachfolger, dessen `PROMOTED <port>` zurueck, `MIGRATE
<adresse> <port>` an alle uebrigen - und dann stellt sich der alte Hub
ab. Umgesetzt in `hub_migrate_begin`/`hub_msg_promoted`
(`lib/hub.sh`) und `mp_promote`/`mp_migrate` (`lib/mp.sh`). Die
Entscheidungen dazu:

- **Der Hub des Gastgebers endet mit ihm** (Nutzervorgabe). Ihn
  weiterlaufen zu lassen waere der kuerzere Weg gewesen - die Sitzung
  laege dann aber als Prozess auf der Maschine von jemandem, der sich
  gerade von ihr abgewandt hat, und nichts wuerde sie je beenden ausser
  dem Weggehen des letzten Spielers. Der Nachfolger startet deshalb
  einen **eigenen** Hub (derselbe `mp_hub_start` wie beim Eroeffnen) und
  die anderen ziehen ihm nach.
- **Nachfolger ist, wer am laengsten da ist**, nicht der niedrigste
  freie Slot (`HUB_JOINED`, eine je Verbindung hochgezaehlte
  Beitrittsnummer). Nach ein paar Kommen und Gehen ist die
  Slot-Reihenfolge fuer niemanden mehr eine Reihenfolge; "wer zuerst da
  war" kann jeder im Raum nachvollziehen.
- **Die Sitzung behaelt ihren Namen.** Der neue Hub wuerde sonst unter
  dem Namen des Nachfolgers laufen und im Beacon als andere Sitzung
  erscheinen. Dafuer traegt `WELCOME` seit 1.2.0 den Sitzungsnamen
  (`MP_SESSION_NAME`), den jeder Client sich merkt und der Nachfolger
  seinem Hub mitgibt.
- **Alle Bereit-Haken fallen** (Nutzerwunsch). Sie galten dem alten
  Gastgeber und seinen Einstellungen, die der neue aendern darf; ausserdem
  **ist** das Bereit-Zeichen des Gastgebers der Startknopf (siehe oben),
  ein geerbter Haken koennte also eine Runde starten, die niemand
  wollte.
- **Die Meldung wird mit Enter bestaetigt** (Nutzerwunsch,
  `mp_host_notice` in `lib/mp.sh`): ein Bildschirm, der den neuen
  Gastgeber nennt und nur auf Enter schliesst. Bewusst nicht "beliebige
  Taste" wie sonst - er faellt mitten in eine Lobby, in der gerade
  jemand auf den Pfeiltasten war, und soll gelesen und nicht
  weggetippt werden.
- **Der Nachfolger bekommt einen Vorsprung.** Der neue Hub gibt die
  Lobby dem Client, der sich zuerst meldet - und das muss der sein, der
  gefragt wurde, nicht der, der am schnellsten neu verbindet. Sein
  Client ist zwar schon zu einem Hub auf der eigenen Maschine
  unterwegs, waehrend das `MIGRATE` der anderen noch ein Netz vor sich
  hat; sitzen aber alle auf **einem** Rechner (zwei Terminals und ein
  Test-Bot auf der Loopback-Adresse), sind das wenige Millisekunden und
  der Falsche gewinnt sie ungefaehr so oft wie der Richtige. Der alte
  Hub haelt das `MIGRATE` deshalb `HUB_MIGRATE_DELAY_MS` (500 ms)
  zurueck (`hub_migrate_finish`), und der Nachfolger wartet nach seinem
  `PROMOTED` nur `MP_HANDOFF_FLUSH_MS` (250 ms) - lang genug, damit
  socat die Zeile noch aus dem Prozess bekommt, bevor `net_close` ihn
  beendet, und kurz genug fuer einen Vorsprung, den lokal niemand
  aufholt.
- **Die FIFOs eines Hubs tragen seine Prozessnummer**
  (`${MP_DIR}/<sitzung>.<pid>.inbox`, dito `.down.<bruecke>`). Zwei
  Hubs desselben Sitzungsnamens auf einer Maschine sind hier der
  Normalfall und kein Versehen - genau das ist ein Umzug -, und mit dem
  blossen Namen loeschte der zweite Hub das Postfach des ersten und
  dessen Bruecken schrieben fortan in ein Postfach, an dem niemand
  wartet. Beim Start raeumt `hub_sweep_stale` die FIFOs von Hubs weg,
  deren Prozess es nicht mehr gibt - streng nach dieser Bedingung, denn
  ein noch laufender Hub gehoert zu einer Sitzung, in der jemand
  spielt.
- **Die Sitzung behaelt auch ihre Groesse.** `WELCOME` nennt sie
  ohnehin; der Nachfolger gibt sie seinem Hub mit (`MP_SESSION_MAX`),
  statt die Runde stillschweigend auf sein eigenes `--mp-max`
  umzustellen. Nach oben begrenzt ihn dabei sein eigener Wert - seine
  Peer-Tabellen und sein Layout haben so viele Plaetze, wie er selbst
  angemeldet hat.
- **Klappt es nicht, ist die Sitzung zu.** Ist niemand mehr da, den man
  fragen koennte, oder antwortet der Gefragte nicht binnen
  `HUB_PROMOTE_MS` (3000 ms) bzw. bekommt keinen Hub hoch, geht ein
  `CLOSED host` bzw. `CLOSED failed` an alle. Eine ausgesprochene
  Absage ist besser als eine Lobby, die stumm bleibt, bis der
  Client-Timeout greift - den es dafuer trotzdem gibt (siehe 5.4/5.8).
- **Nur in der Lobby.** Geht der Gastgeber waehrend der **Runde**, ist
  das ein gewoehnliches Ausscheiden und die Runde spielt sich zu Ende
  (`hub_client_close`); ein Umzug mitten im Spiel muesste den ganzen
  Rundenzustand mitnehmen. Der Hub laeuft dann bis zum Rundenende
  weiter, wie er es auch ohne diesen Fall taete.

### 5.2 Transport: socat, LAN-Broadcast und Unix-Domain-Socket

**`socat` ist gesetzt** (Nutzerentscheidung mit dem Beginn der
Lobby-Arbeit). Bash kann kein AF_UNIX und keinen UDP-Broadcast;
`/dev/tcp` deckt nur ausgehendes TCP ab. Die frueher vorgesehene
Suchreihenfolge `socat` > `ncat --unixsock` > `nc -U` ist damit
hinfaellig, und das ist eine Vereinfachung, keine Einschraenkung: die
Discovery unten braucht **UDP-Broadcast**, die Sitzung braucht
**TCP-Listen/Connect** bzw. **UNIX-Listen/Connect**, und `socat` ist das
einzige der drei Programme, das alles beherrscht. Eine Abhaengigkeit,
die alles kann, ist besser als drei, die je einen Teil koennen - und
eine Fallunterscheidung je Werkzeug im Verbindungsaufbau entfaellt
ersatzlos. Die frueher dokumentierte FIFO-Variante ohne Fremdprogramm
ist mit derselben Entscheidung vom Tisch: sie reicht ueber die Grenzen
eines Hosts prinzipiell nicht hinaus. Die 512-Byte-Grenze je Nachricht
(5.4) bleibt trotzdem, sie ist jetzt eine Schutz- statt einer
Kompatibilitaetsgrenze.

Fehlt `socat`, bleibt der Menuepunkt sichtbar, nennt den Paketnamen und
kehrt zurueck; der Einzelspieler laeuft ohne jede neue Abhaengigkeit
weiter. Im Debian-Paket bleibt `socat` deshalb `Recommends` und wird
kein `Depends` (siehe 4.7).

**Transport `lan` (Standard): TCP im lokalen Netz.**

- Der Hub des Hosts lauscht auf `MP_PORT` (Standard **27301**,
  `--mp-port`); ist der Port belegt, nimmt er den naechsten freien und
  kuendigt genau den an. Clients verbinden sich mit
  `TCP4:<host>:<port>`, der Hub lauscht mit
  `TCP4-LISTEN:<port>,fork,reuseaddr,max-children=<mp-max>`.
- **Gefunden wird der Host ueber einen Broadcast-Beacon.** Der Hub
  schickt einmal je Sekunde eine Zeile an `255.255.255.255:MP_PORT`
  (limitierte Broadcast-Adresse, wird von keinem Router
  weitergereicht - genau die gewuenschte Reichweite):

  ```
  ROWHAMMER <proto> <sitzung> <spieler> <max> <tcpport> <lobby|play>
  ```

  Ein suchender Client hoert `MP_DISCOVER_MS` (Standard 2000 ms) auf
  demselben Port zu und baut daraus die Sitzungsliste. Der Beacon ist
  damit auch die Antwort auf die Frage, wie eine Sitzung wieder
  verschwindet: hoert er auf, faellt der Eintrag nach drei verpassten
  Beacons aus der Liste. Ein `INFO`-Anfrage/Antwort-Paar, wie es die
  frueheren Fassungen dieses Abschnitts fuer die Sitzungsliste
  vorsahen, braucht es dadurch nicht mehr - und der lauschende Client
  braucht keinen Rueckweg, was in Bash den Unterschied zwischen einem
  Lese-Coprocess und einem zweiten Serverprozess ausmacht.
- **Die Adresse des Hosts steht nie im Beacon**, sondern kommt aus der
  Absenderadresse des Datagramms (`SOCAT_PEERADDR`). Ein Beacon kann
  also niemanden auf einen Dritten zeigen lassen; eine gefaelschte
  Ankuendigung kann hoechstens auf den Faelscher selbst zeigen (siehe
  5.5). Empfangen wird deshalb mit
  `UDP4-RECVFROM:<port>,fork,reuseaddr,broadcast` und einem
  selbstaufgerufenen Sammler (`--mp-discover`, siehe 5.3), der die
  Absenderadresse vor die Zeile setzt - dieselbe Bauart wie die Bridge.
- **IPv4 only in v1**, bewusst: IPv6 kennt keinen Broadcast, dort waere
  es eine Multicast-Gruppe und damit ein zweiter Discovery-Pfad. Der
  Beitritt per Adresse (naechster Punkt) funktioniert unterdessen mit
  jeder Adresse, die `socat` versteht.
- **Beitritt per Adresse ist ein gleichrangiger zweiter Weg, kein
  Notnagel** (Nutzerentscheidung). `--mp-join HOST[:PORT]` und der
  Menuepunkt "Direkt verbinden" nehmen eine IP-Adresse (oder einen
  Hostnamen) von Hand entgegen und verbinden ohne jede Discovery.
  WLANs mit Client-Isolation, getrennte VLANs, so mancher
  Hypervisor-Switch und mancher Container-Netzstack lassen Broadcasts
  nicht durch; ohne diesen Weg waere das Spiel dort ohne erkennbaren
  Grund kaputt. Der Host sieht seine eigene Adresse und den Port
  deshalb **in der Lobby stehen**, damit er sie durchsagen kann - eine
  Adresse, die man erst mit `ip addr` suchen muss, ist keine Loesung
  fuer jemanden, der gerade nicht weiterkommt. Die eingegebene Adresse
  wird wie jede aus dem Netz stammende geprueft und zerlegt, bevor
  daraus eine socat-Adresse gebaut wird (siehe 5.5); dass sie diesmal
  von der eigenen Tastatur kommt, aendert daran nichts.

**Waehrend der Runde braucht es keinen Broadcast** - und auch keinen
Multicast. Der Broadcast dient ausschliesslich dem Finden einer
Sitzung; sobald ein Client verbunden ist, laeuft der gesamte Verkehr
ueber die stehende **TCP-Verbindung zwischen ihm und dem Hub**, also
Punkt zu Punkt. Ein Netz, das Broadcasts verwirft, kostet damit nur
die Sitzungsliste, nicht das Spiel: wer sich per Adresse verbunden hat,
spielt voellig gleichwertig mit. Vier Gruende, warum die Verteilung an
alle nicht ueber Multicast laeuft, obwohl der Hub dieselbe Nachricht
oft an mehrere schickt:

- **Die Nachrichten sind gar nicht dieselben.** `NEEDBOARD` haengt am
  Terminal des einzelnen Clients, und `PEER`, `PEERBOARD` und `PEERACT`
  gehen an alle **ausser** dem Absender. Multicast lohnt erst, wo
  wirklich alle dasselbe bekommen - und selbst `GARBAGE` und `QUEUE`,
  die seit Protokoll 4 an alle gehen, sind an genau einen Slot adressiert und
  nur fuer ihn eine Anweisung; die uebrigen schreiben sie bloss mit.
- **TCP bringt mit, was sonst nachzubauen waere.** Reihenfolge,
  Zustellung, Flusskontrolle und ein sauberes EOF beim Absturz eines
  Clients (an dem 5.8 den Verbindungsabbruch erkennt). Ueber UDP
  muesste die Wiederholung ausgerechnet fuer `CLEAR` und `TOPOUT` in
  Bash nachgebaut werden - die beiden Nachrichten, die zuverlaessig
  ankommen muessen (5.9).
- **Multicast ist im WLAN eher unzuverlaessiger als Broadcast**, nicht
  weniger: es braucht IGMP-Snooping, wird von Access Points gern auf
  die niedrigste Basisrate gelegt oder ganz verworfen. Es wuerde also
  genau die Netze treffen, fuer die die Adresseingabe oben da ist.
- **Die Menge rechtfertigt es nicht.** Schlimmstenfalls - sechs
  Spieler, Detailstufe 2 - schickt der Hub rund 6 kB/s je Empfaenger
  (5.4), also gut 30 kB/s ausgehend. Das ist in jedem LAN nichts.

Damit ist der Beacon das **einzige** Datagramm im ganzen
Mehrspieler-Betrieb. Er laeuft waehrend der Runde weiter (mit
`play` statt `lobby`, die Sitzung erscheint in der Liste als nicht
beitretbar), damit ein Suchender sieht, dass hier gerade gespielt wird,
statt gar nichts zu finden - notwendig fuer den Ablauf ist er dann
aber nicht mehr, und ein Netz, das ihn schluckt, stoert die laufende
Partie an keiner Stelle.

**Transport `unix`: Domain-Socket auf einem gemeinsamen Host.**

- Wie bisher, fuer das SSH-Szenario (mehrere Leute auf derselben
  Maschine) und fuer den spaeteren dedizierten Server (5.11). Kein
  Beacon - die laufenden Sitzungen stehen als Socket-Dateien im
  gemeinsamen Verzeichnis und werden per Glob gefunden.
- **Socket-Pfad:** `${MP_DIR}/<sitzung>.sock`. `MP_DIR` ist
  standardmaessig `${XDG_RUNTIME_DIR:-/tmp/rowhammer-${UID}}/rowhammer`,
  umstellbar per `--mp-dir DIR` / `ROWHAMMER_MP_DIR`.
  - **Privat (Standard):** Verzeichnis mit `mkdir -m 0700`, nur eigene
    Sitzungen (mehrere Terminals/SSH-Sessions desselben Kontos).
  - **Geteilt (mehrere Konten auf einem Host):** ein Verzeichnis mit
    gemeinsamer Gruppe, `0770`, Socket `mode=0660`. Der Pfad muss vom
    Administrator angelegt werden (z. B. `/var/games/rowhammer`); das
    Spiel legt ein solches Verzeichnis **nicht** selbst an und weigert
    sich, ein world-writable Verzeichnis ohne Sticky-Bit zu benutzen
    (siehe 5.5).
- Adressen: `UNIX-LISTEN:<sock>,fork,max-children=<mp-max>,mode=<0600
  privat bzw. 0660 geteilt>` und `UNIX-CONNECT:<sock>`. Alles Uebrige -
  Hub, Bridge, Protokoll, Validierung - ist mit dem `lan`-Transport
  identisch.

**Gewaehlt wird der Transport ueber `--mp-transport lan|unix`**
(`ROWHAMMER_MP_TRANSPORT`, Standard `lan`, siehe 5.10). Der Standard
ist das LAN, weil das der Fall ist, fuer den der Mehrspieler gedacht
ist; `unix` ist die Wahl fuer den Host, auf dem ohnehin alle sitzen -
dort spart er die Netzwerkschicht komplett ein und behaelt die
Dateirechte als zusaetzliche Schranke.

### 5.3 Prozessmodell

Vier Rollen, strikt getrennt (die vierte nur im Transport `lan`):

- **Client** (`rowhammer.sh`, ein Prozess je Spieler und Terminal):
  spielt die eigene Runde, rendert, sendet den eigenen Zustand, empfaengt
  Gegnerzustand und Garbage. Der Client haelt die Verbindung als
  **Coprocess**: `coproc MP_LINK { socat "${addr}" -; }`, wobei
  `${addr}` je nach Transport `TCP4:<ip>:<port>` oder
  `UNIX-CONNECT:<sock>` ist und **aus geprueften Einzelteilen gebaut
  wird**, nie aus einer empfangenen Zeichenkette (siehe 5.5).
  Damit sind Lese- und Schreib-FD normale Bash-FDs; Lesen erfolgt
  nicht-blockierend mit `read -t 0` (Datenpruefung) plus `read -r -t 0.01`
  (Zeile holen) einmal pro Tick. Die Taktung des Game-Loops bleibt
  unveraendert beim `read`-Timeout auf STDIN - Bash kann nicht auf zwei
  FDs gleichzeitig warten, deshalb bleibt die Tastatur der Taktgeber und
  der Socket wird pro Tick nur geleert (max. N Zeilen pro Tick, damit ein
  fluteter Socket den Frame nicht anhaelt, siehe 5.5).
- **Hub** (`rowhammer.sh --mp-hub`, ein Prozess je Sitzung, headless):
  autoritative Sitzungslogik. Kein Terminal, kein Rendering, kein
  `stty`, keine Signal-Handler des Spiels. Er haelt die Spielerliste,
  verteilt Seed und Startsignal, verrechnet Garbage, verteilt
  Zustandsupdates und erkennt Timeouts. Der Host-Client startet ihn im
  Hintergrund (`setsid`-artig entkoppelt), damit ein haengender Client
  nie den Hub blockiert und umgekehrt. Im Transport `lan` sendet er
  zusaetzlich den Beacon (5.2) - er ist der Einzige, der weiss, wie
  viele Spieler in der Lobby sitzen und ob die Runde laeuft.
- **Bridge** (`rowhammer.sh --mp-bridge`, ein kurzlebiger Prozess je
  Verbindung): wird von `socat TCP4-LISTEN:...,fork` bzw.
  `socat UNIX-LISTEN:...,fork` gestartet, hat die
  Socket-Enden auf STDIN/STDOUT und uebersetzt zwischen Socket und den
  FIFOs des Hubs (Client -> `inbox`-FIFO mit vorangestellter Client-ID,
  Hub -> privates `down.<id>`-FIFO -> Socket). So spricht der Hub nur
  mit FIFOs (Bash-nativ) und `socat` nur mit dem Socket; **der Wechsel
  zwischen den beiden Transporten aendert damit nur die
  socat-Adresse**, keine Zeile Sitzungslogik - genau die Trennung, die
  dieser Abschnitt seit jeher vorsieht. Beide FIFO-Namen tragen seit
  1.2.0 die Prozessnummer des Hubs, damit zwei Hubs derselben Sitzung
  auf einer Maschine - der Normalfall waehrend eines Gastgeberwechsels,
  siehe 5.1 - einander nicht das Postfach unter den Bruecken
  wegziehen.
  **Beide Leseseiten heben eine angelesene Zeile auf.** Ein `read` mit
  Zeitlimit gibt beim Ablauf zurueck, was es bis dahin hatte - und das
  ist mitten in einer Zeile eben deren Anfang. Der Client tut das seit
  jeher (`NET_PART` in `net_poll`, `lib/net.sh`), der Hub seit 1.4.0
  (`HUB_INBOX_PART` in `hub_main`): sein Postfach-`read` laeuft alle
  50 ms ab, und ein Hub, der genau dann verdraengt wird - was eine volle
  Sitzung auf einer beschaeftigten Maschine tut -, verwarf die Zeile
  samt allem, was sie noch zu sagen hatte. Im Spiel faellt das kaum auf,
  weil der naechste Schnappschuss darueber hinweggeht; einer
  Demo-Aufnahme bleibt das Loch (siehe 5.20). Beide Puffer sind auf
  `MP_LINE_MAX` gedeckelt, damit ein Schreiber ohne Zeilenende sie nicht
  wachsen laesst.
- **Discover-Sammler** (`rowhammer.sh --mp-discover`, ein kurzlebiger
  Prozess je empfangenem Beacon, nur Transport `lan`): wird von
  `socat UDP4-RECVFROM:<port>,fork,...` gestartet, liest das Datagramm
  von STDIN und schreibt `<SOCAT_PEERADDR> <zeile>` in das
  Sammel-FIFO des suchenden Clients. Er existiert allein deshalb, weil
  die Absenderadresse nur einem von socat gestarteten Kindprozess in
  der Umgebung zur Verfuegung steht - und die Absenderadresse ist genau
  das, was den Beacon vertrauenswuerdiger macht als seinen Inhalt
  (5.2, 5.5).

Modulschnitt (neue Dateien, siehe auch 4.2):

- `lib/net.sh` - Transport und Rahmung: `socat`-Erkennung, Bau der
  Adressen aus geprueften Einzelteilen, Verbindungsauf-/abbau, Beacon
  senden und einsammeln, Zeilen senden/empfangen, Laengen- und
  Zeichensatzpruefung, Debug-Mitschnitt. Kennt **keine** Spielregeln.
- `lib/proto.sh` - Nachrichtentabelle, Serialisierung und
  **Validierung** (Whitelist der Verben, Feldtypen, Wertebereiche).
  Kennt keine Sockets und keinen Bildschirm.
- `lib/hub.sh` - Sitzungs- und Rundenlogik des Hubs (Lobby, Start,
  Garbage-Verrechnung, KO-Reihenfolge, Timeouts).
- `lib/mp.sh` - Client-Seite: Lobby-Menue, Sitzungssuche, Anbindung des
  Game-Loops, Puffer fuer Gegnerzustaende.
- Gegner-Darstellung kommt in `lib/render.sh` dazu (`render_peer`,
  `draw_frame`-Erweiterung), damit alles Zeichnen an einer Stelle bleibt.

Voraussetzung im bestehenden Code: die Rundenlogik muss ohne Rendering
und ohne Tastatur laufen koennen (offener Punkt, siehe TODO.md).
Konkret: `game_reset`, `step_down`, `lock_and_next`, `hold_piece`,
`try_move`, `try_rotate` duerfen weder zeichnen noch lesen; `DIRTY`
markiert nur. Das ist ohnehin fast erreicht - offen sind die Stellen, an
denen `flash_rows` den Loop anhaelt und `record_round` Bildschirme zeigt.

### 5.4 Protokoll (Version 5)

- **Rahmen:** eine Nachricht = eine Zeile, `\n`-terminiert, reines
  druckbares ASCII (0x20-0x7E), maximal **512 Byte** inklusive Zeilenende.
  Felder durch **ein Leerzeichen** getrennt, erstes Feld ist das Verb in
  Grossbuchstaben. Unbekannte Verben werden ignoriert (Vorwaerts-
  kompatibilitaet), fehlerhafte Zeilen fuehren zum Verbindungsabbruch
  (siehe 5.5).
- **Versionierung:** `PROTO_VERSION=5`. Der Hub lehnt abweichende
  Versionen im `HELLO` mit `ERR proto ...` ab. Gemaess der Arbeitsregel
  "keine Abwaertskompatibilitaet" wird das Protokoll bei Bedarf
  hochgezaehlt statt kompatibel erweitert; genau das ist viermal
  passiert. **Version 2** kam mit den Sitzungseinstellungen (1.1.0,
  siehe 5.1): `SETUP` in beide Richtungen. **Version 3** kam mit dem
  Gastgeberwechsel (1.2.0, siehe unten und 5.8): `HOST`, `PROMOTE`,
  `PROMOTED`, `MIGRATE` und `CLOSED`, dazu der Sitzungsname als viertes
  Feld von `WELCOME` - eine umgezogene Sitzung soll unter ihrem eigenen
  Namen weiterlaufen und nicht unter dem des Nachfolgers.
  **Version 4** (Schritte 9.3 und 9.4) verteilt die Zuege aller
  Teilnehmer (`ACT`, `PEERACT`) und stellt `GARBAGE` und `QUEUE` einen
  Slot voran, damit eine Demo-Aufzeichnung jeden Mitspieler nachspielen
  kann (5.20). Sie kam mit 1.3.0. Ein Version-3-Client wuerde `ACT`/`PEERACT` stillschweigend
  ignorieren (so ist ein unbekanntes Verb gedacht), aber den Slot in
  `GARBAGE` als Reihenzahl lesen und die falsche Menge Stoerreihen
  einschieben - genau dafuer gibt es diese Zahl.
  **Version 5** (1.4.1) gibt `KO` ein drittes Feld: **warum** der
  Spieler seinen Platz bekommt (`play`, `ko` oder `gone`). Der Hub
  wusste das immer schon und sagte es eine Tick-Laenge spaeter im
  `ROSTER`; wer darauf wartet, bekommt die Antwort zu spaet, sobald
  dasselbe Ausscheiden die Runde beendet - `END` geht sofort raus, der
  Roster erst am Ende des Ticks. Ein Version-4-Client wuerde die
  Nachricht an ihrer Feldzahl verwerfen, also eine Runde spielen, in der
  keine Plaetze mehr ankommen; deshalb die neue Nummer statt eines
  angehaengten Feldes. Was daran haengt, steht in 5.8 (Anzeige) und
  5.20 (Aufzeichnung).
- **Client -> Hub**

  | Nachricht | Felder | Bedeutung |
  | --- | --- | --- |
  | `HELLO` | `<proto> <name> <caps>` | Anmeldung; `caps` = Komma-Liste (z. B. `board`) |
  | `READY` | `<0 oder 1>` | Bereitschaft in der Lobby |
  | `STATE` | `<lines> <rows> <level> <gold> <silver> <height> <pending>` | eigener Zaehlerstand, bei Aenderung, max. 10/s |
  | `BOARD` | `<200 Zeichen>` | Feld-Snapshot, nur wenn der Hub `NEEDBOARD 1` gesetzt hat, max. 5/s |
  | `CLEAR` | `<lines> <silver> <gold>` | ein Reihenabbau als Angriffs-Meldung (Hub rechnet daraus die Garbage aus) |
  | `APPLIED` | `<count>` | eingeschobene Stoerreihen (seit 1.1.0, siehe unten) |
  | `ACT` | `<t> <tokens>` | die eigenen Zuege eines Zeitfensters (seit Protokoll 4, siehe unten) |
  | `VIEW` | `<0 oder 1>` | ob dieser Client die Gegnerfelder zeichnet (seit 1.1.0) |
  | `SETUP` | `<modus> <garbage>` | Sitzungseinstellungen, nur vom Gastgeber (seit 1.1.0, siehe 5.1) |
  | `PROMOTED` | `<port>` | "mein Hub laeuft auf diesem Port" - Antwort auf `PROMOTE` (seit 1.2.0) |
  | `TOPOUT` | - | eigenes Game Over |
  | `PONG` | `<token>` | Antwort auf `PING` |
  | `BYE` | - | geordnetes Verlassen |

- **Hub -> Client**

  | Nachricht | Felder | Bedeutung |
  | --- | --- | --- |
  | `WELCOME` | `<slot> <proto> <maxplayers> <sitzung>` | Anmeldung akzeptiert; der Sitzungsname seit 1.2.0 (siehe oben) |
  | `ROSTER` | `<slot> <name> <ready> <state>` | eine Zeile je Spieler, bei jeder Aenderung |
  | `SETUP` | `<modus> <garbage>` | die geltenden Sitzungseinstellungen, an alle (seit 1.1.0) |
  | `HOST` | `<slot>` | wer die Sitzung fuehrt (seit 1.2.0) |
  | `PROMOTE` | - | "uebernimm die Sitzung" - nur an den Nachfolger (seit 1.2.0) |
  | `MIGRATE` | `<adresse> <port>` | "die Sitzung zieht dorthin um" (seit 1.2.0) |
  | `CLOSED` | `<host oder failed>` | die Sitzung ist zu Ende, ohne Nachfolger (seit 1.2.0) |
  | `SEED` | `<seed>` | gemeinsamer Seed fuer die Steinfolge |
  | `START` | `<countdown_ms>` | Rundenstart |
  | `PEER` | `<slot> <lines> <rows> <level> <gold> <silver> <height> <pending> <state>` | Zustand eines Mitspielers |
  | `PEERBOARD` | `<slot> <200 Zeichen>` | Feld-Snapshot eines Mitspielers |
  | `PEERACT` | `<slot> <t> <tokens>` | die Zuege eines Mitspielers, unveraendert weitergereicht (seit Protokoll 4) |
  | `NEEDBOARD` | `<0 oder 1>` | ob dieser Client Snapshots senden soll (spart Last, wenn niemand Stufe 2 anzeigt) |
  | `GARBAGE` | `<slot> <count> <hole>` | Stoerreihen fuer einen Spieler, Lochspalte 0-9; seit Protokoll 4 mit Slot und an alle |
  | `QUEUE` | `<slot> <count>` | verbindliche Laenge einer Warteschlange (seit 1.1.0; seit Protokoll 4 mit Slot und an alle) |
  | `KO` | `<slot> <platz> <play\|ko\|gone>` | Platz in der Runde, mit dem Grund; das dritte Feld seit Protokoll 5 |
  | `END` | `<siegerslot>` | Runde vorbei |
  | `PING` | `<token>` | Lebendpruefung, alle 2 s |
  | `ERR` | `<code> <text>` | Ablehnung/Fehler, danach ggf. Abbruch |

- **Feld-Snapshot (`BOARD`/`PEERBOARD`):** genau **200 Zeichen**, Zeile
  fuer Zeile von oben (y=HIDDEN_ROWS) nach unten, je Zelle ein Zeichen
  aus `.IOTSZJLgsx`: `.` leer, Grossbuchstabe = Baustein-Sorte,
  `g` Gold-Quadrat, `s` Silber-Quadrat, `x` Garbage. Feste Laenge statt
  Lauflaengenkodierung, weil die Validierung dadurch trivial und
  lueckenlos ist (Laenge + Zeichensatz); 200 Byte bei max. 5 Hz und 6
  Spielern sind lokal unkritisch (~6 kB/s). Der aktive, noch fallende
  Stein wird **nicht** mitgesendet (er waere veraltet, sobald er ankommt);
  optional spaeter als eigenes `PIECE`-Verb.
- **Autoritaet:** der Hub ist die einzige Quelle fuer Garbage-Mengen,
  Lochspalten, KO-Reihenfolge und Rundenende. Clients melden nur
  Ereignisse (`CLEAR`, `TOPOUT`); sie berechnen nie selbst, wie viel
  Garbage der Gegner bekommt. Damit ist der offensichtlichste Cheat
  ("ich sende einfach 20 Reihen") ausgeschlossen. Ein manipulierter
  Client kann weiterhin falsche `CLEAR`-Meldungen abgeben - vollstaendige
  Cheat-Sicherheit ist ohne serverseitige Simulation nicht erreichbar und
  ist **kein** Ziel (siehe Vertrauensmodell in 5.5).
- **Zeitverhalten:** `PING` alle 2 s, Timeout nach 6 s ohne Lebenszeichen
  -> Spieler gilt als abgestuerzt (siehe 5.8). Der Hub laeuft mit einem
  eigenen Tick von 50 ms (`read -t` auf dem Inbox-FIFO, kein `sleep`).
  **Die Uhr laeuft seit 1.2.0 in beide Richtungen** (Nutzerwunsch): der
  Client merkt sich mit jeder empfangenen Zeile die Zeit
  (`MP_LAST_RX_MS` in `lib/mp.sh`) und gibt nach denselben
  `MP_TIMEOUT_MS` (6000 ms) Stille auf (`mp_link_silent`). Der `PING`
  des Hubs alle `MP_PING_MS` (2000 ms) ist damit nicht nur eine Frage,
  sondern zugleich das Lebenszeichen, auf das der Client wartet - drei
  ausgefallene reichen. Gefragt wird an jeder Stelle, an der ein Client
  auf den Hub wartet: Lobby, Einstellungsmenue, Namensabfrage,
  Countdown und Game-Loop. Ohne diese Pruefung erkennt ein Client nur
  das, was ihm gesagt wird - und ein Hub, dessen Maschine ausgeschaltet
  wurde, sagt nichts mehr (siehe 5.8).

### 5.5 Sicherheit

Bedrohungsmodell: Mitspieler sind **halb vertrauenswuerdig**. Sie
duerfen im Spiel schummeln koennen (das ist hinnehmbar), aber unter
keinen Umstaenden

1. Code im Prozess eines anderen Spielers ausfuehren,
2. dessen Terminal uebernehmen oder Dateien beschaedigen,
3. den fremden Prozess zum Absturz oder Haengen bringen.

**Mit dem LAN-Transport (5.2) ist "Mitspieler" nicht mehr "jemand mit
einem Konto auf diesem Host", sondern "jeder, der Pakete an diesen Port
schicken kann".** Die Regeln unten aendern sich dadurch nicht - sie
waren von Anfang an gegen genau diesen Fall geschrieben -, aber ihr
Gewicht: die Dateirechte des Sitzungsverzeichnisses waren bisher eine
zusaetzliche Schranke vor dem Parser, und im LAN gibt es sie nicht
mehr. **Die Validierung ist dort die einzige Schranke.** Drei Punkte
kommen deshalb hinzu:

- **Eine Adresse aus dem Netz wird nie als Zeichenkette weitergereicht.**
  Die Gegenstelle kommt aus der Absenderadresse des Beacons
  (`SOCAT_PEERADDR`, siehe 5.2/5.3), wird in vier Oktette `0..255` und
  einen Port `1..65535` zerlegt und geprueft; die socat-Adresse wird
  aus **diesen Zahlen neu gebaut**. So kann kein Zeichen aus dem Netz
  je in einer Kommandozeile landen - der Weg, auf dem eine
  Netzwerk-Discovery am ehesten zur Codeausfuehrung wird. Eine im
  Beacon **mitgeschickte** Adresse gibt es aus demselben Grund nicht
  (sie waere frei waehlbar und koennte auf einen Dritten zeigen); ein
  Feld, das trotzdem wie eine Adresse aussieht, wird ignoriert.
- **Beacons sind unbeglaubigt und werden auch so behandelt.** Die
  Sitzungsliste ist ein Hinweis, keine Wahrheit: gefaelschte Eintraege
  sind eine Belaestigung (der Beitritt scheitert dann eben), kein
  Einbruch. Dagegen begrenzt: hoechstens ein Beacon je Absender und
  Sekunde, hoechstens `MP_DISCOVER_MAX` (32) Sitzungen in der Liste,
  Name und Zahlen gegen dieselben Muster wie im Protokoll. Ein Fluter
  fuellt damit weder Speicher noch Bildschirm.
- **Der Hub gibt niemandem unbegrenzt Zeit.** Eine Verbindung, die
  nicht binnen `MP_HELLO_MS` (5000 ms) ein gueltiges `HELLO` schickt,
  wird getrennt, und `max-children` der socat-Adresse deckelt die Zahl
  offener Verbindungen auf `--mp-max`. Sonst haelt ein Dutzend
  stummer Verbindungen die Lobby besetzt, ohne je eine Nachricht zu
  senden.

Regeln, verbindlich fuer `lib/net.sh`, `lib/proto.sh`, `lib/hub.sh` und
jede Stelle, die Empfangenes anfasst:

- **Kein `eval`, kein `source`, keine Kommandosubstitution auf
  Empfangenem.** Nie einen Befehlsstring aus Netzdaten bauen. Empfangene
  Werte landen ausschliesslich in Variablen und werden ausschliesslich
  als `"${var}"` benutzt.
- **Arithmetik ist ein Injektionsziel.** `$(( ))` und `((  ))` werten
  ihren Inhalt rekursiv aus: `$(( x ))` mit `x='a[$(rm -rf ~)]'` fuehrt
  den Befehl aus. Deshalb: jedes Zahlenfeld **vor** der ersten Rechnung
  gegen `^[0-9]{1,9}$` pruefen und auf den erlaubten Bereich begrenzen.
  Dasselbe gilt fuer alles, was als Array-Index oder als Schluessel eines
  assoziativen Arrays benutzt wird.
- **Zeichensatzfilter vor allem anderen.** Jede empfangene Zeile wird
  verworfen, wenn sie ein Byte ausserhalb 0x20-0x7E enthaelt. Das ist die
  wichtigste Einzelmassnahme: ein Spielername mit ANSI-Escapes koennte
  sonst den Bildschirm des Gegners umschreiben, den Fenstertitel setzen
  oder - je nach Terminal - ueber Antwort-Sequenzen Text in dessen
  Eingabepuffer schreiben. Der Filter greift im Empfangspfad, also
  einmal zentral, nicht erst beim Zeichnen.
- **Whitelist statt Blacklist.** Zerlegen mit `read -r verb rest`,
  danach `case "${verb}"` mit genau den Verben aus 5.4; jedes Feld hat
  ein eigenes Muster (`^[A-Za-z0-9_-]{1,16}$` fuer Namen,
  `^[0-9]{1,9}$` fuer Zahlen, `^[.IOTSZJLgsx]{200}$` fuer Snapshots,
  `^[0-9]$` fuer die Lochspalte). Ein Feld, das nicht passt, macht die
  ganze Nachricht ungueltig.
- **Harte Grenzen gegen Ressourcen-Angriffe:** Zeilenlaenge 512 Byte
  (Lesen mit `read -r -N` bzw. Laengenpruefung, ueberlange Zeilen werden
  bis zum naechsten `\n` verworfen), max. 64 Nachrichten pro Sekunde und
  Client (danach Verbindungsabbruch), max. `--mp-max` Verbindungen, max.
  16 Nachrichten pro Tick aus dem Socketpuffer, damit ein Fluter den
  Frame nicht anhaelt. Ein Client, der dreimal in Folge Muell schickt,
  wird getrennt (`ERR proto`), nicht toleriert.
- **Kein Absturz durch Fremddaten:** Der Empfangspfad laeuft nicht unter
  `set -e`-Annahmen; jede Pruefung endet in einem definierten "Nachricht
  verwerfen"-Zweig. Ein Verbindungsabbruch (EOF, `EPIPE`) beendet die
  Runde geordnet, nie das Terminal-Setup (der bestehende `trap` bleibt
  zustaendig).
- **Dateisystem** (Transport `unix`, und fuer die FIFOs des Hubs in
  beiden Transporten)**:** `umask 0077` fuer alle Sitzungsdateien; das
  Sitzungsverzeichnis muss dem Aufrufer oder root gehoeren und darf nicht
  world-writable ohne Sticky-Bit sein - sonst Abbruch mit Meldung
  (Schutz gegen Socket-Squatting und Symlink-Fallen in `/tmp`). Vor dem
  Anlegen: vorhandenen Pfad pruefen (kein Symlink, kein fremder
  Eigentuemer), `unlink-early` beim Listener, Aufraeumen des Sockets im
  bestehenden EXIT-`trap`. Sitzungsnamen werden gegen
  `^[A-Za-z0-9_-]{1,16}$` geprueft, bevor sie in einen Pfad eingehen
  (kein `..`, kein `/`).
- **Ausgehende Daten sind ebenfalls zu pruefen:** der eigene Spielername
  stammt aus der Config und kann exotisch sein; er wird beim Senden auf
  das Namensmuster reduziert, damit ein Client nicht unbeabsichtigt
  Muell erzeugt, den der Hub dann verwerfen muss.
- **Gegenprobe beim Rendern:** Namen und Zahlen werden vor der Ausgabe
  ein zweites Mal auf Laenge und Zeichensatz geprueft und hart
  abgeschnitten (Verteidigung in der Tiefe - auch der Hub gilt nicht als
  vertrauenswuerdig, er koennte ein fremdes Programm sein).
- **Debug-Modus:** der komplette Verkehr wird in `net.log`
  (`printf %q`-quotiert, wie `input.log`) mitgeschnitten, damit
  Protokollfehler und Angriffsversuche nachvollziehbar sind.
- **Testbarkeit:** ein Fuzz-Skript (`tools/net-fuzz.sh`) speist zufaellige
  und gezielt boesartige Zeilen (ANSI-Escapes, `$(...)`, Backticks,
  `../`-Pfade, 100-kB-Zeilen, Nullbytes, halbe Zeilen ohne `\n`) in
  Hub- und Client-Parser - **und in den Beacon-Sammler**, der im LAN
  der erste Parser ist, den ein Fremder ueberhaupt erreicht (er
  braucht dafuer nicht einmal eine Verbindung). Abnahmekriterium: kein Prozess stirbt, kein
  Befehl wird ausgefuehrt, kein Byte ausserhalb 0x20-0x7E erreicht das
  Terminal.

### 5.6 Darstellung der Mitspieler

Das bestehende Layout ist fest: linke Spalte 12 + 1 Abstand + Feld 22 +
1 Abstand + rechte Spalte 12 = 48 Spalten, 22 Zeilen Minimum (seit
0.22.0 zentriert, seit 0.26.0 ohne Statuszeilen, siehe 3.4). Die
Mitspieler sitzen **links und rechts daneben** (seit 1.3.0,
Nutzerwunsch; bis 1.2.0 standen sie alle rechts),
das eigene Feld bleibt unveraendert an seinem Platz und in der Mitte;
der Block wird dann
entsprechend breiter zentriert. Wo unten "Seitenleiste" steht, ist die
rechte Spalte gemeint (die linke traegt seit 0.26.0 Hold und die
eigenen Rundenzaehler und ist damit belegt).

**Sitzordnung (seit 1.3.0, Nutzerwunsch).** Der erste Mitspieler sitzt
**rechts** neben dem eigenen Feld, der zweite **links** davon, der
dritte weiter rechts, der vierte weiter links - der Bildschirm liest
sich also `[5][3][selbst][2][4]` (mit "selbst" als Spieler 1). Zwei
Festlegungen dazu:

- **Das eigene Feld bleibt in der Mitte**, egal wie viele Mitspieler
  dazukommen. Der Blick liegt die ganze Runde auf dem eigenen Stapel;
  ein Feld, das mit jedem Beitritt weiter nach links rutscht, muesste
  jedes Mal neu gesucht werden. Deshalb wird abwechselnd rechts und
  links angebaut statt der Reihe nach in eine Richtung.
- **Die Reihenfolge ist die der Slots** (`MP_PEER_SLOTS`), also die des
  Beitritts. Ein Mitspieler behaelt damit seinen Platz auf dem
  Bildschirm, solange die Sitzung laeuft; nach Rows zu sortieren wuerde
  die Felder waehrend der Runde tauschen lassen.

Drei Detailstufen, automatisch nach verfuegbarer Terminalgroesse und
Spielerzahl gewaehlt (`--mp-view auto|full|compact|score` erzwingt eine
Stufe):

- **Stufe 2 "full" - ein Feld je Gegner, in zwei Zellenbreiten.**
  22 Zeilen hoch (Kopfzeile mit Namen, 20 Feldzeilen, Fusszeile mit
  `Rows`/`pending`), Farben wie im eigenen Feld (Gold/Silber bleiben
  erkennbar, Garbage dunkelgrau). **Wer draussen ist, traegt in der
  Fusszeile seinen Platz** statt der Zahlen - mit dem Grund davor,
  denn es sind zwei verschiedene Dinge: `K.O.` fuer einen Stapel an der
  Decke, `Weg` fuer eine gerissene Verbindung. Den dritten Ausgang
  `SIEG` setzt nur eine durchgelaufene Demo-Wiedergabe; in einer Runde
  steht der Sieg im Kasten ueber dem Feld (5.20).
  - **Volle Breite (seit 1.3.0, Nutzerwunsch):** zwei Zeichen je Zelle,
    exakt wie das eigene Feld - 20 Spalten Inhalt + Rahmen = 22, plus 1
    Spalte Abstand = **23 Spalten je Gegner**. Ein Gegnerfeld traegt
    damit dieselben Glyphen wie das eigene (`##`/`%%`/`::` und die
    Sorten-Glyphen aus `PIECE_GLYPH`) und liest sich in denselben
    Proportionen. Bedarf: `48 + n*23` Spalten - 71 (2 Spieler),
    94 (3), 117 (4), 140 (5).
  - **Halbe Breite (die bisherige):** ein Zeichen je Zelle, also 10
    Spalten Inhalt + Rahmen = 12, plus 1 Spalte Abstand = **13 Spalten
    je Gegner**. Bedarf: `48 + n*13` Spalten - 61 (2 Spieler), 74 (3),
    87 (4), 100 (5).
  - **Gewaehlt wird die volle Breite, wenn sie passt**, sonst die
    halbe. **Das eigene Feld wird dafuer nie verkleinert:** seine 48
    Spalten sind der Block, auf dem das ganze feste Layout steht -
    Seitenleisten, Rundenende-Kasten, Menues und die
    Mindest-Terminalgroesse (3.4). Reicht der Platz fuer die vollen
    Gegnerfelder nicht, weichen deshalb die Gegner auf die halbe
    Breite aus und nicht das eigene Feld.
- **Stufe 1 "compact" - Textzeile je Gegner.** Kein Feld, sondern je
  Gegner zwei Zeilen in der Seitenleiste:
  `<name8> R<rows> L<lines>` und ein 10 Zeichen breiter Stapelhoehen-
  Balken plus Markierung fuer eingehende Garbage und KO-Status. Passt in
  die vorhandenen 12 Spalten der rechten Seitenleiste, kostet dort aber
  Platz: ab 3 Gegnern entfaellt die Vorschau des dritten Next-Steins.
  Bedarf: unveraendert 48 Spalten, aber 2 Zeilen je Gegner.
- **Stufe 0 "score" - Scoreboard.** Eine Zeile je Gegner:
  `<platz> <name8> <rows>`, sortiert nach Rows, KO-Spieler grau und
  ans Ende. Braucht 1 Zeile je Gegner und passt immer in 48x22.

Auswahlregel fuer `auto` (bei jedem Resize neu ausgewertet, der
SIGWINCH-Pfad aus 0.19.0 ruft sie mit auf):

1. Reicht `48 + n*13` Spalten und 22 Zeilen -> Stufe 2. Innerhalb der
   Stufe entscheidet dann die Breite ueber die Zellenbreite: reichen
   `48 + n*23` Spalten, kommen die Gegnerfelder in voller Breite, sonst
   in halber.
2. Sonst: reichen `22 - belegte Seitenleistenzeilen` fuer `2*n` Zeilen
   -> Stufe 1.
3. Sonst -> Stufe 0. Unter 48x22 greift weiterhin die bestehende
   "resize me"-Overlay.

Ein Wechsel der Gesamtbreite - Resize, ein Beitritt in der Lobby, ein
erzwungener Modus, der erst jetzt passt - zentriert den Block neu und
erzwingt einen vollstaendigen Neuaufbau (`RENDER_FULL`). Der
Zeilen-Diff (4.3) ueberschreibt nur, was er schreibt; ohne das bliebe
beim Schrumpfen die alte Ausgabe in den Spalten stehen, die der Block
gerade aufgegeben hat - und weil die Gegner jetzt auch nach links
wachsen, wandert dabei die linke Kante selbst.

Nur in Stufe 2 sendet ein Client Feld-Snapshots; der Hub schaltet das je
Client per `NEEDBOARD` (siehe 5.4), sodass kleine Terminals keine
Snapshot-Last erzeugen. Genau das ist die Antwort auf "bei vielen
Spielern und kleinem Terminal nur Reihen und Bloecke": die Stufen 1 und 0
uebertragen und zeigen nur noch Zaehler.

Uebertragene und angezeigte Statistiken je Mitspieler (Stufe 2 zeigt
alle, Stufe 1 die ersten vier, Stufe 0 nur Name und Rows):
Name, Rows (gewichtete Reihen = Score), Lines, Stapelhoehe,
eingehende/ausstehende Garbage, Level, Gold- und Silberzaehler,
Status (`lobby`/`play`/`ko`/`gone`). Bewusst **nicht** uebertragen:
Next-Queue und Hold des Gegners (waere im Original nicht sichtbar und
kostet Bandbreite), die Spielzeit (der Hub kennt die Rundenzeit selbst),
Tastendruecke.

Jeder Slot bekommt eine feste Akzentfarbe fuer Name und Rahmen, damit
Zuordnung auch ohne Namenslesen funktioniert.

**Dieselben Spalten zeigt die Demo-Wiedergabe** (seit 1.4.0, siehe
5.20): sie fuellt die `MP_PEER_*`-Tabellen aus ihrer Simulation statt
aus dem Netz, sodass `render_peer_column` unveraendert bleibt. Zwei
Dinge sind dort anders - in der Mitte sitzt der Sitzplatz im **Fokus**
statt des eigenen Feldes, und die Mini-Felder tragen den **fallenden
Stein** -, beides mit seiner Begruendung in 5.20.

### 5.7 Garbage-Regeln

**Stoerreihen sind seit 1.1.0 abschaltbar und anfangs aus** (siehe die
Sitzungseinstellungen in 5.1). Alles in diesem Abschnitt beschreibt die
Runde, in der der Gastgeber sie eingeschaltet hat; ist der Schalter aus,
faellt genau dieser Teil weg - ein Abbau zaehlt weiter fuer die Rows,
er schickt nur nichts los (`hub_msg_clear` kehrt frueh zurueck), und die
"Muell"-Zeile verschwindet aus dem HUD.

- **Angriffswert eines Reihenabbaus** (Hub-Berechnung aus `CLEAR`):
  - 1/2/3/4 Reihen -> 0/1/2/4 Garbage-Reihen (Tetris lohnt sich),
  - je **Silber-Quadrat** in den abgebauten Reihen: **+2**,
  - je **Gold-Quadrat**: **+4**,
  - Deckel: **10** Reihen pro Lock.
  Die Werte spiegeln die Reihenwertung aus 3.2 (1/+5/+10) in halbierter
  Form und sind justierbar (`GARBAGE_*` in `lib/hub.sh`). Nach
  Playtesting nachziehen.
- **Verrechnung (Cancel):** eingehende Garbage wird zunaechst in einer
  Warteschlange gehalten. Ein eigener Abbau reduziert erst die eigene
  Warteschlange, nur der Rest geht raus. Das belohnt Gegenangriffe statt
  reiner Reaktion.
- **Einspielen:** ausstehende Garbage wird **beim naechsten Lock nach dem
  Reihenabbau** von unten eingeschoben, nie waehrend ein Stein faellt.
  Damit bleibt der laufende Zug planbar; die Warteschlange ist im HUD
  als Balken neben dem Feld sichtbar (Vorwarnung).
- **Form der Garbage-Reihe:** volle Reihe mit **genau einem Loch**; die
  Lochspalte kommt vom Hub (`GARBAGE <count> <hole>`) und bleibt fuer
  alle Reihen eines Angriffs gleich. Der Hub zieht sie aus seinem
  eigenen RNG, damit kein Client sie beeinflussen kann.
- **Auswirkung auf das Quadrat-System:** Garbage-Zellen bekommen die
  eigene Sorte `x`, Instanz-ID 0 und gelten als "zerschnitten"; sie
  koennen also nie Teil eines Quadrats werden. Das Hochschieben
  verschiebt `BOARD`, `BOARD_ID` und `BOARD_SQ` zeilenweise gemeinsam -
  Instanzen bleiben unversehrt und behalten ihren Gold-/Silber-Status,
  nur ihre Koordinaten wandern. Faellt dabei eine belegte Zelle aus dem
  sichtbaren Bereich oder kollidiert der aktive Stein nach dem
  Verschieben, ist das ein Top-Out.
  **Dieser Teil existiert seit 0.49.0 bereits**: der Hochwasser-Modus
  (siehe 3.6) schiebt genau solche Reihen ein und hat dafuer
  `GARBAGE_CELL` und `board_flood_row` (`lib/board.sh`) samt der
  Top-Out-Pruefung mitgebracht. Der Mehrspieler-Modus wird beides
  benutzen, statt eine zweite Sorte Stoerreihe einzufuehren; offen
  bleibt fuer ihn nur, mehrere Reihen auf einmal einzuschieben und die
  Lochspalte vom Hub statt aus `RANDOM` zu nehmen.
- **Zielwahl:**
  - 2 Spieler: der Gegner, trivial.
  - 3+ Spieler: Standard `random` (der Hub waehlt je Angriff einen
    lebenden Gegner), Alternativen `all` (jeder Gegner bekommt die volle
    Menge, sehr aggressiv) und `even` (gleichmaessig aufgeteilt, Rest an
    einen zufaelligen). Umschaltbar in der Lobby, vom Hub entschieden
    und in `KO`/`GARBAGE` nachvollziehbar geloggt. Eine manuelle
    Zielauswahl per Taste ist bewusst ausgeklammert (Tastenbelegung ist
    voll, und sie skaliert schlecht).

### 5.8 Rundenende, Ausscheiden, Verbindungsabbruch

- **Top-Out:** Der Client sendet `TOPOUT`, spielt nicht weiter und wird
  **Zuschauer** - er sieht die verbleibenden Felder bis zum Rundenende.
  Der Hub vergibt den Platz von hinten (erster Ausgeschiedener = letzter
  Platz) und meldet `KO <slot> <platz>`.
- **Sieg: haengt am Modus** (seit 1.1.0, siehe 5.1). In `survival` ist
  es der letzte lebende Spieler: steigen alle bis auf einen aus, ist die
  Runde vorbei (`END <slot>`). In `sprint` sind es die meisten Rows,
  wenn die Uhr des Hubs abgelaufen ist, in `ultra` der erste Spieler am
  Rows-Ziel; in beiden endet die Runde ausserdem, wenn **alle**
  ausgeschieden sind, und dann entscheiden ebenfalls die Rows. Bei
  Gleichstand entscheidet der niedrigere Slot - eine Runde braucht eine
  Antwort, und die Slot-Reihenfolge ist der einzige Tiebreaker, der fuer
  alle gleich aussieht.
- **Verbindungsabbruch eines Clients:** EOF oder 6 s ohne `PONG` ->
  Status `gone`, gilt wie ein KO, die Runde laeuft weiter. Kein
  Reconnect in v1 (Zustandsuebertragung waere aufwendig; die Runde
  dauert wenige Minuten). **Der Unterschied zum Top-Out steht im `KO`
  selbst** (seit 1.4.1, siehe 5.4): der Hub schickt den Grund mit dem
  Platz, sodass Fusszeile und Aufnahme sofort `Weg` von `K.O.`
  unterscheiden. Ihn aus dem `ROSTER` zu lesen ging nicht auf - er kommt
  erst am Ende des Hub-Ticks und damit hinter `END`, wenn genau dieses
  Ausscheiden die Runde entschieden hat (Begruendung in 5.20).
- **Ausfall des Hubs:** alle Clients bekommen EOF, zeigen "Verbindung
  verloren" und kehren ins Hauptmenue zurueck. Die Runde wird wie ein
  abgebrochenes Spiel behandelt und gemaess 3.3 gewertet (abgebrochene
  Runden zaehlen). **Ein EOF setzt allerdings voraus, dass ueberhaupt
  noch jemand da ist, der die Verbindung schliesst** - deshalb gibt
  jeder Client seit 1.2.0 zusaetzlich nach `MP_TIMEOUT_MS` (6000 ms)
  ohne eine einzige empfangene Zeile von selbst auf (Nutzerwunsch,
  `mp_link_silent`, siehe 5.4): ein ausgeschalteter Rechner, ein
  gezogenes Kabel oder ein WLAN, das mitten in der Lobby weg ist,
  schickt kein EOF. Gefragt wird an jeder Warte-Stelle - Lobby,
  Einstellungsmenue, Namensabfrage, Countdown und Game-Loop -, sodass
  eine tote Sitzung nirgends stehen bleibt; im Game-Loop endet die
  Runde damit wie bei jedem anderen Verbindungsverlust.
- **Der Gastgeber verlaesst die Lobby:** die Sitzung zieht zum zuerst
  beigetretenen Spieler um, der alte Hub endet, alle bekommen den neuen
  Gastgeber genannt und bestaetigen ihn mit Enter (seit 1.2.0,
  ausfuehrlich in 5.1). Findet sich kein Nachfolger, sagt der Hub das
  mit `CLOSED` und die Clients kehren ins Menue zurueck. **Waehrend der
  Runde** ist das Weggehen des Gastgebers dagegen ein gewoehnliches
  Ausscheiden wie bei jedem anderen.
- **Verlassen ueber das Menue:** wie im Einzelspieler beendet "Runde
  beenden" die Runde; zusaetzlich geht ein `BYE` raus. Eine
  Mehrspieler-Runde kann **nicht** ins Hauptmenue gelegt und spaeter
  fortgesetzt werden (die anderen warten nicht) - der Eintrag "Ins
  Hauptmenue" fehlt im Mehrspieler-Pausenmenue.
- **Pause:** eine echte Pause gibt es im Mehrspieler nicht. Umgesetzt
  seit 1.1.0: `p` tut schlicht nichts (eine Einblendung, die nichts
  anhaelt, waere die verwirrendere Antwort), und `Esc`/`x` oeffnet ein
  eigenes Menue mit "Fortsetzen" und "Runde verlassen"
  (`mp_pause_menu`, `lib/mp.sh`). Es **leert die Leitung weiter**,
  waehrend es offen ist - ein Menue, das nicht mehr liest, liefe in den
  Ping-Timeout und flaege aus einer Runde, die niemand verlassen
  wollte. Das eigene Feld steht solange still; genau das sagt der Text
  des Menues, damit niemand es fuer eine Pause haelt.
- **Wertung und Persistenz (Nutzerentscheidung):** in Statistik und
  Weltwunder-Fortschritt fliesst **allein die eigene Leistung** ein.
  Was das im Einzelnen heisst:
  - **Weltwunder und Statistik zaehlen wie im Einzelspieler**, mit den
    Reihen, die dieser Spieler selbst abgebaut hat - es sind echte
    Reihen, gelegt und geraeumt von ihm. Eine Reihe, die zum Teil aus
    Garbage bestand, zaehlt dabei voll mit: sie wegzuraeumen war seine
    Arbeit, und woher die Zellen kamen, weiss der Zaehler nicht.
  - **Von den Mitspielern fliesst nichts ein.** Kein Zaehler des Hubs,
    keine Reihen der Gegner, und auch der Sieg selbst bringt keine
    Reihen - er ist ein Ergebnis, keine Leistung in Reihen. Damit ist
    ein Weltwunder auf demselben Weg gebaut, egal ob allein oder zu
    fuenft gespielt wurde.
  - **Die Statistik bekommt den Mehrspieler als eigenen Modus**
    (`mode_versus_*`, siehe die Modus-Zaehler in 4.5), dazu die zwei
    Zahlen, die es nur hier gibt: Siege und die gesendete bzw.
    erhaltene Garbage. Sie stehen neben den Modus-Zaehlern und nicht
    in den Gesamtzaehlern - die zaehlen Reihen, nicht Duelle.
  - **Die Runde kommt in eine eigene Bestenliste**
    `highscore-versus` statt in die Marathon-Liste - dasselbe Muster,
    das dieses Projekt fuer die fuenf Einzelspieler-Listen anwendet;
    Begruendung in 4.5.

### 5.9 Auswirkungen auf bestehende Systeme

- **Rendering-Performance:** mit bis zu fuenf Feldern reicht ein
  "kompletter Frame als String" nicht; der Zeilen-Diff samt Cache der
  liegenden Feldreihen (seit 0.22.0, siehe 4.3) ist die Voraussetzung;
  fuer die Mini-Felder der Mitspieler ist der Diff genauso zu nutzen.
- **Game-Loop:** pro Tick zusaetzlich Socket leeren, Peer-Puffer
  aktualisieren, eigenen Zustand senden (nur bei Aenderung). Der
  Sendepfad darf nie blockieren (voller Socketpuffer -> Nachricht
  verwerfen, ausser bei `CLEAR`/`TOPOUT`, die zuverlaessig zugestellt
  werden muessen).
- **`flash_rows`** haelt den Loop heute ~280 ms an. Im Mehrspieler darf
  das die Verbindung nicht verhungern lassen: waehrend der Animation
  wird der Socket weiter geleert (Tastendruecke bleiben wie bisher
  verworfen).
- **Seed:** der Hub-Seed muss in das Zahlenfeld des Protokolls passen
  (neun Stellen, `PROTO_NUM_RE`), deshalb nimmt `hub_start_round` ihn
  modulo 1.000.000.000 - egal ob er gewuerfelt wurde (die Maske
  `0x3FFFFFFF` reicht bis 1.073.741.823) oder aus `--seed` kam, das
  Ziffern beliebiger Laenge entgegennimmt. Ein zu langer Seed wird von
  **jedem** Client als fehlerhafte Nachricht verworfen; jeder behaelt
  dann sein eigenes `RANDOM` und spielt eine **andere Steinfolge** -
  genau die Fairness, fuer die der gemeinsame Seed da ist (siehe 5.1),
  und auf dem Bildschirm stuende nichts davon. Ein Seed, der vom
  gewuenschten abweicht, ist das erheblich kleinere Uebel als einer, den
  niemand bekommt.
- **Seed (CLI):** `--seed` wird im Mehrspieler vom Hub-Seed uebersteuert; ein
  gesetzter `--seed` beim Host wird zum Sitzungs-Seed.
- **Terminalgroesse:** der SIGWINCH-Pfad waehlt zusaetzlich die
  Detailstufe neu (siehe 5.6).
- **Demo-Schicht:** eine Mehrspieler-Runde wird wie jede andere
  mitgeschnitten, zeichnet aber **alle Teilnehmer** auf
  (Nutzerentscheidung, Zielanforderung und Architektur siehe 5.20). Sie
  ist damit die einzige Stelle, die nicht nur das Demo-Format erweitert,
  sondern auch das Protokoll: die Zuege der Mitspieler kommen sonst
  nirgends an, und ohne sie waere ein Gegner in der Wiedergabe nur ein
  Standbild.
- **Debug-Modus:** neue Datei `net.log` (auch die empfangenen Beacons,
  sie sind der erste Kontakt mit Fremddaten); `events.log` bekommt
  Mehrspieler-Ereignisse (Join/Leave, Garbage rein/raus, KO, Hub-Start).
- **Paketierung:** `socat` als `Recommends`; `make install` unveraendert.
  Kein `Depends`, obwohl `socat` fuer den Mehrspieler jetzt gesetzt ist
  (5.2) - das Spiel ist ohne ihn vollstaendig einzelspielerfaehig, und
  ein `Depends` wuerde jeder Einzelspieler-Installation ein Paket
  aufzwingen, das sie nie benutzt.

### 5.10 CLI und Konfiguration

Neue Optionen (jeweils auch als Umgebungsvariable, Praezedenz
Standard < Config < Env < CLI, wie in Abschnitt 6 gefordert):

| Option | Umgebung | Bedeutung |
| --- | --- | --- |
| `--mp-host` | `ROWHAMMER_MP_HOST` | Sitzung eroeffnen (ein Schalter ohne Argument; den Namen setzt `--mp-session`) |
| `--mp-join ZIEL` | `ROWHAMMER_MP_JOIN` | Beitreten: Sitzungsname oder `HOST[:PORT]` (siehe 5.2) |
| `--mp-session NAME` | `ROWHAMMER_MP_SESSION` | Name der eroeffneten Sitzung, 1-16 Zeichen `[A-Za-z0-9_-]`; Vorgabe ist der Benutzername, auf dieses Muster reduziert (leeres Ergebnis wird `player`) |
| `--mp-transport MODE` | `ROWHAMMER_MP_TRANSPORT` | `lan` (Standard) oder `unix` |
| `--mp-port N` | `ROWHAMMER_MP_PORT` | TCP-/Beacon-Port, Standard 27301 (nur `lan`) |
| `--mp-dir DIR` | `ROWHAMMER_MP_DIR` | Sitzungsverzeichnis (nur `unix`, siehe 5.2) |
| `--mp-max N` | `ROWHAMMER_MP_MAX` | Obergrenze der Spielerzahl 2..5, Standard 5 (siehe 5.1) |
| `--mp-view MODE` | `ROWHAMMER_MP_VIEW` | `auto`, `full`, `compact`, `score` |
| `--mp-target MODE` | `ROWHAMMER_MP_TARGET` | `random`, `all`, `even` (nur Host) |
| `--mp-mode MODE` | `ROWHAMMER_MP_MODE` | `survival` (Standard), `sprint`, `ultra`: womit eine eroeffnete Sitzung startet (siehe 5.1) |
| `--mp-garbage on\|off` | `ROWHAMMER_MP_GARBAGE` | Stoerreihen einer eroeffneten Sitzung, Standard `off` |
| `--mp-hub` | - | interner Modus: Hub-Prozess (nicht dokumentiert im Menue) |
| `--mp-bridge` | - | interner Modus: Socket-Bridge |
| `--mp-discover` | - | interner Modus: Beacon-Sammler (siehe 5.3) |
| `--mp-bot` | `ROWHAMMER_MP_BOT` | Testclient ohne Terminal, spielt zufaellig |

Menuefuehrung: "Mehrspieler" -> "Spiel eroeffnen" / "Spiel beitreten"
(Liste der gefundenen Sitzungen: im Transport `lan` aus den Beacons,
im Transport `unix` aus dem Glob ueber `MP_DIR`, je mit Name und
Spielerzahl) / "Direkt verbinden" (Adresse von Hand, siehe 5.2) /
"Zurueck". Danach eine Lobby mit Spielerliste, Bereitschaftsstatus, den
**Sitzungseinstellungen** (Modus und Stoerreihen, sichtbar fuer alle,
aenderbar nur vom Host ueber den Eintrag "Einstellungen", siehe 5.1)
und - fuer den Host - Start und die **eigene Adresse samt Port** zum
Durchsagen (siehe 5.2). **Der Start gehoert
allein dem Host** (5.1): er sieht den Eintrag, sobald ein zweiter
Spieler da ist, und niemand wartet auf eine vorher festgelegte Zahl.

