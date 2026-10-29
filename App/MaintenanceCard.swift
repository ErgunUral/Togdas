import SwiftUI

/// Bakım hatırlatıcıları kartı.
///
/// Kayıtlar VIN bazlı `MaintenanceStore` içinde tutulur; kart kendi giriş
/// alanlarını ve hata mesajını yönetir. Bildirimler yalnız uygulama açıkken
/// ve 500 km eşiğinde `MaintenanceNotifier` üzerinden gönderilir.
struct MaintenanceCard: View {
    let vin: String
    let odometer: Double?

    @State private var title = ""
    @State private var dueKm = ""
    @State private var items: [MaintenanceItem] = []
    @State private var error: String?

    private var store: MaintenanceStore { MaintenanceStore(vin: vin) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Bakım Hatırlatıcıları", systemImage: "wrench.and.screwdriver")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                Spacer()
                if let odometer {
                    Text("\(Int(odometer.rounded())) km")
                        .font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
                }
            }

            if items.isEmpty {
                Text("Henüz bakım kaydı yok. Aşağıdan ekleyin.")
                    .font(.caption2).foregroundStyle(ToggTheme.muted)
            }

            ForEach(items) { item in
                HStack(spacing: 8) {
                    Image(systemName: item.done ? "checkmark.circle.fill"
                          : (isOverdue(item) ? "exclamationmark.triangle.fill" : "circle"))
                        .font(.system(size: 13))
                        .foregroundStyle(item.done ? ToggTheme.green
                                         : (isOverdue(item) ? ToggTheme.orange : ToggTheme.muted))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.caption).strikethrough(item.done)
                            .foregroundStyle(item.done ? ToggTheme.muted : .white)
                        Text(subtitle(for: item))
                            .font(.system(size: 9)).foregroundStyle(ToggTheme.muted)
                    }
                    Spacer()
                    if !item.done {
                        Button("Tamam") { complete(item) }
                            .font(.system(size: 10, weight: .semibold)).buttonStyle(.bordered)
                            .accessibilityLabel("\(item.title) bakımını tamamlandı olarak işaretle")
                    }
                    Button {
                        delete(item)
                    } label: {
                        Image(systemName: "trash").font(.system(size: 10))
                    }
                    .buttonStyle(.plain).foregroundStyle(ToggTheme.muted)
                    .accessibilityLabel("\(item.title) bakımını sil")
                }
                .accessibilityElement(children: .contain)
            }

            Divider().overlay(ToggTheme.muted.opacity(0.2))

            HStack(spacing: 6) {
                TextField("Bakım adı", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                TextField("km", text: $dueKm)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(width: 78)
                Button {
                    add()
                } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ToggTheme.teal)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || Double(dueKm) == nil)
                .accessibilityLabel("Bakım ekle")
            }

            if let error {
                Text(error).font(.system(size: 9)).foregroundStyle(ToggTheme.pink)
                    .accessibilityLabel("Hata: \(error)")
            } else {
                Text("Bakım km'sine 500 km kalınca uygulama açıkken bildirim gönderilir.")
                    .font(.system(size: 9)).foregroundStyle(ToggTheme.muted)
            }
        }
        .padding(18).toggCardBackground()
        .onAppear { reload() }
        .onChange(of: odometer) { _ in reload() }
    }

    private func reload() {
        items = store.items
        guard let odometer else { return }
        let due = items.filter { !$0.done && $0.remainingKm(currentOdometer: odometer) <= 500 }
        guard !due.isEmpty else { return }
        MaintenanceNotifier.notify(items: due, odometer: odometer, vin: vin)
    }

    private func add() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard let km = Double(dueKm.replacingOccurrences(of: ",", with: ".")), km > 0 else {
            error = "Geçerli bir km girin."
            return
        }
        if let odometer, km <= odometer {
            error = "Bakım km'si mevcut km'den büyük olmalı (\(Int(odometer.rounded())) km)."
            return
        }
        error = nil
        store.add(title: trimmed, dueKm: km)
        title = ""
        dueKm = ""
        MaintenanceNotifier.requestAuthorization()
        reload()
    }

    private func complete(_ item: MaintenanceItem) {
        store.markDone(item.id, atOdometer: odometer)
        MaintenanceNotifier.cancel(itemIDs: [item.id], vin: vin)
        reload()
    }

    private func delete(_ item: MaintenanceItem) {
        store.remove(item.id)
        MaintenanceNotifier.cancel(itemIDs: [item.id], vin: vin)
        reload()
    }

    private func isOverdue(_ item: MaintenanceItem) -> Bool {
        guard let odometer else { return false }
        return item.dueKm <= odometer
    }

    private func subtitle(for item: MaintenanceItem) -> String {
        if item.done {
            if let km = item.completedAtKm { return "Tamamlandı · \(Int(km.rounded())) km" }
            return "Tamamlandı"
        }
        guard let odometer else { return "Bakım: \(Int(item.dueKm.rounded())) km · güncel km bilinmiyor" }
        let remaining = item.remainingKm(currentOdometer: odometer)
        if remaining <= 0 { return "Gecikti · \(Int((odometer - item.dueKm).rounded())) km geçti" }
        return "Bakım: \(Int(item.dueKm.rounded())) km · \(Int(remaining.rounded())) km kaldı"
    }
}
