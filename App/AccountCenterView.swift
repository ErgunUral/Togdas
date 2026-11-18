import Foundation
import SwiftUI

struct AccountItem: Identifiable {
    let id: String
    let title: String
    let body: String
    let meta: String
    let isUnread: Bool
    let ticketID: String?
}

private enum AccountKind: Int, CaseIterable {
    case notifications, tickets, subscriptions

    var title: String {
        switch self {
        case .notifications: return "Bildirimler"
        case .tickets: return "Destek"
        case .subscriptions: return "Paketler"
        }
    }

    var emptyText: String {
        switch self {
        case .notifications: return "Yeni bir bildirim geldiğinde burada görünür."
        case .tickets: return "Destek talebi açtığınızda yanıtlar burada listelenir."
        case .subscriptions: return "Aktif bir paket yoksa bu liste boş kalır."
        }
    }

    var emptyTitle: String {
        switch self {
        case .notifications: return "Bildirim yok"
        case .tickets: return "Destek talebi yok"
        case .subscriptions: return "Aktif paket yok"
        }
    }

    var icon: String {
        switch self {
        case .notifications: return "bell"
        case .tickets: return "lifepreserver"
        case .subscriptions: return "shippingbox"
        }
    }
}

/// Superapp bildirim, destek talebi ve paket aboneliklerini gösterir.
/// Yanıt şemaları sürümler arasında değişebildiği için alanlar esnek eşlenir.
struct AccountCenterView: View {
    let api: ToggAPI

    @State private var kind: AccountKind = .notifications
    @State private var items: [AccountItem] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ZStack {
            ToggTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    tabs
                    state
                    ForEach(items) { item in
                        if let ticketID = item.ticketID {
                            NavigationLink {
                                TicketNotesView(ticketId: ticketID, api: api)
                            } label: {
                                itemCard(item)
                            }
                            .buttonStyle(.plain)
                        } else {
                            itemCard(item)
                        }
                    }
                    footer
                }
                .padding(20)
            }
            .refreshable { await load() }
        }
        .navigationTitle("Bildirimler & Destek")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(ToggTheme.teal.opacity(0.2)).frame(width: 40, height: 40)
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 18)).foregroundStyle(ToggTheme.teal)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Hesap Merkezi")
                    .font(ToggTheme.text(.lead, weight: .bold)).foregroundStyle(.white)
                Text("Bildirimler, destek talepleri ve paketler")
                    .font(ToggTheme.text(.micro)).foregroundStyle(DSColor.muted)
            }
            Spacer()
            if loading { ProgressView().tint(ToggTheme.teal) }
        }
        .padding(DSSpace.md)
        .dsCard(.raised)
    }

    private var tabs: some View {
        HStack(spacing: 8) {
            ForEach(Array(AccountKind.allCases), id: \.rawValue) { item in
                Button {
                    guard kind != item else { return }
                    kind = item
                    Task { await load() }
                } label: {
                    Text(item.title)
                        .font(ToggTheme.text(.caption, weight: .bold))
                        .foregroundStyle(kind == item ? .black : .white)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: DSRadius.row, style: .continuous)
                                .fill(kind == item ? DSColor.accent : DSColor.surfaceVariant)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.title) sekmesi")
                .accessibilityValue(kind == item ? "Seçili" : "")
                .accessibilityAddTraits(kind == item ? .isSelected : [])
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text(Self.versionText)
                .font(.caption2.weight(.medium))
                .foregroundStyle(ToggTheme.muted)
                .accessibilityLabel("Uygulama sürümü")
                .accessibilityValue(Self.versionText)
            Text("Reklam ve izleme yok · Ses kaydı saklanmaz")
                .font(.caption2)
                .foregroundStyle(ToggTheme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String,
              let build = info?["CFBundleVersion"] as? String else {
            return "Sürüm bilgisi yok"
        }
        return "Toqdas \(version) (\(build))"
    }

    @ViewBuilder
    private var state: some View {
        if let error {
            EmptyState(
                icon: "exclamationmark.triangle",
                title: "Liste yüklenemedi",
                message: error,
                actionTitle: "Yeniden dene",
                action: { Task { await load() } }
            )
        } else if loading && items.isEmpty {
            VStack(alignment: .leading, spacing: DSSpace.xs) {
                SkeletonRow(height: 16)
                SkeletonRow(height: 12)
                SkeletonRow(height: 12)
            }
            .padding(DSSpace.sm)
            .dsCard()
        } else if items.isEmpty {
            EmptyState(
                icon: kind.icon,
                title: kind.emptyTitle,
                message: kind.emptyText
            )
        }
    }

    private func itemCard(_ item: AccountItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                if item.isUnread {
                    Circle().fill(ToggTheme.teal).frame(width: 7, height: 7).padding(.top, 5)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(ToggTheme.text(.body, weight: .bold)).foregroundStyle(.white)
                        .lineLimit(3)
                    if !item.body.isEmpty {
                        Text(item.body)
                            .font(ToggTheme.text(.caption)).foregroundStyle(DSColor.muted)
                            .lineLimit(4)
                    }
                }
                Spacer(minLength: 4)
                if item.ticketID != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(ToggTheme.muted)
                        .accessibilityHidden(true)
                }
            }
            if !item.meta.isEmpty {
                Text(item.meta)
                    .font(ToggTheme.text(.micro)).foregroundStyle(DSColor.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpace.sm)
        .dsCard(.raised)
    }

    @MainActor
    private func load() async {
        guard !loading else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let data: Data
            switch kind {
            case .notifications: data = try await api.notifications()
            case .tickets: data = try await api.supportTickets()
            case .subscriptions: data = try await api.subscriptions()
            }
            items = AccountFormat.items(from: data, kind: kind, ticket: kind == .tickets)
        } catch {
            items = []
            self.error = error.localizedDescription
        }
    }
}

