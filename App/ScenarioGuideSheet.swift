import SwiftUI

/// Senaryolar rehberi — uygulamanın tüm kullanıcı senaryolarını, canlı
/// durum rozetleriyle gösteren sheet. İçerik `ScenarioCatalog`'tan gelir
/// (Core, saf model); bu dosya yalnız sunumdur.
///
/// Uyum: U1 `ToggText` semantik stiller (sabit `.system(size:)` yok),
/// U2 `VisualTone`/`ToggTheme.color(for:)`, U3 VoiceOver etiketleri.
/// Etkileşimli öğe yalnız kapatma düğmesidir (toolbar standart hedefi).
struct ScenarioGuideSheet: View {
    /// Açılışta odaklanılacak bölüm (örn. yakınlık kartından açılışta `.proximity`).
    var initialSection: ScenarioSection?
    var live: ScenarioLiveStatus

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        liveStrip
                        ForEach(ScenarioCatalog.groups) { group in
                            groupCard(group)
                        }
                        footerNote
                    }
                    .padding(16)
                }
                .background(ToggTheme.background.ignoresSafeArea())
                .onAppear {
                    guard let section = initialSection else { return }
                    proxy.scrollTo(section.id, anchor: .top)
                }
            }
            .navigationTitle("Senaryolar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                        .accessibilityIdentifier("guide.close")
                }
            }
        }
        .tint(ToggTheme.teal)
    }

    // MARK: - Canlı durum şeridi

    private var liveStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Anlık durum")
                .font(ToggTheme.text(.caption, weight: .bold))
                .foregroundStyle(ToggTheme.muted)
            ForEach(live.badges) { badge in
                HStack(spacing: 10) {
                    Circle()
                        .fill(ToggTheme.color(for: badge.tone))
                        .frame(width: 8, height: 8)
                    Text(badge.title)
                        .font(ToggTheme.text(.caption, weight: .semibold))
                        .foregroundStyle(ToggTheme.muted)
                    Spacer()
                    Text(badge.value)
                        .font(ToggTheme.text(.caption, weight: .bold))
                        .foregroundStyle(ToggTheme.color(for: badge.tone))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(badge.title): \(badge.value)")
            }
        }
        .padding(14)
        .toggCardBackground()
    }

    // MARK: - Bölüm kartı

    private func groupCard(_ group: ScenarioGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: group.section.icon)
                    .font(ToggTheme.text(.lead, weight: .bold))
                    .foregroundStyle(ToggTheme.teal)
                Text(group.section.title)
                    .font(ToggTheme.text(.lead, weight: .bold))
                    .foregroundStyle(.white)
            }
            .accessibilityElement(children: .combine)

            Text(group.section.summary)
                .font(ToggTheme.text(.caption))
                .foregroundStyle(ToggTheme.muted)

            ForEach(group.items) { item in
                itemRows(item)
            }
        }
        .padding(16)
        .toggCardBackground()
        .id(group.id)
    }

    private func itemRows(_ item: ScenarioItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .font(ToggTheme.text(.body, weight: .bold))
                .foregroundStyle(.white)
            row(label: "Ne olur", color: ToggTheme.muted, text: item.effect)
            row(label: "Şartın", color: ToggTheme.teal, text: item.requirement)
            row(label: "Aksarsa", color: ToggTheme.color(for: .warning), text: item.onBreak)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title). Ne olur: \(item.effect). Şartın: \(item.requirement). Aksarsa: \(item.onBreak)")
    }

    private func row(label: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(ToggTheme.text(.micro, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 58, alignment: .leading)
            Text(text)
                .font(ToggTheme.text(.caption))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private var footerNote: some View {
        Text("Bu rehber uygulamanın gerçek davranışını anlatır; durum rozetleri anlık koşulu gösterir. Komut gönderimi her zaman aynı güven kapısından geçer.")
            .font(ToggTheme.text(.micro))
            .foregroundStyle(ToggTheme.muted)
            .padding(.top, 2)
    }
}
