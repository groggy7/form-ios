import Foundation

public enum WarmupPlateEngine {
    public static let defaultPlatesKg: [Double] = [25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25]
    public static let defaultPlatesLbs: [Double] = [45.0, 35.0, 25.0, 10.0, 5.0, 2.5]

    public static func supportsExercise(equipmentCategory: String) -> Bool { equipmentCategory == "bar" }

    public static func hasWorkingLoad(_ weightKg: Double?) -> Bool {
        guard let weightKg else { return false }
        return weightKg.isFinite && weightKg > 0
    }

    public static func defaultPlates(for unit: WeightUnit) -> [Double] {
        return unit == .lbs ? defaultPlatesLbs : defaultPlatesKg
    }

    public static func defaultPlates(unit: WeightUnit = .kg) -> [Double] {
        defaultPlates(for: unit)
    }

    public static func calculatePlates(
        targetWeight: Double,
        barWeight: Double,
        availablePlates: [Double],
        unit: WeightUnit = .kg
    ) -> PlateCalculationResult {
        guard targetWeight.isFinite, barWeight.isFinite else {
            return PlateCalculationResult(
                targetWeight: 0.0,
                barWeight: 0.0,
                weightPerSide: 0.0,
                platesPerSide: [],
                totalPlatesWeight: 0.0,
                totalAchievedWeight: 0.0,
                remainderPerSide: 0.0,
                isExactMatch: false,
                displayText: "Invalid Weight"
            )
        }
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

        let sortedPlates = Array(Set(availablePlates.filter { $0 > 0 && $0.isFinite })).sorted(by: >)
        var remainingPerSide = neededPerSide
        var selectedPlates: [PlateCount] = []

        for plate in sortedPlates {
            if plate <= 0 { continue }
            let count = Int(floor((remainingPerSide + 0.0001) / plate))
            if count > 0 {
                selectedPlates.append(PlateCount(weight: plate, count: count))
                remainingPerSide -= Double(count) * plate
            }
        }
        // Heaviest-first is exact for standard sets but can miss a load with a custom set
        // (20+15+10 for 45 per side); search only then, so standard results never change.
        if (remainingPerSide * 100).rounded() / 100 > 0.01,
           let closest = closestLoad(perSide: neededPerSide, plates: sortedPlates),
           closest.remainder < remainingPerSide - 0.0001 {
            selectedPlates = closest.plates
            remainingPerSide = closest.remainder
        }

        let totalPlatesPerSide = selectedPlates.reduce(0.0) { $0 + $1.totalWeight }
        let totalPlatesBothSides = (totalPlatesPerSide * 2.0 * 100).rounded() / 100
        let totalAchieved = ((safeBar + totalPlatesBothSides) * 100).rounded() / 100
        let remainder = (remainingPerSide * 100).rounded() / 100
        let isExact = remainder <= 0.01

        let unitLabel = unit.label
        let displayParts = selectedPlates.map { "\($0.count)×\(formatPlateWeight($0.weight)) \(unitLabel)" }
        let displayText = displayParts.isEmpty ? "Bar only" : displayParts.joined(separator: " + ")

        return PlateCalculationResult(
            targetWeight: safeTarget,
            barWeight: safeBar,
            weightPerSide: neededPerSide,
            platesPerSide: selectedPlates,
            totalPlatesWeight: totalPlatesBothSides,
            totalAchievedWeight: totalAchieved,
            remainderPerSide: remainder,
            isExactMatch: isExact,
            displayText: displayText
        )
    }

    /// Plate search covers up to 1,000 display units per side.
    private static let maxSearchHundredths = 100_000

    /// Fewest plates reaching the heaviest load at or below `perSide`, preferring heavier plates.
    /// Values are hundredths of the display unit; nil when the target is out of range.
    private static func closestLoad(perSide: Double, plates: [Double]) -> (plates: [PlateCount], remainder: Double)? {
        let target = Int((perSide * 100).rounded())
        guard target > 0, target <= maxSearchHundredths else { return nil }
        let units = plates.map { Int(($0 * 100).rounded()) }
        guard units.contains(where: { $0 > 0 }) else { return nil }
        let unreachable = Int.max
        var count = [Int](repeating: unreachable, count: target + 1)
        var last = [Int](repeating: -1, count: target + 1)
        count[0] = 0
        for sum in stride(from: 1, through: target, by: 1) {
            for (index, plate) in units.enumerated() where plate > 0 && plate <= sum {
                let previous = count[sum - plate]
                if previous != unreachable, previous + 1 < count[sum] {
                    count[sum] = previous + 1
                    last[sum] = index
                }
            }
        }
        guard let best = stride(from: target, through: 0, by: -1).first(where: { count[$0] != unreachable }) else { return nil }
        var counts = [Int](repeating: 0, count: units.count)
        var sum = best
        while sum > 0 { counts[last[sum]] += 1; sum -= units[last[sum]] }
        let chosen = plates.indices.filter { counts[$0] > 0 }.map { PlateCount(weight: plates[$0], count: counts[$0]) }
        return (chosen, Double(target - best) / 100)
    }

