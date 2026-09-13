# rowhammer - Konzept: Demo-Aufzeichnung im Mehrspieler (5.20)

Teil des technischen Konzepts von rowhammer. Die Abschnittsnummern sind
die aus [CLAUDE.md](../../CLAUDE.md) und bleiben stabil
(Arbeitsregel 6.1): ein Verweis der Form `CLAUDE.md 5.20` im Code meint
den gleichnamigen Abschnitt hier. Die Datei fuehrt den **aktuellen**
Stand samt seiner Begruendung; was abgeloest wurde, steht in
[HISTORY.md](../../HISTORY.md), was noch fehlt, in
[TODO.md](../../TODO.md).

### 5.20 Demo-Aufzeichnung im Mehrspieler

Dieser Unterabschnitt gehoert zu **Phase 5** und steht trotzdem hinter
den Phase-6-Abschnitten, damit die Nummerierung 5.11-5.19 nicht wandert
und die Verweise darauf gueltig bleiben (Arbeitsregel 6.1). Er
beschreibt Format und Architektur der Mehrspieler-Demo, gebaut in den
Teilschritten 9.1 bis 9.14 (Unterbau und Aufzeichnung mit 1.3.0,
Wiedergabe und Gegenprobe mit 1.4.0).

**Warum eine Mehrspieler-Runde nicht wie jede andere aufgezeichnet
wird.** Eine Demo speichert Zuege, keine Bildschirme (3.8). Die eigenen
Zuege liegen vollstaendig vor; die **Zuege der Mitspieler** kommen
dagegen nur deshalb an, weil das Protokoll sie eigens verteilt
(`ACT`/`PEERACT`, Version 4, siehe unten und 5.4) - uebertragen werden
sonst nur ihre Zaehler (`PEER`) und, nur in Detailstufe 2,
Feld-Schnappschuesse (`PEERBOARD`, 200 Zeichen, max. 5 Hz, siehe 5.6).
Daraus liesse sich keine Runde nachspielen: ein Gegner waere ein
5-Hz-Standbild ohne fallenden Stein, ohne Next und ohne Hold.

**Leitentscheidung: der Vollausbau** (Nutzerentscheidung). Eine Aufnahme
ist eine **vollstaendige Aufzeichnung der Partie** und nicht die Sicht
eines Einzelnen: sie traegt fuer **jeden** Teilnehmer denselben
Ereignisstrom, den sie fuer den eigenen traegt, die Wiedergabe simuliert
alle Felder gleichzeitig echt, und der Fokus wechselt waehrend der
Wiedergabe frei mit den Pfeiltasten - der gewaehlte Spieler sitzt
mittig, die uebrigen sitzen wie gewohnt um ihn herum (5.6). Damit ist
eine Aufnahme **unabhaengig von der Detailstufe**, in der sie entstand:
auch eine im Scoreboard-Modus gespielte Runde spielt mit vollen
Gegnerfeldern ab. Der Grundsatz aus 3.8 bleibt dabei unangetastet - **die
Aufzeichnung erzwingt keine Schnappschuesse** und aendert das Spiel
nicht; `NEEDBOARD` entscheidet weiter allein die Detailstufe.

**Je Teilnehmer eine eigene Datei, lokal.** Eine zentrale Aufnahme beim
Hub bringt nichts: er sieht dieselben Ereignisse wie jeder Client, die
Datei laege nur beim Gastgeber, und ein Client, der ohnehin alles
empfaengt, schreibt sie sich selbst. Im Uebrigen gelten die Regeln aus
3.8 und 4.10 unveraendert - Ablage beim echten Rundenende, atomar,
`DEMO_MAX`, Schutz ueber den Runden-Hash, und eine Wiedergabe wird nie
gewertet.

**Zielanforderung.**

1. Eine Mehrspieler-Runde wird bei jedem Teilnehmer in seinem eigenen
   Datenverzeichnis aufgezeichnet.
2. Die Aufnahme ist vollstaendig und symmetrisch: jeder Teilnehmer ist
   aus Zuegen reproduzierbar, kein Feld-Schnappschuss wird zur
   Wiedergabe gebraucht.
3. Die Aufnahme ist unabhaengig von der Detailstufe des aufzeichnenden
   Terminals.
4. Die Wiedergabe simuliert alle Felder durch dieselben Spielfunktionen
   wie eine echte Runde (3.8).
5. Der Fokus wechselt waehrend der Wiedergabe frei mit Pfeil
   links/rechts; der fokussierte Spieler steht mittig, mit vollem HUD,
   Hold und Next.
6. Tempo (0.25x bis 4x), Pause und die Rueckkehr zur Liste
   funktionieren unveraendert.
7. Der Kasten am Ende nennt zusaetzlich die Platzierung der Runde.
8. Die Aufzeichnung aendert das Spiel nicht: der Verkehr einer Runde
   ist derselbe, ob `--demo-record on` oder `off` gesetzt ist.
9. Eine Wiedergabe wird nie gewertet und sendet nie ein Byte.
10. Eine von Hand bearbeitete Aufnahme kann weder Code ausfuehren noch
    einen Prozess starten noch das Terminal uebernehmen (5.5).
11. Einzelspieler-Aufnahmen im Format 2 bleiben lesbar.
12. Eine an einem Verbindungsverlust abgebrochene Runde wird behalten
    und als solche gekennzeichnet (`end=lost`).

**Nicht Ziel:** die Gegnerfelder waehrend der laufenden Runde zu
simulieren. Die Mini-Felder kommen im Spiel weiterhin aus den
`PEERBOARD`-Schnappschuessen (5.6); nur die Wiedergabe simuliert.

**Fuenf Rundenzustaende gleichzeitig: Namerefs.**
Der Rundenzustand liegt in Globals - Brett, Instanztabellen, Queue,
Beutel, der aktive Stein, die Zaehler, `LOCK_PENDING`, `GAME_OVER`, die
Garbage-Warteschlange; die verbindliche Liste ist `game_reset`
(`rowhammer.sh`). Fuenf davon gleichzeitig zu halten, ohne die ganze
Rundenlogik zu parametrieren, loesen **Namerefs** (`declare -n`):

```
unset BOARD                      # eine vorhandene Array-Variable MUSS
declare -g -n BOARD=D0_BOARD     # vorher weg - "unset -n" reicht NICHT
declare -g -n BOARD=D1_BOARD     # danach beliebig umbindbar, ohne unset
```

