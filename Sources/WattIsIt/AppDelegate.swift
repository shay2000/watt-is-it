import AppKit

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

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu!
    private var displaySubmenu: NSMenu!
    private var actualInputItem: NSMenuItem!
    private var systemDrawItem: NSMenuItem!
    private var chargeSurplusItem: NSMenuItem!
    private var ratedInputItem: NSMenuItem!
    private var displayItems: [DisplayValue: NSMenuItem] = [:]
    private var refreshTimer: Timer?
    private var snapshot = PowerSnapshot.unavailable

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            DisplayValue.actualInput.defaultsKey: true,
            DisplayValue.systemDraw.defaultsKey: false,
            DisplayValue.chargeSurplus.defaultsKey: false,
            DisplayValue.ratedInput.defaultsKey: false
        ])

        NSApp.setActivationPolicy(.accessory)
        configureStatusMenu()
        refresh()

        refreshTimer = Timer.scheduledTimer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(refresh),
            userInfo: nil,
            repeats: true
        )
        refreshTimer?.tolerance = 0.1
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
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

        let quitItem = NSMenuItem(
            title: "Quit Watt is it?",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        statusMenu.addItem(quitItem)
        updateDisplayMenu()
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

        guard let button = newStatusItem.button else {
            return
        }
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.toolTip = "Watt is it? — actual input"
    }

    private func removeStatusItemIfNeeded() {
        guard let statusItem else {
            return
        }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    @objc private func refresh() {
        snapshot = PowerReader.read()

        // Keep the indicator absent until an adapter is connected. The timer
        // remains alive so it can return as soon as the Mac is plugged in.
        guard snapshot.externalConnected else {
            removeStatusItemIfNeeded()
            return
        }

        installStatusItemIfNeeded()
        renderStatusItem()
        updateStatusMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
        updateStatusMenu()
        updateDisplayMenu()
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
        button.title = values.isEmpty ? wattageText(snapshot.powerWatts) : values.joined(separator: "  ")
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
