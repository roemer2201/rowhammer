# rowhammer - Konzept: Persistenz, Reset, Datenverzeichnis (4.5, 4.8, 4.12)

Teil des technischen Konzepts von rowhammer. Die Abschnittsnummern sind
die aus [CLAUDE.md](../../CLAUDE.md) und bleiben stabil
(Arbeitsregel 6.1): ein Verweis der Form `CLAUDE.md 4.5` im Code meint
den gleichnamigen Abschnitt hier. Die Datei fuehrt den **aktuellen**
Stand samt seiner Begruendung; was abgeloest wurde, steht in
[HISTORY.md](../../HISTORY.md), was noch fehlt, in
[TODO.md](../../TODO.md).

### 4.5 Persistenz

- Alle persistenten Spieldaten liegen gemeinsam im Datenverzeichnis
  `${HOME}/.config/rowhammer` (seit 0.13.0, vorher `${HOME}/rowhammer`;
  aenderbar per `--data-dir DIR` bzw.
  `ROWHAMMER_DATA_DIR`, seit 1.5.0 auch dauerhaft ueber das
  Einstellungsmenue - dann steht der Pfad in der Zeigerdatei
  `${HOME}/.config/rowhammer/datadir`, siehe 4.12): die Konfiguration `rowhammer.conf`, die
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
  Tastenbelegung, Demo-Aufzeichnung seit 0.46.0; der Speicherort seit
  1.5.0 steht als einziger Eintrag **nicht** hier, sondern in einer
  eigenen Datei - siehe 4.12) schreibt
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
  Eine Zeile muss nicht alle elf Felder tragen (Kulanzregel unten).
  Fehlende Zaehler werden beim Laden als `0` ergaenzt statt die ganze
  Runde zu verwerfen - eine Runde soll nicht verschwinden, nur weil sie
  aelter ist als ein Zaehler. Jede unbekannte Feldzahl sowie ein
  einzelnes Feld, das sein Muster nicht erfuellt (Namen, Datum, Zahlen),
  wirft die ganze Zeile heraus.
  **Ein Zahlenfeld hat hoechstens 15 Ziffern** (`HS_FIELD_NUM_RE`, seit
  1.4.2) - dieselbe Grenze, die die Statistik (`STATS_LINE_RE`) und das
  Protokoll (5.5) immer schon hatten. Ohne sie konnte eine von Hand
  bearbeitete Datei eine Zahl tragen, die Bash nicht darstellen kann,
  und jede Stelle, die danach mit ihr rechnete, ging auf ihre eigene
  Weise daneben: `$(( ))` laeuft still ueber (`fmt_ppm` machte aus
  einer riesigen Teilezahl eine negative Rate), `test -le` und
  `printf %d` schreiben ihre Beschwerde nach STDERR - und STDERR ist in
  einem Vollbild-Programm mitten im Spielfeld, wo der Diff-Renderer sie
  stehen laesst (siehe 4.10). 15 Ziffern mal den 600 aus `fmt_ppm`
  bleiben drei Zehnerpotenzen unter der 64-Bit-Grenze.
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
  **Eine Liste je Modus.** Neben der Marathon-Liste gibt es fuenf
  weitere Dateien mit derselben Bauart. **Warum ueberhaupt getrennt:**
  ein Lauf unter anderen Regeln ist mit einer endlosen Runde nicht
  vergleichbar - ein 150-Rows-Ultra-Lauf, drei Sprint-Minuten oder eine
  Runde unter steigendem Wasser saehen in der endlosen Liste nie einen
  Platz, und umgekehrt wuerden ihre Zahlen die Rangfolge dort
  verfaelschen. Was **allen sechs** gemeinsam ist:

  - Top 10, dieselben elf Felder je Zeile mit dem Runden-Hash am Ende
    (bei Ultra in anderer Reihenfolge, siehe unten; kuerzere Zeilen
    siehe "Kulanz bei der Feldzahl"), dieselbe Muster-Validierung,
    atomares Schreiben.
  - Angezeigt ueber denselben Browser `highscore_browse` mit demselben
    `HS_PAGE_ENTRIES` (gleiche Eintragshoehe - eine zweite Konstante
    koennte nur auseinanderlaufen), zwei Zeilen je Eintrag, gleiche
    Spaltenbreiten und Faerbung, der Score jeweils in der Akzentfarbe.
  - Bei Gleichstand rangiert der **aeltere** Eintrag vorn.
  - Der erreichte Rang steht zusaetzlich im Rundenende-Kasten.

  Die Unterschiede - und nur die - stehen in dieser Tabelle; die
  Entscheidung, welche Zahl ein Modus wertet und welche Laeufe
  ueberhaupt gelistet werden, ist in 3.6 (Einzelspieler) bzw. 5.8
  (Mehrspieler) begruendet:

  | Liste | Datei / Praefix | Sortiert nach | Gelistet wird | Statt der Spielzeit-Spalte |
  | --- | --- | --- | --- | --- |
  | Marathon | `highscore-marathon`, `HS_*` | Rows, absteigend | jede Runde | - (zeigt die Spielzeit) |
  | Ultra | `highscore-ultra`, `HSU_*` | `time`, **aufsteigend** | nur ein Lauf am Ziel | - (Zeit ist der Score) |
  | Sprint | `highscore-sprint`, `HSS_*` | Rows, absteigend | nur ein Lauf ueber die volle Zeit | Lines |
  | Time Attack | `highscore-timeattack`, `HSA_*` | Rows, absteigend | jeder Lauf | - (zeigt die Spielzeit) |
  | Hochwasser | `highscore-flood`, `HSF_*` | Rows, absteigend | jede Runde | - (zeigt die Spielzeit) |
  | Mehrspieler | `highscore-versus`, `HSV_*` | Rows, absteigend | jede Runde | - (zeigt die Spielzeit) |

  Vier Einzelheiten, die sich aus der Tabelle nicht ergeben:

  - **Die Ultra-Liste hat das `time`-Feld vorn**
    (`time|rows|lines|level|name|date|gold|silver|rowhammers|pieces|hash`)
    und speichert es in **Millisekunden** statt in ganzen Sekunden: es
    ist dort das Sortierkriterium, und zwei Versuche auf dasselbe Ziel
    landen oft genug in derselben Sekunde, dass ganze Sekunden die
    Rangfolge nach Eintreffen statt nach Tempo entscheiden wuerden.
    Angezeigt wird sie
    als MM:SS.mmm (`fmt_duration_ms`), die PPM-Spalte rechnet die
    Millisekunden auf ganze Sekunden herunter (die Einheit von
    `fmt_ppm`). Die Rows-Spalte bleibt daneben stehen - um wie viel ein
    Lauf `ULTRA_TARGET_ROWS` ueberschossen hat, ist eine Information.
  - **Die Sprint-Liste zeigt Lines statt der Spielzeit**: jeder Eintrag
    hat dieselben drei Minuten gespielt, eine Zeitspalte stuende dort
    zehnmal gleich. Lines und Rows nebeneinander zeigen dafuer, wie viel
    des Ergebnisses aus den Quadraten kam. Gespeichert bleibt die
    Spielzeit trotzdem - die PPM-Spalte rechnet mit ihr.
  - **Wo die Spielzeit-Spalte steht, verdient sie ihren Platz:** bei
    Time Attack weist eine zu kurze Zeit den Lauf als vorzeitig beendet
    aus (er spielt sonst genau Startzeit + 1 s je Row), bei Hochwasser
    sagt sie, gegen wie viele Flutreihen ein Eintrag angespielt hat, und
    im Mehrspieler trennt sie einen fruehen K.O. von einer
    durchgespielten Runde.
  - **Der Mehrspieler hat nur eine Liste fuer alle drei Sitzungsmodi**
    (`survival`, `sprint`, `ultra`, siehe 5.1) - die eine Stelle, an der
    bewusst *nicht* aufgeteilt wird: sie unterscheiden sich in der
    Siegbedingung, gewertet wird aber ueberall dieselbe Zahl in
    derselben Einheit, und drei Listen mit je zwei Eintraegen waeren
    weniger wert als eine mit sechs. **Der erreichte Platz wird nicht
    gespeichert:** die Liste rangiert, was ein Spieler getan hat, und
    das ist ueber Abende zu zweit und zu fuenft vergleichbar - wer an
    einem bestimmten Abend gewonnen hat, nicht. Wie oft jemand gewonnen
    hat, steht in der Statistik (das `goal`-Feld des Modus, siehe
    unten).

  **Kulanz bei der Feldzahl** (Nutzerentscheidung seit 0.29.0, bewusste
  Ausnahme von "keine Abwaertskompatibilitaet", Abschnitt 6): Eine Liste
  akzeptiert genau die Laengen, die ihr eigenes Format tatsaechlich
  einmal hatte - ein Eintrag soll nicht verschwinden, nur weil er
  aelter ist als ein Feld.

  - **Marathon:** 5, 7, 8, 9, 10 oder 11 Felder (`HS_FIELD_COUNTS`,
    `highscore_parse_line` in `lib/highscore.sh`) - die Stationen des
    schrittweisen Anhaengens von Gold/Silber, Zeit, Rowhammer, Pieces
    und Hash seit dem Punktesystem-Umbau (0.16.0).
  - **Ultra, Sprint, Time Attack:** elf oder zehn, also mit oder ohne
    den Runden-Hash.
  - **Hochwasser und Mehrspieler:** nur elf. Sie sind mit dem Hash
    entstanden und haben nie eine kuerzere Fassung gehabt, gegenueber
    der sie kulant sein muessten.

  Zeilen aus der Zeit **vor** 0.16.0 (fuehrendes `score`-Feld, Rows an
  dritter Stelle) sind ausgenommen: das ist eine andere
  Spaltenreihenfolge und keine bloss kuerzere Version der heutigen -
  ihre Felder wiederzuverwenden wuerde den alten Score faelschlich als
  Rows einordnen.

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
  Lines und Level bleiben gespeichert, werden aber nicht angezeigt; eine
  Score-Spalte gibt es seit dem Punktesystem-Umbau (0.16.0) nicht mehr.
  **Der Zwei-Zeilen-Block ist der Grund, warum ueberhaupt geblaettert
  wird:** ein einzeiliger Eintrag passte mit dem
  Zwei-Zeichen-Menue-Einzug exakt ins 48-Spalten-Minimum, sodass jede
  neue Spalte eine vorhandene bezahlen musste; die zweite Zeile gibt dem
  Namen 12 Zeichen zurueck (gespeichert bleiben bis zu 16) und macht
  Platz fuer PCS und PPM. Die Liste ist damit zu hoch fuer einen
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
  lang wird (`HS_FIELD_NUM_RE` begrenzt die Ziffern eines Feldes, nicht
  die Breite einer ganzen Zeile - eine von Hand editierte Datei kann sie
  also weiter sprengen), verzichtet auf Farbe und faellt auf den
  bisherigen, hart abgeschnittenen Klartext zurueck -
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

