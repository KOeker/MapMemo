# MapMemo

<img src="Media/Logo.png" alt="MapMemo logo" width="128">

Save notes on the World Map in World of Warcraft: Forever. MapMemo can remind you when you enter a zone, leave with a task still open, or approach a pin. Your reminders are saved locally.

---

## 🗺️ Core Features

- **Zone reminders** — Get a reminder when you enter a selected zone. An open one-time reminder can alert once more when you leave after seeing the arrival alert.
- **Map pins** — Mark a spot, add a note, and get a reminder when you approach it. Hover over a pin to read the note or click it to edit.
- **World Map integration** — Select the pin tab alongside Quests and Nearby Services to show MapMemo in the right-hand quest pane. Nearby Services is provided by ShortestPathForever when installed.
- **Reminder management** — Search and filter your list, pause or complete reminders, and choose whether each reminder belongs to one character or the whole account.

---

## 🎮 How It Works

1. Open the World Map and select the pin tab. Click **+** to create a zone reminder.
2. **Shift+right-click** supported map terrain to place a pin. You can also enter coordinates or use **Use my position** when the client provides your location.
3. When a reminder appears, select **Done**, **Later**, or **Open**. **Done** starts a 60-second deletion timer for a one-time reminder, or acknowledges a recurring reminder for that visit. The reminder row shows the remaining time in red. Undo the completion from the toast or the **Completed** filter during the grace period. **Later** closes the current message and leaves the reminder open, including for a departure alert.

Pin proximity uses a percentage of the zone map. A recurring reminder can alert again after a fresh entry and a five-minute cooldown.

---

## 📦 Installation & Setup

1. **Extract the ZIP** into `_forever_/Interface/AddOns`. The result should contain `MapMemo/MapMemo.toc`.
2. **Enable MapMemo** in the in-game AddOns list.
3. **Open MapMemo** with the pin tab in the World Map or type `/mmemo` or `/mapmemo` to select that tab. For command help, enter `/mmemo help`.

The interface supports English and German and follows your game language, with English as the fallback.

**Version 0.1.0 targets Forever 1.60.1 (interface 16001).** [Changelog](CHANGELOG.md)
