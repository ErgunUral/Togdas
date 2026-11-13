// Erişilebilirlik denetimi (kalıcı): yeni dokunma hedefi, etiket ve kırpma
// sorunlarını yakalar.
//
// Kapsam bilinçli olarak sınırlı:
// - `.dynamicType` hariç: uygulama Dynamic Type'ı `xxxLarge` ile sınırlıyor
//   (kasıtlı tasarım kararı); ayrı XXXL kullanılabilirlik testi var.
// - `.contrast` hariç: koyu tema tokenları WCAG AA üstünde (elle ölçüldü,
//   Docs/Erisilebilirlik.md); otomatik kontrast denetimi SwiftUI
//   malzemelerinde yanlış pozitif üretiyor.
// Denetim 2026-11-13'te 165 bulgu verdi: 134 Dynamic Type (kapsam dışı),
// 10 kontrast (kapsam dışı), 4 dokunma hedefi, 9 okunamayan ikon etiketi,
// 4 kırpılmış metin — son 17'si düzeltildi.

import XCTest

@available(iOS 17.0, *)
final class ToqdasAccessibilityAuditTests: ToqdasUITestCase {
    private let auditTypes: XCUIAccessibilityAuditType = [
        .hitRegion,
        .sufficientElementDescription,
        .textClipped,
        .trait
    ]

    private func audit(_ app: XCUIApplication) throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit iOS 17+") }
        try app.performAccessibilityAudit(for: auditTypes) { issue in
            // Öğesi olmayan bulgular eylem verilemez (Xcode gürültüsü).
            issue.element == nil
        }
    }

    func testOverviewHasNoNewAuditIssues() throws {
        let app = launchFixture()
        DashboardScreen(app: app).waitForLoad()
        try audit(app)
    }

    func testTabsHaveNoNewAuditIssues() throws {
        let app = launchFixture()
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        for tab in ["İklimlendirme", "Trugo Şarj", "Araç Durumu"] {
            dashboard.selectTab(tab)
            try audit(app)
        }
    }

    func testScenarioGuideHasNoNewAuditIssues() throws {
        let app = launchFixture()
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        dashboard.openMenu().openScenarioGuide()
        try audit(app)
    }

    func testCommandsSheetHasNoNewAuditIssues() throws {
        let app = launchFixture(["-openCommands"])
        CommandSheet(app: app).waitForOpen()
        try audit(app)
    }
}
