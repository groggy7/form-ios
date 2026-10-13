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
    static func height(programs: [Program], width: CGFloat, titleSize: CGFloat, bodySize: CGFloat, daysSize: CGFloat, countsSize: CGFloat = 11) -> CGFloat {
        let contentWidth = max(1, width - 32)
        let footerWidth = max(1, contentWidth - 96)
        return programs.reduce(CGFloat(216)) { current, program in
            let title = textHeight(program.displayName, width: contentWidth - 56, size: titleSize, weight: .semibold, spacing: 2)
            let description = program.displayDescription.isEmpty ? 0 : 8 + textHeight(program.displayDescription, width: contentWidth * descriptionFraction(width: width, bodySize: bodySize), size: bodySize, weight: .regular, spacing: 3)
            let days = LanguageManager.t("programs.daysPerWeek", ["days": "\(program.workouts.filter { !$0.exercises.isEmpty }.count)"])
            let counts = LanguageManager.t("programs.counts", [
                "workouts": program.workouts.count,
                "exercises": program.workouts.reduce(0) { $0 + $1.exercises.count }
            ])
            let daysHeight = textHeight(days, width: max(1, footerWidth - 24), size: daysSize, weight: .semibold)
            let countsHeight = textHeight(counts, width: footerWidth, size: countsSize, weight: .regular)
            let footer = max(40, daysHeight + 4 + countsHeight)
            return max(current, 32 + title + description + 10 + footer)
        }
    }
}

public struct ProgramsView: View {
    @ObservedObject var themeManager = ThemeManager.shared
    @ObservedObject var store: AppStore
    var onDismiss: () -> Void
    @State private var editingProgram: Program? = nil
    @State private var isCreatingNew = false
    @State private var showFileImporter = false
    @State private var importErrorMessage: String? = nil
    @State private var showImportError = false
    @State private var sharingItem: ProgramShareItem? = nil
    @State private var deletingProgram: Program? = nil
    @State private var menuProgramId: String? = nil
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 13
    @ScaledMetric(relativeTo: .subheadline) private var daysSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption) private var countsSize: CGFloat = 11

    public init(store: AppStore, onDismiss: @escaping () -> Void) {
        self.store = store
        self.onDismiss = onDismiss
    }

    private func shareProgram(_ program: Program) {
        let envelope = AppStore.ProgramFileEnvelope(format: "form.program", schemaVersion: 4, program: program)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(envelope) else { return }
        let safeName = program.displayName.replacingOccurrences(of: "[^\\p{L}\\p{N} ._-]", with: "_", options: .regularExpression)
        let filename = "\(safeName.prefix(80)).form-program.json"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: tempURL)
            sharingItem = ProgramShareItem(url: tempURL)
        } catch {
            print("Share error: \(error)")
        }
    }

    public var body: some View {
        let _ = themeManager.currentTheme
        NavigationStack {
            GeometryReader { geometry in
                let width = max(1, geometry.size.width - 40)
                let height = ProgramHeroLayout.height(programs: store.state.programs, width: width, titleSize: titleSize, bodySize: bodySize, daysSize: daysSize, countsSize: countsSize)
                ScrollView {
                    VStack(spacing: 14) {
                        HStack(spacing: 12) {
                            Button(action: { isCreatingNew = true }) {
                                Label(LanguageManager.t("programs.new"), systemImage: "plus")
                                    .font(.system(size: bodySize * 14 / 13, weight: .semibold))
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .background(AppColors.accent).foregroundStyle(AppColors.todaySelectionText)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }.buttonStyle(.plain)
                            Button(action: { showFileImporter = true }) {
                                Label(LanguageManager.t("programs.import"), systemImage: "square.and.arrow.down")
                                    .font(.system(size: bodySize * 14 / 13, weight: .semibold))
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .foregroundStyle(AppColors.text)
                                    .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppColors.border, lineWidth: 1))
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
                                width: width, height: height, titleSize: titleSize, bodySize: bodySize, daysSize: daysSize, countsSize: countsSize,
                                onSelect: {
                                    if menuProgramId != nil {
                                        withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
                                            menuProgramId = nil
                                        }
                                    } else {
                                        store.switchProgram(to: program.id)
                                        onDismiss()
                                    }
                                },
                                onEdit: { editingProgram = program },
                                onDelete: {
                                    if program.id == store.state.activeProgramId {
                                        store.showErrorNotice(LanguageManager.t("notice.cannotDeleteActiveProgram"))
                                    } else if store.activeSession?.programId == program.id {
                                        store.showErrorNotice(LanguageManager.t("history.finishActiveFirst"))
                                    } else {
                                        deletingProgram = program
                                    }
                                },
                                onToggleMenu: {
                                    withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                        menuProgramId = program.id
                                    }
                                },
                                onCloseMenu: {
                                    withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
                                        menuProgramId = nil
                                    }
                                })
                            .zIndex(menuProgramId == program.id ? 10 : 0)
                        }
                    }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 24)
                }
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if menuProgramId != nil {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
                                menuProgramId = nil
                            }
                        }
                    }
                )
            }
            .background(AppColors.background)
            .navigationTitle(LanguageManager.t("programs.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.secondaryText)
                    }
                    .accessibilityLabel(LanguageManager.t("common.close"))
                }
            }
            .sheet(item: $editingProgram) { program in
                ProgramBuilderView(store: store, program: program) { editingProgram = nil }
            }
            .sheet(isPresented: $isCreatingNew) {
                ProgramBuilderView(store: store) { isCreatingNew = false }
            }
            .sheet(item: $sharingItem) { item in
                ProgramShareSheet(url: item.url)
            }
            .alert(
                LanguageManager.t("programs.deleteTitle", ["name": deletingProgram?.displayName ?? ""]),
                isPresented: Binding(get: { deletingProgram != nil }, set: { if !$0 { deletingProgram = nil } })
            ) {
                Button(LanguageManager.t("modal.cancel"), role: .cancel) { deletingProgram = nil }
                Button(LanguageManager.t("modal.delete"), role: .destructive) {
                    if let prog = deletingProgram {
                        store.deleteProgram(withId: prog.id)
                        deletingProgram = nil
                    }
                }
            } message: {
                Text(LanguageManager.t("programs.deleteHint"))
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer {
                        if accessed {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    do {
                        let data = try Data(contentsOf: url)
                        _ = try store.importProgram(jsonData: data)
                        store.showNotice(LanguageManager.t("programs.imported"))
                    } catch {
                        importErrorMessage = error.localizedDescription
                        showImportError = true
                    }
                case .failure(let error):
                    importErrorMessage = error.localizedDescription
                    showImportError = true
                }
            }
            .alert(LanguageManager.t("programs.fileError"), isPresented: $showImportError) {
                Button(LanguageManager.t("programs.close"), role: .cancel) { }
            } message: {
                Text(importErrorMessage ?? LanguageManager.t("errors.fileRead"))
            }
        }
    }
}