Zwei Festlegungen zum Umfang:

- **`all` loescht auch das Savegame.** "Alles" heisst alles; wer nur den
  Weltwunder-Fortschritt zuruecksetzen will, hat dafuer das eigene Ziel
  `save`, das die uebrigen Dateien unangetastet laesst.
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
  Und davor wiederum wird seit 1.5.0 die Zeigerdatei gelesen (4.12), so
  dass ein Reset das Verzeichnis trifft, in dem auch gespielt wird, und
  nicht den leer gewordenen Standardpfad. Die Zeigerdatei selbst ist
  **kein** Reset-Ziel: sie steht ausserhalb des Datenverzeichnisses, und
  ein `--reset all`, das den Weg zu den Daten mit wegraeumt, waere die
  ueberraschendere Antwort - zurueckgelegt wird der Ort ueber denselben
  Menuepunkt, der ihn verlegt hat.
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

### 4.12 Verlegen des Datenverzeichnisses (seit 1.5.0)

Das Datenverzeichnis (4.5) laesst sich im **Einstellungsmenue**
dauerhaft an einen anderen Ort legen (Nutzerwunsch). Bis dahin ging das
nur mit `--data-dir` bzw. `ROWHAMMER_DATA_DIR`, also bei jedem Aufruf
erneut - was praktisch heisst: gar nicht, denn der Starter in
`/usr/games` (4.7) reicht keine Optionen durch. Der Eintrag
**"Speicherort"** steht unter "Demo-Aufzeichnung" und nennt den
aktuellen Pfad; die Mechanik liegt in `lib/datadir.sh`, der Dialog als
`menu_datadir`/`menu_datadir_apply` in `lib/menu.sh` - dieselbe
Aufteilung wie zwischen `lib/demo.sh` und `menu_demos`.

