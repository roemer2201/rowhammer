# rowhammer - Konzept: Spielkonzept (2, 3.1 bis 3.7)

Teil des technischen Konzepts von rowhammer. Die Abschnittsnummern sind
die aus [CLAUDE.md](../../CLAUDE.md) und bleiben stabil
(Arbeitsregel 6.1): ein Verweis der Form `CLAUDE.md 3.6` im Code meint
den gleichnamigen Abschnitt hier. Die Datei fuehrt den **aktuellen**
Stand samt seiner Begruendung; was abgeloest wurde, steht in
[HISTORY.md](../../HISTORY.md), was noch fehlt, in
[TODO.md](../../TODO.md).

## 2. Vorbild: The New Tetris (N64)

Die fuer uns relevanten Merkmale des Originals:

- **Wonders-Modus:** Jede abgebaute Reihe zahlt auf einen persistenten
  Gesamtzaehler ein. Mit steigendem Zaehler werden nacheinander Weltwunder
  Stueck fuer Stueck aufgebaut und schliesslich freigeschaltet.
- **Quadrate (Squares):** Wer aus **genau vier vollstaendigen Bausteinen** ein
  4x4-Quadrat legt, erhaelt einen Bonusblock:
  - **Gold-Quadrat (Mono-Square):** vier Teile der **gleichen** Sorte.
  - **Silber-Quadrat (Multi-Square):** vier Teile **gemischter** Sorten.
  - Teile, die bereits durch einen Reihenabbau zerschnitten wurden, zaehlen
    nicht mehr fuer ein Quadrat.
- **Bonus-Reihen:** Wird eine Reihe abgebaut, die durch ein Quadrat verlaeuft,
  zaehlt sie mehrfach fuer den Reihenzaehler (Silber deutlich mehr als eine
  normale Reihe, Gold noch einmal doppelt so viel wie Silber).
- Komfortfunktionen: Vorschau auf kommende Teile, Hold-Funktion, Soft-/Hard-Drop.

## 3. Spielkonzept

### 3.1 Kernregeln

- Spielfeld: **10 Spalten x 20 Zeilen** (klassisch), plus unsichtbare
  Spawn-Zeilen oberhalb.
- Die 7 Standard-Bausteine (I, O, T, S, Z, J, L) mit **Bag-Randomizer**:
  ein Beutel fasst **63 Steine** - neun vollstaendige Saetze der sieben
  Sorten, als Ganzes gemischt (`BAG_SETS` in `lib/pieces.sh`, seit
  1.0.4). Der lange Beutel gibt der Bildung der Spezialbloecke
  (Gold-/Silber-Quadrate, siehe 3.2) ihre Dynamik: die Garantie bleibt
  dieselbe - ueber einen vollen Beutel kommt jede Sorte gleich oft -,
  aber innerhalb des Beutels ist die Reihenfolge frei genug fuer beides,
  die Haeufung gleicher Sorten, aus der ein Gold-Quadrat ueberhaupt erst
  wird, und die Duerre, die es zu einer Entscheidung macht. Zwei
  Festlegungen dazu:
  - **Gemischt wird ueber den ganzen Beutel**, nicht Satz fuer Satz. Ein
    Mischen je Siebenersatz wuerde nur siebenmal je sieben Steine
    umsortieren und damit genau die gleichmaessige Verteilung erhalten,
    die hier geloest werden soll.
  - **Die Satzzahl ist eine justierbare Konstante** (`BAG_SETS`), wie
    `ULTRA_TARGET_ROWS` oder `FLOOD_INTERVAL_MS`: sie gehoert zum
    Spielgefuehl und wird nach Playtesting nachgezogen, nicht je Runde
    gewaehlt. `BAG_SETS=1` ist wieder der klassische 7er-Beutel.
  Demos und der Mehrspieler bleiben davon unberuehrt: eine Aufnahme
  speichert die Steinfolge selbst und keinen Beutel (siehe 4.10), und
  die Mehrspieler-Fairness haengt am gemeinsamen Seed (siehe 5.1), nicht
  an der Beutelgroesse.