Gemessen (Bash 5.2): indizierte Arrays, assoziative Arrays und Skalare
funktionieren gleichermassen, Funktionen schreiben durch den Nameref auf
den richtigen Slot, und **ein Kontextwechsel ueber 30 Namen kostet
0,1 ms** - bei fuenf Wechseln je Frame und 30 fps sind das 1,5 % einer
CPU. Der kopierende Weg (Zustaende hin- und herkopieren) waere ein
Vielfaches davon und scheidet aus.

Zwei Konsequenzen:

- **Das Bash-Minimum steigt von 4.0 auf 4.3** (Namerefs, 2014). Das
  Spiel bevorzugt ohnehin schon Bash 5 (`${EPOCHREALTIME}`, siehe 4.3);
  Paketabhaengigkeiten, 4.1 und die README ziehen nach, und ein
  Startcheck sagt es mit einer klaren Meldung statt mit einem
  Syntaxfehler.
- **Ein eigenes Modul `lib/state.sh`** (gebaut mit 9.1) haelt die Liste
  des Rundenzustands (`STATE_VARS`, je Eintrag die Art - indiziertes
  Array, assoziatives Array oder Skalar - und der Name) und die
  Funktionen `state_new`, `state_bind` und `state_release`; dazu kamen
  beim Bauen `state_unbind` und `state_release_all`. Die Liste ist damit
  die einzige Stelle, an der der Rundenzustand aufgezaehlt wird - ein
  kuenftiger Zaehler wird dort eingetragen, sonst nirgends. Drei
  Festlegungen aus der Umsetzung:
  - **`state_unbind` musste dazu**, weil `unset` auf einem Nameref der
    Referenz folgt und die Daten dahinter loescht statt den Zeiger. Nur
    `unset -n` loest die Bindung; ohne diese Funktion gaebe es keinen
    Weg zurueck zu gewoehnlichen Globals, den eine Wiedergabe beim
    Verlassen braucht.
  - **Die Sitzungs- und Schleifenzustaende bleiben draussen** (`DIRTY`,
    `RENDER_FULL`, `GAME_EXIT`, `GAME_SUSPENDED`, `GAME_RESTART`,
    `REDRAW_PENDING`, `NOW_MS`) und ebenso, was nur innerhalb eines Locks
    lebt (`NEXT_TYPE`, `FULL_ROWS`, `FLASH_ROWS`). Eine Wiedergabe von
    fuenf Runden zeichnet ein Bild und hat ein Abbruch-Flag; und was die
    Funktion nicht ueberlebt, die es erzeugt hat, kann auch kein Slot
    ueber einen Kontextwechsel tragen.
  - **`tools/state-check.sh` haelt die Liste ehrlich** (Abnahme von 9.1,
    im CI): es legt fuenf Slots an, schreibt in jeden - aus einer
    Funktion heraus, so wie es die echten Rundenfunktionen tun - und
    liest alle fuenf zurueck; und es liest die Zuweisungen aus
    `game_reset` und verlangt, dass jede in `STATE_VARS` steht oder in
    der kurzen Liste der Sitzungszustaende. Damit kann die Liste nicht
    hinter dem Spiel zurueckbleiben, ohne dass es auffaellt.

**Protokoll Version 4: die Zuege werden verteilt** (gebaut mit den
1.3.0).
Sie ist mit dem Vollausbau entschieden. Der Einwand von damals - jeder Client
muesste bis zu vier fremde Runden mitsimulieren - **greift hier nicht**:
uebertragen und mitgeschrieben werden die Zuege, simuliert wird erst bei
der Wiedergabe.

- **`ACT <t> <tokens>`** (Client -> Hub): die eigenen Ereignisse eines
  Zeitfensters. `tokens` sind die Ereignisse im Alphabet der Demo mit
  ihren Deltas (`120l60g0h`), `t` die Rundenzeit in Millisekunden, von
  der das **erste** Delta zaehlt. Gesendet alle `MP_ACT_MS` (100 ms),
  wenn etwas passiert ist - rund zehn Nachrichten je Sekunde und
  Spieler. Drei Dinge, die beim Bauen festgelegt wurden:
  - **`t` ist die Basis des Fensters, nicht der Zeitpunkt des ersten
    Tokens.** Konkret: die Rundenzeit des letzten Tokens des
    *vorherigen* Fensters (am Rundenanfang 0). Damit sind die Deltas
    ueber Fenstergrenzen hinweg durchgehend - `ACT 0 53c` gefolgt von
    `ACT 53 67c68c` -, und ein Empfaenger muss nie raten, worauf sich
    das erste Delta bezieht. Die Alternative (`t` = Zeitpunkt des
    ersten Tokens, dessen Delta dann immer 0) haette ein Byte je
    Nachricht gekostet und dieselbe Information getragen.
  - **Das Feld hat feste Grenzen** (`PROTO_ACT_RE`): hoechstens sechs
    Ziffern je Delta und hoechstens 48 Tokens, zusammen also nie mehr
    als 336 Zeichen - so kann die Nachricht `MP_LINE_MAX` (512) nicht
    sprengen, wie auch immer sie zusammengesetzt ist. Ein volles
    Fenster geht vorzeitig raus, statt gekuerzt zu werden: ein
    verlorener Zug wuerde eine Aufnahme stillschweigend auseinander
    laufen lassen.
  - **Nur das Bewegungsalphabet** (`l r c a s h o g k`). Die Ereignisse,
    die ein Hub oder eine Aufnahme selbst herleitet - eingehende
    Stoerreihen, Warteschlangenlaenge, Ausscheiden - darf ein Client
    nicht behaupten; und die Flutreihe `w<spalte>` gehoert dem
    Hochwasser-Modus, der im Mehrspieler nicht vorkommt.
- **`PEERACT <slot> <t> <tokens>`** (Hub -> alle ausser dem Absender):
  unveraendert weitergereicht. Der Hub schaut nicht hinein und merkt
  sich nichts davon - es ist die einzige Nachricht, die er rein
  weiterreicht, weil die Zuege fuer die Sitzungslogik nichts bedeuten
  (was ein Abbau wert ist, rechnet er aus `CLEAR`). Angenommen nur von
  einem Slot, der wirklich spielt.
