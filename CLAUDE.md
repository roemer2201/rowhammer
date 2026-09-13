# CLAUDE.md - rowhammer

Diese Datei gibt Claude Code (und menschlichen Mitwirkenden) den
Einstieg in dieses Repository: was das Projekt ist, wo das technische
Konzept steht und nach welchen Regeln daran gearbeitet wird. Sie ist
bewusst kurz - sie wird in **jeder** Sitzung geladen und kostet dort
Kontext (Claude Code empfiehlt unter 200 Zeilen je CLAUDE.md).

**Wo steht was:**

| Datei | Inhalt |
| --- | --- |
| **CLAUDE.md** (diese) | Projektueberblick, Wegweiser, verbindliche Konventionen |
| [docs/konzept/](docs/konzept/) | das technische Konzept, Abschnitte 2 bis 5 (Tabelle unten) |
| [TODO.md](TODO.md) | offene Punkte - Roadmap und Entscheidungen |
| [HISTORY.md](HISTORY.md) | Archiv der erledigten Punkte, nach Version |
| [README.md](README.md) | Anleitung fuer Spielerinnen und Spieler |

Die Aufteilung ist eine Arbeitsregel (Abschnitt 6) und keine blosse
Ordnung: Was eine Funktion **heute** tut, steht im Konzept; **was sie
abgeloest hat** und warum, steht in HISTORY.md beim jeweiligen
Versionseintrag; **was noch fehlt**, in TODO.md. Eine Angabe steht
jeweils an genau einer Stelle, die anderen verweisen darauf.

Gliederung: Abschnitt 1 ordnet das Projekt ein, 2 nennt das Vorbild, 3
beschreibt das Spielkonzept, 4 die technische Umsetzung, 5 den
Mehrspieler und den geplanten Server-Betrieb, 6 die verbindlichen
Konventionen. Hier stehen 1 und 6; die Abschnitte 2 bis 5 stehen in den
Konzeptdateien. Die Nummerierung ist stabil - rund 130 Kommentare in
`rowhammer.sh`, `lib/*.sh`, `tools/*.sh` und den Workflows verweisen
mit ihr auf einzelne Abschnitte ("siehe CLAUDE.md 5.20"); ein solcher
Verweis meint den gleichnamigen Abschnitt in der Konzeptdatei, die die
Tabelle unten nennt.

## 1. Projektueberblick

**rowhammer** ist ein Tetris-artiges Spiel, das vollstaendig in **Bash** im
Terminal laeuft. Vorbild ist **"The New Tetris"** fuer das Nintendo 64:

- Ueber alle Runden hinweg wird an einem **Weltwunder** gebaut. Der Baufortschritt
  richtet sich nach der **Gesamtzahl der abgebauten Reihen**.
- Das **Quadrat-System** des Originals ist enthalten: Aus Bausteinen gebildete
  4x4-Quadrate werden zu **Gold-** (sortenrein) bzw. **Silber-Bloecken**
  (gemischt) und liefern beim Abbau Bonus-Reihen.
- Eine **Mehrspieler-Funktion** gibt es seit 1.1.0: zwei bis fuenf
  Leute im lokalen Netz, jeder an seinem eigenen Feld mit derselben
  Steinfolge (siehe Abschnitt 5).

Der Repo-Name "rowhammer" ist ein Wortspiel: Es geht ums "Hammern" von Reihen
(rows), nicht um den gleichnamigen Hardware-Angriff.

## Wegweiser: welches Konzept wo steht

**Lies die zustaendige Konzeptdatei, bevor du den Bereich aenderst** -
sie traegt nicht nur, was der Code tut, sondern warum er es so tut, und
eine Aenderung, die ihre Begruendung nicht kennt, macht die Datei zur
Luege. Lies nur die zustaendige: die Dateien sind so geschnitten, dass
eine Aufgabe in der Regel mit einer auskommt. Alle Pfade unterhalb von
`docs/konzept/`.