- Steuerung (Standardbelegung; ueber das Einstellungsmenue aenderbar und
  in der Nutzer-Konfigurationsdatei gespeichert, siehe 4.5):
  - Links/Rechts: Pfeiltasten (seit 0.31.0 ohne Buchstabentaste)
  - Rotation: `d` (im Uhrzeigersinn), `a` (gegen Uhrzeigersinn)
  - Soft-Drop: `s` bzw. Pfeil runter
  - Hard-Drop: Leertaste und Pfeil hoch (seit 0.31.0 ohne
    Buchstabentaste)
  - Hold: `c` bzw. `w`
  - Pause: `p`; `Esc`/`x` oeffnet das Pausenmenue (seit 0.12.0, Issue
    #12): Fortsetzen, Neustarten (seit 0.43.0, Nutzerwunsch), Ins
    Hauptmenue (Runde pausiert, wieder aufnehmbar
    ueber den Eintrag "Fortsetzen", der dann im Hauptmenue und im
    Einzelspieler-Menue an erster Stelle steht) oder Runde beenden.
    **"Neustarten"** gibt die laufende Runde auf und startet eine
    frische im selben Modus (`GAME_RESTART` in `rowhammer.sh`,
    gesetzt von `menu_pause`, ausgefuehrt in `handle_key`): erst
    `record_round`, dann `game_reset` ohne Argument. Die Reihenfolge
    ist zwingend - eine aufgegebene Runde zaehlt wie jede abgebrochene
    (siehe 3.3), und `game_reset` loescht genau die Zaehler, die
    `record_round` liest. Es ist dieselbe Reihenfolge, mit der
    `game_run` eine noch pausierte Runde verbucht, bevor eine neue
    startet. Der Eintrag steht direkt unter "Fortsetzen", weil er der
    andere Weg ist weiterzuspielen; die beiden Eintraege, die die Runde
    verlassen, bleiben unten, wo sie im bisherigen Dreier-Menue standen.
    Der Wunder-Bildschirm erscheint dabei nicht (er gehoert ans Ende
    der Spielsitzung, nicht zwischen zwei Runden); verbucht ist der
    Fortschritt trotzdem. Die Taste `r` im Game-Over-Bild macht
    dasselbe ohne `record_round` - dort ist die Runde beim Game Over
    schon verbucht.
    **Sicherheitsabfragen (seit 0.43.0, Nutzerwunsch):** Die beiden
    Eintraege, die die Runde wegwerfen - "Neustarten" und "Runde
    beenden" -, fragen vorher zurueck (`menu_confirm`): "Wirklich neu
    starten?" bzw. "Runde wirklich beenden?", je mit dem Stand der
    Runde (Lines, Rows, Level) und dem Hinweis, dass sie gewertet wird.
    Wie ueberall ist "Nein" vorausgewaehlt, und `ESC` lehnt ebenfalls
    ab. Die beiden anderen Eintraege fragen nicht: "Fortsetzen"
    aendert nichts, und eine ins Hauptmenue gelegte Runde geht nicht
    verloren, sondern wartet dort. Abgelehnt fuehrt die Abfrage
    **zurueck ins Pausenmenue**, nicht in die Runde - wer den Eintrag
    nicht wollte, wollte meist trotzdem etwas aus diesem Menue;
    `menu_pause` ist dafuer eine Schleife um `menu_run`
- **Belegungswechsel 0.31.0 (Nutzerentscheidung):** `q`/`e` (Rotation)
  wurden zu `a`/`d`, die feste Hold-Sekundaertaste `2` zu `w`. Die drei
  Buchstaben waren zuvor mit Links, Rechts und Hard-Drop belegt; diese
  Aktionen behalten deshalb nur ihre festen Sekundaertasten
  (Pfeiltasten bzw. Leertaste/Pfeil hoch) und haben in der
  Standardbelegung keine Buchstabentaste mehr. Dafuer kennen die
  Bindungen den Wert `NONE` ("keine Buchstabentaste"): `KEY_LEFT` und
  `KEY_RIGHT` stehen darauf, `KEY_HARD` auf `SPACE`. `NONE` ist als
  einziger Wert von der Dubletten-Pruefung ausgenommen (mehrere Aktionen
  duerfen ungebunden sein) und kann nie mit einem echten Tastendruck
  kollidieren, weil `read_key` nur Einzelzeichen oder die Namen
  `LEFT`/`RIGHT`/`UP`/`DOWN`/`SPACE`/`ENTER`/`ESC` meldet. Ueber das
  Einstellungsmenue laesst sich jeder Aktion wieder eine Buchstabentaste
  geben; `NONE` selbst ist nur ueber Config-Datei bzw.
  `ROWHAMMER_KEY_*` setzbar (der Rebind-Dialog nimmt nur echte Tasten
  entgegen).
- **Rundenende am oberen Feldrand (seit 1.0.2, Nutzerreport):** Die
  Runde endet, sobald etwas **oberhalb des sichtbaren Feldes** liegen
  bleibt - also in den beiden verdeckten Spawn-Zeilen. Das Feld ist 20
  Reihen hoch, und was darueber stehen bleibt, gehoert nicht mehr dazu;
  neben dem blockierten Spawn ist das der zweite Weg ins Game Over.
  Umsetzung: `board_top_out` (`lib/board.sh`) meldet, ob eine Zelle in
  den verdeckten Zeilen liegt; gefragt wird sie an den zwei Stellen, an
  denen dort etwas hinkommen kann - `lock_and_next` nach dem Festsetzen
  eines Steins und `flood_raise` nach einem Anstieg im Hochwasser-Modus
  (beide in `rowhammer.sh`). Die Entscheidungen dazu:
  - **Gefragt wird das Brett, nicht der Stein.** Eine Pruefung der
    gerade festgesetzten Zellen muesste den Reihenabbau nachrechnen, der
    sie verschiebt - und sie liesse die zweite Stelle (das steigende
    Wasser) mit einer eigenen Regel zurueck. So gilt fuer beide
    dieselbe.
  - **Geprueft wird nach dem Reihenabbau.** Ein Stein, der oben
    heraussteht, aber Reihen mitnimmt, zieht den Stapel wieder ins Feld
    zurueck; dieser Rettungszug soll belohnt und nicht bestraft werden.
  - **Das Ultra-Ziel gewinnt.** Die Zielpruefung in `lock_and_next`
    steht vor dieser hier: ein Lauf, der mit genau diesem Stein sein
    Ziel erreicht, hat gewonnen, wie hoch der Stein auch sass.
  - **Im Hochwasser-Modus endet die Runde am Anstieg selbst**, nicht
    erst beim naechsten Lock - sonst waeren die beiden Wege ueber die
    Feldkante verschieden streng. Die Pruefung in `board_flood_row`
    (die eine Zelle erst dann nicht mehr schieben will, wenn sie vom
    Brett gefallen waere) bleibt daneben als Eigensicherung der Funktion
    stehen: sie ist das Einzige, was ueberhaupt verhindert, dass eine
    Zelle aus dem Brett geschoben wird, und die Mehrspieler-Garbage
    (5.7) schiebt dort mehrere Reihen auf einmal durch.
- Vorschau: die naechsten 3 Teile. Hold: genau ein Teil, einmal pro Zug tauschbar.
- Level/Geschwindigkeit: Fallgeschwindigkeit steigt mit der Zahl abgebauter
  Reihen der laufenden Runde.
- **Lock Delay (seit 0.18.0):** Ein Stein, der nicht mehr fallen kann,
  wird nicht sofort festgesetzt, sondern ruht ein kurzes Gnadenfenster
  (`LOCK_DELAY_MS`, 250 ms), in dem er weiter nach links/rechts
  verschoben und gedreht werden kann. Der Touchdown-Timer wird **nur**
  zurueckgesetzt, wenn eine Verschiebung/Drehung den Stein wieder ins
  Fallen bringt (dann faellt er normal weiter); eine Bewegung, die ihn
  weiter aufliegen laesst, behaelt die urspruengliche Frist, sodass ein
  Stein nicht endlos am Boden gehalten werden kann. Nur der
  Transitions-Moment ins Aufliegen setzt die Frist; wiederholte
  Gravitations-Ticks oder ein Soft-Drop auf einen bereits ruhenden Stein
  verschieben sie nicht. Der Hard-Drop setzt weiterhin sofort fest, und
  das Fenster laeuft weder in der Pause noch im Pausenmenue
  (Umsetzung: `lock_touchdown`, `lock_delay_recheck`, `step_down` und der
  Game-Loop in `rowhammer.sh`; Wert justierbar in `LOCK_DELAY_MS`).
- **Blink-Effekt beim Reihenabbau (seit 0.20.0):** Vervollstaendigt ein
  Lock eine oder mehrere Reihen, blinken diese Reihen erst kurz auf und
  werden dann entfernt. Die Reihen werden vor dem Abbau ermittelt
  (`board_full_rows` in `lib/board.sh`), die Animation wechselt
  `FLASH_CYCLES`-mal zwischen hell hervorgehobener und normaler
  Darstellung (`FLASH_ROWS`/`FLASH_STATE` in `lib/render.sh`, gesteuert
  von `flash_rows` in `rowhammer.sh`; Standard 2 Zyklen a 2x70 ms =
  rund 280 ms, justierbar in `FLASH_MS`/`FLASH_CYCLES`,
  `FLASH_CYCLES=0` schaltet die Animation ab). Die Quadrat-Erkennung
  laeuft vorher, sodass eine Reihe durch ein frisch gebildetes Quadrat
  bereits in ihrer Gold-/Silber-Wertigkeit blinkt. Die Animation haelt
  den Game-Loop fuer ihre Dauer an (das naechste Teil erscheint erst
  danach); Tastendruecke waehrend des Blinkens werden bewusst verworfen,
  damit sie nicht gesammelt auf dem neuen Stein losgehen. Das Warten
  nutzt wie der uebrige Loop ein `read` mit Timeout (kein `sleep`-Fork),
  und zwar ueber `key_drain` (`lib/input.sh`, seit 0.23.0) statt eines
  rohen `read`: `key_drain` schickt die Bytes durch denselben
  Zustandsautomaten wie das Spiel (siehe 4.3) und verwirft nur die
  fertig erkannten Tasten, sodass eine Escape-Sequenz entweder ganz oder
  gar nicht geschluckt wird - ein Roh-Read koennte ihre Haelfte
  schlucken und den Rest als eigene Taste durchreichen. Dieselbe
  Funktion nutzt die "resize me"-Overlay.

### 3.2 Quadrat-System (Gold/Silber)

- Jeder gelegte Stein behaelt eine **Identitaet** (welcher Baustein, welche
  Instanz), solange er unversehrt ist.
- Nach jedem Lock pruefen: Existiert ein 4x4-Bereich, der aus **genau vier
  vollstaendigen, unversehrten** Bausteinen besteht und exakt gefuellt ist?
  - Ja, alle vier gleiche Sorte -> Zellen werden zum **Gold-Quadrat**.
  - Ja, gemischte Sorten -> **Silber-Quadrat**.
- Quadrate werden farblich hervorgehoben (Gold/Gelb bzw. Silber/Weiss) und
  verhalten sich physikalisch wie normale Bloecke.
- **Reihenwertung beim Abbau** (per Recherche gegen das Original
  verifiziert): keine Multiplikation, sondern feste Bonuszeilen pro
  Quadrat in der geraeumten Reihe:
  - Basis: jede abgebaute Reihe zaehlt **1** Reihe Baufortschritt
  - je **Silber-Quadrat** in der Reihe: **+5** Bonuszeilen
  - je **Gold-Quadrat** in der Reihe: **+10** Bonuszeilen
  - Boni sind **additiv** bei mehreren Quadraten in einer Reihe
  - **Tetris** (4 Reihen auf einmal): **+1** Bonuszeile zusaetzlich
  - Beispiele: Tetris durch ein komplettes Gold-Quadrat = 4 + 1 + 4x10 =
    **45**; durch ein Silber-Quadrat = **25**; durch zwei komplette
    Gold-Quadrate = 4 + 1 + 8x10 = die beruehmten **85**.
- Umgesetzt seit 0.4.0 (`lib/squares.sh`, `lib/board.sh`): Werte
  justierbar in `ROWS_NORMAL`/`ROWS_SILVER`/`ROWS_GOLD`/`ROWS_TETRIS`.
  Die Quadrat-Anzahl je Reihe ergibt sich aus Gold-/Silber-Zellen / 4
  (Reihenabbau entfernt nur ganze Zeilen, Quadrate bleiben horizontal
  immer 4 Zellen breit). Ein angeschnittenes Quadrat behaelt seine
  Gold-/Silber-Zellen und liefert weiter Bonus.
- **Die Reihenwertung ist zugleich das Punktesystem** (seit 0.16.0,
  Nutzerentscheidung): abgebaute Reihen sind die einzige Punktquelle,
  der "Rows"-Zaehler ist der Score der Runde. Es gibt keine separaten
  Punkte mehr fuer Soft-/Hard-Drop, fuer die Quadrat-Bildung (der Bonus
  faellt erst beim Abbau der Reihen an) oder fuer Spins, und keine
  Level-Skalierung. Beispiele fuer eine einzelne Reihe: 2x Silber =
  1 + 2x5 = 11, 1x Silber + 1x Gold = 1 + 5 + 10 = 16, 2x Gold =
  1 + 2x10 = 21; Maximum pro Zug bleibt der Tetris durch zwei komplette
  Gold-Quadrate mit 85.
- Original-Regel bewusst nicht umgesetzt: Ein "Spin Move" beim Abraeumen
  laesst Gold-/Silber-Bloecke vorher in normale Einzelbloecke zerfallen
  (Nutzerentscheidung: soll nicht zur Anwendung kommen).

### 3.3 Weltwunder-Aufbau (seit 0.8.0)

- Feste Abfolge von sieben Weltwundern (`lib/wonders.sh`). Der Abgleich
  mit dem Original ergab (Recherche, Quellen nur teilweise erreichbar):
  Die Wunder des Originals sind reale Bauwerke, belegt sind u. a.
  Maya-Tempel, Stonehenge, Sphinx, Pantheon und Basilius-Kathedrale;
  das erste Wunder (Maya) ist dort bei 2.500 Zeilen fertig, das letzte
  bei 500.000. Finale Liste (Reihen-Kosten je Wunder in Klammern,
  justierbar in `WONDER_COSTS`):
  1. Maya-Tempel / Chichen Itza (10.000)
  2. Stonehenge (20.000)
  3. Sphinx von Gizeh (40.000)
  4. Pantheon, Rom (80.000)
  5. Chinesische Mauer (160.000)
  6. Taj Mahal (320.000)
  7. Basilius-Kathedrale, Moskau (640.000)
  Chinesische Mauer und Taj Mahal fuellen die zwei nicht verifizierbaren
  Plaetze. Die Kosten verdoppeln sich je Wunder (grob geometrisch wie im
  Original) und liegen seit 0.44.0 auch in dessen Groessenordnung
  (1.270.000 gewichtete Reihen insgesamt, im Original 2.500 bis 500.000
  Zeilen je Wunder), sodass ein Wunder ein Langfrist-Ziel ist.
- Jedes Wunder ist **eine** ASCII-Art-Datei (`assets/wonders/`, 12
  Zeilen, max. 44 Spalten, reines ASCII). Die Baustufen werden nicht als
  separate Dateien gepflegt, sondern durch **zeilenweises Aufdecken von
  unten** proportional zum Baufortschritt abgeleitet (12 Zeilen = 12
  Baustufen); die oberste Zeile erscheint erst bei 100 %. Der
  persistente Gesamt-Reihenzaehler bestimmt Wunder und Baustufe; nach
  Fertigstellung folgt das naechste Wunder, nach dem letzten zaehlt der
  Zaehler weiter und der Bildschirm meldet "Alle Weltwunder errichtet".
- Der Baufortschritt wird **ueber Sitzungen hinweg gespeichert**
  (Savegame `${DATA_DIR}/save`, siehe 4.5). Der Rundenkredit ("Rows")
  wird genau einmal je Runde verbucht, und zwar beim echten Rundenende:
  Game Over, "Runde beenden" oder "Neustarten" im Pausenmenue (seit
  0.43.0; die aufgegebene Runde wird verbucht, bevor die neue ihre
  Zaehler ueberschreibt, siehe 3.1) oder - falls noch eine
  pausierte Runde wartet - beim Start einer neuen Runde bzw. beim
  Beenden des Programms (auch abgebrochene Runden zaehlen, wie im
  Original). Eine ueber das Pausenmenue ins Hauptmenue gelegte Runde
  ist noch nicht beendet und wird nicht verbucht (seit 0.12.0, Issue
  #12). Anzeige:
  als Baustellen-Bildschirm nach jedem Spiel beim Verlassen ins
  Menue sowie jederzeit ueber den Hauptmenuepunkt "Weltwunder". Im HUD
  stand der Baufortschritt bis 0.24.0 laufend mit; seit 0.25.0 gehoert
  dieser Platz dem Rowhammer-Zaehler (Nutzerentscheidung, siehe 3.4).
  Der Wunder-Zustand wird deshalb nicht mehr je Reihenabbau
  nachgerechnet, sondern nur noch beim Rundenende (`record_round`) und
  beim Anzeigen des Wunder-Bildschirms (`wonder_screen` rechnet selbst).
- **Blaettern zu den fertigen Wundern (seit 0.54.0, Nutzerwunsch):**
  Pfeil links/rechts schaltet auf dem Wunder-Bildschirm zwischen den
  bereits **fertiggestellten** Wundern und der aktuellen Baustelle um
  (`wonder_screen` in `lib/wonders.sh`, ein Bildschirm je Wunder gebaut
  von `wonder_screen_lines`). Entscheidungen dazu:
  - **Der Bereich ist 0..`WONDER_INDEX`**, also die fertigen Wunder
    plus die laufende Baustelle. Ein noch nicht begonnenes Wunder wird
    nicht gezeigt - es waere nur ein leerer Rahmen und naehme dem
    Weiterbauen die Ueberraschung. Geblaettert wird umlaufend wie in
    jeder anderen Liste des Spiels (Anleitung, Bestenlisten).
  - **Ein fertiges Wunder zeigt seine Art vollstaendig** und in der
    Zahlenzeile seine Kosten als erreichten Stand ("Baustufe 12/12 -
    20000/20000 Reihen (100%)"). Die Zahlen kommen aus `WONDER_COSTS`
    und nicht aus einem gespeicherten Stand: gespeichert ist allein der
    Gesamtzaehler (siehe 4.5), und die Reihen, die dieses Wunder gebaut
    haben, stecken laengst in den Wundern danach.
  - **Solange nichts fertig ist, bleibt der Bildschirm, was er war:**
    ein Bild, das jede Taste schliesst ("Beliebige Taste druecken").
    Es gibt dann nichts zu blaettern, und genau so erwartet es der
    Ablauf nach einer Runde. Erst als Blaetterer nennt die Fusszeile
    die Tasten und schliesst nur noch auf `Enter`, Leertaste, `x` oder
    `ESC` - die Pfeile bedeuten jetzt etwas anderes. Das ist dieselbe
    Aufteilung, die die Anleitung seit 0.33.0 hat.
  - **Der Bildschirm nach einer Runde ist derselbe** und kann deshalb
    ebenfalls blaettern; ein zweiter Bildschirm nur fuers Zurueckschauen
    waere dieselbe Anzeige ein zweites Mal.

### 3.4 Anzeige / HUD

- **Layout (seit 0.22.0, umgestellt in 0.26.0):** Der Spielbildschirm
  ist ein fester Block
  von 48x22 Zeichen, der **mittig im Terminal** ausgerichtet wird
  (`layout_update` in `lib/render.sh` berechnet aus `TERM_ROWS`/
  `TERM_COLS` die linke obere Ecke; ein Resize richtet ihn neu aus).
  Der Block ist in Spalten gegliedert: linke Spalte 12 Zeichen, Luecke
  1, Spielfeld 22 (10 Zellen a 2 Zeichen plus Rahmen), Luecke 1, rechte
  Spalte 12. In Zeilen: Zeile 0 obere Feldkante, 1-20 die sichtbaren
  Feldreihen, 21 untere Feldkante - der Block ist damit genau so hoch
  wie das Spielfeld. Seit 0.28.0 sind auch Menues, Info-Bildschirme und
  der Weltwunder-Bildschirm zentriert, buendig zur linken Kante des
  Spielblocks (`render_menu_frame`, siehe 4.3).
  - **Links:** der Hold-Stein (Ueberschrift "Hold") und darunter die
    Rundenzaehler (seit 0.26.0, Nutzerentscheidung): Lines (physische
    Reihen der Runde), Rows (gewertete Reihen = Punkte der Runde, siehe
    3.2), Level, Gold-/Silberzaehler, Rowhammer der Runde (Label
    "Hammer", vier Reihen auf einmal), die Spielzeit (Time, MM:SS;
    seit 0.17.0) und die abgelegten Teile (Pieces, seit 0.27.0 -
    hochgezaehlt in `lock_and_next`, wo ein Stein wirklich festgesetzt
    wird; zusammen mit der Spielzeit ergibt sich daraus die
    PCS/Minute, die Statistik und Highscore ausweisen). Die zwoelf Spalten der Seitenleiste teilen sich je
    Zaehler in 1 Einzug + 6 Label + 5 rechtsbuendiger Wert
    (`pane_stat`); die Zeile wird anschliessend hart auf `PANE_W`
    gekappt, damit ein ungewoehnlich langer Wert die Blockbreite nicht
    sprengt. Die **Tastenlegende** ist dafuer entfallen (samt
    `hud_keys_build`), ebenso der **Spielername** - ein Name darf 16
    Zeichen haben und waere in 12 Spalten nur als Stummel zu sehen; er
    steht weiterhin in der Highscore-Liste.
  - **Mitte:** das Spielfeld mit Rahmen.
  - **Oben rechts:** die naechsten drei Steine (Ueberschrift "Next").
  - **Unten:** nichts mehr. Die beiden Statuszeilen unter dem Feld sind
    mit ihren Zaehlern in die linke Spalte umgezogen (0.26.0,
    Nutzerentscheidung); der Block wurde dadurch zwei Zeilen kuerzer,
    und mit ihm das Terminal-Minimum (`MIN_TERM_ROWS` 24 -> 22). Eine
    separate Score-Zeile gibt es seit 0.16.0 nicht mehr, der
    Weltwunder-Fortschritt hat den HUD in 0.25.0 verlassen und steht
    auf dem Weltwunder-Bildschirm.
  - **Pause und Game Over** erscheinen als Kasten **ueber dem
    Spielfeld** (`render_status_box`), das Game-Over-Bild mit dem
    erreichten Highscore-Rang und den Tasten fuers Neustarten bzw.
    Verlassen - dauerhaften Platz kostet keiner von beiden.
  - Jede Blockzeile wird auf **exakt 48 sichtbare Spalten** gebaut. Das
    ist die Voraussetzung fuer das inkrementelle Rendering (siehe 4.3):
    eine neu geschriebene Zeile ueberdeckt ihre Vorgaengerin immer
    vollstaendig, es braucht keine Loesch-Sequenzen. Ein Spielbildschirm-
    Titel entfaellt dafuer - die 22 Zeilen gehoeren restlos dem Feld.
  - Platzreserve: die linke Spalte hat unter den Zaehlern noch acht
    freie Zeilen (Zeile 14-21; Zeile 13 hat der Pieces-Zaehler aus
    0.27.0 belegt). Ein weiterer Zaehler muss also nichts
    mehr verdraengen, solange sein Label in sechs Zeichen passt.
    Zwei davon (Zeile 15 und 16) nutzt seit 0.34.0 der Ultra-Modus fuer
    "Goal" und "Left"; seit 0.39.0 nutzt der Sprint-Modus dieselben
    beiden Zeilen fuer sein Zeitlimit und die Restzeit, seit 0.42.0 der
    Time-Attack-Modus fuer seine mitwachsende Restzeit und seit 0.49.0
    der Hochwasser-Modus fuer den Flut-Abstand ("Flut") und die Zeit bis
    zur naechsten Flutreihe ("Rest") (die vier Modi
    laufen nie gleichzeitig). Eine weitere (Zeile 18) nutzt seit 0.46.0
    die Demo-Wiedergabe fuer das Abspieltempo (Label "Demo", siehe 3.8);
    sie liegt zwei Zeilen unter den Ziel-Zaehlern, damit eine
    wiedergegebene Runde eines Zeitmodus ihre beiden weiter zeigt.
    Alles nur, solange eine Runde des
    jeweiligen Modus bzw. eine Wiedergabe laeuft; im Marathon bleiben
    alle acht Zeilen frei (siehe 3.6).
- Spielzeit-Counter (seit 0.17.0): Die Anzeige "Time" zaehlt nur die
  aktive Spielzeit der laufenden Runde. Pausen (Taste `p` und das
  Pausenmenue) sowie der Game-Over-Bildschirm zaehlen nicht; die Zeit
  wird im Game-Loop analog zur Fallzeit ueber `${EPOCHREALTIME}`
  (Millisekunden, `now_ms`) akkumuliert und bei jedem Wiederaufnehmen
  neu angesetzt (`play_clock_resume`), sodass Leerlaufphasen nie
  mitzaehlen. Eine ueber das Pausenmenue ins Hauptmenue gelegte Runde
  behaelt ihre bis dahin gezaehlte Zeit und setzt sie beim Fortsetzen
  fort. Beim Rundenende wird die Spielzeit (in ganzen Sekunden) mit dem
  Highscore-Eintrag gespeichert (siehe 4.5).
- Reihenabbau: die betroffenen Reihen blinken kurz auf, bevor sie
  verschwinden (siehe 3.1).
- Nach Rundenende: Bildschirm mit dem aktuellen Wunder in seiner neuen Baustufe.

### 3.5 Anleitung (seit 0.32.0)

Der Hauptmenuepunkt **"Anleitung"** steht zwischen "Einstellungen" und
"Beenden" und erklaert das Spiel auf zehn Info-Bildschirmen
(`menu_help` in `lib/menu.sh`, ueber `render_menu_frame` zentriert wie
der Spielblock). **Seit Version 0.33.0 (Nutzerwunsch)** blaettert man mit
den **Pfeiltasten links/rechts** durch die Seiten (umlaufend: von der
letzten geht es mit Pfeil rechts zurueck zur ersten und umgekehrt);
Enter, Leertaste, `x` und `ESC` schliessen die Anleitung. Damit auch
rueckwaerts auf jede Seite gesprungen werden kann, baut `menu_help_body`
(ein `case`-Switch je Seite, 0-basiert) den Inhalt der angeforderten
Seite bei Bedarf neu, statt ihn in fester Reihenfolge einmal
durchzureichen:

1. Spielprinzip: Bausteine, volle Reihen als "Rows", der 63er-Beutel
   (seit 1.0.4, siehe 3.1),
   Level/Tempo, Rundenende.
2. Steuerung: alle Aktionen mit ihren aktuellen Tasten, dazu die
   Menue-Bedienung und die beiden Wege zum Neustart (`r` im
   Game-Over-Bild, "Neustarten" im Pausenmenue; die Zeile nennt seit
   0.43.0 beide, weil die Seite mit 18 Zeilen genau auf
   `MENU_BODY_MAX` sitzt und keine zusaetzliche vertraegt).
3. Vorschau ("Next") und Hold (ein Tausch je Zug).
4. Gold-/Silber-Quadrate und die Reihenwertung (Werte aus
   `ROWS_NORMAL`/`ROWS_SILVER`/`ROWS_GOLD`/`ROWS_TETRIS`, siehe 3.2).
5. Weltwunderbau mit der Kostentabelle aus `lib/wonders.sh`, dazu seit
   0.54.0 der Hinweis auf das Blaettern zu den fertigen Wundern (siehe
   3.3). Eine Zeile mehr war dafuer nicht zu haben - die Seite sitzt mit
   18 Zeilen auf `MENU_BODY_MAX` -, also ist der Schlussabsatz enger
   formuliert und sagt in denselben vier Zeilen jetzt beides.
6. Spielmodi, Teil 1 (seit 0.39.0): Marathon, Ultra und Sprint mit
   ihrem jeweiligen Ende und Ergebnis.
   Die Seite kam bewusst erst mit dem Sprint-Modus dazu: die
   urspruenglichen fuenf Seiten stammen aus der Zeit, als es nur die
   endlose Runde gab, und mit Sprint liessen sich alle drei Modi in
   einem Zug erklaeren, statt die Seite zweimal umzubauen.
7. Spielmodi, Teil 2 (seit 0.49.0): Time Attack (Seite 6 in 0.42.0)
   und Hochwasser. Der fuenfte Modus sprengte die Modus-Seite, von der
   mit den Bestenlisten schon einmal etwas abgegeben worden war; der
   Schnitt laeuft dort, wo die Modi mit festem Ziel bzw. festem
   Zeitlimit aufhoeren und die beginnen, deren Uhr die Runde selbst
   traegt.
8. Bestenlisten (seit 0.42.0): eine eigene Liste je Modus, welche Zahl
   sie jeweils rangiert, und welche Laeufe ueberhaupt gewertet werden -
   bei Ultra und Sprint nur einer, der sein Ziel bzw. die volle Zeit
   erreicht hat, bei Time Attack und Hochwasser dagegen jeder, samt
   Begruendung (siehe
   3.6). Die Seite ist der abgespaltene Schluss der Modus-Seite: der
   vierte Modus fuellte diese bis auf die letzte ihrer `MENU_BODY_MAX`
   Zeilen, und der Absatz handelt ohnehin von der Wertung statt vom
   Spielablauf.
9. Demos (seit 0.46.0): dass jede Runde mitgeschnitten wird, dass die
   Zuege und nicht der Bildschirm aufgezeichnet werden (und die
   Wiedergabe die Runde deshalb wirklich noch einmal spielt), wie viele
   Aufnahmen aufbewahrt werden, wo sich einzelne loeschen und die
   Aufzeichnung abschalten laesst, dass auch die Bestenliste eine Demo
   startet (seit 0.52.0, siehe 4.5) und die Tasten der Wiedergabe. Die
   Zeile fuer den neuen Weg hat der Einleitungsabsatz bezahlt: die Seite
   sass mit 18 Zeilen schon auf `MENU_BODY_MAX`, und der Absatz sagte in
   fuenf Zeilen, was in vieren steht. Dieselbe Rechnung noch einmal fuer
   die Zeile des Fokuswechsels (1.4.0, siehe 5.20): der Absatz sagt es
   jetzt in drei Zeilen. Die Tastenzeilen selbst sind unveraendert aus
   dem laufenden Zustand gelesen - links/rechts waehlen den Spieler,
   hoch/runter und `+`/`-` das Tempo, in zwei getrennten Zeilen.

10. Mehrspieler (seit 1.1.0): dass jeder sein eigenes Feld mit
   derselben Steinfolge spielt, dass abgebaute Reihen dem Gegner
   Stoerreihen schicken und ein eigener Abbau zuerst die eigene
   Warteschlange raeumt, wie eine Sitzung eroeffnet und gefunden wird
   (Beacon oder eingegebene Adresse), dass der Letzte im Feld gewinnt,
   dass es keine Pause gibt, dass nur die eigene Leistung gewertet wird,
   dass socat gebraucht wird und - seit 1.4.0 - dass die Runde bei
   jedem mitgeschnitten wird und die Wiedergabe jeden Mitspieler zeigt
   (die zwei Zeilen dafuer waren noch frei, die Seite steht mit 18
   Zeilen jetzt auf `MENU_BODY_MAX`). Spielerzahl und Port kommen aus
   `MP_MAX`/`MP_PORT`, damit ein nachjustierter Wert die Seite nicht zur
   Luege macht - dieselbe Regel wie bei den Modus- und Wunder-Seiten.

Fuenf Teile werden bewusst aus dem laufenden Zustand gelesen statt
ausgeschrieben, damit die Anleitung nicht luegen kann: die
Tastenbelegung (`menu_help_keys` setzt die konfigurierbare Taste vor die
fest verdrahteten Sekundaertasten, laesst `NONE` weg und vermeidet
Dubletten wie `KEY_HARD=SPACE` neben der Leertaste), die Wunder-Namen
samt Kosten, die Ziele der drei Zeitmodi (`ULTRA_TARGET_ROWS`,
`SPRINT_TIME_MS`, `TIME_ATTACK_START_MS`/`TIME_ATTACK_ROW_MS`) samt dem
Flut-Abstand des Hochwasser-Modus (`FLOOD_INTERVAL_MS`) und auf
der Demo-Seite die Zahl der aufbewahrten Aufnahmen (`DEMO_MAX`) samt
den Wiedergabetasten. Jeder
Bildschirm bleibt in den 46 Zeichen Breite und
den `MENU_BODY_MAX` Zeilen, die ein 48x22-Terminal laesst - die
Bestenlisten- und die Demo-Seite nutzen sie mit je 18 Zeilen genau aus
(die Demo-Seite seit dem Fokuswechsel in 1.4.0).

### 3.6 Spielmodi (Ultra seit 0.34.0, Sprint seit 0.39.0, Time Attack seit 0.42.0, Hochwasser seit 0.49.0)

Das Einzelspieler-Menue waehlt den Modus der Runde; der gewaehlte Name
geht als Argument an `game_run` und liegt waehrend der Runde in
`GAME_MODE` (Rundenzustand in `rowhammer.sh`, bleibt ueber
Pausieren/Fortsetzen erhalten - eine ins Hauptmenue gelegte Runde kommt
im Modus zurueck, in dem sie gestartet wurde).

**Die Menue-Eintraege der Modi baut `menu_mode_entries`** (`lib/menu.sh`)
fuer alle drei Auswahlen (Einzelspieler, "Highscores", "Statistik")
gemeinsam, damit derselbe Modus ueberall gleich zu lesen ist: erst der
Name, dann in Klammern, wogegen der Modus laeuft - Ziel, Zeitlimit bzw.
Flut-Abstand, aus den laufenden Konstanten gelesen, sodass ein
nachjustierter Wert kein Menue zur Luege machen kann. Zwei Festlegungen
dazu (seit 0.53.0, Nutzerwunsch):

- **Die Klammern sind eine eigene Spalte.** Jeder Name wird auf den
  laengsten aufgefuellt, sodass alle Beschreibungen in derselben Spalte
  beginnen statt hinter Namen von fuenf bis elf Zeichen zu flattern. Die
  Breite wird ueber die Namen **gemessen** statt festgeschrieben: welche
  Laenge sie haben, entscheidet die Sprache (der Hochwasser-Modus allein
  heisst "Hochwasser" oder "Flood", siehe 4.11).
- **Auch Marathon traegt eine Beschreibung** ("endlos, bis Game Over").
  Er war der einzige Eintrag ohne, was sich wie ein fehlender Text las
  statt wie der eine Modus ohne Ziel. Die Texte stehen als
  `entry_*`-Eintraege in der Texttabelle, mit den Klammern, aber ohne
  Namen und ohne Auffuellung - die Ausrichtung gehoert dem Code, die
  Formulierung der Uebersetzung.

- **Marathon** (`marathon`; bis 0.34.1 "Normales Spiel"/`normal` -
  Nutzerentscheidung, an den in anderen Tetris-Spielen ueblichen Namen
  fuer den endlosen Modus angeglichen): die endlose Runde wie bisher,
  Ende durch Game Over.
- **Ultra** (`ultra`, Nutzerwunsch): Wettlauf gegen die Uhr -
  `ULTRA_TARGET_ROWS` (150) **Rows** so schnell wie moeglich abbauen.
  Die Runde endet in dem Moment, in dem die Wertung das Ziel erreicht
  oder ueberschreitet; das Ergebnis ist die Spielzeit.
- **Sprint** (`sprint`, Nutzerwunsch, seit 0.39.0): das Spiegelbild von
  Ultra - in `SPRINT_TIME_MS` (180000 ms = 3 Minuten) Spielzeit
  moeglichst viele **Rows** abbauen. Die Runde endet in dem Moment, in
  dem die Spielzeit das Limit erreicht; das Ergebnis sind die Rows.
  Gemessen wird dieselbe Spielzeit wie im HUD (`PLAY_MS`, siehe 3.4),
  Pausen und Pausenmenue zaehlen also nicht mit, und eine ins
  Hauptmenue gelegte Runde nimmt ihre Restzeit beim Fortsetzen mit.
- **Time Attack** (`timeattack`, Nutzerwunsch, seit 0.42.0): die Uhr als
  Einsatz. Die Runde startet mit `TIME_ATTACK_START_MS` (60000 ms =
  1 Minute) Restzeit, die rueckwaerts laeuft; jede gewertete **Row**
  schreibt `TIME_ATTACK_ROW_MS` (1000 ms = 1 Sekunde) gut. Der Lauf
  dauert damit genau so lange, wie er sich selbst am Leben haelt, und
  endet, wenn die Uhr auf 0 steht - oder vorher durch Game Over. Das
  Ergebnis sind die Rows. Gemessen wird wieder `PLAY_MS` (siehe 3.4),
  also ohne Pausen. Das Zeitguthaben wird **nicht** in einem eigenen
  Zaehler mitgefuehrt, sondern bei Bedarf aus `ROW_CREDIT` abgeleitet
  (`time_attack_budget` in `rowhammer.sh` setzt `TIME_ATTACK_BUDGET_MS`
  = Startzeit + Rows x Gutschrift): die Reihenwertung ist ohnehin die
  eine Zahl, um die sich der ganze Modus dreht, und ein zweiter, bei
  jedem Abbau fortgeschriebener Zaehler koennte von ihr nur abweichen.
- **Hochwasser** (`flood`, Nutzerwunsch, seit 0.49.0): Marathon mit
  steigendem Wasser. Alle `FLOOD_INTERVAL_MS` (20000 ms = 20 Sekunden)
  Spielzeit schiebt sich von unten eine volle Reihe mit **genau einem
  Loch** ins Feld; das ganze Feld rueckt dabei um eine Zeile nach oben
  (`flood_raise` in `rowhammer.sh`, `board_flood_row` in
  `lib/board.sh`). Sonst ist die Runde Marathon: sie endet im Game Over,
  das Ergebnis sind die Rows, ein Ziel gibt es nicht. Gemessen wird wie
  ueberall `PLAY_MS` (siehe 3.4), eine Pause laesst also kein Wasser
  herein.

**Entscheidungen, die fuer alle vier Modi gleich gelten.** Sie wurden
mit Ultra getroffen (0.34.0) und von den drei spaeteren uebernommen -
alles andere waere im selben Menue schwer zu erklaeren:

- **Gemessen werden Rows, nicht Lines.** "Abgebaute Reihen" bezeichnet
  im Weltwunder- und Statistik-Kontext laengst die gewichtete Wertung
  (siehe 3.2, 3.3); ausserdem macht das die Gold-/Silber-Quadrate - die
  Kernmechanik des Spiels - zum schnellen Weg ins Ziel statt zu totem
  Gewicht. Ein Rowhammer durch zwei Gold-Quadrate (85 Rows) ist bei
  Ultra mehr als die halbe Strecke und verlaengert eine Time-Attack-Runde
  um 85 Sekunden.
- **HUD: zwei zusaetzliche Zaehler** in der linken Spalte
  (`render_pane_left`, Zeile 15/16), nur im jeweiligen Modus sichtbar.
  Sie belegen zwei der acht freien Zeilen aus 3.4; die Modi laufen nie
  gleichzeitig, deshalb teilen sie sich die Zeilen, statt weitere zu
  belegen, und im Marathon bleiben alle acht frei. Was dort steht, sagt
  die Tabelle unten.
- **Rundenende-Kasten** (`render_status_box`): jeder Modus bringt seine
  eigenen Ausgaenge mit, **alle mit denselben acht Innenzeilen**, damit
  die Rahmen stehen bleiben. Der Kasten traegt damit acht Ausgaenge; die
  Fallunterscheidung ist ein `case` ueber `GAME_MODE` mit der
  `GOAL_REACHED`-Pruefung darin.
- **`r` im Rundenende-Bild startet im selben Modus neu** (`game_reset`
  ohne Argument behaelt `GAME_MODE`).
- **Reihen und Zaehler zaehlen immer**, auch wenn ein Lauf nicht in
  seine Bestenliste kommt: Weltwunder-Fortschritt und Statistik nehmen
  ihn wie jede abgebrochene Runde (siehe 3.3).
- **Die Ziele sind justierbare Konstanten**, keine
  Kommandozeilen-Schalter: sie gehoeren zum Spielgefuehl und werden nach
  Playtesting nachgezogen (siehe TODO.md), nicht je Runde gewaehlt.

Die Abweichungen je Modus:

| | Ultra | Sprint | Time Attack | Hochwasser |
| --- | --- | --- | --- | --- |
| Ende | Rows-Ziel erreicht | Zeit abgelaufen | Uhr auf 0, oder Game Over | Game Over |
| Ergebnis | die Spielzeit | die Rows | die Rows | die Rows |
| HUD "Goal" | das Ziel | das Zeitlimit (MM:SS) | erspielte Gesamtzeit | "Flut": Flut-Abstand |
| HUD "Left" | fehlende Rows | Restzeit | Restzeit | "Rest": Zeit bis zur naechsten Flut |
| Gelistet wird | nur ein Lauf am Ziel | nur ein voller Lauf | jeder Lauf | jede Runde |

Vier Einzelheiten dazu:

- **"Left" wird aufgerundet**, wo es eine Zeit ist: die Runde ist
  vorbei, wenn dort 00:00 steht, und Abrunden wuerde diese Anzeige die
  ganze letzte Sekunde lang zeigen. "Left" in Rows wird umgekehrt bei
  Ueberschreitung auf 0 gekappt.
- **Warum ein gescheiterter Ultra- oder Sprint-Lauf nicht gelistet
  wird:** Er hat keine vergleichbare Zeit bzw. weniger Rows aus einem
  Grund, der mit der Spielstaerke nichts zu tun hat; ihn neben volle
  Laeufe zu sortieren hiesse, zwei verschiedene Dinge zu vergleichen.
  **Time Attack und Hochwasser kennen diesen Zustand nicht:** die Runde
  ist zu Ende, wenn sie zu Ende ist, die Rows sind in jedem Fall
  dieselbe Leistung, und wer vorzeitig oben rausbaut, hat schlicht
  weniger davon - dieselbe Lage wie im Marathon. Deshalb traegt bei
  ihnen **auch der Game-Over-Ausgang einen Rang**; die Ueberschrift des
  Kastens ist das, was ihn vom regulaeren Ende unterscheidet.
- **Der Time-Attack-Highscore sind die Rows** (Nutzerfrage). Die zweite
  denkbare Wertung - die ueberlebte Zeit - ist keine Alternative,
  sondern dieselbe Rangfolge: ein Lauf, der an der Uhr endet, hat exakt
  `TIME_ATTACK_START_MS` + Rows x `TIME_ATTACK_ROW_MS` gespielt. Den
  Ausschlag gibt, dass die Rows im ganzen Spiel die Punktwaehrung sind
  (siehe 3.2) und auch fuer den vorzeitig gescheiterten Lauf
  aussagekraeftig bleiben, wo die Gleichung nicht mehr gilt.
- **Das Time-Attack-"Goal" wird in `render_pane_left` neu berechnet**
  statt aus dem Game-Loop uebernommen: ein Abbau passiert nach dessen
  Aktualisierung, und ausgerechnet der Frame, in dem der Spieler die
  Gutschrift sehen will, zeigte sonst noch den alten Stand.

**Zeitmessung.** Bei Ultra ist die Spielzeit die Wertung, deshalb wird
sie im Zielmoment noch einmal nachgefuehrt (`play_clock_tick`, dieselbe
Funktion, die der Game-Loop je Tick nutzt): ein Hard-Drop faellt
zwischen zwei Ticks, und diese Millisekunden gehoeren zum Lauf. Bei
Sprint und Time Attack ist umgekehrt die Uhr das Ziel; ihre Pruefung
(`sprint_time_up`, `time_attack_time_up` in `rowhammer.sh`) sitzt direkt
hinter `play_clock_tick` und **vor** der Gravitation des Ticks, damit
auf abgelaufener Zeit kein Stein mehr faellt oder festgesetzt wird - der
noch fallende Stein wird nicht mehr gelockt, seine Reihen zaehlen also
nicht mehr. Das Zeitguthaben von Time Attack wird dabei **nicht** in
einem eigenen Zaehler gefuehrt, sondern bei Bedarf aus `ROW_CREDIT`
abgeleitet (`time_attack_budget`, siehe oben).

**Entscheidungen zum Hochwasser-Modus** (0.49.0). Seine Uhr beendet die
Runde nicht, sie fuellt das Feld; wo die drei Zeitmodi eine Sonderregel
haben, folgt er deshalb dem Marathon:

- **Die Flutreihe ist eine Reihe eigener Art** (`GARBAGE_CELL`, `x`,
  in `lib/board.sh`), kein Baustein: sie traegt die Instanz-ID 0 und
  kann damit nie Teil eines Quadrats werden (`square_check_at` weist
  ID 0 ab). Das ist dieselbe Festlegung, die der Mehrspieler fuer seine
  Garbage-Reihen trifft (siehe 5.7) - der Hochwasser-Modus nimmt sie
  vorweg, statt eine zweite zu erfinden. Angezeigt wird sie grau mit
  einem eigenen Glyph (`::`, `GARBAGE_GLYPH` in `lib/render.sh`), **auch
  im Farbmodus**: im Thema `mono` haben die Steine dasselbe Grau, und
  eine Reihe, die niemand gelegt hat, soll in jedem Fall als solche zu
  erkennen sein.
- **Das Hochschieben laesst die Steine heil.** `board_flood_row`
  verschiebt `BOARD`, `BOARD_ID` und `BOARD_SQ` zeilenweise gemeinsam;
  Instanzen behalten ihre ID und ihre Gold-/Silber-Markierung und
  wandern nur nach oben - ein Quadrat ueberlebt die Flut also genauso,
  wie es einen Reihenabbau unter sich ueberlebt. Eine neue Flutreihe
  kann nie eine volle Reihe ergeben (sie hat immer ihr Loch), deshalb
  folgt ihr keine Abbaupruefung.
- **Steht der Stapel nach dem Anstieg ueber dem Feld, ist die Runde
  vorbei.** Das ist das Game Over dieses Modus, so wie der blockierte
  Spawn das des Marathons ist; entschieden wird es von `board_top_out`
  (siehe 3.1) - dieselbe Regel, an der auch ein festgesetzter Stein
  gemessen wird.
- **Der fallende Stein bleibt, wo er ist** - der Stapel steigt unter
  ihm. Nur wenn er danach im gestiegenen Stapel steckt, rueckt er eine
  Zeile mit hoch: er lag auf dem, was sich bewegt hat, und sitzt damit
  wieder genau dort, wo er sass. Ist auch das blockiert (der Stein
  steht ganz oben), endet die Runde. Ein scharfes Lock-Delay wird nur
  geprueft, nicht neu gestellt (`lock_delay_recheck`) - die Regel aus
  3.1 gilt unveraendert: nur wer wieder fallen kann, faellt weiter.
- **Die naechste Flut wird vom Eintreffen der letzten an gerechnet**
  (`FLOOD_NEXT_MS` = `PLAY_MS` + `FLOOD_INTERVAL_MS`), nicht von ihrem
  Soll-Zeitpunkt. Sonst haette ein spaet gekommener Tick (Resize,
  Blink-Animation, langsames Terminal) mehrere faellige Reihen auf
  einmal im Feld - dieselbe Ueberlegung, aus der die Gravitation
  `LAST_FALL` auf "jetzt" setzt.
- **Die Fluthoehe steht im Game-Loop vor der Gravitation, aber in einem
  eigenen `if`.** Ein Anstieg ist kein Rundenende und darf dem Tick
  seine Gravitation nicht nehmen - das Wasser kommt, waehrend der Stein
  weiterfaellt, das ist der Modus. Beendet er die Runde, faengt das
  `GAME_OVER`-Zweiglein vor der Kette das ab: auf einer beendeten Runde
  faellt und lockt nichts mehr.

### 3.7 Namensabfrage am Rundenende (seit 0.45.0)

Am Ende einer Runde fragt das Spiel nach dem Namen, unter dem die Runde
in ihrer Bestenliste steht (Nutzerwunsch). Der **Spielername aus den
Einstellungen ist die Vorgabe** und steht **vormarkiert** in der
Eingabezeile - wie in einem grafischen Textfeld: das erste getippte
Zeichen ersetzt sie vollstaendig, Enter uebernimmt sie unveraendert.

- **Wann:** in `record_round` (`rowhammer.sh`), also an jedem echten
  Rundenende (Game Over, "Runde beenden", "Neustarten", Programmende
  mit wartender Runde, siehe 3.3) und dank `ROUND_RECORDED` genau
  einmal je Runde. Und zwar **vor** dem Listeneintrag: dort geht der
  Name hinein, und dort entsteht der Rang, den der Rundenende-Kasten
  anschliessend zeigt.
- **Nur fuer eine Runde, die wirklich einen Platz in einer Liste
  bekommt** (`round_is_ranked`): Sie spiegelt die Modus-Regeln aus 3.6
  (nur ein
  erfolgreicher Ultra-/Sprint-Lauf wird gelistet), die
  Null-Pruefungen der Listenfunktionen selbst (`lib/highscore.sh`
  verwirft eine Runde ohne Rows bzw. ohne gemessene Zeit) und - seit
  1.0.1, Nutzerwunsch - die Top 10 selbst: die Platz-Vorschau
  (`round_rank_preview`, siehe unten) muss einen Platz melden. Eine
  Runde,
  die nirgends abgelegt wird, hat keinen Namen zu erfragen; alles
  andere, was sie noch speist - Weltwunder-Fortschritt und Statistik -,
  ist ohnehin namenlos. Eine Runde, die die Top 10 verfehlt, behaelt den
  Spielernamen aus den Einstellungen und geht direkt zum
  Rundenende-Kasten, der dieselben Zahlen ohnehin zeigt.
- **Der eingegebene Name gilt fuer diese eine Runde**, die Einstellung
  bleibt unveraendert (und damit die Vorgabe der naechsten Runde). Das
  ist genau der Fall, fuer den die Abfrage da ist - jemand anderes
  spielt eine Runde mit -, und es laesst den Einstellungs-Eintrag die
  eine Stelle sein, die die Vorgabe bestimmt. `record_round` haelt den
  Namen deshalb in einer lokalen Variablen und gibt ihn an die
  `highscore_*_add`-Funktionen weiter, statt `PLAYER_NAME` zu
  ueberschreiben.
- **Bedienung** (`menu_text_input` in `lib/menu.sh`, gemeinsam genutzt
  mit der Namensabfrage im Einstellungsmenue): Tippen ersetzt die
  markierte Vorgabe, Backspace auf ihr loescht sie, eine **Pfeiltaste
  hebt die Markierung auf und behaelt den Text** (die Vorgabe laesst
  sich also auch bearbeiten statt ersetzen). Danach verhaelt sich die
  Zeile wie eine gewoehnliche Eingabe: Zeichen haengen an, Backspace
  loescht das letzte. Enter uebernimmt, `ESC` laesst alles beim Alten,
  eine leer gemachte Zeile ebenfalls. Es gibt keinen Cursor **im**
  Text - bei maximal 16 Zeichen wird vom Ende her editiert.
- **Nur gueltige Zeichen kommen ueberhaupt an** (`MENU_INPUT_RE`,
  `MENU_INPUT_MAX`: dasselbe Muster, gegen das der Spielername beim
  Start und beim Laden der Config geprueft wird, max. 16 Zeichen). Der
  Editor kann damit keinen ungueltigen Namen erzeugen, und die frueher
  noetige Fehlermeldung nach der Eingabe entfaellt. Eine
  Buchstabentaste ist hier ein Buchstabe und keine Spielaktion - `x`
  schliesst den Dialog also nicht, dafuer ist `ESC` da.
- **Der Platz in der Bestenliste steht dabei (seit 0.50.0,
  Nutzerwunsch):** unter den Rundenzahlen nennt der Bildschirm den Rang,
  den die Runde in der Liste ihres Modus einnehmen wird ("Bestenliste:
  Platz 3 von 10").
  Er wird **vorhergesagt statt abgelesen**: der Eintrag entsteht erst
  hinter dieser Abfrage (der Name geht in ihn hinein, siehe oben), also
  leitet `highscore_rank_preview` (`lib/highscore.sh`, siehe 4.5) den
  Platz aus der geladenen Liste ab, ohne sie anzufassen -
  `round_rank_preview` (`rowhammer.sh`) sagt ihr dafuer, nach welcher
  Zahl der Modus rangiert (Zeit bei Ultra, Rows sonst), dieselbe
  Fallunterscheidung, die gleich darueber `round_is_ranked` trifft. Die
  Vorschau kann vom spaeteren Eintrag nicht abweichen: sie wendet
  dessen Einfuegeregel an, und zwischen beiden aendert nichts die
  Liste. Seit 1.0.1 ist dieselbe Vorschau zugleich die Bedingung fuer
  die Abfrage (siehe oben), sodass der Bildschirm immer einen Platz
  nennt. Sie laeuft damit zweimal je Runde - einmal in
  `round_is_ranked`, einmal in `prompt_round_name` -, was eine
  Abfrage in einer bereits geladenen Liste ist und beide Stellen
  fuer sich lesbar laesst.
- **Die Zeit steht auf die Millisekunde genau da (seit 1.0.3,
  Nutzerwunsch):** `fmt_duration_ms` (MM:SS.mmm) wie in der
  Ultra-Bestenliste, und zwar **in jedem Modus**, nicht nur im Ultra -
  ein Bildschirm soll eine Zahl nicht in zwei Formen zeigen, je nachdem
  welcher Modus lief. Gelesen wird `PLAY_MS`, also genau der Wert, der
  gleich in den Eintrag geht. Der Rundenende-Kasten bleibt davon
  unberuehrt: dort ist die Zeit im Ultra ohnehin schon auf die
  Millisekunde genau (siehe 3.6), und in den anderen Modi ist sie nicht
  die Wertung, sondern eine Randnotiz.
- **Darstellung:** ein regulaerer, zentrierter Menue-Frame
  (`render_menu_frame`, siehe 4.3) mit Modus, Rows, Lines, Level, Zeit
  und Listenplatz der Runde ueber der Eingabezeile. Die Markierung ist invertierter
  Text (`\e[7m`), nach ihrem Aufheben steht ein invertierter Block als
  Cursor hinter dem Text - der echte Cursor bleibt die ganze Sitzung
  ueber ausgeblendet. Danach setzt `prompt_round_name` `RENDER_FULL=1`,
  damit das Spielfeld samt Rundenende-Kasten vollstaendig neu gezeichnet
  wird.