- **`GARBAGE` und `QUEUE` bekommen einen Slot vorangestellt** und gehen
  an alle statt nur an den Betroffenen. Sie sind die einzige Eingabe in
  ein fremdes Feld, die nicht aus dessen Zuegen kommt, und der Hub ist
  ihre Quelle (5.7). **Handeln darf nur der genannte Slot**: die
  anderen schreiben die Zeile mit und lassen ihre eigene Warteschlange
  in Ruhe - was die Warteschlange eines Mitspielers ist, sagt dessen
  `PEER`, und eine zweite Quelle fuer dieselbe Zahl koennte von ihr nur
  abweichen.
- **Gesammelt wird an derselben Stelle wie fuer die Aufnahme.** Die
  zehn Stellen, an denen einer Runde etwas zustoesst, rufen seit 1.3.0
  `round_event` (`rowhammer.sh`) statt `demo_record_event`; der Trichter
  gibt das Ereignis an beide Verbraucher desselben Alphabets weiter -
  die Aufzeichnung und den Zugstrom. Auch der Test-Bot (`--mp-bot`)
  geht durch ihn, sonst waeren die Stroeme nur mit so vielen Terminals
  zu testen wie Spielern.
- Bandbreite: rund 40 B/s je Spieler an Zuegen, verteilt an vier
  andere - unter 1 kB/s fuer die ganze Sitzung, gegen die 6 kB/s der
  Schnappschuesse (5.4) also nichts.
- **Nachgemessen** an fuenf Teilnehmern in Detailstufe 2 (Messwerte in
  HISTORY.md, 1.3.0): der Zugstrom kostet gut zwei Drittel mehr
  Nachrichten und bleibt damit bei einem Viertel von `MP_RATE_MAX`; die
  Empfangsseite liegt unter einem Zehntel dessen, was ein Tick abraeumen
  kann, der Hub-Tick haelt seinen `PING`-Abstand, und die Bildrate
  bleibt im bisherigen Streubereich. **Keine der beiden Grenzen wurde
  nachgezogen** - eine Zahl, die nicht annaehernd erreicht wird, enger
  zu ziehen bringt nichts, und weiter zu ziehen gaebe nur einem Fluter
  mehr Raum.

Drei Festlegungen dazu:

- **Die Zeitbasis ist die Rundenzeit, nicht die Spieluhr.** Alle
  Teilnehmer haengen am selben Countdown (`MP_START_MS`), das ist die
  einzige gemeinsame Uhr. Die Demo-Uhr laeuft im Mehrspieler deshalb
  **durchgehend** und bleibt insbesondere im Pausenmenue nicht stehen -
  die Gegner spielen dort weiter (5.8), und ihre Zeitstempel kaemen
  sonst gegen eine eingefrorene eigene Uhr. Im Einzelspieler bleibt es
  bei der Spieluhr, dort haelt eine Pause die ganze Welt an.
  Das behebt zugleich einen Fehler, der ohne diese Umstellung entstuende:
  `demo_record_event` rechnet den Stempel aus `PLAY_MS` und `PLAY_LAST`,
  und `play_clock_resume` zieht `PLAY_LAST` nach einem Menue auf
  "jetzt" - der Wert faellt also hinter den zuletzt geschriebenen
  zurueck, die Delta-Klemme auf 0 macht daraus lauter Nullen, und die
  naechsten Sekunden Spiel liefen bei der Wiedergabe im Schwall ab.
- **Das Protokoll gibt damit die Zuege der Gegner preis.** Ein
  manipulierter Client koennte fremde Felder samt fallendem Stein
  nachbauen; die Schnappschuesse liessen den aktiven Stein bisher
  bewusst weg. Nach dem Vertrauensmodell in 5.5 ist das hinnehmbar -
  Schummeln ist ausdruecklich kein Ausschlusskriterium, Prozess- und
  Terminalsicherheit ist es. Es steht hier als bewusste Entscheidung und
  nicht als Nebenwirkung.
- **Gesendet wird immer**, nicht nur bei laufender Aufnahme. Sonst
  aenderte die Aufzeichnung das Spiel (3.8), und `--demo-record off`
  waere am Verkehr zu erkennen.

**Demo-Format Version 3.**
Der Lader nimmt **Version 2 und 3**, geschrieben wird 3. Eine
Einzelspieler-Aufnahme ist eine echte Teilmenge, und die vorhandenen
Aufnahmen - an denen Highscore-Eintraege haengen - bleiben damit
lesbar. Das ist eine bewusste, eng begrenzte Ausnahme von der
Arbeitsregel "keine Abwaertskompatibilitaet" (Abschnitt 6,
Nutzerentscheidung), wie sie 4.5 fuer die Bestenlisten schon einmal
getroffen hat.

```
version=3   game=1.4.0   mode=versus   name=...   date=...
time=123456        eigene Spielzeit (HUD, Statistik)
length=245000      Laenge der Zeitachse = Dauer der Runde
end=over|goal|quit|lost
players=4   slot=1   mpmode=survival   garbage=1   winner=2
peer=0 Alice       je Teilnehmer eine Zeile
peer=1 Bob
pcs=IOTSZJL...     die gemeinsame Steinfolge - eine fuer alle
p=1 120l           <slot> <delta zum letzten Ereignis DIESES slots><aktion>
v=2 41 96 4 1 2 7  Pruefpunkt: die per PEER gemeldeten Zaehler von Slot 2
```

- **"Teilmenge" heisst woertlich: eine Einzelspieler-Aufnahme der
  Version 3 ist byteweise die der Version 2.** Der ganze Block oben -
  `length`, `players`, `slot`, `mpmode`, `garbage`, `winner`, `peer=`,
  `p=` und `v=` - wird nur in einer Versus-Aufnahme geschrieben, und die
  vier Einzelspieler-Modi behalten ihren einen Strom `e=`. Es waere
  gleichmaessiger gewesen, auch dort `p=0` zu schreiben; dann waere
  aber der Schritt, der das Format schreibt (9.6), derselbe geworden,
  der jede vorhandene Wiedergabe bricht - und zwischen ihm und dem
  Schritt, der das neue Lesen bringt (9.8), stuenden Aufnahmen, die
  niemand ansehen kann. Der Leser hat es trotzdem nur mit **einem**
  Modell zu tun: `e=` fuellt Strom 0, `p=<n>` fuellt Strom n.
  `length` fehlt aus demselben Grund im Einzelspieler - dort ist es
  `time`; und `winner` fehlt, wenn es keinen gibt (eine Runde, die
  dieser Client vor dem Ende verlassen hat), statt eine Zahl
  hinzuschreiben, die jemand als Slot liest.