**Der Standardpfad behaelt eine Zeigerdatei.** `${DATA_DIR_DEFAULT}/datadir`
(also `~/.config/rowhammer/datadir`) traegt eine validierte Zeile
`data_dir=<pfad>`. Vier Festlegungen dazu:

- **Eine eigene Datei, kein Wert in `rowhammer.conf`.** Die Config liegt
  *im* Datenverzeichnis und koennte deshalb nicht sagen, wo dieses
  liegt. Die Zeigerdatei ist das Einzige, was am festen Ort bleiben
  muss.
- **Geparst, nicht gesourct** - wie Savegame und Statistik (4.5).
  Gesourct wird allein `rowhammer.conf`, und auch nur, weil das
  Einstellungsmenue sie schreibt. Der gelesene Pfad laeuft danach durch
  dieselbe Pruefung wie ein getippter (`datadir_path_check`): eine von
  Hand bearbeitete Zeigerdatei ist Fremdeingabe, und ihr Wert steht
  gleich in jedem Dateipfad des Spiels.
- **Eine Zeigerdatei, kein Symlink** (Nutzerentscheidung). Der
  Standardordner bleibt damit ein echter Ordner, in dem die Sicherung
  und die Zeigerdatei nebeneinander liegen koennen; ein Symlink haette
  beides ins Ziel verschoben und `--data-dir`/`--reset` mehrdeutig
  gemacht.
