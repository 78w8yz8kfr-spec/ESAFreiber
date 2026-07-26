# Optionale Elektro-Spezialmodule

Stand: 26.07.2026
Technischer Stand: V0.26.0

## Ziel

VDE, DGUV, LWL und KNX werden als optionale Fachmodule an denselben Firmen-,
Kunden-, Projekt-, Baustellen-, Mitarbeiter- und Dokumentenbestand angebunden.
Ein Modul erzeugt keine parallelen Stammdaten.

## Freigabeprinzip

- Ein fehlender Freigabedatensatz bedeutet sicher „deaktiviert“.
- Nur Administrator und Geschäftsführung dürfen Module firmenweit aktivieren
  oder deaktivieren.
- Jede Statusänderung erhöht den Versionsstand und wird mit Benutzer und
  Zeitpunkt unveränderlich historisiert.
- Mandantenfilter werden serverseitig erzwungen.
- Deaktivierung entfernt keine Fachdaten.

## Sichtbarkeit

Die Modulfreigabe ist zunächst eine technische Grundlage. Ein Modul erscheint
erst dann in der Oberfläche, wenn seine echte Fachfunktion vollständig
angebunden und für die jeweilige Firma aktiviert ist. Es werden keine leeren
Menüpunkte oder funktionslosen Platzhalter angezeigt.

## Reihenfolge

1. VDE als vorhandene fachliche Quelle kontrolliert anbinden.
2. Gemeinsame Verknüpfung zu Kunde, Projekt, Baustelle, Mitarbeiter und
   Dokument herstellen.
3. Erst danach DGUV, LWL und KNX nach demselben Muster ergänzen.