- **Das Delta gilt je Slot, nicht global.** Die Zuege eines Gegners
  treffen mit Netzverzoegerung ein und koennen aelter sein als das
  zuletzt geschriebene Ereignis; je Slot bleibt jeder Strom monoton, und
  die Wiedergabe fuehrt schlicht fuenf Cursor. Was diese Monotonie
  sichert, ist eine Klemme auf 0 - dieselbe, die eine rueckwaerts
  gesprungene Uhr abfaengt. Sie greift regelmaessig bei den drei
  Ereignissen, die vom Hub kommen (`y`, `q`, `n`/`z`): die werden
  gestempelt, wenn sie eintreffen, waehrend die Zuege eines Gegners bis
  zu ein Sendefenster (`MP_ACT_MS`) aelter sind als ihre Ankunft. Der
  betroffene Strom ist danach fuer genau ein Ereignis um hoechstens
  dieses Fenster gestaucht und laeuft dann wieder richtig; die Wirkung
  der Ereignisse selbst verschiebt sich gar nicht, denn Stoerreihen
  werden eingereiht und erst beim naechsten Lock eingeschoben.
- **Das Alphabet** sind die vorhandenen Buchstaben (`l r c a s h o g k`,
  siehe 4.10) plus `y<nn><h>` eingehende Stoerreihen (Anzahl 01 bis 10,
  Lochspalte 0 bis 9), `q<nn>` verbindliche Warteschlangenlaenge,
  `n<n>` Ausscheiden mit Platz und `z<n>` Verbindungsverlust mit Platz.
  `w<spalte>` bleibt dem Hochwasser-Modus. Die Datei kennt damit **nur
  ihr eigenes Alphabet**: keine rohen Protokollzeilen, keine Wiedergabe
  durch den Nachrichten-Dispatcher und keine Verb-Whitelist - eine
  `.demo`-Datei ist Fremddatum im Sinne von 5.5, und was sie nicht
  ausdruecken kann, kann sie auch nicht ausloesen.
  Die Nutzlasten sind **feste Breiten**, weil die Tokens im Protokoll
  ohne Trenner aneinanderstossen (`PROTO_ACT_RE`): eine variable
  Ziffernzahl waere vom Delta des naechsten Tokens nicht zu
  unterscheiden. Zahlen, die nicht hineinpassen, werden beim Schreiben
  gekappt (99 Reihen, Spalte 9, Platz 9) - kein Wert, den dieses Spiel
  je sendet, aber der Hub ist nichts, dem dieses Ende glauben muesste
  (5.5).
- **`y` und `q` werden fuer jeden Slot notiert**, auch fuer die
  Mitspieler: Stoerreihen sind das Einzige, was einem Brett ohne einen
  Zug dahinter zustoesst, und was ein Abbau von einer Warteschlange
  weggekuerzt hat, ist die Rechnung des Hubs - eine Wiedergabe, die die
  Reihen selbst zusammenzaehlt, liefe beim ersten verrechneten Angriff
  auseinander.
- **`n` und `z` stehen im `KO` selbst** (seit 1.4.1, Protokoll 5, siehe
  5.4). Der Grund kommt mit dem Platz, und die Aufnahme schreibt den
  Buchstaben in demselben Moment. **Vorher** sagte das `KO` fuer einen
  Top-Out dasselbe wie fuer eine gerissene Verbindung, der Platz wurde
  vorgemerkt und der Buchstabe erst gesetzt, wenn das `ROSTER` einen
  Hub-Tick spaeter den Zustand nannte - und beim Schliessen der Aufnahme
  als `n`, falls es nie kam. Genau der Fall, fuer den die Verzoegerung
  da war, wurde damit falsch beantwortet: beendet dieses Ausscheiden die
  Runde, ueberholt `END` den Roster (`hub_eliminate` sendet `KO` und
  `END` sofort, den Roster erst am Tick-Ende), und der aufzeichnende
  Client hat seine Buecher laengst geschlossen. Eine gerissene
  Verbindung stand danach als Top-Out in der Datei, und zwar immer dann,
  wenn sie die Runde entschieden hat. Aus demselben Grund traf es die
  laufende Anzeige: `mp_poll` setzte den Zustand hart auf `ko`, bis ein
  Roster ihn richtigstellte.
- **Ein Platz ist noch kein Ausscheiden.** Das dritte `KO`-Feld kennt
  `play` als dritte Antwort: in `sprint` und `ultra` vergibt der Hub am
  Ende **alle** Plaetze nach Rows neu (5.1), auch an Bretter, die noch
  standen. Fuer sie wird nichts geschrieben - sie haben die Runde nicht
  verlassen, die Runde hat sie verlassen, und genau das zeigt die
  Wiedergabe ohnehin ("Runde zu Ende"). Sie behalten damit auch in der
  laufenden Runde ihre Zahlen, statt als `K.O.` in der Fusszeile zu
  stehen. Der Preis ist, dass ihr Platz in der Aufnahme nicht vermerkt
  ist (siehe TODO.md); ein falsches `K.O.` mit Platz war der schlechtere
  Tausch. Ein zweites `KO` fuer einen Slot, der schon eines hat, wird
  dagegen **geschrieben** statt verworfen: die Wiedergabe nimmt schlicht
  den neueren Platz (`demo_apply`), und wer die beiden auseinanderhaelt,
  schreibt die Reihenfolge des Ausscheidens dorthin, wo die Runde anders
  gewertet hat.
