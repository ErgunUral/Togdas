import SwiftUI

struct ServiceView: View {
    let vehicle: Vehicle
    let api: ToggAPI
    @State private var data = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        List {
            Section("Servis kartı") {
                if busy { ProgressView() }
                if let error { Text(error).foregroundStyle(.red) }
                if !data.isEmpty {
                    Text(data).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                Button("Servis kartını yenile") { Task { await refresh() } }
                    .disabled(busy)
            }
        }
        .navigationTitle("Servis kartı")
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    @MainActor
    private func refresh() async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let bytes = try await api.serviceCards(for: vehicle.vin)
            let formatted = try JSONSerialization.data(withJSONObject: try JSONSerialization.jsonObject(with: bytes),
                                                       options: [.prettyPrinted, .sortedKeys])
            data = String(decoding: formatted, as: UTF8.self)
        } catch { self.error = error.localizedDescription }
    }
}

struct TicketNotesView: View {
    let ticketId: String
    let api: ToggAPI
    @State private var data = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        List {
            Section("Destek notları") {
                if busy { ProgressView() }
                if let error { Text(error).foregroundStyle(.red) }
                if !data.isEmpty {
                    Text(data).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                Button("Notları yenile") { Task { await refresh() } }
                    .disabled(busy)
            }
        }
        .navigationTitle("Destek notları")
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    @MainActor
    private func refresh() async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let bytes = try await api.ticketNotes(for: ticketId)
            let formatted = try JSONSerialization.data(withJSONObject: try JSONSerialization.jsonObject(with: bytes),
                                                       options: [.prettyPrinted, .sortedKeys])
            data = String(decoding: formatted, as: UTF8.self)
        } catch { self.error = error.localizedDescription }
    }
}
