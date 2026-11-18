import SwiftUI

enum ToggThemeStyle: String, CaseIterable, Identifiable, Hashable {
    /// Kurumsal kimlik: tek vurgu rengi, nötr yüzeyler.
    case corporate
    /// Erişilebilirlik: yüksek kontrast (WCAG AA üstü).
    case contrast
    /// Eski paletler (göç için korunur; seçicide görünmez).
    case togg, ocean, graphite

    var id: String { rawValue }

    /// Seçicide yalnız kurumsal iki palet görünür.
    static var selectable: [ToggThemeStyle] { [.corporate, .contrast] }

    var title: String {
        switch self {
        case .corporate: return "Kurumsal"
        case .contrast: return "Yüksek Kontrast"
        case .togg: return "Togg Gece"
        case .ocean: return "Okyanus"
        case .graphite: return "Grafit / Amber"
        }
    }

    var subtitle: String? {
        switch self {
        case .corporate: return "Tek vurgu rengi, nötr yüzeyler"
        case .contrast: return "Daha yüksek kontrast"
        default: return nil
        }
    }

    var backgroundColor: Color {
        switch self {
        case .corporate: return Color(hex: 0x0A0F14)
        case .contrast: return Color(hex: 0x000000)
        case .togg: return Color(hex: 0x0B121E)
        case .ocean: return Color(hex: 0x071725)
        case .graphite: return Color(hex: 0x111416)
        }
    }

    var surfaceColor: Color {
        switch self {
        case .corporate: return Color(hex: 0x121A21)
        case .contrast: return Color(hex: 0x0F0F0F)
        case .togg: return Color(hex: 0x131C2E)
        case .ocean: return Color(hex: 0x102638)
        case .graphite: return Color(hex: 0x1B2023)
        }
    }

    var surfaceVariantColor: Color {
        switch self {
        case .corporate: return Color(hex: 0x1A242D)
        case .contrast: return Color(hex: 0x1C1C1C)
        case .togg: return Color(hex: 0x1C273C)
        case .ocean: return Color(hex: 0x18384D)
        case .graphite: return Color(hex: 0x282F33)
        }
    }

    var outlineColor: Color {
        switch self {
        case .corporate: return Color(hex: 0x2A3844)
        case .contrast: return Color(hex: 0x6E6E6E)
        case .togg: return Color(hex: 0x2E3D58)
        case .ocean: return Color(hex: 0x2C536A)
        case .graphite: return Color(hex: 0x41494D)
        }
    }

    var accentColor: Color {
        switch self {
        case .corporate: return Color(hex: 0x00D2C8)
        case .contrast: return Color(hex: 0x00F0E6)
        case .togg: return Color(hex: 0x00D2C8)
        case .ocean: return Color(hex: 0x42D5F5)
        case .graphite: return Color(hex: 0xFFB547)
        }
    }

    var accentContainerColor: Color {
        switch self {
        case .corporate: return Color(hex: 0x0B3B3A)
        case .contrast: return Color(hex: 0x00332F)
        case .togg: return Color(hex: 0x004F4D)
        case .ocean: return Color(hex: 0x124A5B)
        case .graphite: return Color(hex: 0x5B3E16)
        }
    }
}

/// Tema paletleri koyu tutulur; kartlardaki beyaz metinlerin kontrastı korunur.
/// Pano yerleşimi: F1'de "yoğunluk + öncelik" modeline göç edecek.
/// Eski ham değerler korunur (kayıtlı tercih sessizce sıfırlanmasın).
enum DashboardLayoutStyle: String, CaseIterable, Identifiable, Hashable {
    case classic, minimal, sport, technical
    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Dengeli"
        case .minimal: return "Sade"
        case .sport: return "Kontrol önde"
        case .technical: return "Teknik önde"
        }
    }

    var subtitle: String {
        switch self {
        case .classic: return "Özet + kontroller"
        case .minimal: return "Yalnız özet"
        case .sport: return "Hızlı eylemler üstte"
        case .technical: return "Telemetri üstte"
        }
    }
}

enum ToggTheme {
    /// Eski palet seçimleri (togg/ocean/graphite) kurumsal kimliğe **göç
    /// eder**; kayıt silinmez, böylece geri dönüş yolu kapanmaz.
    private static var selected: ToggThemeStyle {
        guard let raw = UserDefaults.standard.string(forKey: StorageKeys.theme),
              let style = ToggThemeStyle(rawValue: raw) else { return .corporate }
        switch style {
        case .corporate, .contrast: return style
        case .togg, .ocean, .graphite: return .corporate
        }
    }