- **Eine Steinfolge fuer alle.** Der gemeinsame
  Seed (5.1) gibt jedem dieselbe Folge, nur zu anderen Zeitpunkten. Der
  Aufzeichnende zieht sie deshalb weit genug: er zaehlt je Slot die
  Ereignisse mit, die einen Stein aus der Folge nehmen, und fuellt die
  Folge beim Schliessen der Aufnahme aus seinem **eigenen Beutel** bis
  zum Bedarf des Spielers nach, der am weitesten gekommen ist - auch
  nachdem er selbst ausgeschieden ist (`demo_pieces_topup` in
  `lib/demo.sh`). Vier Festlegungen dazu:
  - **Gezaehlt wird grosszuegig.** Steinverbrauchend sind der Lock
    (`h` und `k`, er setzt immer den naechsten Stein) und das Hold
    (`o`, nur beim ersten Mal). Jedes Hold mitzuzaehlen zieht die Folge
    ein paar Steine zu weit; das kostet ein Byte je Stein, waehrend eine
    zu kurze Folge eine Wiedergabe mittendrin abschneiden wuerde. Genau
    deshalb muss die Zahl auch nicht aus den Stroemen simuliert werden.
  - **Nachgefuellt wird am Ende, nicht waehrend der Runde.** Wie weit
    jemand gekommen ist, steht erst fest, wenn sie vorbei ist, und an
    dieser Stelle kostet die Schleife die Runde nichts mehr.
  - **Aus dem eigenen Beutel.** Er steht genau dort, wo die eigenen
    Zuege ihn gelassen haben - `queue_fill` ist das Einzige, was aus ihm
    nimmt -, und `RANDOM` wird je Runde aus dem `SEED` des Hubs neu
    gesetzt, waehrend `game_reset` den Beutel leert. Weiterziehen setzt
    also die eine Folge fort und kann die naechste Runde der Sitzung
    nicht verschieben.
  - **Der Bedarf ist Spawns + `PREVIEW_COUNT` + 1.** Ein Brett hat neben
    den gespawnten Steinen immer die drei Vorschauen und den naechsten
    in der Queue, und auch die sind aus der Folge gezogen.
- **Der Leser kennt nur ein Modell** (`demo_load` in `lib/demo.sh`, seit
  `lib/demo.sh`): `e=` fuellt Strom 0, `p=<n>` fuellt Strom n, und eine
  Einzelspieler-Aufnahme hat schlicht nichts ausser Strom 0. Vier
  Festlegungen dazu:
  - **Je Strom vier Arrays**, angesprochen ueber **Namerefs**
    (`demo_stream_bind`) - dieselbe Loesung wie fuer den Rundenzustand in
    `lib/state.sh` und aus demselben Grund: gearbeitet wird immer auf
    einem Strom, und ihn zu wechseln darf nicht heissen, vier Arrays zu
    kopieren. Alles, was `DEMO_EV_T`/`DEMO_EV_A` bisher las, liest nach
    dem Laden einer Einzelspieler-Aufnahme genau das, was es vorher las.
  - **Die Deltas werden je Strom aufsummiert**, mit einem Akkumulator je
    Slot: die Stroeme liegen in der Reihenfolge ihres Eintreffens in der
    Datei, und monoton ist die Zeit nur innerhalb eines von ihnen (siehe
    oben).
  - **Ein Pruefpunkt wird an die Zahl der Ereignisse gebunden**, die
    sein Strom bis dorthin hat, nicht an eine Zeit - er ist eine Aussage
    ueber den Strom, keine ueber die Uhr (siehe unten).
  - **Ein Sitzungsblock gehoert einer Versus-Aufnahme und nur ihr.**
    Beide Richtungen werden geprueft: ein `peer=`, `players=` oder ein
    `p=`-Strom in einer Marathon-Aufnahme faellt ebenso heraus wie ein
    `e=` in einer Versus-Aufnahme. Dazu muessen die Sitzungsangaben
    zusammenpassen (mindestens zwei Plaetze, so viele `peer=`-Zeilen wie
    `players`, eigener Slot und Sieger unter ihnen, jeder Strom auf
    einem besetzten Platz, kein Platz ohne Ereignisse). Abgewiesen wird
    **mit Grund** ins Debug-Log (`demo_reject`): auf dem Bildschirm
    steht die eine uebersetzte Meldung, welches Feld welcher Datei nicht
    passte, ist eine Diagnose und gehoert dorthin, wo dieses Spiel seine
    Diagnosen fuehrt (4.6).
- **Die `v=`-Pruefpunkte** sind die Gegenprobe, nicht die Anzeigequelle:
  die Wiedergabe vergleicht ihre Simulation mit den seinerzeit
  gemeldeten Zaehlern und meldet eine Abweichung ins Debug-Log. Damit
  wird eine ganze Fehlerklasse - die Simulation laeuft auseinander -
  sichtbar statt still. Drei Festlegungen dazu:
  - **Sie sind positionsgebunden und tragen deshalb keinen
    Zeitstempel.** Ein Pruefpunkt gilt fuer den Moment, in dem der Strom
    seines Slots das letzte vor ihm geschriebene Ereignis erreicht hat.
    Er ist kein Ereignis, sondern eine Aussage ueber den Strom um ihn
    herum.
  - **Er wird hinter die Zuege gelegt, die er beschreibt.** Ein
    Mitspieler schickt am Ende seines Ticks erst seine Zaehler (`STATE`)
    und danach sein Zugfenster: die Zahlen koennen also bis zu ein
    Fenster vor den Zuegen ankommen, die sie erzeugt haben. Ein dort
    abgelegter Pruefpunkt wuerde einer korrekten Wiedergabe eine
    Abweichung vorwerfen. Also wird der zuletzt gemeldete Stand
    aufgehoben und erst hinter dem naechsten `PEERACT` dieses Slots
    geschrieben.
  - **Hoechstens einer je Sekunde und Slot** (`DEMO_V_MS`, gemessen auf
    der Uhr des Stroms). Die Zaehler aendern sich bei jedem Lock (schon
    wegen der Stapelhoehe), und einen Pruefpunkt je gemeldeter Aenderung
    zu schreiben wuerde eine Fuenf-Spieler-Aufnahme vervielfachen, ohne
    mehr zu pruefen. Den eigenen Slot schreibt der Aufzeichnende dabei
    aus seinen **lebenden** Zaehlern mit: er kam nie ueber das Netz und
    ist damit die schaerfste Probe darauf, ob die Wiedergabe das Spiel
    richtig nachspielt.
  - **Der eigene Pruefpunkt steht vor seinem Ereignis, der fremde
    dahinter.** Das ist derselbe Ort, nur von zwei Seiten erreicht:
    jede Stelle, die `round_event` ruft, meldet die Aktion **bevor** sie
    sie ausfuehrt (siehe 4.10), die lebenden Zaehler sind dort also die
    des vorherigen Ereignisses - und genau das heisst ein Pruefpunkt,
    der "nach den Ereignissen vor ihm" gilt. Hinter das Ereignis
    geschrieben wuerde er den Stand eines Locks behaupten, das noch
    nicht stattgefunden hat, und jeder Pruefpunkt, der auf ein `h` oder
    `k` faellt, wuerde einer korrekten Wiedergabe eine Abweichung
    vorwerfen.

  **Verglichen wird beim Abspielen** (`demo_verify` in `lib/demo.sh`,
  gerufen aus `demo_step` nach jedem einzelnen angewandten Ereignis -
  nach dem ganzen Schwung waere die Stellung schon zwei Ereignisse
  weiter). Ein Cursor je Sitzplatz laeuft durch dessen Pruefpunkte, wie
  einer durch dessen Ereignisse laeuft; stimmen die sechs Zahlen nicht,
  geht eine Zeile mit beiden Staenden ins Debug-Log (4.6), und am Ende
  der Wiedergabe eine mit der Bilanz - **auch ein sauberer Lauf sagt
  das**, sonst hiesse eine fehlende Meldung nur, dass niemand
  hingesehen hat. Auf dem Bildschirm steht davon nichts: wer zusieht,
  kann daran nichts aendern, und Diagnosen fuehrt dieses Spiel im Log.
