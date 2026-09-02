# Changelog

## 1.1.9 - 2026-09-02

- Adds a **Start at login** option in the menu so Watt is it? launches automatically when you log in.

## 1.1.8 - 2026-09-02

- Caches the AppleSmartBattery service handle between reads and retries cleanly if it becomes invalid.
- Extracts only the required telemetry values without bridging the entire registry node into Swift dictionaries.
- Skips redundant menu-row updates and increases timer tolerance while preserving one-second polling.

## 1.1.7 - 2026-09-02

- Keeps the menu readouts updating while the menu is open.
- Avoids needless redraws of the menu-bar title when the displayed wattage has not changed.
- Refreshes the closed-menu readouts only when the menu opens instead of on every one-second tick.
- Adds explicit timeouts to the GitHub release check and DMG download requests.
- Marks the daily automatic update check only after it succeeds so a failed check can be retried.
- Clears in-progress update state when an update task is cancelled.
- Fixes a potential deadlock while capturing command output during update installation.

## 1.1.6

- Fixes the menu-bar status item being hidden after upgrading from an older spinner layout.

## 1.1.5

- Keeps the update spinner inside the existing wattage status item.
- Avoids creating a second menu-bar icon while an update is active.

## 1.1.4

- Automatic release checks now run once a day at midnight UTC by default.
- Adds an option to turn automatic checks off while keeping manual checks available.

## 1.1.3

- Shows an animated loading indicator while an update downloads or installs.

## 1.1.2

- Adds a version footer to the menu.
- Shows a temporary successful-update message after relaunch.
- Adds an in-app changelog.

## 1.1.1

- Automatic release checks now run once every 7 days.

## 1.1.0

- Stops polling while unplugged and resumes on power-source notifications.
- Adds automatic and manual GitHub release updates.
