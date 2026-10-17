# Usability-Review MoneyLedger (Stand 2026-10-17)

Statische Durchsicht des UI-Codes (`lib/features/**`, `lib/core/widgets`,
Router, `app_en.arb` / `app_de.arb`) entlang der Haupt-Journeys, aus der Sicht
einer neuen Nutzerin, die mit Freunden eine Reise abrechnen will. Es lief kein
Build, kein Emulator und kein Test – alles, was Bildschirmbreite, TalkBack oder
Schriftgröße betrifft, ist als **Gerätecheck** markiert und muss am Gerät bestätigt
werden. Bereits geplante oder entschiedene Punkte (G52–G54, G57, G58, G61,
Leos Entscheidungen in `plan.md`) werden **nicht** neu vorgeschlagen. Wo ein
Befund die kommende Link-Gruppen-Strecke berührt, steht er als **Anforderung an
G52/G54** da.

---

## 1. Kurzfazit

Innerhalb einer Gruppe ist MoneyLedger schon gut: Das Formular für Ausgaben
ist durchdacht (Vorschlag für die Kategorie, Datum mit Heute/Gestern, vier
Aufteilungsarten mit *Verteilen*, *Rest hier* und *Gesamtbetrag = Summe*). Es
fragt nach, bevor ungespeicherte Eingaben verworfen werden. Salden und
Ausgleichsvorschläge sind klar, und jede Fehlbedienung lässt sich über
Verlauf und Wiederherstellungspunkte reparieren. Die größte Hürde ist weiterhin
das **Teilen einer Gruppe**. Ohne Konto geht es gar nicht, mit Matrix nur per
eingetippter Matrix-ID, und die eingeladene Person erfährt davon nichts. Das
löst G52. Davor müssen aber zwei Dinge sitzen, auf denen der Join-Ablauf
aufbaut: **Personen schon beim Anlegen der Gruppe** und **eindeutige
Namen**. Der einzige echte Korrektheitsfehler, den ich gefunden habe: Wer eine
Ausgabe mit einer **ehemaligen Person** bearbeitet, verändert beim Speichern
unbemerkt die Salden (U11). Für eine Reise-App fehlen außerdem gängige
**Währungen**: Es gibt nur 7, CZK, SEK, PLN, NOK, DKK, HUF, THB fehlen ganz,
und JPY wird mit Nachkommastellen angezeigt. Darüber hinaus sind die Befunde
eher Feinschliff: uneinheitliche Begriffe (Mitglied/Person/Personen), ein
überladenes ⋮-Menü, vier sich überschneidende Arten der Wiederherstellung, rohe
Fehlertexte und eine Sync-Wolke, auf die man nicht tippen kann.

**Tap-Zählung (heute, lokaler Modus, bis zur ersten Ausgabe mit 3 Personen):**
Überspringen → *Ohne Konto nutzen* → Name + *Los geht's* → *Los geht's*
(Onboarding) → *Gruppe erstellen* → Name + *Erstellen* → 2 × (*Personen
hinzufügen* → Name → *Hinzufügen*) → *Ausgabe hinzufügen* → Tippen in
Beschreibung, Tippen in Betrag → *Hinzufügen* ≈ **15 Taps + 5 Texteingaben**.
Tricount: ≈ 8. Den Unterschied machen vor allem das Hinzufügen der Personen
einzeln (U4) und der fehlende Autofokus (U12).

---

## 2. Befunde pro Journey

Schwere: **hoch** = Datenfehler oder Abbruchgrund · **mittel** = spürbare
Reibung · **niedrig** = Feinschliff. Aufwand: **S** ≤ ½ Tag · **M** 1–3 Tage ·
**L** > 3 Tage.

### J1 – Erster Start, Willkommen, Modus wählen

**U1 – Vier Erklärseiten mit Matrix-Fachbegriffen vor der ersten Wahl** · mittel · S (Teil von G54)
- *Was/wo:* `welcome_page.dart` (`WelcomeTopic`: intro, openSource, matrix, privacy). „Homeserver“, „Ende-zu-Ende-verschlüsselter Übermittler“ und „Metadaten“ kommen vor, bevor jemand überhaupt weiß, ob er Matrix braucht. *Ohne Konto nutzen* steht an dritter Stelle der Auswahl.
- *Warum es stört:* Wer „nur schnell die Pizza aufteilen“ will, liest drei Seiten über Infrastruktur. *Überspringen* gibt es, es führt aber direkt zu einer Auswahl, deren erste Option eine Anmeldung ist.
- *Vorschlag = Anforderung an G54:* höchstens drei Seiten. Das Wort „Homeserver“ kommt erst im Matrix-Zweig vor (Login, „Warum Matrix?“). Die Auswahl startet mit *Ohne Konto starten* als primärem Button (G54 sieht das vor). Zusätzlich: Ein über einen Einladungslink geöffneter Start überspringt die Erklärseiten ganz und landet direkt im Join-Ablauf. Ein kurzer Hinweis wie „Was ist MoneyLedger?“ bleibt erreichbar.

