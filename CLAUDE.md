# CLAUDE.md - rowhammer

Diese Datei gibt Claude Code (und menschlichen Mitwirkenden) den Kontext,
das Konzept und die Arbeitsregeln fuer dieses Repository. Sie beschreibt
den **aktuellen** Stand und das, was noch aussteht; die abgeschlossenen
Roadmap-Punkte samt ihrer Begruendung liegen im Archiv
[HISTORY.md](HISTORY.md).

## 1. Projektueberblick

**rowhammer** ist ein Tetris-artiges Spiel, das vollstaendig in **Bash** im
Terminal laeuft. Vorbild ist **"The New Tetris"** fuer das Nintendo 64:

- Ueber alle Runden hinweg wird an einem **Weltwunder** gebaut. Der Baufortschritt
  richtet sich nach der **Gesamtzahl der abgebauten Reihen**.
- Das **Quadrat-System** des Originals ist enthalten: Aus Bausteinen gebildete
  4x4-Quadrate werden zu **Gold-** (sortenrein) bzw. **Silber-Bloecken**
  (gemischt) und liefern beim Abbau Bonus-Reihen.
- Eine **Multiplayer-Funktion** ist geplant, wird aber erst in einer spaeteren
  Phase umgesetzt (siehe Roadmap).

Der Repo-Name "rowhammer" ist ein Wortspiel: Es geht ums "Hammern" von Reihen
(rows), nicht um den gleichnamigen Hardware-Angriff.

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
  1.0.4). **Umstellung von sieben auf 63 (Nutzerentscheidung):** um mehr
  Dynamik fuer die Bildung der Spezialbloecke (Gold-/Silber-Quadrate,
  siehe 3.2) zu bekommen. Die Garantie des Beutels bleibt dieselbe -
  ueber einen vollen Beutel kommt jede Sorte gleich oft -, aber
  innerhalb des Beutels ist die Reihenfolge deutlich freier: bei einem
  Beutel aus sieben Steinen liegen zwei gleiche Sorten hoechstens zwoelf
  Steine auseinander, und diese gleichmaessige Ausgabe ist genau das,
  was ein Quadrat schwer macht - es braucht vier zueinander passende
  Teile. Der lange Beutel bringt beides zurueck: die Haeufung gleicher
  Sorten, aus der ein Gold-Quadrat ueberhaupt erst wird, und die
  Duerre, die es zu einer Entscheidung macht. Zwei Festlegungen dazu:
  - **Gemischt wird ueber den ganzen Beutel**, nicht Satz fuer Satz. Ein
    Mischen je Siebenersatz wuerde nur siebenmal je sieben Steine
    umsortieren und damit genau die gleichmaessige Verteilung erhalten,
    die hier geloest werden soll.
  - **Die Satzzahl ist eine justierbare Konstante** (`BAG_SETS`), wie
    `ULTRA_TARGET_ROWS` oder `FLOOD_INTERVAL_MS`: sie gehoert zum
    Spielgefuehl und wird nach Playtesting nachgezogen, nicht je Runde
    gewaehlt. `BAG_SETS=1` ist wieder der klassische 7er-Beutel.
  Demos und der geplante Mehrspieler bleiben davon unberuehrt: eine
  Aufnahme speichert die Steinfolge selbst und keinen Beutel (siehe
  4.10), und die Mehrspieler-Fairness haengt am gemeinsamen Seed
  (siehe 5.1), nicht an der Beutelgroesse.
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
  bleibt - also in den beiden verdeckten Spawn-Zeilen. Bis 0.55.0 kannte
  das Spiel nur einen einzigen Top-Out, die blockierte Spawn-Position;
  ein Stein liess sich deshalb auf der obersten Reihe festsetzen und
  durfte darueber hinausragen, ohne dass die Runde verloren war. Das
  Feld ist 20 Reihen hoch, und was darueber stehen bleibt, gehoert nicht
  mehr dazu. Umsetzung: `board_top_out` (`lib/board.sh`) meldet, ob eine
  Zelle in den verdeckten Zeilen liegt; gefragt wird sie an den zwei
  Stellen, an denen dort etwas hinkommen kann - `lock_and_next` nach dem
  Festsetzen eines Steins und `flood_raise` nach einem Anstieg im
  Hochwasser-Modus (beide in `rowhammer.sh`). Die Entscheidungen dazu:
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
    erst beim naechsten Lock. Damit rueckt dieses Rundenende eine Zeile
    frueher als die alte Pruefung in `board_flood_row` (die eine Zelle
    erst dann nicht mehr schieben wollte, wenn sie vom Brett gefallen
    waere). Jene Pruefung bleibt als Eigensicherung der Funktion stehen:
    sie ist das Einzige, was ueberhaupt verhindert, dass eine Zelle aus
    dem Brett geschoben wird, und die Mehrspieler-Garbage (5.7) wird
    dort spaeter mehrere Reihen auf einmal durchschieben.
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
  seit 0.23.0 aber ueber `key_drain` (`lib/input.sh`) statt eines rohen
  `read`: ein Roh-Read verwarf einzelne Bytes und konnte damit genau die
  Haelfte einer Escape-Sequenz schlucken - blieb `[C` einer Pfeiltaste
  liegen, wurde das `C` danach als Hold-Taste `c` angewandt (Issue #7 an
  der Eingabeschicht vorbei). `key_drain` schickt die Bytes durch
  denselben Zustandsautomaten und verwirft nur die fertig erkannten
  Tasten, sodass eine Sequenz entweder ganz oder gar nicht geschluckt
  wird. Dieselbe Funktion nutzt die "resize me"-Overlay.

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

### 3.3 Weltwunder-Aufbau (umgesetzt, Version 0.8.0)

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
  (1.270.000 gewichtete Reihen insgesamt).
  **Kosten-Umstellung 0.45.0 (Nutzerentscheidung):** die urspruengliche
  Reihe 100..6.400 (12.700 insgesamt) war bewusst auf
  Einzelrechner-Spielzeit herunterskaliert und damit deutlich zu billig -
  ein Wunder fiel in wenigen Runden. Jede Kostenstelle wurde mit 100
  multipliziert; die Verdopplung je Wunder und die Wunder-Liste selbst
  bleiben unveraendert, nur der Massstab wandert an den des Originals
  (dort 2.500 bis 500.000 Zeilen je Wunder) heran, sodass ein Wunder
  wieder ein Langfrist-Ziel ist. Ein vorhandener Spielstand behaelt
  seinen Reihenzaehler (`save`, siehe 4.5), kauft damit aber weniger
  Fortschritt: die Baustelle faellt auf ein frueheres Wunder und eine
  fruehere Baustufe zurueck. Das ist Absicht und kein Datenverlust - der
  Zaehler ist die einzige gespeicherte Groesse, Wunder und Baustufe
  werden aus ihm abgeleitet (siehe 4.5).
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
Enter, Leertaste, `x` und `ESC` schliessen die Anleitung. Zuvor fuehrte
jede beliebige Taste zur naechsten Seite, ohne Weg zurueck - die fuenf
Bildschirme liefen als feste Folge einzelner `menu_message`-Aufrufe
nacheinander durch. Damit auch rueckwaerts auf jede Seite gesprungen
werden kann, baut `menu_help_body` (ein `case`-Switch je Seite, 0-basiert)
den Inhalt der angeforderten Seite bei Bedarf neu, statt ihn wie vorher
in fester Reihenfolge einmal durchzureichen:

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
   fuenf Zeilen, was in vieren steht.

10. Mehrspieler (seit 1.1.0): dass jeder sein eigenes Feld mit
   derselben Steinfolge spielt, dass abgebaute Reihen dem Gegner
   Stoerreihen schicken und ein eigener Abbau zuerst die eigene
   Warteschlange raeumt, wie eine Sitzung eroeffnet und gefunden wird
   (Beacon oder eingegebene Adresse), dass der Letzte im Feld gewinnt,
   dass es keine Pause gibt, dass nur die eigene Leistung gewertet wird
   und dass socat gebraucht wird. Spielerzahl und Port kommen aus
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
Bestenlisten-Seite nutzt sie mit 18 Zeilen genau aus, die Demo-Seite
mit 17.

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

Entscheidungen zu Ultra (die drei in der Roadmap offen gelassenen
Punkte, im Sinne der dortigen Empfehlung entschieden):

- **Gemessen werden Rows, nicht Lines.** "Abgebaute Reihen" bezeichnet
  im Weltwunder- und Statistik-Kontext laengst die gewichtete Wertung
  (siehe 3.2, 3.3); ausserdem macht das die Gold-/Silber-Quadrate - die
  Kernmechanik des Spiels - zum schnellen Weg ins Ziel statt zu totem
  Gewicht. Ein Rowhammer durch zwei Gold-Quadrate (85 Rows) ist damit
  mehr als die halbe Strecke.
- **Nur erfolgreiche Laeufe kommen in die Ultra-Bestenliste.** Ein
  Versuch, der vorher im Game Over endet, hat keine vergleichbare Zeit;
  ihn nach Rows einzusortieren hiesse, zwei Ordnungen in eine Liste zu
  mischen. Reihen und Zaehler eines gescheiterten Versuchs zaehlen aber
  wie bei jeder abgebrochenen Runde in Weltwunder-Fortschritt und
  Statistik (siehe 3.3).
- **HUD:** zwei zusaetzliche Zaehler in der linken Spalte, nur im
  Ultra-Modus sichtbar (`render_pane_left`, Zeile 15/16): "Goal" (das
  Ziel) und "Left" (noch fehlende Rows, bei Ueberschreitung auf 0
  gekappt). Sie belegen zwei der acht freien Zeilen aus 3.4; im
  Marathon-Modus bleiben alle acht frei.
- **Rundenende-Kasten** (`render_status_box`): derselbe Kasten ueber dem
  Spielfeld traegt jetzt drei Ausgaenge, alle mit denselben acht
  Innenzeilen, damit die Rahmen stehen bleiben - "ULTRA CLEAR" mit Zeit
  (`fmt_duration_ms`, MM:SS.mmm) und Ultra-Rang, ein gescheiterter
  Ultra-Versuch mit dem erreichten Stand ("Rows 87/150", bewusst ohne
  Rang) und das klassische Game Over der endlosen Runde mit dem
  Highscore-Rang.
- **Zeitmessung:** die Spielzeit der Runde (siehe 3.4) ist die Wertung,
  deshalb wird sie im Zielmoment noch einmal nachgefuehrt
  (`play_clock_tick`, dieselbe Funktion, die der Game-Loop je Tick
  nutzt): ein Hard-Drop faellt zwischen zwei Ticks, und diese
  Millisekunden gehoeren zum Lauf.
- **`r` im Rundenende-Bild startet im selben Modus neu** (`game_reset`
  ohne Argument behaelt `GAME_MODE`).

Entscheidungen zu Sprint (0.39.0). Der Modus ist die Umkehrung von
Ultra, deshalb sind die Ultra-Entscheidungen oben eins zu eins
gespiegelt - alles andere waere im selben Menue schwer zu erklaeren:

- **Gewertet werden Rows, nicht Lines** - dieselbe Begruendung wie bei
  Ultra (siehe oben): "abgebaute Reihen" heisst im ganzen Spiel die
  gewichtete Wertung, und die Quadrate sollen auch hier der schnelle
  Weg zu einem guten Ergebnis sein.
- **Nur vollstaendige Laeufe kommen in die Sprint-Bestenliste.** Ein
  Versuch, der nach einer Minute im Game Over endet, hat weniger Rows
  aus einem Grund, der mit der Spielstaerke nichts zu tun hat; er neben
  vollen Laeufen einzusortieren hiesse, zwei verschiedene Dinge zu
  vergleichen. Reihen und Zaehler zaehlen wie bei jeder abgebrochenen
  Runde in Weltwunder-Fortschritt und Statistik (siehe 3.3).
- **HUD:** dieselben zwei Zeilen der linken Spalte wie bei Ultra
  (`render_pane_left`, Zeile 15/16, siehe 3.4): "Goal" ist hier das
  Zeitlimit (MM:SS) und "Left" die verbleibende Spielzeit, auf die
  naechste ganze Sekunde aufgerundet - die Runde ist vorbei, wenn dort
  00:00 steht, und Abrunden wuerde diese Anzeige die ganze letzte
  Sekunde lang zeigen. Die Modi laufen nie gleichzeitig, deshalb teilen
  sie sich die Zeilen, statt zwei weitere zu belegen.
- **Rundenende-Kasten** (`render_status_box`): zwei weitere Ausgaenge
  mit denselben acht Innenzeilen - "SPRINT END" mit den erreichten Rows
  und dem Sprint-Rang, und fuer einen vorzeitig gescheiterten Versuch
  das klassische Game Over mit der gespielten Zeit ("Time 01:23/03:00",
  bewusst ohne Rang). Damit traegt der Kasten fuenf Ausgaenge; die
  Fallunterscheidung ist deshalb ein `case` ueber `GAME_MODE` mit der
  `GOAL_REACHED`-Pruefung darin.
- **Zeitmessung:** die Zielpruefung sitzt im Game-Loop direkt hinter
  `play_clock_tick` (`sprint_time_up` in `rowhammer.sh`) - die Uhr ist
  hier das Ziel, so wie die Reihenwertung es bei Ultra ist, und dort
  wird sie fortgeschrieben. Sie laeuft **vor** der Gravitation des
  Ticks, damit auf abgelaufener Zeit kein Stein mehr faellt oder
  festgesetzt wird; der noch fallende Stein wird nicht mehr gelockt,
  seine Reihen zaehlen also nicht mehr.

Entscheidungen zu Time Attack (0.42.0). Der Modus liegt zwischen den
beiden anderen - eine Uhr wie bei Sprint, aber eine, die von der
Reihenwertung gespeist wird -, deshalb folgt er ihren Entscheidungen,
wo sie passen, und weicht an genau einer Stelle begruendet ab:

- **Gewertet werden Rows, nicht Lines** - dieselbe Begruendung wie bei
  Ultra und Sprint, hier zusaetzlich zwingend: die Rows sind zugleich
  die Waehrung, mit der Spielzeit gekauft wird. Ein Rowhammer durch
  zwei Gold-Quadrate (85 Rows) verlaengert die Runde damit um 85
  Sekunden.
- **Der Highscore sind die Rows** (Nutzerfrage). Die zweite denkbare
  Wertung - die ueberlebte Zeit - ist keine Alternative, sondern
  dieselbe Rangfolge: ein Lauf, der an der Uhr endet, hat exakt
  `TIME_ATTACK_START_MS` + Rows x `TIME_ATTACK_ROW_MS` gespielt, seine
  Zeit ist also eine Funktion seiner Rows und sortiert die Liste
  zwangslaeufig gleich. Den Ausschlag gibt, dass die Rows im ganzen
  Spiel die Punktwaehrung sind (siehe 3.2) und auch fuer den vorzeitig
  gescheiterten Lauf noch aussagekraeftig bleiben, wo die Gleichung
  nicht mehr gilt. Die Zeit steht in der Liste trotzdem daneben - sie
  ist genau die Spalte, an der ein solcher Lauf zu erkennen ist.
- **Jeder Lauf kommt in die Time-Attack-Bestenliste** - die bewusste
  Abweichung von Ultra und Sprint. Dort gibt es einen Zustand
  "abgebrochen", der sich mit einem vollen Lauf nicht vergleichen
  laesst (keine Zeit bzw. weniger Zeit zum Punkten). Time Attack kennt
  diesen Zustand nicht: die Runde ist zu Ende, wenn sie zu Ende ist,
  die Rows sind in beiden Faellen dieselbe Leistung, und wer vorzeitig
  oben rausbaut, hat schlicht weniger davon - dieselbe Lage wie im
  Marathon, wo eine Runde ebenfalls im Game Over endet und trotzdem
  gewertet wird.
- **HUD:** dieselben zwei Zeilen wie Ultra und Sprint
  (`render_pane_left`, Zeile 15/16, siehe 3.4). "Goal" ist hier keine
  Konstante, sondern die bisher erspielte Gesamtzeit
  (`TIME_ATTACK_BUDGET_MS`, MM:SS) - so ist zu sehen, was ein Abbau in
  Zeit wert war -, "Left" die Restzeit, aufgerundet wie bei Sprint. Der
  Wert wird in `render_pane_left` neu berechnet statt aus dem Game-Loop
  uebernommen: ein Abbau passiert nach dessen Aktualisierung, und
  ausgerechnet der Frame, in dem der Spieler die Gutschrift sehen will,
  zeigte sonst noch den alten Stand.
- **Rundenende-Kasten** (`render_status_box`): zwei weitere Ausgaenge,
  wieder mit denselben acht Innenzeilen - "TIME UP" bzw. "GAME OVER",
  beide mit den erreichten Rows und dem Time-Attack-Rang. Anders als
  bei Ultra und Sprint traegt **auch der Game-Over-Ausgang einen Rang**,
  denn beide Laeufe werden gewertet; die Ueberschrift ist das, was sie
  unterscheidet. Damit traegt der Kasten sieben Ausgaenge.
- **Zeitmessung:** die Zielpruefung sitzt an derselben Stelle im
  Game-Loop wie die von Sprint, direkt hinter `play_clock_tick` und vor
  der Gravitation (`time_attack_time_up` in `rowhammer.sh`), aus
  demselben Grund: auf abgelaufener Zeit soll kein Stein mehr fallen
  oder festgesetzt werden.
- **`r` im Rundenende-Bild startet im selben Modus neu**, wie bei den
  anderen Modi (`game_reset` ohne Argument).

Entscheidungen zu Hochwasser (0.49.0). Die Uhr dieses Modus beendet die
Runde nicht, sie fuellt das Feld; wo die drei Zeitmodi eine Sonderregel
haben, folgt er deshalb dem Marathon:

- **Die Flutreihe ist eine Reihe eigener Art** (`GARBAGE_CELL`, `x`,
  in `lib/board.sh`), kein Baustein: sie traegt die Instanz-ID 0 und
  kann damit nie Teil eines Quadrats werden (`square_check_at` weist
  ID 0 ab). Das ist dieselbe Festlegung, die die Mehrspieler-
  Spezifikation fuer ihre Garbage-Reihen trifft (siehe 5.7) - der
  Hochwasser-Modus nimmt sie vorweg, statt eine zweite zu erfinden.
  Angezeigt wird sie grau mit einem eigenen Glyph (`::`,
  `GARBAGE_GLYPH` in `lib/render.sh`), **auch im Farbmodus**: im Thema
  `mono` haben die Steine dasselbe Grau, und eine Reihe, die niemand
  gelegt hat, soll in jedem Fall als solche zu erkennen sein.
- **Das Hochschieben laesst die Steine heil.** `board_flood_row`
  verschiebt `BOARD`, `BOARD_ID` und `BOARD_SQ` zeilenweise gemeinsam;
  Instanzen behalten ihre ID und ihre Gold-/Silber-Markierung und
  wandern nur nach oben - ein Quadrat ueberlebt die Flut also genauso,
  wie es einen Reihenabbau unter sich ueberlebt. Eine neue Flutreihe
  kann nie eine volle Reihe ergeben (sie hat immer ihr Loch), deshalb
  folgt ihr keine Abbaupruefung.
- **Steht der Stapel nach dem Anstieg ueber dem Feld, ist die Runde
  vorbei.** Das ist das Game Over dieses Modus, so wie der blockierte
  Spawn das des Marathons ist. Seit 1.0.2 entscheidet das
  `board_top_out` (die verdeckten Zeilen oberhalb des Feldes, siehe
  3.1) - dieselbe Regel, an der auch ein festgesetzter Stein gemessen
  wird, und eine Zeile frueher als bis 0.55.0, wo `board_flood_row` das
  Schieben erst verweigerte, wenn eine Zelle vom Brett gefallen waere.
  Jene Pruefung meldet den Fall weiterhin, ohne etwas zu aendern, und
  bleibt als Eigensicherung der Funktion bestehen.
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
- **Jede Runde kommt in die Hochwasser-Bestenliste**, wie bei Time
  Attack und aus demselben Grund: es gibt keinen Zustand
  "abgebrochen", der sich nicht vergleichen liesse - jede Runde dieses
  Modus endet im Game Over, das ist der Modus. Eigene Datei
  `${DATA_DIR}/highscore-flood` (siehe 4.5), Rangordnung nach Rows wie
  im Marathon, denn am Wert einer Runde aendert die Flut nichts.
- **HUD:** dieselben zwei Zeilen wie die drei Zeitmodi
  (`render_pane_left`, Zeile 15/16, siehe 3.4), aber mit eigenem Label:
  "Flut" ist der Abstand zweier Flutreihen (`FLOOD_INTERVAL_MS`,
  MM:SS), "Rest" die Zeit bis zur naechsten, aufgerundet wie bei
  Sprint. Kein "Ziel", weil es hier keines gibt.
- **Rundenende-Kasten** (`render_status_box`): ein weiterer Ausgang mit
  denselben acht Innenzeilen - "GAME OVER" mit den erreichten Rows und
  dem Hochwasser-Rang; damit traegt der Kasten acht Ausgaenge. Der Rang
  steht hier neben dem Game Over, weil jede Runde gewertet wird, und
  die Rows nehmen die Zeile, die einem gescheiterten Zeitmodus-Lauf
  seinen Stand zeigt: sie sind die Geschichte einer Runde, die kuerzer
  ist als eine Marathon-Runde.
- **`r` im Rundenende-Bild startet im selben Modus neu**, wie ueberall
  (`game_reset` ohne Argument).
- **Der Abstand ist eine justierbare Konstante**, kein
  Kommandozeilen-Schalter: wie `ULTRA_TARGET_ROWS` und `SPRINT_TIME_MS`
  gehoert er zum Spielgefuehl und wird nach Playtesting nachgezogen
  (siehe Abschnitt 8), nicht je Runde gewaehlt.

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
  ist ohnehin namenlos.
  **Aenderung 1.0.1 (Nutzerwunsch):** bis 0.55.0 entschied die
  Vorschau nur, *was* auf dem Bildschirm stand ("Platz 3 von 10" bzw.
  "kein Platz (Top 10)"), nicht *ob* es ihn gab - eine Runde ohne Platz
  wurde nach einem Namen gefragt, der nirgends hinging. Sie behaelt
  jetzt den Spielernamen aus den Einstellungen und geht direkt zum
  Rundenende-Kasten, der dieselben Zahlen ohnehin zeigt. Damit hat die
  Meldung "kein Platz" keinen Fall mehr und ist aus beiden
  Sprachdateien entfallen.
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
  nennt: eine **verfehlte** Liste wurde bis 0.55.0 mit "kein Platz
  (Top 10)" gemeldet, wird jetzt aber gar nicht mehr gefragt. Die
  Vorschau laeuft damit zweimal je Runde - einmal in
  `round_is_ranked`, einmal in `prompt_round_name` -, was eine
  Abfrage in einer bereits geladenen Liste ist und beide Stellen
  fuer sich lesbar laesst.
