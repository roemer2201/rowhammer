# rowhammer - Konzept: Demos: Konzept und Dateiformat (3.8, 4.10)

Teil des technischen Konzepts von rowhammer. Die Abschnittsnummern sind
die aus [CLAUDE.md](../../CLAUDE.md) und bleiben stabil
(Arbeitsregel 6.1): ein Verweis der Form `CLAUDE.md 4.10` im Code meint
den gleichnamigen Abschnitt hier. Die Datei fuehrt den **aktuellen**
Stand samt seiner Begruendung; was abgeloest wurde, steht in
[HISTORY.md](../../HISTORY.md), was noch fehlt, in
[TODO.md](../../TODO.md).

### 3.8 Demos: Aufzeichnung und Wiedergabe (seit 0.46.0)

Jede gespielte Runde wird mitgeschnitten und laesst sich ueber den
Hauptmenuepunkt **"Demos"** noch einmal ansehen (`lib/demo.sh`,
`menu_demos` in `lib/menu.sh`). Der Menuepunkt steht zwischen
"Statistik" und "Einstellungen" - beides sind Rueckblicke auf bereits
gespielte Runden. Seit 0.52.0 gibt es einen zweiten Weg dorthin: in
einer Bestenliste startet Enter die Aufnahme des ausgewaehlten Eintrags
(siehe 4.5) - dieselbe Wiedergabe, nur von der anderen Seite der
Hash-Verknuepfung aus.

**Aufgezeichnet werden die Zuege, nicht der Bildschirm.** Eine Demo ist
die Liste dessen, was der Runde widerfahren ist: die Tastenaktionen des
Spielers (Bewegen, Drehen, Soft-/Hard-Drop, Hold), die
Gravitationsschritte, das Ablaufen des Lock Delays und die Steinfolge,
mit der die Vorschau-Queue gefuellt wurde. Die Wiedergabe fuettert diese
Liste in **dieselben Spielfunktionen**, die auch eine echte Runde
benutzt (`try_move`, `try_rotate`, `step_down`, `hard_drop`,
`hold_piece`, `lock_and_next`), sie spielt die Runde also wirklich noch
einmal, statt ein Bild davon abzuspielen. Drei Gruende gegen eine
Bildschirmaufzeichnung (etwa im asciinema-`.cast`-Format):

- **Groesse.** Gemessen an echten Runden kostet eine Demo rund
  **2 kB je Spielminute** (etwa 4 Ereignisse je Sekunde a 9 Byte, dazu
  ein Byte je Stein und ein knapp 300 Byte grosser Kopf); eine
  Zehn-Minuten-Runde liegt bei ~20 kB. Ein Frame-Mitschnitt kostet je
  Bildschirmaenderung den halben Bildschirm. Damit ist auch die in der
  Frage nach einer Obergrenze beantwortet: eine reine **Stueckzahl**
  (`DEMO_MAX`, 10 wie die Bestenlisten) reicht, ein
  Gesamtgroessen-Budget waere Aufwand ohne Gegenwert. Die Grenze gilt
  seit 0.46.0 nur fuer die **gewoehnlichen** Aufnahmen; eine, die noch
  einen Highscore-Eintrag haelt, wird nie geloescht (siehe unten).
- **Unabhaengigkeit vom Terminal.** Die Datei enthaelt kein einziges
  ANSI-Byte. Terminalgroesse, Farbmodus, Farbschema und - ausdruecklich
  auch - der **Render-Modus** (`--render-mode partial|full`, siehe 4.3)
  sind damit reine Eigenschaften der *abspielenden* Sitzung: eine im
  Partial-Modus aufgenommene Runde laeuft im Full-Modus korrekt und
  umgekehrt, und eine in `guideline` aufgenommene Runde laesst sich in
  `colorblind` ansehen. Ein Frame-Mitschnitt haette all das festgeschrieben
  und zwingend im Full-Modus aufgenommen werden muessen, weil ein
  Zeilen-Diff nur vor dem Bildschirm Sinn ergibt, den er vorgefunden hat.
