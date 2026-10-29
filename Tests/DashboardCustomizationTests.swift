import XCTest
@testable import ToqdasCore

final class DashboardCustomizationTests: XCTestCase {
    func testDefaultCustomOrderContainsAllOptionalCards() {
        XCTAssertEqual(DashboardCustomization.default.visibleCards, DashboardCustomization.defaultOrder)
        XCTAssertEqual(Set(DashboardCustomization.default.order), Set(DashboardCard.allCases))
    }

    func testVisibilityCanBeCustomizedWithoutDroppingCardOrder() {
        var settings = DashboardCustomization.default
        settings.setVisible(false, for: .proximity)
        XCTAssertFalse(settings.isVisible(.proximity))
        XCTAssertEqual(settings.order, DashboardCustomization.defaultOrder)

        settings.setVisible(true, for: .proximity)
        XCTAssertTrue(settings.isVisible(.proximity))
    }

    func testMoveReordersCardsAndClampsAtBounds() {
        var settings = DashboardCustomization.default
        settings.move(.chargingShortcut, offset: -20)
        XCTAssertEqual(settings.order.first, .chargingShortcut)
        settings.move(.quickActions, offset: 20)
        XCTAssertEqual(settings.order.last, .quickActions)
    }

    func testLoadCompletesCardsAddedByLaterVersions() throws {
        let partial = DashboardCustomization(order: [.technical], hidden: [.quickActions])
        let data = try JSONEncoder().encode(partial)
        let decoded = try JSONDecoder().decode(DashboardCustomization.self, from: data)
        let restored = DashboardCustomization(order: decoded.order, hidden: decoded.hidden)
        XCTAssertEqual(Set(restored.order), Set(DashboardCard.allCases))
        XCTAssertFalse(restored.isVisible(.quickActions))
        XCTAssertTrue(restored.isVisible(.proximity))
    }
}
