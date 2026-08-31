import Foundation
import IOKit

enum PowerReader {
    static func read() -> PowerSnapshot {
        let now = Date()
        let properties = smartBatteryProperties()
        guard !properties.isEmpty else {
            return PowerSnapshot(
                hasBattery: false,
                externalConnected: false,
                isCharging: false,
                isFullyCharged: false,
                batteryPercent: nil,
                powerWatts: nil,
                systemDrawWatts: nil,
                ratedInputWatts: nil,
                chargeSurplusWatts: nil,
                updateDate: now,
                errorMessage: "No AppleSmartBattery service found"
            )
        }

        let chargerData = dictionary(properties["ChargerData"])
        let telemetry = dictionary(properties["PowerTelemetryData"])
        let adapterDetails = dictionary(properties["AdapterDetails"])
        let powerDistribution = dictionary(properties["PowerDistribution"])

        let externalConnected = bool(properties["ExternalConnected"])
            ?? bool(properties["AppleRawExternalConnected"])
            ?? false
        let charging = bool(properties["IsCharging"])
            ?? bool(chargerData["IsCharging"])
            ?? false
        let fullyCharged = bool(properties["FullyCharged"]) ?? false

        let capacity = number(properties["CurrentCapacity"])
        let maximumCapacity = number(properties["MaxCapacity"])
        let batteryPercent = percent(current: capacity, maximum: maximumCapacity)

        // SystemPowerIn is reported by macOS in milliwatts. It is the power
        // delivered by the adapter, rather than the battery's own current.
        let telemetryPower = number(telemetry["SystemPowerIn"]).map { $0 / 1_000 }
        let inputVoltage = number(telemetry["SystemVoltageIn"]).map { $0 / 1_000 }
        let inputCurrent = number(telemetry["SystemCurrentIn"]).map { abs($0) / 1_000 }
        let calculatedInputPower = inputVoltage.flatMap { voltage in
            inputCurrent.map { voltage * $0 }
        }

        // SystemLoad is reported by macOS in milliwatts. It represents the
        // Mac's current system draw, which lets the menu show the remaining
        // rated adapter headroom as a useful charging-surplus estimate.
        let systemDrawWatts = number(telemetry["SystemLoad"])
            .flatMap { $0 > 0.1 ? $0 / 1_000 : nil }

        let powerWatts: Double?
        if externalConnected {
            powerWatts = telemetryPower.flatMap { $0 > 0.1 ? $0 : nil } ?? calculatedInputPower
        } else {
            powerWatts = nil
        }

        // AdapterDetails.Watts is already in watts on current Macs. Older
        // systems expose the same rating through PowerDistribution in mW.
        let ratedInputWatts = number(adapterDetails["Watts"])
            ?? number(powerDistribution["IPDWattageOverride"]).map { $0 / 1_000 }
            ?? number(powerDistribution["IPDInputPower"]).map { $0 / 1_000 }

        let chargeSurplusWatts = ratedInputWatts.flatMap { rated in
            systemDrawWatts.map { rated - $0 }
        }

        return PowerSnapshot(
            hasBattery: true,
            externalConnected: externalConnected,
            isCharging: charging,
            isFullyCharged: fullyCharged,
            batteryPercent: batteryPercent,
            powerWatts: powerWatts,
            systemDrawWatts: systemDrawWatts,
            ratedInputWatts: ratedInputWatts,
            chargeSurplusWatts: chargeSurplusWatts,
            updateDate: now,
            errorMessage: nil
        )
    }

    private static func smartBatteryProperties() -> [String: Any] {
        let matching = IOServiceMatching("AppleSmartBattery")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return [:]
        }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else {
            return [:]
        }
        defer { IOObjectRelease(service) }

        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            service,
            &unmanagedProperties,
            kCFAllocatorDefault,
            0
        ) == KERN_SUCCESS else {
            return [:]
        }

        guard let unmanagedProperties else {
            return [:]
        }
        return (unmanagedProperties.takeRetainedValue() as? [String: Any]) ?? [:]
    }

    private static func dictionary(_ value: Any?) -> [String: Any] {
        if let dictionary = value as? [String: Any] {
            return dictionary
        }
        if let dictionary = value as? NSDictionary {
            return dictionary.reduce(into: [String: Any]()) { partialResult, element in
                if let key = element.key as? String {
                    partialResult[key] = element.value
                }
            }
        }
        return [:]
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            return value.boolValue
        }
        if let value = value as? String {
            switch value.lowercased() {
            case "yes", "true": return true
            case "no", "false": return false
            default: return nil
            }
        }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber {
            let type = String(cString: value.objCType)
            if type == "Q" {
                let raw = value.uint64Value
                if raw > UInt64(Int64.max) {
                    return Double(Int64(bitPattern: raw))
                }
            }
            return value.doubleValue
        }
        if let value = value as? Double {
            return value
        }
        if let value = value as? Int {
            return Double(value)
        }
        if let value = value as? UInt64 {
            return Double(value)
        }
        return nil
    }

    private static func percent(current: Double?, maximum: Double?) -> Int? {
        guard let current, let maximum, maximum > 0 else {
            return nil
        }
        return Int((current / maximum * 100).rounded()).clamped(to: 0...100)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
