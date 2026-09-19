import Foundation

public enum WarmupPlateEngine {
    public static let defaultPlatesKg: [Double] = [25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25]
    public static let defaultPlatesLbs: [Double] = [45.0, 35.0, 25.0, 10.0, 5.0, 2.5]

    public static func defaultPlates(for unit: WeightUnit) -> [Double] {
        return unit == .lbs ? defaultPlatesLbs : defaultPlatesKg
    }

    public static func defaultPlates(unit: WeightUnit = .kg) -> [Double] {
        return unit == .lbs ? defaultPlatesLbs : defaultPlatesKg
    }

    public static func defaultPlates(_ unit: WeightUnit) -> [Double] {
        return unit == .lbs ? defaultPlatesLbs : defaultPlatesKg
    }

    public static func calculatePlates(
        targetWeight: Double,
        barWeight: Double,
        availablePlates: [Double],
        unit: WeightUnit = .kg
    ) -> PlateCalculationResult {
        let safeTarget = (targetWeight * 100).rounded() / 100
        let safeBar = (barWeight * 100).rounded() / 100

        if safeTarget <= safeBar {
            let isExact = safeTarget == safeBar
            return PlateCalculationResult(
                targetWeight: safeTarget,
                barWeight: safeBar,
                weightPerSide: 0.0,
                platesPerSide: [],
                totalPlatesWeight: 0.0,
                totalAchievedWeight: safeBar,
                remainderPerSide: 0.0,
                isExactMatch: isExact,
                displayText: isExact ? "Empty Bar" : "Below Bar Weight"
            )
        }

        let neededFromPlates = safeTarget - safeBar
        let neededPerSide = neededFromPlates / 2.0

        let sortedPlates = availablePlates.filter { $0 > 0 }.sorted(by: >)
        var remaining = neededPerSide
        var selected: [PlateCount] = []

        for plate in sortedPlates {
            if plate <= 0 { continue }
            let count = Int((remaining + 0.0001) / plate)
            if count > 0 {
                selected.append(PlateCount(weight: plate, count: count))
                remaining -= Double(count) * plate
                remaining = (remaining * 100).rounded() / 100
            }
        }

        let totalPerSide = selected.reduce(0.0) { $0 + $1.totalWeight }
        let totalBothSides = ((totalPerSide * 2.0) * 100).rounded() / 100
        let totalAchieved = (((safeBar + totalBothSides) * 100).rounded()) / 100
        let remainder = (remaining * 100).rounded() / 100
        let isExact = remainder <= 0.001

        let unitLabel = unit.label
        let displayParts = selected.map { "\($0.count)×\(formatPlateWeight($0.weight)) \(unitLabel)" }
        let displayText = displayParts.isEmpty ? "Bar only" : displayParts.joined(separator: " + ")

        return PlateCalculationResult(
            targetWeight: safeTarget,
            barWeight: safeBar,
            weightPerSide: neededPerSide,
            platesPerSide: selected,
            totalPlatesWeight: totalBothSides,
            totalAchievedWeight: totalAchieved,
            remainderPerSide: remainder,
            isExactMatch: isExact,
            displayText: displayText
        )
    }

    public static func generateWarmupRamp(
        workingWeightKg: Double,
        barWeightKg: Double = 20.0,
        availablePlatesKg: [Double] = defaultPlatesKg,
        unit: WeightUnit = .kg
    ) -> WarmupRamp {
        let safeWorking = (workingWeightKg * 100).rounded() / 100
        let safeBar = (barWeightKg * 100).rounded() / 100

        let increment = unit == .lbs ? 5.0 : 2.5
        var steps: [WarmupStep] = []

        // Step 1: Empty Bar x 10 (warm joints)
        let step1Plates = calculatePlates(targetWeight: safeBar, barWeight: safeBar, availablePlates: availablePlatesKg, unit: unit)
        steps.append(
            WarmupStep(
                setNumber: 1,
                weightKg: safeBar,
                reps: 10,
                percentage: safeWorking > 0 ? Int(((safeBar / safeWorking) * 100).rounded()) : 100,
                labelKey: "warmup.warm_joints",
                isPotentiation: false,
                platesResult: step1Plates
            )
        )

        if safeWorking > safeBar {
            let candidates: [(fraction: Double, reps: Int, labelKey: String)] = [
                (0.50, 5, "warmup.50_percent"),
                (0.70, 3, "warmup.70_percent"),
                (0.85, 1, "warmup.85_percent")
            ]

            for candidate in candidates {
                let rawWeight = safeWorking * candidate.fraction
                let roundedWeight = roundToIncrement(rawWeight, increment: increment)
                let lastWeight = steps.last?.weightKg ?? 0.0

                if roundedWeight > lastWeight && roundedWeight < safeWorking {
                    let plates = calculatePlates(targetWeight: roundedWeight, barWeight: safeBar, availablePlates: availablePlatesKg, unit: unit)
                    steps.append(
                        WarmupStep(
                            setNumber: steps.count + 1,
                            weightKg: roundedWeight,
                            reps: candidate.reps,
                            percentage: Int(candidate.fraction * 100),
                            labelKey: candidate.labelKey,
                            isPotentiation: candidate.fraction >= 0.84,
                            platesResult: plates
                        )
                    )
                }
            }
        }

        return WarmupRamp(
            workingWeightKg: safeWorking,
            barWeightKg: safeBar,
            steps: steps
        )
    }

    public static func roundToIncrement(_ value: Double, increment: Double) -> Double {
        guard increment > 0 else { return value }
        let factor = 1.0 / increment
        let rounded = (value * factor).rounded() / factor
        return (rounded * 100).rounded() / 100
    }

    public static func formatPlateWeight(_ weight: Double) -> String {
        if weight.truncatingRemainder(dividingBy: 1.0) == 0.0 {
            return "\(Int(weight))"
        }
        return String(format: "%.2f", weight).replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
    }
}