- **Die Zeit steht auf die Millisekunde genau da (seit 1.0.3,
  Nutzerwunsch):** `fmt_duration_ms` (MM:SS.mmm) wie in der
  Ultra-Bestenliste, und zwar **in jedem Modus**, nicht nur im Ultra.
  Bis 1.0.2 zeigte der Bildschirm `fmt_duration` (MM:SS) - und schnitt
  damit ausgerechnet die Stellen ab, die im Ultra ueber den Platz
  entscheiden, den derselbe Bildschirm eine Zeile tiefer nennt (zwei
  Versuche auf dasselbe Ziel landen oft in derselben Sekunde, deshalb
  speichert die Ultra-Liste Millisekunden, siehe 4.5). Fuer alle Modi
  gleich, weil ein Bildschirm eine Zahl nicht in zwei Formen zeigen
  soll, je nachdem welcher Modus lief; gelesen wird `PLAY_MS`, also
  genau der Wert, der gleich in den Eintrag geht. Der Rundenende-Kasten
  bleibt davon unberuehrt: dort ist die Zeit im Ultra ohnehin schon auf
  die Millisekunde genau (siehe 3.6), und in den anderen Modi ist sie
  nicht die Wertung, sondern eine Randnotiz.
- **Darstellung:** ein regulaerer, zentrierter Menue-Frame
  (`render_menu_frame`, siehe 4.3) mit Modus, Rows, Lines, Level, Zeit
  und Listenplatz der Runde ueber der Eingabezeile. Die Markierung ist invertierter
  Text (`\e[7m`), nach ihrem Aufheben steht ein invertierter Block als
  Cursor hinter dem Text - der echte Cursor bleibt die ganze Sitzung
  ueber ausgeblendet. Danach setzt `prompt_round_name` `RENDER_FULL=1`,
  damit das Spielfeld samt Rundenende-Kasten vollstaendig neu gezeichnet
  wird.

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
  Roadmap offen gelassene Frage nach einer Obergrenze entschieden: eine
  reine **Stueckzahl** (`DEMO_MAX`, 10 wie die Bestenlisten) reicht, ein
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
  **nicht als RNG-Seed** - obwohl die Roadmap "Eingabe-Mitschnitt plus
  Seed" skizziert hatte. `RANDOM` wird einmal je Sitzung gesetzt, nicht
  je Runde (eine zweite Runde setzt den Strom fort), und der Generator
  hinter `RANDOM` hat sich zwischen Bash-Versionen geaendert: ein Seed
  wuerde auf einer anderen Bash eine andere Runde abspielen. Ein Byte je
  Stein macht die Frage gegenstandslos.

**Bedienung der Wiedergabe** (die dritte in der Roadmap offen gelassene
Frage - Pause und Vorspulen: beides, plus Zeitlupe):

- Pausetaste (`p`) oder Leertaste haelt an und laeuft weiter; angezeigt
  wird das ueber denselben "PAUSED"-Kasten wie im Spiel.
- Pfeil links/rechts stellt das Tempo in fuenf Stufen von **0.25x bis
  4x** (`DEMO_SPEEDS`). Die aktuelle Stufe steht im HUD in der linken
  Spalte (Zeile 18, Label "Demo") - die einzige Angabe, die dem Bild
  sonst fehlen wuerde.
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

## 4. Technisches Konzept

### 4.1 Rahmenbedingungen

- **Bash >= 4.0** (assoziative Arrays), Ziel: uebliche Linux-Distributionen.
- Keine harten Abhaengigkeiten ausser Coreutils; `tput` optional (Fallback auf
  feste ANSI-Sequenzen).
- Farben ueber ANSI-Escape-Sequenzen (8/16 Farben als Basis, 256-Farben als
  Verbesserung wenn verfuegbar). Umgesetzt seit 0.9.0: `--color-mode`
  mit `auto` (Erkennung ueber `tput colors`, `TERM`, `COLORTERM`),
  `basic` und `extended`; die vorberechneten SGR-Sequenzen
  baut `render_colors_init` in `lib/render.sh`.
- **Konfigurierbare Farben ueber benannte Farbschemata (Themes,
  seit 0.21.0):** Farben werden ueber symbolische Namen (z. B. `cyan`,
  `orange`, `gold`) adressiert; jeder Name traegt eine Basic- (ANSI-
  Vordergrund, Tabelle `COLOR_BASIC`) und eine Extended-Bedeutung
  (256er-Index, `COLOR_EXT`), beide in `lib/pieces.sh`. Ein Theme
  (`THEME_COLOR`, Liste `COLOR_THEMES`) bildet jede Steinsorte und die
  Gold-/Silber-Quadrate auf einen solchen Namen ab. Das loest das
  Zwei-Paletten-Problem sauber: eine rohe SGR-Zahl gilt nur in einem
  Modus, ein Name in beiden. Vier Schemata: `guideline` (bisheriges
  Standard-Aussehen, unveraendert reproduziert), `classic`, `mono` und
  `colorblind` (deuteranopie-tauglich, meidet das Rot/Gruen-Paar).
  Auswahl im Einstellungsmenue (mit Live-Farbvorschau je Theme,
  `render_theme_swatch`), per `--color-theme NAME`
  (`ROWHAMMER_COLOR_THEME`, Standard `guideline`) und gespeichert in der
  Config (`COLOR_THEME`). `--no-color` hat weiterhin Vorrang und schaltet
  Farben ganz ab. `render_colors_init` liest das aktive Theme und baut
  daraus die finalen SGR-Sequenzen fuer den aufgeloesten Farbmodus.
- Im farblosen Modus (`--no-color`/`NO_COLOR`, seit 0.28.0) bekommt jede
  Steinsorte ein eigenes Zwei-Zeichen-Glyph statt eines einheitlichen
  `[]` (`PIECE_GLYPH` in `lib/pieces.sh`: `II OO TT SS ZZ JJ LL`), damit
  abgelegte Steine unterscheidbar bleiben und Gold-/Silber-Quadrate
  ueberhaupt planbar sind. Die Quadrate nutzen bewusst Nicht-Buchstaben-
  Glyphen (`SQ_GOLD_GLYPH`/`SQ_SILVER_GLYPH` in `lib/render.sh`: `##`
  fuer Gold, `%%` fuer Silber), damit ein Quadrat nie mit einer Steinsorte
  kollidiert (insbesondere kollidiert der S-Stein `SS` so nie mit einem
  Silber-Quadrat).
- Die Flutreihen des Hochwasser-Modus (seit 0.49.0, siehe 3.6) haben
  einen eigenen Farbslot je Theme (`THEME_COLOR[...:GARBAGE]`, ueberall
  `grey`) und ein eigenes Glyph (`GARBAGE_GLYPH` in `lib/render.sh`:
  `::`) - anders als die Steine **auch im Farbmodus**, denn im Thema
  `mono` sind die Steine ebenfalls grau, und eine Reihe, die niemand
  gelegt hat, soll immer als solche zu erkennen sein.

### 4.2 Architektur und Dateistruktur

Ein Hauptskript, Logik in sourcebaren Modulen:

```
rowhammer/
  rowhammer.sh         # Hauptskript: Argumente, Init, Game-Loop
  lib/
    board.sh           # Spielfeld-Zustand, Kollision, Reihenabbau
    pieces.sh          # Baustein-Definitionen und Rotationstabellen
    squares.sh         # Erkennung und Verwaltung von Gold-/Silber-Quadraten
    render.sh          # Rendering (Layout, Zeilen-Diff, ANSI)
    input.sh           # Nicht-blockierende Tastatureingabe
    menu.sh            # Startmenue (Einzel-/Mehrspieler, Einstellungen)
    config.sh          # Laden/Speichern der Nutzer-Konfiguration
    debug.sh           # Debug-Modus: Session-Trace in Log-Dateien
    demo.sh            # Demo-Aufzeichnung und -Wiedergabe (Format, Ablage)
    i18n.sh            # Uebersetzungsschicht: Sprachwahl, Texttabelle
    lang/
      de.sh            # deutsche Texte (Referenzsprache)
      en.sh            # englische Texte
    highscore.sh       # Persistente Highscore-Liste (Top 10)
    wonders.sh         # Weltwunder-Logik, Baustufen, Fortschritt
    save.sh            # Laden/Speichern des Spielstands
    stats.sh           # Persistente Spielstatistik (Reihen, Bonusreihen, Bloecke)
    net.sh             # Transport: socat (TCP/Unix), Discovery, Limits
    proto.sh           # Nachrichtentabelle, Parser mit Validierung
    hub.sh             # Sitzungslogik des Hubs (Lobby, Garbage, KO)
    mp.sh              # Client-Seite: Lobby, Peer-Zustaende, Anbindung
  assets/
    wonders/           # ASCII-Art je Wunder und Baustufe
  tools/
    key-scan.sh        # Regressionstest der Eingabeschicht (Issue #7)
    net-fuzz.sh        # Fuzz-Test der Mehrspieler-Parser (siehe 5.5)
    release.sh         # Versions-Abgleich, Release-Notes, Release-Tag
    demo/              # Werkzeuge fuer die asciinema-Democlips
  .github/workflows/
    ci.yml             # Pruefungen und Paketbau bei Push/Pull Request
    release.yml        # Paketbau und GitHub-Release bei einem v*-Tag
  Makefile             # install/uninstall-Ziele (genutzt von deb und rpm)
  build-deb.sh         # Baut das Debian-Paket, Artefakte nach dist/
  build-rpm.sh         # Baut das RPM-Paket, Artefakte nach dist/
  debian/              # Debian-Paketierung (debhelper, natives Paket)
  rowhammer.spec       # RPM-Paketierung (nutzt dasselbe make install)
  docs/
    release-process.md # Ablauf eines Releases und was die Workflows tun
    input-analysis.md  # Analyse der Eingabeschicht (Nachfassen Issue #7)
  CLAUDE.md            # Konzept, Architektur, offene Roadmap
  HISTORY.md           # Archiv der erledigten Roadmap-Punkte
  README.md
```

