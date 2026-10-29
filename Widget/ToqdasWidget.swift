import SwiftUI
import WidgetKit

private struct VehicleStatusEntry: TimelineEntry {
    let date: Date
    let snapshot: VehicleWidgetSnapshot?
}

private struct VehicleStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> VehicleStatusEntry {
        VehicleStatusEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (VehicleStatusEntry) -> Void) {
        completion(VehicleStatusEntry(date: .now, snapshot: VehicleWidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VehicleStatusEntry>) -> Void) {
        let entry = VehicleStatusEntry(date: .now, snapshot: VehicleWidgetSnapshotStore.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct ToqdasVehicleStatusWidget: Widget {
    static let kind = VehicleWidgetSnapshot.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: VehicleStatusProvider()) { entry in
            VehicleStatusView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Toqdas Araç Durumu")
        .description("Kilit, batarya, menzil ve bu ayın şarj harcamasını gösterir. Komut göndermez.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct ToqdasWidgetBundle: WidgetBundle {
    var body: some Widget { ToqdasVehicleStatusWidget() }
}

private struct VehicleStatusView: View {
    let snapshot: VehicleWidgetSnapshot?

    private var lockTint: Color {
        guard let snapshot, !snapshot.lockDataIsStale else { return .orange }
        return snapshot.locked == true ? .green : (snapshot.locked == false ? .orange : .secondary)
    }

    var body: some View {
        Group {
            if let snapshot {
                widgetContent(snapshot)
            } else {
                unavailableContent
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(red: 0.025, green: 0.075, blue: 0.13))
    }

    @ViewBuilder
    private func widgetContent(_ snapshot: VehicleWidgetSnapshot) -> some View {
        if contextFamily == .systemMedium {
            mediumContent(snapshot)
        } else {
            smallContent(snapshot)
        }
    }

    @Environment(\.widgetFamily) private var contextFamily

    private func smallContent(_ snapshot: VehicleWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            header(snapshot.vehicleName)
            Label(snapshot.displayLock, systemImage: snapshot.locked == true ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(lockTint)
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                metric("Battery.100", snapshot.displayBattery)
                metric("road.lanes", snapshot.displayRange)
            }
            metric("bolt.car.fill", "Bu ay \(snapshot.displayChargeSpend)")
            freshness(snapshot)
        }
    }

    private func mediumContent(_ snapshot: VehicleWidgetSnapshot) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                header(snapshot.vehicleName)
                Label(snapshot.displayLock, systemImage: snapshot.locked == true ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(lockTint)
                    .lineLimit(1)
                freshness(snapshot)
            }
            Spacer(minLength: 4)
            VStack(alignment: .leading, spacing: 10) {
                metric("Battery.100", snapshot.displayBattery)
                metric("road.lanes", snapshot.displayRange)
                metric("bolt.car.fill", "Bu ay \(snapshot.displayChargeSpend)")
            }
        }
    }

    private var unavailableContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TOQDAS").font(.system(size: 10, weight: .bold)).tracking(1.2)
                .foregroundStyle(Color.cyan)
            Text("Araç verisi yok")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            Text("Uygulamayı açıp araç verilerini yenileyin.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func header(_ name: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(Color.cyan).frame(width: 6, height: 6)
            Text(name.isEmpty ? "Toqdas" : name)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
    }

    private func metric(_ icon: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.cyan)
            Text(value).font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white).lineLimit(1)
        }
    }

    private func freshness(_ snapshot: VehicleWidgetSnapshot) -> some View {
        HStack(spacing: 4) {
            Image(systemName: snapshot.bleReady ? "dot.radiowaves.left.and.right" : "clock")
            Text(freshnessText(snapshot))
        }
        .font(.system(size: 8, weight: .medium))
        .foregroundStyle(snapshot.bleReady && !snapshot.lockDataIsStale ? .white.opacity(0.55) : .orange)
        .lineLimit(1)
    }

    private func freshnessText(_ snapshot: VehicleWidgetSnapshot) -> String {
        guard let date = snapshot.bleUpdatedAt else { return "Kilit bilgisi yok" }
        if snapshot.lockDataIsStale { return "Son BLE: \(date.formatted(date: .omitted, time: .shortened))" }
        return snapshot.bleReady ? "Canlı BLE · \(date.formatted(date: .omitted, time: .shortened))" : "Son BLE · \(date.formatted(date: .omitted, time: .shortened))"
    }
}
