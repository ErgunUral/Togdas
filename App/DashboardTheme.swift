import SwiftUI

enum ToggThemeStyle: String, CaseIterable, Identifiable, Hashable {
    case togg, ocean, graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .togg: return "Togg Gece"
        case .ocean: return "Okyanus"
        case .graphite: return "Grafit / Amber"
        }
    }

    var backgroundColor: Color {
        switch self {
        case .togg: return Color(hex: 0x0B121E)
        case .ocean: return Color(hex: 0x071725)
        case .graphite: return Color(hex: 0x111416)
        }
    }

    var surfaceColor: Color {
        switch self {
        case .togg: return Color(hex: 0x131C2E)
        case .ocean: return Color(hex: 0x102638)
        case .graphite: return Color(hex: 0x1B2023)
        }
    }

    var surfaceVariantColor: Color {
        switch self {
        case .togg: return Color(hex: 0x1C273C)
        case .ocean: return Color(hex: 0x18384D)
        case .graphite: return Color(hex: 0x282F33)
        }
    }

    var outlineColor: Color {
        switch self {
        case .togg: return Color(hex: 0x2E3D58)
        case .ocean: return Color(hex: 0x2C536A)
        case .graphite: return Color(hex: 0x41494D)
        }
    }

    var accentColor: Color {
        switch self {
        case .togg: return Color(hex: 0x00D2C8)
        case .ocean: return Color(hex: 0x42D5F5)
        case .graphite: return Color(hex: 0xFFB547)
        }
    }

    var accentContainerColor: Color {
        switch self {
        case .togg: return Color(hex: 0x004F4D)
        case .ocean: return Color(hex: 0x124A5B)
        case .graphite: return Color(hex: 0x5B3E16)
        }
    }
}

enum DashboardLayoutStyle: String, CaseIterable, Identifiable, Hashable {
    case classic, minimal, sport, technical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Klasik"
        case .minimal: return "Minimal"
        case .sport: return "Sportif"
        case .technical: return "Teknik"
        }
    }

    var subtitle: String {
        switch self {
        case .classic: return "Tüm kartlar"
        case .minimal: return "Özet ve hızlı erişim"
        case .sport: return "Kontroller önde"
        case .technical: return "Tanı ve telemetri önde"
        }
    }
}

/// Tema paletleri koyu tutulur; kartlardaki beyaz metinlerin kontrastı korunur.
enum ToggTheme {
    private static var selected: ToggThemeStyle {
        guard let raw = UserDefaults.standard.string(forKey: "toqdas.theme"),
              let style = ToggThemeStyle(rawValue: raw) else { return .togg }
        return style
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
        case .togg: return Color(hex: 0x9AA7BD)
        case .ocean: return Color(hex: 0x9AB7C9)
        case .graphite: return Color(hex: 0xB1B9BC)
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