- **Robustheit.** Die Steinfolge steht als Buchstabenkette in der Datei,
  **nicht als RNG-Seed**, obwohl das kuerzer waere: `RANDOM` wird einmal
  je Sitzung gesetzt, nicht
  je Runde (eine zweite Runde setzt den Strom fort), und der Generator
  hinter `RANDOM` hat sich zwischen Bash-Versionen geaendert: ein Seed
  wuerde auf einer anderen Bash eine andere Runde abspielen. Ein Byte je
  Stein macht die Frage gegenstandslos.

**Bedienung der Wiedergabe** (Pause und Vorspulen, plus Zeitlupe):

- Pausetaste (`p`) oder Leertaste haelt an und laeuft weiter; angezeigt
  wird das ueber denselben "PAUSED"-Kasten wie im Spiel.
- Pfeil hoch/`+` und Pfeil runter/`-` stellen das Tempo in fuenf Stufen
  von **0.25x bis 4x** (`DEMO_SPEEDS`). Die aktuelle Stufe steht im HUD
  in der linken Spalte (Zeile 18, Label "Demo") - die einzige Angabe,
  die dem Bild sonst fehlen wuerde. Bis 1.3.0 stellten die Pfeiltasten
  links/rechts dasselbe mit; sie waehlen seit 1.4.0 den Sitzplatz einer
  Mehrspieler-Aufnahme (5.20), und seit 1.4.3 tragen dafuer die
  senkrechten Pfeile das Tempo. Der Grund ist derselbe, aus dem die
  waagerechten den Sitzplatz waehlen: eine Einzelspieler-Aufnahme hat
  keinen zu waehlen, und ohne die senkrechten stuenden dort beide
  Pfeilpaare ohne Wirkung.
- Quit-Taste (`x`) oder `ESC` kehrt zur Liste zurueck (zu der, aus der
  die Wiedergabe gestartet wurde - Demo-Liste oder Bestenliste), `r`
  spielt eine durchgelaufene Demo noch einmal von vorn.
- Am Ende erscheint der Kasten ueber dem Spielfeld ("DEMO ENDE" mit
  Rows, Zeit und der Art des Rundenendes) - ein weiterer Ausgang des
  `render_status_box` (siehe 3.6), der bewusst **vor** allen anderen
  greift: auch eine Runde, die im Game Over endete, zeigt beim Abspielen
  den Demo-Kasten, weil dessen Tasten die der Wiedergabe sein muessen.

**Aufnahmen zu Highscore-Eintraegen bleiben erhalten** (Nutzerwunsch,
seit 0.46.0). Jede beendete Runde bekommt einen kurzen Hash aus ihren
eigenen Ergebnissen (`round_hash` in `rowhammer.sh`); er steht als
letztes Feld im Highscore-Eintrag (siehe 4.5) und im **Dateinamen** der
Aufnahme (siehe 4.10). Damit weiss das Aufraeumen, welche Aufnahme zu
einem noch gueltigen Highscore gehoert, und laesst sie stehen. Die
Entscheidungen dahinter:

- **Der Hash steht im Dateinamen, nicht in der Datei.** Liste und
  Pruning kommen so ohne einen einzigen Dateizugriff aus - bei bis zu
  fuenfzig Aufnahmen ist das der Unterschied zwischen einem Glob und
  fuenfzig geoeffneten Dateien je Menue-Aufruf.
- **Die Grenze `DEMO_MAX` zaehlt nur die ungeschuetzten Aufnahmen.**
  Zusammenzuzaehlen sieht ordentlicher aus, versagt aber genau dort, wo
  die Funktion gebraucht wird: liegen `DEMO_MAX` Aufnahmen zu
  Highscore-Eintraegen auf der Platte, waere das Budget schon von ihnen
  aufgebraucht, und jede frisch gespielte Runde haette ihre Aufnahme
  im selben Moment wieder verloren. Das Verzeichnis darf deshalb ueber
  die Grenze hinauswachsen - schlimmstenfalls auf die 4 x 10 Eintraege
  der Bestenlisten plus `DEMO_MAX`, also rund fuenfzig Aufnahmen oder
  wenige Megabyte.
- **Der Schutz endet von selbst.** Verdraengt eine bessere Runde den
  Eintrag aus der Liste, ist auch sein Hash weg und die Aufnahme beim
  naechsten Aufraeumen wieder normal dran. Es gibt keinen Zustand, den
  jemand pflegen muesste.
