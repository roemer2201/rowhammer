# Dezimale Protokollzahlen und frueh abgebrochene Demo-Aufnahmen

Beauftragt am 2026-10-10; Umsetzung im offenen Korrektur-PR fuer 2.0.4.

1. MP-04 zuerst: Alle Zahlenfelder der Klasse `n` nach vollstaendiger
   Formpruefung zentral in `proto_parse` mit `10#` normalisieren.
   Fuehrende Nullen bleiben erlaubt; Ping/Pong-Tokens und gepackte
   Zugdaten behalten ihren Wortlaut. Regressionen pruefen Parser und
   echte Hub-/Client-Arithmetik, Grenzwerte und ungueltige Nachrichten.
2. Konzept, Review, TODO und Versionshistorie aktualisieren und die
   Protokollkorrektur als eigenen Commit abschliessen.
3. DEMO-01 danach: Benannte Versus-Sitze ohne Ereignis behalten ihren
   gueltigen Anfangszustand. Writer und Loader muessen fuer frueh
   abgebrochene Aufnahmen zusammenpassen; vollstaendig ereignislose
   Aufnahmen bleiben ausgeschlossen. Regressionen pruefen echte
   Aufzeichnung, Laden und Wiedergabe mit leeren Sitz-Streams.
4. Demo-Dokumentation und Review aktualisieren, die zweite Korrektur
   separat committen und die relevanten bestehenden Checks ausfuehren.
5. Den bestehenden PR aktualisieren. Die dokumentierte Option, die
   Systemuhr nur einmal pro Sekunde gegen Uptime zu pruefen, bleibt
   ausdruecklich unimplementiert.