- **Der Weg zurueck loescht sie.** Wird als Ziel wieder der
  Standardpfad gewaehlt, schreibt `datadir_link_write` keine Datei,
  sondern raeumt die vorhandene weg: der Standard braucht keinen
  Vermerk, und einer, der "die Daten liegen, wo sie immer lagen" sagt,
  waere nur eine weitere Stelle, die veralten kann.

**Praezedenz: Standard < Zeigerdatei < Env < CLI.** `datadir_link_load`
laeuft in `rowhammer.sh` direkt hinter der Modulschleife und nur, wenn
`DATA_DIR_EXPLICIT` 0 ist - `--data-dir` und `ROWHAMMER_DATA_DIR`
gewinnen also weiter. Der Platz ist zwingend: vor `config_load` (der
ersten Datei, die aus dem Verzeichnis gelesen wird), vor
`highscore_migrate_legacy` (4.5) und vor dem Reset-Block (4.8), damit
`--reset` das Verzeichnis trifft, in dem auch gespielt wird. Solange die
Sitzung per Option oder Umgebung festgelegt ist, aendert der Menuepunkt
nichts, sondern sagt genau das - ein gespeicherter Pfad ohne Wirkung
waere die schlechtere Antwort.

**Was umzieht, ist "der Inhalt".** `datadir_entries` ist die eine
Stelle, die das definiert: jeder Eintrag des Verzeichnisses, versteckte
eingeschlossen, **ausser** der Zeigerdatei und vorhandenen Archiven
(`*.zip`, `*.tar.gz`). Umzug, Sicherung, Loeschen und die
Leer-Pruefung lesen alle sie und koennen sich deshalb nicht
widersprechen. Bewusst keine Liste der bekannten Dateinamen: die
`.bak`-Dateien eines Resets (4.8) und alles, was eine kuenftige Version
dazulegt, gehoeren dem Spieler genauso, und eine Liste liesse sie
stillschweigend zurueck.

**Der Ablauf haengt am Zustand des Ziels** (`datadir_target_state`):

| Zustand | was passiert |
| --- | --- |
| `new` (existiert nicht) | anlegen und verschieben, **ohne Rueckfrage** |
| `empty` | verschieben, ohne Rueckfrage |
| `foreign` (nicht leer, keine `rowhammer.conf`) | verschieben, wenn kein Name kollidiert; sonst Abbruch mit dem kollidierenden Eintrag |
| `config` (traegt `rowhammer.conf`) | die Drei-Wege-Abfrage unten |
| `blocked` (kein Verzeichnis oder nicht beschreibbar) | Meldung, nichts passiert |

Der leere Fall ist der Normalfall und deshalb der rueckfragenfreie
(Nutzerentscheidung): dort ist nichts zu verlieren. Was ein Ziel zu
"jemandes Spieldaten" macht, ist die Anwesenheit von `rowhammer.conf` -
das ist der eine Eintrag, der das sagt, waehrend ein paar fremde Dateien
nur heissen, dass der Ordner nicht leer ist. Ein solches `foreign`-Ziel
wird trotzdem nicht blind bezogen: ein Umzug darf nie stillschweigend
etwas ueberschreiben, also entscheidet die Kollisionspruefung.

**Die Drei-Wege-Abfrage** (`menu_run`, ESC zaehlt wie der erste
Eintrag - die Antwort, die nichts aendert, muss auch die leichteste
sein):

1. **Nichts unternehmen.**
2. **Daten hier verwerfen, Ziel uebernehmen.** Der Inhalt des
   *aktuellen* Verzeichnisses wird als Archiv gesichert, dann die
   Zeigerdatei geschrieben, dann der Inhalt geloescht. Im Normalfall
   bleiben im Standardordner damit genau zwei Dinge liegen: das Archiv
   und die Zeiger-Config.
