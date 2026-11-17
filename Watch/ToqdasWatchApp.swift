import SwiftUI
import WatchKit
import AVFoundation

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
            Self.playHaptic(for: result)
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
        defer { previousReady = ready }
        if let previous = previousReady {
            guard !previous, ready else { return }
        } else {
            // İlk gözlem: yalnız taze veri "gerçekten bağlı" sayılır; cache'ten
            // gelen eski READY sessizce duyurulmaz.
            guard ready, telemetryFresh(at: Date()) else { return }
        }
        let defaults = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        let last = defaults.double(forKey: "toqdas.watch.connectAnnouncedAt")
        guard now - last >= 90 else { return }
        defaults.set(now, forKey: "toqdas.watch.connectAnnouncedAt")
        WKInterfaceDevice.current().play(.success)
        if scenePhase == .active {
            WatchChime.playConnected()
        }
        NotificationPoster.requestAuthorization(using: watchPoster)
        NotificationPoster.post(
            NotificationPoster.Draft(
                identifier: UUID().uuidString,
                title: "Araç bağlandı",
                body: "Kilit verisi akıyor; saat uygulamasından komut verebilirsin.",
                timeSensitive: false),
            using: watchPoster
        )
    }

    /// Kilit geçişi sesli bildirim (anahtarlık davranışı): kilit AÇILDIĞINDA
    /// **çift bip** (0,5 sn arayla iki bildirim), KİLİTLENDİĞİNDE **tek
    /// bip** (tek bildirim). watchOS özel bildirim sesini desteklemediği
    /// için ayrım bildirim sayısıyla üretilir. Bildirim sesi yalnız saat
    /// uygulaması arka plandayken duyulur (platform davranışı); ön plandaysa
    /// haptik kalır. Metinler telemetri kilit durumunu anlatır (kapının
    /// fiziksel açılması ayrı bir iddia taşımaz); VIN yok. Yön başına 15 sn
    /// sönümleme bağlantı flap'inde tekrar sesi önler.
    private func announceLockChangeIfNeeded() {
        let locked = link.snapshot?.locked
        defer { previousLocked = locked }
        guard let previous = previousLocked, let locked, previous != locked else { return }
        let defaults = UserDefaults.standard
        let key = locked ? "toqdas.watch.lockAnnouncedAt" : "toqdas.watch.unlockAnnouncedAt"
        let now = Date().timeIntervalSince1970
        guard now - defaults.double(forKey: key) >= 15 else { return }
        defaults.set(now, forKey: key)
        WKInterfaceDevice.current().play(locked ? .success : .notification)
        NotificationPoster.requestAuthorization(using: watchPoster)
        let draft = NotificationPoster.Draft(
            identifier: UUID().uuidString,
            title: locked ? "Araç kilitlendi" : "Araç kilidi açıldı",
            body: locked ? "Kilit durumu imzalı telemetriyle doğrulandı." : "Kilit durumu imzalı telemetriyle doğrulandı.",
            timeSensitive: false,
            sound: true)
        if locked {
            NotificationPoster.post(draft, using: watchPoster)
        } else {
            // Çift bip: ikinci bildirim 0,5 sn sonra (aynı default ses).
            NotificationPoster.post(draft, using: watchPoster)
            NotificationPoster.post(
                draft,
                using: watchPoster,
                delay: 0.5
            )
        }
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


/// Saatte uygulama içi kısa ton (bağlantı onayı).
///
/// Neden gerekli: watchOS, uygulama ön plandayken kendi yerel bildirimini
/// sessiz işler; kullanıcı "bağlandı" geri bildirimini duyamıyordu. Ton
/// bellek içinde üretilen kısa bir WAV'dır (paket varlığı yok, telif yok),
/// `AVAudioPlayer` ile çalınır ve yalnız uygulama etkinken çağrılır.
/// Çalınamazsa sessiz düşer; haptik geri bildirim zaten verilmiş olur.
enum WatchChime {
    private static var player: AVAudioPlayer?

    static func playConnected() {
        guard let data = connectedToneData() else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let audio = try AVAudioPlayer(data: data)
            audio.volume = 0.9
            audio.play()
            player = audio
        } catch {
            // Ses çalınamadı: haptik zaten verildi; kullanıcıya hata gösterilmez.
        }
    }

    /// İki notalı kısa onay tonu (880 Hz → 1175 Hz), 16-bit PCM mono WAV.
    private static func connectedToneData() -> Data? {
        let rate = 44_100
        let segments: [(frequency: Double, seconds: Double)] = [
            (880, 0.18), (0, 0.05), (1174.66, 0.26)
        ]
        var samples: [Int16] = []
        for segment in segments {
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
