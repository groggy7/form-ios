import SwiftUI

/// The binding writes through immediately, including when the app leaves the foreground.
struct NoteField: View {
    let titleKey: String
    @Binding var text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { expanded.toggle() } label: {
                HStack {
                    Text(LanguageManager.t(titleKey)).font(.app(size: 13))
                    Spacer(minLength: 8)
                    Text(LanguageManager.t(expanded ? "common.done" : text.isEmpty ? "notes.add" : "notes.edit"))
                        .font(.app(size: 12))
                }
                .foregroundStyle(AppColors.secondaryText)
                .frame(minHeight: 48).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("\(titleKey)-toggle")
            if expanded {
                TextField(LanguageManager.t(titleKey), text: $text, axis: .vertical)
                    .lineLimit(2...6).font(.app(size: 14)).foregroundStyle(AppColors.text)
                    .padding(12).background(AppColors.surfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("\(titleKey)-input")
                    .onChange(of: text) { _, value in if value.count > 10_000 { text = String(value.prefix(10_000)) } }
                    .padding(.bottom, 12)
            } else if !text.isEmpty {
                Text(text).font(.app(size: 14)).foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled).padding(.bottom, 12)
            }
        }
        .padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
    }
}

struct SavedNote: View {
    let text: String?
    var body: some View {
        if let text, !text.isEmpty {
            Text(text).font(.app(size: 14)).foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }
}
