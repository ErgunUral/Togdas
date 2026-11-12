import SwiftUI
import WidgetKit

/// Saat complication'ı (WidgetKit). Yalnız `WatchComplicationStore`'dan
/// okunan **son bilinen gösterim verisi** gösterilir; komut göndermez,
/// konum kullanmaz, ağ erişimi yoktur (invariant: complication salt
/// görüntüdür). Veri yoksa "—" gösterilir; asla 0 sahtesi yapılmaz.
struct WatchSnapshotEntry: TimelineEntry {
    let date: Date
    let vin: String
    let vehicleName: String
    let locked: Bool?
    let ready: Bool
    let updatedAt: Date?
    let batteryPercent: Double?
    let auxiliaryBatteryPercent: Double?
    let rangeKM: Double?

    static let empty = WatchSnapshotEntry(
        date: Date(), vin: "", vehicleName: "Toqdas", locked: nil, ready: false,
        updatedAt: nil, batteryPercent: nil, auxiliaryBatteryPercent: nil, rangeKM: nil
    )
}

struct WatchSnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchSnapshotEntry { .empty }

    func getSnapshot(in context: Context, completion: @escaping (WatchSnapshotEntry) -> Void) {
        completion(entryFromStore(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchSnapshotEntry>) -> Void) {
        let entry = entryFromStore(date: Date())
        // Tazeleme sorumluluğu watch uygulamasındadır (WidgetCenter reload
        // her snapshot'ta çağrılır). Yedek: 30 dakikalık sessiz yenileme.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: entry.date) ?? entry.date
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func entryFromStore(date: Date) -> WatchSnapshotEntry {
        guard let data = WatchComplicationStore.snapshotData(),
              let snapshot = try? JSONDecoder().decode(WatchSnapshot.self, from: data) else {
            return .empty
        }
        return WatchSnapshotEntry(
            date: date,
            vin: snapshot.vin,
            vehicleName: snapshot.vehicleName,
            locked: snapshot.locked,
            ready: snapshot.ready,
            updatedAt: Date(timeIntervalSince1970: snapshot.updatedAt),
            batteryPercent: snapshot.batteryPercent,
            auxiliaryBatteryPercent: snapshot.auxiliaryBatteryPercent,
            rangeKM: snapshot.rangeKM
        )
    }
}

// MARK: - Görünümler

private func lockColor(locked: Bool?, ready: Bool) -> Color {
    guard ready else { return .secondary }
    switch locked {
    case true: return .green
    case false: return .orange
    default: return .secondary
    }
}

private func lockSymbol(locked: Bool?, ready: Bool) -> String {
    guard ready else { return "questionmark.circle" }
    switch locked {
    case true: return "lock.fill"
    case false: return "lock.open.fill"
    default: return "questionmark.circle"
    }
}

private func auxTint(_ percent: Double?) -> Color? {
    guard let assessment = AuxiliaryBatteryPolicy.assess(percent) else { return nil }
    return assessment.isCritical ? .red : .orange
}

struct ComplicationRectangularView: View {
    let entry: WatchSnapshotEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: lockSymbol(locked: entry.locked, ready: entry.ready))
                    .foregroundStyle(lockColor(locked: entry.locked, ready: entry.ready))
                Text(entry.vehicleName)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                if let battery = entry.batteryPercent {
                    Label("%\(Int(battery.rounded()))", systemImage: "battery.100percent")
                        .font(.caption2)
                } else {
                    Text("Şarj —").font(.caption2)
                }
                if let aux = entry.auxiliaryBatteryPercent {
                    Text("12V \(AuxiliaryBatteryPolicy.percentText(aux) ?? "—")")
                        .font(.caption2)
                        .foregroundStyle(auxTint(aux) ?? .secondary)
                } else {
                    Text("12V —").font(.caption2)
                }
                if let range = entry.rangeKM {
                    Text("\(Int(range.rounded())) km").font(.caption2)
                } else {
                    Text("— km").font(.caption2)
                }
            }
        }
    }
}

struct ComplicationCircularView: View {
    let entry: WatchSnapshotEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: lockSymbol(locked: entry.locked, ready: entry.ready))
                .font(.title3.weight(.semibold))
                .foregroundStyle(lockColor(locked: entry.locked, ready: entry.ready))
        }
    }
}

struct ComplicationInlineView: View {
    let entry: WatchSnapshotEntry

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: lockSymbol(locked: entry.locked, ready: entry.ready))
            switch (entry.ready, entry.locked) {
            case (true, true): Text("Kilitli")
            case (true, false): Text("Kilit açık")
            default: Text("Hazır değil")
            }
        }
    }
}

struct ComplicationCornerView: View {
    let entry: WatchSnapshotEntry

    var body: some View {
        ZStack(alignment: .topLeading) {
            AccessoryWidgetBackground()
            Image(systemName: lockSymbol(locked: entry.locked, ready: entry.ready))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(lockColor(locked: entry.locked, ready: entry.ready))
                .padding(4)
            Gauge(value: min(max(entry.batteryPercent ?? 0, 0), 100), in: 0...100) {
            } currentValueLabel: {
                Text(entry.batteryPercent.map { "%\(Int($0.rounded()))" } ?? "—")
                    .font(.system(size: 8, weight: .bold))
                    .minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircular)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(14)
        }
    }
}

struct ToqdasWatchComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ToqdasWatchComplication", provider: WatchSnapshotProvider()) { entry in
            ComplicationRectangularView(entry: entry)
        }
        .configurationDisplayName("Toqdas araç durumu")
        .description("Kilit durumu ve son bilinen şarj/12 V/menzil. Yalnızca gösterim; komut göndermez.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline, .accessoryCorner])
    }
}

@main
struct ToqdasWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        ToqdasWatchComplication()
    }
}
