import SwiftUI

// MARK: - Kurumsal tasarım sistemi
//
// Neden gerekli: kart zemini, köşe yarıçapı ve boşluklar her görünümde elle
// yazılıyordu (`RoundedRectangle(cornerRadius: 16)` vb.) → ekranlar arası
// tutarsızlık ve kurumsal kimliğin dağılması. Bu dosya **yalnız görsel
// dili** tanımlar: iş mantığı, komut veya ağ erişimi içermez.
//
// Kasıtlı sınırlar:
// - Metin ölçeği `ToggText`te kalır (Dynamic Type davranışı değişmesin).
// - Renkler `ToggTheme`ten çözülür (tek palet kaynağı; tema göçü orada).
// - Bileşenler veri almaz; durum metni çağıranda kurulur (dürüstlük kuralı
//   UI bileşeninde değil, veriyi üreten politikada).

// MARK: - Token'lar

enum DSSpace {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum DSRadius {
    static let row: CGFloat = 12
    static let card: CGFloat = 16
    static let sheet: CGFloat = 20
}

enum DSElevation {
    /// Sayfa zemini üstündeki düz kart.
    case surface
    /// Öne çıkan kart (hero, öncelik).
    case raised
    /// Modal/sheet.
    case modal
}

enum DSColor {
    static var accent: Color { ToggTheme.teal }
    static var accentSoft: Color { ToggTheme.tealContainer }
    static var background: Color { ToggTheme.background }
    static var surface: Color { ToggTheme.surface }
    static var surfaceVariant: Color { ToggTheme.surfaceVariant }
    static var outline: Color { ToggTheme.outline }
    static var muted: Color { ToggTheme.muted }
    static var positive: Color { ToggTheme.green }
    static var warning: Color { ToggTheme.orange }
    static var negative: Color { ToggTheme.red }
    static var info: Color { ToggTheme.blue }
}

extension View {
    /// Tek kart zemini: yüzey + 1px çizgi + (gerekirse) yumuşak gölge.
    func dsCard(_ elevation: DSElevation = .surface,
                radius: CGFloat = DSRadius.card) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(elevation == .surface ? DSColor.surface : DSColor.surfaceVariant)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(DSColor.outline.opacity(elevation == .surface ? 0.55 : 0.8),
                                lineWidth: 1)
                )
                .shadow(color: .black.opacity(elevation == .modal ? 0.35 : 0.12),
                        radius: elevation == .surface ? 0 : 12,
                        y: elevation == .surface ? 0 : 6)
        )
    }

    /// Bölüm içi sabit dikey ritim.
    func dsSectionSpacing() -> some View {
        padding(.bottom, DSSpace.md)
    }
}

// MARK: - Durum dili (tek kelime, tek renk)

/// Dürüstlük sözleşmesinin görsel karşılığı: her ekranda aynı dört durum.
enum DSStatus {
    /// İmzalı telemetri taze.
    case fresh
    /// Veri bekleniyor (normal dönem arası).
    case waiting
    /// Veri eski.
    case stale
    /// Komut sonucu doğrulanamadı.
    case unverified
    /// Bağlantı yok / iPhone arka planda.
    case offline
    /// Kritik eşik (12 V, lastik vb.).
    case critical
    /// Şarj oturumu sürüyor.
    case charging
    /// Şarj oturumu yok (veri var).
    case idle

    var text: String {
        switch self {
        case .fresh: return "Güncel"
        case .waiting: return "Bekleniyor"
        case .stale: return "Eski veri"
        case .unverified: return "Doğrulanamadı"
        case .offline: return "Bağlantı yok"
        case .critical: return "Kritik"
        case .charging: return "Şarj sürüyor"
        case .idle: return "Şarj yok"
        }
    }

    var color: Color {
        switch self {
        case .fresh: return DSColor.positive
        case .waiting: return DSColor.muted
        case .stale, .unverified: return DSColor.warning
        case .offline: return DSColor.muted
        case .critical: return DSColor.negative
        case .charging: return DSColor.accent
        case .idle: return DSColor.muted
        }
    }

    var icon: String {
        switch self {
        case .fresh: return "checkmark.circle.fill"
        case .waiting: return "clock"
        case .stale: return "clock.badge.exclamationmark"
        case .unverified: return "questionmark.circle"
        case .offline: return "wifi.slash"
        case .critical: return "exclamationmark.triangle.fill"
        case .charging: return "bolt.fill"
        case .idle: return "bolt.slash"
        }
    }
}