- **Ein Test-Bot (`--mp-bot`) zeichnet nicht auf.** Seine Runden sind
  Testverkehr, und seine Aufnahmen laegen in einem Datenverzeichnis als
  echte - sie zaehlten gegen `DEMO_MAX` und verdraengten Runden, die
  jemand gespielt hat.

**Ein Strom muss vollstaendig sein.** Ein einziger fehlender Zug
verschiebt den Stein, auf dem er lag, und von da an ist das ganze Brett
dieses Sitzplatzes ein anderes - lautlos, denn niemand vermisst eine
Zeile, die nie ankam. Drei Stellen, an denen genau das passierte - alle
drei gefunden von der Gegenprobe oben, die dafuer da ist:

- **Der Countdown liest die Uhr vor der Leitung** (`mp_countdown`,
  `lib/mp.sh`). Sein letzter Durchlauf wartet bis zu 100 ms auf eine
  Taste und sass damit regelmaessig hinter dem Rundenstart: die ersten
  Zuege aller anderen wurden dort abgeholt, wo es die Runde - und damit
  ihre Aufnahme - noch gar nicht gab. Sie bleiben jetzt im
  Socket-Puffer, den der Game-Loop einen Wimpernschlag spaeter leert.
  Verloren geht dabei nichts: vor `MP_START_MS` kann sich niemand
  bewegen, und eine in dieser Strecke abreissende Leitung merkt der
  Game-Loop im ersten Durchlauf.
- **Der letzte `STATE` geht vor den letzten Zuegen raus**
  (`round_finish`, `rowhammer.sh`). Der Game-Loop schickt die Zaehler am
  Ende eines Ticks und kommt zu diesem einen nicht mehr; ohne ihn ist
  das Letzte, was die anderen von diesem Brett gehoert haben, der Stand
  ein Lock bevor es voll war. Auf dem Schirm ist das eine veraltete
  Stapelhoehe fuer jemanden, der ohnehin draussen ist - in einer
  Aufnahme ein Pruefpunkt hinter Zuegen, die er nicht beschreibt.
- **Der Hub verliert keine angelesene Zeile mehr** (siehe 5.3). Eine
  abgeschnittene Nachricht ist im laufenden Spiel kaum zu sehen, weil
  der naechste Schnappschuss darueber hinweggeht; in der Aufnahme bleibt
  das Loch.

**Wiedergabe.**
Je Frame wird fuer jeden Slot umgebunden, alle faelligen Ereignisse
werden angewandt, und ein Slot, dessen Brett sich geaendert hat, wird in
die vorhandenen `MP_PEER_*`-Tabellen geschrieben; zuletzt wird auf den
Fokus-Slot gebunden. Der Renderer bleibt dadurch fast unveraendert:

- Der **fokussierte** Spieler ist der, auf den die Globals zeigen -
  Spielfeld, HUD, Hold, Next und der Rundenende-Kasten funktionieren
  ohne eine Zeile Aenderung.
- Die **uebrigen** kommen wie im Spiel aus `MP_PEER_BOARD` und den
  `MP_PEER_*`-Zaehlern, nur gefuellt aus der Simulation statt aus dem
  Netz. `render_peer_column` bleibt, wie es ist.
- **`MP_SLOT` ist der Fokus.** `mp_peer_count` schliesst genau diesen
  Slot aus, und die Sitzordnung `[5][3][selbst][2][4]` (5.6) setzt ihn
  in die Mitte. Ein Fokuswechsel ist damit: `MP_SLOT` setzen, den
  Zustand umbinden, `RENDER_FULL` erzwingen.
- Anders als im Spiel zeigen die Mini-Felder **den fallenden Stein**.
  Der Schnappschuss liess ihn weg, weil er unterwegs veraltet waere
  (5.4); in einer Wiedergabe gibt es dieses Problem nicht, und ein Feld
  ohne fallenden Stein saehe neben vier anderen tot aus.
