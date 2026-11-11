// Giriş ekranı (Togg ID ile giriş)
// DashboardView'dan ayrıldı (2026-11-12) — yalnız taşıma; davranış değişikliği yok.

import SwiftUI

struct LoginView: View {
    @ObservedObject var model: GarageModel

    var body: some View {
        ZStack {
            ToggTheme.background.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                VStack(spacing: 10) {
                    Text("TRUMORE")
                        .font(.system(size: 40, weight: .black))
                        .tracking(4)
                        .foregroundStyle(ToggTheme.teal)
                    Text("Togg dijital anahtar ve araç kontrolü")
                        .font(.subheadline).foregroundStyle(ToggTheme.muted)
                }
                VStack(spacing: 12) {
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 70)).foregroundStyle(ToggTheme.teal.opacity(0.8))
                    Text("Aracınıza bağlanmak için Togg ID ile giriş yapın.")
                        .font(.footnote).foregroundStyle(ToggTheme.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(28)
                .frame(maxWidth: .infinity)
                .toggCardBackground()

                Button {
                    Task { await model.login() }
                } label: {
                    HStack {
                        Image(systemName: "person.badge.key.fill")
                        Text("Togg ID ile giriş yap")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(RoundedRectangle(cornerRadius: 18).fill(ToggTheme.teal))
                }
                .buttonStyle(.plain)
                .disabled(model.busy)
                .accessibilityIdentifier("login.toggButton")

                if model.busy { ProgressView().tint(ToggTheme.teal) }
                if let facingError = model.facingError {
                    ErrorBanner(error: facingError,
                                onRetry: { Task { await model.refresh() } },
                                onDismiss: { model.facingError = nil })
                }
                Spacer()
                Text("Togg ID ve araç bilgileri üretim servislerini kullanır.")
                    .font(.caption2).foregroundStyle(ToggTheme.muted)
            }
            .padding(24)
        }
    }
}
