import Foundation

struct PowerSnapshot {
    let hasBattery: Bool
    let externalConnected: Bool
    let isCharging: Bool
    let isFullyCharged: Bool
    let batteryPercent: Int?
    let powerWatts: Double?
    let systemDrawWatts: Double?
    let ratedInputWatts: Double?
    let chargeSurplusWatts: Double?
    let updateDate: Date
    let errorMessage: String?

    static let unavailable = PowerSnapshot(
        hasBattery: false,
        externalConnected: false,
        isCharging: false,
        isFullyCharged: false,
        batteryPercent: nil,
        powerWatts: nil,
        systemDrawWatts: nil,
        ratedInputWatts: nil,
        chargeSurplusWatts: nil,
        updateDate: Date(),
        errorMessage: "No battery information available"
    )

    var stateTitle: String {
        if !hasBattery {
            return "No battery detected"
        }
        if isFullyCharged {
            return externalConnected ? "Fully charged" : "On battery"
        }
        if isCharging {
            return "Charging"
        }
        if externalConnected {
            return "Connected, not charging"
        }
        return "On battery"
    }
}
