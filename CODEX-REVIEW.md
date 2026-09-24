# CODEX Review: Mehrspieler-Demoaufzeichnung

**Review-Basis:** Beginn der eigentlichen Aufzeichnung mit Commit `a13167c0a76a3ef04d006f2bf836ec6f2ad80bb0` (Schritt 9.6) bis zur Version `1.4.0` (`064d2ba31785b422cea0fe6b57ef9851217697bf`).

**Scope:** Aufzeichnungsformat, Writer, Empfang/Übernahme der Multiplayer-Ereignisse, Lade-/Replay-Logik sowie die direkt daran beteiligten Teile von `lib/mp.sh`, `lib/hub.sh` und `lib/net.sh`.

## Findings

### 1. Hohe Priorität: Verspätete PEERACT-Ereignisse können im selben Slot hinter neueren Ereignissen aufgezeichnet werden

**Betroffene Funktionen:**
- `lib/demo.sh`: `demo_record_peer_act()`, `demo_slot_event()`
- `lib/mp.sh`: Behandlung von `PEERACT`

Die Aufzeichnung legt für jeden Slot einen einzigen monotonen Ereignisstrom an. Ein `PEERACT` enthält jedoch die ursprüngliche Rundenuhr des Sendefensters; der Empfänger verarbeitet das Fenster erst nach dessen Ankunft. Gleichzeitig können vom Hub stammende Ereignisse (`GARBAGE`, `QUEUE`, `KO`) bereits früher in den lokalen Aufnahmepuffer gelangt sein.

`demo_slot_event()` löst einen Rücksprung der Zeitachse dadurch, dass es ein negatives Delta auf `0` klemmt und anschließend den gespeicherten Zeitstempel nur um dieses tatsächlich geschriebene Delta erhöht. Damit wird ein verspätet eintreffender Zug nicht an seiner ursprünglichen Zeit, sondern hinter dem zuletzt aufgezeichneten Ereignis eingeordnet.

Das ist für eine reine Zeitdarstellung harmlos, nicht aber für den Replay-Stream: Die Reihenfolge der Ereignisse ist damit teilweise **Ankunftsreihenfolge statt ursprünglicher Spielreihenfolge**. Ein konkreter Ablauf ist möglich, wenn ein Mitspieler einen Zug z. B. bei Rundentakt 920 ms ausführt, sein `PEERACT` aber erst nach einem bei 1000 ms eintreffenden Hub-Ereignis verarbeitet wird. Der Zug wird dann auf 1000 ms geklemmt und im Stream hinter das Hub-Ereignis gestellt.

Beim Replay werden die Zugereignisse über die normalen Spieloperationen ausgeführt. Dadurch kann ein Zug, der in der Originalrunde noch vor einem Lock/Gravity-Schritt lag, im Replay erst danach ausgeführt werden. Das kann die Position, den Lockzeitpunkt und damit den weiteren Brettverlauf verändern. Die vorhandenen Checkpoints können diesen Drift anschließend nur feststellen; sie können die verlorene zeitliche Ordnung nicht wiederherstellen.

**Empfehlung:** Ursprüngliche Ereigniszeit und Empfangszeit getrennt erhalten. Für `PEERACT` sollte die ursprüngliche Zeitbasis des Fensters erhalten bleiben; Hub-Ereignisse benötigen ihre eigene Sequenz-/Empfangsinformation. Für das Replay sollte anschließend nach der ursprünglichen Ereigniszeit sortiert bzw. eine explizite Kausalitätsreihenfolge verwendet werden, statt verspätete Ereignisse durch Delta-Klemmung an das Ende des Streams zu hängen.

### 2. Mittlere Priorität: Ein fehlendes ROSTER-Update kann ein verlorenes Mitglied als Top-Out aufzeichnen

**Betroffene Funktionen:**
- `lib/demo.sh`: `demo_record_ko()`, `demo_ko_flush()`
- `lib/mp.sh`: `KO`-/`ROSTER`-Verarbeitung
- `lib/hub.sh`: `hub_eliminate()` / `hub_client_close()`