Stand (Version 1.1.0): alle Module aus dem Baum oben existieren; die
vier Mehrspieler-Module (`net`, `proto`, `hub`, `mp`) sind mit 1.1.0
dazugekommen (siehe Abschnitt 5)
(`rowhammer.sh`, `lib/*.sh` inklusive `wonders.sh`, `save.sh`,
`stats.sh`, `demo.sh` und `i18n.sh` mit `lib/lang/` sowie
`assets/wonders/` mit einer Art-Datei je Wunder). Die Anwendung
startet in einem Menue (Einzelspieler / Mehrspieler /
Highscores / Weltwunder / Statistik / Demos / Einstellungen /
Anleitung / Beenden;
solange eine pausierte Runde wartet, zusaetzlich "Fortsetzen" an
erster Stelle, ebenso im Einzelspieler-Untermenue). Das
Einzelspieler-Untermenue waehlt seit 0.34.0 den Spielmodus
("Marathon", "Ultra", seit 0.39.0 "Sprint", seit 0.42.0
"Time Attack" und seit 0.49.0 "Hochwasser", siehe 3.6; der
endlose Modus hiess bis
0.34.1 "Normales Spiel"), und seit 0.38.0 waehlt der Menuepunkt
"Highscores" ebenso den Modus der anzuzeigenden Bestenliste
(`menu_highscores`, seit 0.49.0 mit fuenf Listen, siehe 4.5). Seit
0.47.0 waehlt auch der Menuepunkt "Statistik" zuerst die Sicht
(`menu_stats`: Gesamt oder einer der Modi, siehe 4.5). Die
Modus-Eintraege dieser drei Auswahlen baut seit 0.48.0 ein gemeinsamer
Helfer (`menu_mode_entries`); seit 1.1.0 haengt er auf Wunsch einen
sechsten Modus an - den Mehrspieler, den nur die beiden
Rueckblick-Auswahlen (Highscores, Statistik) fuehren, weil er im
Einzelspieler-Menue nicht gestartet wird; seit 0.53.0 nennt jeder Eintrag hinter dem
Namen in einer eigenen, ausgerichteten Spalte, wogegen der Modus laeuft
(siehe 3.6). Die
Menue-Beschriftung
ist seit 0.48.0 nicht mehr fest, sondern uebersetzt (siehe 4.11):
Deutsch und Englisch stehen zur Wahl, Code, Kommentare und
Diagnosemeldungen nach STDERR bleiben Englisch.
Das Spielfeld haelt je Zelle drei parallele Arrays (Sorte `BOARD`,
Instanz-ID `BOARD_ID`, Quadrat-Status `BOARD_SQ`); der HUD-Zaehler
"Rows" ist die gewichtete Reihenwertung (1/5/10), die den
Weltwunder-Fortschritt speist und seit 0.16.0 zugleich der Score der
Runde ist (siehe 3.2), "Lines" zaehlt physische Reihen und
treibt das Level. Seit 0.45.0 fragt jede Runde, die in eine
Bestenliste kommt, an ihrem Ende nach dem Namen fuer den Eintrag
(vormarkierte Vorgabe aus den Einstellungen, siehe 3.7).
CLI-Optionen bisher: `--seed N` (`ROWHAMMER_SEED`)
fuer reproduzierbare Teilfolgen, `--name NAME` (`ROWHAMMER_PLAYER_NAME`),
`--lang de|en|auto` (`ROWHAMMER_LANG`, Standard `auto`, seit 0.48.0;
auch im Einstellungsmenue waehlbar und in der Config gespeichert,
siehe 4.11),
`--data-dir DIR` (`ROWHAMMER_DATA_DIR`) fuer das Datenverzeichnis,
`--no-color` (`ROWHAMMER_NO_COLOR`; seit 0.28.0 wird zusaetzlich die
De-facto-Standardvariable `NO_COLOR` [https://no-color.org/] beachtet:
ist sie gesetzt und nicht leer, sind Farben standardmaessig aus.
Praezedenz der Abschalt-Schalter: Standard-`NO_COLOR` < projekteigenes
`ROWHAMMER_NO_COLOR` < `--no-color` auf der Kommandozeile, sodass ein
global exportiertes `NO_COLOR` per `ROWHAMMER_NO_COLOR=0` fuer rowhammer
wieder ueberschrieben werden kann), `--color-mode auto|basic|extended`
(`ROWHAMMER_COLOR_MODE`, Standard `auto`; `--no-color` gewinnt),
`--color-theme guideline|classic|mono|colorblind`
(`ROWHAMMER_COLOR_THEME`, Standard `guideline`; auch im
Einstellungsmenue waehlbar und in der Config gespeichert),
`--render-mode partial|full` (`ROWHAMMER_RENDER_MODE`, Standard
`partial`, seit 0.41.0, siehe 4.3),
`--demo-record on|off` (`ROWHAMMER_DEMO_RECORD`, Standard `on`, seit
0.46.0; auch im Einstellungsmenue und in der Config, siehe 3.8/4.10),
die Mehrspieler-Optionen `--mp-transport lan|unix`, `--mp-port N`,
`--mp-dir DIR`, `--mp-max N`, `--mp-session NAME`,
`--mp-view auto|full|compact|score`, `--mp-target random|all|even`,
`--mp-host`, `--mp-join HOST[:PORT]` und `--mp-bot` (je mit
`ROWHAMMER_MP_*`-Variable, seit 1.1.0, siehe 5.10) sowie die drei
internen Prozessmodi `--mp-hub`, `--mp-bridge` und `--mp-discover`,
`--reset config|stats|highscore|save|demo|all` (`ROWHAMMER_RESET`, seit
0.35.0, das Ziel `demo` seit 0.46.0, siehe 4.8), `--force` (`ROWHAMMER_FORCE`, seit 0.36.0:
beantwortet Sicherheitsabfragen automatisch mit "ja", derzeit die des
Resets; frei mit anderen Optionen kombinierbar),
`--debug` (`ROWHAMMER_DEBUG`),
`--debug-dir DIR` (`ROWHAMMER_DEBUG_DIR`), `-h/--help`. Tastenbelegung
zusaetzlich per `ROWHAMMER_KEY_*`-Umgebungsvariablen uebersteuerbar.

### 4.3 Game-Loop, Input, Rendering

- **Game-Loop:** feste Tick-Rate; Fall-Intervall abhaengig vom Level.
  Zeitmessung ueber `${EPOCHREALTIME}` (Bash 5) mit Fallback. Ruht ein
  Stein (Lock Delay scharf, `LOCK_PENDING`), pausiert die Gravitation und
  der Loop lockt erst nach Ablauf von `LOCK_DELAY_MS` seit `TOUCHDOWN_MS`
  (siehe 3.1).
- **Input:** nicht-blockierend ueber `read -rsn1 -t <timeout>`;
  Escape-Sequenzen der Pfeiltasten sauber einlesen. Terminal-Modus mit `stty`
  setzen und ueber einen `trap`-Handler (EXIT/INT/TERM) garantiert
  wiederherstellen. **Der Rohmodus gilt seit 0.28.1 fuer die ganze
  Sitzung** (`term_input_raw` in `lib/input.sh`, aufgerufen aus
  `term_setup`: `stty -echo -icanon min 1 time 0`, Issue #33). Vorher
  war ueberhaupt kein Modus gesetzt; das Spiel lebte von dem Modus, den
  `read -rsn1` nur fuer die Dauer eines einzelnen Reads einstellt und
  danach zuruecknimmt. Zwischen zwei Reads - beim Bauen und Schreiben
  eines Frames, waehrend der Blink-Animation und auf den Pause- und
  Game-Over-Bildschirmen - echote das Terminal darum jeden Tastendruck
  an die Cursorposition, also hinter die zuletzt geschriebene Zeile.
  Seit dem inkrementellen Rendering (0.22.0) wird eine unveraenderte
  Zeile nicht mehr neu geschrieben, sodass das echote `^[[C` stehen
  blieb (frueher hatte der naechste Voll-Frame es uebermalt). **Seit
  0.45.0 gilt der Rohmodus ausnahmslos:** die einzige Ausnahme war die
  Namensabfrage, die per `term_input_line` in den kanonischen Modus mit
  Echo zurueckschaltete; mit dem gemeinsamen Zeileneditor `menu_text_input`
  (siehe 3.7) zeichnet das Spiel die getippte Zeile selbst, `term_input_line`
  ist ersatzlos entfallen.
  Der Editor liest ueber denselben `read_key`, nur im **Textmodus**
  (`KEY_TEXT`, `lib/input.sh`): eine gesetzte Flagge aendert allein die
  Behandlung einfacher Bytes in `key_plain` - das Zeichen wird so
  gemeldet, wie es getippt wurde (statt kleingeschrieben), und die
  beiden Loeschbytes (0x08/0x7f) werden zur Taste `BACKSPACE`, statt als
  inert verworfen zu werden. Beides ist fuer das Spiel falsch (`A` und
  `a` sind dieselbe Bindung, an Backspace haengt nichts) und fuer eine
  Namenseingabe unverzichtbar. Escape-Sequenzen laufen unveraendert
  durch den Zustandsautomaten unten, sodass Pfeiltasten, Mausmeldungen,
  Terminalantworten und Paste im Textmodus genauso behandelt werden wie
  im Spiel. Die Flagge wird nur um den einzelnen `read_key`-Aufruf herum
  gesetzt, damit kein Rueckgabepfad sie in den Game-Loop traegt.
  Escape-Sequenzen laufen seit 0.23.0 (Issue #7,
  Analyse in `docs/input-analysis.md`) durch einen **Zustandsautomaten**
  (`key_feed` und die `key_in_*`-Helfer in `lib/input.sh`), dessen
  Zustand in Globals liegt und damit ueber `read_key`-Aufrufe und
  Spiel-Ticks hinweg erhalten bleibt: eine vom Terminal in Stuecken
  zugestellte Sequenz (SSH, tmux/screen, Last) wird unabhaengig von der
  Luecke zwischen ihren Bytes als eine Sequenz zusammengesetzt. Bis
  0.20.0 musste die Entscheidung innerhalb eines Aufrufs fallen, und
  spaet eintreffende Bytes wurden als eigene Tastendruecke angewandt
  (der Schwanz `C` einer Rechts-Pfeiltaste wurde zur Hold-Taste `c`);
  das Hochsetzen des Fortsetzungs-Timeouts auf 50 ms in 0.16.1 hatte
  das nur unwahrscheinlicher gemacht, ab rund 45 ms Byte-Abstand riss
  eine Pfeiltaste weiterhin auseinander. Derselbe Automat konsumiert
  die Sequenzklassen, die zuvor ihre Nutzlast als Tastendruecke
  durchreichten: X10-Mausmeldungen (drei Rohbytes nach `ESC [ M`),
  OSC-/DCS-Terminalantworten, 8-Bit-CSI (`0x9b`), ueberlange
  CSI-Sequenzen und Bracketed Paste (in `term_setup` eingeschaltet,
  Mausmeldungen werden dort zugleich abgeschaltet). Bytes ausserhalb
  des druckbaren ASCII werden verworfen statt gemeldet. Zeitabhaengig
  ist nur noch, wann ein einzelnes `Esc` gemeldet wird
  (`ESC_LONE_MS`, 300 ms); trifft der Rest der Sequenz danach doch noch
  ein, faengt ihn der Zustand `esc_late` ab, sodass auch dann kein
  Schwanz-Byte zur Taste wird. Ein Byte, das Bash (beobachtet mit 5.1)
  im Timeout-Moment zusammen mit dem Timeout-Status liefert, wird
  weiterhin ausgewertet statt verworfen. Regressionstest:
  `tools/key-scan.sh` (72 Faelle, auch mit kuenstlicher Byte-Luecke
  ueber `--gap`). Seit 0.19.0
  behandelt der Input-Layer auch Terminal-Groessenaenderungen: ein
  SIGWINCH-Trap (scharf ab `term_setup`) setzt nur das Flag
  `TERM_RESIZED`; `read_key` wendet es beim naechsten Tick ueber
  `term_resize_apply` an (neu messen mit `term_measure`, Bildschirm
  loeschen, `REDRAW_PENDING` fuer die aufrufende Schleife setzen) und
  blockiert bei Unterschreitung des 48x22-Minimums hinter der
  "resize me"-Overlay, bis das Terminal wieder gross genug ist
  (HISTORY.md, 0.19.0 "Anpassung an Terminalgroesse").
- **Rendering (inkrementell seit 0.22.0):** `draw_frame` baut den
  Spielbildschirm zeilenweise in das Array `FRAME_LINES`; `render_flush`
  vergleicht es mit dem zuletzt ausgegebenen Stand (`PREV_LINES`) und
  schreibt **nur die tatsaechlich geaenderten Zeilen**, jede mit eigener
  Cursor-Positionierung, in einem einzigen `printf` (Double-Buffering
  gegen Flackern). Weil jede Zeile exakt `LAYOUT_W` sichtbare Spalten
  breit ist (siehe 3.4), ueberdeckt eine neue Zeile ihre Vorgaengerin
  immer vollstaendig. `RENDER_FULL` erzwingt einen Voll-Neuaufbau
  (Bildschirm loeschen, alle Zeilen schreiben) nach Menues, Resize und
  zum Rundenstart.
  Zusaetzlich sind die **liegenden Feldreihen gecacht**
  (`BOARD_ROW_CACHE`): sie werden nur nach einer echten Brettaenderung
  neu gebaut (`render_board_dirty`, aufgerufen aus `board_init`,
  `lock_piece`, `clear_lines` und der Quadrat-Markierung in
  `lib/squares.sh`). Ein bloss bewegter Stein kostet damit die
  hoechstens vier Reihen unter dem Stein statt aller 200 Zellen.
  Gemessen gegen den frueheren Voll-Frame-Renderer: rund die Haelfte der
  Zeit je Frame und etwa ein Vierzehntel der Terminal-Ausgabe.
- **Umschaltbar seit 0.41.0:** `--render-mode partial|full`
  (`ROWHAMMER_RENDER_MODE`, Standard `partial`) waehlt zwischen dem
  Zeilen-Diff oben und dem Voll-Aufbau, wie ihn der Renderer vor 0.22.0
  hatte (jede der `LAYOUT_H` Zeilen je Frame). `partial` bleibt der
  Standard, weil es die ressourcenschonende Variante ist; `full` ist
  der Kompatibilitaets-Rueckfall fuer Terminals und Multiplexer, bei
  denen das inkrementelle Update falsch dargestellt wird, und der
  Debugging-Fall, in dem das Frame-Log ganze Frames zeigen soll (der
  Modus steht deshalb im Kopf von `events.log`, siehe 4.6). Der
  Schalter ist wie `--color-mode` **kein Config-Wert** (Praezedenz
  Standard < Env < CLI): er ist eine Eigenschaft des benutzten
  Terminals, keine Geschmacksfrage, und muss erreichbar bleiben, ohne
  eine Datei zu bearbeiten, wenn gerade die Bildausgabe das Defekte
  ist. Die Variable gehoert `rowhammer.sh`; `lib/render.sh` liest sie
  nur und setzt bewusst **keinen** eigenen Vorgabewert - die Module
  werden nach dem Parsen der Argumente gesourct, eine Zuweisung dort
  wuerde den gerade gesetzten CLI-Wert ueberschreiben.
  Umgesetzt in `render_flush`: das Flag entscheidet allein darueber, ob
  alle Zeilen geschrieben werden; **ob der Bildschirm geloescht wird,
  haengt weiterhin allein an `RENDER_FULL`** (Menue, Resize,
  Rundenstart). Der kuerzere Weg, den die Roadmap skizziert hatte -
  `RENDER_FULL` dauerhaft auf 1 halten - haette mit jedem Frame ein
  `\e[2J` geschickt und den Rueckfallmodus flackern lassen, also genau
  das Gegenteil dessen bewirkt, wozu er da ist.
  Cursor verstecken, alternativen Screen-Buffer nutzen, und im
  Alternate-Screen ist der **Auto-Wrap abgeschaltet** (`\e[?7l`): bei
  exakt 48x22 fuellt das Layout die letzte Bildschirmzelle, was mit
  Auto-Wrap auf manchen Terminals scrollen wuerde.
- **Menue- und Info-Bildschirme (zentriert seit 0.28.0):** Menues,
  Info-Bildschirme, Abfragen und der Weltwunder-Bildschirm werden nicht
  mehr als ein Block ab `\e[H` geschrieben, sondern als Liste reiner
  Inhaltszeilen an `render_menu_frame` (`lib/render.sh`) uebergeben.
  Die Funktion positioniert jede Zeile einzeln: **linke Kante wie der
  Spielblock** (dieselbe Zentrierung von `LAYOUT_W`, damit Menue und
  Spielbildschirm buendig sind) und **vertikal nach der eigenen Hoehe
  zentriert**, weil die Bildschirme unterschiedlich lang sind. Jede
  geschriebene Zeile endet mit `\e[K`, sodass eine kuerzere Zeile keinen
  Rest ihrer Vorgaengerin stehen laesst; die sichtbare Breite wird nie
  gemessen (die Zeilen enthalten SGR-Sequenzen). Zwischen zwei Menues
  werden nur die Zeilen geloescht, die der vorherige Block belegte und
  der neue nicht mehr abdeckt - ein Voll-Loeschen je Tastendruck wuerde
  beim Blaettern flackern. Das Flag `MENU_FULL` merkt sich dagegen, dass
  ein **anderer** Bildschirm zuletzt dran war (Spielblock ueber
  `render_flush`, "resize me"-Overlay, Resize ueber `layout_update` -
  jede dieser Stellen setzt das Flag selbst); dann loescht der
  naechste Menue-Frame zuerst den ganzen Bildschirm. Der Helfer
  `render_menu_dirty`, ueber den frueher die echoende Namensabfrage das
  Flag setzte, ist mit ihr in 0.45.0 entfallen (siehe 3.7): der neue
  Zeileneditor ist selbst ein regulaerer Menue-Frame. Nach einem Resize
  bauen die Warteschleifen ihren Frame neu auf, statt den gespeicherten
  erneut auszugeben - er traegt absolute Cursor-Positionen der alten
  Terminalgroesse.
- **Datenmodell:** Spielfeld als eindimensionales Bash-Array (Index
  `y * Breite + x`); Zelle enthaelt Sorte, Stein-Instanz-ID und
  Quadrat-Status (keins/Silber/Gold), damit `squares.sh` und die
  Reihenwertung effizient arbeiten koennen.

### 4.4 Quadrat-Erkennung (Skizze)

1. Jede gelegte Stein-Instanz bekommt eine eindeutige ID; jede Zelle kennt
   ihre ID. Beim Reihenabbau werden betroffene Instanzen als "zerschnitten"
   markiert.
2. Nach jedem Lock: Fuer jede moegliche 4x4-Position (begrenzt auf die Umgebung
   des neuen Steins) pruefen, ob genau 4 unzerschnittene Instanzen den Bereich
   exakt fuellen und keine Zelle dieser Instanzen ausserhalb liegt.
3. Bei Treffer: Zellen als Gold/Silber markieren; die Instanzen sind damit
   verbraucht (ein Stein kann nur zu einem Quadrat gehoeren).

### 4.5 Persistenz

- Alle persistenten Spieldaten liegen gemeinsam im Datenverzeichnis
  `${HOME}/.config/rowhammer` (seit 0.13.0, vorher `${HOME}/rowhammer`;
  aenderbar per `--data-dir DIR` bzw.
  `ROWHAMMER_DATA_DIR`): die Konfiguration `rowhammer.conf`, die
  Marathon-Bestenliste `highscore-marathon` (bis 0.50.0 `highscore`,
  siehe unten), die Ultra-Bestenliste `highscore-ultra`
  (seit 0.34.0, siehe 3.6), die Sprint-Bestenliste `highscore-sprint`
  (seit 0.39.0), die Time-Attack-Bestenliste `highscore-timeattack`
  (seit 0.42.0), die Hochwasser-Bestenliste `highscore-flood`
  (seit 0.49.0), die Mehrspieler-Bestenliste `highscore-versus`
  (seit 1.1.0, siehe unten), der Spielstand `save`, die
  Statistik `stats` und - seit 0.46.0 - das Unterverzeichnis `demos`
  mit den aufgezeichneten Runden (Format und Ablage siehe 4.10; als
  einziger Eintrag ein Verzeichnis statt einer Datei, weil es beliebig
  viele Aufnahmen bis `DEMO_MAX` fasst).
- Bewusste Abweichung von den Script-Konventionen (Abschnitt 11,
  organisationsbasierte Suche unter `/etc` und `${HOME}/.config`):
  seit 0.7.0 gibt es genau eine Config-Datei im Datenverzeichnis
  (Nutzerentscheidung). Alte Pfade werden gemaess der Arbeitsregel
  "keine Abwaertskompatibilitaet" nicht mehr beruecksichtigt - das
  gilt auch fuer den Umzug des Datenverzeichnisses nach
  `${HOME}/.config/rowhammer` in 0.13.0 (keine Migration von
  `${HOME}/rowhammer`).
- Alle Dateien werden atomar geschrieben (Tempdatei + `mv`).
- `lib/config.sh` (seit 0.2.0, Pfad seit 0.7.0): das Einstellungsmenue
  (Spielername, Sprache seit 0.48.0, Farbschema seit 0.21.0,
  Tastenbelegung, Demo-Aufzeichnung seit 0.46.0) schreibt
  `${DATA_DIR}/rowhammer.conf`;
  Werte werden validiert und single-quoted geschrieben, da die Datei
  gesourct wird. Das Farbschema wird als `COLOR_THEME='...'` gespeichert
  und beim Laden gegen die bekannten Schemata validiert (unbekannt =
  Abbruch mit Meldung); die Sprache steht als `LANGUAGE='...'` daneben
  und wird genauso geprueft (siehe 4.11). Der Spielername ist die **Vorgabe** der
  Namensabfrage am Rundenende (siehe 3.7); geaendert wird er nur hier im
  Einstellungsmenue, seit 0.45.0 mit demselben Zeileneditor
  (`menu_text_input`) und dem bisherigen Namen vormarkiert.
- `lib/highscore.sh` (seit 0.7.0): Top 10 abgeschlossener Runden in
  `${DATA_DIR}/highscore-marathon` (bis 0.50.0 `highscore`, siehe die
  Umbenennung unten), eine Zeile je Eintrag im Format
  `rows|lines|level|name|date|gold|silver|time|rowhammers|pieces|hash`,
  absteigend nach Rows
  sortiert. Seit dem Punktesystem-Umbau (0.16.0) ist die gewichtete
  Reihenwertung der einzige Score: das fruehere fuehrende
  `score`-Feld entfaellt, Rows bestimmt die Rangfolge und den Rang
  im Game-Over-Bild. Das Feld `time` (seit 0.17.0) ist
  die Spielzeit der Runde in ganzen Sekunden, `rowhammers` (seit
  0.25.0) die Zahl der Vierfach-Abbaeue der Runde und das
  abschliessende Feld `pieces` (seit 0.27.0) die Zahl der abgelegten
  Teile. Seit 0.46.0 folgt darauf `hash`, der aus den Ergebnissen der
  Runde berechnete Kennwert (`round_hash` in `rowhammer.sh`, acht
  Hex-Ziffern oder `-` fuer einen aelteren Eintrag ohne). Er verbindet
  den Eintrag mit der Aufzeichnung derselben Runde, die ihn im
  Dateinamen traegt: solange ein Eintrag in einer der Listen steht, wird
  seine Demo nicht weggeraeumt (siehe 3.8 und 4.10). Alle vier Listen
  tragen ihn als **letztes** Feld, sodass `highscore_hash_set` sie mit
  einer einzigen Expansion einsammeln kann.
  Seit 0.29.0 (Nutzerentscheidung, bewusste Ausnahme von der
  Arbeitsregel "keine Abwaertskompatibilitaet"): eine Zeile muss nicht
  mehr alle elf Felder tragen. Akzeptiert werden 5, 7, 8, 9, 10 oder 11
  Felder - genau die Laengen, die das Format seit dem Punktesystem-
  Umbau (0.16.0, Rows fuehrend) beim schrittweisen Anhaengen von
  Gold/Silber, Zeit, Rowhammer, Pieces und - seit 0.46.0 - dem
  Runden-Hash tatsaechlich durchlaufen hat
  (`HS_FIELD_COUNTS`, `highscore_parse_line` in `lib/highscore.sh`).
  Fehlende Zaehler werden beim Laden als `0` ergaenzt statt die ganze
  Runde zu verwerfen - eine Runde soll nicht verschwinden, nur weil sie
  aelter ist als ein Zaehler. Zeilen aus der Zeit vor 0.16.0 (fuehrendes
  `score`-Feld, Rows an dritter Stelle) sind davon ausgenommen: das ist
  eine andere Spaltenreihenfolge und keine bloss kuerzere Version der
  heutigen, ein Wiederverwenden ihrer Felder wuerde den alten Score
  faelschlich als Rows einordnen. Jede andere Feldzahl sowie ein
  einzelnes Feld, das sein Muster nicht erfuellt (Namen, Datum, Zahlen),
  wirft weiterhin die ganze Zeile heraus.
  Die Datei wird geparst und validiert (nicht gesourct); defekte
  Zeilen werden beim Laden uebersprungen. Eine Runde wird beim
  echten Rundenende genau einmal gewertet (Game Over oder endgueltiges
  Beenden der Runde, siehe 3.3; 0 Rows zaehlt nicht, gleiche Rows
  rangieren hinter dem aelteren Eintrag). Das Feld `name` ist seit
  0.45.0 nicht mehr zwangslaeufig der Spielername aus den Einstellungen,
  sondern der am Rundenende abgefragte (siehe 3.7) - fuer alle vier
  Listen gleichermassen. Der erreichte Rang erscheint im Game-Over-Bild,
  die Liste unter "Highscores" im Hauptmenue. Angezeigt wird je
  Eintrag seit 0.27.0 ein **Zwei-Zeilen-Block** (Nutzerentscheidung:
  die Anzeige darf dafuer mehrzeilig werden): erste Zeile Rang, Name,
  Rows, Spielzeit (Spalte "Zeit", MM:SS; seit 0.17.0) und Datum (seit
  0.14.0), zweite Zeile die Gold- und Silberquadrate ("Gold"/"Silb"),
  die Rowhammer der Runde ("RH", seit 0.25.0), die abgelegten Teile
  ("PCS") und die daraus mit der Spielzeit berechnete Ablegerate
  ("PPM", Teile je Minute, `fmt_ppm` in `rowhammer.sh`).
  **Ultra-Bestenliste (seit 0.34.0, siehe 3.6):** die Ergebnisse des
  Ultra-Modus liegen in einer **eigenen** Datei `${DATA_DIR}/highscore-ultra`
  mit eigener Ordnung - Zeilenformat
  `time|rows|lines|level|name|date|gold|silver|rowhammers|pieces|hash`,
  aufsteigend nach `time` sortiert (schnellster Lauf zuerst, gleiche
  Zeit rangiert hinter dem aelteren Eintrag), ebenfalls Top 10
  (`HSU_*` in `lib/highscore.sh`). Zwei Gruende fuer die getrennte
  Datei: ein Lauf auf Zeit und eine endlose Runde sind ueber Rows nicht
  vergleichbar, und ein 150-Rows-Lauf soll die Top 10 der endlosen
  Liste nicht verdraengen. Das fuehrende `time`-Feld ist die Spielzeit
  in **Millisekunden** (nicht in ganzen Sekunden wie in der
  Normal-Liste): es ist hier das Sortierkriterium, und zwei Versuche auf
  dasselbe Ziel landen oft genug in derselben Sekunde, dass ganze
  Sekunden die Rangfolge nach Eintreffen statt nach Tempo entscheiden
  wuerden; angezeigt wird das ueber `fmt_duration_ms` als
  MM:SS.mmm. Gespeichert werden nur Laeufe, die das Ziel erreicht haben
  (Entscheidung in 3.6). Es gilt die uebliche Arbeitsregel "keine
  Abwaertskompatibilitaet": seit 0.46.0 elf Felder, oder zehn fuer eine Zeile
  ohne den Runden-Hash; jede andere faellt bei der Validierung heraus.
  Die Kulanz um genau diese eine Laenge kam mit dem Hash: das Format hat
  seither doch in einer kuerzeren Fassung existiert, und es gilt derselbe
  Grund wie bei der Marathon-Liste - ein Eintrag soll nicht
  verschwinden, nur weil er aelter ist als ein Feld.
  **Anzeige (seit 0.38.0, Nutzerwunsch):** `highscore_ultra_screen`
  zeigt die Liste so, wie `highscore_screen` die Marathon-Liste zeigt -
  seitenweise ueber `highscore_browse`, zwei Zeilen je Eintrag, gleiche
  Spaltenbreiten, gleiche Faerbung (deshalb teilt sie sich auch
  `HS_PAGE_ENTRIES`: gleiche Eintragshoehe, eine zweite Konstante
  koennte nur auseinanderlaufen). Zwei Unterschiede,
  beide aus der Rangordnung nach Zeit: die Zeit-Spalte traegt die
  Akzentfarbe, die auf dem Marathon-Bildschirm die Rows-Spalte hat (sie
  ist hier der Score), und die PPM-Spalte rechnet die Millisekunden auf
  ganze Sekunden herunter, die Einheit von `fmt_ppm`. Die Rows-Spalte
  bleibt daneben stehen - ein Ultra-Lauf endet bei oder ueber
  `ULTRA_TARGET_ROWS`, und um wie viel er ueberschossen hat, ist eine
  Information. Der erreichte Rang steht wie bisher zusaetzlich im
  Rundenende-Kasten.
  **Sprint-Bestenliste (seit 0.39.0, Nutzerwunsch, siehe 3.6):** die
  Ergebnisse des Sprint-Modus liegen in einer dritten Datei
  `${DATA_DIR}/highscore-sprint`, Zeilenformat und Rangordnung wie die
  Marathon-Liste
  (`rows|lines|level|name|date|gold|silver|time|rowhammers|pieces|hash`,
  absteigend nach Rows, gleiche Rows rangieren hinter dem aelteren
  Eintrag), ebenfalls Top 10 (`HSS_*` in `lib/highscore.sh`). Das
  gleiche Format ist Absicht: gewertet wird dieselbe Zahl in derselben
  Einheit, ein zweites Layout waere nur ein zweites, das mitgepflegt
  werden muesste. Eine eigene Datei ist es trotzdem, denn ein auf drei
  Minuten begrenzter Lauf und eine Runde, die erst beim Game Over endet,
  sind nicht dasselbe - die Rows der endlosen Liste wuerden die kurzen
  Laeufe schlicht verdraengen. Gespeichert werden nur Laeufe, die ihre
  volle Zeit gespielt haben (Entscheidung in 3.6). Wie bei der
  Ultra-Liste werden seit 0.46.0 elf Felder erwartet, oder zehn fuer
  eine Zeile ohne den Runden-Hash; jede andere faellt bei der
  Validierung heraus.
  **Anzeige:** `highscore_sprint_screen` zeigt die Liste im Layout der
  beiden anderen (seitenweise ueber `highscore_browse`, dasselbe
  `HS_PAGE_ENTRIES`, zwei Zeilen je Eintrag, gleiche
  Spaltenbreiten und Faerbung, Rows in der Akzentfarbe wie auf dem
  Marathon-Bildschirm). Eine Spalte weicht ab: wo die Marathon-Liste die
  Spielzeit zeigt, stehen hier die physischen Reihen ("Lines"). Jeder
  Eintrag hat dieselben drei Minuten gespielt, eine Zeitspalte stuende
  also zehnmal gleich da; die Lines sind neben den gewichteten Rows die
  interessante Zahl, weil beide zusammen zeigen, wie viel des Ergebnisses
  aus den Quadraten kam. Gespeichert bleibt die Spielzeit trotzdem - die
  PPM-Spalte der zweiten Zeile rechnet mit ihr.
  **Time-Attack-Bestenliste (seit 0.42.0, Nutzerwunsch, siehe 3.6):**
  die Ergebnisse des Time-Attack-Modus liegen in einer vierten Datei
  `${DATA_DIR}/highscore-timeattack`, Zeilenformat und Rangordnung
  wieder wie die Marathon-Liste (absteigend nach Rows, gleiche Rows
  hinter dem aelteren Eintrag), ebenfalls Top 10 (`HSA_*` in
  `lib/highscore.sh`), seit 0.46.0 ebenfalls elf Felder mit dem
  Runden-Hash am Ende (oder zehn ohne ihn, wie bei den anderen Listen). Dass die Rows und nicht die ueberlebte Zeit die
  Wertung sind, ist in 3.6 begruendet (beide ergeben dieselbe
  Rangfolge). Eine eigene Datei ist noetig, weil ein Lauf auf einer
  selbst erspielten Minute nicht die Leistung einer endlosen Runde ist.
  Der Unterschied zu den beiden anderen Zeitmodi: **jeder** Lauf wird
  gespeichert, auch der vorzeitig im Game Over gescheiterte
  (Entscheidung in 3.6) - dieser Modus hat keinen Zustand
  "unvollstaendig", der sich nicht vergleichen liesse.
  **Anzeige:** `highscore_timeattack_screen` zeigt die Liste im Layout
  der drei anderen (seitenweise ueber `highscore_browse`, dasselbe
  `HS_PAGE_ENTRIES`, zwei Zeilen je Eintrag, Rows in der
  Akzentfarbe). Die Spalten sind die der Marathon-Liste samt
  Spielzeit - und die verdient ihren Platz hier: ein Lauf an der Uhr
  spielt genau Startzeit + eine Sekunde je Row, eine kuerzere Zeit
  weist den Eintrag also als vorzeitig beendet aus.
  **Hochwasser-Bestenliste (seit 0.49.0, Nutzerwunsch, siehe 3.6):**
  die Ergebnisse des Hochwasser-Modus liegen in einer fuenften Datei
  `${DATA_DIR}/highscore-flood`, Zeilenformat und Rangordnung wieder wie
  die Marathon-Liste (absteigend nach Rows, gleiche Rows hinter dem
  aelteren Eintrag), ebenfalls Top 10 (`HSF_*` in `lib/highscore.sh`).
  Anders als die vier aelteren Listen kennt sie **nur die volle
  Feldzahl** (elf, mit dem Runden-Hash am Ende): sie ist mit ihm
  entstanden und hat deshalb keine kuerzere Fassung, gegenueber der sie
  kulant sein muesste. Eine eigene Datei ist noetig, weil eine Runde
  unter steigendem Wasser nach Minuten endet und in der endlosen Liste
  nie einen Platz saehe. Wie bei Time Attack wird **jede** Runde
  gespeichert (Entscheidung in 3.6) - dieser Modus endet immer im Game
  Over, einen Zustand "unvollstaendig" gibt es nicht.
  **Anzeige:** `highscore_flood_screen` zeigt die Liste im Layout der
  vier anderen (seitenweise ueber `highscore_browse`, dasselbe
  `HS_PAGE_ENTRIES`, zwei Zeilen je Eintrag, Rows in der
  Akzentfarbe), mit den Spalten der Marathon-Liste samt Spielzeit: das
  Wasser steigt nach der Uhr, die ueberlebte Zeit sagt also, gegen wie
  viele Flutreihen ein Eintrag angespielt hat, und trennt zwei Runden
  mit gleichen Rows.
  **Mehrspieler-Bestenliste (seit 1.1.0, siehe 5.8):** die Ergebnisse
  einer Mehrspieler-Runde liegen in einer sechsten Datei
  `${DATA_DIR}/highscore-versus`, Zeilenformat und Rangordnung wieder
  wie die Marathon-Liste (elf Felder, absteigend nach Rows, gleiche Rows
  hinter dem aelteren Eintrag), ebenfalls Top 10 (`HSV_*` in
  `lib/highscore.sh`). Damit ist die in Abschnitt 8 offen gelassene
  Frage entschieden, und zwar mit der Empfehlung, die dort stand: eine
  **eigene Liste** statt eines Eintrags in der Marathon-Liste. Garbage
  kuerzt eine Runde ab und schenkt ihr zugleich zusaetzliche Reihen zum
  Abbauen - die Zahlen haben schlicht nicht dieselbe Groesse, und genau
  dagegen wurde die Liste fuenfmal aufgeteilt. **Jede** Runde wird
  gewertet, gewonnen wie verloren (wie bei Time Attack und Hochwasser:
  es gibt keinen Zustand "unvollstaendig"). **Der erreichte Platz wird
  bewusst nicht gespeichert:** die Liste rangiert, was ein Spieler
  getan hat, und das ist ueber Abende zu zweit und zu fuenft
  vergleichbar - wer an einem bestimmten Abend gewonnen hat, nicht. Wie
  oft jemand gewonnen hat, steht dafuer in der Statistik (das
  `goal`-Feld des Modus, siehe unten).
  **Eine Liste fuer alle drei Mehrspieler-Modi** (seit 1.1.0, als der
  Gastgeber die Wahl zwischen `survival`, `sprint` und `ultra` bekam,
  siehe 5.1). Das ist die eine Stelle, an der bewusst *nicht* nach dem
  Muster der Einzelspieler-Listen aufgeteilt wird: die drei
  unterscheiden sich in der Siegbedingung, gewertet wird aber ueberall
  dieselbe Zahl in derselben Einheit - die eigenen Rows -, und drei
  Listen mit je zwei Eintraegen waeren fuer den Leser weniger wert als
  eine mit sechs. Der Modus ist Teil des Abends, wie die Zahl der
  Mitspieler, und der steht auch nicht in der Liste.
  **Anzeige:** `highscore_versus_screen` zeigt die Liste im Layout der
  fuenf anderen, mit den Spalten der Marathon-Liste samt Spielzeit: ein
  Lauf, der frueh ausgeschieden ist, ist genau der kurze, sodass die
  Zeit einen K.O. von einer durchgespielten Runde trennt.

  **Umbenennung der Marathon-Datei (seit 0.51.0, Nutzerwunsch):** die
  Marathon-Liste hiess bis 0.50.0 schlicht `highscore` - als einzige
  ohne ihren Modus im Namen, ein Rest aus der Zeit, in der sie die
  einzige Liste war. Sie heisst jetzt `${DATA_DIR}/highscore-marathon`
  und passt damit ins Schema der vier anderen. Eine vorhandene alte
  Datei wird beim naechsten Start **einmalig umbenannt**
  (`highscore_migrate_legacy` in `lib/highscore.sh`, `mv`) - eine
  bewusste Ausnahme von der Arbeitsregel "keine
  Abwaertskompatibilitaet" (Abschnitt 6, ebenfalls Nutzerwunsch):
  am Inhalt der Datei aendert sich nichts, nur an ihrem Namen, und eine
  Top Ten dafuer wegzuwerfen waere ein Verlust ohne jeden Gegenwert.
  Drei Festlegungen dazu:
  - **Aufgerufen wird vor dem Reset-Block** in `rowhammer.sh` (also vor
    `reset_run`, siehe 4.8) und damit vor allem, was eine Liste liest.
    `--reset highscore` arbeitet mit den Dateinamen, die die Module
    besitzen; eine noch unter dem alten Namen liegende Datei waere dort
    als "nicht vorhanden" gemeldet worden und haette ihren eigenen
    Reset ueberlebt. So kennt genau eine Funktion den alten Namen
    (`HS_LEGACY_FILE_NAME`), und der Rest des Spiels sieht nur den
    aktuellen.
  - **Eine schon vorhandene Zieldatei wird nie ueberschrieben.** Dann
    hat die Umbenennung bereits stattgefunden und der alte Name ist
    etwas von Hand Zurueckgelegtes; die Datei bleibt unangetastet
    liegen und meldet sich auf STDERR.
  - **Ein fehlgeschlagenes `mv` ist ein harter Fehler** (`die`): das
    Datenverzeichnis ist dann nicht beschreibbar, das Spiel koennte
    dort ohnehin keine Liste speichern, und weiterzumachen hiesse
    stillschweigend mit einer leeren Marathon-Liste zu starten.
  **Modus-Auswahl:** weil es damit mehrere Listen mit verschiedenen
  Rangordnungen
  gibt, fragt der Hauptmenuepunkt "Highscores" seit 0.38.0 zuerst nach
  dem Modus (`menu_highscores` in `lib/menu.sh`: Marathon / Ultra /
  Sprint / Time Attack / Hochwasser / Zurueck, der Sprint-Eintrag seit
  0.39.0, der Time-Attack-Eintrag seit 0.42.0, der
  Hochwasser-Eintrag seit 0.49.0) und zeigt danach die
  gewaehlte Liste; die Auswahl bleibt
  stehen, bis "Zurueck" oder `ESC` kommt, sodass ein Vergleich der
  Listen nicht durchs Hauptmenue muss. Die Bildschirmtitel nennen ihren
  Modus ("Highscores - Marathon", "- Ultra", "- Sprint", "- Time Attack"
  bzw. "- Hochwasser"), sonst
  waere
  nicht zu sehen, welche gerade auf dem Schirm steht. Eine
  gemeinsame Liste waere keine Alternative: sie muesste mehrere
  Ordnungen
  in eine Tabelle mischen (siehe 3.6).
  **Bedienung der Listen (seit 0.52.0, Nutzerwunsch):** alle fuenf
  Bildschirme sind ein Browser mit Cursor (`highscore_browse` in
  `lib/highscore.sh`), nicht mehr eine Folge von Info-Bildschirmen. Pfeil
  hoch/runter waehlt den Eintrag und blaettert dabei die Seite mit, Pfeil
  links/rechts blaettert die Seiten direkt, `ESC`/`x` geht zurueck; beide
  Richtungen laufen um wie in jeder anderen Liste des Spiels. **Enter
  spielt die Demo-Aufzeichnung des ausgewaehlten Eintrags ab** (siehe
  3.8). Entscheidungen dahinter:
  - **Der Cursor ist ein `>` vor der ersten Zeile des Eintrags**, nicht
    die Invertierung, mit der `menu_run` seine Eintraege markiert: eine
    Eintragszeile besteht aus SGR-Sequenzen, die auf einen Reset enden,
    und der wuerde eine invertierte Strecke mittendrin abschneiden. Die
    zweite Zeile laesst die Cursor-Spalte leer - ein zweites `>` laese
    sich wie eine zweite Auswahl.
  - **Blaettern setzt den Cursor auf den ersten Eintrag der Seite**,
    damit die Auswahl immer sichtbar ist.
  - **Ob es zu einem Eintrag eine Aufnahme gibt, beantwortet der
    Runden-Hash**: er steht als letztes Feld im Eintrag und im
    Dateinamen der Aufnahme (siehe 3.8 und 4.10). `demo_hash_map`
    (`lib/demo.sh`) baut daraus die Umkehrung von `highscore_hash_set` -
    Hash auf Dateipfad - und kostet dafuer ein Glob und keinen einzigen
    Dateizugriff. Gebaut wird sie bei jedem Oeffnen eines Listen-
    Bildschirms neu: eine zwischendurch gespielte Runde oder eine
    geloeschte Aufnahme aendert genau dieses Ergebnis.
  - **Markiert sind solche Eintraege mit `*`**, samt Legende unter der
    Tabelle; die Legende erscheint nur, wenn die Liste ueberhaupt eine
    Markierung traegt. Ein Eintrag ohne Aufnahme sagt auf Enter, dass es
    keine gibt, statt nichts zu tun - die Markierung sagt nur, welche
    Eintraege eine haben, nicht warum die anderen keine haben.
  - **Waehrend eine Runde pausiert im Hauptmenue wartet, ist die
    Wiedergabe gesperrt** - dieselbe Regel und dieselbe Meldung wie im
    Demo-Menue (siehe 3.8): eine Wiedergabe laeuft durch genau den
    Rundenzustand, in dem diese Runde parkt.
  **Platz-Vorschau (seit 0.50.0):** `highscore_rank_preview MODUS WERT`
  sagt in `HS_PREVIEW_RANK`/`HS_PREVIEW_MAX`, welchen Platz eine Runde
  in der Liste ihres Modus einnehmen wuerde, ohne sie einzutragen (0 =
  verfehlt). Sie bedient alle fuenf Listen - sie unterscheiden sich nur
  im befragten Array und darin, ob der kleinere Wert der bessere ist
  (Ultra) - und wendet die Einfuegeregel der `*_add`-Funktionen an: ein
  Platz hinter der Zahl der mindestens gleich guten Eintraege, und kein
  Platz, wenn das ueber `*_MAX` hinausgeht. Gebraucht wird sie von der
  Namensabfrage am Rundenende (siehe 3.7), die vor dem Eintrag laeuft
  und den Rang der `*_add`-Funktionen deshalb noch nicht kennt - seit
  1.0.1 entscheidet sie dort zusaetzlich, ob ueberhaupt gefragt wird.
  Lines und Level bleiben gespeichert, werden aber nicht angezeigt;
  die Score-Spalte wurde in 0.15.0 auf Nutzerwunsch aus
  der Anzeige und in 0.16.0 auch aus dem Dateiformat entfernt.
  Bis 0.26.0 war ein Eintrag eine Zeile, und weil das Layout (mit dem
  Zwei-Zeichen-Menue-Einzug) exakt ins 48-Spalten-Minimum passte,
  zahlte jede neue Spalte eine vorhandene: der Name schrumpfte mit der
  Zeit-Spalte (0.17.0) von 13 auf 8 Zeichen und mit der RH-Spalte
  (0.25.0) auf 6. Fuer PCS und PPM war kein Platz mehr uebrig; der
  Zeilenumbruch gibt dem Namen dafuer 12 Zeichen zurueck (gespeichert
  bleiben weiterhin bis zu 16). Die Liste ist damit zu hoch fuer einen
  22-Zeilen-Bildschirm und wird seitenweise gezeigt - fuenf Eintraege je
  Seite (`HS_PAGE_ENTRIES`), Tabellenkopf auf jeder Seite wiederholt,
  Seitenzaehler im Titel.
  **Farbige Darstellung (seit 0.30.0):** die Tabelle nutzt seither
  dieselbe Theme-Infrastruktur wie das Spielfeld (`COLOR_THEME`,
  `COLOR_MODE`, siehe 4.1): `render_colors_init` (`lib/render.sh`)
  leitet daraus reine Text-SGR-Farben ab (`TXT_GOLD_SGR`,
  `TXT_SILVER_SGR`, `TXT_ACCENT_SGR` = Farbe des I-Steins,
  `TXT_WARN_SGR` = Farbe des Z-Steins, `TXT_BOLD_SGR`, `TXT_RESET_SGR`).
  Rang 1 und 2 erscheinen in Gold-/Silber-Farbe (Medaillen-Optik), die
  Rows-Spalte und die uebrigen Raenge in der Akzentfarbe, die
  Gold-/Silber-/Rowhammer-Werte in der jeweiligen Themenfarbe.
  `TXT_WARN_SGR` greift bewusst auf die Z-Stein-Farbe statt auf ein
  festes Rot zurueck, damit das `colorblind`-Schema (das Rot/Gruen
  meidet) auch hier stimmig bleibt. In `--no-color`/`NO_COLOR` sind alle
  `TXT_*`-Variablen leer, die Anzeige ist dann byteidentisch zur
  unkolorierten Fassung. Eine Zeile, die trotz der 46-Zeichen-Grenze zu
  lang wird (`HS_FIELD_NUM_RE` begrenzt die Ziffernzahl nicht, eine von
  Hand editierte Datei koennte also ueberlaufen), verzichtet auf Farbe
  und faellt auf den bisherigen, hart abgeschnittenen Klartext zurueck -
  sonst koennte eine Escape-Sequenz mitten durchgeschnitten werden.
- `lib/save.sh` (seit 0.8.0): der Gesamt-Reihenzaehler in
  `${DATA_DIR}/save`, eine validierte Zeile `total_rows=N` (geparst,
  nicht gesourct; eine defekte Datei faellt mit Meldung auf 0 zurueck).
  Nur der Zaehler wird gespeichert; aktuelles Wunder und Baustufe
  werden daraus deterministisch abgeleitet (`lib/wonders.sh`), damit
  Spielstand und Wunder-Tabellen nie auseinanderlaufen koennen.
- `lib/stats.sh` (seit 0.10.0): persistente Gesamt-Statistik in
  `${DATA_DIR}/stats` als validierte `key=value`-Zeilen (geparst,
  nicht gesourct; defekte Zeilen fallen auf 0 zurueck): abgebaute
  Reihen (`lines`), Bonusreihen (`bonus_rows`, der Gold-/Silber-/
  Tetris-Anteil der Reihenwertung, also Rows minus Lines) sowie
  gebaute Gold- (`gold_squares`) und Silberquadrate
  (`silver_squares`). Seit 0.24.0 zusaetzlich die "rowhammer" der
  Namensgebung: `rowhammers` zaehlt, wie oft vier Reihen auf einmal
  abgebaut wurden (hochgezaehlt in `clear_lines` an der Stelle, die
  den Tetris-Bonus vergibt; Rundenzaehler `ROWHAMMER_COUNT` in
  `rowhammer.sh`). Seit 0.27.0 zusaetzlich die abgelegten Teile
  (`pieces`, Rundenzaehler `PIECE_COUNT`, hochgezaehlt in
  `lock_and_next`) und die gespielte Zeit (`play_time`, Sekunden) -
  beide zusammen ergeben die Ablegerate in Teilen je Minute.
  Seit 0.11.0 zusaetzlich die Ergebnisse der
  letzten drei Runden (`recent=`-Zeilen, neueste zuerst; seit 0.27.0
  im Format `lines|bonus|gold|silver|rowhammers|pieces|time|date` mit dem Spieldatum
  als `YYYY-MM-DD` - das fruehere fuehrende `score`-Feld entfiel mit
  dem Punktesystem-Umbau, die Punkte einer Runde sind Lines + Bonus
  und werden bei der Anzeige abgeleitet statt gespeichert; alte
  Zeilen im falschen Format werden gemaess der
  Arbeitsregel "keine Abwaertskompatibilitaet" beim Laden verworfen).
  Eine Runde wird
  beim Rundenende genau einmal
  verbucht (gemeinsam mit Highscore und Savegame in
  `record_round`); seit 0.27.0 auch eine Runde ganz ohne Reihenabbau,
  weil sie Teile und Spielzeit beisteuert (frueher fiel sie durch die
  Null-Pruefung).
  **Statistik je Spielmodus (Runden seit 0.42.0, alle Zaehler seit
  0.47.0 auf Nutzerwunsch):** jeder Zaehler oben existiert ein zweites
  Mal je Modus, als Zeile `mode_<modus>_<feld>=N` mit `<modus>` aus
  `marathon|ultra|sprint|timeattack|flood|versus` und `<feld>` aus
  `rounds|goal|lines|bonus_rows|gold_squares|silver_squares|rowhammers|`
  `pieces|play_time` (`STATS_MODE_RE`, im Code das assoziative Array
  `STATS_MODE` mit dem Schluessel `<modus>_<feld>`). `rounds` zaehlt die
  verbuchten Runden des Modus, `goal` die davon, die im regulaeren Ende
  des Modus ausgingen statt im Game Over (Ziel erreicht / volle Zeit
  gespielt / Uhr abgelaufen / die Mehrspieler-Runde gewonnen) -
  Marathon und Hochwasser haben kein Ziel und deshalb kein `goal`-Feld
  in der Datei; beim Mehrspieler ist es die Siegquote, also genau die
  Zahl, die die Bestenliste bewusst nicht traegt (siehe 4.5); welche Modi das sind, sagt
  `stats_mode_has_goal` (`lib/stats.sh`), damit der Dateiinhalt nicht
  daran haengt, ob eine Sprachdatei die passende Beschriftung kennt. `record_round` reicht dafuer `GAME_MODE` und
  `GOAL_REACHED` an `stats_add_round` durch - die einzigen beiden
  Rundenangaben, die sich aus den uebrigen Zaehlern nicht
  rekonstruieren lassen, und die Erfolgsquote der Zeitmodi steht
  nirgends sonst (ein gescheiterter Lauf fehlt in seiner Bestenliste).
  Ein flacher Schluessel je Feld statt einer Zeile je Modus mit
  gepackten Feldern: ein fehlender Zaehler faellt so einzeln auf 0
  zurueck, statt alles zu entwerten, was dieselbe Zeile traegt. Die
  Schluessel loesen die `rounds_<modus>[_goal]`-Schluessel aus 0.42.0 ab
  (Arbeitsregel "keine Abwaertskompatibilitaet": eine bestehende Datei
  verliert ihre Runden je Modus und behaelt alles andere).
  Gezaehlt wird hinter derselben Null-Pruefung wie alles andere: eine
  Runde ohne einen einzigen abgelegten Stein ist keine gespielte Runde,
  und sie hier zu zaehlen, waehrend sie in jedem anderen Zaehler fehlt,
  wuerde die beiden nur widerspruechlich machen. Ein unbekannter
  Modusname (nur aus einem kuenftigen Modus ohne Eintrag in
  `STATS_MODES` erreichbar) wird je Modus nirgends gezaehlt statt
  Marathon zugeschlagen - lieber eine Luecke als eine falsche
  Zuordnung.
  **Die Gesamtzaehler bleiben eigene Zaehler** und werden nicht aus den
  Modus-Zaehlern summiert (Nutzervorgabe: die Gesamtstatistik soll
  erhalten bleiben). Sichtbar wird der Unterschied nur im eben genannten
  Fall - die Runde eines unbekannten Modus steht in den Gesamtzahlen und
  sonst nirgends -, und genau deshalb bleibt die Gesamtsicht die
  vollstaendige.
  Anzeige ueber den Hauptmenuepunkt
  "Statistik", der seit 0.47.0 wie "Highscores" zuerst nach der Sicht
  fragt (`menu_stats` in `lib/menu.sh`: Gesamt / Marathon / Ultra /
  Sprint / Time Attack / Hochwasser / Zurueck, wortgleich mit dem
  Einzelspieler- und
  dem Highscore-Menue, und in einer Schleife, sodass ein Vergleich nicht
  durchs Hauptmenue muss). Weitere Bildschirme an die vorhandenen
  anzuhaengen war die Alternative und haette bedeutet, sich durch acht
  Bildschirme zu druecken, um den letzten zu sehen.
  **Gesamt** (`stats_screen`) steht seit 0.27.0 auf **zwei** und seit
  0.42.0 auf **drei Bildschirmen**: erst die
  Gesamtzaehler (inklusive der gewichteten Gesamtsumme Lines + Bonus,
  des Rowhammer-Zaehlers, der abgelegten Teile, der Gesamtspielzeit als
  H:MM:SS und der daraus berechneten Steine/Minute), dann die letzten
  drei Spiele mit je drei Zeilen (Datum, Rows, Reihen, Bonus / Gold,
  Silb, RH, PCS, PPM / Reihen-Bonus-Verhaeltnis, seit 0.55.0), zuletzt
  die Runden je Modus (die Erfolgszahl der
  Zeitmodi jeweils eingerueckt unter der Rundenzahl, weil sie ein
  Anteil davon ist, dazu die Gesamtzahl). Der dritte Bildschirm ist ein
  eigener, weil der erste mit zehn Zeilen Zaehlern voll ist. Die ersten
  beiden zusammen passen nicht mehr in die 18
  Zeilen, die ein 22-Zeilen-Terminal einem Info-Bildschirm laesst
  (`MENU_BODY_MAX` in `lib/menu.sh`; bis 0.27.0 waren es 17 - die
  zentrierten Bildschirme aus 0.28.0 brauchen keine Zeile mehr fuers
  Freiraeumen der obersten Bildschirmzeile) - deshalb der Schnitt statt
  gestrichener Spalten. Jede Zeile bleibt in den 46 Zeichen, die der
  Zwei-Zeichen-Einzug vom 48-Spalten-Minimum uebriglaesst. Der dritte
  Bildschirm ist seit 0.47.0 zugleich der Ueberblick vor der Auswahl -
  der eine Bildschirm, der alle Modi nebeneinander stellt.
  **Ein Modus** (`stats_mode_screen`, seit 0.47.0) steht dagegen auf
  **einem** Bildschirm: dieselben Zaehler in derselben Reihenfolge, mit
  denselben Beschriftungen und derselben Faerbung wie der
  Gesamtbildschirm (er soll sich lesen wie dieser, nur fuer eine
  kleinere Menge Runden), dazu die Runden des Modus und - bei den
  Zeitmodi - die Zahl der erfolgreichen Laeufe. Zwei Zahlen kommen
  hinzu, beide **abgeleitet statt gespeichert** (wie schon die
  gewichtete Gesamtsumme und die PCS/min): **Rows je Runde**, die Zahl,
  die zwei Modi ueberhaupt vergleichbar macht, und bei den Zeitmodi die
  **Erfolgsquote** in Prozent; ohne eine einzige Runde des Modus steht
  in beiden ein "-" statt einer Division durch 0. Mit 17 Zeilen im
  laengsten Fall (Zeitmodus, seit 0.55.0 eine mehr) bleibt der
  Bildschirm in `MENU_BODY_MAX`.
  **Verhaeltnis Reihen/Bonus (seit 0.55.0, Nutzerwunsch):** jeder
  Statistik-Bildschirm nennt seither, wie die beiden Zaehler "Abgebaute
  Reihen" und "Bonusreihen" zueinander stehen - der Gesamtbildschirm,
  jede der drei letzten Runden und jeder Modus-Bildschirm. Beide Zahlen
  standen laengst nebeneinander; wie viel der Reihenwertung aus den
  Gold-/Silber-Quadraten kam und wie viel aus den Reihen selbst, musste
  man sich dazu im Kopf teilen. `stats_ratio` (`lib/stats.sh`)
  formatiert es als "1:X.XX" - eine abgebaute Reihe war so viele
  Bonusreihen wert. Vier Festlegungen:
  - **Die Form "1:X.XX" statt Prozent oder blossem Quotienten**, weil
    genau das die beiden Zahlen sind: eine Reihe des Feldes und der
    Bonus, den sie getragen hat. Zwei Nachkommastellen, weil die
    interessanten Unterschiede zweier Spielweisen in der zweiten
    stehen. Ohne eine einzige abgebaute Reihe steht "-" - der einzige
    Division-durch-0-Fall, und zugleich der einzige, in dem die Zahl
    ohnehin nichts sagen wuerde (ohne Reihe kein Bonus).
  - **Der Platz ist zwischen "Bonusreihen" und der gewichteten
    Gesamtsumme.** Das Verhaeltnis setzt die beiden rohen Zaehler
    zueinander, waehrend Gesamtsumme und Rows je Runde aus ihnen
    abgeleitet sind. Bewusst ohne Faerbung: die Akzentfarbe gehoert auf
    diesen Bildschirmen der Gesamtsumme, der Zahl, die die Wunder baut.
  - **Bei den letzten Spielen kostet es eine dritte Zeile je Runde.**
    Die beiden vorhandenen sind mit 44 der 46 Zeichen voll, und eine
    ihrer Spalten fuer eine ableitbare Zahl herzugeben waere der
    falsche Tausch gewesen - eine gespeicherte gegen eine gerechnete.
    Drei Zeilen je Runde passen: der Bildschirm landet bei 14 der 18
    Zeilen aus `MENU_BODY_MAX`.
  - **Ein absurdes Verhaeltnis wird gekappt** ("1:>9999"): in einer
    gespielten Runde bleibt der ganzzahlige Teil unter 21 (ein Tetris
    durch zwei Gold-Quadrate sind 4 Reihen und 81 Bonusreihen), alles
    darueber kann nur aus einer von Hand bearbeiteten Datei kommen und
    wuerde bloss die Zeilenbreite sprengen.
  **Farbige Darstellung (seit 0.30.0):** wie die Highscore-Liste nutzt
  auch dieser Bildschirm die `TXT_*`-SGR-Farben aus `lib/render.sh`
  (siehe dort): die gewichtete Gesamtsumme in der Akzentfarbe, Gold-
  und Silberbloecke in Gold-/Silberfarbe, der Rowhammer-Zaehler in der
  Warnfarbe (Z-Stein-Farbe des aktiven Themas), und auf dem zweiten
  Bildschirm dieselbe Faerbung fuer Rows sowie Gold/Silb/RH je Runde.
  Dieselbe 46-Zeichen-Rueckfallregel gilt hier ebenfalls.

### 4.6 Debug-Modus (umgesetzt, Version 0.6.0)

Zweck: Ein Problem oder eine Frage zum Spielverlauf soll anhand von
Log-Dateien nachvollziehbar sein, ohne die Situation live reproduzieren
zu muessen (z. B. fuer Bug-Reports an Claude Code).

- Aktivierung: `--debug` bzw. `ROWHAMMER_DEBUG=1`; Zielverzeichnis
  `--debug-dir DIR` bzw. `ROWHAMMER_DEBUG_DIR` (Standard:
  `${XDG_STATE_HOME:-~/.local/state}/rowhammer/debug/<Zeitstempel>.<PID>`,
  ein Verzeichnis pro Lauf; der Pfad wird beim Beenden ausgegeben).
- Drei korrelierte Log-Dateien (`lib/debug.sh`); jede Zeile traegt die
  Millisekunden seit Sessionstart und den Bildschirm-Update-Zaehler
  ("f N" = nach Update N, vor N+1):
  - `frames.log`: jede Terminal-Ausgabe 1:1 (Byte fuer Byte, inklusive
    ANSI-Sequenzen). Moeglich durch den zentralen Ausgabe-Trichter
    `screen_write` in `lib/render.sh`, durch den seit 0.6.0 alle Module
    (Spiel, Menues, Prompts, Terminal-Setup) schreiben. Seit dem
    inkrementellen Rendering (0.22.0) enthaelt eine Spiel-Ausgabe nur
    noch die geaenderten Zeilen samt ihrer Cursor-Positionierung, nicht
    mehr den ganzen Bildschirm - die Datei bleibt damit die exakte
    Kopie dessen, was ans Terminal ging, wird aber deutlich kleiner.
    Wie viel eine Ausgabe umfasst, haengt seit 0.41.0 vom Render-Modus
    ab (siehe 4.3); der Sitzungskopf in `events.log` nennt ihn deshalb
    (`# render:`), sonst waere das Frame-Log nicht richtig zu lesen.
    Wer ganze Frames sehen will, laesst die Sitzung mit
    `--render-mode full` laufen.
  - `input.log`: jeder Tastendruck mit Rohbytes (`printf %q`-quotiert)
    und gemapptem Symbol; auch nicht zuordenbare Escape-Sequenzen.
  - `events.log`: Session-Header (Version, Bash, Terminal, Seed,
    Spieler, Tastenbelegung, geladene Config-Dateien) und alle
    Aktionen: Spawns samt Queue, Bewegungen/Rotationen (inklusive
    blockierter Versuche), Gravitations-Fall, Locks, Quadrat-Bildung
    mit Instanz-IDs, Reihenabbau mit Credit-Aufschluesselung je Reihe,
    Hold, Pause, Bag-Refills, Menuewahl, Config-Speicherungen, fatale
    Fehler sowie ein Board-Snapshot (Typ- und Quadrat-Gitter plus
    cut/squared-Instanzlisten) nach jedem Lock. Seit 0.46.0 auch Beginn,
    Ablage und Wiedergabe von Demos (siehe 3.8/4.10) - eine abgespielte
    Demo erzeugt dabei dieselben Spielereignisse wie die Runde, die sie
    aufgezeichnet hat, was sie zum Vergleichen zweier Laeufe brauchbar
    macht.
- Ohne `--debug` sind alle Logging-Helfer No-Ops (ein Guard am
  Funktionsanfang); der Spiel-Loop bleibt frei von Zusatzkosten.
- Die Logs koennen in langen Sessions mehrere MB gross werden; es gibt
  bewusst keine Rotation (ein Verzeichnis je Lauf, manuell loeschbar).

### 4.7 Paketierung

- **Debian (umgesetzt):** klassische debhelper-Paketierung im `debian/`-
  Verzeichnis, natives Quellformat "3.0 (native)"; die Paketversion in
  `debian/changelog` folgt der Skriptversion von `rowhammer.sh`.
  Installations-Layout: Spiel, Module und `assets/` nach
  `/usr/share/rowhammer/`,
  Starter als relativer Symlink `/usr/games/rowhammer` (Debian-Policy:
  Spiele nach `/usr/games`). `rowhammer.sh` loest deshalb beim Bestimmen
  von `SCRIPT_DIR` Symlinks per `readlink -f` auf. Die Installationslogik
  liegt zentral im `Makefile` (`make install`, `DESTDIR`/`PREFIX`),
  `debian/rules` ruft es mit `PREFIX=/usr` auf. Bequemer Build ueber
  `./build-deb.sh` (Artefakte in `dist/`, per `.gitignore`
  ausgeschlossen); Build-Abhaengigkeiten: `dpkg-dev`, `debhelper`.
- **RPM (umgesetzt, Version 0.37.0):** Spec-Datei `rowhammer.spec` im
  Wurzelverzeichnis (dort erwartet sie das RPM-Oekosystem, anders als das
  `debian/`-Verzeichnis). Sie enthaelt bewusst **keine eigene
  Installationslogik**, sondern ruft im `%install`-Abschnitt dasselbe
  `make install DESTDIR=... PREFIX=/usr` auf wie `debian/rules`; beide
  Pakete liefern damit identische Pfade (`/usr/share/rowhammer`, Starter
  `/usr/games/rowhammer`), und ein Layout-Wechsel ist nur im `Makefile`
  nachzuziehen. Das `%make_install`-Makro wird absichtlich nicht genutzt,
  weil es nicht auf jedem Build-Host definiert ist. Paket-Eigenschaften:
  `BuildArch: noarch`, `Requires: bash >= 4.0`, `Recommends: ncurses`
  (`tput` ist optional, siehe 4.1). `/usr/games` ist als Verzeichnis
  mitverpackt, weil es auf RPM-Distributionen nicht ueberall vom
  `filesystem`-Paket kommt (Mitbesitz ist bei RPM zulaessig); die
  Ablage von Spielen in `/usr/games` statt `%{_bindir}` weicht von der
  Fedora-Gepflogenheit ab und ist die bewusste Entscheidung fuer
  Gleichlauf mit dem Debian-Paket.
- Build ueber `./build-rpm.sh` (Script-Konventionen wie `build-deb.sh`):
  packt das Quell-Tarball aus dem Arbeitsbaum (nicht aus dem letzten
  Commit, analog zu `dpkg-buildpackage`), laesst `rpmbuild` in einem
  privaten `_topdir` unterhalb des Ausgabeverzeichnisses laufen - das
  `~/rpmbuild` des Aufrufers bleibt unberuehrt - und sammelt die Pakete
  in `dist/`. Optionen: `--output-dir`, `--release N` (erneuter Bau
  derselben Version, im Spec als `%{rowhammer_release}` verankert),
  `--srpm` (zusaetzlich das Quellpaket), `--keep-build`, `--verbose`,
  `--silent`, je mit `ROWHAMMER_RPM_*`-Umgebungsvariable.
  Build-Abhaengigkeiten: `rpm-build`, `make`, `tar` (GNU-`tar` wegen
  `--transform`). Zwei bewusste Entscheidungen: (1) Das Skript prueft
  die `Version` des Specs gegen `ROWHAMMER_VERSION` in `rowhammer.sh`
  und bricht bei Abweichung ab, statt ein falsch beschriftetes Paket zu
  bauen (das Spec ist die Versionsquelle des RPMs, so wie
  `debian/changelog` die des Debian-Pakets). (2) `rpmbuild` laeuft mit
  `--nodeps`, weil die `BuildRequires` gegen die RPM-Datenbank des Hosts
  aufgeloest werden - auf einem Debian-Entwicklungsrechner ist die leer,
  obwohl `make` und `tar` da sind. Das Skript prueft dieselben Werkzeuge
  vorher selbst per `command -v`; der `BuildRequires`-Eintrag bleibt im
  Spec, wo ihn `mock`/COPR und ein direkter `rpmbuild`-Lauf auf einer
  RPM-Distribution regulaer durchsetzen.
- Beide Build-Skripte geben ihre Statusmeldungen seit 0.40.0 nicht nur
  bei erkanntem Terminal aus, sondern auch, wenn die Umgebungsvariable
  `CI` gesetzt ist. Ein CI-Runner hat weder ein Terminal noch ein
  Journal, in das jemand schaut; vorher scheiterten beide Skripte dort
  vollstaendig lautlos, Fehlermeldungen inklusive.
- Gebaut werden beide Pakete zusaetzlich automatisch auf GitHub - bei
  jedem Push zur Kontrolle, bei einem Release-Tag als Release-Asset
  (siehe 4.9).
- Hinweis: Das Repository hat noch keine Lizenzdatei;
  `debian/copyright` ist entsprechend als "UNLICENSED" markiert
  (im Spec `License: LicenseRef-UNLICENSED`) und beides muss
  nachgezogen werden, sobald eine Lizenz festgelegt ist. Aus demselben
  Grund werden die Pakete unsigniert gebaut (siehe 4.9).

### 4.8 Reset persistenter Daten (seit 0.35.0)

`--reset TARGET` (`ROWHAMMER_RESET`) setzt gezielt persistente Dateien
im Datenverzeichnis (siehe 4.5) zurueck und beendet das Programm, statt
ins Menue zu starten. Ziele:

| TARGET | betroffene Dateien |
| --- | --- |
| `config` | `rowhammer.conf` |
| `stats` | `stats` |
| `highscore` | `highscore-marathon`, `highscore-ultra`, `highscore-sprint`, `highscore-timeattack`, `highscore-flood` **und** `highscore-versus` |
| `save` | `save` (Weltwunder-Fortschritt) |
| `demo` | das Verzeichnis `demos` (alle Aufzeichnungen) |
| `all` | alle neun Dateien und das Verzeichnis `demos` |

**Reset heisst verschieben, nicht loeschen (seit 0.36.0,
Nutzerentscheidung).** Jede betroffene Datei wandert nach
`<datei>-YYYYMMDDhhmmss.bak` im selben Verzeichnis; ein versehentliches
`--reset all` kostet damit keine Daten mehr, das Zurueckholen ist ein
`mv`. Der Zeitstempel gilt fuer den ganzen Lauf, sodass die Backups
eines `all` sichtbar zusammengehoeren. Existiert eine Backup-Datei
dieser Sekunde bereits, lief derselbe Reset gerade eben schon einmal:
`reset_run` wartet dann mit `sleep 1` auf die naechste Sekunde und
nimmt einen frischen Zeitstempel, statt das eben geschriebene Backup zu
ueberschreiben (`RESET_STAMP_ATTEMPTS`, 3 Versuche; danach Abbruch mit
Meldung - eine stehende oder zurueckspringende Uhr soll keine
Endlosschleife ergeben). Verschoben wird mit einfachem `mv` ohne `-f`,
weil ein vorhandenes Backup nie ueberschrieben werden darf. Die
`.bak`-Dateien bleiben liegen; das Spiel liest sie nie (kein Dateiname
passt auf die Konstanten aus 4.5), aufgeraeumt werden sie von Hand.

Entscheidungen zu den beiden in der Roadmap offen gelassenen Punkten:

- **`all` loescht auch das Savegame.** "Alles" heisst alles; wer nur den
  Weltwunder-Fortschritt zuruecksetzen will, hat dafuer das eigene Ziel
  `save` (der in der Roadmap angedachte Wert), das die uebrigen Dateien
  unangetastet laesst.
- **`highscore` trifft alle Bestenlisten.** Endlos-, Ultra-, Sprint-,
  Time-Attack-, Hochwasser- und Mehrspieler-Liste (seit 0.34.0, 0.39.0,
  0.42.0, 0.49.0 bzw. 1.1.0, siehe 4.5)
  sind dieselbe Art
  Daten; eine davon stehen zu
  lassen waere ueberraschend, und ein eigenes Ziel je Liste waere fuer
  einen Reset zu fein.
- **`demo` ist das einzige Ziel, das ein Verzeichnis bewegt** (seit
  0.46.0). Verschoben wird `demos` als Ganzes - dieselbe `mv`-Schleife
  wie fuer die Dateien, die den Unterschied nicht kennen muss -, sodass
  die Aufnahmen eines Resets zusammen in einem `.bak`-Verzeichnis
  liegen und sich in einem Zug zurueckholen lassen. Ein eigenes Ziel
  hat es, weil es die mit Abstand groessten Daten sind und am ehesten
  allein geleert wird.

Ablauf und Einordnung:

- **Kein Config-Wert.** Praezedenz Standard < Env < CLI wie beim
  Datenverzeichnis und den Debug-Schaltern. Die Config-Datei ist eines
  der Reset-Ziele - wuerde der Reset von dort gelesen, koennte sich eine
  Datei bei jedem Start selbst loeschen lassen.
- **Zeitpunkt:** direkt nach dem Sourcen der Module (die Dateinamen
  kommen aus den Modulen, die sie besitzen: `CONFIG_NAME`,
  `STATS_FILE_NAME`,
  `HS_FILE_NAME`/`HSU_FILE_NAME`/`HSS_FILE_NAME`/`HSA_FILE_NAME`/
  `HSF_FILE_NAME`/`HSV_FILE_NAME`, `SAVE_FILE_NAME`, `DEMO_DIR_NAME`)
  und **vor** der TTY-Pruefung. Die TTY-Pruefung ist dafuer aus dem
  Prerequisites-Block nach unten gewandert: ein Reset loescht nur
  Dateien und darf deshalb auch aus einem Skript oder einer CI-Umgebung
  ohne Terminal laufen. Das Terminal wird nie angefasst (kein
  Alternate-Screen, kein Rohmodus). Unmittelbar davor laeuft seit
  0.51.0 die einmalige Umbenennung `highscore` ->
  `highscore-marathon` (`highscore_migrate_legacy`, siehe 4.5), damit
  `--reset highscore` die Datei unter ihrem aktuellen Namen antrifft.
- **Sicherheitsabfrage:** an einem Terminal listet `reset_run` erst die
  betroffenen Pfade und fragt dann `Bist du sicher, dass du <ziel>
  zuruecksetzen moechtest? [N/y]`; wie bei `menu_confirm` ist "nein" die
  Vorgabe - deshalb steht das `N` vorn und gross, und leere Antwort, EOF
  oder alles ausser `y`/`yes` bricht ab. Nach dem Verschieben meldet der
  Reset `Reset erfolgreich`, darunter die Bilanz (gesicherte und nicht
  vorhandene Dateien). **Sprache (seit 0.36.1 deutsch, seit 0.48.0
  uebersetzt):** der Reset-Dialog ist ein Nutzerdialog wie die Menues
  und laeuft deshalb in der gewaehlten Sprache (Texte `reset_*` in der
  Tabelle, siehe 4.11) - `--help` ebenso. Nur die Fehlermeldungen nach
  STDERR bleiben englisch (Konvention, Abschnitt 6). Die annehmenden
  Antworten sind in jeder Sprache `y`/`yes`: die Abfrage schreibt sie
  als "[N/y]" aus, und ein Skript, das mit "y" antwortet, darf nicht
  von der Sprache der Sitzung abhaengen.
  Ohne TTY entfaellt die Abfrage, weil ein wartendes `read` den Aufrufer
  haengen liesse. Die Abfrage ist bewusst ein einfaches `read` statt
  `menu_confirm`: letzteres braucht Alternate-Screen, Rohmodus und
  `render_menu_frame`, also genau das, was der Reset nicht aufbaut.
- **`--force` (`ROWHAMMER_FORCE`, seit 0.36.0)** beantwortet die Abfrage
  vorab mit "ja". Der Schalter ist bewusst allgemein gehalten und nicht
  `--reset-force`: er laesst sich mit jeder anderen Option kombinieren
  und ist ueberall wirkungslos, wo nichts gefragt wird (das Spiel
  startet mit `--force` also ganz normal). Wie das Reset-Ziel steht er
  nicht in der Config - ein gespeichertes "frag mich nie wieder" wuerde
  das Sicherheitsnetz aushebeln -, Praezedenz also Standard < Env < CLI.
- Nicht vorhandene Dateien sind kein Fehler (Ziel bereits erreicht) und
  werden nur gemeldet; eine vorhandene Datei, die sich nicht verschieben
  laesst, bricht mit Fehlermeldung ab.

### 4.9 Release-Struktur und CI (seit 0.40.0)

Der ausfuehrliche Ablauf steht in `docs/release-process.md`; hier die
Struktur und die Entscheidungen dahinter.

**Ein Release ist ein Tag.** Der Tag heisst `v<version>` (`v0.40.0`),
und mehr als sein Push braucht ein Release nicht: der Release-Workflow
baut daraufhin die Pakete und legt das GitHub-Release samt Assets an.
**Vorab-Versionen (`v0.40.0-rc1`) sind bewusst ausgeschlossen** -
rowhammer ist ein *natives* Debian-Paket, und eine native Paketversion
darf keinen Bindestrich enthalten; ein RC-Tag liesse sich also gar nicht
als `.deb` bauen und wird deshalb sofort abgewiesen statt spaet in
`dpkg-buildpackage`. Die `0.x`-Reihe ist ohnehin die Vorab-Phase des
Projekts.

**`tools/release.sh`** (Script-Konventionen, `ROWHAMMER_RELEASE_*`) ist
das einzige Stueck Code, das alle vier Stellen mit der Version kennt:
`ROWHAMMER_VERSION` in `rowhammer.sh` (Referenz - was das Spiel ueber
sich selbst sagt), die oberste Strophe von `debian/changelog`, die
`Version` samt `%changelog` in `rowhammer.spec` und - seit 1.0.3,
Nutzerwunsch - die Zeile `**Version:** X.Y.Z` unter der Ueberschrift der
README. Vier Modi
(`--mode check|version|notes|tag`):

- `check` vergleicht die vier Nummern **und** prueft, ob beide
  Changelogs die Version wirklich dokumentieren - eine Version ohne
  Changelog-Eintrag ergaebe ein Release ohne Release-Notes.
  `--expect VERSION` prueft zusaetzlich gegen einen Wert von aussen (im
  Workflow: den Namen des gepushten Tags).
- `notes` baut die Release-Notes, `tag` legt das annotierte Tag mit
  diesen Notes als Nachricht an (nach `check`, bei sauberem Arbeitsbaum,
  niemals ein vorhandenes Tag verschiebend) und pusht es mit `--push`.

**Die Versionszeile in der README (seit 1.0.3, Nutzerwunsch).** Sie
steht als eigene Zeile `**Version:** X.Y.Z` direkt unter der
Ueberschrift und wird von `check` mitgeprueft. Drei Festlegungen dazu:

- **Sie ist eine Anzeige, keine Quelle.** Die Referenz bleibt
  `ROWHAMMER_VERSION`; die Version dorthin zu verlagern, wo sie zuerst
  gelesen wird, ginge nicht: `dpkg-buildpackage` und `rpmbuild` lesen
  ihre Version ausschliesslich aus `debian/changelog` bzw. dem Spec, und
  das Spiel selbst kaeme an die README zur Laufzeit gar nicht heran -
  `make install` legt Skript und Module nach `/usr/share/rowhammer`, die
  README dagegen als Doku nach `/usr/share/doc/rowhammer` (`%doc` bzw.
  `debian/docs`), von wo `rpm --excludedocs` sie ganz entfernen darf.
- **Geprueft statt gepflegt.** Genau deshalb steht sie in `check`: eine
  von Hand gepflegte Nummer in einer Doku-Datei ist die erste, die
  veraltet, und ein Besucher glaubt ihr. Der CI-Lauf laesst sie nicht
  mehr veralten, und das Hochzaehlen kostet eine Zeile mehr (Schritt 2
  in `docs/release-process.md`).
- **Eine eigene Zeile mit festem Praefix**, keine Zahl in einem Satz:
  nur so laesst sie sich mit einem `sed`-Muster lesen, ohne dass ein
  umformulierter Absatz die Pruefung reisst. Fehlt die Zeile, meldet
  `check` sie als `<none>` und schlaegt fehl - dasselbe wie eine falsche
  Nummer, denn beides heisst, dass die README ihre Version nicht sagt.

**Die Release-Notes sind die Changelog-Strophe** zur Version, nicht ein
eigener Text. Die Strophe muss fuers Debian-Paket ohnehin geschrieben
werden; ein zweiter, davon unabhaengiger Release-Text wuerde frueher
oder spaeter etwas anderes erzaehlen als das Paket, das danebenliegt.
Der angehaengte Installationsabschnitt nennt bewusst keine festen
RPM-Dateinamen (dort stehen Release-Nummer und Distributions-Tag mit
drin, ein hart geschriebenes Beispiel veraltete beim ersten Rebuild).

**Assets eines Releases:** `.deb`, `.rpm`, `.src.rpm`, ein
Quell-Tarball des getaggten Commits (`git archive`, damit er zum Tag
gehoert und nicht zum Arbeitsbaum des Builds) und `SHA256SUMS`. Die
`.changes`- und `.buildinfo`-Dateien aus dem Debian-Build bleiben
draussen: Build-Metadaten, die niemand herunterlaedt. Signiert wird
nicht (`dpkg-buildpackage -us -uc`), solange es weder Lizenz noch
oeffentliche Paketquelle gibt (siehe 4.7).

**Zwei Workflows unter `.github/workflows/`:**

- `ci.yml` bei jedem Push auf `main`/`claude/**` und jedem Pull Request:
  Bash-Syntax, ShellCheck, ASCII-Pruefung und `release.sh --mode check`;
  der Eingabe-Regressionstest `tools/key-scan.sh`, einmal normal und
  einmal mit `--gap 0.06` (die stueckweise Zustellung aus Issue #7);
  Bau beider Pakete.
- `release.yml` bei einem `v*`-Tag: prueft Tag gegen Baum, baut die
  Assets und veroeffentlicht das Release. Ein bereits vorhandenes
  Release wird aktualisiert statt als Fehler behandelt, sodass ein auf
  halber Strecke abgebrochener Lauf wiederholbar ist
  (`workflow_dispatch` mit dem Tag als Eingabe).

Entscheidungen zu den Workflows:

- **ShellCheck blockiert nur auf Stufe `error`.** Dort ist der Baum
  sauber; die verbleibenden Warnungen sind Fehlalarme der
  Modul-Architektur - `lib/*.sh` wird ins Hauptskript gesourct, seine
  Variablen wirken einzeln geprueft ungenutzt (SC2034) und seine Arrays
  wie Skalare (SC2128, SC2178). Der vollstaendige Bericht wird trotzdem
  ausgegeben, nur ohne den Job scheitern zu lassen.
- **Die Pakete werden installiert, nicht nur gebaut.** Der Starter ist
  ein relativer Symlink nach `/usr/share` (siehe 4.7), ein falscher Pfad
  faellt also erst nach der Installation auf; anschliessend wird das
  Paket wieder entfernt und geprueft, dass nichts liegen bleibt. Als
  Spielprogramm laeuft rowhammer im CI nur so weit, wie es ohne Terminal
  geht - das sind `--help` und `--reset` (siehe 4.8), und genau die
  nutzen die Smoke-Tests.
- **Das RPM wird zusaetzlich in einem Fedora-Container installiert.**
  Gebaut wird es auf dem Ubuntu-Runner (`build-rpm.sh` gibt dafuer
  `--nodeps` mit, siehe 4.7), aber erst die Installation auf einer
  RPM-Distribution prueft den `%files`-Abschnitt wirklich, samt des
  bewusst mitbesessenen Verzeichnisses `/usr/games`.
- **Das Release entsteht mit der `gh`-CLI des Runners** statt mit einer
  fremden Action - eine Abhaengigkeit weniger in einem Workflow, der
  Schreibrechte aufs Repository hat (`permissions: contents: write`).
- **Der Release-Workflow prueft selbst nach**, statt sich auf den
  CI-Lauf des Branches zu verlassen: ein Tag darf auf jedem beliebigen
  Commit sitzen.

### 4.10 Demo-Format und Ablage (seit 0.46.0)

Das Konzept und die Entscheidungen dahinter stehen in 3.8; hier das
Dateiformat und der Weg einer Aufnahme.

**Dateiformat** (`lib/demo.sh`). Eine Aufnahme ist eine Textdatei aus
`key=value`-Zeilen, die - wie Savegame und Statistik (4.5) - **geparst
und validiert, nie gesourct** wird; jedes Feld hat sein eigenes Muster
(`DEMO_*_RE`). Erst der Kopf, dann die Steinfolge, dann die Ereignisse:

```
version=2            Formatversion (jede andere wird abgelehnt)
game=0.52.0          Spielversion, die aufgenommen hat (nur Info)
mode=marathon        marathon|ultra|sprint|timeattack|flood - die Regeln
name=Player          Spielername
date=2026-08-03 21:40
time=123456          Spielzeit der Runde in Millisekunden
lines=42 rows=98 level=4 gold=1 silver=2 rowhammers=1 pieces=57
goal=0               ob das Modus-Ziel erreicht wurde
end=over             over|goal|quit - wie die Runde endete
pcs=IOTSZJLIOT...    die Steinfolge (Zeilen zu hoechstens 80 Buchstaben)
e=120l               ein Ereignis: Zeitdelta in ms + Aktionsbuchstabe
```

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

**Zeit.** Jedes Ereignis traegt die **Spielzeit** (`PLAY_MS`, Pausen
also ausgenommen) als Delta zum vorherigen. Beim Laden werden die Deltas
zu absoluten Zeitstempeln aufsummiert; die Wiedergabe fuehrt eine eigene
Uhr (`DEMO_CLOCK_MS`), die je Schleifendurchlauf um die vergangene
Echtzeit mal Tempofaktor waechst, und wendet jedes Ereignis an, sobald
sie dessen Stempel passiert hat. Absolut statt "je Ereignis schlafen":
so kann sich ueber eine lange Demo kein Fehler aufsummieren, ein
langsamer Durchlauf holt auf, und ein Tempowechsel wirkt sofort. Nach
dem letzten Ereignis laeuft die Uhr bis `time` weiter - der Schwanz nach
der letzten Aktion gehoert zur Runde. Das HUD bekommt die Demo-Uhr als
`PLAY_MS`, damit der "Time"-Zaehler (und der Sprint-Countdown) so laeuft
wie in der aufgenommenen Runde.

**Steinfolge.** `queue_fill` (`lib/pieces.sh`) ist die einzige Stelle,
an der Steine in eine Runde kommen, und damit die Stelle, an der die
Demo-Schicht haengt: waehrend einer Aufnahme wird jeder gezogene Stein
notiert, waehrend einer Wiedergabe kommen die Steine aus der Aufnahme
statt aus dem Beutel. Damit stimmen Vorschau und Spawn-Reihenfolge
gleichermassen. Laeuft die Folge einer von Hand bearbeiteten Datei aus,
faellt die Wiedergabe auf den normalen Beutel zurueck (mit Vermerk im
Debug-Log), statt abzubrechen.

**Ablage.** Waehrend der Runde wird ausschliesslich auf eine **RAM-Disk**
geschrieben (`XDG_RUNTIME_DIR`, sonst `/dev/shm`, als letzter Ausweg
`TMPDIR`/`/tmp` mit Vermerk im Debug-Log), und zwar gepuffert: erst je
`DEMO_FLUSH_MAX` (64) Ereignisse - rund alle 15 Sekunden Spielzeit -
haengt ein `printf` sie an die Datei. So kostet eine laufende Runde
weder Frame-Zeit noch Schreibzyklen auf einer SSD, und ein abgestuerzter
Prozess verliert hoechstens diese Sekunden. Erst beim echten Rundenende
(`record_round`, siehe 3.3) baut `demo_record_finish` Kopf, Steinfolge
und Ereignisse zusammen und legt die fertige Datei **atomar**
(Tempdatei + `mv`) unter `${DATA_DIR}/demos/<YYYYMMDD-HHMMSS>-<modus>.demo`
ab; danach werden die aeltesten Aufnahmen ueber `DEMO_MAX` hinaus
geloescht. Der Dateiname beginnt mit dem Datum, sodass das Glob
chronologisch sortiert ist und weder Liste noch Pruning `stat` braucht.
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

### 4.11 Mehrsprachige Oberflaeche (seit 0.48.0)

Jeder Text, den ein Spieler zu sehen bekommt, kommt aus einer
**Texttabelle** statt aus dem Code: Menues und Sicherheitsabfragen, die
Anleitung, die HUD-Beschriftungen, der Kasten am Rundenende, die
Highscore- und Statistik-Tabellen, der Weltwunder-Bildschirm, die
Demo-Liste, der Reset-Dialog (4.8) und die `--help`-Ausgabe.
Umgesetzt in `lib/i18n.sh` plus einer Datei je Sprache unter
`lib/lang/`; mitgeliefert sind **Deutsch** (`de`, die Referenzsprache -
in ihr waren die Menues geschrieben) und **Englisch** (`en`).

- **Die Tabelle ist ein assoziatives Array** (`I18N`), gelesen als
  `${I18N[key]}`. Bewusst keine Lookup-Funktion `t KEY`: die
  HUD-Beschriftungen werden je Frame gelesen (`render_pane_left`), und
  eine Array-Expansion kostet dort weniger als ein Funktionsaufruf je
  Beschriftung.
- **Formatstrings gehoeren in die Tabelle.** Ein Eintrag mit `%s`/`%d`
  wird vom Aufrufer mit `printf -v` gefuellt, sodass die Wortstellung
  Sache der Uebersetzung ist und nicht des Codes. Die Argumentreihenfolge
  legt der Code fest; sie ist in den Sprachdateien dokumentiert.
- **Mehrzeilige Bloecke** (`i18n_lines KEY` fuellt `I18N_LINES`): die
  acht Anleitungsseiten und die laengeren Meldungen stehen als ein
  Block je Absatz in der Sprachdatei, statt als nummerierte
  Zeilenschluessel. Seiten, die Text mit generierten Zeilen mischen
  (Tastenbelegung, Wunder-Kosten, Modus-Ziele), setzen die Bloecke
  davor und dahinter.
- **`--help` ist eine Funktion je Sprachdatei** (`i18n_usage_text`, ein
  gequotetes Heredoc), kein Tabelleneintrag: der Text ist lang, enthaelt
  Anfuehrungs- und Prozentzeichen und wird genau einmal ausgegeben.
- **Eine Sprache dazuzunehmen ist eine Datei plus ein Eintrag** in
  `I18N_LANGS` (`lib/i18n.sh`) und ihr Name in `I18N_LANG_LABEL`.
  Sonst kennt kein Code einen Sprachcode. Geladen wird immer nur die
  aktive Datei, und sie weist das **ganze** Array zu - ein Wechsel zur
  Laufzeit kann damit keinen Text der vorherigen Sprache stehen lassen.
- **Keine Anzeige-Namen mehr in den Modul-Tabellen.** `KEY_LABELS`,
  `COLOR_THEME_LABEL`, `STATS_MODE_LABEL`/`STATS_MODE_GOAL_LABEL` und
  `WONDER_NAMES_DE`/`WONDER_NAMES_HUD` sind entfallen: sie wurden beim
  Sourcen der Module gefuellt, also bevor die Sprache feststeht. Ihre
  Eintraege haben jetzt einen aus dem Bezeichner gebauten Schluessel
  (`keylabel_KEY_HOLD`, `theme_mono`, `mode_ultra`, `stats_goal_sprint`,
  `wonder_stonehenge` aus dem Art-Dateinamen). Der Debug-Log nennt ein
  Wunder seither bei diesem Dateinamen - ein Log muss in jeder Sprache
  gleich zu lesen sein.

**Sprachwahl.** `LANGUAGE` ist ein **Config-Wert** (Praezedenz Standard
< Config < `ROWHAMMER_LANG` < `--lang`), anders als Farb- und
Render-Modus: welche Sprache jemand liest, ist eine Eigenschaft der
Person und keine des Terminals. Erlaubt sind die Codes aus `I18N_LANGS`
und `auto`.

- **Standard ist `auto`**: die Sprache kommt aus `LC_ALL`, `LC_MESSAGES`
  bzw. `LANG` (nur der Sprachteil, `de_DE.UTF-8` -> `de`). Ein Spiel,
  das zwei Sprachen mitbringt und die Locale ignoriert, unterstuetzt
  keine von beiden richtig.
- **Rueckfall ist Deutsch** (`I18N_FALLBACK_LANG`), wenn die Locale
  keine bekannte Sprache nennt (`C`, `POSIX`, nicht gesetzt, unbekannt):
  eine Sitzung ohne brauchbare Locale sieht damit genauso aus wie vor
  0.48.0.
- **Gespeichert wird die Auswahl, `auto` eingeschlossen.** Wer "folge
  der Locale" gewaehlt hat, will das weiter - nicht die Sprache, zu der
  es beim Speichern gerade fuehrte. Der Menuepunkt nennt deshalb bei
  `auto` in Klammern die Sprache, zu der es aktuell aufloest
  (`i18n_lang_label`).
- **Aufgeloest wird frueh**, direkt nach dem Sourcen der Module und vor
  allem, was Text ausgibt: dafuer ist `config_load` vor den
  Reset-Block gewandert (die Sprachwahl steht in der Config), und
  `-h/--help` setzt beim Parsen nur noch ein Flag, statt sofort zu
  drucken - in welcher Sprache zu antworten ist, steht erst fest, wenn
  Config, Umgebung und der Rest der Kommandozeile gelesen sind. Aus
  demselben Grund wirft eine **falsche Option** nicht mehr den ganzen
  Hilfetext nach STDERR, sondern verweist auf `--help`.
- **Umschalten wirkt sofort** (`menu_language` in `lib/menu.sh`): die
  Tabelle wird neu geladen, gespeichert und `RENDER_FULL=1` gesetzt -
  die HUD-Beschriftungen stehen im Frame-Cache des Diff-Renderers
  (4.3), und genau sie haben sich geaendert.

**Was nicht uebersetzt wird:** Diagnosemeldungen nach STDERR (`die`,
Argumentfehler) bleiben englisch, wie es die Konventionen in Abschnitt 6
verlangen. Sie treten teils auf, bevor die Sprache aufgeloest ist - und
wenn die Sprachwahl selbst das Defekte ist, waere eine uebersetzte
Meldung der falsche Ort, das zu zeigen. Ebenso englisch bleiben die
Bezeichner, die zugleich Eingabewerte sind (Modus-, Farbschema- und
Reset-Ziel-Namen auf der Kommandozeile und in der Config) sowie der
Titel des Hauptmenues - das ist der Name des Spiels.

**Breitengrenzen.** Eine Uebersetzung darf das feste Layout (3.4) nicht
sprengen: Menue- und Info-Zeilen hoechstens 46 Zeichen, Zeilen des
Rundenende-Kastens 18, HUD-Beschriftungen 6. Die Grenzen stehen im Kopf
der Sprachdateien; beim Vermessen fielen sechs deutsche Texte auf, die
schon vorher zu lang waren und auf einem 48-Spalten-Terminal
abgeschnitten wurden (Mehrspieler-Platzhalter, die drei Meldungen des
Rebind-Dialogs, die Abbrechen-Fusszeile einer Sicherheitsabfrage und je
eine Zeile der ersten und dritten Anleitungsseite) - sie sind umbrochen.

## 5. Multiplayer (Phase 5, umgesetzt seit 1.1.0)

**Diese Phase laeuft in der `1.x`-Reihe** (siehe die Arbeitsregel in
Abschnitt 6): `2.0.0` ist fuer den Stand reserviert, an dem der
Mehrspieler fertig ist - einschliesslich der Demo-Aufzeichnung aus
5.20. Bis dahin traegt jeder Zuwachs eine Minor-Version, angefangen bei
`1.1.0`.

**Stand:** Der Mehrspieler laeuft seit 1.1.0 - Sitzung eroeffnen und
beitreten, gemeinsame Steinfolge, Stoerreihen, Ausscheiden, Sieger,
eigene Bestenliste und eigener Statistik-Modus (Roadmap-Schritte 1 bis 8
und 10 bis 12, siehe HISTORY.md); seit 1.2.0 ueberlebt eine Lobby
ausserdem ihren Gastgeber (Umzug der Sitzung, siehe 5.1) und ein Client
erkennt eine verstummte Sitzung von selbst (siehe 5.4/5.8). Dieser Abschnitt beschreibt damit
nicht mehr eine Absicht, sondern den gebauten Zustand; wo die Umsetzung
von der urspruenglichen Spezifikation abweicht, steht es an Ort und
Stelle. **Offen ist ein Punkt:** die Demo-Aufzeichnung einer
Mehrspieler-Runde (5.20, Schritt 9). Sie braucht die Formatversion 3 mit
den Peer-Ereignissen; bis dahin wird eine Mehrspieler-Runde bewusst
**nicht** aufgezeichnet (`demo_record_start` lehnt einen Modus ab, den
das Format nicht kennt) - eine Aufnahme im heutigen Format wuerde als
Runde ablaufen, in der aus dem Nichts Stoerreihen erscheinen.

Drei Nachrichten kamen beim Bauen hinzu, die die Nachrichtentabelle in
5.4 so nicht hatte; sie sind dort mit aufgefuehrt und hier zusammen
begruendet, weil sie alle drei dieselbe Luecke schliessen - die
Spezifikation nannte eine Wirkung, ohne zu sagen, woher der Absender
weiss, dass sie noetig ist:

- **`VIEW <0|1>`** (Client -> Hub): "ich zeichne die Gegnerfelder".
  `NEEDBOARD` war vorgesehen, aber der Hub kann nicht wissen, welche
  Detailstufe ein Terminal gerade zeigt.
- **`QUEUE <n>`** (Hub -> Client): die verbindliche Laenge der eigenen
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

- **Die Nachrichten sind gar nicht dieselben.** `GARBAGE` geht an ein
  Ziel, `NEEDBOARD` haengt am Terminal des einzelnen Clients, und ein
  `PEER` geht an alle **ausser** dem Absender. Multicast lohnt erst,
  wo wirklich alle dasselbe bekommen.
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
und ohne Tastatur laufen koennen (Roadmap-Punkt "Spiellogik entkoppeln").
Konkret: `game_reset`, `step_down`, `lock_and_next`, `hold_piece`,
`try_move`, `try_rotate` duerfen weder zeichnen noch lesen; `DIRTY`
markiert nur. Das ist ohnehin fast erreicht - offen sind die Stellen, an
denen `flash_rows` den Loop anhaelt und `record_round` Bildschirme zeigt.

### 5.4 Protokoll (Version 3)

- **Rahmen:** eine Nachricht = eine Zeile, `\n`-terminiert, reines
  druckbares ASCII (0x20-0x7E), maximal **512 Byte** inklusive Zeilenende.
  Felder durch **ein Leerzeichen** getrennt, erstes Feld ist das Verb in
  Grossbuchstaben. Unbekannte Verben werden ignoriert (Vorwaerts-
  kompatibilitaet), fehlerhafte Zeilen fuehren zum Verbindungsabbruch
  (siehe 5.5).
- **Versionierung:** `PROTO_VERSION=3`. Der Hub lehnt abweichende
  Versionen im `HELLO` mit `ERR proto ...` ab. Gemaess der Arbeitsregel
  "keine Abwaertskompatibilitaet" wird das Protokoll bei Bedarf
  hochgezaehlt statt kompatibel erweitert; genau das ist zweimal
  passiert. **Version 2** kam mit den Sitzungseinstellungen (1.1.0,
  siehe 5.1): `SETUP` in beide Richtungen. **Version 3** kam mit dem
  Gastgeberwechsel (1.2.0, siehe unten und 5.8): `HOST`, `PROMOTE`,
  `PROMOTED`, `MIGRATE` und `CLOSED`, dazu der Sitzungsname als viertes
  Feld von `WELCOME` - eine umgezogene Sitzung soll unter ihrem eigenen
  Namen weiterlaufen und nicht unter dem des Nachfolgers.
- **Client -> Hub**

  | Nachricht | Felder | Bedeutung |
  | --- | --- | --- |
  | `HELLO` | `<proto> <name> <caps>` | Anmeldung; `caps` = Komma-Liste (z. B. `board`) |
  | `READY` | `<0 oder 1>` | Bereitschaft in der Lobby |
  | `STATE` | `<lines> <rows> <level> <gold> <silver> <height> <pending>` | eigener Zaehlerstand, bei Aenderung, max. 10/s |
  | `BOARD` | `<200 Zeichen>` | Feld-Snapshot, nur wenn der Hub `NEEDBOARD 1` gesetzt hat, max. 5/s |
  | `CLEAR` | `<lines> <silver> <gold>` | ein Reihenabbau als Angriffs-Meldung (Hub rechnet daraus die Garbage aus) |
  | `APPLIED` | `<count>` | eingeschobene Stoerreihen (seit 1.1.0, siehe unten) |
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
  | `NEEDBOARD` | `<0 oder 1>` | ob dieser Client Snapshots senden soll (spart Last, wenn niemand Stufe 2 anzeigt) |
  | `GARBAGE` | `<count> <hole>` | eingehende Stoerreihen, Lochspalte 0-9 |
  | `QUEUE` | `<count>` | verbindliche Laenge der eigenen Warteschlange (seit 1.1.0) |
  | `KO` | `<slot> <platz>` | Spieler ausgeschieden |
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
  erkennbar, Garbage dunkelgrau).
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
  dauert wenige Minuten).
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
    sechst gespielt wurde.
  - **Die Statistik bekommt den Mehrspieler als eigenen Modus**
    (`mode_versus_*`, siehe die Modus-Zaehler in 4.5), dazu die zwei
    Zahlen, die es nur hier gibt: Siege und die gesendete bzw.
    erhaltene Garbage. Sie stehen neben den Modus-Zaehlern und nicht
    in den Gesamtzaehlern - die zaehlen Reihen, nicht Duelle.
  - **Ob eine Mehrspieler-Runde zusaetzlich in eine lokale
    Bestenliste kommt, ist noch offen** (Nutzer unentschieden,
    Tendenz "ja"). Empfehlung mit dem Muster, das dieses Projekt fuer
    genau diese Frage schon fuenfmal angewandt hat: **eine eigene
    Liste `highscore-versus`** statt eines Eintrags in der
    Marathon-Liste. Begruendung und Alternativen in Abschnitt 8.

### 5.9 Auswirkungen auf bestehende Systeme

- **Rendering-Performance:** mit bis zu 6 Feldern reicht ein
  "kompletter Frame als String" nicht. Der Phase-4-Punkt "nur
  geaenderte Zellen zeichnen" war damit Voraussetzung und ist mit 0.22.0
  erledigt (Zeilen-Diff plus Cache der liegenden Feldreihen, siehe 4.3);
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
- **Seed:** `--seed` wird im Mehrspieler vom Hub-Seed uebersteuert; ein
  gesetzter `--seed` beim Host wird zum Sitzungs-Seed.
- **Terminalgroesse:** der SIGWINCH-Pfad waehlt zusaetzlich die
  Detailstufe neu (siehe 5.6).
- **Demo-Schicht:** eine Mehrspieler-Runde wird wie jede andere
  mitgeschnitten, zeichnet aber **alle Teilnehmer** auf
  (Nutzerentscheidung, Format und Grenzen siehe 5.20). Das ist die
  einzige Stelle, an der das Demo-Format der Runde etwas hinzufuegen
  muss, das nicht aus den eigenen Zuegen kommt.
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
| `--mp-host [NAME]` | `ROWHAMMER_MP_HOST` | Sitzung eroeffnen (Standardname = Benutzername) |
| `--mp-join ZIEL` | `ROWHAMMER_MP_JOIN` | Beitreten: Sitzungsname oder `HOST[:PORT]` (siehe 5.2) |
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
- **Empfehlung fuer das spaetere Account-System (zu bestaetigen, siehe
  Abschnitt 8):** rowhammer-Accounts **nicht** eins-zu-eins auf
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
- **Empfehlung (zu bestaetigen):** kein Sprung direkt auf einen separaten
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
der Roadmap (Phase 6, Abschnitt 7) und werden erst konkretisiert, wenn
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
- **Empfehlung (zu bestaetigen, siehe Abschnitt 8):** kein Bruch, sondern
  eine klare Grenze entlang dessen, was Bash gut kann und was nicht:
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

- **Idee (Nutzervorschlag, zu bestaetigen, siehe Abschnitt 8):** auf
  einem Server bauen nicht nur einzelne Accounts an ihrem eigenen
  Weltwunder (siehe 3.3, das bleibt fuer den lokalen
  Einzelspieler-Betrieb unveraendert bestehen), sondern **alle Spieler
  gemeinsam** zusaetzlich an einem serverweiten Weltwunder. Jede
  abgebaute Reihe jedes Accounts zahlt dann doppelt ein: auf den
  eigenen (Account-)Zaehler und auf einen gemeinsamen Server-Zaehler.
- **Konsequenz fuer die Kostentabelle:** Die bestehende
  `WONDER_COSTS`-Reihe (seit 0.45.0 10.000..640.000, insgesamt 1.270.000
  Reihen, siehe 3.3) ist auf einen einzelnen Spieler ausgelegt und waere
  von vielen
  gleichzeitig spielenden Accounts durchgespielt, lange bevor ein
  gemeinsames Wunder etwas Gemeinsames haette. Der
  Server-Fortschritt braucht deshalb weiterhin **eine eigene, deutlich
  groessere Kostentabelle** (`SERVER_WONDER_COSTS`) - die Umstellung in
  0.45.0 hat den Abstand nur verkleinert, nicht aufgehoben: sie bringt
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
- **Offen (siehe Abschnitt 8):** ob der Server tatsaechlich eigene,
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
- **Offen (siehe Abschnitt 8):** konkrete Abzeichen-Liste und ihre
  Bedingungen sind noch nicht festgelegt - erst nach Playtesting und
  zusammen mit dem Liga-System (5.14) sinnvoll auszuarbeiten, damit
  Abzeichen und Liga-Punkte sich nicht widersprechen.

### 5.20 Demo-Aufzeichnung im Mehrspieler

Dieser Unterabschnitt gehoert zu **Phase 5** und steht trotzdem hier am
Ende, damit die Nummerierung 5.11-5.19 (Phase 6) nicht wandert und die
Verweise darauf im ganzen Dokument gueltig bleiben.

**Jeder Client zeichnet alle Teilnehmer auf** (Nutzerentscheidung); die
Datei waechst damit mit der Spielerzahl, was hinnehmbar ist. Die
Aufzeichnung folgt im Uebrigen den Regeln aus 3.8 und 4.10 - sie
zeichnet Zuege statt Bildschirmen auf, sie darf das Spiel nicht
veraendern, sie wird beim echten Rundenende geschrieben, und eine
Wiedergabe wird nie gewertet.

**Der eigene Spieler und die Mitspieler werden verschieden
aufgezeichnet, weil ueber die Leitung Verschiedenes ankommt.** Die
eigenen Zuege liegen vollstaendig vor und werden wie bisher notiert und
bei der Wiedergabe durch dieselben Spielfunktionen nachgespielt. Die
**Zuege der Mitspieler kommen nirgends an**: das Protokoll (5.4)
uebertraegt ihre Zaehler (`PEER`, max. 10/s) und - nur in der
Detailstufe 2 - Feld-Schnappschuesse (`PEERBOARD`, 200 Zeichen, max.
5 Hz, siehe 5.6). Ein Mitspieler laesst sich deshalb nicht
nachsimulieren, sondern nur so wiedergeben, wie er ankam. Daraus
folgen fuenf Festlegungen:

- **Aufgezeichnet wird, was empfangen wurde.** Fuer jeden Mitspieler
  wandern die `PEER`-Zaehler und, sofern vorhanden, die
  Feld-Schnappschuesse in die Datei. Die Wiedergabe zeigt die
  Mitspieler damit exakt so, wie dieser Spieler sie waehrend der Runde
  gesehen hat - eine persoenliche Aufnahme derselben Partie, kein
  Mitschnitt aus der Vogelperspektive. Das ist ehrlicher, als es
  klingt: was ein Spieler gesehen hat, ist genau das, worauf er
  reagiert hat.
- **Die Aufnahme erzwingt keine Schnappschuesse.** Ob `PEERBOARD`
  ueberhaupt fliesst, entscheidet weiterhin `NEEDBOARD` und damit die
  Detailstufe des Terminals (5.6). Die Aufzeichnung dort einzugreifen
  zu lassen, waere ein doppelter Bruch: sie ist standardmaessig an, es
  wuerde also faktisch immer jeder Client Schnappschuesse anfordern und
  `NEEDBOARD` waere sinnlos - und die Regel "die Aufzeichnung aendert
  das Spiel nicht" (3.8) faellt. Der Kopf der Datei vermerkt
  stattdessen, was drinsteht (`peers=board` bzw. `peers=state`), und
  eine Wiedergabe ohne Schnappschuesse zeigt die Mitspieler in der
  Kompakt- bzw. Scoreboard-Ansicht. Wer volle Gegnerfelder in seiner
  Aufnahme haben will, spielt in Detailstufe 2.
- **Eingehende Garbage ist ein eigenes Ereignis.** Sie kommt vom Hub
  (`GARBAGE <count> <hole>`) und laesst sich aus nichts ableiten, was
  sonst in der Datei steht; ohne sie liefe das eigene Feld bei der
  Wiedergabe auseinander. Sie bekommt deshalb einen Ereignisbuchstaben
  mit Nutzlast, wie ihn 4.10 bisher nur fuer die Flutreihe des
  Hochwasser-Modus kennt (`w<spalte>`) - dieselbe Bauart, nur mit
  Anzahl und Lochspalte.
- **Formatversion 3.** Der Kopf bekommt `players=`, den eigenen Slot,
  je Mitspieler eine Namenszeile und den `peers=`-Vermerk oben; die
  Ereignisliste bekommt die drei neuen Buchstaben (Peer-Zaehler,
  Peer-Feldzeile, eingehende Garbage). Die Formatversion wird wie
  beim Hochwasser-Modus (4.10) hochgezaehlt statt kompatibel erweitert
  (Arbeitsregel "keine Abwaertskompatibilitaet").
- **Feld-Schnappschuesse werden zeilenweise abgelegt, nicht als
  200-Zeichen-Bloecke.** Notiert wird nur, was sich gegenueber dem
  letzten Stand dieses Mitspielers geaendert hat (Zeilennummer plus die
  zehn Zellen). Ein Schnappschuss aendert typischerweise die ein bis
  vier Zeilen um den eben festgesetzten Stein; das ist der Unterschied
  zwischen rund 200 und rund 30 Byte je Aktualisierung. Ueberschlag mit
  vier Mitspielern und einem Lock je Sekunde: gut 8 kB je Spielminute
  fuer alle Mitspieler zusammen, gegenueber den rund 2 kB, die die
  eigene Runde kostet (3.8) - eine Fuenf-Spieler-Partie ueber fuenf
  Minuten landet bei etwa 60 kB. Ohne diese Zeilen-Ablage waere es das
  Fuenf- bis Zehnfache. `DEMO_MAX` und das Aufraeumen bleiben deshalb
  unveraendert; auch fuenfzig Aufnahmen dieser Groesse sind wenige
  Megabyte.

**Wiedergabe.** Die Demo-Uhr (4.10) treibt beide Seiten: das eigene
Feld wird aus den Zuegen nachgespielt, die Mitspielerfelder werden zu
ihren Zeitstempeln gesetzt. Tempo (0.25x bis 4x), Pause und die
Rueckkehr zur Liste funktionieren damit unveraendert - sie haengen an
der Uhr, nicht an der Art der Ereignisse. Der Kasten am Ende zeigt
zusaetzlich die Platzierung der Runde.

## 6. Konventionen fuer alle Skripte

Fuer **jedes** Bash-Skript in diesem Repo gelten verbindlich die
**Script-Konventionen** (Skill `script-conventions`). Insbesondere:

- Header-Kommentarblock mit Beschreibung, Programmablaufplan (bei laengeren
  Skripten), Nutzung und SemVer-Version mit Datum.
- Kommentare, Strings und Ausgaben in **Englisch**, **nur ASCII**.
  Ausnahme seit 0.48.0: die Texte, die ein Spieler zu sehen bekommt,
  stehen nicht mehr als Strings im Code, sondern in den Sprachdateien
  unter `lib/lang/` (siehe 4.11) - dort gilt die Sprache der Datei, die
  ASCII-Regel unveraendert weiter (deutsche Umlaute als ae/oe/ue/ss).
  Diagnosemeldungen nach STDERR bleiben ausnahmslos englisch.
- `-h`/`--help` mit allen Parametern; jeder Parameter zusaetzlich per
  Umgebungsvariable setzbar (Praefix `ROWHAMMER_`, Praezedenz
  Standard < Config < Env < CLI).
- Variablen immer als `"${var}"` schreiben.
- Fehler mit aussagekraeftiger Meldung nach STDERR; STDERR von Befehlen nicht
  unterdruecken; Exit-Code 0/!=0, Aufruffehler 2.
- Begruendungskommentare bei spaeteren Aenderungen bewahren.

Hinweis: Das Spiel ist interaktiv; die Logging-Regeln fuer cron/systemd sind
hier nachrangig, die uebrigen Regeln gelten uneingeschraenkt.
Diese CLAUDE.md (Konzept, Roadmap) ist bei jeder inhaltlichen Aenderung
mitzupflegen.

Arbeitsregel: **Erledigte Roadmap-Punkte wandern nach HISTORY.md.** Die
Roadmap (Abschnitt 7) fuehrt nur Offenes; ist ein Punkt umgesetzt, wird
er samt seiner Begruendung nach [HISTORY.md](HISTORY.md) verschoben
(Archiv, nach Version geordnet, mit Uebersichtstabelle). Zum Verschieben
gehoert dazu:

1. **Aktuellen Zustand nachziehen.** Was die Funktion *heute* tut, gehoert
   in die Abschnitte 1 bis 5 dieser Datei - und, soweit es Spielerinnen
   und Spieler sehen (Menuepunkte, Tasten, CLI-Optionen, Dateien im
   Datenverzeichnis), zusaetzlich in die README.md. HISTORY.md beschreibt
   nur den Stand zum Umsetzungszeitpunkt und ist keine Quelle fuer den
   aktuellen Zustand.
2. **Ueberholtes markieren.** Loest die neue Version eine aeltere ab,
   bekommt der aeltere Eintrag in HISTORY.md eine Zeile
   _"Spaeter ueberholt: ..."_ mit Verweis auf die abloesende Version.
3. **Querverweise pruefen.** Zeigt eine Stelle in CLAUDE.md auf einen
   Roadmap-Punkt ("siehe Phase 4 ..."), wird der Verweis auf HISTORY.md
   samt Version umgeschrieben.

Arbeitsregel: **`2.0.0` kommt erst, wenn der Mehrspieler fertig ist**
(Nutzerentscheidung, ueberarbeitet mit 1.1.0). Bis dahin laeuft die
Arbeit am Mehrspieler in der **`1.x`-Reihe** weiter, Seite an Seite mit
allem anderen, was am Spiel nachgezogen wird: eine Minor-Version je
Zuwachs, eine Patch-Version je Korrektur.

Bis 1.0.4 galt hier die umgekehrte Regel - jede Aenderung am
Mehrspieler sei Arbeit an `2.x.x`, und der erste Schritt hinein der
Sprung auf `2.0.0`. Die erste Fassung des Mehrspielers war danach
zunaechst als `2.0.0` beschriftet; noch vor jedem Release hat der Nutzer
das umgedreht, weil die grosse Zahl etwas Fertiges verspricht, das
dieser Modus noch nicht ist (der Lobby-Aufbau, die Sitzungs-
einstellungen und die Demo-Aufzeichnung fehlten). Eine Versionsnummer
ist eine Aussage ueber den Zustand, nicht ueber die Menge der Arbeit.
`2.0.0` ist damit reserviert fuer den Stand, an dem Phase 5
abgeschlossen ist - also einschliesslich der Demo-Aufzeichnung einer
Mehrspieler-Runde (5.20); die Server-Phase 6 baut danach darauf auf.
SemVer traegt das: die neuen Formate des Mehrspielers (Protokoll,
Sitzungsverzeichnis) sind bislang nur untereinander im Umlauf, und die
Arbeitsregel "keine Abwaertskompatibilitaet" unten laesst sie ohnehin
brechen - eine Protokollversion, die ein alter Client nicht kennt,
weist der Hub sauber ab.

Arbeitsregel: **Keine Abwaertskompatibilitaet noetig.** Das Projekt wird
sequenziell entwickelt und war nie anderswo installiert; Migrationslogik
fuer alte Config-/Savegame-Formate oder alte Schnittstellen ist unnoetig
und soll weggelassen werden. Formate duerfen bei Bedarf einfach brechen.

Arbeitsregel: **Aenderungen an der ToDo-Liste (Abschnitt 7) duerfen
direkt auf dem `main`-Branch vorgenommen werden**, auch ohne eigenen
Feature-Branch oder Pull Request. Dasselbe gilt fuer HISTORY.md, soweit
nur bereits erledigte Punkte dorthin verschoben oder dort nachgetragen
werden.

## 7. Roadmap / Todo-Liste

Diese Liste fuehrt nur noch die **offenen** Punkte. Ein erledigter Punkt
wandert samt seiner Begruendung nach [HISTORY.md](HISTORY.md) - dem
Archiv der abgeschlossenen Roadmap-Punkte, nach Version geordnet. Der
**aktuelle** Zustand der jeweiligen Funktion steht danach nicht dort,
sondern in den Abschnitten 1 bis 5 dieser Datei und - soweit
spielersichtbar - in der README.md (Arbeitsregel in Abschnitt 6).

**Versionszuordnung (ueberarbeitet mit 1.1.0):** Alles unten laeuft in
der **`1.x`-Reihe** - die offenen Einzelspieler-Punkte ebenso wie der
Rest der Phase 5. **`2.0.0` ist fuer den fertigen Mehrspieler
reserviert** (Arbeitsregel in Abschnitt 6): erst wenn Phase 5
abgeschlossen ist, also samt der Demo-Aufzeichnung einer
Mehrspieler-Runde (5.20), traegt das Spiel die grosse Zahl; die
Server-Phase 6 baut danach darauf auf.

Erledigt und nach HISTORY.md verschoben:

- **Phase 1 - Spielbarer Kern** (0.1.0), vollstaendig
- **Zwischenschritt - Menue und Konfiguration** (0.2.0), vollstaendig
- **Phase 2 - The-New-Tetris-Mechaniken** (0.3.0, Bonuswerte 0.4.0),
  vollstaendig
- **Zwischenschritt - Debug-Modus** (0.6.0), vollstaendig
- **Phase 3 - Weltwunder** (0.8.0), vollstaendig
- **Zwischenschritt - Paketierung**: `Makefile`, Debian-Paketierung und
  `build-deb.sh` (0.17.0), RPM-Paketierung und `build-rpm.sh` (0.37.0),
  Release-Struktur auf GitHub samt CI-Paketbau (0.40.0, siehe 4.9);
  die restlichen Punkte dieses Zwischenschritts stehen unten
- **Phase 4 - Politur**: alles von 0.5.0 (Tastenbelegung) bis 1.0.2
  (Rundenende am oberen Feldrand); die
  Uebersichtstabelle in HISTORY.md
  listet jede Version mit ihrem Thema. Offen ist der Punkt unten
- **Phase 5 - Mehrspieler** (1.1.0): die Schritte 1 bis 8 und 10 bis 12
  (Transport, Protokoll, Hub und Lobby, Mitspieler-Anzeige in drei
  Stufen, Garbage, Rundenende, mehrere Spieler, Test-Bot und
  Fuzz-Review). Offen bleiben die zwei Punkte unten

### Zwischenschritt - Paketierung (Version 1.x.x; offene Punkte, deb 0.17.0, rpm 0.37.0 und Release/CI 0.40.0 erledigt, siehe HISTORY.md)

- [ ] Lauffaehigkeit fuer abgespeckte Shells pruefen (z. B. `ash`/BusyBox
      auf OpenWrt/Embedded-Systemen); nur bei positivem Ergebnis den
      naechsten Punkt (opkg-Paketierung) angehen
- [ ] opkg-Paketierung implementieren (fuer OpenWrt/Embedded-Systeme,
      analog zur Debian-Paketierung, nutzt ebenfalls `make install`),
      vorausgesetzt die Shell-Kompatibilitaetspruefung faellt positiv aus
- [ ] Lizenz festlegen und `debian/copyright` aktualisieren. Haengt
      inzwischen mehr dran als die beiden Dateien: solange es keine
      Lizenz gibt, werden die Release-Pakete bewusst unsigniert gebaut
      und es gibt keine oeffentliche Paketquelle (siehe 4.9). Ein
      Signier-Schritt im Release-Workflow (Schluessel als Secret) waere
      der naechste Schritt, sobald die Lizenzfrage entschieden ist.

### Phase 4 - Politur (Version 1.x.x; offene Punkte, die erledigten stehen in HISTORY.md)

- [ ] Weltwunder-Animation (siehe 5.18, Nutzerwunsch): der
      Wunder-Bildschirm deckt die ASCII-Art bislang nur statisch
      zeilenweise auf. Kurze, von Hand aus asciinema-Voraufnahmen
      abgeleitete Frame-Tabellen sollen Wunder-Uebergaenge (neue
      Baustufe, Fertigstellung) mit einem kleinen Animationsschritt
      versehen, ueber das bestehende `FRAME_LINES`-Rendering (4.3) ohne
      neue Abhaengigkeit. Gilt fuer den lokalen wie den spaeteren
      serverweiten Wunder-Bildschirm (5.17) gleichermassen und hat
      keine Server-Abhaengigkeit, ist also unabhaengig von Phase 6
      umsetzbar.
### Phase 5 - Multiplayer (Version 1.x.x; Kern seit 1.1.0, offener Rest unten)

Die Schritte 1 bis 8 sowie 10 bis 12 sind mit `1.1.0` umgesetzt und samt
ihrer Begruendung nach [HISTORY.md](HISTORY.md) gewandert; der aktuelle
Zustand steht in Abschnitt 5. Offen ist ein Schritt:

- [ ] **Schritt 9 - Demo-Aufzeichnung der Mehrspieler-Runde** (siehe 5.20).
      Formatversion 3, Kopf mit Slots und Namen, Peer-Zaehler und
      zeilenweise Peer-Schnappschuesse als Ereignisse, eingehende
      Garbage als eigenes Ereignis, Wiedergabe mit nachgespieltem
      eigenem Feld und gesetzten Gegnerfeldern. Bis dahin wird eine
      Mehrspieler-Runde **nicht** aufgezeichnet: `demo_record_start`
      lehnt einen Modus ab, den `DEMO_MODE_RE` nicht kennt, denn eine
      Aufnahme im Format 2 liefe als Runde ab, in der aus dem Nichts
      Stoerreihen erscheinen. Abnahme: die Wiedergabe einer
      Vier-Spieler-Runde zeigt denselben Verlauf, den der aufzeichnende
      Client gesehen hat, und eine Aufnahme aus Detailstufe 0/1 laeuft
      ohne Gegnerfelder sauber durch.
- [ ] **Rest aus Schritt 1 - Entkopplung der Rundenlogik** (siehe 5.3).
      Der Mehrspieler brauchte davon nur, was er benutzt, und laeuft
      damit; vollstaendig entkoppelt ist die Rundenlogik aber nicht:
      `flash_rows` haelt den Loop weiterhin an (es leert im Mehrspieler
      immerhin die Leitung mit) und `record_round` verbucht und zeigt
      noch in einem. Das ist Aufraeumarbeit ohne sichtbare Wirkung und
      steht deshalb hinter allem anderen.

### Phase 6 - Server-Betrieb, Accounts, Web (Version 2.x.x; spezifiziert in 5.11-5.19, noch nicht umgesetzt)

Diese Phase beginnt hinter `2.0.0`, also hinter dem abgeschlossenen
Mehrspieler (Arbeitsregel in Abschnitt 6).

Setzt auf einem fertigen Phase 5 auf (der Mehrspieler-Kern muss laufen
und sich per Playtesting bewaehrt haben, bevor Accounts/Web/Liga
sinnvoll sind). Reihenfolge wie in 5.11-5.19 begruendet: Deployment
zuerst (ohne Server kein Bedarf fuer Accounts), Accounts vor dem
Persistenz-Umbau (das Datenbankschema haengt vom Kontomodell ab),
serverweite Statistik und gemeinsames Weltwunder direkt danach (sie
brauchen nur Accounts und die Datenbank, keine laufende
Mehrspieler-Session, und lassen sich vor der Webseite fertig testen),
Web-Frontend/Kontoverknuepfung/Abzeichen anschliessend, Liga und
Multi-Server zuletzt.

- [ ] **Schritt 1 - SSH-ForceCommand-Deployment** (siehe 5.11).
      `sshd_config`/`authorized_keys`-Vorlage mit `ForceCommand` bzw.
      `command=`, Haertung (`no-port-forwarding` usw.), eigener
      Systembenutzer, Rechte auf `${DATA_DIR}`/`${MP_DIR}` geprueft.
      Laeuft zunaechst weiter mit freiem Login (siehe 5.12).
      Abnahme: mehrere SSH-Sitzungen landen direkt im Spiel, keine Shell
      erreichbar.
- [ ] **Schritt 2 - Konto-Grundlage: SSH-Key-Bindung** (siehe 5.12).
      Spielkonto an SSH-Public-Key-Fingerprint gebunden, Erstanmeldung
      fragt Kontonamen ab, Namensmuster wie 5.5. Noch ohne Passwort- oder
      OAuth-Login. Abnahme: derselbe Key wird bei jeder Sitzung demselben
      Konto zugeordnet, ein fremder Key kann einen belegten Namen nicht
      kapern.
- [ ] **Schritt 3 - Server-Persistenz auf SQLite umstellen** (siehe 5.13).
      Highscore, Stats und Konten in SQLite-Tabellen statt Flatfiles,
      `sqlite3`-Zugriff aus Bash mit gebundenen Parametern, Migration der
      Formate ohne Altdaten-Uebernahme (Arbeitsregel Abschnitt 6).
      Abnahme: identisches Verhalten wie die bisherigen Flatfiles, aber
      per SQL abfragbar (z. B. Rang eines Kontos ueber alle Runden).
- [ ] **Schritt 4 - Erweiterte Server-Highscore-Liste** (siehe 5.13).
      Laengere Liste (mehr als Top 10), Filter/Suche nach Konto,
      weiterhin im Spiel ueber "Highscores" abrufbar. Abnahme: Liste
      bleibt bei vielen Konten performant und uebersichtlich (seitenweise
      wie heute, siehe 4.5).
- [ ] **Schritt 5 - Serverweite Statistik** (siehe 5.16).
      Kontounabhaengiger Aggregat-Zaehler zusaetzlich zum Account-Eintrag
      bei jeder verbuchten Runde (`server_stats`), neuer Menuepunkt
      "Server-Statistik". Abnahme: der Zaehler summiert sichtbar ueber
      mehrere Accounts hinweg korrekt auf, unabhaengig von Highscore und
      persoenlicher Statistik.
- [ ] **Schritt 6 - Gemeinsamer Weltwunder-Fortschritt** (siehe 5.17).
      Zusaetzlicher serverweiter Reihenzaehler mit eigener, deutlich
      groesserer Kostentabelle (`SERVER_WONDER_COSTS`), zweiter
      Wunder-Bildschirm fuer den Server-Fortschritt. Abnahme: Reihen
      mehrerer Accounts zahlen sichtbar auf denselben Server-Fortschritt
      ein, der Account-eigene Fortschritt bleibt davon unberuehrt.
- [ ] **Schritt 7 - Web-Highscore (read-only)** (siehe 5.14).
      Separates, schlankes Web-Backend liest die Datenbank aus Schritt 3,
      zeigt Highscore/Statistik (inklusive Server-Statistik aus Schritt 5)
      im Browser. Kein Schreibzugriff vom Web aus. Abnahme: Highscore-
      Liste ist ohne SSH-Zugang einsehbar.
- [ ] **Schritt 8 - OAuth-Kontoverknuepfung** (siehe 5.12, 5.14).
      Login mit Google/Apple/Facebook & Co. auf der Webseite, Anzeige
      eines kurzlebigen Verknuepfungscodes, Eingabe im Spiel
      ("Konto verknuepfen") bindet SSH-Key und Web-Identitaet an
      dasselbe Konto. Abnahme: Anmeldung ueber einen der Anbieter fuehrt
      zum selben Spielkonto wie der bisherige SSH-Key-Login.
- [ ] **Schritt 9 - Account-Abzeichen** (siehe 5.19).
      Feste Abzeichen-Liste mit pruefbaren Bedingungen, Freischaltung bei
      `record_round`, Anzeige im Account-Bereich und spaeter auf der
      Highscore-Webseite. Abnahme: ein erfuelltes Kriterium schaltet das
      passende Abzeichen zuverlaessig und dauerhaft frei.
- [ ] **Schritt 10 - Liga-System** (siehe 5.14).
      Saisons/Ranglisten oberhalb der Highscore-Liste; Regeln noch offen
      (siehe Abschnitt 8), erst nach Playtesting des Mehrspieler-Kerns und
      im Zusammenspiel mit den Abzeichen aus Schritt 9 zu konkretisieren.
- [ ] **Schritt 11 - Multi-Server-Faehigkeit** (siehe 5.14).
      Mehrere Spiel-Server gegen ein gemeinsames Accounts-/Highscore-
      Backend, Kontosynchronisation ueber Server-Grenzen hinweg. Abnahme:
      ein Konto behaelt Highscore und Einstellungen beim Wechsel des
      Servers.

## 8. Offene Punkte

- Bonus-Reihenwertung ist verifiziert und umgesetzt (siehe 3.2); seit
  dem Punktesystem-Umbau in 0.16.0 ist sie zugleich der Score. Die
  frueher offene Frage nach den Punkten fuer die Quadrat-Bildung hat
  sich damit erledigt (es gibt bewusst keine Bildungs-Punkte mehr).
- Weltwunder-Liste und Baustufen sind seit 0.8.0 festgelegt (siehe
  3.3). Die Reihen-Kosten je Wunder waren gegenueber dem Original
  bewusst herunterskaliert (100..6400) und sind mit 0.45.0 auf
  Nutzerentscheidung mit 100 multipliziert worden (10.000..640.000,
  Original-Groessenordnung). Offen bleibt wie bisher nur die
  Feinjustierung nach Playtesting (`WONDER_COSTS`).
- Mindest-Terminalgroesse: seit 0.26.0 48x22 (vorher 48x24 - die zwei
  Statuszeilen sind mit dem HUD-Umbau entfallen, siehe 3.4), seit
  0.19.0 auch waehrend des Spiels ueberwacht (SIGWINCH, siehe HISTORY.md,
  0.19.0 "Anpassung an Terminalgroesse"): ein Resize zeichnet sauber neu, ein
  Unterschreiten des Minimums pausiert die Runde hinter einer
  "resize me"-Overlay bis das Terminal wieder gross genug ist. Das feste
  Layout skaliert bewusst nicht mit, wird aber seit 0.22.0 mittig im
  Terminal ausgerichtet (siehe 3.4) - seit 0.28.0 ebenso die Menue- und
  Info-Bildschirme (siehe 4.3); groessere Terminals zeigen das
  Spiel also zentriert statt oben links. Ein mitwachsendes Layout (z. B.
  breitere Zellen oder mehr Vorschau auf grossen Terminals) ist bewusst
  nicht vorgesehen.
- Rowhammer-Zaehler: erledigt. 0.24.0 brachte Rundenzaehler und
  Gesamtstatistik, 0.25.0 auf Nutzerentscheidung auch HUD,
  `recent=`-Liste und Highscore-Zeile - im HUD anstelle des
  Weltwunder-Fortschritts, in den beiden Tabellen zulasten der
  Namensspalte bzw. der letzten freien Spalten (siehe 3.4 und 4.5).
  Die beiden Tabellen (Highscore, letzte Spiele) waren damit randvoll.
  Fuer den HUD gilt das seit 0.26.0 nicht mehr - die Zaehler
  stehen jetzt untereinander in der linken Spalte und haben dort noch
  acht freie Zeilen (siehe 3.4).
- Tabellenbreite: erledigt fuer den naechsten Zuwachs. Der
  Pieces-Zaehler (0.27.0) hat die Ein-Zeilen-Grenze der beiden Tabellen
  gesprengt; auf Nutzerentscheidung ist ein Eintrag jetzt zwei Zeilen
  breit, seitenweise angezeigt (bis 0.51.0 ueber `menu_pages`, seit
  0.52.0 ueber `highscore_browse`, siehe 4.5). Weitere Werte kosten
  damit keine vorhandene Spalte mehr, sondern Zeilen - und irgendwann
  eine weitere Seite: pro Info-Bildschirm passen 18 Zeilen
  (`MENU_BODY_MAX`, seit 0.28.0 eine mehr), die Highscore-Liste zeigt fuenf Eintraege je
  Seite, die Statistik teilt sich in Gesamtzaehler und letzte Spiele.
  Eine Zeile der Liste hat seit 0.52.0 zwei Zeichen weniger fuer sich
  (`HS_LINE_MAX` 44 statt 46): die beiden vordersten Spalten gehoeren
  dem Cursor und der Demo-Markierung.
- Spielmodi: die drei Fragen zum Ultra-Modus sind mit 0.34.0
  entschieden (Rows statt Lines, gescheiterte Versuche ohne
  Listeneintrag, HUD-Zaehler "Goal"/"Left" in der linken Spalte, siehe
  3.6), Sprint hat sie mit 0.39.0 gespiegelt uebernommen und Time
  Attack folgt ihnen seit 0.42.0 mit einer begruendeten Ausnahme (jeder
  Lauf wird gewertet, siehe 3.6). Offen
  bleibt nur die Justierung: ob 150 Rows die richtige
  Distanz, 3 Minuten die richtige Dauer und 1 Minute Startzeit bei
  1 Sekunde je Row die richtige Time-Attack-Waehrung sind, entscheidet
  Playtesting
  (`ULTRA_TARGET_ROWS`, `SPRINT_TIME_MS`, `TIME_ATTACK_START_MS`/
  `TIME_ATTACK_ROW_MS`) - mit den
  Quadrat-Boni ist die Ultra-Strecke deutlich kuerzer als 150 physische
  Reihen, das ist so gewollt, und aus demselben Grund verlaengert ein
  Rowhammer durch zwei Gold-Quadrate eine Time-Attack-Runde gleich um
  85 Sekunden. Hochwasser (0.49.0) folgt derselben Linie: Rows als
  Wertung, jede Runde gewertet (es gibt nur ein Ende), und offen ist
  auch hier allein die Justierung - ob 20 Sekunden je Flutreihe
  (`FLOOD_INTERVAL_MS`, Nutzervorgabe "vorerst") auf Dauer die richtige
  Steigung sind, entscheidet Playtesting. Die Anzeige der Ultra-Liste
  ist mit
  0.38.0 nachgezogen (Modus-Auswahl unter "Highscores", siehe 4.5), die
  Sprint-Liste mit 0.39.0, die Time-Attack-Liste samt Statistik je
  Modus mit 0.42.0 und die Hochwasser-Liste mit 0.49.0.
- Punktesystem-Feinschliff (Kombos, Back-to-Back?): Nach dem Umbau in
  0.16.0 (nur abgebaute Reihen zaehlen) waeren solche Extras eine
  bewusste Abweichung vom Konzept "Punkte = Reihenwertung" - nur nach
  expliziter Nutzerentscheidung wieder aufgreifen.
- UI-Sprache: erledigt mit 0.48.0. Die frueher feste Mischung (Menues
  Deutsch, HUD und `--help` Englisch) ist einer Uebersetzungsschicht
  gewichen: die Oberflaeche ist vollstaendig ein- und umschaltbar
  zweisprachig (Deutsch/Englisch, siehe 4.11), Diagnosemeldungen nach
  STDERR bleiben englisch. Offen bleibt nur, ob weitere Sprachen
  dazukommen sollen - technisch ist das eine Datei unter `lib/lang/`.

Offene Punkte zum Mehrspieler (Spezifikation siehe Abschnitt 5; alles
Uebrige dort ist entschieden):

- **Siegbedingung im Versus-Modus:** entschieden und umgesetzt
  (Nutzerentscheidung mit 1.1.0). Sie ist **keine Festlegung des
  Spiels mehr, sondern eine der Sitzung**: der Gastgeber waehlt in der
  Lobby zwischen `survival` (wer uebrig bleibt - die Vorgabe),
  `sprint` (die meisten Rows in der Zeit) und `ultra` (wer zuerst am
  Ziel ist), und die Stoerreihen sind ein Schalter daneben, der
  anfangs aus ist (siehe 5.1). Damit ist auch die frueher offene Frage
  nach einem "reinen Rows-Wettkampf ohne Garbage" beantwortet: das ist
  `sprint` bzw. `ultra` mit ausgeschalteten Stoerreihen.
  Offen bleibt nur, welche Modi nach Playtesting dazukommen oder
  wegfallen - die drei sind die, die sich in der Siegbedingung
  unterscheiden.
- **Fremdabhaengigkeit:** entschieden und seit 1.1.0 in Gebrauch
  (Nutzerentscheidung). **`socat` ist gesetzt**, weil die Discovery
  UDP-Broadcast braucht und `socat` als einziges der frueher
  erwogenen Programme Broadcast, TCP und Unix-Socket zugleich kann; die
  Suchreihenfolge ueber `ncat`/`nc -U` und die FIFO-Variante sind damit
  entfallen (siehe 5.2). Es bleibt ein `Recommends` - der Einzelspieler
  laeuft ohne.
- **Wertung von Mehrspieler-Runden:** entschieden und umgesetzt.
  **Weltwunder-Fortschritt und Statistik: ja, aber nur die eigene
  Leistung** - keine Reihe eines Mitspielers, kein Bonus fuer den Sieg
  (Nutzerentscheidung, siehe 5.8). Die zuletzt offene Frage nach der
  **Bestenliste** ist mit 1.1.0 im Sinne der Empfehlung entschieden:
  eine **eigene Liste `highscore-versus`** (siehe 4.5). Die drei Wege
  und warum es dieser wurde:
  - **Eigene Liste `highscore-versus`** (gebaut): dasselbe
    Zeilenformat und dieselbe Rangordnung nach Rows wie Marathon, eine
    sechste Datei neben den fuenf vorhandenen (4.5), jede Runde
    gewertet wie bei Time Attack und Hochwasser - eine
    Mehrspieler-Runde kennt keinen Zustand "unvollstaendig". Es ist
    genau die Entscheidung, die fuer Ultra, Sprint, Time Attack und
    Hochwasser schon getroffen wurde: eine Runde unter anderen Regeln
    gehoert in eine andere Liste. Kosten: eine Datei, ein Eintrag in
    `menu_mode_entries` (der die Modus-Auswahl fuer Einzelspieler,
    Highscores und Statistik ohnehin gemeinsam baut, siehe 3.6), ein
    `HSV_*`-Block in `lib/highscore.sh`.
  - **Mit in die Marathon-Liste:** billiger, aber es mischt zwei
    Ordnungen in eine Tabelle. Garbage schneidet eine Runde ab und
    schenkt ihr zugleich zusaetzliche Reihen zum Abbauen; die Zahlen
    sind schlicht nicht dieselbe Groesse. Genau dagegen wurde die
    Liste fuenfmal aufgeteilt.
  - **Gar nicht werten:** der bisherige Stand der Spezifikation.
    Verliert die Motivation, die eine Bestenliste stiftet, und passt
    schlecht dazu, dass Statistik und Weltwunder die Runde sehr wohl
    zaehlen.
- **Garbage-Werte** (0/1/2/4 Reihen, +2 Silber, +4 Gold, Deckel 10,
  `GARBAGE_*` in `lib/hub.sh`) sind aus der Reihenwertung abgeleitet,
  nicht aus dem Original - "The New Tetris" hat keinen vergleichbaren
  Versus-Modus. Sie stehen seit 1.1.0 im Code und sind bislang nur
  gerechnet, nicht gespielt: nach Playtesting nachjustieren.
- **Zielwahl ab 3 Spielern:** Standard `random`. Ob eine manuelle
  Zielauswahl (Taste) gewuenscht ist, bleibt offen; die Tastenbelegung
  ist voll und die Bedienung skaliert schlecht.
- **Spielerzahl:** entschieden (Nutzerentscheidung, siehe 5.1) -
  **minimal 2, maximal 5, keine Vorgabe dazwischen**, der Host
  entscheidet ueber den Start. Die Obergrenze ist mit 1.3.0 von 6 auf 5
  gesunken (Nutzerentscheidung, Begruendung in 5.1). Offen bleibt nur,
  ob 5 in der Praxis auf
  schwacher Hardware fluessig laeuft - gemessen wurde bisher gegen
  Test-Bots auf einem Rechner, nicht in einem echten Raum voller
  Terminals; die volle Zellenbreite (5.6) verdoppelt dabei die
  Zeichenmenge je Gegnerfeld, was zuerst dort auffallen wird.
- **Demo-Aufzeichnung im Mehrspieler:** entschieden
  (Nutzerentscheidung, siehe 5.20) - **jeder Client zeichnet alle
  Teilnehmer auf** -, aber noch nicht gebaut: es ist der eine offene
  Schritt der Phase 5, und bis dahin wird eine Mehrspieler-Runde
  bewusst gar nicht aufgezeichnet. Offen bleibt eine Folgefrage, die erst das
  Playtesting beantworten kann: die Mitspieler koennen nur so
  aufgenommen werden, wie sie ankamen (Zaehler, und Feld-Schnappschuesse
  nur in Detailstufe 2), weil ihre **Zuege nie uebertragen werden**.
  Die Alternative waere, im Protokoll die Zuege statt der
  Schnappschuesse zu verteilen - das kostet weniger Bandbreite (~40 B/s
  je Spieler statt bis zu 1 kB/s), liefert exakte Gegnerfelder in jeder
  Detailstufe und macht die Demo durchgehend zugbasiert, verlangt aber
  von **jedem** Client, bis zu fuenf fremde Runden mitzusimulieren.
  Genau diese Rechenlast war der Grund fuer die Schnappschuesse (5.6),
  weshalb die Spezifikation bei ihnen bleibt; ob die Bash-Simulation
  wirklich zu teuer ist, laesst sich mit dem Test-Bot messen, sobald
  Schritt 6 steht.
- **Kein Reconnect in v1** (5.8). Falls sich Abbrueche im Alltag haeufen,
  waere ein Wiedereinstieg mit vollstaendiger Zustandsuebertragung ein
  eigener spaeterer Punkt.
- **Anti-Cheat:** bewusst nur Hub-Autoritaet ueber Garbage-Mengen und
  Rundenende (5.4). Ein manipulierter Client kann falsche `CLEAR`s
  melden; eine serverseitige Vollsimulation ist kein Ziel. Die
  Sicherheitsregeln in 5.5 schuetzen dagegen die Prozesse und Terminals
  der Mitspieler - dieser Teil ist nicht verhandelbar.

Offene Punkte zum Server-Betrieb (Phase 6, Spezifikation siehe 5.11-5.19):

- **Unix-Accounts vs. eigenes Kontosystem:** Empfehlung in 5.12 ist ein
  vom SSH-Login entkoppeltes Spielkonto (Bindung an
  SSH-Key-Fingerprint, keine Unix-Accounts je Spieler). Bestaetigung
  ausstehend.
- **Backend-Sprache:** Empfehlung in 5.15 ist, Spiel-Engine und lokales
  Mehrspieler-Protokoll bei Bash zu belassen, aber fuer Web/Liga/
  Multi-Server einen schlanken separaten Dienst in einer HTTP-/JSON-/
  DB-tauglicheren Sprache vorzusehen. Sprache selbst noch offen;
  Bestaetigung ausstehend, ob dieser Schnitt so gewuenscht ist.
- **Server-Persistenz:** Empfehlung in 5.13 ist SQLite als
  Zwischenschritt vor einem "richtigen" Datenbankserver (erst bei
  Multi-Server-Bedarf, 5.14). Bestaetigung ausstehend.
- **Liga-Regeln:** komplett offen (Saisonlaenge, Punkteverfall,
  Ranglisten je Modus), siehe 5.14.
- **Serverweites Weltwunder:** Nutzervorschlag (5.17), zu bestaetigen.
  Offen: eigene, groessere Wunder-Liste oder dieselbe Liste mit
  hoeherer Kostentabelle (`SERVER_WONDER_COSTS`); ob ein
  fertiggestelltes Server-Wunder allen verbundenen Clients angekuendigt
  wird.
- **Weltwunder-Animation:** Nutzerwunsch (5.18) nach mehr Bewegung im
  Wunder-Bildschirm. Offen: eigener `.cast`-Player zur Laufzeit oder
  eine von Hand aus einer asciinema-Voraufnahme abgeleitete
  Frame-Tabelle (letzteres ist der Vorschlag, weil es ohne neue
  Abhaengigkeit auskommt).
- **Account-Abzeichen:** Nutzerwunsch (5.19). Offen: konkrete
  Abzeichen-Liste und ihre Bedingungen, Verhaeltnis zum spaeteren
  Liga-System.