struct ProgramShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ProgramShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ProgramHeroCard: View {
    @ObservedObject var themeManager = ThemeManager.shared
    let program: Program
    let isActive: Bool
    let width: CGFloat
    let height: CGFloat
    let titleSize: CGFloat
    let bodySize: CGFloat
    let daysSize: CGFloat
    var countsSize: CGFloat = 11
    let onSelect: () -> Void
    let onEdit: () -> Void
    var onShare: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var isMenuOpen: Bool = false
    var onToggleMenu: (() -> Void)? = nil
    var onCloseMenu: (() -> Void)? = nil
    @State private var localMenuOpen = false

    private var menuVisible: Bool {
        onToggleMenu != nil ? isMenuOpen : (isMenuOpen || localMenuOpen)
    }

    private func toggleMenu() {
        if menuVisible {
            closeMenu()
        } else {
            if let onToggleMenu {
                onToggleMenu()
            } else {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                    localMenuOpen = true
                }
            }
        }
    }

    private func closeMenu() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
            localMenuOpen = false
        }
        onCloseMenu?()
    }

    init(
        program: Program,
        isActive: Bool,
        width: CGFloat,
        height: CGFloat,
        titleSize: CGFloat,
        bodySize: CGFloat,
        daysSize: CGFloat,
        countsSize: CGFloat = 11,
        onSelect: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onShare: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        isMenuOpen: Bool = false,
        onToggleMenu: (() -> Void)? = nil,
        onCloseMenu: (() -> Void)? = nil
    ) {
        self.program = program
        self.isActive = isActive
        self.width = width
        self.height = height
        self.titleSize = titleSize
        self.bodySize = bodySize
        self.daysSize = daysSize
        self.countsSize = countsSize
        self.onSelect = onSelect
        self.onEdit = onEdit
        self.onShare = onShare
        self.onDelete = onDelete
        self.isMenuOpen = isMenuOpen
        self.onToggleMenu = onToggleMenu
        self.onCloseMenu = onCloseMenu
    }

    var body: some View {
        let _ = themeManager.currentTheme
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
            // The switch button and menu button are siblings, so menu taps never switch programs.
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(program.displayName).font(.system(size: titleSize, weight: .semibold)).lineSpacing(2)
                        .foregroundStyle(AppColors.text).frame(width: max(1, contentWidth - 56), alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    if !program.displayDescription.isEmpty {
                        Text(program.displayDescription).font(.system(size: bodySize)).lineSpacing(3)
                            .foregroundStyle(AppColors.secondaryText).frame(width: contentWidth * ProgramHeroLayout.descriptionFraction(width: width, bodySize: bodySize), alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                    }
                    Spacer(minLength: 10)
                    HStack(alignment: .center, spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar").font(.system(size: 16)).foregroundStyle(AppColors.accent)
                                Text(LanguageManager.t("programs.daysPerWeek", ["days": "\(program.workouts.filter { !$0.exercises.isEmpty }.count)"]))
                                    .font(.system(size: daysSize, weight: .semibold)).foregroundStyle(AppColors.accent)
                            }
                            Text(LanguageManager.t("programs.counts", [
                                "workouts": program.workouts.count,
                                "exercises": program.workouts.reduce(0) { $0 + $1.exercises.count }
                            ]))
                            .font(.system(size: countsSize))
                            .foregroundStyle(AppColors.muted)
                        }
                        Spacer()
                    }.frame(minHeight: 40)
                }.padding(16).frame(width: width, height: height, alignment: .topLeading).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityIdentifier("program-card-\(program.id)")
                .accessibilityAddTraits(isActive ? [.isSelected] : [])

            Button(action: onSelect) {
                Text(LanguageManager.t(isActive ? "programs.applied" : "programs.apply"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isActive ? AppColors.accent : AppColors.todaySelectionText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(isActive ? AppColors.positiveBg : AppColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isActive ? AppColors.accent.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("program-apply-\(program.id)")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(16)

            if menuVisible {
                Color.black.opacity(0.001)
                    .frame(width: width, height: height)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        closeMenu()
                    }
            }

            Button(action: toggleMenu) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                    .frame(width: 38, height: 38)
                    .background(AppColors.surfaceRaised.opacity(0.95), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(LanguageManager.t("programs.more")) \(program.displayName)")
            .padding(8)

            if menuVisible {
                VStack(spacing: 0) {
                    Button(action: {
                        closeMenu()
                        onEdit()
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.secondaryText)
                                .frame(width: 18, alignment: .center)
                            Text(LanguageManager.t("programs.edit"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppColors.text)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if let onShare {
                        Rectangle()
                            .fill(AppColors.border.opacity(0.6))
                            .frame(height: 1)
                            .padding(.horizontal, 8)

                        Button(action: {
                            closeMenu()
                            onShare()
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppColors.secondaryText)
                                    .frame(width: 18, alignment: .center)
                                Text(LanguageManager.t("programs.share"))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(AppColors.text)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    if let onDelete {
                        Rectangle()
                            .fill(AppColors.border.opacity(0.6))
                            .frame(height: 1)
                            .padding(.horizontal, 8)

                        Button(action: {
                            closeMenu()
                            onDelete()
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "trash")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppColors.danger)
                                    .frame(width: 18, alignment: .center)
                                Text(LanguageManager.t("modal.delete"))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(AppColors.danger)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                .frame(width: 148)
                .background(AppColors.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppColors.border, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.45), radius: 12, x: 0, y: 6)
                .padding(.top, 56)
                .padding(.trailing, 12)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.85, anchor: .topTrailing).combined(with: .opacity),
                        removal: .scale(scale: 0.85, anchor: .topTrailing).combined(with: .opacity)
                    )
                )
            }
        }
        .frame(width: width, height: height).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(isActive ? AppColors.accent : AppColors.border, lineWidth: isActive ? 2 : 1))
    }
}
