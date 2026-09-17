import SwiftUI

struct ExerciseMuscleProfile: Decodable {
    let primary: [String]
    let secondary: [String]
    let focus: String
    let initialView: String
    let status: String
    let sources: [String]
    var all: [String] { primary + secondary }
}
struct ExerciseAnatomyView: Decodable {
    let offsetX: CGFloat
    let regions: [String: String]
}
struct ExerciseMuscleCatalog: Decodable {
    let version: Int
    let width: CGFloat
    let height: CGFloat
    let views: [String: ExerciseAnatomyView]
    let muscles: [String: [String: String]]
    let exercises: [String: ExerciseMuscleProfile]

    static let shared: ExerciseMuscleCatalog? = {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "ExerciseMuscles"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ExerciseMuscleCatalog.self, from: data)
    }()
    func profile(_ id: String?) -> ExerciseMuscleProfile? {
        guard let id, let profile = exercises[id], profile.status == "curated" else { return nil }
        return profile
    }
    func availableViews(_ profile: ExerciseMuscleProfile) -> [String] {
        [profile.initialView, profile.initialView == "front" ? "back" : "front"].filter { view in
            profile.all.contains { views[view]?.regions[$0] != nil }
        }
    }
    static let images: [String: UIImage] = {
        var result: [String: UIImage] = [:]
        for view in ["front", "back"] {
            if let url = Bundle.main.url(forResource: view, withExtension: "png", subdirectory: "ExerciseMuscles"),
               let image = UIImage(contentsOfFile: url.path) { result[view] = image }
        }
        return result
    }()
}

struct ExerciseMusclesCard: View {
    let exerciseId: String?
    let initiallyExpanded: Bool
    @State private var isExpanded: Bool
    @State private var selectedView: String?
    @ObservedObject private var language = LanguageManager.shared
    @Environment(\.dynamicTypeSize) private var dynamicType
    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) private var labelSize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption) private var noteSize: CGFloat = 12

    init(exerciseId: String?, initiallyExpanded: Bool = true) {
        self.exerciseId = exerciseId
        self.initiallyExpanded = initiallyExpanded
        self._isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 14 : 0) {
            HStack {
                Text(LanguageManager.t("anatomy.title"))
                    .font(.system(size: titleSize, weight: .semibold)).foregroundColor(AppColors.text)

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.muted)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }

            if isExpanded {
                if let catalog = ExerciseMuscleCatalog.shared, let profile = catalog.profile(exerciseId) {
                    let view = selectedView ?? profile.initialView
                    let views = catalog.availableViews(profile)
                    if dynamicType >= .xxLarge {
                        stacked(catalog, profile, view, views)
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .center, spacing: 16) {
                                figure(catalog, profile, view).frame(width: 128, height: 190)
                                VStack(alignment: .leading, spacing: 16) {
                                    legend(catalog, profile)
                                    if views.count > 1 {
                                        segmentedControl(views, selected: view)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("anatomy-legend")
                            }.frame(minWidth: 260)
                            stacked(catalog, profile, view, views)
                        }
                    }
                    Text(LanguageManager.t("anatomy.note"))
                        .font(.system(size: noteSize)).foregroundColor(AppColors.muted).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(LanguageManager.t("anatomy.unavailable"))
                        .font(.system(size: bodySize)).foregroundColor(AppColors.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            if !isExpanded {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = true
                }
            }
        }
        .accessibilityIdentifier("exercise-muscles-card")
        .onChange(of: exerciseId) { _, _ in selectedView = nil }
    }

    private func stacked(_ catalog: ExerciseMuscleCatalog, _ profile: ExerciseMuscleProfile, _ view: String, _ views: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            figure(catalog, profile, view).frame(maxWidth: .infinity).frame(height: 210)
            VStack(alignment: .leading, spacing: 16) {
                legend(catalog, profile)
                if views.count > 1 {
                    segmentedControl(views, selected: view)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("anatomy-legend")
        }
    }

    private func segmentedControl(_ views: [String], selected: String) -> some View {
        HStack(spacing: 2) {
            ForEach(views, id: \.self) { option in
                let isSelected = selected == option
                Button {
                    selectedView = option
                } label: {
                    Text(LanguageManager.t(option == "front" ? "anatomy.front" : "anatomy.back"))
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(isSelected ? AppColors.purple : AppColors.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(isSelected ? AppColors.purpleBg : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? AppColors.purple.opacity(0.6) : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("anatomy-view-\(option)")
            }
        }
        .padding(3)
        .frame(height: 38)
        .background(AppColors.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private func legend(_ catalog: ExerciseMuscleCatalog, _ profile: ExerciseMuscleProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            muscleList(catalog, profile.primary, primary: true)
            if !profile.secondary.isEmpty { muscleList(catalog, profile.secondary, primary: false) }
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func muscleList(_ catalog: ExerciseMuscleCatalog, _ muscles: [String], primary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LanguageManager.t(primary ? "anatomy.primary" : "anatomy.secondary"))
                .font(.system(size: labelSize, weight: .medium)).foregroundColor(AppColors.secondaryText)
            ForEach(muscles, id: \.self) { muscle in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(primary ? AppColors.purple : AppColors.muscleSecondary)
                        .frame(width: 8, height: 8).padding(.top, bodySize * 0.3).accessibilityHidden(true)
                    Text(catalog.muscles[muscle]?[language.currentLanguage] ?? muscle)
                        .font(.system(size: bodySize, weight: .medium)).foregroundColor(AppColors.text)
                        .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func figure(_ catalog: ExerciseMuscleCatalog, _ profile: ExerciseMuscleProfile, _ view: String) -> some View {
        let anatomy = catalog.views[view]
        let paths = profile.all.compactMap { muscle -> (String, CGPath)? in
            guard let raw = anatomy?.regions[muscle] else { return nil }
            return (muscle, SVGPathParser.parse(raw))
        }
        return Canvas { context, size in
            guard let anatomy, let image = ExerciseMuscleCatalog.images[view] else { return }
            let top: CGFloat = profile.focus == "lower" ? 410 : 0
            let height: CGFloat = profile.focus == "lower" ? 614 : 620
            let scale = min(size.width / catalog.width, size.height / height)
            context.clip(to: Path(CGRect(origin: .zero, size: size)))
            context.translateBy(x: (size.width - catalog.width * scale) / 2, y: (size.height - height * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: 0, y: -top)
            context.draw(Image(uiImage: image), in: CGRect(x: 0, y: 0, width: catalog.width, height: catalog.height))
            context.translateBy(x: -anatomy.offsetX, y: 0)
            context.blendMode = .color
            context.opacity = 0.7
            for (muscle, path) in paths {
                context.fill(Path(path), with: .color(profile.primary.contains(muscle) ? AppColors.purple : AppColors.muscleSecondary))
            }
        }.accessibilityLabel(LanguageManager.t(view == "front" ? "anatomy.front" : "anatomy.back"))
    }
}
