import SwiftUI

/// Merkezi hata gösterimi: başlık, açıklama, öneri ve isteğe bağlı "Tekrar dene".
struct ErrorBanner: View {
    let error: UserFacingError
    var onRetry: (() -> Void)?
    var onDismiss: (() -> Void)?

    @State private var showDetail = false

    private var accent: Color {
        switch error.kind {
        case .network, .server, .vehicleAsleep: return ToggTheme.orange
        case .authentication, .permission, .certificate: return ToggTheme.pink
        case .bleNotReady: return ToggTheme.teal
        case .cancelled, .unknown: return ToggTheme.muted
        }
    }

    private var icon: String {
        switch error.kind {
        case .network: return "wifi.exclamationmark"
        case .authentication: return "person.crop.circle.badge.exclamationmark"
        case .certificate: return "key.slash"
        case .vehicleAsleep: return "car.side.rear.open"
        case .bleNotReady: return "dot.radiowaves.left.and.right"
        case .permission: return "hand.raised.slash"
        case .server: return "exclamationmark.icloud"
        case .cancelled: return "xmark.circle"
        case .unknown: return "exclamationmark.triangle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(error.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Text(error.message)
                        .font(.system(size: 11))
                        .foregroundStyle(ToggTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(ToggTheme.muted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hatayı kapat")
                }
            }

            if let recovery = error.recovery {
                Text(recovery)
                    .font(.system(size: 10))
                    .foregroundStyle(ToggTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if error.isRetryable, let onRetry {
                    Button("Tekrar dene", action: onRetry)
                        .font(.system(size: 11, weight: .semibold))
                        .buttonStyle(.bordered)
                        .tint(accent)
                }
                if let detail = error.technicalDetail {
                    Button(showDetail ? "Ayrıntıyı gizle" : "Ayrıntı") {
                        showDetail.toggle()
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundStyle(ToggTheme.muted)
                }
            }

            if showDetail, let detail = error.technicalDetail {
                Text(detail)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(ToggTheme.muted)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(accent.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent.opacity(0.3), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}
