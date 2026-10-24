import SwiftUI

@main
struct ToqdasWatchApp: App {
    @StateObject private var link = WatchLink()
    var body: some Scene {
        WindowGroup { WatchGarageView(link: link) }
    }
}

struct WatchGarageView: View {
    @ObservedObject var link: WatchLink
    @StateObject private var bluetooth = BluetoothDiscovery()
    @Environment(\.scenePhase) private var phase

    var body: some View {
        NavigationStack {
            List {
                Label("Toqdas", systemImage: "car.side.fill")
                Text(link.status).font(.caption2)
                if link.vehicleNames.isEmpty { Text("iPhone’da giriş yapıp araçları yenileyin.").font(.caption) }
                ForEach(Array(link.vehicleNames.enumerated()), id: \.offset) { _, name in Text(name) }
                if let date = link.updatedAt {
                    Text("Son eşitleme: \(date.formatted(date: .omitted, time: .shortened))").font(.caption2)
                }
                Section("Saatten Bluetooth") {
                    Text(bluetooth.status).font(.caption2)
                    Button(bluetooth.scanning ? "Durdur" : "Araç servisini tara") {
                        bluetooth.scanning ? bluetooth.stop() : bluetooth.start()
                    }.disabled(bluetooth.activeDeviceID != nil)
                    ForEach(bluetooth.devices) { device in
                        Button { bluetooth.connect(to: device.id) } label: {
                            VStack(alignment: .leading) {
                                Text(device.name)
                                Text("\(device.rssi) dBm • Bağlan").font(.caption2)
                            }
                        }.disabled(bluetooth.activeDeviceID != nil)
                    }
                    if bluetooth.activeDeviceID != nil {
                        ForEach(bluetooth.channels, id: \.self) { Text($0).font(.caption2) }
                        if let rssi = bluetooth.connectionRSSI { Text("Sinyal: \(rssi) dBm").font(.caption2) }
                        Button("Sinyali yenile") { bluetooth.refreshRSSI() }.disabled(!bluetooth.discoveryComplete)
                        Button("Bağlantıyı kes") { bluetooth.disconnect() }
                    }
                }
                Text("Kilit kontrolü geliştirme aşamasında. Yakınlık taraması kilit komutu göndermez.").font(.caption2)
            }
            .navigationTitle("Garajım")
            .onChange(of: phase) { if $0 == .background { bluetooth.shutdown() } }
            .onDisappear { bluetooth.shutdown() }
        }
    }
}