Ein `KO` enthält nur Slot und Platz. Die Aufzeichnung merkt sich deshalb zunächst nur den Platz und wartet auf das anschließende `ROSTER`, um zwischen `ko` (Top-Out) und `gone` (Verbindungsverlust) zu unterscheiden.

Beim Schließen der Aufnahme werden jedoch noch offene KO-Marker in `demo_ko_flush()` **immer als `n` (Top-Out)** geschrieben. Genau der Fall, für den die Verzögerung eingeführt wurde - ein ausbleibendes Status-Update - wird damit zu einer falschen Ursache.

Das kann passieren, wenn nach dem `KO` die Verbindung bzw. der Hub verschwindet, bevor die noch ausstehende `ROSTER`-Nachricht den aufzeichnenden Client erreicht. Der Datensatz enthält danach einen syntaktisch gültigen, aber inhaltlich falschen `n<place>`-Eintrag. Beim Replay erscheint der betroffene Spieler als ausgeschieden statt als Verbindungsverlust.

**Empfehlung:** Beim Flush einen unbekannten Zustand nicht automatisch als `n` klassifizieren. Für den Fall, dass die Ursache nicht mehr sicher bestimmt werden kann, sollte entweder ein eigener unklarer Abschlusszustand im Format verwendet oder die Aufnahme als nicht vollständig klassifiziert werden. Alternativ kann die Aufzeichnung beim Sitzungsabbruch die letzte bekannte Ursache explizit markieren.

## Hinweise ohne Befund

- Die in Schritt 9.13 bereits behobenen Probleme (teilweise gelesene Hub-Zeile, Countdown-Drain vor Rundendbeginn, fehlender letzter `STATE`, Position des eigenen Checkpoints) sind im aktuellen Stand berücksichtigt.
- Die Piece-Top-up-Logik ist konservativ: `h|k|o` kann bei einem abgelehnten `hold` eine zusätzliche Reserve zählen, führt also eher zu überzähligen aufgezeichneten Steinen als zu einem zu kurzen Stream.
- Die Formatprüfung schützt gegen ungültige Slot-/Eventformen und verhindert, dass Versus-Aufnahmen als Einzelspielerströme geladen werden.

## Kurzfazit

Die wichtigste offene Schwachstelle ist die Vermischung von **Ursprungszeit und Ankunftszeit** im per-Slot-Stream. Dadurch kann eine syntaktisch korrekte Aufnahme den tatsächlichen Kausalverlauf einer Multiplayer-Partie verändern. Die KO-Fallback-Logik ist ein separater, kleinerer Genauigkeitsfehler beim Abbruch der Verbindung.

---

# Ergänzung: Singleplayer-Review (2026-09-24)

**Basis:** `main` bei Commit `cc329000e8591ab249c4d066b996c2b5fa4741e0` (Version 2.0.3). Geprüft wurden Spiellogik, Modi, Eingabe, Persistenz und die Einzelspieler-Demo. Die folgenden Befunde sind statisch aus den Aufrufketten abgeleitet; ein interaktiver Lauf wurde nicht durchgeführt. Die beiden älteren Mehrspieler-Befunde oben bleiben unverändert und wurden hier nicht erneut bewertet.

## Befunde

### SP-01 · Mittel: Rundenname und Name in der Demo widersprechen sich

**Stellen:** `rowhammer.sh:1829-1834, 1848-1862, 1975`; `lib/demo.sh:1161-1162, 1221-1224`; `lib/menu.sh:1661-1701`.