**U2 – Lokaler Modus erklärt dreimal dasselbe** · niedrig · S (Teil von G54)
- *Was/wo:* `local_setup_page.dart` zeigt 4 Punkte (bleibt hier, Personen mit Namen, sichern, später verbinden). Direkt danach zeigt `onboarding_page.dart` 3 Karten mit fast demselben Inhalt (bleibt hier, Kopie anlegen, später teilen). Der Chip „Nur lokal“ öffnet ein drittes Sheet dazu.
- *Warum es stört:* Zwei aufeinanderfolgende Bildschirme mit *Los geht's* fühlen sich wie eine Schleife an.
- *Vorschlag:* Im lokalen Modus entfällt das Onboarding, die Setup-Seite reicht. Ihre Texte schreibt G54 ohnehin um („Einladen per Link“ statt „Später teilen“, Chip „Kein Konto“ laut Design §8.2).

**U3 – Veralteter Beispiel-Homeserver** · niedrig · S
- *Was/wo:* `homeserverHint` = „matrix.org oder mozilla.modular.im“ (`app_en.arb:480`, `app_de.arb:211`). Mozilla nutzt seit Jahren `chat.mozilla.org`, und modular.im ist eine alte Domain von Element Matrix Services.
- *Vorschlag:* Nur „z. B. matrix.org“ – ein zweites Beispiel hilft Laien nicht.

### J2 – Gruppe anlegen, Personen hinzufügen, teilen

**U4 – Beim Anlegen der Gruppe wird nach keinen Personen gefragt; jede Person kostet einen eigenen Dialog** · hoch · M
- *Was/wo:* `create_group_page.dart` fragt nur Name und Währung ab. `add_person_dialog.dart` schließt sich nach jeder Person (FAB oder CTA → Name → *Hinzufügen*). Für 5 Personen sind das 15 Taps.
- *Warum es stört:* Tricount und Splitwise fragen die Personen direkt beim Anlegen ab. Für G52 ist das sogar Voraussetzung: Der Join-Picker („Welche Person bist du?“, Design §6.2) funktioniert nur gut, wenn die Personen schon angelegt sind. Sonst wählt jede Person „Ich bin neu dabei“, und die Gruppe enthält eine Person doppelt (Anna lokal + Anna per Link).
- *Vorschlag:* Auf der Seite *Neue Gruppe* steht unter dem Namen ein Feld „Wer ist dabei?“ mit Chips (Enter fügt hinzu, der eigene Name ist vorausgefüllt). Im Dialog *Person hinzufügen* gibt es zusätzlich *Hinzufügen & weitere*. **Anforderung an G52 Schritt 6/7:** Das Einladungs-Sheet nennt die angelegten Personen („Anna, Ben und Chris können sich beim Öffnen auswählen“).

**U5 – Name oder Beschreibung nur aus Leerzeichen wird akzeptiert** · niedrig · S
- *Was/wo:* `create_group_page.dart:73` und `add_expense_page.dart:378` prüfen `v.isEmpty` ohne `trim()`. Gespeichert wird aber `trim()`, also entsteht eine Gruppe oder Ausgabe ohne Namen. `group_edit_dialog.dart:66` macht es richtig.
- *Vorschlag:* Überall `v.trim().isEmpty`.

**U6 – Uneinheitliche Begriffe für Leute** · mittel · S
- *Was/wo:* ⋮ → „Mitglied hinzufügen“ (`addMember`), FAB/Dialog „Person hinzufügen“, CTA „Personen hinzufügen“, Seite „Mitglieder“, Untertitel „Lokal“ / „Lokale Person“. Englisch genauso: *Add member / Add person / Add people*. Löschtexte sagen „für alle Mitglieder entfernt“, auch im lokalen Modus, wo es keine anderen Geräte gibt.
- *Warum es stört:* Laien fragen sich, ob ein „Mitglied“ etwas anderes ist als eine „Person“ (z. B. eins mit Konto). In Link-Gruppen gibt es außerdem bald Personen, die per Link dabei sind.
- *Vorschlag:* Im UI überall „Personen“ (EN *people*), Seitentitel „Personen“. „Mitglied“ nur dort, wo es um Mitgliedschaft geht („ehemalige Mitglieder“, „aus der Gruppe entfernt“). Lösch- und Zurücksetz-Texte je Modus formulieren („für alle in der Gruppe“ statt „für alle Mitglieder“; lokal: „wird gelöscht“).

**U7 – Zwei Wege, einen Matrix-Nutzer hinzuzufügen; das Teilen-Icon führt zur Eingabe der Matrix-ID** · mittel · S (Teil von G52 Schritt 6)
- *Was/wo:* `add_person_dialog.dart` hat ein optionales Feld „Matrix-ID“, das die Person **direkt** hinzufügt, ohne Picker. `group_members_page.dart:57-63` zeigt ein `Icons.share_outlined` „Per Matrix-ID einladen“ **mit** dem Picker „Wer ist X in dieser Gruppe?“. Beide machen etwas Ähnliches mit unterschiedlichem Ergebnis.
- *Vorschlag = Anforderung an G52 §8.4:* Es gibt genau einen Eintrag *Einladen* (Link/QR). Darin steht die Matrix-ID-Einladung als Abschnitt „Matrix-Nutzer einladen (sicher)“, mit dem Picker. Das Matrix-ID-Feld verschwindet aus *Person hinzufügen*, und das Teilen-Icon ist für den Link reserviert.

