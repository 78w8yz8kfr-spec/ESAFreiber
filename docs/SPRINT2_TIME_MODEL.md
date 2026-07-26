# Sprint 2: Planung und Zeiterfassung

Stand: 26.07.2026
Technischer Stand: V0.28.0

Dieses Dokument beschreibt die verbindlichen Regeln der Migrationen 009 bis
012. Der Sprint verbindet Wochenplanung, Vorarbeiterverantwortung,
Offline-Zeitereignisse und den berechneten Stundenzettel.

Die PWA stellt den berechneten Stundenzettel zusätzlich als vollständige
Arbeitswoche dar. `GET /api/v1/work-weeks/{montag}` liefert Montag bis Freitag,
die wirksamen eigenen Buchungen und die Summen für Brutto, Pause, Arbeit,
Fahrt und Mehrzeit. Eine Korrektur wird direkt an der betreffenden
Wochenbuchung begonnen; der laufende Arbeitstag bleibt dadurch ruhig.

## Gemeinsame Regeln

- Jede Tabelle gehört verpflichtend zu einer Firma; zusammengesetzte
  Fremdschlüssel und erzwungene Row Level Security schützen die Mandanten.
- Planung und Zeitbuchungen werden fachlich beendet oder korrigiert, niemals
  überschrieben oder hart gelöscht.
- Spontane Änderungen erhalten eine Begründung und einen unveränderlichen
  Vorher-Stand.
- Das Frontend erzeugt für jede Buchung eine eindeutige Client-UUID. Die
  Datenbank akzeptiert dieselbe UUID je Mitarbeiter und Firma nur einmal.
- Es werden keine GPS-Daten für die Zeiterfassung abgefragt oder gespeichert.

## 009 `site_assignments`

Ein Mitarbeiter kann an einem Arbeitstag mehrere Baustellen in einer
verbindlichen Reihenfolge erhalten. `sequence_number` ist Pflicht; eine
Startzeit bleibt optional. Dieselbe Baustelle darf in der Tagesfolge mehrfach
vorkommen.

Entwürfe können als Tages- oder Wochenplanung freigegeben werden. Wiederholungen
und Vorlagen besitzen Referenzschlüssel, bleiben aber einzelne historische
Datensätze. Änderungen an freigegebenen Baustellen, Tagen, Reihenfolgen oder
Uhrzeiten verlangen eine Begründung. `site_assignment_history` speichert bei
jeder Änderung den vollständigen vorherigen Stand.

## 010 `site_supervisors`

Eine Baustelle kann mehrere geplante oder aktive Vorarbeiter besitzen. Genau ein
aktiver Datensatz darf Hauptvorarbeiter und genau ein aktiver Datensatz darf
berichtspflichtig sein. Nur Benutzer mit aktiver Vorarbeiterrolle können neu
eingeplant werden.

Wird ein neuer Hauptvorarbeiter aktiviert, beendet die Datenbank die bisherige
Hauptzuweisung automatisch. Eine vorhandene Berichtsverantwortung wird auf den
neuen Hauptvorarbeiter übertragen. Die Änderung ist in
`site_supervisor_history` mit dem Grund der automatischen Übergabe sichtbar.

## 011 `work_days`

`users.weekly_target_minutes` speichert individuelle Sollminuten für alle sieben
ISO-Wochentage. Standard sind Montag bis Donnerstag jeweils 510 Minuten,
Freitag 360 Minuten und am Wochenende 0 Minuten. Beim Anlegen eines Arbeitstags
wird das jeweilige Soll als unveränderlicher Tageswert übernommen.

`work_days` ist die berechnete Tageszusammenfassung. Die derzeitige
`calculation_version = 2` verwendet folgende Regeln:

- ab 3 Stunden 30 Minuten Bruttozeit: 30 Minuten Pause,
- ab 6 Stunden Bruttozeit: insgesamt 60 Minuten Pause,
- ein weiterer Arbeitsbeginn nach Feierabend eröffnet einen neuen Arbeitsblock,
- die Unterbrechung zwischen zwei Arbeitsblöcken zählt mindestens als Pause,
- Arbeitszeit = Bruttozeit minus Pause,
- Fahrtzeit zählt zur Arbeitszeit,
- Mehrarbeit = Arbeitszeit oberhalb des individuellen Tagessolls.