| Datei | Abschnitte | Thema | betrifft |
| --- | --- | --- | --- |
| `spielkonzept.md` | 2, 3.1-3.7 | Kernregeln, Steuerung, Lock Delay, Gold-/Silber-Quadrate, Reihenwertung, Weltwunder, HUD, Anleitung, Spielmodi, Namensabfrage | `lib/board.sh`, `lib/pieces.sh`, `lib/squares.sh`, `lib/wonders.sh` |
| `technik.md` | 4.1-4.4, 4.6, 4.7, 4.9, 4.11 | Rahmenbedingungen, Modulschnitt, CLI-Optionen, Game-Loop, Eingabe, Rendering, Debug-Modus, Paketierung, Release/CI, Mehrsprachigkeit | `rowhammer.sh`, `lib/render.sh`, `lib/input.sh`, `lib/i18n.sh`, `lib/lang/`, `debian/`, `.github/` |
| `persistenz.md` | 4.5, 4.8, 4.12 | Datenverzeichnis, Config, die sechs Bestenlisten, Savegame, Statistik, `--reset`, Verlegen des Speicherorts | `lib/config.sh`, `lib/highscore.sh`, `lib/save.sh`, `lib/stats.sh`, `lib/datadir.sh` |
| `demos.md` | 3.8, 4.10 | Demo-Aufzeichnung und -Wiedergabe, Dateiformat, Ablage, Runden-Hash | `lib/demo.sh` |
| `mehrspieler.md` | 5. Einleitung, 5.1-5.10 | Sitzungen, Transport, Prozessmodell, Protokoll, Sicherheit, Gegner-Darstellung, Garbage, Rundenende, CLI | `lib/net.sh`, `lib/proto.sh`, `lib/hub.sh`, `lib/mp.sh` |
| `server-phase6.md` | 5.11-5.19 | **geplant, nichts davon gebaut**: dedizierter Server, Accounts, Server-Datenbank, Web-Highscore, Abzeichen | - |
| `mehrspieler-demo.md` | 5.20 | Demo-Aufzeichnung einer Mehrspieler-Runde, Rundenzustaende per Nameref, Formatversion 3 | `lib/state.sh`, `lib/demo.sh`, `lib/mp.sh` |

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
  Standard < Config < Env < CLI - welche Werte ueberhaupt in der Config
  landen, sagt die Optionstabelle in 4.2).
- Variablen immer als `"${var}"` schreiben.
- Fehler mit aussagekraeftiger Meldung nach STDERR; STDERR von Befehlen nicht
  unterdruecken; Exit-Code 0/!=0, Aufruffehler 2.
- Begruendungskommentare bei spaeteren Aenderungen bewahren.

Hinweis: Das Spiel ist interaktiv; die Logging-Regeln fuer cron/systemd sind
hier nachrangig, die uebrigen Regeln gelten uneingeschraenkt.

### 6.1 Arbeitsregeln fuer die Dokumentation

Arbeitsregel: **Jede Markdown-Datei hat eine Rolle**, und eine Angabe
steht an genau einer Stelle (Tabelle im Kopf dieser Datei). Wer etwas
fertigstellt, pflegt alle:

1. **Aktuellen Zustand nachziehen.** Was die Funktion *heute* tut,
   gehoert in die zustaendige Konzeptdatei (Wegweiser oben) - und,
   soweit es Spielerinnen und Spieler sehen (Menuepunkte, Tasten,
   CLI-Optionen, Dateien im Datenverzeichnis), zusaetzlich in die
   README.md.
2. **Erledigtes nach HISTORY.md verschieben**, samt seiner Begruendung
   und der Abnahme (Archiv, nach Version geordnet, mit
   Uebersichtstabelle). Was die Version **abgeloest** hat, gehoert als
   _"Vorzustand: ..."_ ebenfalls dorthin und nicht in die Beschreibung
   im Konzept - das fuehrt den heutigen Stand samt seiner Begruendung,
   nicht die Geschichte davor.
