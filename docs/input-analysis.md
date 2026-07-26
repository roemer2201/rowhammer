# Analyse der Tastatureingabe (Nachfassen zu Issue #7)

Stand: 2026-07-26, Code-Stand 0.20.0 (`lib/input.sh` 0.5.0)

Ausloeser: Nach dem Fix fuer Issue #7 (Version 0.16.1) gab es weiterhin den
Verdacht, dass andere Tastenkombinationen falsche Aktionen ausloesen.

## 1. Vorgehen

Statt einzelne Faelle zu raten, wurde die Eingabeschicht systematisch
durchgemessen. Dafuer gibt es jetzt `tools/key-scan.sh`: das Werkzeug
spielt 72 Byte-Folgen, die ein Terminal senden kann, durch die echte
`read_key`-Funktion aus `lib/input.sh` und protokolliert, welches Symbol
und damit welche Spielaktion dabei herauskommt.

Abgedeckte Klassen: Pfeiltasten (CSI und SS3), modifizierte Pfeiltasten,
Navigations- und Funktionstasten, Ziffernblock im Application-Mode, die
drei Maus-Protokolle, Terminal-Antworten (CSI, OSC, DCS), 8-Bit-CSI,
Bracketed Paste, Alt-Chords, Steuerzeichen und Nicht-ASCII-Eingaben.

Jeder Fall traegt die Symbole, die korrekterweise herauskommen muessten.
Damit ist das Werkzeug zugleich ein Regressionstest fuer jeden kuenftigen
Umbau der Eingabeschicht:

    tools/key-scan.sh                    # voller Durchlauf
    tools/key-scan.sh -g 0.06 -o arrow   # Sequenzen zerreissen (Issue #7)
    tools/key-scan.sh -v -o mouse        # zeigt, was ein Mausklick einspeist

Bewertung je Fall:

- `ok` - erwartetes Symbol,
- `warn` - Abweichung, aber die durchgereichten Symbole loesen keine
  Spielaktion aus (Kosmetik),
- `FAIL` - Abweichung, und mindestens ein durchgereichtes Symbol loest
  eine echte Spielaktion aus.

Ergebnis im Ist-Zustand: **12 von 72 Folgen loesen eine falsche
Spielaktion aus**, 7 weitere reichen wirkungslose Symbole durch.

## 2. Befunde

### A. Issue #7 ist entschaerft, aber nicht behoben