Nimmt eine Runde einen Bestenlistenplatz ein, kann der Spieler im Abschlussdialog einen anderen Namen als den in den Einstellungen hinterlegten `PLAYER_NAME` eingeben. `record_round` übergibt diesen `ROUND_NAME` an `round_book`; Bestenlisteneintrag und Runden-Hash verwenden den eingegebenen Namen. `demo_record_finish` erhält aber nur Ende und Hash und schreibt im Demo-Header weiterhin `name=${PLAYER_NAME}`. Beispiel: Standardname „Player“, für die Runde „Alice“ eingegeben → Bestenliste „Alice“, zugehörige Aufnahme `name=Player`. Der Hash verknüpft beide Dateien weiterhin, aber die Aufnahme weist die Runde der falschen Person zu.

**Vorschlag:** Den tatsächlich gewählten Namen an `demo_record_finish` übergeben und für `name=` verwenden. Bei Versus-Aufnahmen klären, ob zusätzlich der ursprüngliche Sitzungsname getrennt erhalten bleiben soll.

**Prüfung nach Korrektur:** Mit Standardname „Player“ eine platzierte Einzelspieler-Runde als „Alice“ abschließen; Bestenliste und Demo-Header müssen „Alice“ zeigen und die Aufnahme muss aus der Bestenliste startbar bleiben.

### SP-02 · Mittel: Systemuhrsprung verändert Spielzeit und Modusfristen

**Stellen:** `rowhammer.sh:1495-1503, 1606-1610, 1649-1657, 2885-2909`; `lib/demo.sh:752-760`.

`now_ms` liest mit `EPOCHREALTIME` beziehungsweise `date +%s%N` die verstellbare Systemzeit. `play_clock_tick` addiert `NOW_MS - PLAY_LAST` ungeprüft zur Spielzeit. Wird die Uhr während einer Runde zurückgestellt, sinkt `PLAY_MS` und kann sogar negativ werden; Zeitangriff, Sprint und Hochwasser gewinnen dadurch Zeit, und die Demo kann Zeitstempel in falscher Reihenfolge erhalten. Ein Sprung nach vorn lässt Zeitlimits, Hochwasser und Lock Delay sofort ablaufen. Die Rücksprungbehandlung in `clear_pause_step` schützt nur dessen eigene Frist, nicht die zentrale Spieluhr.

**Vorschlag:** Fristen und verstrichene Spielzeit auf einer monotonen Uhr führen; die Kalenderzeit nur für Datumsfelder und Dateinamen verwenden. Falls kein monotoner Zeitgeber verfügbar ist, Uhrsprünge ausdrücklich erkennen und die verstrichene Zeit begrenzen, ohne Sprünge als gespielte Zeit zu buchen.

**Prüfung nach Korrektur:** Während einer laufenden Sprint- und Hochwasser-Runde die Systemzeit vor- und zurückstellen; Spielzeit und nächste Frist müssen gleichmäßig weiterlaufen.

### SP-03 · Niedrig: Die zehnte Demo derselben Sekunde überschreibt eine bestehende Aufnahme

**Stelle:** `lib/demo.sh:1197-1204, 1324`.

Bei gleichem Sekundenstempel probiert `demo_record_finish` erst den Namen ohne Zähler und dann die Suffixe 2 bis 9. Sind alle neun Pfade belegt, verlässt die Schleife bei `i=10` den Block, obwohl der zuletzt gebildete Pfad mit Suffix 9 weiterhin existiert. Das anschließende `mv -f` ersetzt dessen Aufnahme. Im normalen manuellen Spiel ist die Häufung unwahrscheinlich; bei automatisierten sehr kurzen Runden oder einer zurückgesetzten Systemuhr gehen so dennoch Aufnahmen verloren, möglicherweise auch eine von der Bestenliste referenzierte.

**Vorschlag:** Den Zähler ohne feste Obergrenze weitersuchen lassen und den Zielpfad unmittelbar vor dem Verschieben gegen eine bestehende Datei absichern.

**Prüfung nach Korrektur:** Neun gleichnamig datierte Demo-Dateien vorgeben und eine weitere Aufnahme abschließen; alle zehn Dateien müssen erhalten bleiben.