3. **Ueberholtes markieren.** Loest die neue Version eine aeltere ab,
   bekommt der aeltere Eintrag in HISTORY.md eine Zeile
   _"Spaeter ueberholt: ..."_ mit Verweis auf die abloesende Version.
4. **Den Punkt aus TODO.md streichen** und die Querverweise pruefen -
   im Konzept, in der README und in den Code-Kommentaren.

Arbeitsregel: **Die Abschnittsnummern des Konzepts sind stabil.** Rund
130 Kommentare in `rowhammer.sh`, `lib/*.sh`, `tools/*.sh` und den
Workflows verweisen mit ihnen auf einzelne Abschnitte ("siehe CLAUDE.md
5.20"). Ein neuer Abschnitt wird angehaengt, ein bestehender nicht
umnummeriert; wird eine Umnummerierung doch einmal unvermeidlich, sind
diese Verweise im selben Zug nachzuziehen. Dass ein Abschnitt in eine
andere Konzeptdatei wandert, ist dagegen folgenlos - der Verweis nennt
die Nummer, nicht die Datei; nachzuziehen ist dann allein der Wegweiser
oben.

Arbeitsregel: **Die CLAUDE.md bleibt kurz.** Sie wird in jeder Sitzung
geladen, das Konzept nur bei Bedarf; ein neuer Absatz gehoert deshalb
in eine Konzeptdatei, nicht hierher. Hierher gehoert nur, was in
**jeder** Sitzung gilt: Projektidentitaet, Wegweiser, Konventionen.

Arbeitsregel: **Aenderungen an TODO.md duerfen direkt auf dem
`main`-Branch** vorgenommen werden, auch ohne eigenen Feature-Branch
oder Pull Request. Dasselbe gilt fuer HISTORY.md, soweit nur bereits
erledigte Punkte dorthin verschoben oder dort nachgetragen werden.

### 6.2 Arbeitsregeln fuer den Code

Arbeitsregel: **`2.0.0` kommt erst, wenn der Mehrspieler fertig ist**
(Nutzerentscheidung, ueberarbeitet mit 1.1.0). Bis dahin laeuft die
Arbeit am Mehrspieler in der **`1.x`-Reihe** weiter, Seite an Seite mit
allem anderen, was am Spiel nachgezogen wird: eine Minor-Version je
Zuwachs, eine Patch-Version je Korrektur. Eine Versionsnummer ist eine
Aussage ueber den Zustand, nicht ueber die Menge der Arbeit - `2.0.0`
ist deshalb dem Stand vorbehalten, an dem Phase 5 abgeschlossen ist:
die Demo-Aufzeichnung einer Mehrspieler-Runde steht seit 1.4.0 (5.20),
offen ist allein die vollstaendige Entkopplung der Rundenlogik (5.3,
siehe TODO.md); die Server-Phase 6 baut danach darauf auf. SemVer
traegt das: die Formate des Mehrspielers (Protokoll,
Sitzungsverzeichnis) sind bislang nur untereinander im Umlauf, und die
Regel darunter laesst sie ohnehin
brechen - eine Protokollversion, die ein alter Client nicht kennt, weist
der Hub sauber ab.

Arbeitsregel: **Keine Abwaertskompatibilitaet noetig.** Das Projekt wird
sequenziell entwickelt und war nie anderswo installiert; Migrationslogik
fuer alte Config-/Savegame-Formate oder alte Schnittstellen ist unnoetig
und soll weggelassen werden. Formate duerfen bei Bedarf einfach brechen.
Wo bewusst davon abgewichen wurde, steht es an Ort und Stelle: die
Feldzahlen der Bestenlisten (4.5), die einmalige Umbenennung der
Marathon-Liste (4.5) und die Demo-Formatversionen 2 und 3 (4.10).
