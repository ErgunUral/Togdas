import XCTest
@testable import ToqdasCore

final class ExperienceExportTests: XCTestCase {
    private func record(_ id: String, kind: ExperienceKind = .charges,
                        date: String = "1 Ekim", subtitle: String = "İstasyon",
                        metrics: [ExperienceMetric]) -> ExperienceRecord {
        ExperienceRecord(id: id, detailID: nil, kind: kind, dateText: date,
                         subtitle: subtitle, metrics: metrics)
    }

    func testCSVUsesUnionOfMetricsInFirstSeenOrder() {
        let records = [
            record("1", metrics: [ExperienceMetric(label: "Enerji", value: "10 kWh"),
                                  ExperienceMetric(label: "Tutar", value: "100 ₺")]),
            record("2", metrics: [ExperienceMetric(label: "Tutar", value: "200 ₺"),
                                  ExperienceMetric(label: "Tür", value: "Hızlı şarj")])
        ]
        let csv = ExperienceExport.csv(records: records)
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"))
        let lines = csv.dropFirst().split(separator: "\r\n").map(String.init)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "Tür;Tarih;Konum/Rota;Enerji;Tutar;Tür")
        XCTAssertEqual(lines[1], "Şarj;1 Ekim;İstasyon;10 kWh;100 ₺;")
        XCTAssertEqual(lines[2], "Şarj;1 Ekim;İstasyon;;200 ₺;Hızlı şarj")
    }

    func testCSVEscapesSeparatorQuoteAndNewline() {
        let records = [
            record("1", subtitle: "A; B \"istasyon\"\nyeni", metrics: [])
        ]
        let csv = ExperienceExport.csv(records: records)
        let line = csv.dropFirst().split(separator: "\r\n", omittingEmptySubsequences: false)
            .map(String.init)
        XCTAssertEqual(line[1], "Şarj;1 Ekim;\"A; B \"\"istasyon\"\"\nyeni\"")
    }

    func testCSVEmptyRecordsKeepsHeader() {
        let csv = ExperienceExport.csv(records: [])
        XCTAssertEqual(csv, "\u{FEFF}Tür;Tarih;Konum/Rota\r\n")
    }

    func testJourneyKindLabelAndFilename() {
        let records = [record("1", kind: .journeys, metrics: [])]
        let csv = ExperienceExport.csv(records: records)
        XCTAssertTrue(csv.contains("Yolculuklar;1 Ekim"))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 29))!
        XCTAssertEqual(ExperienceExport.filename(kind: .charges, anchor: "2026-10"),
                       "Seyahatname-sarj-2026-10.csv")
        XCTAssertEqual(ExperienceExport.filename(kind: .journeys, anchor: nil, date: date),
                       "Seyahatname-yolculuk-2026-10-29.csv")
        XCTAssertEqual(ExperienceExport.filename(kind: .charges, anchor: "2026 / Ekim"),
                       "Seyahatname-sarj-2026-ekim.csv")
    }
}
