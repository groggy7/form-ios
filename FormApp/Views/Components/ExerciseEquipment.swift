import SwiftUI

struct EquipmentCategory: Decodable, Identifiable {
    let id: String
    let en: String
    let tr: String
    let icon: String
    var title: String { LanguageManager.shared.currentLanguage == "tr" ? tr : en }
}
struct EquipmentCatalog: Decodable {
    let categories: [EquipmentCategory]
    let exercises: [String: String]
    static let shared: EquipmentCatalog = {
        guard let url = Bundle.main.url(forResource: "equipment_catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(EquipmentCatalog.self, from: data) else {
            assertionFailure("Missing equipment catalogue")
            return EquipmentCatalog(categories: [], exercises: [:])
        }
        return catalog
    }()
    func categoryId(_ exerciseId: String?) -> String { exerciseId.flatMap { exercises[$0] } ?? "other" }
    func matches(_ exerciseId: String?, selected: String?) -> Bool { selected == nil || categoryId(exerciseId) == selected }
}

func equipmentSolidColor(categoryId: String) -> Color {
    switch categoryId {
    case "bar": return Color(hex: 0xF59E0B)           // Amber / Gold
    case "dumbbell": return Color(hex: 0xA855F7)      // Purple
    case "resistance-band": return Color(hex: 0xF97316) // Coral / Orange
    case "kettlebell": return Color(hex: 0x10B981)    // Emerald
    case "machine": return Color(hex: 0x0EA5E9)       // Sky / Cyan
    case "weight-plate": return Color(hex: 0xEF4444)  // Crimson / Rose
    default: return Color(hex: 0x6366F1)            // Indigo / Blue
    }
}

struct EquipmentIcon: View {
    let category: EquipmentCategory
    let tint: Color
    var size: CGFloat = 20
    var body: some View {
        Canvas { context, sz in
            context.scaleBy(x: sz.width / 24, y: sz.height / 24)
            context.stroke(Path(SVGPathParser.parse(category.icon)), with: .color(tint),
                           style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
