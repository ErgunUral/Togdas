import AppIntents
import SwiftUI

/// Siri/Shortcuts ile tetiklenen araç komutları. Komutlar uygulama içi BLE
/// hattına URL üzerinden iletilir; READY ve taze telemetri koşulu yine geçerlidir.
private func openShortcut(_ action: ShortcutAction, openURL: OpenURLAction) async {
    guard let url = ShortcutLink.url(for: action) else { return }
    await openURL(url)
}

struct LockCarIntent: AppIntent {
    static var title: LocalizedStringResource = "Arabamı kilitle"
    static var description = IntentDescription("Toqdas ile aracı kilitler.")
    static var openAppWhenRun: Bool = true

    @Environment(\.openURL) private var openURL

    func perform() async throws -> some IntentResult {
        await openShortcut(.lock, openURL: openURL)
        return .result()
    }
}

struct UnlockCarIntent: AppIntent {
    static var title: LocalizedStringResource = "Arabamı aç"
    static var description = IntentDescription("Toqdas ile aracın kilidini açar.")
    static var openAppWhenRun: Bool = true

    @Environment(\.openURL) private var openURL

    func perform() async throws -> some IntentResult {
        await openShortcut(.unlock, openURL: openURL)
        return .result()
    }
}

struct TrunkOpenIntent: AppIntent {
    static var title: LocalizedStringResource = "Bagajı aç"
    static var description = IntentDescription("Toqdas ile bagajı açar.")
    static var openAppWhenRun: Bool = true

    @Environment(\.openURL) private var openURL

    func perform() async throws -> some IntentResult {
        await openShortcut(.trunkOpen, openURL: openURL)
        return .result()
    }
}

struct TrunkCloseIntent: AppIntent {
    static var title: LocalizedStringResource = "Bagajı kapat"
    static var description = IntentDescription("Toqdas ile bagajı kapatır.")
    static var openAppWhenRun: Bool = true

    @Environment(\.openURL) private var openURL

    func perform() async throws -> some IntentResult {
        await openShortcut(.trunkClose, openURL: openURL)
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
                    shortTitle: "Bagaj aç", systemImageName: "car.side")
        AppShortcut(intent: TrunkCloseIntent(), phrases: ["\(.applicationName) bagajı kapat"],
                    shortTitle: "Bagaj kapat", systemImageName: "car.side")
        AppShortcut(intent: VehicleStatusIntent(),
                    phrases: ["\(.applicationName) araç durumu",
                              "\(.applicationName) pil durumu"],
                    shortTitle: "Araç durumu", systemImageName: "car.fill")
        AppShortcut(intent: ChargingSpendIntent(),
                    phrases: ["\(.applicationName) bu ay şarj harcamam",
                              "\(.applicationName) şarj bütçem"],
                    shortTitle: "Şarj harcaması", systemImageName: "bolt.car.fill")
    }
}
