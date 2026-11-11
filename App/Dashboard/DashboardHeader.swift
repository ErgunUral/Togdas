// Başlık (e-posta, araç, telemetri durumu, menüler)
// DashboardView'dan ayrıldı (2026-11-12) — yalnız taşıma; davranış değişikliği yok.

import SwiftUI

// MARK: - Başlık

struct DashboardHeader: View {
    let email: String
    let vehicle: Vehicle
    let badge: String
    let connected: Bool
    let updatedAt: Date?
    let location: String?
    let busy: Bool
    let vehicles: [Vehicle]
    let selectedVin: String?
    let onSelectVehicle: (Vehicle) -> Void
    let onRefresh: () -> Void
    let onOpenVoice: () -> Void
    let onOpenCommands: () -> Void
    let onOpenService: () -> Void
    let onOpenExperience: () -> Void
    let onOpenAccount: () -> Void
    let onOpenDetail: () -> Void
    let onOpenDiscovery: () -> Void
    let onLogout: () -> Void
    @Binding var themeName: String
    @Binding var layoutName: String

    private var telemetryIsFresh: Bool {
        guard let updatedAt else { return false }
        return Date().timeIntervalSince(updatedAt) < 300
    }

    private var telemetryColor: Color {
        telemetryIsFresh ? ToggTheme.green : ToggTheme.orange
    }

    private var telemetryLabel: String {
        telemetryIsFresh ? "Canlı Telemetri" : "Son Telemetri"
    }

    private var updatedText: String {
        guard let updatedAt else { return "• henüz okunmadı" }
        if Calendar.current.isDateInToday(updatedAt) {
            return "• \(updatedAt.formatted(date: .omitted, time: .shortened))"
        }
        return "• \(updatedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute()))"
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 15)).foregroundStyle(ToggTheme.teal)
                    Text(email)
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(ToggTheme.teal)
                        .lineLimit(1)
                }
                Spacer()
                Text("Togg ID Aktif")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(ToggTheme.green)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(ToggTheme.green.opacity(0.15)))

                Button(action: onOpenVoice) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ToggTheme.teal)
                        .frame(width: 34, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8).fill(ToggTheme.surfaceVariant))
                }
                .accessibilityLabel("Sesli komut")
            }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("TRUMORE")
                            .font(.system(size: 22, weight: .black))
                            .tracking(2)
                            .foregroundStyle(ToggTheme.teal)
                        Text(badge)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: 0x86F8F0))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(ToggTheme.tealContainer))
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "car.side.fill")
                            .font(.system(size: 12)).foregroundStyle(ToggTheme.teal)
                        Text("\(vehicle.title) • \(vehicle.plate.isEmpty ? vehicle.vin : vehicle.plate)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ToggTheme.muted)
                            .lineLimit(1)
                    }
                    if vehicle.isShared {
                        Label("Paylaşılan araç · sahip devri yok", systemImage: "person.2.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(ToggTheme.teal)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(connected ? (telemetryIsFresh ? ToggTheme.green : ToggTheme.orange) : ToggTheme.pink)
                            .frame(width: 7, height: 7)
                        Image(systemName: "wifi").font(.system(size: 12)).foregroundStyle(ToggTheme.teal)
                        Text(connected ? (telemetryIsFresh ? "Aracım Bağlı" : "Son Veri") : "Veri yok")
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Capsule().fill(ToggTheme.surfaceVariant))

                    Menu {
                        if vehicles.count > 1 {
                            Menu("Araç seç", systemImage: "car.2.fill") {
                                ForEach(vehicles) { item in
                                    Button {
                                        onSelectVehicle(item)
                                    } label: {
                                        if item.vin == selectedVin {
                                            Label(item.isShared ? "\(item.title) · Paylaşılan" : item.title,
                                                  systemImage: item.isShared ? "person.2.fill" : "checkmark")
                                        } else {
                                            Text(item.isShared ? "\(item.title) · Paylaşılan" : item.title)
                                        }
                                    }
                                }
                            }
                            Divider()
                        }
                        Button("Araç detayı", systemImage: "info.circle") { onOpenDetail() }
                        Button("Servis kartı", systemImage: "wrench.and.screwdriver") { onOpenService() }
                        Button("Seyahatname", systemImage: "chart.xyaxis.line") { onOpenExperience() }
                        Button("Bildirimler & destek", systemImage: "bell.badge") { onOpenAccount() }
                        Button("Bluetooth komutları", systemImage: "key.horizontal") { onOpenCommands() }
                        Button("Bluetooth taraması", systemImage: "dot.radiowaves.left.and.right") { onOpenDiscovery() }
                        Picker("Renk teması", selection: $themeName) {
                            ForEach(ToggThemeStyle.allCases) { style in
                                Text(style.title).tag(style.rawValue)
                            }
                        }
                        Picker("Dashboard düzeni", selection: $layoutName) {
                            ForEach(DashboardLayoutStyle.allCases) { layout in
                                Text("\(layout.title) · \(layout.subtitle)").tag(layout.rawValue)
                            }
                        }
                        Divider()
                        Button("Çıkış yap", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { onLogout() }
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(ToggTheme.teal)
                            .frame(width: 32, height: 32)
                    }
                }
            }

            Button(action: onRefresh) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: telemetryIsFresh
                              ? "sensor.tag.radiowaves.forward.fill"
                              : "clock.arrow.circlepath")
                            .font(.system(size: 13)).foregroundStyle(telemetryColor)
                        Text(telemetryLabel)
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(telemetryColor)
                        Text(updatedText)
                            .font(.system(size: 11)).foregroundStyle(ToggTheme.muted)
                    }
                    Spacer()
                    if busy {
                        ProgressView().tint(ToggTheme.teal).scaleEffect(0.8)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 11)).foregroundStyle(ToggTheme.teal)
                            Text(location ?? "Konum yok")
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(.white)
                                .lineLimit(1).minimumScaleFactor(0.75)
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(ToggTheme.surfaceVariant))
            }
            .buttonStyle(.plain)
        }
    }
}
