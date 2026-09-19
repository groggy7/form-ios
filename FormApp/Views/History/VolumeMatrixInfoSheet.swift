import SwiftUI

private struct ZoneInfoItem: Identifiable {
    let id: String
    let zone: VolumeZone
    let rangeKey: String
    let detailKey: String
}

public struct VolumeMatrixInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var language = LanguageManager.shared

    private let zoneItems: [ZoneInfoItem] = [
        ZoneInfoItem(id: "underMev", zone: .underMev, rangeKey: "matrix.info.rangeUnderMev", detailKey: "matrix.info.zoneUnderMevDetail"),
        ZoneInfoItem(id: "progressive", zone: .progressive, rangeKey: "matrix.info.rangeProgressive", detailKey: "matrix.info.zoneProgressiveDetail"),
        ZoneInfoItem(id: "optimalMav", zone: .optimalMav, rangeKey: "matrix.info.rangeOptimalMav", detailKey: "matrix.info.zoneOptimalMavDetail"),
        ZoneInfoItem(id: "highFatigue", zone: .highFatigue, rangeKey: "matrix.info.rangeHighFatigue", detailKey: "matrix.info.zoneHighFatigueDetail"),
        ZoneInfoItem(id: "overMrv", zone: .overMrv, rangeKey: "matrix.info.rangeOverMrv", detailKey: "matrix.info.zoneOverMrvDetail")
    ]

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    overviewSection
                    calculationSection
                    zonesSection
                    tipSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(LanguageManager.t("matrix.info.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(AppColors.muted)
                    }
                }
            }
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LanguageManager.t("matrix.info.overviewTitle"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppColors.text)
            Text(LanguageManager.t("matrix.info.overviewText"))
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundColor(AppColors.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surfaceRaised)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
        .cornerRadius(16)
    }

    private var calculationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(LanguageManager.t("matrix.info.calculationTitle"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppColors.text)

            // Direct Sets
            HStack(alignment: .top, spacing: 12) {
                Text("1.0×")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppColors.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AppColors.positiveBg)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppColors.accent.opacity(0.5), lineWidth: 1))
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(LanguageManager.t("matrix.info.directSetsTitle"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.text)
                    Text(LanguageManager.t("matrix.info.directSetsDesc"))
                        .font(.system(size: 12))
                        .lineSpacing(2)
                        .foregroundColor(AppColors.secondaryText)
                }
            }

            Divider().background(AppColors.border)

            // Indirect Sets
            HStack(alignment: .top, spacing: 12) {
                Text("0.5×")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppColors.purple)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AppColors.purpleBg)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppColors.purple.opacity(0.5), lineWidth: 1))
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(LanguageManager.t("matrix.info.indirectSetsTitle"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.text)
                    Text(LanguageManager.t("matrix.info.indirectSetsDesc"))
                        .font(.system(size: 12))
                        .lineSpacing(2)
                        .foregroundColor(AppColors.secondaryText)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surfaceRaised)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
        .cornerRadius(16)
    }

    private var zonesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LanguageManager.t("matrix.info.zonesTitle"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppColors.text)
                Text(LanguageManager.t("matrix.info.zonesSubtitle"))
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.muted)
            }

            ForEach(Array(zoneItems.enumerated()), id: \.element.id) { idx, item in
                if idx > 0 {
                    Divider().background(AppColors.border.opacity(0.7))
                }
                zoneRowView(item: item)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surfaceRaised)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
        .cornerRadius(16)
    }

    private func zoneRowView(item: ZoneInfoItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(item.zone.color)
                        .frame(width: 9, height: 9)
                    Text(LanguageManager.t(item.zone.titleKey))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.text)
                }
                Spacer()
                Text(LanguageManager.t(item.rangeKey))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(item.zone.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(item.zone.badgeBgColor)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(item.zone.color.opacity(0.4), lineWidth: 1))
                    .cornerRadius(6)
            }

            Text(LanguageManager.t(item.detailKey))
                .font(.system(size: 12))
                .lineSpacing(2)
                .foregroundColor(AppColors.secondaryText)
        }
    }

    private var tipSection: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 16))
                .foregroundColor(AppColors.accent)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(LanguageManager.t("matrix.info.tipTitle"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColors.accent)
                Text(LanguageManager.t("matrix.info.tipText"))
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .foregroundColor(AppColors.secondaryText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surfaceRaised)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.accent.opacity(0.35), lineWidth: 1))
        .cornerRadius(16)
    }
}