- **Tasten:** Pfeil links/rechts waehlen den Fokus, umlaufend ueber die
  belegten Slots (`demo_focus_step`/`demo_focus_set` in `lib/demo.sh`);
  Pfeil hoch/`+` und Pfeil runter/`-` stellen das Tempo. Beide Paare
  lagen bis 1.3.0 auf demselben Tempo (`LEFT`/`-` und `RIGHT`/`+`, siehe
  3.8), das Aufteilen hat also keine Funktion gekostet - und die Pfeile
  sind das, womit in diesem Spiel jede Liste durchgegangen wird, was die
  Sitzplaetze sind. Eine Aufnahme mit einem einzigen Sitzplatz hat
  schlicht nichts zum Weiterschalten; genau deshalb liegt das Tempo seit
  1.4.3 zusaetzlich auf hoch/runter, sonst haette eine
  Einzelspieler-Wiedergabe ueberhaupt keine Pfeiltaste mehr. Drei
  Festlegungen aus der Umsetzung:
  - **Der abtretende Sitzplatz wird erst veroeffentlicht.** Solange er
    der Fokus war, wurde er aus dem Rundenzustand gezeichnet und
    `demo_step` hat ihn nie in die `MP_PEER_*`-Tabellen geschrieben;
    ohne das naehme er seinen Platz als Gegnerspalte mit einem Bild von
    sich ein, das so alt ist wie der letzte Fokuswechsel.
  - **Die Spieluhr wird mitgenommen.** `PLAY_MS` steht in `STATE_VARS`,
    jeder Sitzplatz hat also eine eigene, und der Loop schreibt die
    Demo-Uhr nur in den gerade gebundenen - und nur, solange die
    Wiedergabe laeuft. Ein Fokuswechsel **nach** dem Ende zeigte sonst
    als Endzeit dieses Sitzplatzes irgendeinen frueheren Moment.
  - **Der Fokus ueberlebt den Neustart** (`r`): wem jemand folgen
    wollte, dem wollte er auch durch die zweite Runde folgen.
  Die HUD-Zeile 18 nennt weiter das Tempo, Zeile 19 den Namen des
  Sitzplatzes im Fokus - mit `>` davor wie der Cursor der
  Bestenlisten-Liste (4.5) und ueber die volle Breite der Spalte statt
  als Wert hinter einer Beschriftung: ein Name darf 16 Zeichen haben
  und ist das einzige Wort auf der Zeile. Er ist das Einzige, was der
  Bildschirm sonst nicht sagt - die Gegner tragen ihren Namen ueber
  ihrer Spalte, das mittlere Feld nie, weil es in einer echten Runde
  das eigene ist.
- **Die Blink-Animation laeuft nur fuer den Fokus.** `flash_rows` haelt
  den Loop an (3.1); bei den uebrigen verschwindet die Reihe sofort,
  denn alles andere hiesse, den Loop bis zu fuenfmal je Sekunde
  anzuhalten.
- **Der Kasten am Ende nennt Platz und Grund** - beides fuer den
  Sitzplatz im Fokus und nicht fuer die Aufnahme, denn der Fokus wandert
  (`demo_focus_outcome` in `lib/demo.sh`, gelesen von
  `render_status_box`). Er hat weiter genau acht Innenzeilen: die
  Platzierung bezahlt die **fuehrende Leerzeile**, die eine
  Einzelspieler-Aufnahme unveraendert behaelt - sie hat keinen Platz zu
  nennen. Vier Festlegungen dazu:
  - **Aufgeschrieben ist nur der Grund des Aufzeichnenden** (`end=`).
    Fuer jeden anderen Sitzplatz wird er aus dem gelesen, was aus ihm
    geworden ist: `ko` heisst oben rausgebaut, `gone` Verbindung weg,
    und wer am Ende noch stand, bekommt "Runde zu Ende" - "Abgebrochen"
    (der Spieler ist gegangen) kann kein Ereignisstrom zeigen.
  - **`end=lost` hat einen eigenen Text** ("Verbindung weg"), statt wie
    bisher unter "Abgebrochen" zu fallen: eine gerissene Leitung ist
    kein Aufgeben.
  - **Der Sieger wird beim Erreichen des Endes markiert**
    (`demo_finish_marks`). Fuer ihn gibt es kein Ereignis - `n` und `z`
    sind, wie man die Runde verlaesst, und er hat keines von beidem
    getan -, also nennt ihn der Kopf der Datei (`winner=`). Ohne das
    saesse das siegreiche Brett in Rundenkleidung da, waehrend jede
    andere Spalte zeigt, wie sie ausging. Im Fokus steht dann
    "GEWONNEN", in der Gegnerspalte "SIEG".
  - **Der K.O.-Kasten wartet auf den Platz.** In der Wiedergabe fallen
    Top-Out und Ausscheiden auseinander: das Brett endet, wo es endete,
    der Platz kommt mit dem `n`/`z`, das der Hub eine Weile spaeter
    schickte. Bis dahin bleibt der Kasten weg - er verdeckte sonst ein
    Brett, um "Platz 0" zu sagen. In einer echten Runde liegt dazwischen
    ein Roundtrip, hier steht es in der Aufnahme.
- **Ausscheiden und Verbindungsverlust stehen verschieden da.** Der Fuss
  einer Gegnerspalte trennt seither `K.O. <platz>` (oben rausgebaut) von
  `Weg <platz>` (Verbindung weg) und kennt mit `SIEG` einen dritten
  Ausgang, den nur eine fertig gelaufene Wiedergabe setzt. Bis dahin
  las sich beides als `K.O.`, obwohl es zwei verschiedene Dinge sind -
  und in einer Wiedergabe ist der Fuss der einzige Ort, an dem sie
  ueberhaupt stehen koennen.

Die Zustaende dahinter
(`demo_seats_scan`, `demo_play_states_build`,
`demo_play_states_release`, `demo_play_peers_begin`/`_end` in
`lib/demo.sh`). Fuenf Festlegungen aus dieser Umsetzung:

- **Ein Modell fuer beide Sorten Aufnahme, auch beim Abspielen.** Die
  Sitzplaetze einer Aufnahme bekommen je einen Rundenzustand, jeder wird
  von genau dem `game_reset` begonnen, mit dem eine echte Runde beginnt,
  und der Bildschirm haengt am gebundenen Platz - eine
  Einzelspieler-Aufnahme ist dann schlicht eine Sitzung zu einem
  (dieselbe Vereinheitlichung, die `demo_load` schon fuer die Stroeme
  macht). Das kostet die alte Einzelspieler-Wiedergabe nichts und
  erspart einen zweiten Weg, der neben dem ersten mitgepflegt werden
  muesste.
- **Die Sitzplaetze werden gelesen, nicht gezaehlt.** `demo_seats_scan`
  sammelt die Plaetze mit Namen ein, statt `0..players-1` anzunehmen:
  das Format erlaubt eine Sitzung mit Luecken (`demo_header_read`
  prueft die Zahl der `peer=`-Zeilen, nicht ihre Nummern), und eine
  Wiedergabe, die das anders sieht, sucht ein Brett, das es nie gab.
- **Die Zeitachse ist `length`, nicht `time`.** Die beiden gehen
  auseinander, sobald der Aufzeichnende frueh ausgeschieden ist und den
  Rest zugesehen hat; die Wiedergabe laeuft ueber die Runde und nicht
  ueber seine Spielzeit. Fuer jeden anderen Modus setzt
  `demo_header_read` `length` auf die Spielzeit, sodass es eine Zahl
  fuer beide ist (`DEMO_TIMELINE_MS`).
