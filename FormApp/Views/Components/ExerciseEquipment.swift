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

struct EquipmentIcon: View {
    let category: EquipmentCategory
    let tint: Color
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 24, y: size.height / 24)
            context.stroke(Path(SVGPathParser.parse(category.icon)), with: .color(tint),
                           style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }
}
