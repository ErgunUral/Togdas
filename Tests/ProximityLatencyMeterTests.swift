import XCTest
@testable import ToqdasCore

/// `ProximityLatencyMeter`: Android .57 yaklaşma latency paritesinin
/// iOS çekirdek testleri. Sayaca göre eksik veri `nil` kalır, asla 0 olmaz.
final class ProximityLatencyMeterTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_791_000_000)

    func testNoBaselineYieldsNilLatencyNotZero() {
        var meter = ProximityLatencyMeter()
        meter.noteSample()
        meter.noteSample()
        let reading = meter.noteApproachDecision(now: base)
        XCTAssertNil(reading.cycleLatencyMs)
        XCTAssertEqual(reading.samples, 2)
    }

    func testBaselineToDecisionLatencyMeasuredInMilliseconds() {
        var meter = ProximityLatencyMeter()
        meter.noteBaseline(now: base)
        meter.noteSample() // t + 2 sn
        meter.noteSample() // t + 4 sn
        let reading = meter.noteApproachDecision(now: base.addingTimeInterval(4.12))
        XCTAssertEqual(reading.cycleLatencyMs, 4120)
        XCTAssertEqual(reading.samples, 2)
    }

    func testNegativeIntervalClampsToZero() {
        var meter = ProximityLatencyMeter()
        meter.noteBaseline(now: base)
        XCTAssertEqual(
            ProximityLatencyMeter.latencyMs(from: base.addingTimeInterval(1), to: base),
            0
        )
    }

    func testDepartureStartsNewBaselineAndResetsSamples() {
        var meter = ProximityLatencyMeter()
        meter.noteBaseline(now: base)
        meter.noteSample()
        meter.noteDepartureDecision(now: base.addingTimeInterval(30))
        // Yeni döngü: örnek sayacı sıfırlandı, yeni karar tabanı yeni zaman.
        let reading = meter.noteApproachDecision(now: base.addingTimeInterval(35))
        XCTAssertEqual(reading.cycleLatencyMs, 5000)
        XCTAssertEqual(reading.samples, 0)
    }

    func testExpectedIntervalUsesRequiredSamplesTimesPollInterval() {
        for profile in ProximityProfile.allCases {
            XCTAssertEqual(
                ProximityLatencyMeter.Reading.expectedInterval(for: profile),
                Double(profile.requiredSamples) * profile.pollInterval
            )
        }
    }

    func testApproachDecisionDoesNotRestartBaseline() {
        var meter = ProximityLatencyMeter()
        meter.noteBaseline(now: base)
        _ = meter.noteApproachDecision(now: base.addingTimeInterval(2))
        let second = meter.noteApproachDecision(now: base.addingTimeInterval(5))
        XCTAssertEqual(second.cycleLatencyMs, 5000)
        let third = meter.noteApproachDecision(now: base.addingTimeInterval(6))
        XCTAssertEqual(third.cycleLatencyMs, 6000)
    }
}
