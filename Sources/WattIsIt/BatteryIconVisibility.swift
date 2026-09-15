import Foundation

// macOS exposes no public API for the Control Center battery menu-bar icon,
// so its visibility preference is changed directly. The preference differs
// across macOS releases: current versions use the per-host integer "Battery"
// module setting, older ones a boolean "NSStatusItem Visible Battery". Every
// known candidate is recorded before hiding and restored afterwards, so the
// user's original state returns when the icon is shown again.
enum BatteryIconVisibility {
    private static let controlCenterDomain = "com.apple.controlcenter" as CFString

    private static let hiddenByAppKey = "batteryIconHiddenByApp"
    private static let restoreStateKey = "batteryIconRestoreState"
    private static let absentValue = -1

    // 8 keeps a module in Control Center only, removing it from the menu bar.
    private static let hiddenModuleValue = 8

    private struct Candidate {
        let name: String
        let hostSpecific: Bool
        let isInteger: Bool
    }

    private static let candidates = [
        Candidate(name: "Battery", hostSpecific: true, isInteger: true),
        Candidate(name: "NSStatusItem Visible Battery", hostSpecific: false, isInteger: false),
        Candidate(name: "NSStatusItem Visible Battery", hostSpecific: true, isInteger: false)
    ]

    static var isHiddenByApp: Bool {
        UserDefaults.standard.bool(forKey: hiddenByAppKey)
    }

    // True unless a present preference already keeps the icon out of the
    // menu bar, in which case the app leaves the user's own choice alone.
    static var isSystemVisible: Bool {
        for candidate in candidates {
            guard let number = storedNumber(for: candidate) else {
                continue
            }
            if candidate.isInteger {
                // 0 = never, 8 = Control Center only.
                if number == 0 || number == hiddenModuleValue {
                    return false
                }
            } else if number == 0 {
                return false
            }
        }
        return true
    }

    static func hide() {
        var restoreState: [String: Int] = [:]
        for candidate in candidates {
            restoreState[identifier(for: candidate)] = storedNumber(for: candidate) ?? absentValue
        }

        // Persist the recovery state before the first Control Center change
        // so a crash mid-way still leaves the original values recoverable.
        UserDefaults.standard.set(restoreState, forKey: restoreStateKey)
        UserDefaults.standard.set(true, forKey: hiddenByAppKey)

        for candidate in candidates {
            setNumber(imposedNumber(for: candidate), for: candidate)
        }
        applyChanges()
    }

    static func restore() {
        guard isHiddenByApp else {
            return
        }

        let stored = UserDefaults.standard.dictionary(forKey: restoreStateKey) ?? [:]
        for candidate in candidates {
            guard let raw = stored[identifier(for: candidate)] else {
                continue
            }
            // Leave the preference alone when its current value no longer
            // matches the one hide() imposed; the user changed it in the
            // meantime and that newer choice wins.
            guard imposedNumber(for: candidate) == storedNumber(for: candidate) else {
                continue
            }
            let number = (raw as? NSNumber)?.intValue ?? absentValue
            if number == absentValue {
                removeValue(for: candidate)
            } else {
                setNumber(number, for: candidate)
            }
        }
        UserDefaults.standard.removeObject(forKey: restoreStateKey)
        UserDefaults.standard.set(false, forKey: hiddenByAppKey)
        applyChanges()
    }

    private static func imposedNumber(for candidate: Candidate) -> Int {
        candidate.isInteger ? hiddenModuleValue : 0
    }

    private static func identifier(for candidate: Candidate) -> String {
        "\(candidate.hostSpecific ? "byhost" : "app")|\(candidate.name)"
    }

    private static func host(for candidate: Candidate) -> CFString {
        candidate.hostSpecific ? kCFPreferencesCurrentHost : kCFPreferencesAnyHost
    }

    private static func storedNumber(for candidate: Candidate) -> Int? {
        guard
            let value = CFPreferencesCopyValue(
                candidate.name as CFString,
                controlCenterDomain,
                kCFPreferencesCurrentUser,
                host(for: candidate)
            ),
            let number = value as? NSNumber
        else {
            return nil
        }
        return number.intValue
    }

    private static func setNumber(_ number: Int, for candidate: Candidate) {
        let value: CFPropertyList = candidate.isInteger
            ? NSNumber(value: number)
            : (number != 0 ? kCFBooleanTrue : kCFBooleanFalse)
        CFPreferencesSetValue(
            candidate.name as CFString,
            value,
            controlCenterDomain,
            kCFPreferencesCurrentUser,
            host(for: candidate)
        )
    }

    private static func removeValue(for candidate: Candidate) {
        CFPreferencesSetValue(
            candidate.name as CFString,
            nil,
            controlCenterDomain,
            kCFPreferencesCurrentUser,
            host(for: candidate)
        )
    }

    private static func applyChanges() {
        CFPreferencesAppSynchronize(controlCenterDomain)

        // ControlCenter only reads the visibility preferences at launch, so
        // it is restarted to apply the change. launchd relaunches it at once.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["ControlCenter"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
