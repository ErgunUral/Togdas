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
    let onOpenScenarioGuide: () -> Void
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
                        .font(ToggTheme.text(.lead)).foregroundStyle(ToggTheme.teal)
                    Text(email)
                        .font(ToggTheme.text(.caption, weight: .bold)).foregroundStyle(ToggTheme.teal)
                        .lineLimit(1)
                }
                Spacer()
                Text("Togg ID Aktif")
                    .font(ToggTheme.text(.micro, weight: .bold))
                    .foregroundStyle(ToggTheme.green)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(ToggTheme.green.opacity(0.15)))

                Button(action: onOpenVoice) {
                    Image(systemName: "mic.fill")
                        .font(ToggTheme.text(.body, weight: .bold))
                        .foregroundStyle(ToggTheme.teal)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 10).fill(ToggTheme.surfaceVariant))
                }
                .accessibilityLabel("Sesli komut")
                .accessibilityHint("Sesli asistan ekranını açar")
            }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("TRUMORE")
                            .font(ToggTheme.text(.title, weight: .black))
                            .tracking(2)
                            .foregroundStyle(ToggTheme.teal)
                        Text(badge)
                            .font(ToggTheme.text(.caption, weight: .bold))
                            .foregroundStyle(Color(hex: 0x86F8F0))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(ToggTheme.tealContainer))
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "car.side.fill")
                            .font(ToggTheme.text(.caption)).foregroundStyle(ToggTheme.teal)
                        Text("\(vehicle.title) • \(vehicle.plate.isEmpty ? vehicle.vin : vehicle.plate)")
                            .font(ToggTheme.text(.caption, weight: .semibold))
                            .foregroundStyle(ToggTheme.muted)
                            .lineLimit(1)
                    }
                    if vehicle.isShared {
                        Label("Paylaşılan araç · sahip devri yok", systemImage: "person.2.fill")
                            .font(ToggTheme.text(.micro, weight: .semibold))
                            .foregroundStyle(ToggTheme.teal)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(connected ? (telemetryIsFresh ? ToggTheme.green : ToggTheme.orange) : ToggTheme.pink)
                            .frame(width: 7, height: 7)
                        Image(systemName: "wifi").font(ToggTheme.text(.caption)).foregroundStyle(ToggTheme.teal)
                        Text(connected ? (telemetryIsFresh ? "Aracım Bağlı" : "Son Veri") : "Veri yok")
                            .font(ToggTheme.text(.caption, weight: .bold)).foregroundStyle(.white)
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
                        Button("Senaryolar rehberi", systemImage: "book") { onOpenScenarioGuide() }
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
                            .font(ToggTheme.text(.lead))
                            .foregroundStyle(ToggTheme.teal)
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityIdentifier("header.menu")
                }
            }

            Button(action: onRefresh) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: telemetryIsFresh
                              ? "sensor.tag.radiowaves.forward.fill"
                              : "clock.arrow.circlepath")
                            .font(ToggTheme.text(.body)).foregroundStyle(telemetryColor)
                        Text(telemetryLabel)
                            .font(ToggTheme.text(.caption, weight: .bold)).foregroundStyle(telemetryColor)
                        Text(updatedText)
                            .font(ToggTheme.text(.caption)).foregroundStyle(ToggTheme.muted)
                    }
                    Spacer()
                    if busy {
                        ProgressView().tint(ToggTheme.teal).scaleEffect(0.8)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(ToggTheme.text(.caption)).foregroundStyle(ToggTheme.teal)
                            Text(location ?? "Konum yok")
                                .font(ToggTheme.text(.micro, weight: .medium)).foregroundStyle(.white)
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
