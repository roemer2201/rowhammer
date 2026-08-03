# Release-Prozess und CI

Diese Datei beschreibt, wie aus dem Stand auf `main` ein
veroeffentlichtes rowhammer-Release wird: welche Versionsangaben es gibt,
wie ein Release-Tag entsteht, was die beiden GitHub-Actions-Workflows
tun und welche Dateien am Ende an einem Release haengen.

Der **aktuelle** Stand der Paketierung selbst (Layout, `Makefile`,
`debian/`, `rowhammer.spec`) steht in CLAUDE.md Abschnitt 4.7; hier geht
es nur um den Weg vom Commit zum Release.

## 1. Versionsschema und Tag-Namen

- Die Version folgt **SemVer** (`MAJOR.MINOR.PATCH`), wie es die
  Script-Konventionen fuer alle Skripte des Projekts vorgeben. Das
  Projekt ist in der `0.x`-Phase; jede umgesetzte Roadmap-Position
  bekommt ueblicherweise eine neue MINOR-Version.
- Der Release-Tag ist die Version mit fuehrendem `v`: `v0.39.0`. Auf
  dieses Muster reagiert der Release-Workflow, der Praefix ist also Teil
  der Schnittstelle und kein Schmuck.
- **Keine Vorab-Versionen** (`v0.40.0-rc1` o. ae.). rowhammer wird als
  *natives* Debian-Paket gebaut, und eine native Paketversion darf keinen
  Bindestrich enthalten - ein RC-Tag liesse sich also gar nicht als
  `.deb` bauen. Der Release-Workflow weist ein solches Tag deshalb
  gleich zu Beginn ab, statt spaeter in `dpkg-buildpackage` zu scheitern.

## 2. Die drei Stellen mit der Version

Die Versionsnummer steht an drei Stellen, weil jede davon fuer ein
anderes Publikum die Wahrheit ist:

| Datei | Stelle | Bedeutung |
| --- | --- | --- |
| `rowhammer.sh` | `ROWHAMMER_VERSION` | Was das Spiel ueber sich selbst sagt (`--help`, Debug-Log-Kopf). Referenz fuer alles Weitere. |
| `debian/changelog` | Kopfzeile der obersten Strophe | Version des Debian-Pakets **und** Quelle der Release-Notes. |
| `rowhammer.spec` | `Version:` plus `%changelog` | Version des RPM-Pakets. |

`tools/release.sh` ist das einzige Werkzeug, das alle drei kennt. Es
prueft nicht nur, ob die Nummern uebereinstimmen, sondern auch, ob beide
Changelogs die Version wirklich dokumentieren - eine Version ohne
Changelog-Eintrag ergaebe ein Release ohne Release-Notes.

```
./tools/release.sh --mode check          # stimmen alle drei ueberein?
./tools/release.sh --mode version        # welche Version ist das hier?
./tools/release.sh --mode notes          # Release-Notes als Markdown
./tools/release.sh --mode tag --push     # Tag anlegen und pushen
```

## 3. Ablauf eines Releases

1. **Aendern und dokumentieren.** Die Aenderung selbst, dazu CLAUDE.md,
   HISTORY.md und README.md gemaess der Arbeitsregeln aus CLAUDE.md
   Abschnitt 6.
2. **Version hochzaehlen** - an allen drei Stellen aus Abschnitt 2:
   `ROWHAMMER_VERSION` in `rowhammer.sh`, eine neue Strophe in
   `debian/changelog`, `Version:` und ein `%changelog`-Eintrag in
   `rowhammer.spec`.
   Die Strophe in `debian/changelog` ist zugleich der Text, den das
   Release spaeter zeigt - sie wird also fuer Leserinnen und Leser
   geschrieben, nicht als Stichwortliste.
3. **Lokal pruefen:** `./tools/release.sh --mode check` und, wenn man den
   Text sehen will, `./tools/release.sh --mode notes`.
4. **Mergen nach `main`** und abwarten, dass der CI-Workflow gruen ist.
   Der Release-Workflow prueft zwar selbst noch einmal, aber ein Tag auf
   einem roten Commit erspart niemandem etwas.
5. **Taggen:** `./tools/release.sh --mode tag --push`. Das Skript weigert
   sich bei unsauberem Arbeitsbaum, bei einer Versions-Abweichung und bei
   einem bereits vorhandenen Tag; die Release-Notes werden zur
   Tag-Nachricht, sodass der Tag selbst schon traegt, was das Release
   sagt.
6. **Fertig.** Der Push des Tags startet den Release-Workflow, der die
   Pakete baut und das GitHub-Release mit seinen Assets anlegt.

## 4. Die beiden Workflows

### `.github/workflows/ci.yml` - bei jedem Push und Pull Request

Laeuft auf `main`, auf `claude/**`-Branches und bei Pull Requests gegen
`main`. Fuenf Jobs:

- **checks** - `bash -n` ueber jedes Skript, ShellCheck, ASCII-Pruefung
  und `release.sh --mode check`.
  ShellCheck blockiert bewusst nur auf der Stufe **error**: auf dieser
  Stufe ist der Baum sauber, waehrend die verbleibenden Warnungen
  Fehlalarme der Modul-Architektur sind (`lib/*.sh` wird in das
  Hauptskript gesourct, seine Variablen wirken einzeln geprueft ungenutzt
  - SC2034 - und seine Arrays wie Skalare - SC2128, SC2178). Der
  vollstaendige Bericht wird trotzdem ausgegeben, nur eben ohne den Job
  scheitern zu lassen.
  Die ASCII-Pruefung deckt Skripte, `assets/` und die Paketier-Dateien
  ab, nicht aber die Dokumentation: die ist Fliesstext, und
  `docs/demo/` enthaelt Binaerdateien.
