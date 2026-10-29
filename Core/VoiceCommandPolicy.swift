import Foundation

/// Politika kararı için gereken uygulama/araç bağlamı.
/// Onay ve kimlik doğrulama alanları oturum tarafından doldurulur.
public struct VoiceContext: Equatable, Sendable {
    public var linkReady: Bool
    public var telemetryAge: TimeInterval?
    public var deviceUnlocked: Bool
    public var confirmedCommand: VoiceCommand?
    public var authenticatedCommand: VoiceCommand?
    public var climateServiceAvailable: Bool
    public var previewActionsEnabled: Bool

    public init(
        linkReady: Bool = false,
        telemetryAge: TimeInterval? = nil,
        deviceUnlocked: Bool = true,
        confirmedCommand: VoiceCommand? = nil,
        authenticatedCommand: VoiceCommand? = nil,
        climateServiceAvailable: Bool = false,
        previewActionsEnabled: Bool = true
    ) {
        self.linkReady = linkReady
        self.telemetryAge = telemetryAge
        self.deviceUnlocked = deviceUnlocked
        self.confirmedCommand = confirmedCommand
        self.authenticatedCommand = authenticatedCommand
        self.climateServiceAvailable = climateServiceAvailable
        self.previewActionsEnabled = previewActionsEnabled
    }
}

/// Saf politika çıktısı. UI yalnızca bu kararı uygular; kendi kapı mantığını
/// kurmaz.
public enum VoiceDecision: Equatable, Sendable {
    case read(VoiceStatusTopic)
    case speak(String)
    case confirm(command: VoiceCommand, prompt: String)
    case authenticate(command: VoiceCommand, reason: String)
    case execute(VoiceCommand)
    case reject(String)
}

/// Eylem kapılarını tek bir yerde tutan saf fonksiyon.
///
/// Sıra: bağlantı → telemetri tazeliği → cihaz kilidi → önizleme → onay →
/// Face ID → yürütme.
public struct VoiceCommandPolicy: Sendable {
    public static let telemetryFreshness: TimeInterval = 15

    public init() {}

    public func decide(_ command: VoiceCommand, context: VoiceContext) -> VoiceDecision {
        switch command {
        case .status(let topic):
            return .read(topic)
        case .help:
            return .speak(Self.helpText)
        case .cancel:
            return .speak("İptal edildi.")
        case .affirm:
            return .speak("Onaylayacak bir komut yok.")
        case .deny:
            return .speak("Vazgeçildi.")
        case .ambiguous:
            return .speak("Neyi kastettiğini anlayamadım. Örnek: şarjım ne kadar, kapılar kilitli mi, bagajı aç.")
        case .unknown:
            return .speak("Bu komutu anlayamadım. Örnek: şarjım ne kadar, kapılar kilitli mi, bagajı aç.")
        case .findVehicle:
            return .reject("Aracı bulma kornası henüz araçta doğrulanmadı; bu bir önizleme. Komut göndermedim.")
        case .climate(_, _) where !context.climateServiceAvailable:
            return .reject("İklimlendirme servisi şu anda yanıt vermiyor; klima komutu gönderemiyorum.")
        default:
            break
        }

        guard command.isAction else {
            return .speak("Bu komutu uygulayamıyorum.")
        }

        let label = command.actionLabel ?? "Komut"

        guard context.linkReady else {
            return .reject("\(label) için araç bağlantısı hazır değil. Komut göndermedim.")
        }

        guard let age = context.telemetryAge, age < Self.telemetryFreshness else {
            return .reject("\(label) için araç verisi 15 saniyeden eski. Komut göndermedim; önce yenile.")
        }

        if command.requiresDeviceUnlock && !context.deviceUnlocked {
            return .reject("Kilit açma için telefonun kilidini açman gerekiyor. Komut göndermedim.")
        }

        if command.isPreview && !context.previewActionsEnabled {
            return .reject("\(label) henüz etkin değil; önizleme. Komut göndermedim.")
        }

        if context.confirmedCommand != command {
            return .confirm(command: command, prompt: Self.confirmationPrompt(for: command))
        }

        if command.requiresDeviceUnlock && context.authenticatedCommand != command {
            return .authenticate(
                command: command,
                reason: "Sesli komutla kapı kilitlerini açmak için kimliğini doğrula."
            )
        }

        return .execute(command)
    }

    public static let helpText = "Şarj, menzil, kilit, bagaj, cam, lastik ve dış sıcaklık sorabilirsin. Kilit, bagaj ve cam komutları onay ister; kilit açma Face ID ile doğrulanır."

    public static func confirmationPrompt(for command: VoiceCommand) -> String {
        switch command {
        case .lock:
            return "Kapıları kilitlemek için onaylıyor musun?"
        case .unlock:
            return "Kapı kilitlerini açmak için onaylıyor musun? Face ID ile kimlik doğrulaması istenecek."
        case .trunk(let open):
            let action = open ? "Bagajı açmak" : "Bagajı kapatmak"
            return "\(action) için onaylıyor musun? Bu işlev araçta doğrulanmadı; önizleme."
        case .windows(let open):
            let action = open ? "Camları açmak" : "Camları kapatmak"
            return "\(action) için onaylıyor musun? Bu işlev araçta doğrulanmadı; önizleme."
        case .climate(let on, let temperature):
            if on, let temperature {
                return "Klimayı \(temperature) dereceye ayarlamak için onaylıyor musun?"
            }
            return (on ? "Klimayı açmak" : "Klimayı kapatmak") + " için onaylıyor musun?"
        default:
            return "Bu komutu uygulamak için onaylıyor musun?"
        }
    }
}
