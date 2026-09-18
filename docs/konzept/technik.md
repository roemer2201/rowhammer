# rowhammer - Konzept: Technik (4.1 bis 4.4, 4.6, 4.7, 4.9, 4.11)

Teil des technischen Konzepts von rowhammer. Die Abschnittsnummern sind
die aus [CLAUDE.md](../../CLAUDE.md) und bleiben stabil
(Arbeitsregel 6.1): ein Verweis der Form `CLAUDE.md 4.3` im Code meint
den gleichnamigen Abschnitt hier. Die Datei fuehrt den **aktuellen**
Stand samt seiner Begruendung; was abgeloest wurde, steht in
[HISTORY.md](../../HISTORY.md), was noch fehlt, in
[TODO.md](../../TODO.md).

## 4. Technisches Konzept

### 4.1 Rahmenbedingungen

- **Bash >= 4.3** (seit 1.3.0): assoziative Arrays gaeben
  sich mit 4.0 zufrieden, die **Namerefs** (`declare -n`) von
  `lib/state.sh` nicht - sie halten fuenf Rundenzustaende gleichzeitig
  und sind die Voraussetzung der Mehrspieler-Wiedergabe (siehe 5.20).
  Einen Rueckfallweg gibt es dafuer nicht (die Alternative waere, den
  ganzen Rundenzustand je Frame hin- und herzukopieren), deshalb ist es
  eine harte Bedingung: der Startcheck in `rowhammer.sh` vergleicht
  `BASH_VERSINFO` als eine Zahl (Major x 100 + Minor, damit 4.10 nicht
  aelter aussieht als 4.3) und bricht mit der gefundenen Version in der
  Meldung ab. Ziel bleiben die ueblichen Linux-Distributionen - Bash 4.3
  ist von 2014, und `${EPOCHREALTIME}` (Bash 5) nutzt das Spiel ohnehin
  schon, wo es da ist. `debian/control`, `rowhammer.spec` und die README
  nennen dieselbe Zahl.
- **Eine Millisekunden-Uhr** (seit 1.4.2): entweder `${EPOCHREALTIME}`
  (Bash 5, ohne Fork) oder ein `date`, das `%N` kennt. `now_ms`
  (`rowhammer.sh`) nimmt das erste, wo es da ist; welche der beiden es
  ist, entscheidet `clock_source_init` **einmal beim Start** und legt es
  in `CLOCK_SRC` ab. Taugt keine von beiden, bricht das Spiel mit einer
  Meldung ab - wie bei der Bash-Version, und aus demselben Grund: einen
  dritten Weg gibt es nicht. Drei Festlegungen dazu:
  - **Der `date`-Weg wird geprueft, nicht geglaubt.** `%N` ist eine
    GNU-Erweiterung und von POSIX nicht verlangt; ein `date` ohne sie
    reicht entweder den Buchstaben durch (`1757000000N`, woran `$(( ))`
    scheitert - unter `set -e` mitten in der Runde) oder laesst ihn weg
    und gibt die blossen Sekunden zurueck, was schlimmer ist: das sieht
    wie eine Zahl aus und legt die Uhr, durch eine Million geteilt, ins
    Jahr 1970. Der Probelauf verlangt deshalb beides - lauter Ziffern
    **und** genau neun Stellen mehr als `date +%s`.
  - **Kein Rueckfall auf ganze Sekunden.** Ein Spiel, dessen Gravitation,
    Lock Delay (250 ms) und Zeitmodi in Sekunden gemessen werden, ist
    nicht dieses Spiel; eine klare Meldung beim Start ist ehrlicher als
    eine Runde, die sich falsch anfuehlt.
  - **Geprueft wird hinter `--help` und `--reset`** (wie die
    TTY-Pruefung, siehe 4.8) - die beiden fragen nicht, wie spaet es
    ist. Die kopflosen Mehrspieler-Prozesse dagegen schon (der Hub-Tick
    und seine Timeouts laufen auf dieser Uhr), sie sind also **nicht**
    ausgenommen.
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
    datadir.sh         # Speicherort der Spieldaten: Zeigerdatei, Umzug, Sicherung
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
    state.sh           # Rundenzustand benennen und umschalten (Namerefs)
  assets/
    wonders/           # ASCII-Art je Wunder und Baustufe
  tools/
    key-scan.sh        # Regressionstest der Eingabeschicht (Issue #7)
    net-fuzz.sh        # Fuzz-Test der Mehrspieler-Parser (siehe 5.5)
    demo-keys.sh       # Regressionstest der Demo-Tasten (siehe 3.8)
    state-check.sh     # Regressionstest des Rundenzustands (siehe 5.20)
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
  CLAUDE.md            # technisches Konzept und Konventionen
  TODO.md              # offene Punkte (Roadmap, Entscheidungen)
  HISTORY.md           # Archiv der erledigten Punkte je Version
  README.md            # Anleitung fuer Spielerinnen und Spieler
  MISTRAL.md           # externe Review (Juli 2026), wird nicht gepflegt
  CODEX-REVIEW.md      # externe Review Mehrspieler (Sept. 2026), ungepflegt