3. **Daten mitnehmen, Ziel ueberschreiben.** Der Inhalt des *Ziels*
   wird dort als Archiv gesichert, das Ziel geleert, der eigene Inhalt
   hineinverschoben und die Zeigerdatei geschrieben.

Beide zerstoerenden Antworten fragen mit `menu_confirm` noch einmal
zurueck und nennen dabei den betroffenen Pfad; "Nein" ist wie ueberall
vorausgewaehlt (3.1).

**Die Sicherung ist ein `tar.gz`, kein ZIP.** Gewuenscht war ein ZIP;
`zip` gehoert aber nicht zu den Coreutils, und 4.1 laesst keine harte
Abhaengigkeit darueber hinaus zu (Nutzerentscheidung nach Rueckfrage:
lieber `tar.gz` als eine Abhaengigkeit oder ein Format, das von der
Maschine abhaengt). Der Name ist
`backup-YYYYMMDD-HHMMSS.tar.gz`, geschrieben in genau das Verzeichnis,
dessen Inhalt er haelt. Drei Festlegungen:

- **Gepackt werden die Eintraege, nicht das Verzeichnis.**
  `tar -C <verz> -- <eintraege>` statt `tar -C <verz> .` mit
  `--exclude`-Mustern: die Punkt-Form nimmt das Verzeichnis selbst als
  Member auf, und die Temp-Datei, die waehrenddessen darin entsteht,
  laesst `tar` mit "file changed as we read it" abbrechen (Exit 1).
  Die Eintraege zu nennen liest das Verzeichnis gar nicht erst als
  Objekt - und es ist ohnehin genau die Liste aus `datadir_entries`.
- **Vorhandene Archive bleiben draussen** (Nutzervorgabe, urspruenglich
  fuer ein ZIP formuliert): sonst packte jede Sicherung die vorige mit
  ein. Sie werden aus demselben Grund weder verschoben noch geloescht -
  ein Archiv beschreibt das Verzeichnis, in dem es liegt.
  Die Ausnahme gilt nur oben: ein `foo.zip` **in** `demos/` ist Inhalt
  und wandert mit.
- **Ein leeres Verzeichnis bekommt kein Archiv.** Es gibt nichts zu
  sichern, und `tar` weigert sich ohnehin, ein leeres Archiv zu bauen.

**Reihenfolge der Schritte, und warum.** `datadir_link_probe` fragt
**vor** allem Zerstoerenden, ob die Zeigerdatei ueberhaupt schreibbar
waere - scheitert sie erst am Ende, laege die Daten am neuen Ort,
waehrend jeder spaetere Start am alten suchte. In Antwort 2 wird die
Zeigerdatei deshalb **vor** dem Loeschen geschrieben: umgekehrt waeren
die Daten weg und das Spiel saehe weiter in den eben geleerten Ordner.
Ein Umzug, der auf halber Strecke scheitert, **bricht ab und nennt den
Eintrag**, statt zurueckzuraeumen: ein Rueckbau muesste Dateien in ein
Verzeichnis schieben, das sie gerade nicht hergeben wollte.

**Danach wird alles neu gelesen** (`datadir_reload`): Config, die sechs
Bestenlisten, Savegame samt Wunderstand und Statistik. Antwort 2
uebernimmt eine **fremde** `rowhammer.conf`, die eine andere Sprache,
ein anderes Farbschema, einen anderen Namen oder andere Tasten nennen
kann; `i18n_init` und `render_colors_init` laufen deshalb mit, und
`RENDER_FULL=1` sorgt dafuer, dass der Diff-Renderer (4.3) die
geaenderten Beschriftungen wirklich neu schreibt. Die Werte werden dabei
**nachsichtig** geprueft: ein ungueltiger Eintrag behaelt den Wert, den
die laufende Sitzung schon hatte, und vermerkt es im Debug-Log. Beim
Start darf eine kaputte Config mit `die` enden, dort ist noch nichts
verloren; mitten in einer Sitzung darf ausgerechnet ein Umzug nicht das
sein, was sie beendet. Die Dubletten-Regel der Tastenbelegung wird dabei
nicht durchgesetzt - eine doppelt belegte Taste macht eine Aktion
unerreichbar, was der Spieler im Einstellungsmenue repariert, waehrend
das Verwerfen der ganzen Datei die anderen acht Bindungen mitnaehme.

**Im Debug-Log** nennt der Sitzungskopf die Zeigerdatei
(`# datalink:`, 4.6) - ohne sie saehe eine verlegte Sitzung aus wie eine
mit `--data-dir` gestartete.