- **Die gerade geschriebene Aufnahme wird nie weggeraeumt.** Sie zaehlt
  gegen `DEMO_MAX` wie jede andere, wird beim Aufraeumen aber ans Ende
  der Reihenfolge gestellt, statt dort zu bleiben, wo ihr Name sie
  einsortiert: sie *ist* per Definition die neueste, waehrend "neueste"
  sonst am Dateinamen und damit an der Uhr haengt. Ohne das wuerde eine
  rueckwaerts gesprungene Uhr die eben beendete Runde im selben
  Atemzug um ihre Aufnahme bringen.
- **Von Hand loeschen darf man sie trotzdem** - der Menuepunkt sagt
  vorher, dass sie einen Highscore haelt. Ein einzelner, bewusster
  Loeschbefehl ist etwas anderes als das automatische Aufraeumen.
- **Markiert sind sie mit einem `*`** in der Demo-Liste, samt Legende
  im Titel. Weil die Liste damit laenger als der Bildschirm werden kann,
  blaettert `menu_run` seit 0.46.0 mit der Auswahl durch lange Listen
  (`MENU_LIST_MAX`, siehe `lib/menu.sh`) - die Demo-Liste ist das erste
  Menue, dessen Laenge nicht von einer Konstanten begrenzt ist.
- **Der Hash ist FNV-1a (32 Bit) in reinem Bash**, kein Aufruf von
  `cksum` oder `sha256sum`: kein Fork, kein Unterschied zwischen
  Systemen, und acht Hex-Ziffern sind kurz genug fuer einen Dateinamen.
  Angriffssicherheit ist kein Ziel; in die Berechnung geht die Spielzeit
  in Millisekunden ein, sodass zwei verschiedene Runden praktisch nicht
  kollidieren koennen - und eine Kollision wuerde hoechstens eine
  Aufnahme laenger als noetig aufheben.

**Weitere Entscheidungen:**

- **Eine Wiedergabe wird nie gewertet.** `record_round` (`rowhammer.sh`)
  bricht bei laufender Wiedergabe sofort ab: kein Highscore-Eintrag,
  kein Weltwunder-Fortschritt, keine Statistik und keine neue
  Aufzeichnung. Der Guard sitzt in `record_round` selbst und nicht an
  den Aufrufstellen, weil eine Wiedergabe diese Funktion durch genau die
  Spielfunktionen erreicht, die sie nachspielt (`lock_and_next` beim
  Ultra-Ziel, `spawn_piece` bei blockiertem Spawn).
- **Eine Wiedergabe ist waehrend einer pausierten Runde gesperrt.** Sie
  laeuft durch denselben Rundenzustand (Brett, Zaehler, Queue), in dem
  eine ueber das Pausenmenue ins Hauptmenue gelegte Runde parkt; ein
  Abspielen wuerde sie stillschweigend verwerfen. `menu_demos` weist
  deshalb mit einer Meldung darauf hin, statt den Zustand zu sichern und
  wiederherzustellen - das waere ein Dutzend Variablen und Arrays, die
  bei jeder kuenftigen Zustandserweiterung mitgepflegt werden muessten.
- **Aufgezeichnet wird auch eine abgebrochene Runde** (wie sie auch fuer
  Weltwunder und Statistik zaehlt, siehe 3.3); die Art des Endes steht
  im Kopf der Datei (`end=over|goal|quit`). Nur eine Runde ganz ohne
  Ereignis wird verworfen - sie waere nur Rauschen in der Liste. Das
  gilt auch fuer "Neustarten" im Pausenmenue (0.43.0, siehe 3.1): weil
  der Neustart die aufgegebene Runde ueber `record_round` verbucht,
  bevor `game_reset` die neue beginnt, liegt sie danach als fertige
  Aufnahme vor und die neue Runde zeichnet von vorn auf - ohne dass die
  Demo-Schicht diesen Weg kennen muesste.
- **Die Blink-Animation skaliert mit** (`flash_rows`): sie laeuft auf
  echter Zeit, waehrend die Wiedergabe auf der Demo-Uhr laeuft. Bliebe
  sie ungeskaliert, wuerde bei 4x nach jedem Reihenabbau ein Stueck
  Demo-Zeit verschluckt und die naechsten Ereignisse kaemen im Schwall.
