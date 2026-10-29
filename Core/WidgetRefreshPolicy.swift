import Foundation

/// WidgetKit yenileme kararı.
///
/// Uygulama her telemetri güncellemesinde widget'ı yeniden yüklememeli:
/// iOS zaten kendi bütçesini uygular, ayrıca gereksiz `reloadTimelines`
/// çağrıları pili ve widget kotasını tüketir.
///
/// Kural:
/// - İlk yayın her zaman yüklenir.
/// - Hayati alanlar değiştiyse en fazla `minimumInterval` sıklığında yüklenir.
/// - Hiçbir şey değişmese bile `forcedInterval` sonunda tazelenir.
enum WidgetRefreshPolicy {
    static let minimumInterval: TimeInterval = 60
    static let forcedInterval: TimeInterval = 300

    static func shouldReload(
        isFirstPublish: Bool,
        contentChanged: Bool,
        lastReloadAt: Date?,
        now: Date = Date()
    ) -> Bool {
        guard let lastReloadAt else { return true }
        let elapsed = now.timeIntervalSince(lastReloadAt)
        if elapsed < 0 { return true }
        if isFirstPublish { return true }
        if elapsed >= forcedInterval { return true }
        return contentChanged && elapsed >= minimumInterval
    }
}
