import SwiftUI
import UIKit

/// Stable library IDs; names and workout edits never determine the bundled cover.
public enum ProgramCover: String, CaseIterable {
    case hypertrophy, powerbuilding, pushPullLegs = "push_pull_legs", fullBody = "full_body"
    case homeDumbbells = "home_dumbbells", strengthPower = "strength_power", upperLower = "upper_lower", machines

    public var assetName: String { "program_cover_\(rawValue)" }
    public var programID: String {
        switch self {
        case .hypertrophy: return "aesthetic-hypertrophy"
        case .powerbuilding: return "powerbuilding-strength"
        case .pushPullLegs: return "classic-ppl"
        case .fullBody: return "full-body-classic"
        case .homeDumbbells: return "home-forge-dumbbells"
        case .strengthPower: return "athletic-performance"
        case .upperLower: return "upper-lower-balanced"
        case .machines: return "machine-foundation"
        }
    }
    public static func forProgram(_ id: String) -> ProgramCover {
        allCases.first { $0.programID == id } ?? .fullBody
    }
}

/// One measured height for every card, including translated text and Dynamic Type.
enum ProgramHeroLayout {
    static func descriptionFraction(width: CGFloat, bodySize: CGFloat) -> CGFloat {
        bodySize > 13 * 1.15 || width < 300 ? 0.84 : 0.66
    }
    static func textHeight(_ text: String, width: CGFloat, size: CGFloat, weight: UIFont.Weight, spacing: CGFloat = 0) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = spacing
        return ceil((text as NSString).boundingRect(
            with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: UIFont.systemFont(ofSize: size, weight: weight), .paragraphStyle: paragraph], context: nil).height)
    }
    static func height(programs: [Program], width: CGFloat, titleSize: CGFloat, bodySize: CGFloat, daysSize: CGFloat) -> CGFloat {
        let contentWidth = max(1, width - 32)
        return programs.reduce(CGFloat(240)) { current, program in
            let title = textHeight(program.displayName, width: contentWidth - 56, size: titleSize, weight: .semibold, spacing: 2)
            let description = program.displayDescription.isEmpty ? 0 : 10 + textHeight(program.displayDescription, width: contentWidth * descriptionFraction(width: width, bodySize: bodySize), size: bodySize, weight: .regular, spacing: 3)
            let days = LanguageManager.t("programs.daysPerWeek", ["days": "\(program.workouts.filter { !$0.exercises.isEmpty }.count)"])
            let footer = max(48, textHeight(days, width: contentWidth - 48, size: daysSize, weight: .semibold))
            return max(current, 32 + title + description + 14 + footer + 4)
        }
    }
}

public struct ProgramsView: View {
    @ObservedObject var store: AppStore
    var onDismiss: () -> Void
    @State private var editingProgram: Program? = nil
    @State private var isCreatingNew = false
    @State private var showFileImporter = false
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 13
    @ScaledMetric(relativeTo: .subheadline) private var daysSize: CGFloat = 12

    public init(store: AppStore, onDismiss: @escaping () -> Void) {
        self.store = store
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let width = max(1, geometry.size.width - 40)
                let height = ProgramHeroLayout.height(programs: store.state.programs, width: width, titleSize: titleSize, bodySize: bodySize, daysSize: daysSize)
                ScrollView {
                    VStack(spacing: 14) {
                        HStack(spacing: 12) {
                            Button(action: { isCreatingNew = true }) {
                                Label(LanguageManager.t("programs.new"), systemImage: "plus")
                                    .font(.system(size: bodySize * 14 / 13, weight: .semibold))
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .background(AppColors.accent).foregroundStyle(AppColors.todaySelectionText)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain)
                            Button(action: { showFileImporter = true }) {
                                Label(LanguageManager.t("programs.import"), systemImage: "square.and.arrow.down")
                                    .font(.system(size: bodySize * 14 / 13, weight: .semibold))
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .foregroundStyle(AppColors.text)
                                    .background(AppColors.surface)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
                            }.buttonStyle(.plain)
                        }
                        if store.state.programs.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(LanguageManager.t("programs.empty")).font(.title3).foregroundStyle(AppColors.text)
                                Text(LanguageManager.t("programs.emptyHint")).foregroundStyle(AppColors.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 32)
                        }
                        ForEach(store.state.programs) { program in
                            ProgramHeroCard(program: program, isActive: program.id == store.state.activeProgramId,
                                width: width, height: height, titleSize: titleSize, bodySize: bodySize, daysSize: daysSize,
                                onSelect: { store.switchProgram(to: program.id); onDismiss() },
                                onEdit: { editingProgram = program })
                        }
                    }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 24)
                }
            }
            .background(AppColors.background)
            .navigationTitle(LanguageManager.t("programs.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark").font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColors.secondaryText).frame(width: 48, height: 48)
                            .background(AppColors.surfaceRaised, in: Circle())
                    }.accessibilityLabel(LanguageManager.t("common.close"))
                }
            }
            .sheet(item: $editingProgram) { program in
                ProgramBuilderView(store: store, program: program) { editingProgram = nil }
            }
            .sheet(isPresented: $isCreatingNew) {
                ProgramBuilderView(store: store) { isCreatingNew = false }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first, url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let data = try? Data(contentsOf: url) { _ = try? store.importProgram(jsonData: data) }
                }
            }
        }
    }
}

