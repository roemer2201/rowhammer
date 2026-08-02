# CLAUDE.md - rowhammer

Diese Datei gibt Claude Code (und menschlichen Mitwirkenden) den Kontext,
das Konzept und die Arbeitsregeln fuer dieses Repository.

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
- Die 7 Standard-Bausteine (I, O, T, S, Z, J, L) mit **7-Bag-Randomizer**
  (jede Sorte genau einmal pro 7er-Beutel, dann neu mischen).
- Steuerung (Standardbelegung; ueber das Einstellungsmenue aenderbar und
  in der Nutzer-Konfigurationsdatei gespeichert, siehe 4.5):
  - Links/Rechts: Pfeiltasten (seit 0.31.0 ohne Buchstabentaste)
  - Rotation: `d` (im Uhrzeigersinn), `a` (gegen Uhrzeigersinn)
  - Soft-Drop: `s` bzw. Pfeil runter
  - Hard-Drop: Leertaste und Pfeil hoch (seit 0.31.0 ohne
    Buchstabentaste)
  - Hold: `c` bzw. `w`
  - Pause: `p`; `Esc`/`x` oeffnet das Pausenmenue (seit 0.12.0, Issue
    #12): Fortsetzen, Ins Hauptmenue (Runde pausiert, wieder aufnehmbar
    ueber den Eintrag "Fortsetzen", der dann im Hauptmenue und im
    Einzelspieler-Menue an erster Stelle steht) oder Runde beenden
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
  1. Maya-Tempel / Chichen Itza (100)
  2. Stonehenge (200)
  3. Sphinx von Gizeh (400)
  4. Pantheon, Rom (800)
  5. Chinesische Mauer (1600)
  6. Taj Mahal (3200)
  7. Basilius-Kathedrale, Moskau (6400)
  Chinesische Mauer und Taj Mahal fuellen die zwei nicht verifizierbaren
  Plaetze. Die Kosten verdoppeln sich je Wunder (grob geometrisch wie im
  Original), sind aber auf Einzelrechner-Spielzeit herunterskaliert
  (12.700 gewichtete Reihen insgesamt statt 500.000 Zeilen).
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
  Game Over, "Runde beenden" im Pausenmenue oder - falls noch eine
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
    "Goal" und "Left" - aber nur, solange eine Ultra-Runde laeuft; im
    normalen Spiel bleiben alle acht Zeilen frei (siehe 3.6).
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
"Beenden" und erklaert das Spiel auf fuenf Info-Bildschirmen
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

1. Spielprinzip: Bausteine, volle Reihen als "Rows", 7-Bag,
   Level/Tempo, Rundenende.
2. Steuerung: alle Aktionen mit ihren aktuellen Tasten, dazu die
   Menue-Bedienung und `r` im Game-Over-Bild.
3. Vorschau ("Next") und Hold (ein Tausch je Zug).
4. Gold-/Silber-Quadrate und die Reihenwertung (Werte aus
   `ROWS_NORMAL`/`ROWS_SILVER`/`ROWS_GOLD`/`ROWS_TETRIS`, siehe 3.2).
5. Weltwunderbau mit der Kostentabelle aus `lib/wonders.sh`.

Zwei Teile werden bewusst aus dem laufenden Zustand gelesen statt
ausgeschrieben, damit die Anleitung nicht luegen kann: die
Tastenbelegung (`menu_help_keys` setzt die konfigurierbare Taste vor die
fest verdrahteten Sekundaertasten, laesst `NONE` weg und vermeidet
Dubletten wie `KEY_HARD=SPACE` neben der Leertaste) und die Wunder-Namen
samt Kosten. Jeder Bildschirm bleibt in den 46 Zeichen Breite und den
`MENU_BODY_MAX` Zeilen, die ein 48x22-Terminal laesst.

Noch offen: die Anleitung kennt die Spielmodi aus 3.6 noch nicht (die
fuenf Seiten stammen aus der Zeit, als es nur die endlose Runde gab).
Eine sechste Seite "Spielmodi" gehoert nachgezogen, sobald auch Sprint
steht - dann lassen sich beide Modi auf einer Seite erklaeren, statt die
Seite zweimal umzubauen.

### 3.6 Spielmodi (Ultra seit 0.34.0)

Das Einzelspieler-Menue waehlt den Modus der Runde; der gewaehlte Name
geht als Argument an `game_run` und liegt waehrend der Runde in
`GAME_MODE` (Rundenzustand in `rowhammer.sh`, bleibt ueber
Pausieren/Fortsetzen erhalten - eine ins Hauptmenue gelegte Runde kommt
im Modus zurueck, in dem sie gestartet wurde).

- **Marathon** (`marathon`; bis 0.34.1 "Normales Spiel"/`normal` -
  Nutzerentscheidung, an den in anderen Tetris-Spielen ueblichen Namen
  fuer den endlosen Modus angeglichen): die endlose Runde wie bisher,
  Ende durch Game Over.
- **Ultra** (`ultra`, Nutzerwunsch): Wettlauf gegen die Uhr -
  `ULTRA_TARGET_ROWS` (150) **Rows** so schnell wie moeglich abbauen.
  Die Runde endet in dem Moment, in dem die Wertung das Ziel erreicht
  oder ueberschreitet; das Ergebnis ist die Spielzeit.
- **Sprint** (geplant, siehe Roadmap): in 3 Minuten moeglichst viele
  Reihen. Noch nicht umgesetzt.

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
    highscore.sh       # Persistente Highscore-Liste (Top 10)
    wonders.sh         # Weltwunder-Logik, Baustufen, Fortschritt
    save.sh            # Laden/Speichern des Spielstands
    stats.sh           # Persistente Spielstatistik (Reihen, Bonusreihen, Bloecke)
    net.sh             # (Phase 5) Transport: Unix-Socket, Zeilenrahmung, Limits
    proto.sh           # (Phase 5) Nachrichtentabelle, Parser mit Validierung
    hub.sh             # (Phase 5) Sitzungslogik des Hubs (Lobby, Garbage, KO)
    mp.sh              # (Phase 5) Client-Seite: Lobby, Peer-Zustaende, Anbindung
  assets/
    wonders/           # ASCII-Art je Wunder und Baustufe
  Makefile             # install/uninstall-Ziele (genutzt von deb, spaeter rpm)
  build-deb.sh         # Baut das Debian-Paket, Artefakte nach dist/
  debian/              # Debian-Paketierung (debhelper, natives Paket)
  CLAUDE.md
  README.md
