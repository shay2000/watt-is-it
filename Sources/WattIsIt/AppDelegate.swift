import AppKit
import IOKit.ps

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum DisplayValue: String, CaseIterable {
        case actualInput
        case systemDraw
        case chargeSurplus
        case ratedInput

        var title: String {
            switch self {
            case .actualInput: return "Actual input"
            case .systemDraw: return "System draw"
            case .chargeSurplus: return "Charge surplus"
            case .ratedInput: return "Rated input"
            }
        }

        var defaultsKey: String {
            "showInMenuBar.\(rawValue)"
        }
    }

    private enum AutomaticUpdateMode: String, CaseIterable {
        case daily
        case off

        static let defaultsKey = "automaticUpdateMode"

        var title: String {
            switch self {
            case .daily: return "Daily at midnight UTC"
            case .off: return "Off"
            }
        }
    }

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu!
    private var displaySubmenu: NSMenu!
    private var actualInputItem: NSMenuItem!
    private var systemDrawItem: NSMenuItem!
    private var chargeSurplusItem: NSMenuItem!
    private var ratedInputItem: NSMenuItem!
    private var displayItems: [DisplayValue: NSMenuItem] = [:]
    private var automaticUpdateModeItems: [AutomaticUpdateMode: NSMenuItem] = [:]
    private var refreshTimer: Timer?
    private var automaticUpdateTimer: Timer?
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var updateTask: Task<Void, Never>?
    private var updateSpinner: NSProgressIndicator?
    private var isUpdateActive = false
    private var successMessageTimer: Timer?
    private var updateMessageItem: NSMenuItem!
    private var versionItem: NSMenuItem!
    private var snapshot = PowerSnapshot.unavailable

    private let lastUpdateCheckKey = "lastUpdateCheckDate"
    private let pendingUpdateVersionKey = "pendingUpdateVersion"

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            DisplayValue.actualInput.defaultsKey: true,
            DisplayValue.systemDraw.defaultsKey: false,
            DisplayValue.chargeSurplus.defaultsKey: false,
            DisplayValue.ratedInput.defaultsKey: false,
            AutomaticUpdateMode.defaultsKey: AutomaticUpdateMode.daily.rawValue
        ])

        NSApp.setActivationPolicy(.accessory)
        configureStatusMenu()
        configurePowerSourceNotifications()
        showUpdateSuccessIfNeeded()
        refresh()
        configureAutomaticUpdateChecking()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopPolling()
        stopPowerSourceNotifications()
        automaticUpdateTimer?.invalidate()
        updateTask?.cancel()
        successMessageTimer?.invalidate()
        updateSpinner?.stopAnimation(nil)
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    private func configurePowerSourceNotifications() {
        guard powerSourceRunLoopSource == nil else {
            return
        }

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else {
                return
            }

            let delegate = Unmanaged<AppDelegate>
                .fromOpaque(context)
                .takeUnretainedValue()

            Task { @MainActor [weak delegate] in
                delegate?.powerSourceDidChange()
            }
        }

        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else {
            return
        }

        powerSourceRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private func stopPowerSourceNotifications() {
        guard let source = powerSourceRunLoopSource else {
            return
        }

        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        powerSourceRunLoopSource = nil
    }

    private func powerSourceDidChange() {
        // This is the only wake-up path after polling has stopped on battery.
        refresh()
    }

    private func configureUpdateIndicator(on button: NSStatusBarButton) {
        guard updateSpinner == nil else {
            return
        }

        // Keep the progress indicator inside the one and only status item.
        // The leading spaces reserved in renderStatusItem keep it clear of
        // the wattage text while preserving the native status-button menu.
        let spinner = NSProgressIndicator(frame: .zero)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false
        spinner.isHidden = true
        button.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 2),
            spinner.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 12),
            spinner.heightAnchor.constraint(equalToConstant: 12)
        ])
        updateSpinner = spinner
    }

    private func updateIndicatorVisibility() {
        guard let updateSpinner else {
            return
        }

        let shouldShow = isUpdateActive && snapshot.externalConnected && statusItem != nil
        if shouldShow {
            updateSpinner.isHidden = false
            updateSpinner.startAnimation(nil)
        } else {
            updateSpinner.stopAnimation(nil)
            updateSpinner.isHidden = true
        }
    }

    private func setUpdateActivity(_ active: Bool) {
        isUpdateActive = active
        renderStatusItem()
        updateIndicatorVisibility()
    }

    private func configureStatusMenu() {
        statusMenu = NSMenu()
        statusMenu.delegate = self
        statusMenu.autoenablesItems = false

        actualInputItem = disabledInfoItem(title: "Actual input: —W")
        systemDrawItem = disabledInfoItem(title: "System draw: —W")
        chargeSurplusItem = disabledInfoItem(title: "Charge surplus: —W")
        ratedInputItem = disabledInfoItem(title: "Rated input: —W")

        statusMenu.addItem(actualInputItem)
        statusMenu.addItem(systemDrawItem)
        statusMenu.addItem(chargeSurplusItem)
        statusMenu.addItem(ratedInputItem)
        statusMenu.addItem(.separator())

        displaySubmenu = NSMenu(title: "Show in menu bar")
        for value in DisplayValue.allCases {
            let item = NSMenuItem(
                title: value.title,
                action: #selector(toggleDisplayValue(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = value.rawValue
            displayItems[value] = item
            displaySubmenu.addItem(item)
        }

        let displayItem = NSMenuItem(title: "Show in menu bar", action: nil, keyEquivalent: "")
        displayItem.submenu = displaySubmenu
        statusMenu.addItem(displayItem)
        statusMenu.addItem(.separator())

        let updateItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdatesManually),
            keyEquivalent: ""
        )
        updateItem.target = self
        statusMenu.addItem(updateItem)

        let automaticUpdatesItem = NSMenuItem(
            title: "Automatic update checks",
            action: nil,
            keyEquivalent: ""
        )
        automaticUpdatesItem.submenu = makeAutomaticUpdateSubmenu()
        statusMenu.addItem(automaticUpdatesItem)

        let changelogItem = NSMenuItem(title: "Changelog", action: nil, keyEquivalent: "")
        changelogItem.submenu = makeChangelogSubmenu()
        statusMenu.addItem(changelogItem)
        statusMenu.addItem(.separator())

        updateMessageItem = disabledInfoItem(title: "")
        updateMessageItem.isHidden = true
        statusMenu.addItem(updateMessageItem)

        versionItem = disabledInfoItem(title: "Version \(appVersion)")
        statusMenu.addItem(versionItem)
        statusMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Watt is it?",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        statusMenu.addItem(quitItem)
        updateDisplayMenu()
        updateAutomaticUpdateMenu()
    }

    private func makeAutomaticUpdateSubmenu() -> NSMenu {
        let menu = NSMenu(title: "Automatic update checks")
        for mode in AutomaticUpdateMode.allCases {
            let item = NSMenuItem(
                title: mode.title,
                action: #selector(selectAutomaticUpdateMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            automaticUpdateModeItems[mode] = item
            menu.addItem(item)
        }
        return menu
    }

    private func makeChangelogSubmenu() -> NSMenu {
        let menu = NSMenu(title: "Changelog")
        let entries: [(String, [String])] = [
            (
                "1.1.6",
                [
                    "Fixes the menu-bar status item being hidden after upgrading from an older spinner layout."
                ]
            ),
            (
                "1.1.5",
                [
                    "Keeps the update spinner inside the existing wattage status item.",
                    "Avoids creating a second menu-bar icon while an update is active."
                ]
            ),
            (
                "1.1.4",
                [
                    "Automatic release checks now run once a day at midnight UTC by default.",
                    "Adds an option to turn automatic checks off while keeping manual checks available."
                ]
            ),
            (
                "1.1.3",
                [
                    "Shows an animated loading indicator while an update downloads or installs."
                ]
            ),
            (
                "1.1.2",
                [
                    "Adds a version footer to the menu.",
                    "Shows a temporary successful-update message after relaunch.",
                    "Adds an in-app changelog."
                ]
            ),
            (
                "1.1.1",
                [
                    "Automatic release checks now run once every 7 days."
                ]
            ),
            (
                "1.1.0",
                [
                    "Stops polling while unplugged and resumes on power-source notifications.",
                    "Adds automatic and manual GitHub release updates."
                ]
            )
        ]

        for (index, entry) in entries.enumerated() {
            let versionHeader = NSMenuItem(title: entry.0, action: nil, keyEquivalent: "")
            versionHeader.isEnabled = false
            menu.addItem(versionHeader)

            for change in entry.1 {
                let changeItem = NSMenuItem(title: "• \(change)", action: nil, keyEquivalent: "")
                changeItem.isEnabled = false
                menu.addItem(changeItem)
            }

            if index < entries.count - 1 {
                menu.addItem(.separator())
            }
        }

        return menu
    }

    private func disabledInfoItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else {
            return
        }

        let newStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = newStatusItem
        newStatusItem.menu = statusMenu
        newStatusItem.autosaveName = "WattIsIt.mainStatusItem"
        newStatusItem.isVisible = true

        guard let button = newStatusItem.button else {
            return
        }
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.toolTip = "Watt is it? — actual input"
        configureUpdateIndicator(on: button)
    }

    private func removeStatusItemIfNeeded() {
        guard let statusItem else {
            return
        }
        updateSpinner?.removeFromSuperview()
        updateSpinner = nil
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    @objc private func refresh() {
        snapshot = PowerReader.read()

        // Keep the indicator absent until an adapter is connected, and stop
        // the timer completely on battery. The IOKit power-source callback
        // starts polling again when macOS reports a power-source change.
        guard snapshot.externalConnected else {
            stopPolling()
            removeStatusItemIfNeeded()
            updateIndicatorVisibility()
            return
        }

        installStatusItemIfNeeded()
        renderStatusItem()
        updateIndicatorVisibility()
        startPollingIfNeeded()
    }

    private func startPollingIfNeeded() {
        guard refreshTimer == nil else {
            return
        }

        let timer = Timer.scheduledTimer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(refresh),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = 0.1
        refreshTimer = timer
    }

    private func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
        updateStatusMenu()
        updateDisplayMenu()
        updateAutomaticUpdateMenu()
    }

    @objc private func toggleDisplayValue(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let value = DisplayValue(rawValue: rawValue)
        else {
            return
        }

        UserDefaults.standard.set(
            !UserDefaults.standard.bool(forKey: value.defaultsKey),
            forKey: value.defaultsKey
        )
        updateDisplayMenu()
        renderStatusItem()
    }

    @objc private func selectAutomaticUpdateMode(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let mode = AutomaticUpdateMode(rawValue: rawValue)
        else {
            return
        }

        UserDefaults.standard.set(mode.rawValue, forKey: AutomaticUpdateMode.defaultsKey)
        updateAutomaticUpdateMenu()
        configureAutomaticUpdateChecking()
    }

    private func renderStatusItem() {
        guard let button = statusItem?.button else {
            return
        }

        let values = DisplayValue.allCases.compactMap { value -> String? in
            guard UserDefaults.standard.bool(forKey: value.defaultsKey) else {
                return nil
            }
            return displayText(for: value)
        }

        // The status item is intentionally numbers-only. If every optional
        // value is unchecked, retain actual input as the safe fallback.
        let title = values.isEmpty ? wattageText(snapshot.powerWatts) : values.joined(separator: "  ")
        let composedTitle = isUpdateActive ? "    \(title)" : title
        if button.title != composedTitle {
            button.title = composedTitle
        }
        button.image = nil
    }

    private func updateStatusMenu() {
        actualInputItem.title = "Actual input: \(wattageText(snapshot.powerWatts))"
        systemDrawItem.title = "System draw: \(wattageText(snapshot.systemDrawWatts))"
        chargeSurplusItem.title = "Charge surplus: \(wattageText(snapshot.chargeSurplusWatts))"
        ratedInputItem.title = "Rated input: \(wattageText(snapshot.ratedInputWatts))"
    }

    private func updateDisplayMenu() {
        for value in DisplayValue.allCases {
            displayItems[value]?.state = UserDefaults.standard.bool(forKey: value.defaultsKey) ? .on : .off
        }
    }

    private func displayText(for value: DisplayValue) -> String? {
        switch value {
        case .actualInput:
            return snapshot.powerWatts.map(wattageText)
        case .systemDraw:
            return snapshot.systemDrawWatts.map(wattageText)
        case .chargeSurplus:
            return snapshot.chargeSurplusWatts.map(wattageText)
        case .ratedInput:
            return snapshot.ratedInputWatts.map(wattageText)
        }
    }

    private func wattageText(_ watts: Double?) -> String {
        guard let watts else {
            return "—W"
        }
        let rounded = watts.rounded()
        if abs(watts - rounded) < 0.05 {
            return "\(Int(rounded))W"
        }
        return watts.formatted(.number.precision(.fractionLength(1))) + "W"
    }

    @objc private func checkForUpdatesManually() {
        checkForUpdates(manual: true)
    }

    private var automaticUpdateMode: AutomaticUpdateMode {
        AutomaticUpdateMode(
            rawValue: UserDefaults.standard.string(forKey: AutomaticUpdateMode.defaultsKey) ?? ""
        ) ?? .daily
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func updateAutomaticUpdateMenu() {
        let selectedMode = automaticUpdateMode
        for mode in AutomaticUpdateMode.allCases {
            automaticUpdateModeItems[mode]?.state = mode == selectedMode ? .on : .off
        }
    }

    private func configureAutomaticUpdateChecking() {
        automaticUpdateTimer?.invalidate()
        automaticUpdateTimer = nil

        guard automaticUpdateMode == .daily else {
            return
        }

        // Check once on launch if today's UTC check has not happened yet,
        // then schedule the next check precisely for the following midnight.
        if shouldCheckForCurrentUTCDay() {
            checkForUpdates(manual: false)
        }
        scheduleNextAutomaticUpdateCheck()
    }

    private func shouldCheckForCurrentUTCDay() -> Bool {
        guard let lastCheck = UserDefaults.standard.object(forKey: lastUpdateCheckKey) as? Date else {
            return true
        }
        return !utcCalendar.isDate(lastCheck, inSameDayAs: Date())
    }

    private func scheduleNextAutomaticUpdateCheck() {
        let calendar = utcCalendar
        let startOfToday = calendar.startOfDay(for: Date())
        let nextMidnight = calendar.date(
            byAdding: .day,
            value: 1,
            to: startOfToday
        ) ?? Date().addingTimeInterval(24 * 60 * 60)
        let interval = max(1, nextMidnight.timeIntervalSinceNow)

        automaticUpdateTimer = Timer.scheduledTimer(
            timeInterval: interval,
            target: self,
            selector: #selector(automaticUpdateTimerFired),
            userInfo: nil,
            repeats: false
        )
        automaticUpdateTimer?.tolerance = 1.0
    }

    @objc private func automaticUpdateTimerFired() {
        automaticUpdateTimer = nil
        guard automaticUpdateMode == .daily else {
            return
        }

        checkForUpdates(manual: false)
        scheduleNextAutomaticUpdateCheck()
    }

    private func checkForUpdates(manual: Bool) {
        guard updateTask == nil else {
            if manual {
                showUpdateMessage(
                    title: "Update check in progress",
                    message: "Watt is it? is already checking for an update."
                )
            }
            return
        }

        let currentVersion = appVersion

        updateTask = Task { [weak self] in
            do {
                let update = try await UpdateService.fetchLatestUpdate(currentVersion: currentVersion)
                guard !Task.isCancelled else {
                    self?.updateTask = nil
                    return
                }
                self?.finishUpdateCheck(update, manual: manual)
            } catch {
                guard !Task.isCancelled else {
                    self?.updateTask = nil
                    return
                }
                self?.finishUpdateCheck(error: error, manual: manual)
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private func showUpdateSuccessIfNeeded() {
        guard let pendingVersion = UserDefaults.standard.string(forKey: pendingUpdateVersionKey) else {
            return
        }

        UserDefaults.standard.removeObject(forKey: pendingUpdateVersionKey)
        guard pendingVersion == appVersion else {
            return
        }

        updateMessageItem.title = "Successfully updated to \(appVersion)"
        updateMessageItem.isHidden = false
        successMessageTimer?.invalidate()
        successMessageTimer = Timer.scheduledTimer(
            timeInterval: 10.0,
            target: self,
            selector: #selector(hideUpdateSuccess),
            userInfo: nil,
            repeats: false
        )
    }

    @objc private func hideUpdateSuccess() {
        updateMessageItem.isHidden = true
        successMessageTimer = nil
    }

    private func finishUpdateCheck(_ update: AppUpdate?, manual: Bool) {
        updateTask = nil
        UserDefaults.standard.set(Date(), forKey: lastUpdateCheckKey)

        guard let update else {
            if manual {
                showUpdateMessage(
                    title: "You’re up to date",
                    message: "Watt is it? \(appVersion) is the latest published release."
                )
            }
            return
        }

        let alert = NSAlert()
        alert.messageText = "Watt is it? \(update.version) is available"
        alert.informativeText = "You’re running \(appVersion). Download the latest release and restart Watt is it? to install it."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download & Install")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == .alertFirstButtonReturn {
            downloadAndInstall(update)
        }
    }

    private func finishUpdateCheck(error: Error, manual: Bool) {
        updateTask = nil
        guard manual else {
            return
        }

        showUpdateMessage(
            title: "Update check failed",
            message: error.localizedDescription
        )
    }

    private func downloadAndInstall(_ update: AppUpdate) {
        let currentAppURL = Bundle.main.bundleURL
        let pendingUpdateKey = pendingUpdateVersionKey
        setUpdateActivity(true)

        updateTask = Task { [weak self] in
            do {
                let downloadedDMG = try await UpdateService.downloadDMG(for: update)
                try await Task.detached(priority: .userInitiated) {
                    try UpdateInstaller.prepareInstallation(
                        dmgURL: downloadedDMG,
                        replacing: currentAppURL
                    )
                }.value

                guard !Task.isCancelled else {
                    self?.updateTask = nil
                    self?.setUpdateActivity(false)
                    return
                }

                UserDefaults.standard.set(update.version, forKey: pendingUpdateKey)
                self?.finishSuccessfulInstallation()
            } catch {
                guard !Task.isCancelled else {
                    self?.updateTask = nil
                    self?.setUpdateActivity(false)
                    return
                }

                self?.finishInstallation(error: error)
            }
        }
    }

    private func finishSuccessfulInstallation() {
        updateTask = nil
        setUpdateActivity(false)
        NSApp.terminate(nil)
    }

    private func finishInstallation(error: Error) {
        updateTask = nil
        setUpdateActivity(false)
        showUpdateMessage(
            title: "Update could not be installed",
            message: error.localizedDescription
        )
    }

    private func showUpdateMessage(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

@main
struct WattIsItMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}
