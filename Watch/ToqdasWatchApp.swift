import SwiftUI
import WatchKit
import AVFoundation
import UserNotifications

@main
struct ToqdasWatchApp: App {
    @StateObject private var link = WatchLink()
    var body: some Scene {
        WindowGroup {
            WatchGarageView(link: link)
                .environment(\.locale, Locale(identifier: "tr_TR"))
        }
    }
}

struct WatchGarageView: View {
    @ObservedObject var link: WatchLink
    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingCommand: String?
    @State private var showCommandConfirmation = false
    @State private var pendingAutomation: WatchProximityAutomationAction?
    @State private var lastRecovering: Bool?
    @State private var previousReady: Bool?
    @State private var previousLocked: Bool?
    @State private var lastSnapshotStamp: TimeInterval?
    @State private var toneTestNote: String?
    @State private var notificationAllowed: Bool?
    @State private var showSoundSettings = false
    private let watchPoster = SystemNotificationPoster()

    private var snapshot: WatchSnapshot? { link.snapshot }

    private func telemetryAge(at now: Date) -> TimeInterval? {
        guard let snapshot, let age = snapshot.telemetryAge else { return nil }
        // Saat/telefon saat sapmasında küçük negatif fark veri geldiği an
        // oluşur; "süre bilinmiyor" yazmak yerine 0'a kelepçelenir.
        let elapsed = max(0, now.timeIntervalSince1970 - snapshot.updatedAt)
        return age + elapsed
    }

    private func telemetryFresh(at now: Date) -> Bool {
        guard let age = telemetryAge(at: now) else { return false }
        return age < 15
    }

    private func canCommand(at now: Date) -> Bool {
        // iPhone uygulaması arka plandayken `reachable` false olur; istek
        // tek kez kuyruklu kanala bırakıldığı için düğme kapatılmaz.
        snapshot?.ready == true && snapshot?.vin.isEmpty == false
            && telemetryFresh(at: now) && snapshot?.locked != nil
    }

    /// Gösterim tazeliği: komut eşiği (15 sn) ile karıştırılmamalıdır.
    /// İmzalı telemetri ~30 sn aralıklı gelir; 15–45 sn arası normal dönem
    /// arasıdır ve "eski" değil "bekleniyor" der (sağlıklı bağlantıda
    /// flap yapmaz). 45 sn üstü gerçekten bayat sayılır.
    private func displayStale(at now: Date) -> Bool {
        guard let age = telemetryAge(at: now) else { return true }
        return age >= 45
    }

    private func lockText(at now: Date) -> String {
        if displayStale(at: now) { return "Kilit verisi eski" }
        if !telemetryFresh(at: now) { return "Kilit durumu bekleniyor" }
        switch snapshot?.locked {
        case true: return "Kilitli"
        case false: return "Kilit açık"
        default: return "Kilit bilinmiyor"
        }
    }

    private func lockSymbol(at now: Date) -> String {
        guard !displayStale(at: now) else { return "questionmark.circle" }
        switch snapshot?.locked {
        case true: return "lock.fill"
        case false: return "lock.open.fill"
        default: return "questionmark.circle"
        }
    }

    private func lockColor(at now: Date) -> Color {
        // U2 ton sözlüğü: karar Core'da (LockVisual), renk saat paletinden.
        let tone = LockVisual.tone(locked: snapshot?.locked, isStale: !telemetryFresh(at: now))
        switch tone {
        case .positive: return .green
        case .warning: return .orange
        case .negative: return .red
        case .neutral: return .secondary
        }
    }

