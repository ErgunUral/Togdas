#if DEBUG
import Foundation

/// `-e2e` başlatma argümanıyla çalışan uçtan uca duman testi.
///
/// Yalnız gerçek oturum, gerçek Drive Experience yanıtları ve yerel depolarla
/// çalışır; BLE komutu göndermez, araç kilidi açmaz. Sonuçlar konsola
/// `[E2E] PASS/FAIL` olarak yazılır. Ağ/oturum yoksa testler FAIL olur, sahte
/// veri üretilmez.
@MainActor
enum E2EHarness {
    private static var passed = 0
    private static var failed = 0

    static func run(model: GarageModel) async {
        passed = 0
        failed = 0
        print("[E2E] başladı")

        for _ in 0..<30 where model.selectedVehicle == nil {
            if !model.busy, model.signedIn { await model.refresh() }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        guard model.signedIn else {
            fail("oturum", "oturum açık değil; E2E için giriş yapılmış cihaz gerekir")
            summary()
            return
        }
        guard let vehicle = model.selectedVehicle else {
            fail("araç", "seçili araç yok")
            summary()
            return
        }
        let vin = vehicle.vin
        let api = model.api
        let price = max(0, UserDefaults.standard.object(forKey: EnergyPricing.storageKey) as? Double
                        ?? EnergyPricing.defaultPricePerKWh)
        print("[E2E] VIN=\(vin) fiyat=\(price)")

        // 1. Aylık şarjlar: özet, kayıtlar, tür toplamı ve gerçek/tahmin.
        var monthlyRecords: [ExperienceRecord] = []
        var monthlySpend: Double?
        do {
            let data = try await api.driveExperience(vin: vin, kind: "charges", period: "Monthly")
            let root = try json(data)
            let summary = root["summary"] as? [String: Any] ?? root
            monthlySpend = double(summary["total_price"] ?? summary["total_cost"])
            if let period = ExperienceFormat.period(from: data, kind: .charges, pricePerKWh: price) {
                monthlyRecords = period.records
                check("aylık şarj kaydı", !period.records.isEmpty,
                      "kayıt=\(period.records.count)")
                check("aylık özet enerjisi", period.metrics.contains { $0.label == "Toplam enerji" },
                      "metrikler=\(period.metrics.map(\.label).joined(separator: ","))")
                check("aylık grafik", !period.bars.isEmpty, "çubuk=\(period.bars.count)")
                let types = ExperienceFormat.chargeTypeStats(from: [data], pricePerKWh: price)
                let typeSum = types.reduce(0) { $0 + $1.costTRY }
                if let monthlySpend {
                    check("tür toplamı = sunucu toplamı", abs(typeSum - monthlySpend) < 0.05,
                          "tür=\(typeSum) sunucu=\(monthlySpend)")
                } else {
                    check("tür toplamı", types.isEmpty || typeSum == 0, "sunucu tutarı yok")
                }
                if let comparison = ExperienceFormat.chargeCostComparison(from: data, pricePerKWh: price) {
                    let expected = comparison.actualTRY - comparison.estimatedTRY
                    check("gerçek/tahmin farkı", abs(comparison.differenceTRY - expected) < 0.001,
                          "gerçek=\(comparison.actualTRY) tahmin=\(comparison.estimatedTRY)")
                } else {
                    print("[E2E] SKIP gerçek/tahmin: sunucu tutarı veya enerji yok")
                }
            } else {
                fail("aylık ayrıştırma", "ExperienceFormat.period nil")
            }
        } catch {
            fail("aylık şarj isteği", "\(error)")
        }

        // 2. Yıllık şarjlar: sayfalama ve tür dağılımı.
        do {
            var pages: [Data] = []
            var offset = 0
            var hasMore = true
            var guardCount = 0
            var summaryTotal: Double?
            while hasMore && guardCount < 10 {
                let data = try await api.driveExperience(vin: vin, kind: "charges",
                                                         period: "Annual", offset: offset)
                pages.append(data)
                let root = try json(data)
                let summary = root["summary"] as? [String: Any] ?? root
                summaryTotal = double(summary["total_price"] ?? summary["total_cost"]) ?? summaryTotal
                guard let page = ExperienceFormat.period(from: data, kind: .charges,
                                                         offset: offset, pricePerKWh: price) else {
                    fail("yıllık ayrıştırma", "offset=\(offset)")
                    break
                }
                offset = page.nextOffset
                hasMore = page.hasMore && page.receivedCount > 0
                guardCount += 1
            }
            let types = ExperienceFormat.chargeTypeStats(from: pages, pricePerKWh: price)
            let sessions = types.reduce(0) { $0 + $1.sessions }
            let typeSum = types.reduce(0) { $0 + $1.costTRY }
            check("yıllık sayfalar", guardCount > 0 && !types.isEmpty,
                  "sayfa=\(guardCount) seans=\(sessions)")
            if let summaryTotal {
                check("yıllık tür toplamı = sunucu toplamı", abs(typeSum - summaryTotal) < 0.05,
                      "tür=\(typeSum) sunucu=\(summaryTotal)")
            }
        } catch {
            fail("yıllık şarj isteği", "\(error)")
        }

        // 3. Dönem çapası: geçmiş hafta isteği.
        do {
            let data = try await api.driveExperience(vin: vin, kind: "charges",
                                                     period: "Weekly", anchor: "2026-09-28")
            let period = ExperienceFormat.period(from: data, kind: .charges, pricePerKWh: price)
            check("haftalık çapa", period != nil,
                  "kayıt=\(period?.records.count ?? -1) çubuk=\(period?.bars.count ?? -1)")
        } catch {
            fail("haftalık çapa isteği", "\(error)")
        }

        // 4. Yolculuklar ve grafik ölçüleri.
        do {
            let data = try await api.driveExperience(vin: vin, kind: "journeys", period: "Monthly")
            if let period = ExperienceFormat.period(from: data, kind: .journeys, pricePerKWh: price) {
                check("yolculuk kaydı", !period.records.isEmpty, "kayıt=\(period.records.count)")
                let metrics = period.bars.first?.values.keys.map(\.rawValue).sorted() ?? []
                check("yolculuk grafik ölçüleri",
                      metrics.contains("distance") && metrics.contains("duration"),
                      "ölçüler=\(metrics.joined(separator: ","))")
            } else {
                fail("yolculuk ayrıştırma", "ExperienceFormat.period nil")
            }
        } catch {
            fail("yolculuk isteği", "\(error)")
        }

        // 5. Bütçe önbelleği ve eşikler (üretim verisine dokunmadan ayrı suite).
        let suite = "toqdas.e2e.\(UUID().uuidString)"
        if let defaults = UserDefaults(suiteName: suite) {
            let store = ChargingSpendStore(vin: vin, defaults: defaults)
            store.record(amountTRY: 3940.34)
            check("bütçe önbelleği", store.snapshot()?.amountTRY == 3940.34,
                  "okunan=\(store.snapshot()?.amountTRY ?? -1)")
            store.setMonthlyLimit(5000)
            let budget = store.budget()
            check("bütçe durumu", budget.status == .normal && budget.percentText == "79%",
                  "durum=\(budget.status) yüzde=\(budget.percentText)")
            store.record(amountTRY: 9999)
            store.setMonthlyLimit(5000)
            check("bütçe aşımı", store.budget().status == .exceeded
                  && store.budget().notificationThreshold == 100,
                  "durum=\(store.budget().status)")
            store.markNotified(threshold: 100)
            check("bildirim ayda bir", store.lastNotifiedThreshold() == 100,
                  "eşik=\(store.lastNotifiedThreshold())")
            defaults.removePersistentDomain(forName: suite)
        } else {
            fail("bütçe suite", "UserDefaults oluşturulamadı")
        }

        // 6. CSV dışa aktarma gerçek kayıtlarla.
        let csv = ExperienceExport.csv(records: monthlyRecords)
        let lines = csv.split(separator: "\r\n")
        check("CSV başlık", csv.hasPrefix("\u{FEFF}Tür;Tarih;Konum/Rota"),
              "baş=\(csv.prefix(20))")
        check("CSV satır sayısı", lines.count == monthlyRecords.count + 1,
              "satır=\(lines.count) kayıt=\(monthlyRecords.count)")
        let filename = ExperienceExport.filename(kind: .charges, anchor: nil)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            let csvData = Data(csv.utf8)
            try csvData.write(to: url, options: .atomic)
            let readBack = try Data(contentsOf: url)
            check("CSV dosyası", readBack == csvData, "boyut=\(readBack.count)")
            check("CSV UTF-8 BOM", readBack.starts(with: [0xEF, 0xBB, 0xBF]),
                  "ilk=\(readBack.prefix(3).map { String(format: "%02X", $0) }.joined(separator: " "))")
            try? FileManager.default.removeItem(at: url)
        } catch {
            fail("CSV dosyası", "\(error)")
        }

        // 7. Widget/paylaşılan anlık görüntü (varsa) tutarı 0 uydurmamalı.
        if let snapshot = VehicleWidgetSnapshotStore.load() {
            let text = snapshot.displayChargeSpend
            check("widget harcama metni", text == "—" || text.hasSuffix(" ₺"), "metin=\(text)")
        } else {
            print("[E2E] SKIP widget snapshot: kayıt yok")
        }

        // 8. Salt okunur Siri niyetleri: BLE'ye dokunmadan önbellekten yanıt.
        do {
            let status = try await VehicleStatusIntent().perform()
            let description = String(describing: status)
            check("Siri araç durumu", !description.isEmpty, description)
        } catch {
            fail("Siri araç durumu", "\(error)")
        }
        do {
            let spend = try await ChargingSpendIntent().perform()
            let description = String(describing: spend)
            check("Siri şarj harcaması", !description.isEmpty, description)
        } catch {
            fail("Siri şarj harcaması", "\(error)")
        }

        summary()
    }

    // MARK: - Yardımcılar

    private static func json(_ data: Data) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError.message("JSON nesnesi değil")
        }
        return root
    }

    private static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }

    private static func check(_ name: String, _ condition: Bool, _ detail: String) {
        if condition {
            passed += 1
            print("[E2E] PASS \(name) — \(detail)")
        } else {
            failed += 1
            print("[E2E] FAIL \(name) — \(detail)")
        }
    }

    private static func fail(_ name: String, _ detail: String) {
        failed += 1
        print("[E2E] FAIL \(name) — \(detail)")
    }

    private static func summary() {
        print("[E2E] SUMMARY passed=\(passed) failed=\(failed) total=\(passed + failed)")
    }
}
#endif
