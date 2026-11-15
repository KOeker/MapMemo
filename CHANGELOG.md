# Changelog

## v0.1.1

- Entering an instance now triggers the departure alert for open one-time reminders in the previous outdoor zone. Returning to that zone can alert again immediately.
- Zone changes are rechecked after loading. Briefly missing map data and movement within the same zone do not trigger an exit.
- Queued reminders show the latest transition if you cross the zone boundary again before the message appears.

## 0.1.0

- Added one-time and recurring zone and position reminders with character and account scopes.
- Open one-time zone reminders alert on arrival and departure. A confirmed return can alert immediately. Later dismisses the current message, and Done starts a 60-second deletion countdown with Undo.
- Added the MapMemo World Map tab, searchable reminder list, multiline note editor, and per-map pins. The tab shares the quest pane with Nearby Services when available.
- Added localized English and German controls, native notification and click sounds, and a load message with the installed version.
