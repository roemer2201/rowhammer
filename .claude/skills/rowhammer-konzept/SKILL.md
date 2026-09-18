---
name: rowhammer-konzept
description: Das technische Konzept des Spiels rowhammer - Spielregeln, Quadrat-System, Weltwunder, HUD, Spielmodi, Rendering, Eingabe, Persistenz, Demos, Mehrspieler und geplanter Server-Betrieb, jeweils samt Begruendung. Verwende dieses Skill, bevor du an rowhammer.sh, lib/*.sh, tools/*.sh, assets/ oder der Paketierung etwas aenderst oder eine Frage zum Aufbau des Spiels beantwortest, und immer dann, wenn ein Code-Kommentar oder eine Aufgabe auf einen Abschnitt der Form "CLAUDE.md 4.5" bzw. "CLAUDE.md 5.20" verweist.
---

# rowhammer - technisches Konzept

Das Konzept liegt in sieben Dateien unter `docs/konzept/`:

- `spielkonzept.md` - Regeln, Quadrate, Weltwunder, HUD, Spielmodi
- `technik.md` - Modulschnitt, CLI, Game-Loop, Eingabe, Rendering, CI
- `persistenz.md` - Datenverzeichnis, Bestenlisten, Statistik, Reset
- `demos.md` - Demo-Aufzeichnung und -Wiedergabe, Dateiformat
- `mehrspieler.md` - Sitzungen, Transport, Protokoll, Sicherheit
- `server-phase6.md` - geplanter Server-Betrieb, nichts davon gebaut
- `mehrspieler-demo.md` - Demo-Aufzeichnung einer Mehrspieler-Runde

**Welche Datei fuer welchen Abschnitt und welches Code-Modul zustaendig
ist, sagt der Wegweiser in [CLAUDE.md](../../../CLAUDE.md)** - dort
steht die Zuordnung einmal und vollstaendig, samt der Abschnittsnummern
(2 bis 5), mit denen rund 130 Code-Kommentare auf sie verweisen.

**Lies die zustaendige Datei, bevor du den Bereich aenderst.** Sie
traegt nicht nur, was der Code tut, sondern warum er es so tut. Lies
nur die zustaendige: die Dateien sind so geschnitten, dass eine Aufgabe
in der Regel mit einer auskommt.

Die verbindlichen Konventionen und Arbeitsregeln (Abschnitt 6) stehen
ebenfalls in CLAUDE.md und nicht hier - sie gelten in jeder Sitzung und
werden deshalb immer geladen.

## Pflege

Arbeitsregel 6.1 gilt unveraendert, nur mit diesen Dateien anstelle der
frueheren Abschnitte 2 bis 5 der CLAUDE.md: Was eine Funktion **heute**
tut, gehoert hierher; was sie **abgeloest** hat, nach `HISTORY.md`; was
noch **fehlt**, nach `TODO.md`; was Spielerinnen und Spieler sehen,
zusaetzlich in die `README.md`. Eine Angabe steht an genau einer
Stelle.

Ein neuer Abschnitt wird angehaengt, ein bestehender nicht
umnummeriert. Kommt ein Thema dazu, das in keine der sieben Dateien
passt, bekommt es eine achte - und eine Zeile im Wegweiser.