    static var background: Color { selected.backgroundColor }
    static var surface: Color { selected.surfaceColor }
    static var surfaceVariant: Color { selected.surfaceVariantColor }
    static var outline: Color { selected.outlineColor }
    static var teal: Color { selected.accentColor }
    static var tealContainer: Color { selected.accentContainerColor }
    static let blue = Color(hex: 0x00A3FF)
    static let green = Color(hex: 0x00E676)
    static let orange = Color(hex: 0xFF9100)
    static let red = Color(hex: 0xFF3D00)
    static let pink = Color(hex: 0xFF5252)
    static let cyan = Color(hex: 0x00E5FF)
    static let yellow = Color(hex: 0xFFD600)
    static var muted: Color {
        switch selected {
        case .corporate, .togg: return Color(hex: 0x9AA7BD)
        case .contrast: return Color(hex: 0xC8C8C8)
        case .ocean: return Color(hex: 0x9AB7C9)
        case .graphite: return Color(hex: 0xB1B9BC)
        }
    }
}

/// Adlandırılmış metin ölçeği: eskiden `App` genelinde 20'den fazla sabit
/// `.system(size:)` değeri kullanılıyordu (yalnız DashboardView'da 99);
/// bunlar tek ölçek tablosuna taşındı. SwiftUI semantik stil temelli
/// olduğu için Dynamic Type otomatik çalışır; varsayılan boyut eski
/// sabit boyuta en yakın değerdir.
///
/// Kasıtlı sınırlar:
/// - Monospace meta satırları (parmak izi, saat damgası) ölçek tablosuna
///   girmez: sabit boyut kalır, satır hizası kaymasın.
/// - Dashboard kökünde Dynamic Type `xxxLarge` ile sınırlanır: kart
///   düzgünü çok adımlı büyümede taşar; VoiceOver etiketleri telafi eder.
enum ToggText {
    /// 9–10pt → `.caption2` (iOS'un en küçük semantik stili; 12pt taban).
    case micro
    /// 11–12pt → `.footnote` (13pt taban).
    case caption
    /// 13–14pt → `.subheadline` (15pt taban).
    case body
    /// 15–16pt → `.callout` (16pt taban).
    case lead
    /// 17–18pt → `.body` (17pt taban).
    case headline
    /// 20–22pt → `.title3` (20pt taban).
    case title
    /// 24pt+ → `.title2` (22pt taban).
    case display

    var textStyle: Font.TextStyle {
        switch self {
        case .micro: return .caption2
        case .caption: return .footnote
        case .body: return .subheadline
        case .lead: return .callout
        case .headline: return .body
        case .title: return .title3
        case .display: return .title2
        }
    }
}

extension ToggTheme {
    /// Ölçek tablosundan semantik font; ağırlık korunur. `Font.system(_:design:)`
    /// iOS 16.1+ olduğu için tasarım parametresi bilinçli yok (kapsamda
    /// rounded/serif kullanım yok; gerekirse 16.1 guard ile eklenir).
    static func text(_ style: ToggText, weight: Font.Weight = .regular) -> Font {
        Font.system(style.textStyle).weight(weight)
    }

    /// Durum tonu → renk (U2 sözlüğü): yeşil=canlı · turuncu=bekleme/eski ·
    /// pembe=hata · gri=bilgi yok. Widget ve saat aynı tonları kendi
    /// çözücüsüyle kullanır; karar Core'da (VisualTone) tanımlıdır.
    static func color(for tone: VisualTone) -> Color {
        switch tone {
        case .positive: return green
        case .warning: return orange
        case .negative: return pink
        case .neutral: return muted
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: 1
        )
    }

    /// Kart yüzeyi + ince kenarlık.
    func toggCard(_ radius: CGFloat = 28) -> some View {
        self
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(ToggTheme.outline.opacity(0.5), lineWidth: 1)
            )
    }
}

extension View {
    func toggCardBackground(_ radius: CGFloat = 28) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(ToggTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(ToggTheme.outline.opacity(0.5), lineWidth: 1)
                )
        )
    }
}
