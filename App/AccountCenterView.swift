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
        case .notifications: return "Bildirim bulunmuyor."
        case .tickets: return "Destek talebi bulunmuyor."
        case .subscriptions: return "Aktif paket bulunmuyor."
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
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Hesap Merkezi")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                Text("Bildirimler, destek talepleri ve paketler")
                    .font(.system(size: 11)).foregroundStyle(ToggTheme.muted)
            }
            Spacer()
            if loading { ProgressView().tint(ToggTheme.teal) }
        }
        .padding(16)
        .toggCardBackground(20)
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
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(kind == item ? .black : .white)
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(kind == item ? ToggTheme.teal : ToggTheme.surfaceVariant)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var state: some View {
        if let error {
            Text(error)
                .font(.footnote).foregroundStyle(ToggTheme.pink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if items.isEmpty && !loading && error == nil {
            Text(kind.emptyText)
                .font(.footnote).foregroundStyle(ToggTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        .lineLimit(3)
                    if !item.body.isEmpty {
                        Text(item.body)
                            .font(.system(size: 12)).foregroundStyle(ToggTheme.muted)
                            .lineLimit(4)
                    }
                }
                Spacer(minLength: 4)
                if item.ticketID != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(ToggTheme.muted)
                }
            }
            if !item.meta.isEmpty {
                Text(item.meta)
                    .font(.system(size: 10)).foregroundStyle(ToggTheme.teal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .toggCardBackground(18)
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