**U8 – Eine Matrix-Einladung erreicht die eingeladene Person nicht** · hoch (bekannt) · S als Ergänzung
- *Was/wo:* Nach *Einladen* zeigt die App nur „X eingeladen“. X braucht ein Konto, die App und eine Anmeldung, und niemand sagt X Bescheid. Die eingetippte Matrix-ID muss exakt stimmen (`@name:server`).
- *Vorschlag:* Das Grundproblem löst G52. Für Matrix-Einladungen bis G53: Nach dem Einladen bietet die App „Bescheid sagen“ an, einen Teilen-Text („Ich habe dich in ‚Rom 2026‘ eingetragen – installiere MoneyLedger und melde dich mit @x:matrix.org an“). Kosten: share_plus kommt mit G52 ohnehin.

**U9 – Doppelte Namen sind möglich** · mittel · S
- *Was/wo:* `add_person_dialog.dart` und das Umbenennen prüfen keine Duplikate. Zweimal „Alex“ ist danach im Dropdown *Bezahlt von*, auf der Saldo-Seite und im künftigen Join-Picker nicht zu unterscheiden. Der CSV-Import ordnet nach Namen zu (`resolveCsvNames` nimmt dann „die aktive“).
- *Vorschlag:* Hinweis beim Anlegen oder Umbenennen („In dieser Gruppe gibt es schon Alex – trotzdem hinzufügen?“) und ein Vorschlag „Alex B.“. Kein hartes Verbot, denn auch Synchronisierung kann Duplikate erzeugen.

**U10 – Eine Person mit offenem Saldo wird ohne Warnung entfernt** · mittel · S
- *Was/wo:* `group_members_page.dart:533` `_confirmRemove` sagt nur „Ausgabenverlauf bleibt erhalten“. Ihr Saldo bleibt bestehen und taucht weiter in den Ausgleichsvorschlägen auf.
- *Vorschlag:* Im Bestätigungsdialog den Saldo der Person nennen („Ben bekommt noch 23,50 €“) und *Erst ausgleichen* anbieten (öffnet den Zahlungsdialog vorausgefüllt). So macht es der Dialog *Gruppe verlassen* schon (`unsettledWarning`).

### J3 – Ausgabe erfassen, bearbeiten, löschen

**U11 – BUG: Wer eine Ausgabe mit einer ehemaligen Person bearbeitet, verändert stillschweigend die Salden** · **hoch** · S–M
- *Was/wo:* `add_expense_page.dart:184` lädt nur **aktive** Personen. `split_editor.dart:273-276` (`_plan`, Modus *Gleich*) nimmt nur Personen aus `widget.members` auf. Öffnet man eine alte Ausgabe, an der eine inzwischen entfernte oder ausgetretene Person beteiligt war, und ändert **nur die Beschreibung**, wird ihr Anteil beim Speichern auf die übrigen umverteilt. Bei *Genau* fehlt ihr Betrag („noch X offen“), und *Verteilen* verteilt ihn um. War sie die zahlende Person, steht `_paidBy` auf einer ID, die nicht in den Dropdown-Items vorkommt: Im Debug-Build bricht Flutter mit einem Assert ab, im Release-Build ist das Feld leer, die Zahlende bleibt aber gespeichert.
- *Warum es stört:* Der Saldo ist der Kern der App. Die Änderung wird an alle synchronisiert und fällt kaum auf.
- *Vorschlag:* Wie beim Zahlungsdialog (`settle_up.dart:39-44`, „a tapped debt may involve a former member“) alle Personen aufnehmen, auf die die Ausgabe verweist (Zahlende + Schlüssel der Aufteilung), ausgegraut als „ehemalig“. Für neue Ausgaben bleiben sie unwählbar. Regressionstest: Ausgabe mit entfernter Person → nur die Beschreibung ändern → Aufteilung bleibt bytegleich.

**U12 – Kein Autofokus, Formular in ungewohnter Reihenfolge** · niedrig · S
- *Was/wo:* `add_expense_page.dart` hat kein `autofocus` und keine `textInputAction.next`. Die Kategorie steht zwischen Beschreibung und Betrag.
- *Vorschlag:* Autofokus auf die Beschreibung, *Weiter* auf der Tastatur springt zum Betrag. Die Kategorie wird ohnehin vorgeschlagen, sie kann nach dem Datum stehen. Spart zwei Taps bei jeder Ausgabe, und die Ausgabe ist der häufigste Vorgang der App.

**U13 – Löschen ohne Rückmeldung und ohne Rückgängig; im Formular gibt es kein Löschen** · mittel · S–M
- *Was/wo:* `expenses_page.dart:883-918` (Ausgabe) und `:920-975` (Zahlung): Erst kommt ein Bestätigungsdialog, dann passiert nichts Sichtbares und es gibt kein *Rückgängig*. *Zahlung erfasst* hat ebenfalls kein Rückgängig. Im Formular *Ausgabe bearbeiten* gibt es keinen Löschen-Button, nur das ⋮ in der Liste. Ein versehentliches Löschen lässt sich nur über ⋮ → *Auf früheren Stand zurücksetzen* reparieren, das in Batches arbeitet und mehr zurücknimmt, als man will.
- *Vorschlag:* Löschen ohne Dialog, dafür eine Snackbar „‚Pizza‘ gelöscht · Rückgängig“ (6–8 s). Rückgängig schreibt eine neue Version mit `deleted: false` und `nextLwwClock` – derselbe Weg wie der G48-Reset, wird also normal signiert und synchronisiert. Löschen-Icon in der App-Leiste der Bearbeiten-Seite. *Zahlung erfasst* bekommt ebenfalls *Rückgängig*.