- **Der Stand im Steinstrom ist Rundenzustand.** `DEMO_PLAY_POS` steht
  deshalb in `STATE_VARS` (`lib/state.sh`): alle ziehen aus derselben
  Folge (ein Seed, 5.1), aber jeder in seinem eigenen Tempo - die
  Position darin ist so persoenlich wie die Queue, die sie fuellt.
- **Der Rueckbau stellt die Globals wieder her, nicht nur die Zeiger.**
  `state_unbind` deklariert die Namen des Rundenzustands hinterher neu
  (`state_globals_new`), statt sie undefiniert zu lassen: `INSTANCE_CUT`
  und `INSTANCE_SQUARED` sind assoziativ, und ein `=()` auf einen
  undefinierten Namen macht daraus ein indiziertes Array - die Runde
  nach einer Wiedergabe wuerde die Instanztabellen dann ueber eine Zahl
  fuehren, die sie nie gemeint hat. Der Rueckbau laeuft auf jedem Weg
  aus `demo_play` heraus.
- **Die Peer-Tabellen decken nicht `--mp-max` Plaetze ab, sondern alle
  moeglichen** (`MP_SEATS`/`MP_SEAT_MAX` in `lib/mp.sh`, in einer
  Sitzung `MP_MAX`). Eine Aufnahme ist eine Datei, und sie soll keine
  Mitspieler verlieren, weil die Sitzung, die sie ansieht, mit einem
  kleineren `--mp-max` gestartet wurde als die, die sie gespielt hat -
  dieselbe Ueberlegung, auf der `DEMO_STREAM_MAX` steht.

**Die Ereignisse werden angewandt** (`demo_step`,
`demo_peer_publish`, `demo_cursors_reset`, `demo_events_left` und die
vier neuen Buchstaben in `demo_apply`/`demo_apply_out`, alle in
`lib/demo.sh`). Damit spielt jeder Sitzplatz seine Runde wirklich noch
einmal, durch dieselben Spielfunktionen; die Bretter der Mitspieler
stehen in denselben `MP_PEER_*`-Tabellen, aus denen eine laufende Runde
ihre Gegner zeichnet, sodass der Renderer von der Wiedergabe nichts
wissen muss. Sechs Festlegungen aus dieser Umsetzung:

- **Ein Cursor je Sitzplatz, kein Cursor je Datei.** Monoton ist die
  Zeit nur innerhalb eines Stroms (siehe oben); ein gemeinsamer Cursor
  ueber die Datei muesste sie neu sortieren, um dasselbe zu leisten.
  Damit ein Durchlauf der Schleife nicht fuer jeden Sitzplatz dessen
  Strom binden muss, nur um nachzusehen, steht der Zeitstempel des
  naechsten Ereignisses je Sitzplatz daneben (`DEMO_NEXT_MS`, -1 fuer
  einen erschoepften Strom). Gebunden - Zustand und Strom - wird erst
  ein Sitzplatz, der wirklich etwas zu tun hat.
- **Die vier Hub-Buchstaben sind Eingaben in den Rundenzustand, keine
  Sonderwege.** `y<nn><h>` legt die Stoerreihen in die Warteschlange
  desselben `MP_PENDING`/`MP_HOLE`, aus dem `mp_apply_garbage` sie beim
  naechsten Lock einschiebt - der Weg einer echten Runde, also landen
  die Reihen in genau dem Lock, in dem sie damals landeten. `q<nn>`
  **setzt** die Laenge, statt abzuziehen: verrechnet hat der Hub, und
  eine Wiedergabe, die selbst rechnet, laeuft beim ersten
  gekuerzten Angriff auseinander. `n<n>`/`z<n>` beenden den Sitzplatz
  (`GAME_OVER`) und schreiben Zustand und Platz in die
  Mitspieler-Tabellen, wo die Gegnerspalte sie liest.
- **Die Mini-Bretter der Wiedergabe tragen den fallenden Stein.** Der
  Schnappschuss der laufenden Runde laesst ihn weg, weil er unterwegs
  veralten wuerde (5.4); eine Wiedergabe hat keinen Weg, auf dem etwas
  veralten koennte, und ein Brett ohne fallenden Stein saehe neben vier
  anderen tot aus. Gebaut wird es aus `proto_board_encode` plus den vier
  Zellen des Steins - dieselbe Kodierung, die auch ueber die Leitung
  ginge, damit `render_peer_column` unveraendert bleibt.
- **Veroeffentlicht wird nur, was sich geruehrt hat.** `demo_peer_publish`
  laeuft je Sitzplatz erst, wenn dort ein Ereignis angewandt wurde -
  ohne Ereignis aendert sich an einem Brett nichts, auch die Gravitation
  ist eines. Aus demselben Grund meldet `demo_step` zurueck, ob
  ueberhaupt etwas passiert ist: der Bildschirm wird nur dann neu
  gebaut, genau wie im Spiel.
- **Eine Wiedergabe sendet nichts und verbucht nichts, obwohl sie durch
  den Mehrspieler-Code laeuft.** Sie setzt `MP_ACTIVE`, damit der
  Renderer die Gegner zeichnet, hat aber keine Leitung dahinter. Ohne
  Guard meldete das Ende einer simulierten Runde einen Top-Out
  (`round_finish` -> `mp_send_topout` setzt `MP_STATE`) und ein
  Zugfenster liefe in einem Puffer voll, den niemand leert. Die Guards
  sitzen dort, wo diese **Nebenwirkungen** entstehen - `round_finish`
  (`rowhammer.sh`), `mp_act_event`, `mp_send_clear` und das `APPLIED`
  aus `mp_apply_garbage` (`lib/mp.sh`) -, nicht in `net_send`: das ist
  der Transport, und er kennt keine Spielregeln.
- **Die Sitzung wird bei jedem Neustart neu aufgesetzt.**
  `demo_play_peers_begin` steht deshalb **in** der Restart-Schleife und
  vor dem Aufbau der Rundenzustaende: `r` muss den Mitspielern ihre
  leeren Bretter und ihren Zustand "spielt" zurueckgeben, und das
  `mp_reset` darin loescht die Garbage-Warteschlange, die
  `demo_play_states_build` gleich darauf je Sitzplatz vergibt.