struct StatusPill: View {
    let status: DSStatus
    /// Durum metnini bağlama göre daraltmak için (ör. "3 dk önce").
    var detail: String?

    var body: some View {
        HStack(spacing: DSSpace.xxs) {
            Image(systemName: status.icon)
                .font(.system(size: 10, weight: .semibold))
                .accessibilityHidden(true)
            Text(detail ?? status.text)
                .font(ToggTheme.text(.micro, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, DSSpace.xs)
        .padding(.vertical, DSSpace.xxs + 1)
        .background(Capsule().fill(status.color.opacity(0.14)))
        .overlay(Capsule().stroke(status.color.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Durum: \(detail ?? status.text)")
    }
}

// MARK: - Başlıklar

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpace.xs) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ToggTheme.text(.lead, weight: .bold))
                    .foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(ToggTheme.text(.micro))
                        .foregroundStyle(DSColor.muted)
                }
            }
            Spacer(minLength: DSSpace.xs)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(ToggTheme.text(.micro, weight: .bold))
                    .foregroundStyle(DSColor.accent)
                    .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Eylem karosu (2 sütun ızgara)

struct ActionTile: View {
    let title: String
    let subtitle: String
    let icon: String
    var active: Bool = false
    var tint: Color = DSColor.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DSSpace.xs) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(active ? tint.opacity(0.18) : DSColor.surfaceVariant)
                            .frame(width: 36, height: 36)
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(active ? tint : .white)
                    }
                    Spacer(minLength: 0)
                    if active {
                        Circle().fill(tint).frame(width: 6, height: 6)
                    }
                }
                Text(title)
                    .font(ToggTheme.text(.body, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(subtitle)
                    .font(ToggTheme.text(.micro))
                    .foregroundStyle(DSColor.muted)
                    .lineLimit(1)
            }
            .padding(DSSpace.sm)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .dsCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(subtitle): \(title)")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Metrik ve veri satırı

struct MetricCell: View {
    let label: String
    let value: String
    let icon: String
    var tint: Color = DSColor.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: DSSpace.xxs) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(label)
                    .font(ToggTheme.text(.micro))
                    .foregroundStyle(DSColor.muted)
                    .lineLimit(1)
            }
            Text(value)
                .font(ToggTheme.text(.body, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct DataRow: View {
    let label: String
    let value: String
    var detail: String?
    var tint: Color = .white

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpace.xs) {
            Text(label)
                .font(ToggTheme.text(.caption))
                .foregroundStyle(DSColor.muted)
            Spacer(minLength: DSSpace.xs)
            VStack(alignment: .trailing, spacing: 1) {
                Text(value)
                    .font(ToggTheme.text(.body, weight: .bold).monospacedDigit())
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let detail {
                    Text(detail)
                        .font(ToggTheme.text(.micro))
                        .foregroundStyle(DSColor.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Durum şeridi (hero)

struct HeroMetric: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let icon: String
    var tint: Color = DSColor.accent
}

/// Ekranın tek "durum" yüzeyi: başlık, durum rozeti, metrikler ve birincil
/// eylem. Değerler çağırandan gelir; burada hiçbir iddia üretilmez.
struct StatusHero: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let status: DSStatus
    var statusDetail: String? = nil
    var metrics: [HeroMetric] = []
    var footer: String?
    var primaryTitle: String?
    var primaryIcon: String = "arrow.clockwise"
    var primaryAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(eyebrow)
                        .font(ToggTheme.text(.micro, weight: .bold))
                        .foregroundStyle(DSColor.muted)
                    Text(title)
                        .font(ToggTheme.text(.display, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text(subtitle)
                        .font(ToggTheme.text(.caption))
                        .foregroundStyle(DSColor.muted)
                }
                Spacer(minLength: DSSpace.xs)
                StatusPill(status: status, detail: statusDetail)
            }

            if !metrics.isEmpty {
                Divider().overlay(DSColor.outline.opacity(0.6))
                HStack(alignment: .top, spacing: DSSpace.sm) {
                    ForEach(metrics) { metric in
                        MetricCell(label: metric.label, value: metric.value,
                                   icon: metric.icon, tint: metric.tint)
                    }
                }
            }

            if let primaryTitle, let primaryAction {
                Button(action: primaryAction) {
                    HStack(spacing: DSSpace.xs) {
                        Image(systemName: primaryIcon)
                        Text(primaryTitle)
                    }
                    .font(ToggTheme.text(.body, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: DSRadius.row, style: .continuous)
                        .fill(DSColor.accent))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(primaryTitle)
            }

            if let footer {
                Text(footer)
                    .font(ToggTheme.text(.micro))
                    .foregroundStyle(DSColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DSSpace.md)
        .dsCard(.raised)
    }
}

// MARK: - Öncelik kartı ("şimdi ne önemli")

struct PriorityCard: View {
    let title: String
    let detail: String
    let icon: String
    let severity: DSStatus
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: DSSpace.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: DSRadius.row, style: .continuous)
                    .fill(severity.color.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(severity.color)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ToggTheme.text(.body, weight: .bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(ToggTheme.text(.micro))
                    .foregroundStyle(DSColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DSSpace.xxs)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(ToggTheme.text(.micro, weight: .bold))
                    .foregroundStyle(DSColor.accent)
                    .buttonStyle(.plain)
            }
        }
        .padding(DSSpace.sm)
        .dsCard()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Boş durum / iskelet / bildirim

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    /// Eylem birincil mi (dolu düğme) — boş durumun tek çıkışı olduğunda.
    var prominentAction: Bool = false

    var body: some View {
        VStack(spacing: DSSpace.xs) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(DSColor.muted)
                .accessibilityHidden(true)
            Text(title)
                .font(ToggTheme.text(.body, weight: .bold))
                .foregroundStyle(.white)
            Text(message)
                .font(ToggTheme.text(.micro))
                .foregroundStyle(DSColor.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                if prominentAction {
                    Button(action: action) {
                        Text(actionTitle)
                            .font(ToggTheme.text(.body, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: DSRadius.row,
                                                         style: .continuous)
                                .fill(DSColor.accent))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, DSSpace.xxs)
                    .accessibilityIdentifier("emptyState.action")
                } else {
                    Button(actionTitle, action: action)
                        .font(ToggTheme.text(.caption, weight: .bold))
                        .foregroundStyle(DSColor.accent)
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                }
            }
        }
        .padding(DSSpace.lg)
        .frame(maxWidth: .infinity)
        .dsCard()
    }
}

/// Yükleniyor iskeleti: sayfa boş görünmesin, düzen zıplamasın.
struct SkeletonRow: View {
    var height: CGFloat = 14

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(DSColor.surfaceVariant)
            .frame(height: height)
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)
    }
}

struct ToastBanner: View {
    let text: String
    var status: DSStatus = .fresh
    var onClose: (() -> Void)?

    var body: some View {
        HStack(spacing: DSSpace.xs) {
            Image(systemName: status.icon)
                .foregroundStyle(status.color)
                .accessibilityHidden(true)
            Text(text)
                .font(ToggTheme.text(.caption))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DSColor.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Kapat")
            }
        }
        .padding(DSSpace.sm)
        .dsCard()
    }
}

/// Sheet iskeleti: başlık + içerik + dürüst dipnot (tek yerden).
struct SheetShell<Content: View>: View {
    let title: String
    var subtitle: String?
    var footnote: String?
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpace.md) {
                    if let subtitle {
                        Text(subtitle)
                            .font(ToggTheme.text(.caption))
                            .foregroundStyle(DSColor.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    content
                    if let footnote {
                        Text(footnote)
                            .font(ToggTheme.text(.micro))
                            .foregroundStyle(DSColor.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, DSSpace.xxs)
                    }
                }
                .padding(DSSpace.md)
            }
            .background(DSColor.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Hareket (Reduce Motion uyumlu)

extension View {
    /// Kart girişi: Reduce Motion açıksa animasyon yok (erişilebilirlik).
    func dsAppear(index: Int, reduceMotion: Bool) -> some View {
        modifier(DSAppearModifier(index: index, reduceMotion: reduceMotion))
    }
}

private struct DSAppearModifier: ViewModifier {
    let index: Int
    let reduceMotion: Bool
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion || shown ? 1 : 0)
            .offset(y: reduceMotion || shown ? 0 : 8)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.22).delay(Double(min(index, 6)) * 0.04)) {
                    shown = true
                }
            }
    }
}