Berechnete Werte können nicht direkt über die API geändert werden. Nach
Einreichung und Freigabe kann ein Arbeitstag für die Abrechnung gesperrt werden;
danach sind reguläre Änderungen und neue Buchungen ausgeschlossen.

## 012 `time_entries`

Zeitbuchungen sind Ereignisse:

1. `clock_in` – Arbeitstag starten,
2. `site_arrival` – auf der Baustelle angekommen,
3. `site_departure` – Baustelle verlassen,
4. optional `next_site` – verbindlich zur nächsten Baustelle wechseln,
5. `clock_out` – aktuellen Arbeitsblock beenden.

Nach einer Abfahrt ist entweder „Nächste Baustelle“ oder direkt „Feierabend“
möglich. Nach Feierabend kann derselbe Mitarbeiter den Arbeitstag erneut
starten. Jeder Start und jedes Ende bleiben als eigener unveränderlicher
Arbeitsblock erhalten. Für Baustellenereignisse ist eine Baustelle Pflicht.

Die Felder `client_entry_id`, `client_created_at` und `source` unterstützen eine
idempotente Offline-Synchronisation. Eine doppelt übertragene Client-ID erzeugt
keine zweite Buchung.

## Korrekturen

Ein Korrekturantrag ist ein neuer `time_entries`-Datensatz mit Referenz auf das
Original, dem gewünschten Zeitpunkt und einer Begründung. Er startet mit Status
`pending`. Bis zur Entscheidung bleibt der Stundenzettel unverändert.

Bei Genehmigung wird das Original lediglich entwertet und bleibt vollständig
erhalten; anschließend wird der Arbeitstag neu berechnet. Ablehnungen bleiben
ebenfalls mit Prüfer und Zeitpunkt nachvollziehbar. Die View
`pending_time_entry_corrections` liefert offene Anträge für die Organisationsansicht und
der Datenbankkanal `schaefchen_time_correction` bereitet Benachrichtigungen vor.

Die produktive PWA stellt den Ablauf direkt am eigenen synchronisierten
Stundenzettel bereit. Offene Anträge zeigen weiterhin die Originalzeit; die
Einsatzplanung listet alte Uhrzeit, gewünschte Uhrzeit und Begründung. Vor
einer Genehmigung prüft die API die vollständige Zeit- und Baustellenfolge
erneut, damit zwischenzeitliche Buchungen keinen ungültigen Tagesablauf
erzeugen.

## Öffentliche PWA-Demo

Die veröffentlichte Sprint-2-Demo bildet den vollständigen Monteurablauf mit
zwei gekennzeichneten Demo-Baustellen ab. Ereignisse werden ausschließlich in
`localStorage` auf dem jeweiligen Gerät gespeichert und an keinen Server
gesendet. Sie bleiben nach einem Neuladen erhalten und können über „Demo
zurücksetzen“ entfernt werden. Die Demo erzeugt dieselben eindeutigen
Client-IDs und zeigt die Berechnung live. Auf der getrennten Online-Adresse
verwendet die PWA dieselben Client-IDs für die echte API-Synchronisation; die
GitHub-Pages-Demo selbst sendet weiterhin nichts.

## Abnahme

Für jede Migration existiert ein eigener SQL-Test. Geprüft werden unter anderem
mehrfache Tagesbaustellen, Reihenfolge, Änderungsbegründung, automatische
Vorarbeiterübergabe, individuelle Sollzeit, Pausen- und Mehrarbeitsberechnung,
Client-ID-Dubletten, Korrekturen, Sperren, Löschschutz und Mandantentrennung.
GitHub Actions wendet alle Migrationen zweimal an, prüft Backup und Restore und
führt anschließend den echten Login-/Session-/Offline-Sync-Ablauf der Node-API
gegen PostgreSQL aus.