**U14 – Beschriftung der Aufteilungsarten „Gleich / Genau / Anteile / %“** · niedrig · S
- *Was/wo:* `split_editor.dart:478-481`. „Genau“ ist kein natürliches Deutsch für „nach Betrag“. Das Segment „%“ ist ein konstantes `Text('%')`, das TalkBack als Zeichen vorliest.
- *Vorschlag:* DE „Gleichmäßig / Beträge / Anteile / Prozent“, EN „Equally / Amounts / Shares / Percent“. **Gerätecheck** bei 360 dp: Die vier Segmente müssen passen, notfalls Icons oder „%“ mit `semanticsLabel`.

**U15 – Antippen öffnet sofort das Formular; in schreibgeschützten Gruppen passiert gar nichts** · niedrig · M
- *Was/wo:* `expenses_page.dart:528/546`, `onTap: readOnly ? null : …`. Nach dem Entfernen aus einer Gruppe kann man nicht einmal nachsehen, wie eine Ausgabe aufgeteilt war.
- *Vorschlag:* Mindestens für schreibgeschützte Gruppen ein Detail-Sheet nur zum Lesen (Betrag, wer was, Notiz, „Hinzugefügt von“). Optional überall: erst Details, dann *Bearbeiten*, wie bei Tricount. Das senkt auch das Risiko versehentlicher Änderungen in Link-Gruppen, in denen jede Person alles ändern darf.

**U16 – Nur 7 Währungen; JPY mit Nachkommastellen** · **hoch** (für Reisen) · M
- *Was/wo:* `create_group_page.dart:10` `kGroupCurrencies = ['EUR','USD','GBP','CHF','JPY','CAD','AUD']`, genutzt auch im Formular und im Zahlungsdialog. `formatting.dart:18` setzt immer `decimalDigits: 2` → „¥1,000.00“. Die Standardwährung ist fest EUR.
- *Warum es stört:* Eine Reise nach Prag, Krakau, Kopenhagen, Budapest, Stockholm oder Bangkok lässt sich nicht in der Landeswährung erfassen – ein Abbruchgrund für eine Reise-App.
- *Vorschlag:* Vollständige ISO-4217-Liste (statisch im Code, ohne Server) mit Suche, „zuletzt in dieser Gruppe verwendet“ oben, Anzeige mit den richtigen Nachkommastellen (JPY/KRW/HUF… 0). Das Protokoll bleibt unverändert: weiterhin `int` in Hundertsteln, nur Anzeige und Eingabe richten sich nach den Nachkommastellen. Standardwährung aus der Gerätesprache bzw. -region. Unbekannte Codes von Peers bleiben wie heute erhalten.

### J4 – Salden, Ausgleichen, Zahlungen

**U17 – Keine teilbare Zusammenfassung „Wer schuldet wem“** · mittel · S
- *Was/wo:* `balance_page.dart` zeigt Salden und Vorschläge, kann sie aber nicht teilen. Am Ende einer Reise schickt man normalerweise eine Nachricht in die WhatsApp-Gruppe.
- *Vorschlag:* *Teilen* auf der Saldo-Seite → reiner Text über das System-Teilen-Menü („Rom 2026 – Ausgleich: Ben zahlt Anna 42,10 €; Chris zahlt Anna 12,00 € · erstellt mit MoneyLedger“). Kein Server, kein Tracking, `share_plus` kommt mit G52. Gerade für Personen ohne App (lokaler Modus) ist das der einzige Kanal.

**U18 – Mehrere Währungen werden nur getrennt ausgeglichen** · mittel · L
- *Was/wo:* Bewusst so (`simplifyDebtsPerCurrency`, G16). Bei einer Reise mit CHF und EUR braucht man zwei getrennte Ausgleiche.
- *Vorschlag:* Optional **feste, manuell eingetragene Kurse pro Gruppe** („1 CHF = 1,05 €“) und ein Schalter „In EUR abrechnen“. Die Kurse kommen in die signierte Gruppen-Meta, nur wenn gesetzt (wie `categories`). Das ist eine Änderung am Wire-Format und gehört deshalb zu G57 („später, zusammen mit den Link-Gruppen-Wire-Änderungen“). **Automatische Online-Kurse widersprechen Ziel 7** (Dritt-Server) → siehe „Bewusst nicht“.

**U19 – Keine Gruppensummen und keine Statistik** · mittel · M
- *Was/wo:* Die Gruppenseite zeigt nur „Dein Saldo“ (`_GroupSummaryCard`). Es fehlen „Gesamtausgaben der Gruppe“, „wer hat wie viel bezahlt bzw. verbraucht“ und „nach Kategorie“. Die Kategorien gibt es seit G16/G47, sie werden aber nirgends ausgewertet (`open-points.md`: „No category statistics yet“).
- *Vorschlag:* Ein Abschnitt „Übersicht“ auf der Saldo-Seite: Summe je Währung, pro Person bezahlt / Anteil, Top-Kategorien als einfache Balken. Wird rein lokal aus den vorhandenen Daten berechnet.

### J5 – Mehrere Gruppen, Archiv, Suche

**U20 – Die Gruppenliste ist nicht sortiert** · mittel · S
- *Was/wo:* `groups_dao.dart:19-20` `select(groups).watch()` ohne `orderBy` liefert die Reihenfolge der Einfügung. Die aktuelle Reise rutscht nach unten.
- *Vorschlag:* Sortierung nach letzter Aktivität (`GroupOverview.lastActivityAt`, absteigend), neue Gruppen ganz oben.