- **Die Aufzeichnung aendert das Spiel nicht.** `demo_record_event`
  rechnet den Zeitstempel so aus, wie `play_clock_tick` es taete,
  schreibt ihn aber nicht in die Spieluhr zurueck - `PLAY_MS` treibt die
  Zeitmodi und das HUD, und eine laufende Aufnahme darf daran nichts
  aendern.


### 4.10 Demo-Format und Ablage (seit 0.46.0)

Das Konzept und die Entscheidungen dahinter stehen in 3.8; hier das
Dateiformat und der Weg einer Aufnahme.

**Dateiformat** (`lib/demo.sh`). Eine Aufnahme ist eine Textdatei aus
`key=value`-Zeilen, die - wie Savegame und Statistik (4.5) - **geparst
und validiert, nie gesourct** wird; jedes Feld hat sein eigenes Muster
(`DEMO_*_RE`). Erst der Kopf, dann die Steinfolge, dann die Ereignisse:

```
version=3            Formatversion (2 und 3 werden gelesen, 3 wird
                     geschrieben - siehe unten)
game=0.52.0          Spielversion, die aufgenommen hat (nur Info)
mode=marathon        marathon|ultra|sprint|timeattack|flood|versus
name=Player          Spielername
date=2026-08-03 21:40
time=123456          Spielzeit der Runde in Millisekunden
lines=42 rows=98 level=4 gold=1 silver=2 rowhammers=1 pieces=57
goal=0               ob das Modus-Ziel erreicht wurde
end=over             over|goal|quit|lost - wie die Runde endete
pcs=IOTSZJLIOT...    die Steinfolge (Zeilen zu hoechstens 80 Buchstaben)
e=120l               ein Ereignis: Zeitdelta in ms + Aktionsbuchstabe
```

Eine **Mehrspieler-Aufnahme** traegt darueber hinaus
einen Sitzungsblock und einen Ereignisstrom je Teilnehmer; beides steht
mit seinen Entscheidungen in 5.20. Der Rest dieses Abschnitts gilt fuer
beide Sorten.

Das Ereignis-Alphabet ist bewusst ein Buchstabe je Sache, die einer
Runde zustossen kann: `l`/`r` links/rechts, `c`/`a` Drehen im/gegen den
Uhrzeigersinn, `s` Soft-Drop, `h` Hard-Drop (setzt selbst fest), `o`
Hold, `g` ein Gravitationsschritt, `k` das Ablaufen des Lock Delays und
- seit 0.49.0 - `w<spalte>` eine Flutreihe des Hochwasser-Modus (siehe
3.6).
Soft-Drop und Gravitation tun dasselbe und bleiben trotzdem zwei
Buchstaben, damit die Aufnahme noch sagt, welches von beidem es war. Ein
blockierter Spawn braucht kein Ereignis - die Wiedergabe laeuft von
selbst hinein. Auch **blockierte** Bewegungen werden aufgezeichnet: die
Wiedergabe fuehrt sie gegen dasselbe Brett aus, wo sie ebenso scheitern.

Die Flutreihe ist das **einzige Ereignis mit Nutzlast**, und sie braucht
sie: der Anstieg selbst folgt der Uhr und liesse sich nachrechnen, die
Spalte des Lochs kommt aber aus `RANDOM` - eine Wiedergabe, die sie
raet, spielte eine andere Runde. Mit ihr wanderte die Formatversion von
1 auf 2 (`DEMO_FORMAT_VERSION`): eine aeltere Aufnahme wuerde zwar noch
korrekt ablaufen, aber die Regel "keine Abwaertskompatibilitaet" gilt
auch hier, und genau die Frage, welche alten Versionen nahe genug sind,
soll diese eine Zahl ersparen.