```

Stand (Version 0.23.0): alle Module aus dem Baum oben existieren mit
Ausnahme der vier mit "(Phase 5)" markierten Mehrspieler-Module, die
bislang nur spezifiziert sind (siehe Abschnitt 5)
(`rowhammer.sh`, `lib/*.sh` inklusive `wonders.sh`, `save.sh` und
`stats.sh` sowie
`assets/wonders/` mit einer Art-Datei je Wunder). Die Anwendung
startet in einem Menue (Einzelspieler / Mehrspieler-Platzhalter /
Highscores / Weltwunder / Statistik / Einstellungen / Anleitung /
Beenden;
solange eine pausierte Runde wartet, zusaetzlich "Fortsetzen" an
erster Stelle, ebenso im Einzelspieler-Untermenue). Das
Einzelspieler-Untermenue waehlt seit 0.34.0 den Spielmodus
("Marathon" oder "Ultra", siehe 3.6; der endlose Modus hiess bis
0.34.1 "Normales Spiel"); die
Menue-Beschriftung
ist bewusst Deutsch (ASCII), Code und Code-Ausgaben bleiben Englisch.
Das Spielfeld haelt je Zelle drei parallele Arrays (Sorte `BOARD`,
Instanz-ID `BOARD_ID`, Quadrat-Status `BOARD_SQ`); der HUD-Zaehler
"Rows" ist die gewichtete Reihenwertung (1/5/10), die den
Weltwunder-Fortschritt speist und seit 0.16.0 zugleich der Score der
Runde ist (siehe 3.2), "Lines" zaehlt physische Reihen und
treibt das Level. CLI-Optionen bisher: `--seed N` (`ROWHAMMER_SEED`)
fuer reproduzierbare Teilfolgen, `--name NAME` (`ROWHAMMER_PLAYER_NAME`),
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
`--reset config|stats|highscore|save|all` (`ROWHAMMER_RESET`, seit
0.35.0, siehe 4.8),
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
  blieb (frueher hatte der naechste Voll-Frame es uebermalt). Einzige
  Ausnahme ist die Namensabfrage (`prompt_player_name`), die fuer ihren
  zeilenweisen `read` per `term_input_line` in den kanonischen Modus mit
  Echo zurueckschaltet und danach wieder `term_input_raw` setzt.
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
  "resize me"-Overlay, bis das Terminal wieder gross genug ist (siehe
  Phase 4 "Anpassung an Terminalgroesse").
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
  `render_flush`, "resize me"-Overlay, Resize ueber `layout_update`, die
  echoende Namensabfrage ueber `render_menu_dirty`); dann loescht der
  naechste Menue-Frame zuerst den ganzen Bildschirm. Nach einem Resize
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
  Highscore-Liste `highscore`, die Ultra-Bestenliste `highscore-ultra`
  (seit 0.34.0, siehe 3.6), der Spielstand `save` und die
  Statistik `stats`.
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
  (Spielername, Farbschema seit 0.21.0, Tastenbelegung) schreibt
  `${DATA_DIR}/rowhammer.conf`;
  Werte werden validiert und single-quoted geschrieben, da die Datei
  gesourct wird. Das Farbschema wird als `COLOR_THEME='...'` gespeichert
  und beim Laden gegen die bekannten Schemata validiert (unbekannt =
  Abbruch mit Meldung).
- `lib/highscore.sh` (seit 0.7.0): Top 10 abgeschlossener Runden in
  `${DATA_DIR}/highscore`, eine Zeile je Eintrag im Format
  `rows|lines|level|name|date|gold|silver|time|rowhammers|pieces`,
  absteigend nach Rows
  sortiert. Seit dem Punktesystem-Umbau (0.16.0) ist die gewichtete
  Reihenwertung der einzige Score: das fruehere fuehrende
  `score`-Feld entfaellt, Rows bestimmt die Rangfolge und den Rang
  im Game-Over-Bild. Das Feld `time` (seit 0.17.0) ist
  die Spielzeit der Runde in ganzen Sekunden, `rowhammers` (seit
  0.25.0) die Zahl der Vierfach-Abbaeue der Runde und das
  abschliessende Feld `pieces` (seit 0.27.0) die Zahl der abgelegten
  Teile.
  Seit 0.29.0 (Nutzerentscheidung, bewusste Ausnahme von der
  Arbeitsregel "keine Abwaertskompatibilitaet"): eine Zeile muss nicht
  mehr alle zehn Felder tragen. Akzeptiert werden 5, 7, 8, 9 oder 10
  Felder - genau die Laengen, die das Format seit dem Punktesystem-
  Umbau (0.16.0, Rows fuehrend) beim schrittweisen Anhaengen von
  Gold/Silber, Zeit, Rowhammer und Pieces tatsaechlich durchlaufen hat
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
  rangieren hinter dem aelteren Eintrag). Der erreichte Rang erscheint im Game-Over-Bild,
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
  `time|rows|lines|level|name|date|gold|silver|rowhammers|pieces`,
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
  wuerden; angezeigt wird das spaeter ueber `fmt_duration_ms` als
  MM:SS.mmm. Gespeichert werden nur Laeufe, die das Ziel erreicht haben
  (Entscheidung in 3.6). Es gilt die uebliche Arbeitsregel "keine
  Abwaertskompatibilitaet": genau zehn Felder, jede andere Zeile faellt
  bei der Validierung heraus - die Kulanz der Normal-Liste
  (`HS_FIELD_COUNTS`) gibt es hier nicht, weil das Format neu ist und nie
  in einer kuerzeren Fassung existiert hat. Eine Anzeige gibt es noch
  nicht (Nutzerentscheidung: erst die Speicherung); der erreichte Rang
  steht bereits im Rundenende-Kasten.
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
  22-Zeilen-Bildschirm und wird von `menu_pages` (`lib/menu.sh`)
  seitenweise gezeigt - fuenf Eintraege je Seite, Tabellenkopf auf
  jeder Seite wiederholt, Seitenzaehler im Titel.
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
  Null-Pruefung). Anzeige ueber den Hauptmenuepunkt
  "Statistik", seit 0.27.0 auf **zwei Bildschirmen**: erst die
  Gesamtzaehler (inklusive der gewichteten Gesamtsumme Lines + Bonus,
  des Rowhammer-Zaehlers, der abgelegten Teile, der Gesamtspielzeit als
  H:MM:SS und der daraus berechneten Steine/Minute), dann die letzten
  drei Spiele mit je zwei Zeilen (Datum, Rows, Reihen, Bonus / Gold,
  Silb, RH, PCS, PPM). Beides zusammen passt nicht mehr in die 18
  Zeilen, die ein 22-Zeilen-Terminal einem Info-Bildschirm laesst
  (`MENU_BODY_MAX` in `lib/menu.sh`; bis 0.27.0 waren es 17 - die
  zentrierten Bildschirme aus 0.28.0 brauchen keine Zeile mehr fuers
  Freiraeumen der obersten Bildschirmzeile) - deshalb der Schnitt statt
  gestrichener Spalten. Jede Zeile bleibt in den 46 Zeichen, die der
  Zwei-Zeichen-Einzug vom 48-Spalten-Minimum uebriglaesst.
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
  - `input.log`: jeder Tastendruck mit Rohbytes (`printf %q`-quotiert)
    und gemapptem Symbol; auch nicht zuordenbare Escape-Sequenzen.
  - `events.log`: Session-Header (Version, Bash, Terminal, Seed,
    Spieler, Tastenbelegung, geladene Config-Dateien) und alle
    Aktionen: Spawns samt Queue, Bewegungen/Rotationen (inklusive
    blockierter Versuche), Gravitations-Fall, Locks, Quadrat-Bildung
    mit Instanz-IDs, Reihenabbau mit Credit-Aufschluesselung je Reihe,
    Hold, Pause, Bag-Refills, Menuewahl, Config-Speicherungen, fatale
    Fehler sowie ein Board-Snapshot (Typ- und Quadrat-Gitter plus
    cut/squared-Instanzlisten) nach jedem Lock.
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
- **RPM (geplant):** Spec-Datei soll dasselbe `make install`
  wiederverwenden; gleiche Pfade (`/usr/share/rowhammer`, `/usr/games`).
- Hinweis: Das Repository hat noch keine Lizenzdatei;
  `debian/copyright` ist entsprechend als "UNLICENSED" markiert und muss
  nachgezogen werden, sobald eine Lizenz festgelegt ist.

### 4.8 Reset persistenter Daten (seit 0.35.0)

`--reset TARGET` (`ROWHAMMER_RESET`) loescht gezielt persistente Dateien
im Datenverzeichnis (siehe 4.5) und beendet das Programm, statt ins
Menue zu starten. Ziele:

| TARGET | geloeschte Dateien |
| --- | --- |
| `config` | `rowhammer.conf` |
| `stats` | `stats` |
| `highscore` | `highscore` **und** `highscore-ultra` |
| `save` | `save` (Weltwunder-Fortschritt) |
| `all` | alle fuenf Dateien |

Entscheidungen zu den beiden in der Roadmap offen gelassenen Punkten:

- **`all` loescht auch das Savegame.** "Alles" heisst alles; wer nur den
  Weltwunder-Fortschritt zuruecksetzen will, hat dafuer das eigene Ziel
  `save` (der in der Roadmap angedachte Wert), das die uebrigen Dateien
  unangetastet laesst.
- **`highscore` trifft beide Bestenlisten.** Endlos- und Ultra-Liste
  (seit 0.34.0, siehe 4.5) sind dieselbe Art Daten; eine davon stehen zu
  lassen waere ueberraschend, und ein eigenes Ziel je Liste waere fuer
  einen Reset zu fein.

Ablauf und Einordnung:

- **Kein Config-Wert.** Praezedenz Standard < Env < CLI wie beim
  Datenverzeichnis und den Debug-Schaltern. Die Config-Datei ist eines
  der Reset-Ziele - wuerde der Reset von dort gelesen, koennte sich eine
  Datei bei jedem Start selbst loeschen lassen.
- **Zeitpunkt:** direkt nach dem Sourcen der Module (die Dateinamen
  kommen aus den Modulen, die sie besitzen: `CONFIG_NAME`,
  `STATS_FILE_NAME`, `HS_FILE_NAME`/`HSU_FILE_NAME`, `SAVE_FILE_NAME`)
  und **vor** der TTY-Pruefung. Die TTY-Pruefung ist dafuer aus dem
  Prerequisites-Block nach unten gewandert: ein Reset loescht nur
  Dateien und darf deshalb auch aus einem Skript oder einer CI-Umgebung
  ohne Terminal laufen. Das Terminal wird nie angefasst (kein
  Alternate-Screen, kein Rohmodus).
- **Sicherheitsabfrage:** an einem Terminal listet `reset_run` erst die
  betroffenen Pfade und fragt dann nach; wie bei `menu_confirm` ist
  "nein" die Vorgabe (leere Antwort, EOF oder alles ausser `y`/`yes`
  bricht ab). Ohne TTY entfaellt die Abfrage, weil ein wartendes `read`
  den Aufrufer haengen liesse. Die Abfrage ist bewusst ein einfaches
  `read` statt `menu_confirm`: letzteres braucht Alternate-Screen,
  Rohmodus und `render_menu_frame`, also genau das, was der Reset nicht
  aufbaut.
- Nicht vorhandene Dateien sind kein Fehler (Ziel bereits erreicht) und
  werden nur gemeldet; eine vorhandene Datei, die sich nicht loeschen
  laesst, bricht mit Fehlermeldung ab.

## 5. Multiplayer (Phase 5, spezifiziert - noch nicht umgesetzt)

Dieser Abschnitt ist die **Spezifikation**; im Code existiert bislang nur
der Platzhalter-Menuepunkt. Die Umsetzung erfolgt schrittweise nach der
Reihenfolge in Abschnitt 7, Phase 5. Jeder Schritt dort verweist auf die
hier festgelegten Regeln.

Leitentscheidung: **lokales Mehrspieler-Spiel auf einem gemeinsamen Host**
ueber einen **Unix-Domain-Socket** (Nutzerwunsch). Typisches Szenario:
mehrere Leute sind per SSH auf derselben Maschine angemeldet und spielen
gegeneinander. Ein Netzwerk-Transport (TCP) ist damit ausdruecklich **nicht**
Teil von Phase 5; das Protokoll wird aber so entworfen, dass ein
TCP-Transport spaeter nur eine weitere Implementierung derselben
Transport-Schnittstelle ist (siehe 5.3).

### 5.1 Spielerzahl und Spielmodus

- **Standard: 2 bis 4 Spieler**, technisches Maximum **6**
  (`--mp-max N`, Standard 4). Begruendung fuer die Obergrenze:
  - Rechenaufwand: Bash rendert jeden Frame als String; jedes zusaetzliche
    Gegnerfeld kostet ~200 Zellen pro Frame. Ab etwa 6 Feldern ist die
    Framerate auf schwachen Terminals/Hosts nicht mehr zu halten.
  - Bildschirmbreite: ein Mini-Feld braucht 13 Spalten (siehe 5.6);
    bei 4 Gegnern sind das 87 Spalten - schon mehr als die uebliche
    80-Spalten-Breite.
  - Garbage-Zielwahl wird ab ~4 Spielern ohne Zielauswahl-UI beliebig.
  - Mehr als 6 Spieler waeren nur noch als reines Scoreboard sinnvoll;
    das ist bewusst kein Ziel.
- **Modus:** "Versus" - jeder Spieler hat sein eigenes 10x20-Feld, alle
  starten mit demselben Seed (identische 7-Bag-Folge, Fairness).
  Abgebaute Reihen erzeugen Stoerreihen ("Garbage") beim Gegner
  (siehe 5.7). Wer oben rausbaut (Top-Out), scheidet aus und wird
  Zuschauer; wer als Letzter uebrig ist, gewinnt (siehe 5.8).
- Das Quadrat-System bleibt unveraendert die Kernmechanik: Gold- und
  Silber-Quadrate sind im Versus-Modus die staerksten Angriffe.
- Ein spaeterer kooperativer Modus oder ein reiner "Race"-Modus (wer
  zuerst N Reihen hat) ist denkbar, aber nicht Teil dieser Spezifikation.

### 5.2 Transport: Unix-Domain-Socket

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
- **Bash kann kein AF_UNIX.** `/dev/tcp` deckt nur TCP ab, es gibt kein
  eingebautes Socket-Primitiv. Deshalb braucht der Mehrspieler-Modus
  **genau ein** externes Hilfsprogramm, in dieser Reihenfolge gesucht:
  1. `socat` (bevorzugt: `UNIX-LISTEN:...,fork` und `UNIX-CONNECT:...`)
  2. `ncat --unixsock` (nmap)
  3. `nc -U` (OpenBSD-netcat; BusyBox-nc kann es nicht)
  Fehlt alles drei, bleibt der Menuepunkt sichtbar, zeigt aber einen
  Hinweis mit den Paketnamen und kehrt zurueck. Der Einzelspieler bleibt
  ohne jede neue Abhaengigkeit lauffaehig; im Debian-Paket wird `socat`
  als `Recommends` eingetragen (kein `Depends`).
- **Alternative ohne Fremdprogramm (dokumentiert, nicht Standard):**
  benannte Pipes (`mkfifo`, Coreutils) - ein Inbox-FIFO fuer den Hub
  plus ein Downstream-FIFO je Client. Funktioniert lokal genauso, ist
  aber fragiler (mehrere Schreiber auf einem FIFO sind nur bis
  `PIPE_BUF` = 4096 Byte atomar, kein sauberes EOF beim Absturz eines
  Clients). Wird nur aufgegriffen, falls sich die Hilfsprogramm-
  Abhaengigkeit als Problem herausstellt. Die Nachrichtenlaenge wird
  trotzdem auf 512 Byte begrenzt (siehe 5.4), damit dieser Fallback
  ohne Protokollaenderung moeglich bleibt.

### 5.3 Prozessmodell

Drei Rollen, strikt getrennt:

- **Client** (`rowhammer.sh`, ein Prozess je Spieler und Terminal):
  spielt die eigene Runde, rendert, sendet den eigenen Zustand, empfaengt
  Gegnerzustand und Garbage. Der Client haelt die Verbindung als
  **Coprocess**: `coproc MP_LINK { socat UNIX-CONNECT:"${sock}" -; }`.
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
  nie den Hub blockiert und umgekehrt.
- **Bridge** (`rowhammer.sh --mp-bridge`, ein kurzlebiger Prozess je
  Verbindung): wird von `socat UNIX-LISTEN:...,fork` gestartet, hat die
  Socket-Enden auf STDIN/STDOUT und uebersetzt zwischen Socket und den
  FIFOs des Hubs (Client -> `inbox`-FIFO mit vorangestellter Client-ID,
  Hub -> privates `down.<id>`-FIFO -> Socket). So spricht der Hub nur
  mit FIFOs (Bash-nativ) und `socat` nur mit dem Socket; ein Wechsel des
  Transports (TCP, FIFO-Only) tauscht ausschliesslich die Bridge aus.

Modulschnitt (neue Dateien, siehe auch 4.2):

- `lib/net.sh` - Transport und Rahmung: Hilfsprogramm-Erkennung,
  Verbindungsauf-/abbau, Zeilen senden/empfangen, Laengen- und
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

### 5.4 Protokoll v1

- **Rahmen:** eine Nachricht = eine Zeile, `\n`-terminiert, reines
  druckbares ASCII (0x20-0x7E), maximal **512 Byte** inklusive Zeilenende.
  Felder durch **ein Leerzeichen** getrennt, erstes Feld ist das Verb in
  Grossbuchstaben. Unbekannte Verben werden ignoriert (Vorwaerts-
  kompatibilitaet), fehlerhafte Zeilen fuehren zum Verbindungsabbruch
  (siehe 5.5).
- **Versionierung:** `PROTO_VERSION=1`. Der Hub lehnt abweichende
  Versionen im `HELLO` mit `ERR proto ...` ab. Gemaess der Arbeitsregel
  "keine Abwaertskompatibilitaet" wird das Protokoll bei Bedarf
  hochgezaehlt statt kompatibel erweitert.
- **Client -> Hub**

  | Nachricht | Felder | Bedeutung |
  | --- | --- | --- |
  | `HELLO` | `<proto> <name> <caps>` | Anmeldung; `caps` = Komma-Liste (z. B. `board`) |
  | `READY` | `<0 oder 1>` | Bereitschaft in der Lobby |
  | `STATE` | `<lines> <rows> <level> <gold> <silver> <height> <pending>` | eigener Zaehlerstand, bei Aenderung, max. 10/s |
  | `BOARD` | `<200 Zeichen>` | Feld-Snapshot, nur wenn der Hub `NEEDBOARD 1` gesetzt hat, max. 5/s |
  | `CLEAR` | `<lines> <silver> <gold>` | ein Reihenabbau als Angriffs-Meldung (Hub rechnet daraus die Garbage aus) |
  | `TOPOUT` | - | eigenes Game Over |
  | `PONG` | `<token>` | Antwort auf `PING` |
  | `BYE` | - | geordnetes Verlassen |

- **Hub -> Client**

  | Nachricht | Felder | Bedeutung |
  | --- | --- | --- |
  | `WELCOME` | `<slot> <proto> <maxplayers>` | Anmeldung akzeptiert |
  | `ROSTER` | `<slot> <name> <ready> <state>` | eine Zeile je Spieler, bei jeder Aenderung |
  | `SEED` | `<seed>` | gemeinsamer Seed fuer die 7-Bag-Folge |
  | `START` | `<countdown_ms>` | Rundenstart |
  | `PEER` | `<slot> <lines> <rows> <level> <gold> <silver> <height> <pending> <state>` | Zustand eines Mitspielers |
  | `PEERBOARD` | `<slot> <200 Zeichen>` | Feld-Snapshot eines Mitspielers |
  | `NEEDBOARD` | `<0 oder 1>` | ob dieser Client Snapshots senden soll (spart Last, wenn niemand Stufe 2 anzeigt) |
  | `GARBAGE` | `<count> <hole>` | eingehende Stoerreihen, Lochspalte 0-9 |
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

### 5.5 Sicherheit

Bedrohungsmodell: Mitspieler auf demselben Host sind **halb
vertrauenswuerdig**. Sie duerfen im Spiel schummeln koennen (das ist
hinnehmbar), aber unter keinen Umstaenden

1. Code im Prozess eines anderen Spielers ausfuehren,
2. dessen Terminal uebernehmen oder Dateien beschaedigen,
3. den fremden Prozess zum Absturz oder Haengen bringen.

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
- **Dateisystem:** `umask 0077` fuer alle Sitzungsdateien; das
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
  Hub- und Client-Parser. Abnahmekriterium: kein Prozess stirbt, kein
  Befehl wird ausgefuehrt, kein Byte ausserhalb 0x20-0x7E erreicht das
  Terminal.

### 5.6 Darstellung der Mitspieler

Das bestehende Layout ist fest: linke Spalte 12 + 1 Abstand + Feld 22 +
1 Abstand + rechte Spalte 12 = 48 Spalten, 22 Zeilen Minimum (seit
0.22.0 zentriert, seit 0.26.0 ohne Statuszeilen, siehe 3.4). Die
Mitspieler kommen **rechts daneben**,
das eigene Feld bleibt unveraendert an seinem Platz; der Block wird dann
entsprechend breiter zentriert. Wo unten "Seitenleiste" steht, ist die
rechte Spalte gemeint (die linke traegt seit 0.26.0 Hold und die
eigenen Rundenzaehler und ist damit belegt).

Drei Detailstufen, automatisch nach verfuegbarer Terminalgroesse und
Spielerzahl gewaehlt (`--mp-view auto|full|compact|score` erzwingt eine
Stufe):

- **Stufe 2 "full" - Mini-Feld je Gegner.** Ein Zeichen pro Zelle
  (das eigene Feld nutzt zwei), also 10 Spalten Inhalt + Rahmen = 12,
  plus 1 Spalte Abstand = **13 Spalten je Gegner**, 22 Zeilen hoch
  (Kopfzeile mit Name/Slot, 20 Feldzeilen, Fusszeile mit
  `Rows`/`pending`). Farben wie im eigenen Feld (Gold/Silber bleiben
  erkennbar, Garbage dunkelgrau). Bedarf: `48 + n*13` Spalten -
  61 (2 Spieler), 74 (3), 87 (4), 113 (6).
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

1. Reicht `48 + n*13` Spalten und 22 Zeilen -> Stufe 2.
2. Sonst: reichen `22 - belegte Seitenleistenzeilen` fuer `2*n` Zeilen
   -> Stufe 1.
3. Sonst -> Stufe 0. Unter 48x22 greift weiterhin die bestehende
   "resize me"-Overlay.

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
- **Sieg:** letzter lebender Spieler. Steigen alle bis auf einen aus, ist
  die Runde vorbei (`END <slot>`). Bei gleichzeitigem KO entscheidet die
  hoehere Rows-Zahl, danach der niedrigere Slot.
- **Verbindungsabbruch eines Clients:** EOF oder 6 s ohne `PONG` ->
  Status `gone`, gilt wie ein KO, die Runde laeuft weiter. Kein
  Reconnect in v1 (Zustandsuebertragung waere aufwendig; die Runde
  dauert wenige Minuten).
- **Ausfall des Hubs:** alle Clients bekommen EOF, zeigen "Verbindung
  verloren" und kehren ins Hauptmenue zurueck. Die Runde wird wie ein
  abgebrochenes Spiel behandelt und gemaess 3.3 gewertet (abgebrochene
  Runden zaehlen).
- **Verlassen ueber das Menue:** wie im Einzelspieler beendet "Runde
  beenden" die Runde; zusaetzlich geht ein `BYE` raus. Eine
  Mehrspieler-Runde kann **nicht** ins Hauptmenue gelegt und spaeter
  fortgesetzt werden (die anderen warten nicht) - der Eintrag "Ins
  Hauptmenue" fehlt im Mehrspieler-Pausenmenue.
- **Pause:** eine echte Pause gibt es im Mehrspieler nicht. `p` zeigt nur
  eine lokale Einblendung, das Spiel laeuft weiter; das Pausenmenue
  (`Esc`/`x`) bietet "Fortsetzen" und "Runde verlassen". Das muss im HUD
  deutlich stehen, sonst ist es eine Falle.
- **Wertung und Persistenz:** die abgebauten Reihen einer
  Mehrspieler-Runde zaehlen wie im Einzelspieler auf den
  Weltwunder-Zaehler und in die Statistik ein (es sind echte Reihen).
  Die Highscore-Liste bleibt dem Einzelspieler vorbehalten, damit
  Garbage-beeinflusste Runden die Bestenliste nicht verzerren; die
  Statistik bekommt stattdessen eigene Zaehler (Siege, Teilnahmen,
  gesendete/erhaltene Garbage). -> Entscheidung noch zu bestaetigen,
  siehe Abschnitt 8.

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
- **Debug-Modus:** neue Datei `net.log`; `events.log` bekommt
  Mehrspieler-Ereignisse (Join/Leave, Garbage rein/raus, KO, Hub-Start).
- **Paketierung:** `socat` als `Recommends`; `make install` unveraendert.

### 5.10 CLI und Konfiguration

Neue Optionen (jeweils auch als Umgebungsvariable, Praezedenz
Standard < Config < Env < CLI, wie in Abschnitt 6 gefordert):

| Option | Umgebung | Bedeutung |
| --- | --- | --- |
| `--mp-host [NAME]` | `ROWHAMMER_MP_HOST` | Sitzung eroeffnen (Standardname = Benutzername) |
| `--mp-join NAME` | `ROWHAMMER_MP_JOIN` | Sitzung beitreten |
| `--mp-dir DIR` | `ROWHAMMER_MP_DIR` | Sitzungsverzeichnis (siehe 5.2) |
| `--mp-max N` | `ROWHAMMER_MP_MAX` | Spielerzahl 2..6, Standard 4 |
| `--mp-view MODE` | `ROWHAMMER_MP_VIEW` | `auto`, `full`, `compact`, `score` |
| `--mp-target MODE` | `ROWHAMMER_MP_TARGET` | `random`, `all`, `even` (nur Host) |
| `--mp-hub` | - | interner Modus: Hub-Prozess (nicht dokumentiert im Menue) |
| `--mp-bridge` | - | interner Modus: Socket-Bridge |
| `--mp-bot` | `ROWHAMMER_MP_BOT` | Testclient ohne Terminal, spielt zufaellig |

Menuefuehrung: "Mehrspieler" -> "Spiel eroeffnen" / "Spiel beitreten"
(Liste der gefundenen Sitzungen im `MP_DIR`, Name + Spielerzahl aus
einer `INFO`-Abfrage) / "Zurueck". Danach eine Lobby mit Spielerliste,
Bereitschaftsstatus und - fuer den Host - Zielwahl-Modus und Start.

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
  `WONDER_COSTS`-Reihe (100..6400, insgesamt 12.700 Reihen, siehe 3.3)
  ist auf Einzelrechner-Spielzeit herunterskaliert und waere von vielen
  gleichzeitig spielenden Accounts binnen Stunden durchgespielt. Der
  Server-Fortschritt braucht **eine eigene, deutlich groessere
  Kostentabelle** (`SERVER_WONDER_COSTS`) - naeher an der
  Original-Groessenordnung (2.500 bis 500.000 Zeilen je Wunder, siehe
  3.3) oder sogar darueber, je nach erwarteter Serverlast. Beide
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
  bereits fuer die README-Democlips genutzt, siehe Phase 4 "README mit
  Screenshots/Asciinema aktualisieren") je Wunder-Uebergang, die beim
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

## 6. Konventionen fuer alle Skripte

Fuer **jedes** Bash-Skript in diesem Repo gelten verbindlich die
**Script-Konventionen** (Skill `script-conventions`). Insbesondere:

- Header-Kommentarblock mit Beschreibung, Programmablaufplan (bei laengeren
  Skripten), Nutzung und SemVer-Version mit Datum.
- Kommentare, Strings und Ausgaben in **Englisch**, **nur ASCII**.
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

Arbeitsregel: **Keine Abwaertskompatibilitaet noetig.** Das Projekt wird
sequenziell entwickelt und war nie anderswo installiert; Migrationslogik
fuer alte Config-/Savegame-Formate oder alte Schnittstellen ist unnoetig
und soll weggelassen werden. Formate duerfen bei Bedarf einfach brechen.

Arbeitsregel: **Aenderungen an der ToDo-Liste (Abschnitt 7) duerfen
direkt auf dem `main`-Branch vorgenommen werden**, auch ohne eigenen
Feature-Branch oder Pull Request.

## 7. Roadmap / Todo-Liste

### Phase 1 - Spielbarer Kern (umgesetzt, Version 0.1.0)

- [x] Projektgeruest anlegen (`rowhammer.sh`, `lib/`-Module, Header nach Konvention)
- [x] Terminal-Handling: Raw-Mode, alternativer Screen-Buffer, sauberes
      Aufraeumen per `trap`
- [x] Nicht-blockierender Input inkl. Pfeiltasten-Escape-Sequenzen
- [x] Spielfeld-Datenmodell und Kollisionspruefung
- [x] Baustein-Definitionen mit Rotationstabellen, 7-Bag-Randomizer
- [x] Game-Loop mit Gravitation, Lock, Reihenabbau
- [x] Rendering mit Double-Buffering und Farben
- [x] Soft-/Hard-Drop, Pause, Game Over (mit Neustart per `r`)

### Zwischenschritt - Menue und Konfiguration (umgesetzt, Version 0.2.0)

- [x] Startmenue: Einzelspieler / Mehrspieler / Einstellungen / Beenden
- [x] Einzelspieler-Untermenue mit "Normales Spiel" (weitere Modi spaeter)
- [x] Mehrspieler als Platzhalter ohne Funktion (Hinweis-Bildschirm)
- [x] Einstellungen: Tastenbelegung im Spiel aenderbar, Spielername
- [x] Nutzer-Konfigurationsdatei (`rowhammer.conf`) nach Konvention,
      atomar geschrieben, Praezedenz Standard < Config < Env < CLI

### Zwischenschritt - Paketierung (deb umgesetzt, Version 0.17.0)

- [x] `Makefile` mit install/uninstall (DESTDIR/PREFIX, deb/rpm-tauglich)
- [x] Debian-Paketierung (`debian/` mit debhelper, natives Paket,
      Launcher-Symlink `/usr/games/rowhammer`)
- [x] Build-Skript `build-deb.sh` nach Script-Konventionen
- [ ] RPM-Paketierung (Spec-Datei, nutzt `make install`)
- [ ] Lizenz festlegen und `debian/copyright` aktualisieren

### Phase 2 - The-New-Tetris-Mechaniken (umgesetzt, Version 0.3.0)

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

### Zwischenschritt - Debug-Modus (umgesetzt, Version 0.6.0)

- [x] `--debug`/`--debug-dir` mit Session-Verzeichnis und drei
      korrelierten Log-Dateien (`frames.log`, `input.log`, `events.log`),
      Konzept siehe 4.6
- [x] Zentraler Ausgabe-Trichter `screen_write` (Frames 1:1 auch fuer
      Menues und Terminal-Setup)
- [x] Instrumentierung aller Spielaktionen inkl. blockierter Versuche,
      Board-Snapshots nach jedem Lock

### Phase 3 - Weltwunder (umgesetzt, Version 0.8.0)

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

### Phase 4 - Politur

- [x] Konfigurierbare Farben (Version 0.21.0: benannte Farbschemata
      `guideline`/`classic`/`mono`/`colorblind`, Auswahl im
      Einstellungsmenue mit Live-Vorschau, `--color-theme` bzw.
      `ROWHAMMER_COLOR_THEME`, gespeichert als `COLOR_THEME` in der
      Config; symbolische Farbnamen mit Basic- und Extended-Bedeutung,
      siehe 4.1)
- [ ] Umschaltbar zwischen Voll-Frame- und Partial-Rendering: seit
      0.22.0 zeichnet `render_flush` (`lib/render.sh`) standardmaessig
      nur die tatsaechlich geaenderten Zeilen (siehe 4.3); fuer
      Terminals/Multiplexer, bei denen sich das inkrementelle Update
      falsch darstellt (Debugging-Fall, Kompatibilitaets-Fallback),
      soll ein Schalter zurueck auf den alten Voll-Neuaufbau jeder
      Zeile erlauben - **Partial-Rendering bleibt der Standard**.
      Umsetzung nach dem Muster von `--color-mode`
      (`--render-mode full|partial`, `ROWHAMMER_RENDER_MODE`, Standard
      `partial`): ein globales Flag, das `render_flush` vor der
      Zeilen-Diff-Pruefung abfragt und im Full-Modus `RENDER_FULL`
      dauerhaft auf 1 haelt (das ist im Code bereits der Mechanismus,
      der einen kompletten Neuaufbau erzwingt, siehe 4.3) statt es nach
      dem ersten Frame wieder freizugeben.
- [x] `--reset config|stats|highscore|save|all` eingebaut (Version
      0.35.0, siehe 4.8): loescht gezielt persistente Daten im
      Datenverzeichnis (`${DATA_DIR}`, siehe 4.5) und beendet sich mit
      einer Bilanz auf STDOUT, statt ins Menue zu starten. Am Terminal
      werden die betroffenen Pfade vorher aufgelistet und bestaetigt
      ("nein" ist wie bei `menu_confirm` die Vorgabe), ohne TTY laeuft
      der Reset direkt durch, damit ein wartendes `read` kein Skript
      haengen laesst; nicht vorhandene Dateien sind kein Fehler.
      Zusaetzlich per `ROWHAMMER_RESET` setzbar, Praezedenz Standard <
      Env < CLI: bewusst **ohne** die Config-Stufe, weil die
      Config-Datei selbst ein Reset-Ziel ist (sie koennte sich sonst bei
      jedem Start selbst loeschen lassen). Die beiden offen gelassenen
      Fragen sind in 4.8 entschieden - `all` nimmt das Savegame mit
      (das eigene Ziel `save` deckt den Fall "nur der
      Weltwunder-Fortschritt" ab), `highscore` trifft beide
      Bestenlisten. Umsetzung: `reset_run` in `rowhammer.sh`, direkt
      nach dem Sourcen der Module (fuer deren Dateinamen-Konstanten) und
      vor der dorthin verschobenen TTY-Pruefung.
- [ ] Demo-Aufzeichnung und Demo-Player: eigene Runden als Datei
      mitschneiden (vermutlich Eingabe-Mitschnitt plus Seed statt voller
      Board-Snapshots, analog dem Prinzip des Debug-Modus in 4.6, aber
      fuer die reine Wiedergabe statt zur Fehlersuche) und ueber einen
      Menuepunkt wieder abspielen koennen. Notizen fuer die Umsetzung:
      - **Groessenabschaetzung:** vor der Formatwahl den Speicherbedarf
        je Minute Spielzeit abschaetzen (Tick-Rate x Eingabeereignisse
        bzw. x Feldgroesse bei Snapshots), damit klar ist, ob ein
        Eingabe-Mitschnitt oder volle Snapshots infrage kommen und wie
        viele Aufzeichnungen sich das Datenverzeichnis leisten kann.
      - **Aufzeichnung unbedingt auf RAM-Disk:** waehrend der laufenden
        Runde wird ausschliesslich in ein tmpfs geschrieben (z. B.
        `${XDG_RUNTIME_DIR}` bzw. `/dev/shm`), nie direkt ins
        persistente Datenverzeichnis - haeufige kleine Schreibzugriffe
        waehrend des Spiels duerfen weder die Framerate noch (bei SSDs)
        die Hardware belasten. Erst nach echtem Rundenende (siehe 3.3)
        wird die fertige Aufzeichnung ins Datenverzeichnis uebernommen,
        analog dem `--debug-dir`-Verzeichnis pro Lauf in 4.6.
      - **Demo-Verwaltung:** eigener Menuepunkt mit Liste der
        vorhandenen Aufzeichnungen (Datum, Laenge, Ergebnis), Auswahl
        zum Anschauen und einzelnes Loeschen.
      Noch offen: Aufzeichnungsformat im Detail, Obergrenze fuer Anzahl
      bzw. Gesamtgroesse im Datenverzeichnis, Abspielgeschwindigkeit
      (Pause/Vorspulen?).
- [ ] Mehrsprachige Oberflaeche (Multi-Language Support): saemtliche
      benutzersichtbaren Texte (Hauptmenue, Untermenues, Anleitung,
      HUD-Labels, Highscore-/Statistik-Spaltenkoepfe, `-h`/`--help`,
      Fehlermeldungen) hinter eine Uebersetzungsschicht ziehen, damit
      eine Sprache auswaehlbar wird (`--lang CODE`/`ROWHAMMER_LANG`,
      Einstellungsmenue, gespeichert in der Config). Greift die in
      Abschnitt 8 offene UI-Sprachfrage auf (bislang Menues Deutsch,
      HUD/--help Englisch als feste Konvention) und macht daraus eine
      Laufzeit-Entscheidung statt einer festen Sprachmischung. Noch
      offen: welche Sprachen ausser Deutsch/Englisch, Format der
      Uebersetzungstabellen (reines Bash-Array je Sprache vermutlich am
      einfachsten), Umgang mit variabler Textlaenge im starren
      48-Spalten-Layout (siehe 3.4).
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
- [x] Weltwunder-Fortschritt aus der Ingame-Statusanzeige entfernen:
      umgesetzt als Teil des Rowhammer-Zaehlers in Version 0.25.0 (siehe
      naechster Punkt) - der freigewordene Platz auf der zweiten
      Statuszeile ist genau der Grund, warum der Zaehler dort Platz
      fand.
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
- [x] Standard-Tastenbelegung geaendert (siehe 3.1, Version 0.5.0):
      `w`/Pfeil hoch **und** Leertaste fuer Hard-Drop, `e` fuer Rotation
      im Uhrzeigersinn, `c`/`2` fuer Hold/Tauschen. Pfeil hoch und
      Leertaste liegen als feste Sekundaerbelegung auf dem Hard-Drop,
      `2` fest auf Hold; `w`, `e` und `c` sind die konfigurierbaren
      Primaertasten.
- [x] Standard-Tastenbelegung erneut geaendert (siehe 3.1, Version
      0.31.0, Nutzerentscheidung): Rotation liegt jetzt auf `a` (gegen
      den Uhrzeigersinn) und `d` (im Uhrzeigersinn), die feste
      Hold-Sekundaertaste ist `w` statt `2`. Links/Rechts und der
      Hard-Drop geben ihre Buchstabentasten dafuer ab und laufen ueber
      ihre festen Sekundaertasten (Pfeile bzw. Leertaste/Pfeil hoch);
      neu ist der Bindungswert `NONE` fuer "keine Buchstabentaste"
      (Standard fuer `KEY_LEFT`/`KEY_RIGHT`, von der Dubletten-Pruefung
      ausgenommen).
- [x] Highscore-Liste (Version 0.7.0: Top 10 im Datenverzeichnis,
      Anzeige im Hauptmenue, Rang im Game-Over-Bild; siehe 4.5)
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
- [x] Blinkeffekt beim Reihenabbau (Version 0.20.0): abgebaute Reihen
      blinken kurz auf, bevor sie entfernt werden und das naechste Teil
      erscheint (`board_full_rows`, `flash_rows`, `FLASH_ROWS`/
      `FLASH_STATE`; Dauer ueber `FLASH_MS`/`FLASH_CYCLES`, siehe 3.1)
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
- [x] README mit Screenshots/Asciinema aktualisieren (Abschnitt
      "Vorschau" im README): vier kurze, echte Spielsequenzen als
      asciinema-Aufnahmen (`.cast`) und GIF unter `docs/demo/` - Tetris
      (Vierfach-Abbau), Silber-Quadrat (vier gemischte Teile),
      Gold-Quadrat (vier gleiche Teile) und die Weltwunder-Baustelle.
      Die Clips sind mit festem `--seed` reproduzierbar aufgenommen
- [x] Spielzeit-Counter fuer die aktuelle Runde einbauen (Version
      0.17.0: Anzeige im HUD als "Time" MM:SS, Zeitmessung analog zum
      Game-Loop ueber `${EPOCHREALTIME}`/`now_ms`; nur aktive Spielzeit
      zaehlt, Pausen und Game-Over-Bildschirm nicht; die Spielzeit wird
      zusaetzlich mit dem Highscore-Eintrag gespeichert, siehe 3.4/4.5)
- [x] Highscore-Liste um Anzahl erzeugter Silber- und Gold-Bloecke
      erweitern (Version 0.15.0: zusaetzliche Felder im Zeilenformat,
      siehe 4.5; bei Eintraegen ohne diese Felder gilt als
      Standardwert 0. Gold/Silber werden als Spalten angezeigt, die
      Score-Spalte ist dafuer auf Nutzerwunsch aus der Anzeige
      entfernt - der Score bleibt gespeichert und bestimmt weiterhin
      die Rangfolge)
- [x] "Wollen Sie wirklich beenden?"-Abfrage beim Schliessen des Spiels
      (Version 0.22.0): liegt beim Verlassen ueber "Beenden" oder `Esc`
      im Hauptmenue noch eine pausierte Runde im Zwischenspeicher, fragt
      `menu_confirm` (lib/menu.sh) vorher nach und zeigt deren Stand
      (Lines/Rows/Level); die ablehnende Antwort ist vorausgewaehlt und
      `Esc` gilt ebenfalls als Ablehnung. Erst nach Bestaetigung wird die
      Runde beendet und gewertet
- [x] Anzeige des Datums in der Highscore-Liste nachruesten (Version
      0.14.0: das gespeicherte Feld `date` wird als eigene Spalte
      angezeigt, Name in der Anzeige auf 14 Zeichen gekuerzt; die
      Statistik speichert und zeigt seither ebenfalls das Datum der
      letzten drei Spiele, siehe 4.5)
- [x] Fehlinterpretierte Tastendruecke behoben (Version 0.16.1,
      Issue #7): zerrissen zugestellte Pfeiltasten-Sequenzen loesten
      ueber ihre Restbytes (`[`, `C` -> Taste `c`) ungewollte
      Hold-Wechsel aus; per Debug-Log nachgewiesen. `read_key` liest
      Escape-Sequenzen jetzt byteweise bis zum Endbyte mit
      grosszuegigerem Timeout und wertet auch ein im Timeout-Moment
      geliefertes Byte aus (siehe 4.3)
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
- [x] Punktesystem-Umbau (Version 0.16.0, Nutzerentscheidung):
      abgebaute Reihen sind die einzige Punktquelle, der Score ist
      identisch mit der gewichteten Reihenwertung "Rows" (1 je Reihe,
      +5 je Silber-, +10 je Gold-Streifen, +1 je Tetris, siehe 3.2).
      Entfallen sind Drop-Punkte, Quadrat-Bildungs-Boni (2000/1000)
      und die Level-Skalierung; Highscore (Rangfolge nach Rows) und
      Statistik speichern kein separates Score-Feld mehr (siehe 4.5)
- [x] Anleitung im Hauptmenue (Version 0.32.0, Nutzerwunsch): neuer
      Menuepunkt "Anleitung" zwischen "Einstellungen" und "Beenden",
      der das Spiel auf fuenf Info-Bildschirmen erklaert - Spielprinzip,
      Steuerung, Vorschau/Hold, Gold-/Silber-Quadrate mit ihrer
      Reihenwertung und zum Schluss den Weltwunderbau (`menu_help`,
      `menu_help_keys` in `lib/menu.sh`, siehe 3.5). Tastenbelegung und
      Wunder-Kosten stammen aus dem laufenden Zustand, damit ein Rebind
      oder ein justiertes `WONDER_COSTS` die Anleitung nicht veralten
      laesst.
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
- [x] Anleitung mit den Pfeiltasten blaetterbar machen (Version 0.33.0,
      Nutzerwunsch, siehe 3.5): zuvor fuehrte jede beliebige Taste zur
      naechsten der fuenf Seiten, ohne Weg zurueck (eine feste Folge von
      `menu_message`-Aufrufen). `menu_help` (`lib/menu.sh`) ist jetzt
      eine eigene Warteschleife: Pfeil links/rechts blaettert umlaufend
      zwischen den Seiten, Enter/Leertaste/`x`/`ESC` schliessen die
      Anleitung. Der Seiteninhalt kommt aus `menu_help_body`, einem
      `case`-Switch je Seitenindex, damit jede Seite direkt angesprungen
      werden kann statt nur der Reihe nach.
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
- [x] **Endlosen Modus in "Marathon" umbenannt** (Version 0.34.1,
      Nutzerentscheidung): der bisherige Menuepunkt "Normales Spiel"
      heisst jetzt "Marathon" (`lib/menu.sh`), der interne Modusname
      `GAME_MODE` wechselt entsprechend von `normal` zu `marathon`
      (Standardwert und `game_run`-Argument in `rowhammer.sh`, siehe
      3.6). Reine Umbenennung ohne Verhaltensaenderung: `GAME_MODE`
      wird nicht persistiert (siehe 4.5), betrifft also weder Savegame
      noch Highscore-Dateien; einzig `events.log` des Debug-Modus
      protokolliert den neuen Namen.
- [ ] **Sprint-Modus** und die Anzeige-Seiten der Modi (Rest des
      Modus-Themas, Nutzerentscheidung: die Anzeige folgt getrennt von
      der Speicherung). Offen sind:
      - **Sprint** (Ziel: in 3 Minuten moeglichst viele Reihen) als
        dritter Eintrag im Einzelspieler-Menue - dieselbe Mechanik wie
        Ultra mit vertauschten Rollen (feste Zeit, offene Rows), also
        wieder eine eigene Liste (Rangordnung: meiste Rows) und ein
        eigener HUD-Zaehler (verbleibende Zeit).
      - **Anzeige der Ultra-Bestenliste**: das Datenformat steht
        (4.5), es fehlt der Bildschirm. Dafuer braucht der Menuepunkt
        "Highscores" eine vorgeschaltete Modus-Auswahl (oder die
        Seitenlogik aus `menu_pages` je Modus).
      - **Statistik je Modus**: gespielte Runden je Modus, bei Ultra
        zusaetzlich wie oft das Ziel erreicht wurde. Bewusst noch nicht
        eingebaut - Zaehler ohne Anzeige waeren tote Daten, und die
        Statistik-Bildschirme sind schon zweiseitig (siehe 4.5).
      - **Anleitung**: eine sechste Seite "Spielmodi" (siehe 3.5).

### Phase 5 - Multiplayer (spezifiziert in Abschnitt 5, noch nicht umgesetzt)

Die Schritte sind so sortiert, dass jeder fuer sich lauffaehig und
testbar ist und der Mehrspieler-Modus Stueck fuer Stueck waechst. Die
Details stehen jeweils im genannten Unterabschnitt.

- [ ] **Schritt 1 - Vorarbeit: Entkopplung und Render-Performance** (siehe 5.3, 5.9).
      Rundenlogik ohne Rendering/Input lauffaehig machen (`game_reset`,
      `step_down`, `lock_and_next`, `try_move`, `try_rotate`, `hold_piece`
      zeichnen nicht mehr selbst; `record_round` trennt Verbuchen und
      Anzeigen). Der Render-Teil dieses Schritts ist mit 0.22.0 erledigt
      (Zeilen-Diff `FRAME_LINES`/`PREV_LINES` in `render_flush` plus
      Cache der liegenden Feldreihen, siehe 4.3); `screen_write` bleibt
      der einzige Ausgabekanal (Debug-Log!). Offen bleibt die
      Entkopplung der Rundenlogik.
      Abnahme: Einzelspieler unveraendert spielbar, Frame-Kosten messbar
      gesunken.
- [ ] **Schritt 2 - Transportschicht `lib/net.sh`** (siehe 5.2, 5.3).
      Hilfsprogramm-Erkennung (`socat` > `ncat --unixsock` > `nc -U`) mit
      klarer Meldung, wenn nichts vorhanden ist; Verbindung als Coprocess,
      nicht-blockierendes Leeren des Sockets pro Tick, Zeilenrahmung mit
      512-Byte-Grenze, Aufraeumen im bestehenden EXIT-`trap`,
      Debug-Mitschnitt `net.log`. Abnahme: zwei Testprozesse tauschen
      ueber einen Socket Zeilen aus, ohne dass der Game-Loop stockt.
- [ ] **Schritt 3 - Protokoll v1 und Validierung `lib/proto.sh`** (siehe 5.4, 5.5).
      Nachrichtentabelle, Serialisierung, Whitelist-Parser mit
      Feldmustern, Zeichensatzfilter 0x20-0x7E, Ratenbegrenzung.
      Zusammen mit `tools/net-fuzz.sh` (boesartige Zeilen: ANSI-Escapes,
      `$(...)`, Backticks, `../`, Ueberlaenge, Nullbytes, halbe Zeilen).
      Abnahme: kein Prozess stirbt, kein Befehl laeuft, kein
      Steuerzeichen erreicht das Terminal.
- [ ] **Schritt 4 - Hub-Prozess und Lobby** (siehe 5.3, 5.10).
      `--mp-hub` headless, `--mp-bridge`, Sitzungsverzeichnis mit den
      Rechte- und Symlink-Pruefungen aus 5.5, Menue "Spiel eroeffnen /
      Spiel beitreten", Spielerliste, Bereitschaft, Seed-Verteilung,
      Countdown, Ping/Timeout, geordnetes Beenden. Noch **ohne**
      Interaktion im Spiel: alle spielen parallel ihre eigene Runde.
      Abnahme: vier Terminals treten bei, starten gemeinsam, ein
      `kill -9` auf einen Client stoert die anderen nicht.
- [ ] **Schritt 5 - Mitspieler-Anzeige Stufe 0 und 1** (siehe 5.6).
      `PEER`-Zustaende puffern, Scoreboard- und Kompaktansicht in der
      Seitenleiste, Detailstufen-Auswahl inklusive Neuberechnung beim
      Resize, `--mp-view`. Erstes sichtbares Mehrspieler-Erlebnis, laeuft
      im 48x22-Minimum. Abnahme: vier Spieler sehen gegenseitig ihre
      Rows/Lines live.
- [ ] **Schritt 6 - Mitspieler-Anzeige Stufe 2 (Mini-Felder)** (siehe 5.4, 5.6).
      Feld-Snapshot in 200 Zeichen kodieren/dekodieren, `NEEDBOARD`-
      Steuerung, Drosselung auf 5 Hz und "nur bei Aenderung", Layout
      rechts neben der Seitenleiste, Akzentfarbe je Slot. Abnahme: bei
      4 Spielern in einem 90x24-Terminal bleibt die Framerate stabil.
- [ ] **Schritt 7 - Garbage-Mechanik** (siehe 5.7).
      Zellsorte `x`, zeilenweises Hochschieben von `BOARD`/`BOARD_ID`/
      `BOARD_SQ`, Top-Out-Erkennung beim Schieben, Warteschlange mit
      Verrechnung, Hub-seitige Angriffsberechnung und Lochspalte,
      Vorwarn-Balken im HUD. Zuerst nur fuer 2 Spieler. Abnahme:
      Tetris und Gold-Quadrat erzeugen die spezifizierten Mengen,
      Quadrate ueberleben das Hochschieben.
- [ ] **Schritt 8 - Rundenende, KO-Reihenfolge, Zuschauermodus,
      Verbindungsabbruch** (siehe 5.8).
      `TOPOUT`/`KO`/`END`, Platzierung, Endbildschirm mit Rangliste,
      Timeout- und EOF-Behandlung, Mehrspieler-Pausenmenue ohne
      "Ins Hauptmenue", Verbuchung von Wunder-Fortschritt und Statistik.
      Abnahme: eine Runde laeuft sauber bis zum Sieger, ein abgestuerzter
      Client beendet sie nicht.
- [ ] **Schritt 9 - Drei bis sechs Spieler** (siehe 5.1, 5.6, 5.7).
      Zielwahl-Modi `random|all|even`, Layout-Raster fuer mehrere
      Mini-Felder, `--mp-max`, Lasttests. Abnahme: sechs Bots spielen
      eine Runde ohne Verbindungs- oder Renderprobleme durch.
- [ ] **Schritt 10 - Test-Bot, Dokumentation, Paketierung** (siehe 5.10, 5.9).
      `--mp-bot` (Client ohne Terminal, zufaellige Zuege) fuer
      reproduzierbare Mehrspieler-Tests ohne N Terminals; README-Kapitel
      mit Beispiel-Ablauf ueber SSH; asciinema-Clip mit zwei Feldern;
      `socat` als `Recommends` im Debian-Paket.
- [ ] **Schritt 11 - Sicherheits-Review vor der Freigabe** (siehe 5.5).
      Kompletter Durchgang durch alle Stellen, die Empfangenes anfassen:
      kein `eval`/`source`, keine ungeprueften Werte in `$(( ))` oder in
      Array-Indizes, Zeichensatzfilter, Pfadpruefungen, Grenzen. Erneuter
      Fuzz-Lauf gegen den fertigen Stand, dazu ein "boeser Client", der
      absichtlich das Protokoll verletzt.

### Phase 6 - Server-Betrieb, Accounts, Web (spezifiziert in 5.11-5.19, noch nicht umgesetzt)

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
  3.3). Offen bleibt: Die Reihen-Kosten je Wunder (100..6400) sind
  gegenueber dem Original bewusst herunterskaliert und sollten nach
  Playtesting ggf. nachjustiert werden (`WONDER_COSTS`).
- Mindest-Terminalgroesse: seit 0.26.0 48x22 (vorher 48x24 - die zwei
  Statuszeilen sind mit dem HUD-Umbau entfallen, siehe 3.4), seit
  0.19.0 auch waehrend des Spiels ueberwacht (SIGWINCH, siehe Phase 4
  "Anpassung an Terminalgroesse"): ein Resize zeichnet sauber neu, ein
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
  breit, seitenweise angezeigt (`menu_pages`). Weitere Werte kosten
  damit keine vorhandene Spalte mehr, sondern Zeilen - und irgendwann
  eine weitere Seite: pro Info-Bildschirm passen 18 Zeilen
  (`MENU_BODY_MAX`, seit 0.28.0 eine mehr), die Highscore-Liste zeigt fuenf Eintraege je
  Seite, die Statistik teilt sich in Gesamtzaehler und letzte Spiele.
- Spielmodi: die drei Fragen zum Ultra-Modus sind mit 0.34.0
  entschieden (Rows statt Lines, gescheiterte Versuche ohne
  Listeneintrag, HUD-Zaehler "Goal"/"Left" in der linken Spalte, siehe
  3.6). Offen bleibt nur die Justierung: ob 150 Rows die richtige
  Distanz sind, entscheidet Playtesting (`ULTRA_TARGET_ROWS`) - mit den
  Quadrat-Boni ist die Strecke deutlich kuerzer als 150 physische
  Reihen, das ist so gewollt. Sprint, die Anzeige der Ultra-Liste und
  die Statistik je Modus stehen noch aus (siehe Roadmap Phase 4).
- Punktesystem-Feinschliff (Kombos, Back-to-Back?): Nach dem Umbau in
  0.16.0 (nur abgebaute Reihen zaehlen) waeren solche Extras eine
  bewusste Abweichung vom Konzept "Punkte = Reihenwertung" - nur nach
  expliziter Nutzerentscheidung wieder aufgreifen.
- UI-Sprache: Menues sind Deutsch (ASCII), In-Game-HUD und --help
  Englisch (Konvention). Entscheiden, ob das so bleibt oder das UI
  einheitlich einsprachig werden soll.

Offene Punkte zum Mehrspieler (Spezifikation siehe Abschnitt 5; alles
Uebrige dort ist entschieden):

- **Fremdabhaengigkeit `socat`/`ncat`/`nc -U`:** Bash kann kein AF_UNIX.
  Zu bestaetigen ist, dass ein `Recommends`-Paket akzeptabel ist - sonst
  bleibt nur die FIFO-Variante aus 5.2 mit ihren Nachteilen.
- **Wertung von Mehrspieler-Runden:** Vorschlag in 5.8 ist
  Weltwunder-Fortschritt und Statistik ja, Highscore-Liste nein (dafuer
  eigene Mehrspieler-Zaehler). Bestaetigung ausstehend; die Alternative
  waere ein `mode`-Feld in der Highscore-Zeile mit getrennter Anzeige.
- **Garbage-Werte** (0/1/2/4 Reihen, +2 Silber, +4 Gold, Deckel 10) sind
  aus der Reihenwertung abgeleitet, nicht aus dem Original - "The New
  Tetris" hat keinen vergleichbaren Versus-Modus. Nach Playtesting
  nachjustieren.
- **Zielwahl ab 3 Spielern:** Standard `random`. Ob eine manuelle
  Zielauswahl (Taste) gewuenscht ist, bleibt offen; die Tastenbelegung
  ist voll und die Bedienung skaliert schlecht.
- **Spielerzahl:** Standard 4, technisches Maximum 6 (Begruendung in
  5.1). Ob 6 in der Praxis noch fluessig laeuft, entscheidet der Lasttest
  im Roadmap-Schritt 9 (Phase 5).
- **Kein Reconnect in v1** (5.8). Falls sich Abbrueche im Alltag haeufen,
  waere ein Wiedereinstieg mit vollstaendiger Zustandsuebertragung ein
  eigener spaeterer Punkt.
- **Anti-Cheat:** bewusst nur Hub-Autoritaet ueber Garbage-Mengen und
  Rundenende (5.4). Ein manipulierter Client kann falsche `CLEAR`s
  melden; eine serverseitige Vollsimulation ist kein Ziel. Die
  Sicherheitsregeln in 5.5 schuetzen dagegen die Prozesse und Terminals
  der Mitspieler - dieser Teil ist nicht verhandelbar.

Offene Punkte zum Server-Betrieb (Phase 6, Spezifikation siehe 5.11-5.19):

- **Siegbedingung im Versus-Modus:** 5.1/5.8 legen "letzter
  Ueberlebender" (KO ueber Garbage/Top-Out) als Sieger fest. Die
  neueste Nutzerbeschreibung ("man spielt die Runde, der Spieler mit
  den meisten Reihen gewinnt") klingt dagegen nach einer reinen
  Reihen-Wertung ohne Elimination. Beides zusammen ist moeglich (Rows
  als Tiebreaker, wie in 5.8 bereits fuer den Gleichstand-Fall
  vorgesehen), aber als alleinige Regel schliessen sie sich aus:
  Bestaetigung noetig, ob der Garbage-/KO-Versus-Modus aus 5.7/5.8
  bleibt, durch einen reinen Rows-Wettkampf ohne Garbage ersetzt wird,
  oder beide als waehlbare Modi nebeneinander bestehen.
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