**U21 – App-Leiste der Gruppenliste: seltene Aktionen ganz oben** · niedrig · S
- *Was/wo:* `groups_page.dart:58-82`: *CSV importieren* (Upload-Icon, mehrdeutig) und *Abmelden* sind Icons erster Ebene, im lokalen Modus kommt der Chip dazu. Bei 360 dp mit Logo und „Gruppen“ wird es eng (**Gerätecheck**).
- *Vorschlag:* *CSV importieren* in die Einstellungen (Abschnitt „Daten“) und in den leeren Zustand, wo es schon steht. *Abmelden* in die Einstellungen (Abschnitt „Konto“). Oben bleiben Einstellungen und ggf. der Modus-Chip.

**U22 – ⋮-Menü der Gruppe mit 9 Einträgen, die Häufiges, Seltenes und Endgültiges mischen** · mittel · M
- *Was/wo:* `expenses_page.dart:166-283`: Mitglied hinzufügen (doppelt zum Personen-Icon daneben), Bearbeiten, Kategorien, Archivieren, CSV, Sichern, Zurücksetzen, Verlassen/Löschen. G52 bringt *Einladen* und *Link zurücksetzen*, G53 *Gruppe absichern*, G54 *Warum Matrix?* – das wären 12 und mehr.
- *Vorschlag:* Eine Seite **Gruppeneinstellungen** (Name/Währung, Kategorien, Einladung/Link, Export & Sicherung, Verlauf/Zurücksetzen, Archivieren, Verlassen/Löschen in einem roten Bereich am Ende). Das Menü behält *Einladen*, *Gruppeneinstellungen* und *Archivieren*. **Sollte vor G52 Schritt 6 passieren**, damit die neuen Einträge einen Platz haben.

### J6 – Sicherung, Wiederherstellung, Zurücksetzen, CSV

**U23 – Vier sich überschneidende Arten der Wiederherstellung** · mittel · M
- *Was/wo:* „Alle Gruppen sichern / Aus Sicherung wiederherstellen“, „Wiederherstellungspunkte“ (mit „Genau diesen Stand“), ⋮ → „Auf früheren Stand zurücksetzen…“, ⋮ → „Diese Gruppe sichern“ und CSV-Export/-Import. Die Texte erklären sich gegenseitig (`restorePointsHowItWorks` verweist auf das Gruppenmenü). Laien können nicht einschätzen, was sie bei „Ich habe etwas gelöscht“ tun sollen.
- *Vorschlag:* In den Einstellungen nur noch ein Eintrag **„Sichern & Wiederherstellen“**, eine Seite mit drei Blöcken: *Sicherungsdatei* (speichern / einlesen), *Automatische Kopien auf diesem Gerät* (Liste), *Fehler in einer Gruppe rückgängig machen* → Gruppe wählen → Reset-Seite. Oben eine Entscheidungshilfe in zwei Sätzen („Einzelnen Eintrag zurückholen → in der Gruppe ‚Rückgängig‘; ganzes Handy weg → Sicherungsdatei“). CSV gehört in „Daten / Export“, nicht zur Sicherung. Das ändert nur die Navigation, nicht die Funktionen.

### J7 – Sync-Status, Fehler, offline, Geräte, Verlassen

**U24 – Auf die Sync-Wolke kann man nicht tippen; ihre Erklärung steckt im Tooltip** · mittel · S–M
- *Was/wo:* `expenses_page.dart:996-1015`. In den Zuständen *synchronisiert* und *ausstehend* ist `onPressed: null`, das Icon ist also deaktiviert (ausgegraut) und erklärt sich nur über langes Drücken („Warte auf Ben …“). Die Wolke pro Zeile (`cloud_queue`) hat weder Label noch Erklärung.
- *Vorschlag:* Antippen öffnet immer ein Sheet mit dem Stand pro Person („Ben – hat alles“, „Chris – wartet, zuletzt vor 2 Std.“, „Dana – kein Gerät angemeldet“) und *Jetzt synchronisieren*. **Dasselbe Sheet wird mit dem Peers-Sheet aus G52 §5.3 / Schritt 9 gebaut**, damit es nur eins gibt.

**U25 – Rohe Fehlertexte in Snackbars** · mittel · M
- *Was/wo:* 29 Stellen mit `failedWithError(e.toString())` / `errorWithDetail(...)`, z. B. beim Anlegen einer Gruppe, beim Hinzufügen von Personen, beim Löschen und beim Abmelden. Anzeige: „Fehlgeschlagen: StateError: …“. Für die Anmeldung gibt es schon das gute Muster `describeAuthError` + `AuthErrorCard` (G20).
- *Vorschlag:* Ein `describeActionError` mit wenigen Klassen (DB geschlossen → „Bitte erneut versuchen“, Datei nicht schreibbar, Transport nicht verfügbar, Inhaltsregel verletzt) + Details zum Aufklappen. Snackbars bekommen den freundlichen Text und, wo sinnvoll, *Erneut versuchen*.