**Version 3** kam mit dem Mehrspieler und ist die eine
Stelle, an der das Format doch kulant ist: gelesen werden **2 und 3**
(`DEMO_FORMAT_MIN_VERSION`), geschrieben wird 3. Das ist die bewusste,
eng begrenzte Ausnahme von der Arbeitsregel (Abschnitt 6,
Nutzerentscheidung, so schon in 5.20 vorgesehen), und sie kostet nichts:
eine **Einzelspieler-Aufnahme der Version 3 ist byteweise die der
Version 2** - der ganze Sitzungsblock existiert nur in einer
Versus-Aufnahme -, eine Version-2-Datei ist also eine Version-3-Datei
ohne einen Abschnitt, den sie gar nicht haben konnte. Die Aufnahmen, an
denen Highscore-Eintraege haengen, dafuer wegzuwerfen waere ein Verlust
ohne Gegenwert. Umgekehrt gilt die Strenge weiter: eine hoehere Version
faellt heraus, und eine Datei, die `mode=versus` in einer Version ohne
Sitzungsblock behauptet, ebenfalls - das ist keine kurze Aufnahme,
sondern eine bearbeitete Datei.

**Zeit.** Jedes Ereignis traegt die **Spielzeit** (`PLAY_MS`, Pausen
also ausgenommen) als Delta zum vorherigen - in einer
**Mehrspieler-Aufnahme** stattdessen die **Rundenzeit**, die auch im
Pausenmenue weiterlaeuft, weil sie dort die einzige Uhr ist, die alle
Teilnehmer teilen (Begruendung in 5.20). Beim Laden werden die Deltas
zu absoluten Zeitstempeln aufsummiert (je Strom, siehe 5.20); die
Wiedergabe fuehrt eine eigene Uhr (`DEMO_CLOCK_MS`), die je
Schleifendurchlauf um die vergangene Echtzeit mal Tempofaktor waechst,
und wendet jedes Ereignis an, sobald
sie dessen Stempel passiert hat. Absolut statt "je Ereignis schlafen":
so kann sich ueber eine lange Demo kein Fehler aufsummieren, ein
langsamer Durchlauf holt auf, und ein Tempowechsel wirkt sofort. Nach
dem letzten Ereignis laeuft die Uhr bis zum Ende der Zeitachse weiter
(`DEMO_TIMELINE_MS`: die Spielzeit `time`, in einer
Mehrspieler-Aufnahme die Rundendauer `length`, siehe 5.20) - der
Schwanz nach der letzten Aktion gehoert zur Runde. Das HUD bekommt die
Demo-Uhr als `PLAY_MS`, damit der "Time"-Zaehler (und der
Sprint-Countdown) so laeuft wie in der aufgenommenen Runde.

**Steinfolge.** `queue_fill` (`lib/pieces.sh`) ist die einzige Stelle,
an der Steine in eine Runde kommen, und damit die Stelle, an der die
Demo-Schicht haengt: waehrend einer Aufnahme wird jeder gezogene Stein
notiert, waehrend einer Wiedergabe kommen die Steine aus der Aufnahme
statt aus dem Beutel. Damit stimmen Vorschau und Spawn-Reihenfolge
gleichermassen. Laeuft die Folge einer von Hand bearbeiteten Datei aus,
faellt die Wiedergabe auf den normalen Beutel zurueck (mit Vermerk im
Debug-Log), statt abzubrechen.
In einer **Mehrspieler-Aufnahme** ist die Folge dieselbe fuer alle - der
gemeinsame Seed gibt jedem dieselbe, nur zu anderen Zeitpunkten (5.1) -,
und sie wird beim Schliessen der Aufnahme so weit nachgezogen, wie der
Teilnehmer gekommen ist, der am weitesten kam (`demo_pieces_topup`,
Begruendung in 5.20). Sonst haette die Aufnahme eines frueh
Ausgeschiedenen nur die Steine, die er selbst gezogen hat, und den
uebrigen Brettern gingen sie mitten in der Wiedergabe aus.