Der Fix in 0.16.1 hat das Fortsetzungs-Fenster von 20 ms (`TICK_S`) auf
50 ms (`ESC_SUFFIX_T`) vergroessert. Gemessen reisst eine Sequenz ab
einem Byte-Abstand von rund 45 ms weiterhin auseinander - der Fehler ist
also nur unwahrscheinlicher geworden, nicht unmoeglich. Genau die
Bedingungen aus dem Issue (SSH, tmux/screen, Systemlast) erzeugen solche
Abstaende.

    tools/key-scan.sh -g 0.06 -o "arrow "
    FAIL arrow right CSI   -> ESC [ c
         actions  ESC=pause menu, [=no action, c=HOLD

Alle acht Pfeiltasten-Varianten fallen bei 60 ms Abstand aus, und
zusaetzlich alle modifizierten Pfeiltasten. Die Zuordnung des
Schwanz-Bytes ist dieselbe wie im Issue beschrieben: `C` -> `c` = Hold,
`D` -> `d` = nach rechts, `A` -> `a` = nach links.

Zwei Punkte sind dabei neu gegenueber dem urspruenglichen Report:

1. **Das fuehrende ESC ist inzwischen schlimmer als das Schwanz-Byte.**
   Seit 0.12.0 oeffnet `ESC` das Pausenmenue. Eine zerrissene Pfeiltaste
   haelt damit die Runde an, statt nur den Hold-Stein zu tauschen.
2. **Die Ursache ist strukturell, nicht eine Frage des Timeouts.** Der
   Parser entscheidet innerhalb *eines* `read_key`-Aufrufs per Timeout,
   ob ein einzelnes `Esc` oder eine Sequenz vorliegt, und wirft die
   bereits gelesenen Teil-Bytes weg. Jedes weitere Hochdrehen von
   `ESC_SUFFIX_T` verschiebt nur die Schwelle - und verschlimmert
   gleichzeitig Befund G.

### B. Maus-Klicks speisen drei Bytes als Tastendruecke ein

Das aelteste Maus-Protokoll (X10, DECSET 1000) sendet
`ESC [ M <button> <x> <y>`. Das `M` ist ein gueltiges CSI-Endbyte, der
Parser hoert dort korrekt auf - die drei folgenden Rohbytes stehen danach
aber im Puffer und werden als Tastendruecke gelesen. Die Bytes sind
`32 + Wert`, also durchweg druckbare Zeichen:

    FAIL mouse X10 click col 67  -> SPACE c %
         actions  SPACE=hard drop, c=HOLD, %=no action
    FAIL mouse X10 click col 51  -> SPACE s %
         actions  SPACE=hard drop, s=soft drop, %=no action

Das Button-Byte einer linken Maustaste ist `0x20` - **jeder Klick loest
also zuerst einen Hard-Drop aus**, danach je nach Spalte eine weitere
Aktion. Die neueren Protokolle SGR (1006) und urxvt (1015) sind
unauffaellig, weil sie ausschliesslich aus druckbaren Parameter-Bytes
bestehen und sauber auf einem Endbyte enden.

Das Spiel schaltet die Mausmeldungen nie selbst ein - aber auch nie aus.
Ein Modus, den ein vorher gelaufenes Programm gesetzt und nicht
zurueckgenommen hat, bleibt im alternativen Screen aktiv.

### C. OSC- und DCS-Antworten reichen ihre gesamte Nutzlast durch

Nach `ESC` erkennt der Parser nur `[` und `O` als Sequenz-Einleitung.
Alles andere gilt als Alt-Chord und wird als genau zwei Bytes
verschluckt - der Rest der Sequenz landet Zeichen fuer Zeichen im Spiel:

    FAIL reply OSC 11 color   -> 1 1 ; r g b : 2 e 2 e / 3 4 3 4 / ...
         actions  r=restart (game over screen), 2=HOLD, e=rotate cw, ...
    FAIL reply DCS XTVERSION  -> > | x t e r m ( 3 8 8 )
         actions  x=pause menu, e=rotate cw, r=restart, ...
    FAIL reply OSC 52 clipboard -> 5 2 ; c ; d 3 d h c 2 q =
         actions  2=HOLD, c=HOLD, d=move right, q=rotate ccw, ...

Solche Antworten entstehen, wenn ein Programm das Terminal abfragt
(Hintergrundfarbe, Version, Zwischenablage). Das Spiel fragt selbst
nichts ab, aber eine Antwort auf eine Abfrage des vorher laufenden
Programms oder des Multiplexers kann im selben Eingabestrom ankommen.

### D. 8-Bit-CSI wird nicht erkannt

Terminals im 8-Bit-Modus senden `0x9b` statt `ESC [`. Das Byte faellt in
den Standard-Zweig, und das Folgebyte wird eine echte Taste:

    FAIL reply 8-bit CSI up  ->  <0x9b> a      actions  a=move left

### E. CSI-Sequenzen ueber 16 Bytes reissen ab

Die Laengenbremse `n < 16` bricht mitten in langen Sequenzen ab; der Rest
leckt durch. Eine Geraeteantwort mit vielen Parametern endet auf `c`:

    FAIL reply CSI with many params -> 9 ; 1 0 ; ... ; 1 5 c
         actions  c=HOLD

### F. Eingefuegter Text wird als Tastenfolge ausgefuehrt

Bracketed Paste ist nicht eingeschaltet. Der Rahmen `ESC [ 200 ~` wird
zwar korrekt als CSI verschluckt, die Nutzlast danach aber nicht:

    FAIL paste bracketed sentence -> h e l l o SPACE w o r l d
         actions  e=rotate cw, SPACE=hard drop, w=hard drop,
                  r=restart, d=move right

Praktisch relevant ist vor allem der versehentliche Mittelklick-Paste
waehrend des Spiels - er feuert eine ganze Aktionssalve, im Game-Over-
Bild einschliesslich `r` (Neustart).

### G. Umgekehrter Fall: ein echtes `Esc` wird verschluckt

Wird innerhalb von 50 ms nach `Esc` eine weitere Taste gedrueckt,
verschwinden **beide** Tastendruecke ersatzlos (der Alt-Chord-Zweig):

    ESC dann 'c' nach 30 ms  ->  (nichts)

Das ist die Kehrseite von Befund A: `ESC_SUFFIX_T` weiter hochzudrehen
macht diesen Fall haeufiger.

### H. Wirkungslose Durchreicher (`warn`)

Steuerzeichen (Ctrl-A, Ctrl-C, Tab, DEL), UTF-8-Bytes von Umlauten und
das Rad-Ereignis des X10-Protokolls erzeugen Symbole, die auf keine
Aktion gebunden sind. Kein Spielfehler, aber sie sollten sauber
verworfen werden, damit kuenftige Tastenbelegungen nicht versehentlich
darauf treffen.

### I. Geprueft und unauffaellig

Funktionstasten (SS3 und CSI, inklusive der Linux-Konsolen-Form
`ESC [ [ X`), Navigationstasten, Ziffernblock im Application-Mode,
modifizierte Pfeiltasten bei sofortiger Zustellung, SGR- und
urxvt-Mausmeldungen, Focus-Events, DA- und CPR-Antworten, Alt-Chords,
`NUL` (Bash verwirft es, es wird also kein falsches `ENTER` daraus),
Autorepeat-Salven und Grossbuchstaben.

## 3. Loesungsvorschlaege

Alle Vorschlaege betreffen ausschliesslich `lib/input.sh` (L4
zusaetzlich `term_setup`/`term_restore` in derselben Datei). Kein
anderes Modul und keine Persistenzdatei ist betroffen.

### L1 - Escape-Zustandsautomat ueber Tick-Grenzen hinweg (behebt A und G)

Der Kern des Problems ist, dass die Sequenzerkennung in einem einzigen
`read_key`-Aufruf abgeschlossen sein muss. Stattdessen: den Parse-Zustand
(`ESC_STATE`, `ESC_BUF`, `ESC_START_MS`) in Globals halten und je Aufruf
nur *ein* Byte hineinfuettern.

Wirkung: Ein spaet eintreffendes Schwanz-Byte wird weiterhin als Teil der
Sequenz erkannt - unabhaengig davon, wie gross die Luecke war. Die
Fehlzuordnung `C` -> `c` = Hold wird damit unmoeglich, nicht nur
unwahrscheinlich.

Zeitabhaengig bleibt allein die Frage "war das ein einzelnes `Esc`?".
Diese Entscheidung wandert aus dem Lesevorgang heraus und wird am Anfang
von `read_key` getroffen: liegt ein angefangenes `ESC` laenger als
`ESC_LONE_MS` zurueck und ist nichts nachgekommen, wird `ESC` gemeldet.
Empfehlung 300 ms - fuer einen bewussten Esc-Druck nicht spuerbar, fuer
eine zerrissene Sequenz weit jenseits jeder realistischen Luecke.

Nebeneffekt: Befund G verschwindet, weil ein nach `Esc` gedruecktes
Zeichen nicht mehr als Alt-Chord mitverschluckt wird, sondern als eigener
Tastendruck gemeldet werden kann.

### L2 - OSC/DCS/APC/PM/SOS erkennen und verwerfen (behebt C)

Nach `ESC` auch `]`, `P`, `^`, `_` und `X` als Einleitung behandeln und
bis zum String Terminator (`ESC \`) oder `BEL` lesen, mit Laengenbremse.
Der Inhalt wird verworfen - keine dieser Sequenzen ist eine Spieltaste.

### L3 - X10-Mausmeldungen vollstaendig konsumieren (behebt B)

Endet eine CSI-Sequenz auf `M` und begann sie nicht mit `<` (SGR), folgen
genau drei Rohbytes: diese lesen und verwerfen.

### L4 - Bracketed Paste einschalten und Fremdmodi abschalten (behebt F)

In `term_setup` `ESC [ ? 2004 h` senden, in `term_restore` wieder
`ESC [ ? 2004 l`. Trifft der Parser dann auf `ESC [ 200 ~`, verwirft er
alles bis `ESC [ 201 ~`. Ein versehentlicher Paste ist damit folgenlos.

Ergaenzend im selben Zug die Mausmeldungen aktiv abschalten
(`ESC [ ? 1000 l ? 1002 l ? 1003 l ? 1006 l ? 1015 l`), damit ein von
einem Vorgaenger-Programm gesetzter Modus gar nicht erst Klicks
einspeisen kann. Zusammen mit L3 ist das doppelt abgesichert.

### L5 - 8-Bit-CSI und groessere Laengenbremse (behebt D und E)

`0x9b` wie `ESC [` behandeln. Die Bremse von 16 auf 64 Bytes anheben und
beim Ueberlauf nicht abbrechen, sondern bis zum naechsten Endbyte
weiterverwerfen, statt den Rest durchzureichen.

### L6 - Wirkungslose Bytes verwerfen (behebt H)

Am Ende von `read_key` alles verwerfen, was weder ein druckbares
ASCII-Zeichen noch eines der Symbole `ENTER`, `SPACE`, `ESC`, `UP`,
`DOWN`, `LEFT`, `RIGHT` ist. Eine Zeile, entfernt Steuerzeichen- und
UTF-8-Rauschen.

### L7 - Optionaler Schutzwall: Burst-Bremse

Ein Mensch drueckt in einem 20-ms-Tick hoechstens eine Taste. Alles ab
der zweiten oder dritten Taste pro Tick verwerfen faengt jedes
verbleibende Leck generisch ab - auch Pastes und unbekannte Protokolle.

Abwaegung: Die Bremse kann sehr schnelle, aber legitime Eingaben
beschneiden (Autorepeat liefert bei kurzer Wiederholrate durchaus
mehrere Sequenzen pro Tick, siehe den Fall `burst arrows autorepeat`).
Empfehlung: **nicht** als Ersatz fuer L1 bis L6 einbauen, hoechstens
spaeter, falls das Playtesting noch Restfaelle zeigt.

## 4. Empfehlung

L1, L2, L3, L5 und L6 als einen zusammenhaengenden Umbau von `read_key`
(sie teilen sich denselben Zustandsautomaten), L4 als kleine Ergaenzung
in `term_setup`/`term_restore`. L7 vorerst weglassen.

Danach muss `tools/key-scan.sh` ohne `FAIL` durchlaufen - sowohl ohne
Luecke als auch mit `-g 0.06` und `-g 0.2`.