**U26 – Keine Rückmeldung, wenn andere etwas eintragen** · mittel · M
- *Was/wo:* Die Hintergrundrunde (G31) holt Änderungen ab, sagt aber niemandem Bescheid. `POST_NOTIFICATIONS` ist im Manifest bewusst entfernt.
- *Vorschlag:* **Optionale lokale Benachrichtigungen** („Ben hat ‚Tankstelle 48,00 €‘ in Rom 2026 eingetragen“), erzeugt von der Hintergrundrunde auf dem Gerät selbst. Kein Push-Server und keine Google-Dienste, passt also zu den Zielen. Standard aus, angeboten nach dem ersten geteilten Eintrag. Für Link-Gruppen erst nach G52 Schritt 8 sinnvoll.

**U27 – Texte zur Verifizierung sind sehr lang und voller Fachbegriffe** · niedrig · S
- *Was/wo:* `verifiedOnlyConfirmBody` hat rund 150 Wörter, `verifiedOnlyOnBody` rund 60. Dazu Begriffe wie „Emoji-Vergleich“, „signierendes Gerät“, „Signatur nicht überprüfbar“. Die Option steht gleichrangig neben der Hintergrund-Synchronisierung.
- *Vorschlag:* Ein Bereich „Erweitert (Matrix)“ in den Einstellungen (Geräte, *Nur verifizierte Geräte*). Der Bestätigungsdialog bekommt drei kurze Sätze und *Mehr erfahren* (öffnet den langen Text). Gehört zum Ton von G54 („Warum Matrix?“).

### J8 – Einstellungen, Info, Deutsch, 360 dp, Web, Barrierefreiheit

**U28 – Einstellungen sind ein langes Bottom-Sheet** · mittel · M
- *Was/wo:* `SyncSettingsSheet` (`groups_page.dart`): Sync-Erklärung, Hintergrund-Sync, Nur-verifiziert, Geräte, Sicherung (4 Einträge), Info – mit langen Untertiteln, bei 360 dp kaum zu überblicken (**Gerätecheck**). G52 Schritt 9 braucht zusätzlich die Relay-Liste und Peers, U21 Konto und CSV.
- *Vorschlag:* Eine richtige Einstellungsseite `/settings` mit Abschnitten *Konto/Modus*, *Synchronisierung* (inkl. Relays aus G52), *Sichern & Wiederherstellen* (U23), *Daten* (CSV), *Erweitert* (U27), *Info*. Vor G52 Schritt 9 erledigen, damit die Relays einen Platz haben.

**U29 – Deutsche Feinheiten** · niedrig · S
- Gedankenstriche gemischt: „—“ in `groupArchivedUnsettled`, `simplifyDebts*`, sonst „–“. Auslassungspunkte gemischt: „Die Anmeldung läuft noch…“ ohne Leerzeichen, sonst „ …“. „Sync“ (`restoreLeftNote`) steht neben „Synchronisierung“. Der Filter-Chip „Mit mir“ wäre als „Betrifft mich“ klarer. „Kassenbuch“ (Datenschutz, Verlassen-Dialog) ist ok, sollte aber einheitlich bleiben. „1 frühere Version ist unbrauchbar“ (`resetPreviewSkipped`) ist Fachsprache, besser „… lässt sich nicht wiederherstellen“.
- *Vorschlag:* Einmal durch die ARB gehen; ein Test (wie in `about_page_test.dart`) kann „—“ in `app_de.arb` verbieten.

**U30 – Wenig Semantik für Screenreader, zu kleine Tap-Ziele** · mittel · M
- *Was/wo:* Nur 5 `Semantics`-Stellen in `lib`. Ohne Label sind: Kategorie-Kachel (`CategoryIconTile`, reines Icon), Wolke pro Zeile, Notiz- und Warn-Icon (nur Tooltip), das Segment „%“. Die Schrittregler für Anteile und „Rest hier“ nutzen `VisualDensity.compact` (`split_editor.dart:664-677`), also etwa 40 dp statt 48 dp. Kontraste sind schon per Test abgesichert.
- *Vorschlag:* A11y-Durchgang: Zeilen mit `MergeSemantics` und einem Satz („Pizza, 42 €, bezahlt von Anna, du schuldest 14 €, wird noch synchronisiert“), Labels für die Icons, Tap-Ziele ≥ 48 dp. **Gerätecheck** mit TalkBack und Schriftgröße 200 % (Zeilen mit `maxLines: 1` und die Beträge).

**U31 – Web: Einschränkungen sieht man erst beim Suchen** · niedrig · S
- *Was/wo:* Im Web gibt es keine Hintergrund-Synchronisierung und keine Wiederherstellungspunkte, und Emoji bzw. CJK erscheinen als Kästchen (G55, akzeptiert). Gesagt wird das jeweils nur an Ort und Stelle (Einstellungen bzw. Seite der Wiederherstellungspunkte).
- *Vorschlag:* Beim ersten Start im Web ein kurzer Hinweis „Im Browser: nur synchron, solange der Tab offen ist; regelmäßig sichern“. Für Link-Gruppen im Web (G52, Entscheidung 11) besonders wichtig, weil die einladende Person den Tab offen haben muss, damit andere beitreten können.

---

## 3. Feature-Liste / Planung

### Vor dem Release nötig
- Bearbeiten mit ehemaligen Personen korrigieren – **U11** – S–M
- Vollständige Währungsliste, richtige Nachkommastellen, Standard aus der Region – **U16** – M
- Personen beim Anlegen der Gruppe + Hinweis auf doppelte Namen (Voraussetzung für den Join-Picker) – **U4, U9** – M
- Einheitliche Begriffe Personen/Mitglieder, modusabhängige Löschtexte – **U6** – S
- Leerzeichen-Validierung, Hinweis zum Homeserver, DE-Feinschliff – **U5, U3, U29** – S
- Rückgängig beim Löschen und Erfassen, Löschen im Formular – **U13** – S–M
- Warnung beim Entfernen einer Person mit offenem Saldo – **U10** – S
- Anforderungen an G52/G54 erfüllt (ein Einladen-Eintrag, kurzer Willkommensablauf, kein doppeltes Onboarding) – **U1, U2, U7, U8** – in G52/G54

