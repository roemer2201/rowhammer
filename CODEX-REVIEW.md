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