```

Alle Module aus dem Baum oben existieren; die vier
Mehrspieler-Module (`net`, `proto`, `hub`, `mp`) kamen mit 1.1.0 dazu
(siehe Abschnitt 5), `state` mit 1.3.0 (siehe 5.20).

**Menuefuehrung.** Die Anwendung startet in einem Menue (Einzelspieler /
Mehrspieler / Highscores / Weltwunder / Statistik / Demos /
Einstellungen / Anleitung / Beenden; solange eine pausierte Runde
wartet, zusaetzlich "Fortsetzen" an erster Stelle, ebenso im
Einzelspieler-Untermenue). Drei Untermenues waehlen zuerst einen
Modus: das Einzelspieler-Menue den Modus der Runde (Marathon, Ultra,
Sprint, Time Attack, Hochwasser, siehe 3.6), "Highscores" die
anzuzeigende Bestenliste (`menu_highscores`, fuenf Listen, siehe 4.5)
und "Statistik" die Sicht (`menu_stats`: Gesamt oder ein Modus, siehe
4.5). Ihre Eintraege baut ein gemeinsamer Helfer
(`menu_mode_entries`), der auf Wunsch einen sechsten Modus anhaengt -
den Mehrspieler, den nur die beiden Rueckblick-Auswahlen fuehren, weil
er im Einzelspieler-Menue nicht gestartet wird; jeder Eintrag nennt
hinter dem Namen in einer eigenen, ausgerichteten Spalte, wogegen der
Modus laeuft (siehe 3.6). Die Beschriftungen sind uebersetzt (siehe
4.11): Deutsch und Englisch stehen zur Wahl, Code, Kommentare und
Diagnosemeldungen nach STDERR bleiben Englisch.

**Datenmodell und Zaehler.** Das Spielfeld haelt je Zelle drei parallele
Arrays (Sorte `BOARD`, Instanz-ID `BOARD_ID`, Quadrat-Status
`BOARD_SQ`); der HUD-Zaehler "Rows" ist die gewichtete Reihenwertung
(1/5/10), die den Weltwunder-Fortschritt speist und zugleich der Score
der Runde ist (siehe 3.2), "Lines" zaehlt physische Reihen und treibt
das Level. Jede Runde, die in eine Bestenliste kommt, fragt an ihrem
Ende nach dem Namen fuer den Eintrag (vormarkierte Vorgabe aus den
Einstellungen, siehe 3.7).
**CLI-Optionen.** Jede ist zusaetzlich per Umgebungsvariable setzbar
(Konvention aus Abschnitt 6). Die Spalte **Config** sagt, ob der Wert
in `rowhammer.conf` gespeichert wird - und damit, welche Praezedenz
gilt: Standard < **Config** < Env < CLI bei den vier gespeicherten
Werten, Standard < Env < CLI bei allen uebrigen. Der Unterschied ist
kein Zufall: gespeichert wird, was Geschmack ist (Name, Sprache,
Farbschema, Demo-Aufzeichnung), nicht gespeichert, was eine Eigenschaft
des Terminals oder des einzelnen Aufrufs ist (Farb- und Render-Modus,
Reset, Debug, Mehrspieler).

| Option | Umgebung | Config | Bedeutung |
| --- | --- | --- | --- |
| `--seed N` | `ROWHAMMER_SEED` | - | reproduzierbare Teilfolge |
| `--name NAME` | `ROWHAMMER_PLAYER_NAME` | ja | Spielername (Vorgabe der Namensabfrage, 3.7) |
| `--lang de\|en\|auto` | `ROWHAMMER_LANG` | ja | Sprache, Standard `auto` (4.11) |
| `--data-dir DIR` | `ROWHAMMER_DATA_DIR` | - | Datenverzeichnis (4.5); der im Einstellungsmenue gespeicherte Ort steht in einer eigenen Zeigerdatei, Praezedenz Standard < Zeiger < Env < CLI (4.12) |
| `--no-color` | `ROWHAMMER_NO_COLOR` | - | Farben aus (siehe unten) |
| `--color-mode auto\|basic\|extended` | `ROWHAMMER_COLOR_MODE` | - | Farbpalette, Standard `auto`; `--no-color` gewinnt (4.1) |
| `--color-theme guideline\|classic\|mono\|colorblind` | `ROWHAMMER_COLOR_THEME` | ja | Farbschema, Standard `guideline` (4.1) |
| `--render-mode partial\|full` | `ROWHAMMER_RENDER_MODE` | - | Bildaufbau, Standard `partial` (4.3) |
| `--demo-record on\|off` | `ROWHAMMER_DEMO_RECORD` | ja | Demo-Aufzeichnung, Standard `on` (3.8/4.10) |
| `--reset config\|stats\|highscore\|save\|demo\|all` | `ROWHAMMER_RESET` | - | Daten zuruecksetzen und beenden (4.8) |
| `--force` | `ROWHAMMER_FORCE` | - | Sicherheitsabfragen mit "ja" beantworten (4.8) |
| `--debug` | `ROWHAMMER_DEBUG` | - | Session-Trace (4.6) |
| `--debug-dir DIR` | `ROWHAMMER_DEBUG_DIR` | - | Zielverzeichnis der Debug-Logs |
| `-h`, `--help` | - | - | Hilfe in der gewaehlten Sprache |

Dazu die Mehrspieler-Optionen `--mp-transport`, `--mp-port`,
`--mp-dir`, `--mp-max`, `--mp-session`, `--mp-view`, `--mp-target`,
`--mp-mode`, `--mp-garbage`, `--mp-host`, `--mp-join` und `--mp-bot`
(je mit `ROWHAMMER_MP_*`-Variable, keine Config-Werte, Tabelle in 5.10)
sowie die drei internen Prozessmodi `--mp-hub`, `--mp-bridge` und
`--mp-discover` (5.3). Die Tastenbelegung ist zusaetzlich per
`ROWHAMMER_KEY_*` uebersteuerbar.

**`NO_COLOR`:** Neben `--no-color`/`ROWHAMMER_NO_COLOR` wird die
De-facto-Standardvariable [`NO_COLOR`](https://no-color.org/) beachtet -
ist sie gesetzt und nicht leer, sind Farben standardmaessig aus.
Praezedenz der drei Abschalter: Standard-`NO_COLOR` < projekteigenes
`ROWHAMMER_NO_COLOR` < `--no-color`, sodass ein global exportiertes
`NO_COLOR` per `ROWHAMMER_NO_COLOR=0` fuer rowhammer wieder
ueberschrieben werden kann.

### 4.3 Game-Loop, Input, Rendering

- **Game-Loop:** feste Tick-Rate; Fall-Intervall abhaengig vom Level.
  Zeitmessung ueber `${EPOCHREALTIME}` (Bash 5) mit Fallback. Ruht ein
  Stein (Lock Delay scharf, `LOCK_PENDING`), pausiert die Gravitation und
  der Loop lockt erst nach Ablauf von `LOCK_DELAY_MS` seit `TOUCHDOWN_MS`
  (siehe 3.1).
- **Input:** nicht-blockierend ueber `read -rsn1 -t <timeout>`;
  Escape-Sequenzen der Pfeiltasten sauber einlesen. Terminal-Modus mit `stty`
  setzen und ueber einen `trap`-Handler (EXIT/INT/TERM) garantiert
  wiederherstellen. **Der Rohmodus gilt fuer die ganze Sitzung**
  (`term_input_raw` in `lib/input.sh`, aufgerufen aus `term_setup`:
  `stty -echo -icanon min 1 time 0`, seit 0.28.1, Issue #33) und seit
  0.45.0 ausnahmslos - auch die Namensabfrage zeichnet ihre Zeile
  selbst (`menu_text_input`, siehe 3.7). Ohne ihn echote das Terminal
  zwischen zwei Reads jeden Tastendruck an die Cursorposition, und weil
  der Diff-Renderer eine unveraenderte Zeile nicht neu schreibt, blieb
  ein echotes `^[[C` dort stehen.
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
  Luecke zwischen ihren Bytes als eine Sequenz zusammengesetzt - ohne
  ihn wuerde ein spaet eintreffendes Byte zur eigenen Taste (der
  Schwanz `C` einer Rechts-Pfeiltaste zur Hold-Taste `c`). Derselbe
  Automat konsumiert die Sequenzklassen, die ihre Nutzlast sonst als
  Tastendruecke durchreichen wuerden: X10-Mausmeldungen (drei Rohbytes
  nach `ESC [ M`),
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
  Rundenstart). Beides zusammenzulegen - `RENDER_FULL` dauerhaft auf 1
  halten - haette mit jedem Frame ein `\e[2J` geschickt und den
  Rueckfallmodus flackern lassen, also genau das Gegenteil dessen
  bewirkt, wozu er da ist.
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

**Eine Stoerreihe ist ausdruecklich ausgenommen** (seit 1.4.2):
`square_check_at` weist eine Zelle der Sorte `GARBAGE_CELL` ab, bevor es
nach ihrer Instanz fragt. Beides sagt heute dasselbe - die Flutreihe des
Hochwasser-Modus (3.6) und die Mehrspieler-Garbage (5.7) vergeben Sorte
und Instanz-ID 0 gemeinsam -, aber die ID war bis dahin das Einzige, was
zwischen einer Stoerreihe und einem Gold-Quadrat stand, und sie sagt
"gehoert zu keinem Stein", nicht "ist kein Stein". Eine kuenftige
Zellenart mit ID 0 waere aus Versehen quadratsunfaehig statt nach Regel;
jetzt steht die Regel dort, wo ueber sie entschieden wird.

### 4.6 Debug-Modus (seit 0.6.0)

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
    macht. Bei einer Mehrspieler-Aufnahme steht hier ausserdem die
    Gegenprobe gegen ihre Pruefpunkte: je Abweichung eine Zeile mit
    beiden Staenden und am Ende die Bilanz des Laufs (siehe 5.20).
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
  `BuildArch: noarch`, `Requires: bash >= 4.3` (siehe 4.1),
  `Recommends: ncurses`
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
  der Tastentest der Demo-Wiedergabe `tools/demo-keys.sh` (siehe 3.8);
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

