// Hızlı işlem düğmesi (kilit/aç/bagaj/yakınlık kısayolu)
// DashboardView'dan ayrıldı (2026-11-12) — yalnız taşıma; davranış değişikliği yok.

import SwiftUI

// MARK: - Hızlı işlem düğmesi

struct QuickActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let active: Bool
    let activeColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(active ? activeColor : ToggTheme.outline.opacity(0.3))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundStyle(active ? .black : .white)
                }
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(active ? activeColor : .white)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(ToggTheme.muted)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(active ? activeColor.opacity(0.18) : ToggTheme.surfaceVariant)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(active ? "\(subtitle), açık" : subtitle)
        .accessibilityAddTraits(.isButton)
    }
}