    private func connectionText(at now: Date) -> String {
        if snapshot == nil { return "iPhone’dan veri bekleniyor" }
        if snapshot?.recovering == true { return "iPhone bağlantıyı yeniden kuruyor…" }
        // reachable yalnız iPhone uygulaması ön plandayken true olur
        // (platform davranışı); arka plan normaldir, alarm değil.
        if !link.reachable {
            return "iPhone uygulaması arka planda · son veri \(dataAgeText(at: now))"
        }
        if snapshot?.ready != true { return "Dijital anahtar hazır değil" }
        if telemetryFresh(at: now) { return "Telemetri güncel" }
        if let age = telemetryAge(at: now), age < 45 {
            return "İmzalı telemetri bekleniyor (\(Int(age)) sn önce)"
        }
        return "İmzalı telemetri eski (\(dataAgeText(at: now)))"
    }

    private func dataAgeText(at now: Date) -> String {
        guard let age = telemetryAge(at: now) else { return "süre bilinmiyor" }
        if age < 60 { return "\(Int(age)) sn önce" }
        if age < 3600 { return "\(Int(age / 60)) dk önce" }
        return "\(Int(age / 3600)) sa önce"
    }

    private func needsRefresh(at now: Date) -> Bool {
        snapshot != nil && !telemetryFresh(at: now) && link.reachable
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { timeline in
            let now = timeline.date
            ScrollView {
                VStack(spacing: 8) {
                    Text(snapshot?.vehicleName ?? "Toqdas")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Image(systemName: lockSymbol(at: now))
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(lockColor(at: now))
                        .padding(.top, 2)

                    Text(lockText(at: now))
                        .font(.headline)

                    Text(connectionText(at: now))
                        .font(.caption2)
                        .foregroundStyle(canCommand(at: now) ? .green : .orange)
                        .multilineTextAlignment(.center)

                    if telemetryFresh(at: now), let detailLine {
                        Text(detailLine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if needsRefresh(at: now) {
                        Button {
                            link.requestRefresh()
                        } label: {
                            Label("Veriyi yenile", systemImage: "arrow.clockwise")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }

                    automationSection

                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            metric(batteryText, systemImage: batteryIcon)
                            metric(rangeText, systemImage: "road.lanes")
                        }
                        HStack(spacing: 6) {
                            metric(temperatureText, systemImage: "thermometer.medium")
                            metric(telemetryFresh(at: now) ? trunkText : "Bagaj —", systemImage: "car.side")
                        }
                        HStack(spacing: 6) {
                            metric(auxBatteryText, systemImage: "bolt.batteryblock", tint: auxTint)
                            metric(odometerText, systemImage: "speedometer")
                        }
                        HStack(spacing: 6) {
                            metric(snapshot?.lastSeenText ?? "—", systemImage: "eye")
                            metric(snapshot?.sessionQualityText ?? "—",
                                   systemImage: "antenna.radiowaves.left.and.right")
                        }
                    }
                    .padding(.top, 2)

                    HStack(spacing: 8) {
                        commandButton("Kilitle", systemImage: "lock.fill", action: "lock", tint: .blue,
                                      enabled: canCommand(at: now))
                        commandButton("Aç", systemImage: "lock.open.fill", action: "unlock", tint: .orange,
                                      enabled: canCommand(at: now))
                    }
                    .padding(.top, 4)

                    HStack(spacing: 6) {
                        commandButton(trunkCommandTitle, systemImage: "car.side", action: trunkAction, tint: .green,
                                      enabled: canCommand(at: now))
                    }
                    .padding(.top, 2)

                    Text(!link.reachable
                        ? "iPhone arka planda; komut iletilir ama sonuç birkaç saniye gecikebilir."
                        : (link.lastResult?.message ?? "İstek iPhone üzerinden iletilir. Kilit onayı araç telemetrisinden gelir."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)

                    // iPhone uygulamasından yapılan son komutun sonucu
                    // (metin iPhone tarafında hazırlandı; 24 saatten eski kayıt süzülür).
                    if let lastCommand = snapshot?.lastCommandText {
                        Text(lastCommand)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    soundSettingsSection

                    Text("Bagaj komutu iPhone üzerinden iletilir; cam komutları kapalı.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
        }
        .confirmationDialog("Yakınlık otomasyonu",
                            isPresented: Binding(
                                get: { pendingAutomation != nil },
                                set: { if !$0 { pendingAutomation = nil } }),
                            titleVisibility: .visible) {
            Button(pendingAutomation == .enable ? "Aç" : "Kapat") {
                if let automation = pendingAutomation {
                    link.request(automation.action, vin: snapshot?.vin ?? "")
                }
                pendingAutomation = nil
            }
            Button("Vazgeç", role: .cancel) { pendingAutomation = nil }
        } message: {
            Text(pendingAutomation?.confirmationText ?? "")
        }
        .confirmationDialog("Araç komutu gönderilsin mi?", isPresented: $showCommandConfirmation,
                            titleVisibility: .visible) {
            Button(confirmationTitle, role: .destructive) {
                if let pendingCommand { request(pendingCommand) }
            }
            Button("Vazgeç", role: .cancel) { pendingCommand = nil }
        } message: {
            Text("Komut iPhone üzerinden iletilir. İşlemden önce dijital anahtarın hazır ve imzalı araç durumu güncel olmalı.")
        }
        .onChange(of: link.lastResult?.id) { _ in
            guard let result = link.lastResult else { return }
            // Ses/haptik `announce` içinde; tanınmayan durumlarda eski haptik.
            if !announceCommandResult(result) {
                Self.playHaptic(for: result)
            }
        }
        .onChange(of: link.snapshot?.updatedAt) { _ in
            checkChargingTargetOnWatch()
            announceConnectionIfNeeded()
            announceLockChangeIfNeeded()
        }
        .onChange(of: link.snapshot?.recovering) { _ in
            confirmRecoveryIfNeeded()
        }
        .onAppear {
            lastRecovering = link.snapshot?.recovering
        }
        .onAppear {
            // Bildirim izni açılışta istenir: arka plan sesi ilk olay anında
            // değil, kullanıcı izni gördüğünde garantiye alınır.
            NotificationPoster.requestAuthorization(using: watchPoster)
            refreshNotificationPermission()
            refreshIfStale()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { refreshIfStale() }
        }
        .onChange(of: link.reachable) { reachable in
            if reachable { refreshIfStale() }
        }
    }

    /// Bağlantı duyurusu: araç verisi READY olduğunda saatte haptik + ses.
    ///
    /// Ses iki kanaldan gelir, çünkü ikisi farklı durumlarda duyulur:
    /// - **Ön planda** (kullanıcı saate bakıyor): `WatchChime` doğrudan ton
    ///   çalar. watchOS kendi uygulamasının bildirimini ön planda sessiz
    ///   işler; "gerçekten bağlandı" geri bildirimi böyle duyulur.
    /// - **Arka planda**: yerel bildirim (izin verildiyse) sesli teslim edilir.
    ///
    /// Duyuru hem READY'ye geçişte hem de saat ilk açıldığında veri taze ise
    /// yapılır: kullanıcı saati açtığında "bağlı mı" sorusunun yanıtı sessiz
    /// kalmasın. 90 sn sönümleme tekrarı önler; VIN yok.
    private func announceConnectionIfNeeded() {
        let ready = link.snapshot?.ready == true
        let stamp = link.snapshot?.updatedAt
        // Veri akışı kesilip geri geldiyse (60 sn boşluk) bu da "bağlandı"dır:
        // kullanıcı saati açtığında veri sessizce akmaya başlamasın.
        let resumed = stamp != nil && lastSnapshotStamp != nil
            && (stamp! - lastSnapshotStamp!) >= 60
        lastSnapshotStamp = stamp
        defer { previousReady = ready }
        if resumed, ready {
            announce(.resumed)
            return
        }
        if let previous = previousReady {
            guard !previous, ready else { return }
        } else {
            // İlk gözlem: yalnız taze veri "gerçekten bağlı" sayılır; cache'ten
            // gelen eski READY sessizce duyurulmaz (tazelik `announce` içinde).
            guard ready else { return }
        }
        announce(.connected)
    }

    /// Ses + haptik + (arka planda) yerel bildirim.
    ///
    /// Karar `WatchSoundPolicy`de: kullanıcı ayarı, imzalı veri tazeliği ve
    /// sönümleme orada uygulanır; burada yalnız platform işi (ton/bildirim)
    /// yapılır ve sonuç saat tanısına tek satır yazılır. Ses kararı hiçbir
    /// zaman "araç hazır/başarılı" iddiası üretmez.
    private func announce(_ event: WatchSoundPolicy.Event, now: Date = Date()) {
        let toggle = WatchSoundPolicy.toggle(for: event)
        let enabled = WatchSoundSettings.isEnabled(toggle)
        let key = WatchSoundPolicy.dampingKey(for: event)
        let last = UserDefaults.standard.double(forKey: key)
        let since = last > 0 ? now.timeIntervalSince1970 - last : nil
        let decision = WatchSoundPolicy.decision(
            event: event,
            enabled: enabled,
            fresh: telemetryFresh(at: now),
            foreground: scenePhase == .active,
            sinceLast: since)
        switch decision {
        case .suppressed(let reason):
            WatchDiagnostics.log("ses · \(event.rawValue) · \(reason)")
        case .announce(let channel):
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: key)
            WKInterfaceDevice.current().play(Self.haptic(for: event))
            switch channel {
            case .chime(let tone):
                let played = WatchChime.play(tone)
                WatchDiagnostics.log("ses · \(event.rawValue) · ton "
                                     + (played ? "çalındı" : "çalınamadı (ses oturumu)"))
            case .notification(let count):
                postNotifications(for: event, count: count)
                WatchDiagnostics.log("ses · \(event.rawValue) · \(count) bildirim")
            case .none:
                break
            }
        }
    }

    /// Komut sonucu sesi. "forwarded" yalnız **iletildi** demektir (araç
    /// yanıtı bekleniyor) → metin "Komut iletildi"; ack uygulandı anlamına
    /// gelmez. "unavailable"/"rejected" dürüstçe "tamamlanmadı" der.
    @discardableResult
    private func announceCommandResult(_ result: WatchCommandResult) -> Bool {
        switch result.status {
        case "forwarded", "acknowledged":
            announce(.commandForwarded)
            return true
        case "unavailable", "rejected", "expired":
            announce(.commandFailed)
            return true
        default:
            return false
        }
    }

    private static func haptic(for event: WatchSoundPolicy.Event) -> WKHapticType {
        switch event {
        case .connected, .resumed: return .success
        case .locked: return .success
        case .unlocked: return .notification
        case .commandForwarded: return .success
        case .commandFailed: return .failure
        }
    }

    /// Arka plan bildirimi. watchOS özel bildirim sesi desteklemediği için
    /// kilit açılması **çift** bildirimle ayrılır (0,5 sn arayla).
    private func postNotifications(for event: WatchSoundPolicy.Event, count: Int) {
        NotificationPoster.requestAuthorization(using: watchPoster)
        let draft = NotificationPoster.Draft(
            identifier: UUID().uuidString,
            title: WatchSoundPolicy.title(for: event),
            body: WatchSoundPolicy.body(for: event),
            timeSensitive: false,
            sound: true)
        NotificationPoster.post(draft, using: watchPoster)
        if count > 1 {
            NotificationPoster.post(draft, using: watchPoster, delay: 0.5)
        }
    }

    /// Kilit geçişi duyurusu. Ön planda **ton** (kilit = tek ton, açık =
    /// çift ton), arka planda **bildirim sayısı** (kilit 1, açık 2) —
    /// watchOS özel bildirim sesi desteklemediği için ayrım böyle kurulur.
    ///
    /// Tazelik kapısı burada değil `WatchSoundPolicy.decision` içinde:
    /// imzalı veri eskiyse duyuru yapılmaz ("kilitlendi" iddiası üretilmez),
    /// sessiz kalır ve tanıya "imzalı veri eski" yazılır. Metinler telemetri
    /// kilit durumunu anlatır; kapının fiziksel açılması ayrı bir iddiadır.
    private func announceLockChangeIfNeeded() {
        let locked = link.snapshot?.locked
        defer { previousLocked = locked }
        guard let previous = previousLocked, let locked, previous != locked else { return }
        announce(locked ? .locked : .unlocked)
    }

    /// Şarj durumu satırı: yüzde, kullanıcı hedefi ve hedefe kalan.
    /// Eksik değer yazılmaz (0 uydurulmaz).
    private func chargingLine(at now: Date) -> String {
        guard let snapshot else { return "Şarj sürüyor" }
        var parts: [String] = []
        if let percent = snapshot.batteryPercent {
            parts.append("%\(Int(percent.rounded()))")
        }
        if let target = snapshot.chargingTargetPercent, let percent = snapshot.batteryPercent {
            let remaining = max(0, target - Int(percent.rounded()))
            parts.append("hedef %\(target) · kalan %\(remaining)")
        }
        return parts.isEmpty ? "Şarj sürüyor" : "Şarj sürüyor · \(parts.joined(separator: " · "))"
    }

    /// Saat tarafı hedef gözcüsü: hedefe ulaşıldığında saatte yerel
    /// bildirim + haptik. Oturum başına bir kez: dedupe anahtarı oturum
    /// başlangıcını içerir, VIN içermez. Eksik yüzde asla "ulaşıldı"
    /// üretmez (Core politikasıyla aynı taban).
    private func checkChargingTargetOnWatch() {
        guard let snapshot else { return }
        guard snapshot.chargingActive == true,
              let target = snapshot.chargingTargetPercent,
              let startedAt = snapshot.chargingStartedAt,
              let percent = snapshot.batteryPercent,
              ChargingTargetPolicy.reached(target: target, percent: percent) else { return }
        let key = "toqdas.chargingtarget.watch.\(Int(startedAt)).\(target)"
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: key) == false else { return }
        defaults.set(true, forKey: key)
        WKInterfaceDevice.current().play(.notification)
        NotificationPoster.post(
            NotificationPoster.Draft(
                identifier: UUID().uuidString,
                title: "Şarj hedefi (%\(target)) aşıldı",
                body: "Akü %\(Int(percent.rounded())). Araç şarjı uygulamadan durdurmaz.",
                timeSensitive: false),
            using: watchPoster
        )
    }

    /// Sessiz kurtarma bittiğinde tek onay haptiği: "yeniden kuruyor"
    /// durumundan READY'ye geçiş kullanıcıya sessizce bildirilir.
    private func confirmRecoveryIfNeeded() {
        let recovering = link.snapshot?.recovering ?? false
        if lastRecovering == true, recovering == false, link.snapshot?.ready == true {
            WKInterfaceDevice.current().play(.success)
        }
        lastRecovering = recovering
    }

    /// Saat açıldığında veri 30 saniyeden eskiyse iPhone'dan tazeleme ister.
    /// Böylece kullanıcı "Veriyi yenile" düğmesini aramak zorunda kalmaz;
    /// istek yalnız telefon erişilebilirse gider (kuyruk yok).
    private func refreshIfStale() {
        guard link.reachable else { return }
        guard WatchSnapshot.isStale(updatedAt: snapshot?.updatedAt, after: 30) else { return }
        link.requestRefresh()
    }

    /// Yakınlık otomasyonu anahtarı: araç komutu göndermez; iPhone'a
    /// uygulama içi geçiş isteği iletir. Durum snapshot'tan gelir.
    private var automationSection: some View {
        let state = snapshot?.proximityEnabled
        let canToggle = link.reachable && snapshot?.vin.isEmpty == false
            && pendingAutomation == nil && !stateIsLoading
        return VStack(spacing: 6) {
            HStack {
                Text("Yakınlık otomasyonu")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(state == true ? "Açık" : state == false ? "Kapalı" : "—")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(state == true ? Color.green : Color.secondary)
            }
            HStack(spacing: 8) {
                Button {
                    pendingAutomation = .enable
                } label: {
                    Label("Aç", systemImage: "location.north.circle")
                        .font(.caption)
                }
                .disabled(!canToggle || state == true)
                Button {
                    pendingAutomation = .disable
                } label: {
                    Label("Kapat", systemImage: "location.slash")
                        .font(.caption)
                }
                .disabled(!canToggle || state == false)
            }
            .buttonStyle(.bordered)
            if !link.reachable {
                Text("Aç/kapat için iPhone erişilebilir olmalı.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    /// Uygulama anahtarı, araç komutlarının READY/telemetri şartına
    /// tabi değildir; yalnız iPhone erişimi yeterlidir.
    private var stateIsLoading: Bool { false }

    /// Komut yanıtına göre dokunsal geri bildirim. "forwarded" başarının
    /// kanıtı değildir; onay telemetriden gelir, bu nedenle bildirim/hata
    /// tipi kullanılır ve kesin onay tıklaması çalınmaz.
    // MARK: - Ses ve bildirim ayarları

    /// Üç anahtar + izin durumu + ton denemesi. Tercihler `UserDefaults`ta
    /// (VIN yok); kararlar `WatchSoundPolicy`de olduğu için buradaki
    /// değişiklik bir sonraki olaydan itibaren geçerlidir.
    private var soundSettingsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // watchOS'ta DisclosureGroup yok; aç/kapa düğmesi.
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showSoundSettings.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text("Ses ve bildirimler")
                        .font(.caption2.weight(.semibold))
                    Spacer()
                    Image(systemName: showSoundSettings ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                }
            }
            .buttonStyle(.plain)

            if showSoundSettings {
                ForEach(WatchSoundPolicy.Toggle.allCases, id: \.rawValue) { toggle in
                    Toggle(isOn: soundBinding(toggle)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(toggle.title)
                            Text(toggle.detail)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption2)
                }

                Text(notificationPermissionText)
                    .font(.system(size: 10))
                    .foregroundStyle(notificationAllowed == false ? .orange : .secondary)
                    .multilineTextAlignment(.leading)

                Button("Sesi dene") {
                    toneTestNote = WatchChime.play(.connected)
                        ? "Ton çalındı. Duymadıysan: Ayarlar > Ses ve Dokunsal."
                        : "Ton çalınamadı; ses oturumu açılamadı."
                }
                .buttonStyle(.bordered)
                .font(.caption2)

                if let toneTestNote {
                    Text(toneTestNote)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Text("Ses yalnız saatin ses düzeyi açıkken duyulur; arka planda "
                     + "kilit açılması iki bip, kilitlenme tek bip.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 2)
    }

    private func soundBinding(_ toggle: WatchSoundPolicy.Toggle) -> Binding<Bool> {
        Binding(
            get: { WatchSoundSettings.isEnabled(toggle) },
            set: { enabled in
                WatchSoundSettings.set(enabled, for: toggle)
                WatchDiagnostics.log("ses ayarı · \(toggle.rawValue) · "
                                     + (enabled ? "açık" : "kapalı"))
            }
        )
    }

    private var notificationPermissionText: String {
        switch notificationAllowed {
        case .none: return "Bildirim izni kontrol ediliyor…"
        case .some(true): return "Arka planda bildirim sesi açık."
        case .some(false): return "Arka planda ses kapalı · Ayarlar > Bildirimler."
        }
    }

    private func refreshNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let allowed = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            DispatchQueue.main.async { notificationAllowed = allowed }
        }
    }

    private static func playHaptic(for result: WatchCommandResult) {
        switch result.status {
        case "forwarded":
            WKInterfaceDevice.current().play(.notification)
        case "rejected", "unavailable":
            WKInterfaceDevice.current().play(.failure)
        default:
            break
        }
    }

    private var batteryText: String {
        guard let value = snapshot?.batteryPercent else { return "— %" }
        return "%\(Int(value.rounded()))"
    }

    private var isCharging: Bool {
        snapshot?.chargingState?.lowercased() == "charging"
    }

    private var batteryIcon: String {
        isCharging ? "battery.100percent.bolt" : "battery.100percent"
    }

    private var auxBatteryText: String {
        guard let value = snapshot?.auxiliaryBatteryPercent else { return "12V —" }
        return "12V \(AuxiliaryBatteryPolicy.percentText(value) ?? "—")"
    }

    /// 12 V renk kuralı widget ile aynıdır (`AuxiliaryBatteryPolicy`):
    /// ≤%25 kırmızı, ≤%40 turuncu; eksik veri (nil) renklenmez ("bilgi
    /// yok" ≠ uyarı).
    private var auxTint: Color? {
        guard let assessment = AuxiliaryBatteryPolicy.assess(snapshot?.auxiliaryBatteryPercent) else { return nil }
        return assessment.isCritical ? .red : .orange
    }

    private var odometerText: String {
        guard let value = snapshot?.odometerKM else { return "— km" }
        return "\(Int(value.rounded()).formatted()) km"
    }

    private var powerText: String? {
        switch snapshot?.powerState {
        case 2: return "Bekleme"
        case 3: return "Aksesuar"
        case 4: return "Hazır"
        default: return nil
        }
    }

    private var detailLine: String? {
        guard let snapshot else { return nil }
        var parts: [String] = []
        if let powerText { parts.append("Güç: \(powerText)") }
        if snapshot.doorCount == 4 {
            parts.append(snapshot.openDoors == 0 ? "Kapılar kapalı" : "\(snapshot.openDoors) kapı açık")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var confirmationTitle: String {
        switch pendingCommand {
        case "unlock": return "Kilidi aç"
        case "trunkOpen": return "Bagajı aç"
        case "trunkClose": return "Bagajı kapat"
        default: return "Kilitle"
        }
    }

    private var trunkCommandTitle: String {
        snapshot?.trunkAjar == true ? "Bagaj kapat" : "Bagaj aç"
    }

    private var trunkAction: String {
        snapshot?.trunkAjar == true ? "trunkClose" : "trunkOpen"
    }

    private var rangeText: String {
        guard let value = snapshot?.rangeKM else { return "— km" }
        return "\(Int(value.rounded())) km"
    }

    private var temperatureText: String {
        guard let value = snapshot?.outsideTemperatureC else { return "—°C" }
        return "\(Int(value.rounded()))°C"
    }

    private var trunkText: String {
        switch snapshot?.trunkAjar {
        case true: return "Bagaj açık"
        case false: return "Bagaj kapalı"
        default: return "Bagaj —"
        }
    }

    private func metric(_ text: String, systemImage: String, tint: Color? = nil) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint ?? .primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commandButton(_ title: String, systemImage: String, action: String,
                               tint: Color, enabled: Bool) -> some View {
        Button {
            pendingCommand = action
            showCommandConfirmation = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title2)
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 68)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .disabled(!enabled)
        .accessibilityLabel(title)
        .accessibilityHint("Komut iPhone üzerinden gönderilir; taze imzalı telemetri gerekir.")
    }

    private func previewButton(_ title: String) -> some View {
        Button(title) {}
            .buttonStyle(.bordered)
            .font(.caption2.weight(.semibold))
            .disabled(true)
    }

    private func request(_ action: String) {
        guard let vin = snapshot?.vin, !vin.isEmpty else { return }
        link.request(action, vin: vin)
    }
}


/// Saatte uygulama içi kısa tonlar (ön plan geri bildirimi).
///
/// Neden gerekli: watchOS, uygulama ön plandayken kendi yerel bildirimini
/// **sessiz** işler; kullanıcı ön planda hiçbir ses duymuyordu (bağlantı ve
/// kilit geçişleri dahil). Tonlar bellek içinde üretilen kısa WAV'lardır
/// (paket varlığı yok, telif yok), `AVAudioPlayer` ile çalınır.
///
/// Kasıtlı sınırlar:
/// - Yalnız ön planda çağrılır; arka planda ayrım bildirim **sayısıyla**.
/// - Çalınamazsa sessiz düşer (çağıran tanıya yazar); haptik zaten verildi.
/// - Oturum çalma bitince kapatılır: saatteki diğer sesler kesilmez ve
///   ses oturumu açık kalmaz (eskiden `setActive(false)` hiç çağrılmıyordu).
enum WatchChime {
    private static var player: AVAudioPlayer?

    @discardableResult
    static func play(_ tone: WatchSoundPolicy.Tone) -> Bool {
        guard let data = toneData(tone) else { return false }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let audio = try AVAudioPlayer(data: data)
            audio.volume = 0.9
            audio.delegate = ChimeDelegate.shared
            audio.play()
            player = audio
            return true
        } catch {
            try? AVAudioSession.sharedInstance().setActive(false)
            return false
        }
    }

    /// Çalma bitince (ya da çözme hatasında) oturumu bırak.
    fileprivate static func finish() {
        player = nil
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private final class ChimeDelegate: NSObject, AVAudioPlayerDelegate {
        static let shared = ChimeDelegate()

        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            WatchChime.finish()
        }

        func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
            WatchChime.finish()
        }
    }

    /// Ton sözlüğü: yön ve sonuç farkı frekans dizisiyle kurulur.
    /// Kilit = alçalan, açılma = yükselen çift, komut = tek/inen kısa notalar.
    private static func segments(for tone: WatchSoundPolicy.Tone)
    -> [(frequency: Double, seconds: Double)] {
        switch tone {
        case .connected:
            return [(880, 0.18), (0, 0.05), (1174.66, 0.26)]
        case .lock:
            return [(987.77, 0.14), (0, 0.04), (659.25, 0.20)]
        case .unlock:
            return [(659.25, 0.12), (0, 0.04), (987.77, 0.12), (0, 0.06), (1318.51, 0.16)]
        case .commandOK:
            return [(1046.50, 0.12)]
        case .commandFail:
            return [(392.00, 0.14), (0, 0.04), (329.63, 0.20)]
        }
    }

    /// 16-bit PCM mono WAV (44,1 kHz).
    private static func toneData(_ tone: WatchSoundPolicy.Tone) -> Data? {
        let rate = 44_100
        var samples: [Int16] = []
        for segment in segments(for: tone) {
            let count = Int(segment.seconds * Double(rate))
            guard count > 0 else { continue }
            let attack = max(1, Int(0.01 * Double(rate)))
            let release = max(1, Int(0.02 * Double(rate)))
            for index in 0..<count {
                guard segment.frequency > 0 else {
                    samples.append(0)
                    continue
                }
                let time = Double(index) / Double(rate)
                let envelope = min(1.0, Double(index) / Double(attack))
                    * min(1.0, Double(count - index) / Double(release))
                let value = sin(2 * .pi * segment.frequency * time) * 0.35 * envelope
                samples.append(Int16(max(-1, min(1, value)) * 32_767))
            }
        }
        guard !samples.isEmpty else { return nil }

        var data = Data()
        let byteCount = UInt32(samples.count * 2)
        func append(_ string: String) { data.append(contentsOf: Array(string.utf8)) }
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        append("RIFF")
        append32(36 + byteCount)
        append("WAVEfmt ")
        append32(16)
        append16(1)                      // PCM
        append16(1)                      // mono
        append32(UInt32(rate))
        append32(UInt32(rate * 2))       // byte rate
        append16(2)                      // block align
        append16(16)                     // bits per sample
        append("data")
        append32(byteCount)
        for sample in samples {
            append16(UInt16(bitPattern: sample))
        }
        return data
    }
}