private enum AccountFormat {
    static func items(from data: Data, kind: AccountKind, ticket: Bool) -> [AccountItem] {
        guard let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let list = dictionaryList(in: root) else { return [] }
        return list.prefix(100).enumerated().map { index, dict in
            let identifier = string(dict, ["id", "_id", "ticketId", "notificationId", "packageId"])
                ?? "item-\(index)"
            let title = string(dict, titleKeys(kind)) ?? defaultTitle(kind)
            let body = string(dict, bodyKeys(kind)) ?? ""
            let status = statusText(dict)
            let date = dateText(dict)
            let meta = [date, status].filter { !$0.isEmpty }.joined(separator: " • ")
            let unread = isUnread(dict)
            return AccountItem(
                id: identifier,
                title: title,
                body: body == title ? "" : body,
                meta: meta,
                isUnread: unread,
                ticketID: ticket ? identifier : nil
            )
        }
    }

    private static func titleKeys(_ kind: AccountKind) -> [String] {
        switch kind {
        case .notifications: return ["title", "subject", "header", "name", "message"]
        case .tickets: return ["subject", "title", "name", "ticketSubject", "description"]
        case .subscriptions: return ["packageName", "name", "productName", "title", "planName"]
        }
    }

    private static func bodyKeys(_ kind: AccountKind) -> [String] {
        switch kind {
        case .notifications: return ["body", "message", "description", "content", "text"]
        case .tickets: return ["description", "message", "body", "lastMessage", "content"]
        case .subscriptions: return ["description", "details", "status", "period"]
        }
    }

    private static func defaultTitle(_ kind: AccountKind) -> String {
        switch kind {
        case .notifications: return "Bildirim"
        case .tickets: return "Destek talebi"
        case .subscriptions: return "Paket"
        }
    }

    private static func dictionaryList(in node: Any, depth: Int = 0) -> [[String: Any]]? {
        guard depth <= 6 else { return nil }
        if let array = node as? [Any] {
            let list = array.compactMap { $0 as? [String: Any] }
            if !list.isEmpty { return list }
        }
        if let dict = node as? [String: Any] {
            let preferred = ["items", "content", "data", "results", "notifications", "tickets", "subscriptions", "list", "records"]
            for key in preferred {
                if let array = dict[key] as? [Any] {
                    let list = array.compactMap { $0 as? [String: Any] }
                    if !list.isEmpty { return list }
                }
            }
            for value in dict.values {
                if let found = dictionaryList(in: value, depth: depth + 1) { return found }
            }
        }
        return nil
    }

    private static func string(_ dict: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
            if let value = dict[key] as? NSNumber {
                return value.stringValue
            }
            if let value = dict[key] as? [String: Any] {
                for nested in ["name", "title", "displayName", "value"] {
                    if let text = value[nested] as? String, !text.isEmpty { return text }
                }
            }
        }
        return nil
    }

    private static func isUnread(_ dict: [String: Any]) -> Bool {
        if let value = dict["isRead"] as? Bool { return !value }
        if let value = dict["read"] as? Bool { return !value }
        if let value = dict["isRead"] as? NSNumber { return value.intValue == 0 }
        if let value = dict["read"] as? NSNumber { return value.intValue == 0 }
        return false
    }

    private static func statusText(_ dict: [String: Any]) -> String {
        guard let status = string(dict, ["status", "state", "ticketStatus", "isActive"]) else { return "" }
        let key = status.lowercased()
        let map = [
            "open": "Açık", "closed": "Kapalı", "resolved": "Çözüldü",
            "pending": "Beklemede", "active": "Aktif", "inactive": "Pasif",
            "true": "Aktif", "false": "Pasif"
        ]
        return map[key] ?? status
    }

    private static func dateText(_ dict: [String: Any]) -> String {
        for key in ["createdAt", "createdDate", "date", "updatedAt", "startDate", "startDateIso", "timestamp"] {
            if let text = dict[key] as? String, !text.isEmpty {
                return prettyDate(text)
            }
            if let number = dict[key] as? NSNumber {
                let seconds = number.doubleValue > 1_000_000_000_000 ? number.doubleValue / 1000 : number.doubleValue
                if seconds > 0 {
                    return Date(timeIntervalSince1970: seconds)
                        .formatted(date: .abbreviated, time: .shortened)
                }
            }
        }
        return ""
    }

    private static func prettyDate(_ text: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: text)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: text)
        }
        if let date {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return text
    }
}