**Ablage.** Waehrend der Runde wird ausschliesslich auf eine **RAM-Disk**
geschrieben (`XDG_RUNTIME_DIR`, sonst `/dev/shm`, als letzter Ausweg
`TMPDIR`/`/tmp` mit Vermerk im Debug-Log), und zwar gepuffert: erst je
`DEMO_FLUSH_MAX` (64) Ereignisse - rund alle 15 Sekunden Spielzeit -
haengt ein `printf` sie an die Datei. So kostet eine laufende Runde
weder Frame-Zeit noch Schreibzyklen auf einer SSD, und ein abgestuerzter
Prozess verliert hoechstens diese Sekunden. Erst beim echten Rundenende
(`record_round`, siehe 3.3) baut `demo_record_finish` Kopf, Steinfolge
und Ereignisse zusammen und legt die fertige Datei **atomar**
(Tempdatei + `mv`) unter
`${DATA_DIR}/demos/<YYYYMMDD-HHMMSS>-<modus>-<hash>.demo` ab; danach
werden die aeltesten Aufnahmen ueber `DEMO_MAX` hinaus geloescht. Der
Dateiname beginnt mit dem Datum, sodass das Glob chronologisch sortiert
ist und weder Liste noch Pruning `stat` braucht, und endet mit dem
Runden-Hash (siehe 3.8), sodass `demo_file_hash` ihn mit einer einzigen
Expansion wieder abliest.
Die RAM-Disk-Datei einer nie beendeten Runde raeumt der EXIT-`trap` weg.

**Voller Datentraeger (seit 0.48.1).** Der freie Platz wird **bewusst
nicht vorab gemessen** (kein `df`, kein `stat -f`): eine solche Pruefung
waere nur eine Momentaufnahme eines Verzeichnisses, das sich die Aufnahme
mit jedem anderen Programm der Maschine teilt, waehrend der Schreibvorgang
selbst die verbindliche Antwort gibt - und mit rund 2 kB je Spielminute
ist die Aufnahme ohnehin nie die Ursache eines vollen `/dev/shm`, sondern
nur ihr Opfer. Stattdessen wird **jeder** Schreibvorgang des Moduls
geprueft; scheitert einer, wird die Aufnahme verworfen (Vermerk im
Debug-Log) und die **Runde laeuft unveraendert weiter** - eine misslungene
Aufzeichnung ist nie ein Grund, jemandem das Spiel zu verderben. Drei
Stellen daraus sind nicht offensichtlich:

- **`demo_flush`** ist die Stelle, an der eine mitten in der Runde voll
  laufende RAM-Disk auffaellt: Bashs `printf` meldet bei `ENOSPC` einen
  Schreibfehler und liefert ungleich 0.
- **`demo_record_finish` prueft beide Schreibvorgaenge** (Kopf samt
  Steinfolge, dann die Ereignisdatei) ueber ein Flag statt ueber den
  Exit-Status der Gruppe - der waere allein der des letzten Befehls.
  Sonst legt ein Datenverzeichnis, das mitten im Kopf voll laeuft, eine
  **abgeschnittene** Datei ab: `demo_load` weist sie zwar zurueck, aber
  erst beim Ansehen, und bis dahin belegt sie einen der `DEMO_MAX`
  Plaetze und verdraengt eine intakte Aufnahme. `set -e` hilft hier
  nicht - Bash setzt es innerhalb einer `if`-Bedingung aus, und ein
  `set -e` in einer dortigen Subshell stellt es nicht wieder scharf.
- **STDERR geht ueberall nach `/dev/null`.** Das Spiel besitzt das
  Terminal (Alternate-Screen, eigene Cursor-Positionierung); eine
  Meldung von `printf`, `mktemp` oder `rm` wuerde mitten ins Spielfeld
  geschrieben und im Standard-Render-Modus dort **stehen bleiben**, weil
  unveraenderte Zeilen nicht neu geschrieben werden (siehe 4.3).
  Diagnostiziert wird im Debug-Log, wo es in einem
  Vollbild-Programm hingehoert. Aus demselben Grund sind auch die
  Aufraeum-Pfade (`demo_record_discard`, `demo_prune`, `demo_delete`)
  geprueft statt ungeprueft: das Spiel laeuft unter `set -e`, ein
  fehlschlagendes `rm` haette die Runde beendet.

**Einstellung.** `DEMO_RECORD` (`on`/`off`) ist - anders als der
Render- und der Farbmodus - ein **Config-Wert** (Praezedenz Standard <
Config < Env < CLI): ob mitgeschnitten wird, ist Geschmack und keine
Eigenschaft des Terminals. Setzbar per `--demo-record on|off`,
`ROWHAMMER_DEMO_RECORD` und im Einstellungsmenue, das den Wert sofort
speichert. Ein Umschalten wirkt ab der naechsten Runde; eine bereits
laufende Aufnahme wird noch zu Ende gefuehrt.

