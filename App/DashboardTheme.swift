import SwiftUI

/// Togg Trumore arayüz renkleri.
enum ToggTheme {
    static let background = Color(hex: 0x0B121E)
    static let surface = Color(hex: 0x131C2E)
    static let surfaceVariant = Color(hex: 0x1C273C)
    static let outline = Color(hex: 0x2E3D58)
    static let teal = Color(hex: 0x00D2C8)
    static let tealContainer = Color(hex: 0x004F4D)
    static let blue = Color(hex: 0x00A3FF)
    static let green = Color(hex: 0x00E676)
    static let orange = Color(hex: 0xFF9100)
    static let red = Color(hex: 0xFF3D00)
    static let pink = Color(hex: 0xFF5252)
    static let cyan = Color(hex: 0x00E5FF)
    static let yellow = Color(hex: 0xFFD600)
    static let muted = Color(hex: 0x9AA7BD)
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