    /// `availablePlates` are in `unit`; the bar is in canonical kilograms, as loaded in that unit.
    public static func generateWarmupRamp(
        workingWeightKg: Double,
        barWeightKg: Double = 20.0,
        availablePlates: [Double]? = nil,
        unit: WeightUnit = .kg
    ) -> WarmupRamp {
        guard hasWorkingLoad(workingWeightKg), barWeightKg.isFinite, barWeightKg > 0 else {
            return WarmupRamp(workingWeightKg: 0, barWeightKg: 0, steps: [])
        }
        let safeWorking = (workingWeightKg * 100).rounded() / 100
        let safeBar = (barWeightKg * 100).rounded() / 100
        if safeWorking < safeBar {
            return WarmupRamp(workingWeightKg: safeWorking, barWeightKg: safeBar, steps: [])
        }

        let isLbs = unit == .lbs
        let displayWorking = isLbs ? unit.toDisplay(safeWorking) : safeWorking
        // A 45 lb bar is 20.41 kg; rounding its kilograms first would show 44.99 lb and inexact plates.
        let displayBar = isLbs ? (unit.toDisplay(barWeightKg) * 100).rounded() / 100 : safeBar
        let usablePlates = (availablePlates ?? []).filter { $0 > 0 && $0.isFinite }
        let plates = usablePlates.isEmpty ? defaultPlates(for: unit) : usablePlates
        // Each step must be loadable: at least a pair of the smallest plate.
        let increment = max(isLbs ? 5.0 : 2.5, (plates.min() ?? 0) * 2)
        let barStepKg = isLbs ? unit.toCanonicalKg(displayBar) : safeBar

        var steps: [WarmupStep] = []

        // Step 1: Empty Bar x 10 (warm joints)
        let step1Plates = calculatePlates(targetWeight: displayBar, barWeight: displayBar, availablePlates: plates, unit: unit)
        steps.append(
            WarmupStep(
                setNumber: 1,
                weightKg: barStepKg,
                reps: 10,
                percentage: safeWorking > 0 ? Int(((safeBar / safeWorking) * 100).rounded()) : 100,
                labelKey: "warmup.warm_joints",
                isPotentiation: false,
                platesResult: step1Plates
            )
        )

        if displayWorking > displayBar {
            let candidates: [(fraction: Double, reps: Int, labelKey: String)] = [
                (0.50, 5, "warmup.50_percent"),
                (0.70, 3, "warmup.70_percent"),
                (0.85, 1, "warmup.85_percent")
            ]

            for candidate in candidates {
                let rawWeight = displayWorking * candidate.fraction
                let roundedDisplayWeight = roundToIncrement(rawWeight, increment: increment)
                let lastDisplayWeight = isLbs ? (steps.last.map { unit.toDisplay($0.weightKg) } ?? 0.0) : (steps.last?.weightKg ?? 0.0)

                if roundedDisplayWeight > lastDisplayWeight && roundedDisplayWeight < displayWorking {
                    let stepPlates = calculatePlates(targetWeight: roundedDisplayWeight, barWeight: displayBar, availablePlates: plates, unit: unit)
                    let stepKg = isLbs ? unit.toCanonicalKg(roundedDisplayWeight) : roundedDisplayWeight
                    steps.append(
                        WarmupStep(
                            setNumber: steps.count + 1,
                            weightKg: stepKg,
                            reps: candidate.reps,
                            percentage: Int(candidate.fraction * 100),
                            labelKey: candidate.labelKey,
                            isPotentiation: candidate.fraction >= 0.84,
                            platesResult: stepPlates
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
        guard weight.isFinite else { return "0" }
        let safe = (weight * 100.0).rounded() / 100.0
        if safe.truncatingRemainder(dividingBy: 1.0) == 0.0 {
            return "\(Int(safe))"
        }
        return String(format: "%.2f", safe).replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
    }
}
