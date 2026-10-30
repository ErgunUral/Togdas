import XCTest
@testable import ToqdasCore

final class ExperienceFormatTests: XCTestCase {
    func testDashboardMapsPeriodsComparisonAndHighlights() throws {
        let data = Data(#"""
        {
          "this_month": {
            "total_distance_km": 842.4,
            "journey_count": 31,
            "total_duration_min": 1234,
            "avg_consumption_per_100km": 17.25,
            "avg_speed_kmh": 41.2,
            "avg_economy_score": 78,
            "total_kwh_consumed": 145.3,
            "monthly_charges": 4,
            "total_kwh_added": 210.6,
            "preferred_mode": "COMFORT",
            "air_condition": "LOW",
            "charging_type": "AC"
          },
          "last_month": {"total_distance_km": 710.2, "journey_count": 26},
          "last_month_calendar": {"total_distance_km": 655.1},
          "all_time": {
            "total_distance_km": 12345.6,
            "journey_count": 400,
            "total_kwh_added": 2500,
            "avg_economy_score": 81.4
          },
          "community_comparison": {
            "avg_consumption_per_100km": {"you": 17.25, "community": 19.4},
            "total_journeys": {"you": 31, "community": 28},
            "monthly_charges": {"you": 4, "community": 6}
          },
          "last_journey": {
            "journey_id": "j1",
            "start_ts": 1729600000000,
            "total_distance_km": 24.6,
            "total_kwh_consumed": 4.1,
            "start_location": {"name": "Ev"},
            "end_location": {"name": "Ofis"}
          },
          "last_charge": {
            "charge_id": "c1",
            "start_ts": "2026-10-22T20:18:00Z",
            "kwh_added": 32.5,
            "soc_start_pct": 18,
            "soc_end_pct": 80
          }
        }
        """#.utf8)
        let dashboard = try XCTUnwrap(ExperienceFormat.dashboard(from: data))
        XCTAssertEqual(dashboard.sections.map(\.id), ["this_month", "last_month", "last_month_calendar", "all_time"])
        XCTAssertEqual(dashboard.sections.map(\.title), ["Son 30 gün", "Önceki dönem", "Önceki takvim ayı", "Tüm zamanlar"])
        let month = dashboard.sections[0]
        XCTAssertEqual(month.distanceKM ?? 0, 842.4, accuracy: 0.001)
        XCTAssertEqual(month.journeyCount ?? 0, 31)
        XCTAssertEqual(month.durationMinutes ?? 0, 1234)
        XCTAssertEqual(month.averageConsumption ?? 0, 17.25, accuracy: 0.001)
        XCTAssertEqual(month.economyScore ?? 0, 78)
        XCTAssertEqual(month.totalConsumptionKWh ?? 0, 145.3, accuracy: 0.001)
        XCTAssertEqual(month.averageSpeedKMH ?? 0, 41.2, accuracy: 0.001)
        XCTAssertEqual(month.chargeCount ?? 0, 4)
        XCTAssertEqual(month.addedEnergyKWh ?? 0, 210.6, accuracy: 0.001)
        XCTAssertEqual(month.preferredMode, "Konfor")
        XCTAssertEqual(month.airCondition, "Düşük")
        XCTAssertEqual(month.chargingType, "AC")

        XCTAssertEqual(dashboard.comparisons.count, 3)
        let consumption = try XCTUnwrap(dashboard.comparisons.first(where: { $0.id == "avg_consumption_per_100km" }))
        XCTAssertEqual(consumption.you ?? 0, 17.25, accuracy: 0.001)
        XCTAssertEqual(consumption.community ?? 0, 19.4, accuracy: 0.001)
        XCTAssertTrue(consumption.lowerIsBetter)

        let lastJourney = try XCTUnwrap(dashboard.lastJourney)
        XCTAssertEqual(lastJourney.detailID, "j1")
        XCTAssertEqual(lastJourney.kind, .journeys)
        XCTAssertTrue(lastJourney.detailText.contains("24,6 km"))
        XCTAssertFalse(lastJourney.dateText.isEmpty)

        let lastCharge = try XCTUnwrap(dashboard.lastCharge)
        XCTAssertEqual(lastCharge.detailID, "c1")
        XCTAssertEqual(lastCharge.kind, .charges)
        XCTAssertTrue(lastCharge.detailText.contains("32,50 kWh"))
        XCTAssertTrue(lastCharge.detailText.contains("18% → 80%"))
    }

    func testDashboardAcceptsWrappedResponseAndSkipsEmptySections() throws {
        let data = Data(#"""
        {"data": {"this_month": {"total_distance_km": 12.5}, "community_comparison": {}}}
        """#.utf8)
        let dashboard = try XCTUnwrap(ExperienceFormat.dashboard(from: data))
        XCTAssertEqual(dashboard.sections.count, 1)
        XCTAssertEqual(dashboard.sections[0].distanceKM ?? 0, 12.5, accuracy: 0.001)
        XCTAssertTrue(dashboard.comparisons.isEmpty)
        XCTAssertNil(dashboard.lastJourney)
        XCTAssertNil(dashboard.lastCharge)
    }

    func testJourneyPeriodMapsRecordsRouteBarsAndPagination() throws {
        let data = Data(#"""
        {
          "summary": {
            "total_distance_km": 356.2,
            "total_kwh_consumed": 60.4,
            "avg_consumption_per_100km": 16.96,
            "journey_count": 2,
            "total_duration_min": 95,
            "avg_speed_kmh": 38.5,
            "avg_economy_score": 82
          },
          "journeys": [
            {
              "journey_id": "j1",
              "start_ts": 1729600000000,
              "total_distance_km": 24.6,
              "total_kwh_consumed": 4.1,
              "duration_min": 38,
              "avg_speed_kmh": 39.2,
              "start_location": {"name": "Ev"},
              "end_location": {"name": "Ofis"}
            },
            {
              "trip_id": "j2",
              "start_time": "2026-10-21T08:00:00Z",
              "distance_km": 10,
              "kwh_consumed": 1.8,
              "start": {"latitude": 39.9, "longitude": 32.5},
              "end": {"latitude": 39.95, "longitude": 32.6}
            }
          ],
          "period_km": [
            {"period_label": "2026-08", "km_total": 120.5},
            {"period_label": "2026-09", "km_total": 235.7}
          ],
          "journeys_pagination": {"has_more": true}
        }
        """#.utf8)
        let period = try XCTUnwrap(ExperienceFormat.period(from: data, kind: .journeys))
        XCTAssertEqual(period.receivedCount, 2)
        XCTAssertEqual(period.nextOffset, 2)
        XCTAssertTrue(period.hasMore)
        XCTAssertEqual(period.records.count, 2)
        XCTAssertEqual(period.records[0].detailID, "j1")
        XCTAssertEqual(period.records[0].subtitle, "Ev → Ofis")
        XCTAssertEqual(period.records[0].metrics.map(\.label), ["Mesafe", "Tüketim", "Süre", "Ort. hız"])
        XCTAssertEqual(period.records[1].detailID, "j2")
        XCTAssertEqual(period.records[1].subtitle, "39.90000, 32.50000 → 39.95000, 32.60000")
        XCTAssertEqual(period.records[1].metrics.first?.value, "10,0 km")

        XCTAssertEqual(period.bars.count, 2)
        XCTAssertEqual(period.bars[0].label, "Ağu 2026")
        XCTAssertEqual(period.bars[0].value, 120.5, accuracy: 0.001)
        XCTAssertEqual(period.bars[0].unit, "km")

        let labels = Dictionary(uniqueKeysWithValues: period.metrics.map { ($0.label, $0.value) })
        XCTAssertEqual(labels["Mesafe"], "356,2 km")
        XCTAssertEqual(labels["Toplam tüketim"], "60,40 kWh")
        XCTAssertEqual(labels["Ort. tüketim"], "16,96 kWh/100 km")
        XCTAssertEqual(labels["Yolculuk"], "2")
        XCTAssertEqual(labels["Sürüş süresi"], "1 sa 35 dk")
        XCTAssertEqual(labels["Ort. hız"], "38,5 km/sa")
        XCTAssertEqual(labels["Verim puanı"], "82 / 100")
    }

    func testChargePeriodMapsSocPlaceAndSummary() throws {
        let data = Data(#"""
        {
          "summary": {
            "total_sessions": 4,
            "total_energy_kwh": 210.6,
            "total_duration_min": 180,
            "avg_cost_per_kwh": 8.45
          },
          "charges": [
            {
              "charge_id": "c1",
              "start_ts": "2026-10-22T20:18:00Z",
              "soc_start_pct": 18,
              "soc_end_pct": 80,
              "kwh_added": 32.5,
              "duration_min": 45,
              "charge_type": "FAST",
              "station_name": "Togg Şarj AVM"
            }
          ],
          "period_energy": [
            {"period_start": "2026-10-01", "kwh_total": 32.5}
          ],
          "charges_pagination": {"has_more": false}
        }
        """#.utf8)
        let period = try XCTUnwrap(ExperienceFormat.period(from: data, kind: .charges))
        XCTAssertEqual(period.records.count, 1)
        XCTAssertEqual(period.records[0].detailID, "c1")
        XCTAssertEqual(period.records[0].subtitle, "Togg Şarj AVM")
        XCTAssertEqual(period.records[0].metrics.map(\.label), ["SOC", "Enerji", "Süre", "Tür"])
        XCTAssertEqual(period.records[0].metrics.map(\.value), ["18% → 80%", "32,50 kWh", "45 dk", "Hızlı şarj"])
        XCTAssertFalse(period.hasMore)
        XCTAssertEqual(period.bars.first?.label, "1 Eki")
        XCTAssertEqual(period.bars.first?.unit, "kWh")

        let labels = Dictionary(uniqueKeysWithValues: period.metrics.map { ($0.label, $0.value) })
        XCTAssertEqual(labels["Şarj sayısı"], "4")
        XCTAssertEqual(labels["Toplam enerji"], "210,60 kWh")
        XCTAssertEqual(labels["Süre"], "3 sa")
        XCTAssertEqual(labels["Birim maliyet"], "8,45 ₺/kWh")
    }

    func testChargeDetailComputesPowerAndFlagsUnverifiedPrice() throws {
        let data = Data(#"""
        {
          "charge_id": "c1",
          "start_ts": "2026-10-22T20:18:00Z",
          "soc_start_pct": 18,
          "soc_end_pct": 80,
          "kwh_added": 32.5,
          "duration_min": 45,
          "charge_type": "FAST",
          "total_price": 275.4,
          "station_name": "Togg Şarj AVM"
        }
        """#.utf8)
        let detail = try XCTUnwrap(ExperienceFormat.detail(from: data, kind: .charges))
        let labels = Dictionary(uniqueKeysWithValues: detail.metrics.map { ($0.label, $0.value) })
        XCTAssertEqual(labels["Başlangıç SOC"], "18%")
        XCTAssertEqual(labels["Bitiş SOC"], "80%")
        XCTAssertEqual(labels["Eklenen enerji"], "32,50 kWh")
        XCTAssertEqual(labels["Süre"], "45 dk")
        XCTAssertEqual(detail.subtitle, "Togg Şarj AVM")
        XCTAssertTrue(detail.notes.contains(where: { $0.contains("43,3 kW") }))
        XCTAssertTrue(detail.notes.contains(where: { $0.contains("Ödeme/fatura olarak doğrulanmadı") }))
    }

    func testJourneyDetailMapsEfficiencyAndProfiles() throws {
        let data = Data(#"""
        {
          "journey_id": "j1",
          "start_time": "2026-10-21T08:00:00Z",
          "total_distance_km": 24.6,
          "total_kwh_consumed": 4.1,
          "avg_consumption_per_100km": 16.67,
          "avg_speed_kmh": 39.2,
          "duration_min_total": 38,
          "trip_efficiency_pct": 86,
          "avg_economy_score": 82,
          "elevation_change_m": -120,
          "outside_temp_change_c": 3.5,
          "preferred_mode_rate_pct": 72,
          "start_address": "Ev",
          "end_address": "Ofis",
          "ac_usage": {"low": 45, "high": 10},
          "drive_mode_profile": {"comfort": 80, "eco": 20}
        }
        """#.utf8)
        let detail = try XCTUnwrap(ExperienceFormat.detail(from: data, kind: .journeys))
        let labels = Dictionary(uniqueKeysWithValues: detail.metrics.map { ($0.label, $0.value) })
        XCTAssertEqual(labels["Mesafe"], "24,6 km")
        XCTAssertEqual(labels["Tüketim"], "4,10 kWh")
        XCTAssertEqual(labels["Ort. tüketim"], "16,67 kWh/100 km")
        XCTAssertEqual(labels["Ort. hız"], "39,2 km/sa")
        XCTAssertEqual(labels["Süre"], "38 dk")
        XCTAssertEqual(labels["Verim"], "86%")
        XCTAssertEqual(labels["Ekonomi puanı"], "82 / 100")
        XCTAssertEqual(labels["Rakım değişimi"], "-120,0 m")
        XCTAssertEqual(labels["Dış sıcaklık farkı"], "3,5 °C")
        XCTAssertEqual(labels["Tercih edilen mod"], "72%")
        XCTAssertEqual(detail.subtitle, "Ev → Ofis")
        XCTAssertEqual(detail.sections.map(\.title), ["Klima kullanımı", "Sürüş modu dağılımı"])
        XCTAssertEqual(detail.sections[1].metrics.first(where: { $0.label == "Konfor" })?.value, "80%")
    }

    func testFormattersKeepMissingValuesExplicit() {
        XCTAssertEqual(ExperienceFormat.duration(minutes: 45), "45 dk")
        XCTAssertEqual(ExperienceFormat.duration(minutes: 90), "1 sa 30 dk")
        XCTAssertEqual(ExperienceFormat.duration(minutes: 120), "2 sa")
        XCTAssertNil(ExperienceFormat.distance(nil))
        XCTAssertNil(ExperienceFormat.energy(nil))
        XCTAssertNil(ExperienceFormat.consumption(nil))
        XCTAssertEqual(ExperienceFormat.distance(-1), nil)
        XCTAssertEqual(ExperienceFormat.whole(nil), "—")
        XCTAssertEqual(ExperienceFormat.oneDecimal(12.34), "12,3")
        XCTAssertEqual(ExperienceFormat.twoDecimals(12.345), "12,35")
        XCTAssertEqual(ExperienceFormat.periodLabel("2026-10"), "Eki 2026")
        XCTAssertEqual(ExperienceFormat.periodLabel("2026-10-01"), "1 Eki")
        XCTAssertEqual(ExperienceFormat.periodLabel("2026"), "2026")
        XCTAssertEqual(ExperienceFormat.display("FAST"), "Hızlı şarj")
        XCTAssertEqual(ExperienceFormat.display("Medium Ac"), "Orta AC")
        XCTAssertEqual(ExperienceFormat.display("MEDIUM_AC"), "Orta AC")
        XCTAssertEqual(ExperienceFormat.display("DRIVEMODE_COMFORT"), "Konfor")
        XCTAssertEqual(ExperienceFormat.label(forKey: "avg_speed_kmh"), "Avg Speed Kmh")
    }

    func testPeriodRejectsUnknownResponseAndKeepsMissingRecordIdNonTappable() throws {
        XCTAssertNil(ExperienceFormat.period(from: Data(#"{"unexpected":true}"#.utf8), kind: .journeys))
        let data = Data(#"""
        {"charges": [{"start_ts": "2026-10-22T20:18:00Z", "kwh_added": 12}], "charges_pagination": {"has_more": false}}
        """#.utf8)
        let period = try XCTUnwrap(ExperienceFormat.period(from: data, kind: .charges))
        XCTAssertEqual(period.records.count, 1)
        XCTAssertNil(period.records[0].detailID)
        XCTAssertEqual(period.records[0].id, "charges-0")
        XCTAssertEqual(period.nextOffset, 1)
        XCTAssertFalse(period.hasMore)
    }
}
