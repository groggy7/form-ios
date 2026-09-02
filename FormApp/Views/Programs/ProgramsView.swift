import SwiftUI

public struct ProgramsView: View {
    @ObservedObject var store: AppStore
    var onDismiss: () -> Void

    @State private var editingProgram: Program? = nil
    @State private var isCreatingNew: Bool = false
    @State private var showFileImporter: Bool = false

    public init(store: AppStore, onDismiss: @escaping () -> Void) {
        self.store = store
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Action Buttons: New Program and Import JSON (same height!)
                    HStack(spacing: 12) {
                        Button(action: { isCreatingNew = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .bold))
                                Text(LanguageManager.t("programs.new"))
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(AppColors.accent)
                            .foregroundColor(AppColors.todaySelectionText)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)

                        Button(action: { showFileImporter = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 14, weight: .semibold))
                                Text(LanguageManager.t("programs.importJson"))
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(AppColors.surface)
                            .foregroundColor(AppColors.text)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                    // Programs List
                    VStack(spacing: 12) {
                        ForEach(store.state.programs) { program in
                            let isActive = program.id == store.state.activeProgramId

                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(program.name)
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundColor(AppColors.text)

                                        if !program.description.isEmpty {
                                            Text(program.description)
                                                .font(.system(size: 13))
                                                .foregroundColor(AppColors.muted)
                                                .lineLimit(2)
                                        }
                                    }

                                    Spacer()

                                    if isActive {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(AppColors.positive)
                                    }
                                }

                                HStack {
                                    Text("\(program.workouts.filter { !$0.exercises.isEmpty }.count) days/week")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(AppColors.accent)

                                    Spacer()

                                    Button(action: { editingProgram = program }) {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 14))
                                            .foregroundColor(AppColors.muted)
                                            .padding(8)
                                    }
                                    .buttonStyle(.plain)

                                    if !isActive {
                                        Button(action: {
                                            store.switchProgram(to: program.id)
                                            onDismiss()
                                        }) {
                                            Text(LanguageManager.t("programs.apply"))
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundColor(AppColors.todaySelectionText)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 7)
                                                .background(AppColors.accent)
                                                .cornerRadius(8)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(AppColors.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(isActive ? AppColors.accent : AppColors.border, lineWidth: isActive ? 2 : 1)
                                    )
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .background(AppColors.background)
            .navigationTitle(LanguageManager.t("programs.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(AppColors.muted)
                    }
                }
            }
            .sheet(item: $editingProgram) { prog in
                ProgramBuilderView(store: store, program: prog) {
                    editingProgram = nil
                }
            }
            .sheet(isPresented: $isCreatingNew) {
                ProgramBuilderView(store: store) {
                    isCreatingNew = false
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first, url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        if let data = try? Data(contentsOf: url) {
                            _ = try? store.importProgram(jsonData: data)
                        }
                    }
                case .failure(let err):
                    print("Import error: \(err)")
                }
            }
        }
    }
}