struct ProgramHeroCard: View {
    let program: Program
    let isActive: Bool
    let width: CGFloat
    let height: CGFloat
    let titleSize: CGFloat
    let bodySize: CGFloat
    let daysSize: CGFloat
    let onSelect: () -> Void
    let onEdit: () -> Void

    var body: some View {
        let contentWidth = max(1, width - 32)
        let wideText = ProgramHeroLayout.descriptionFraction(width: width, bodySize: bodySize) > 0.7
        ZStack(alignment: .topTrailing) {
            AppColors.surface
            let imageHeight = max(height, width / 1.5)
            let imageWidth = imageHeight * 1.5
            Image(ProgramCover.forProgram(program.id).assetName).resizable()
                .frame(width: imageWidth, height: imageHeight)
                .position(x: imageWidth / 2 - (imageWidth - width) * 0.75, y: height / 2)
                .accessibilityHidden(true)
            LinearGradient(stops: [.init(color: AppColors.background.opacity(0.96), location: 0),
                .init(color: AppColors.background.opacity(0.90), location: wideText ? 0.76 : 0.48),
                .init(color: AppColors.background.opacity(wideText ? 0.55 : 0.35), location: wideText ? 0.94 : 0.78),
                .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [.init(color: AppColors.background.opacity(0.15), location: 0),
                .init(color: .clear, location: 0.70), .init(color: AppColors.background.opacity(0.8), location: 1)], startPoint: .top, endPoint: .bottom)
            // The switch button and edit button are siblings, so editing never switches programs.
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(program.displayName).font(.system(size: titleSize, weight: .semibold)).lineSpacing(2)
                        .foregroundStyle(AppColors.text).frame(width: max(1, contentWidth - 56), alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    if !program.displayDescription.isEmpty {
                        Text(program.displayDescription).font(.system(size: bodySize)).lineSpacing(3)
                            .foregroundStyle(AppColors.secondaryText).frame(width: contentWidth * ProgramHeroLayout.descriptionFraction(width: width, bodySize: bodySize), alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                    }
                    Spacer(minLength: 14)
                    HStack(spacing: 6) {
                        Image(systemName: "calendar").font(.system(size: 16)).foregroundStyle(AppColors.accent)
                        Text(LanguageManager.t("programs.daysPerWeek", ["days": "\(program.workouts.filter { !$0.exercises.isEmpty }.count)"]))
                            .font(.system(size: daysSize, weight: .semibold)).foregroundStyle(AppColors.accent)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.system(size: 18)).foregroundStyle(AppColors.secondaryText)
                    }.frame(minHeight: 48)
                }.padding(16).frame(width: width, height: height, alignment: .topLeading).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityIdentifier("program-card-\(program.id)")
                .accessibilityAddTraits(isActive ? [.isSelected] : [])
            Button(action: onEdit) {
                Image(systemName: "pencil").font(.system(size: 18)).foregroundStyle(AppColors.secondaryText)
                    .frame(width: 48, height: 48).background(AppColors.surfaceRaised.opacity(0.9), in: Circle())
            }.buttonStyle(.plain).padding(12)
                .accessibilityLabel("\(LanguageManager.t("programs.edit")) \(program.displayName)")
            if isActive {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 24)).foregroundStyle(AppColors.accent)
                    .padding(.top, 72).padding(.trailing, 24).accessibilityHidden(true)
            }
        }
        .frame(width: width, height: height).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(isActive ? AppColors.accent : AppColors.border, lineWidth: isActive ? 2 : 1))
    }
}
