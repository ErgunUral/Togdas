import Foundation

/// Durumların görsel tonu — SwiftUI'siz, saf ve test edilebilir.
/// UI katmanı (Dashboard/Widget/Saat) bu tonu kendi paletinden renge
/// çevirir; böylece durum→renk kararı tek yerde tanımlanır.
///
/// Sözlük: yeşil=canlı/doğru/hazır · turuncu=bekleme/işlem sürüyor/eski ·
/// pembe=hata · gri=bilgi yok/bağlı değil.
enum VisualTone: Equatable {
    case positive
    case warning
    case negative
    case neutral
}

/// Kilit bilgisinin tonu: eski veri ("veri eski" rozeti) uyarı tonudur;
/// bilinmeyen kilit bilgi yok tonudur — asla hataya dönüştürülmez.
enum LockVisual {
    static func tone(locked: Bool?, isStale: Bool) -> VisualTone {
        if isStale { return .warning }
        switch locked {
        case true: return .positive
        case false: return .warning
        case nil: return .neutral
        }
    }
}