- **input-regression** - `tools/key-scan.sh`, einmal normal und einmal
  mit `--gap 0.06`. Das ist der Regressionstest zu Issue #7 (zerrissene
  Escape-Sequenz, deren Restbyte als andere Taste ankam); der zweite Lauf
  reproduziert die stueckweise Zustellung ueber SSH und in tmux.
- **package-deb** - baut das Debian-Paket, **installiert** es und ruft
  das installierte Spiel auf. Der Starter ist ein relativer Symlink nach
  `/usr/share`, ein falscher Pfad faellt also erst nach der Installation
  auf. Danach wird das Paket wieder entfernt und geprueft, dass nichts
  liegen bleibt.
- **package-rpm** - baut das RPM auf dem Ubuntu-Runner (`build-rpm.sh`
  gibt dafuer `--nodeps` mit, siehe die Begruendung im Skript).
- **verify-rpm** - installiert das gebaute RPM in einem
  Fedora-Container. Das ist die einzige Stelle, an der der
  `%files`-Abschnitt wirklich geprueft wird, samt des bewusst
  mitbesessenen Verzeichnisses `/usr/games` (CLAUDE.md 4.7).

Als Spielprogramm laesst sich rowhammer im CI nur begrenzt ausfuehren -
es braucht ein Terminal. Die beiden Pfade, die ohne TTY laufen, sind
`--help` und `--reset`; genau die nutzen die Smoke-Tests.

### `.github/workflows/release.yml` - bei einem Tag `v*`

- **verify** - leitet die Version aus dem Tag-Namen ab, weist ein Tag mit
  Vorab-Suffix ab (siehe Abschnitt 1), prueft mit
  `release.sh --mode check --expect <version>`, dass der Baum dieselbe
  Version traegt wie das Tag, und laesst den Eingabe-Regressionstest
  laufen. Ein Tag darf auf jedem beliebigen Commit sitzen, deshalb prueft
  das Release fuer sich selbst nach und verlaesst sich nicht auf den
  CI-Lauf des Branches.
- **build** - baut `.deb`, `.rpm` und `.src.rpm`, packt zusaetzlich ein
  Quell-Tarball des getaggten Commits (`git archive`, damit das Tarball
  zum Tag passt und nicht zu dem, was im Arbeitsbaum lag), macht den
  Installations-Smoke-Test des Debian-Pakets, bildet `SHA256SUMS` und
  legt das GitHub-Release an.

Das Release wird mit der auf dem Runner vorinstallierten `gh`-CLI
angelegt statt mit einer fremden Action - eine Abhaengigkeit weniger in
einem Workflow, der Schreibrechte auf das Repository hat. Existiert das
Release schon, wird es aktualisiert statt als Fehler behandelt; ein Lauf,
der auf halber Strecke abgebrochen ist, laesst sich damit einfach
wiederholen (`workflow_dispatch` mit dem Tag als Eingabe).

## 5. Assets eines Releases

| Datei | Inhalt |
| --- | --- |
| `rowhammer_<version>_all.deb` | Debian-/Ubuntu-Paket |
| `rowhammer-<version>-<release>.noarch.rpm` | RPM-Paket |
| `rowhammer-<version>-<release>.src.rpm` | RPM-Quellpaket |
| `rowhammer-<version>.tar.gz` | Quell-Tarball des getaggten Commits |
| `SHA256SUMS` | Pruefsummen aller obigen Dateien |

Die `.changes`- und `.buildinfo`-Dateien, die `dpkg-buildpackage`
daneben erzeugt, werden bewusst **nicht** angehaengt: sie sind
Build-Metadaten, die niemand herunterlaedt.

## 6. Release-Notes

Der Text eines Releases ist die Strophe aus `debian/changelog` zu dieser
Version, aufbereitet von `tools/release.sh --mode notes`: Ueberschrift,
die Changelog-Punkte als Markdown-Liste und ein kurzer
Installationsabschnitt.

Der Grund fuer diese Quelle: das Changelog muss fuer das Debian-Paket
ohnehin geschrieben werden. Ein zweiter, davon unabhaengiger Release-Text
wuerde frueher oder spaeter etwas anderes erzaehlen als das Paket, das
danebenliegt. Der Installationsabschnitt nennt bewusst keine festen
RPM-Dateinamen, weil dort Release-Nummer und Distributions-Tag mit
drinstehen und ein hart geschriebenes Beispiel beim ersten Rebuild
veralten wuerde.

## 7. Voraussetzungen im Repository

- Der Release-Workflow braucht `contents: write` - das ist im Workflow
  gesetzt und verlangt, dass unter *Settings -> Actions -> General ->
  Workflow permissions* Schreibrechte fuer den `GITHUB_TOKEN` erlaubt
  sind.
- Weitere Secrets braucht keiner der beiden Workflows. Die Pakete werden
  unsigniert gebaut (`dpkg-buildpackage -us -uc`); wer sie signieren
  will, braucht dafuer einen Schluessel im Repository und einen
  zusaetzlichen Schritt - das ist bewusst noch nicht eingebaut, solange
  das Projekt keine Lizenz und keine oeffentliche Paketquelle hat (siehe
  den offenen Roadmap-Punkt "Lizenz festlegen").