### Bald (hoher Nutzen)
- Ergebnis teilen („Wer zahlt wem“ als Text) – **U17** – S
- Gruppenliste nach Aktivität sortieren – **U20** – S
- Sync-Sheet pro Person (gemeinsam mit dem Peers-Sheet aus G52) – **U24** – S–M
- Gruppeneinstellungen statt 9er-Menü – **U22** – M
- Einstellungsseite statt Sheet; CSV und Abmelden dorthin – **U28, U21** – M
- Freundliche Fehlermeldungen – **U25** – M
- „Sichern & Wiederherstellen“ zusammenfassen – **U23** – M
- Autofokus/Reihenfolge im Formular, Beschriftung der Aufteilungsarten – **U12, U14** – S
- Barrierefreiheit (Semantik, 48 dp, TalkBack-/Schriftgrößen-Check) – **U30** – M
- Übersicht/Statistik (Summe, pro Person, Kategorien) – **U19** – M

### Später / nice to have
- Lokale Benachrichtigungen (opt-in) – **U26** – M
- Manuelle Wechselkurse + „in einer Währung abrechnen“ (Wire-Änderung → mit G57) – **U18** – L
- Detailansicht nur zum Lesen (mindestens in schreibgeschützten Gruppen) – **U15** – M
- Web-Hinweis beim ersten Start – **U31** – S
- „Ausgabe duplizieren“ (günstige Vorstufe zu wiederkehrenden Ausgaben, z. B. WG-Miete) – S; echte wiederkehrende Ausgaben – M
- Zahlungsdaten pro Person (IBAN / PayPal.me als Text, nur lokal in der Gruppe sichtbar) + **EPC-/GiroCode-QR** beim Ausgleichen – M (synchronisierte Feldänderung → Wire, mit G57 bündeln)
- Rechner im Betragsfeld („12,50+8“) – S
- Mehrere Zahlende pro Ausgabe – L (Protokolländerung `paid_by`)
- Aufteilung nach Posten / Kassenzettel – L
- Schnelleingabe (App-Shortcut „Ausgabe hinzufügen“ für die zuletzt genutzte Gruppe; Widget) – S/M
- Belegfoto **nur auf dem eigenen Gerät** (nicht synchronisiert, klar so beschriftet) – M; ob das die Erwartung erfüllt, ist fraglich

### Bewusst nicht (widerspricht den Zielen)
- **Automatische Online-Wechselkurse** (Kontakt zu einem Kurs-Server, Ziel 7) – höchstens später als ausdrückliches Opt-in mit Server-Hinweis; empfohlen: nur manuelle Kurse (U18).
- **Push-Benachrichtigungen über einen Server / FCM** (eigener Server oder Google, Ziel 3/7) – lokale Benachrichtigungen reichen (U26).
- **Belegfotos synchronisieren** über Relay bzw. Homeserver (Größe ≤ 64 KB, Daten lägen dauerhaft bei Dritten, Ziel 5; vgl. `open-points.md`).
- **Kontakte-Abgleich / Adressbuch hochladen**, Erinnerungs-E-Mails, „Zahlung anfordern“ über einen Dienst, Bank-Anbindung, Beleg-OCR in der Cloud.
- **Eigene Konten, Analyse, Absturzberichte** (Ziel 3/7; G44 hat das Debug-Log schon abgelehnt).

### Vorschlag für Plan-Einträge (Reihenfolge, Abhängigkeiten)

