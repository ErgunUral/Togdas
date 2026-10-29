import AppIntents
import SwiftUI

/// Siri/Shortcuts ile tetiklenen araç komutları. Komutlar uygulama içi BLE
/// hattına URL üzerinden iletilir; READY ve taze telemetri koşulu yine geçerlidir.
struct LockCarIntent: AppIntent {
    static var title: LocalizedStringResource = "Arabamı kilitle"
    static var description = IntentDescription("Toqdas ile aracı kilitler.")
    static var openAppWhenRun: Bool = true

    @Environment(\.openURL) private var openURL

    func perform() async throws -> some IntentResult {
        if let url = URL(string: "toqdas://command?action=lock") {
            await openURL(url)
        }
        return .result()
    }
}

struct UnlockCarIntent: AppIntent {
    static var title: LocalizedStringResource = "Arabamı aç"
    static var description = IntentDescription("Toqdas ile aracı kilitlerini açar.")
    static var openAppWhenRun: Bool = true

    @Environment(\.openURL) private var openURL

    func perform() async throws -> some IntentResult {
        if let url = URL(string: "toqdas://command?action=unlock") {
            await openURL(url)
        }
        return .result()
    }
}

struct TrunkOpenIntent: AppIntent {
    static var title: LocalizedStringResource = "Bagajı aç"
    static var description = IntentDescription("Toqdas ile bagajı açar.")
    static var openAppWhenRun: Bool = true

    @Environment(\.openURL) private var openURL

    func perform() async throws -> some IntentResult {
        if let url = URL(string: "toqdas://command?action=trunkOpen") {
            await openURL(url)
        }
        return .result()
    }
}

struct ToqdasShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LockCarIntent(), phrases: ["\(.applicationName) arabamı kilitle"],
                    shortTitle: "Kilitle", systemImageName: "lock.fill")
        AppShortcut(intent: UnlockCarIntent(), phrases: ["\(.applicationName) arabamı aç"],
                    shortTitle: "Aç", systemImageName: "lock.open.fill")
        AppShortcut(intent: TrunkOpenIntent(), phrases: ["\(.applicationName) bagajı aç"],
                    shortTitle: "Bagaj", systemImageName: "car.side")
    }
}