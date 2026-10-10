# Bereinigte Spieluhr und Zuschauerzeit

Freigegeben am 2026-10-10. Ausgangspunkt: 2.0.3.

1. Die Millisekunden-Aufloesung von `EPOCHREALTIME` bzw. `date` bleibt
   erhalten. Eine zentrale Uhr vergleicht die Systemzeit mit Linux
   `/proc/uptime` und rechnet erkannte Vorwaerts- und Rueckwaertsspruenge
   durch einen persistenten Offset heraus.
2. Die Erkennung beruecksichtigt die 10-ms-Aufloesung der Kontrolluhr
   und die Zeit zwischen den Messungen. Echte Prozesspausen werden nicht
   als Uhrsprung behandelt. Kleine Aenderungen innerhalb der Toleranz
   sind nicht sicher erkennbar; bei einer Korrektur bleibt eine begrenzte
   Messunsicherheit. Die bereinigte Uhr darf nicht rueckwaerts laufen.
3. Die persoenliche Spielzeit wird beim Ausscheiden einmalig gestoppt.
   Zuschauen bis zum Ende der Mehrspieler-Runde und ein Terminal-Resize
   starten sie nicht erneut. Die gemeinsame Rundenuhr laeuft weiter.
4. Regressionstests simulieren normale Millisekunden-Schritte, beide
   Sprungrichtungen, echte Verzoegerungen und das Ausscheiden mit
   anschliessender Zuschauerphase. Bestehende Checks werden ausgefuehrt.
5. Konzept, Review und Versionsdokumentation werden auf den geprueften
   Stand gebracht. Plan und Implementierung erhalten getrennte Commits;
   die Umsetzung wird als Pull Request bereitgestellt.