| # | Name | Umfang (eine Zeile) | Befunde | Größe | Abhängigkeit / Zeitpunkt |
|---|------|---------------------|---------|-------|--------------------------|
| 1 | **G63 Korrektheit & Texte vor Release** | Ehemalige Personen beim Bearbeiten erhalten (+ Regressionstest), Validierung mit `trim`, Homeserver-Hinweis, DE-Feinschliff, Beschriftung der Aufteilungsarten | U11, U5, U3, U29, U14 | S–M | Unabhängig. **Passt in die Wartezeit bis zum Retention-Gate am 2026-10-20** (G52 Schritt 5) |
| 2 | **G64 Personen & Gruppe anlegen** | Personen-Chips beim Anlegen, *Hinzufügen & weitere*, Hinweis auf doppelte Namen, Begriff „Personen“, Saldo-Warnung beim Entfernen | U4, U9, U6, U10 | M | **Vor G52 Schritt 6/7** (Join-Picker baut darauf auf) |
| 3 | **G65 Gruppeneinstellungen & Einstellungsseite** | Gruppeneinstellungen statt 9er-Menü, `/settings` als Seite mit Abschnitten, CSV/Abmelden umziehen | U22, U28, U21 | M | **Vor G52 Schritt 6** (Einladen) und **Schritt 9** (Relays) |
| 4 | **G66 Währungen** | ISO-4217-Liste mit Suche, Nachkommastellen je Währung, Standard aus der Region | U16 | M | Unabhängig; vor dem Release |
| 5 | **G67 Rückgängig & verständliche Fehler** | Snackbar mit Rückgängig beim Löschen/Erfassen, Löschen im Formular, `describeActionError`, Detail-Sheet in schreibgeschützten Gruppen | U13, U25, U15 | M | Unabhängig; das Rückgängig ist in Link-Gruppen besonders wichtig (jede Person darf löschen, Design §14) |
| 6 | **G68 Sync-Sheet pro Person** | Antippbare Wolke, Status pro Person, *Jetzt synchronisieren*; dasselbe Sheet für Matrix und Link | U24 | S–M | **Zusammen mit G52 Schritt 9** (Peers-Sheet) |
| 7 | **G69 Teilen & Übersicht** | „Wer zahlt wem“ als Text teilen, Gruppenliste nach Aktivität, Statistik auf der Saldo-Seite | U17, U20, U19 | M | Nach G52 Schritt 6 (`share_plus`) |
| 8 | **G70 Sichern & Wiederherstellen vereinfachen** | Eine Seite, drei Blöcke, Entscheidungshilfe | U23 | M | Nach G65 (braucht die Einstellungsseite); vor G52 Schritt 10 (Backup mit Link-Secret) sinnvoll |
| 9 | **G71 Barrierefreiheit & Formular-Flow** | Semantik, 48 dp, Autofokus/Weiter, Gerätecheck TalkBack/200 % | U30, U12 | M | Nach G63; Gerätecheck im Device-Pass von G52 Schritt 13 mitlaufen lassen |
| 10 | **G72 Lokale Benachrichtigungen (opt-in)** | Benachrichtigung aus der Hintergrundrunde bei fremden Änderungen, Datenschutztext, Einstellung | U26 | M | Nach G52 Schritt 8 (Link-Phase im Hintergrund) |
| 11 | **G73 Wechselkurse (manuell)** | Feste Kurse in der signierten Meta, „In {Währung} abrechnen“ | U18 | L | Wire-Änderung → gebündelt mit G57 nach G52/G53 |

Requirements an bestehende Items (ohne neue Nummer): **G52 Schritt 6/7** – U7, U8 (ein Einladen-Eintrag, Matrix-ID als „sicher“-Abschnitt; Sheet nennt die vorhandenen Personen), U31 (Web-Hinweis für Einladende). **G54** – U1, U2, U27 (kurzer Willkommensablauf, „Homeserver“ nur im Matrix-Zweig, kein doppeltes Onboarding im lokalen Modus, Verifizierung unter „Erweitert“, Start per Link ohne Erklärseiten).

Empfohlene Ausführungsreihenfolge: **G63** (jetzt, Wartezeit bis 2026-10-20) → G52 Schritte 3–5 → **G64**, **G65** → G52 Schritte 6–8 → G52 Schritt 9 mit **G68** → G52 Schritte 10–13 (Device-Pass inkl. **G71**-Check) → G54 → **G66**, **G67** → Release-Kandidat → **G69**, **G70** → G53 → **G72** → G57 + **G73**. G66 und G67 hängen an nichts und können vorgezogen werden, wenn G52 blockiert ist.

---

## 4. Offene Fragen an Leo

1. **Release vor oder nach den Link-Gruppen?** Ein v1 nur mit Matrix + lokalem Modus hätte als ersten Eindruck die Matrix-lastige Willkommensstrecke, und G54 dreht sie danach um. *Empfehlung:* Release nach G52 + G54. G63 und G66 aber unabhängig davon jetzt erledigen, damit kein bekannter Datenfehler (U11) und keine fehlende Währung (U16) in einen Release gerät.
2. **Personen schon beim Anlegen der Gruppe abfragen (Tricount-Stil)?** *Empfehlung:* Ja, als optionales Chip-Feld mit dem eigenen Namen vorausgefüllt. Das spart rund 2 Taps pro Person und macht den Join-Picker aus G52 erst sinnvoll.
3. **Begriff im UI: „Personen“ statt „Mitglieder“?** *Empfehlung:* Ja, „Personen“ überall; „Mitglied“ nur für die Mitgliedschaft (ehemalige Mitglieder, entfernt).
4. **Löschen ohne Bestätigungsdialog, dafür mit Rückgängig?** *Empfehlung:* Ja für einzelne Ausgaben und Zahlungen (Snackbar 6–8 s). Bei Gruppe löschen/verlassen und *Lokale Daten löschen* bleibt der Dialog.
5. **Mehrere Währungen: nie umrechnen, manuelle Kurse oder Online-Kurse?** *Empfehlung:* Manuelle feste Kurse pro Gruppe als Opt-in (G73, gebündelt mit den Wire-Änderungen von G57). Online-Kurse nicht, weil sie Ziel 7 verletzen.
6. **Lokale Benachrichtigungen bei fremden Änderungen?** *Empfehlung:* Ja, opt-in (Standard aus, einmal angeboten), erst nach G52 Schritt 8. Braucht die Berechtigung `POST_NOTIFICATIONS` wieder; der Datenschutztext muss sagen, dass nichts über Google läuft.
7. **Zahlungsdaten (IBAN/PayPal.me) pro Person + GiroCode beim Ausgleichen?** *Empfehlung:* Ja, aber später. Das ist im deutschsprachigen Raum ein echter Mehrwert, braucht aber ein neues synchronisiertes Feld, also mit G57/G73 bündeln. Bis dahin reicht das Teilen als Text (U17).
