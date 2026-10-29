import SwiftUI

private struct ExperienceDetailTarget: Identifiable {
    let id: String
    let kind: ExperienceKind
    let detailID: String

    init(kind: ExperienceKind, detailID: String) {
        self.kind = kind
        self.detailID = detailID
        self.id = kind.rawValue + ":" + detailID
    }
}

/// Togg Drive Experience: dönem özeti, topluluk karşılaştırması,
/// yolculuk ve şarj geçmişi ile kayıt ayrıntıları.
struct DriveExperienceView: View {
    let vehicle: Vehicle
    let api: ToggAPI

    @State private var kind = ProcessInfo.processInfo.arguments.contains("-experienceCharges")
        ? ExperienceKind.charges : ExperienceKind.journeys
    @State private var chartMetric = ExperienceChartMetric.distance
    @State private var showPeriodPicker = false
    @State private var period: String = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-experiencePeriod"), index + 1 < args.count,
           ["Weekly", "Monthly", "Annual"].contains(args[index + 1]) {
            return args[index + 1]
        }
        #endif
        return "Monthly"
    }()
    /// Sunucuya gönderilen dönem çapası: yıllık "2026", aylık "2026-10", haftalık "2026-10-19".
    @State private var anchor: String? = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-experienceAnchor"), index + 1 < args.count {
            return args[index + 1]
        }
        #endif
        return nil
    }()
    @State private var dashboard: ExperienceDashboard?
    @State private var selectedSummaryID: String?
    @State private var metrics: [ExperienceMetric] = []
    @State private var bars: [ExperienceBar] = []
    @State private var records: [ExperienceRecord] = []
    @State private var offset = 0
    @State private var hasMore = false
    @State private var busy = false
    @State private var summaryBusy = false
    @State private var error: String?
    @State private var summaryError: String?
    @State private var loadedSummary = false
    @State private var raw = ""
    @State private var rawSummary = ""
    @State private var detailTarget: ExperienceDetailTarget?
    @State private var requestGeneration = 0
    @State private var summaryGeneration = 0
    @AppStorage(EnergyPricing.storageKey) private var pricePerKWh = EnergyPricing.defaultPricePerKWh

    private let periods: [(String, String)] = [
        ("Weekly", "Haftalık"), ("Monthly", "Aylık"), ("Annual", "Yıllık")
    ]

    var body: some View {
        ZStack {
            ToggTheme.background.ignoresSafeArea()
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    titleCard
                    priceCard

                    if summaryBusy && dashboard == nil {
                        ProgressView().tint(ToggTheme.teal).padding(24)
                    }
                    if let summaryError {
                        errorBanner(summaryError)
                    }
                    if let dashboard {
                        summaryView(dashboard)
                    }

                    selector

                    if let error {
                        errorBanner(error)
                    }

                    if !metrics.isEmpty {
                        periodMetricsCard
                    }
                    if !bars.isEmpty {
                        chartCard
                    }

                    if busy && records.isEmpty {
                        ProgressView().tint(ToggTheme.teal).padding(28)
                    }
                    if records.isEmpty && !busy {
                        Text("Bu dönem için kayıt bulunamadı.")
                            .font(.footnote).foregroundStyle(ToggTheme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Color.clear.frame(height: 1).id("records")

                    if !records.isEmpty {
                        HStack {
                            Text("Kayıtlar")
                                .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                            Spacer()
                            Text("\(records.count)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(ToggTheme.muted)
                        }
                    }

                    ForEach(records) { record in
                        recordCard(record)
                    }

                    if hasMore {
                        Button { Task { await load(reset: false) } } label: {
                            Label("Daha fazla yükle", systemImage: "arrow.down.circle")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(RoundedRectangle(cornerRadius: 14).fill(ToggTheme.teal))
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                    }

                    technicalResponse

                    Text("Veriler Togg Drive Experience servisinden alınır. Topluluk karşılaştırması, maliyet ve konum alanları yalnız sunucu değer döndürdüğünde gösterilir; eksik değerler tahmin edilmez.")
                        .font(.caption2).foregroundStyle(ToggTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
            }
            .refreshable {
                await loadSummary()
                await load(reset: true)
            }
            #if DEBUG
            .onChange(of: records.count) { count in
                guard count > 0 else { return }
                if ProcessInfo.processInfo.arguments.contains("-scrollDriveRecords") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        proxy.scrollTo("records", anchor: .top)
                    }
                }
                if ProcessInfo.processInfo.arguments.contains("-openDriveDetail"),
                   let first = records.first(where: { $0.detailID != nil }),
                   let detailID = first.detailID {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        detailTarget = ExperienceDetailTarget(kind: first.kind, detailID: detailID)
                    }
                }
            }
            #endif
            }
        }
        .navigationTitle("Sürüş & Şarj")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await loadSummary()
                        await load(reset: true)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(busy || summaryBusy)
                .accessibilityLabel("Analizi yenile")
            }
        }
        .task {
            guard !loadedSummary else { return }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-openDriveCharges") {
                kind = .charges
            }
            #endif
            await loadSummary()
            await load(reset: true)
        }
        .sheet(item: $detailTarget) { target in
            ExperienceDetailSheet(api: api, vin: vehicle.vin, target: target,
                                  pricePerKWh: pricePerKWh)
        }
        .sheet(isPresented: $showPeriodPicker) {
            PeriodPickerSheet(period: period, initialAnchor: anchor) { selected in
                anchor = selected
                Task { await load(reset: true) }
            }
        }
    }

    // MARK: - Başlık

    private var titleCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(ToggTheme.teal.opacity(0.2)).frame(width: 40, height: 40)
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 18)).foregroundStyle(ToggTheme.teal)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Seyahatname")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                Text(vehicle.title + " • " + (vehicle.plate.isEmpty ? vehicle.vin : vehicle.plate))
                    .font(.system(size: 12)).foregroundStyle(ToggTheme.muted)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(16)
        .toggCardBackground(20)
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12)).foregroundStyle(ToggTheme.pink)
            Text(text).font(.footnote).foregroundStyle(ToggTheme.pink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(ToggTheme.pink.opacity(0.08)))
    }

    // MARK: - Özet

    private func summaryView(_ dashboard: ExperienceDashboard) -> some View {
        VStack(spacing: 12) {
            if dashboard.sections.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(dashboard.sections) { section in
                            Button {
                                selectedSummaryID = section.id
                            } label: {
                                Text(section.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(selectedSummaryID == section.id ? .black : .white)
                                    .padding(.horizontal, 12)
                                    .frame(height: 32)
                                    .background(
                                        Capsule().fill(selectedSummaryID == section.id
                                                       ? ToggTheme.teal : ToggTheme.surfaceVariant)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let section = selectedSection(in: dashboard) {
                summarySectionCard(section)
            }

            if !dashboard.comparisons.isEmpty {
                comparisonCard(dashboard.comparisons)
            }

            if dashboard.lastJourney != nil || dashboard.lastCharge != nil {
                highlightsRow(dashboard)
            }
        }
    }

    private func selectedSection(in dashboard: ExperienceDashboard) -> ExperienceSummarySection? {
        if let selectedSummaryID,
           let section = dashboard.sections.first(where: { $0.id == selectedSummaryID }) {
            return section
        }
        return dashboard.sections.first
    }

    private func summarySectionCard(_ section: ExperienceSummarySection) -> some View {
        let hero = hero(for: section)
        let stats = summaryStats(section, heroLabel: hero?.label)
        let extras = summaryExtras(section, heroLabel: hero?.label, stats: stats)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(section.title)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(ToggTheme.muted)
                Spacer()
                if let score = section.economyScore {
                    Text("Verim \(ExperienceFormat.whole(score))/100")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ToggTheme.teal)
                }
            }

            if let hero {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(hero.value)
                            .font(.system(size: 38, weight: .bold))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text(hero.unit)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ToggTheme.muted)
                    }
                    Text(hero.label)
                        .font(.system(size: 11)).foregroundStyle(ToggTheme.muted)
                }
            }

            if !stats.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(stats) { metric in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(metric.label)
                                .font(.system(size: 9)).foregroundStyle(ToggTheme.muted)
                                .lineLimit(1)
                            Text(metric.value)
                                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                                .lineLimit(1).minimumScaleFactor(0.65)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if !extras.isEmpty {
                Divider().overlay(ToggTheme.outline.opacity(0.5))
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(extras) { metric in
                        HStack(spacing: 6) {
                            Text(metric.label)
                                .font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(metric.value)
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                }
            }

            let notes = summaryNotes(section)
            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(notes, id: \.0) { item in
                        HStack(alignment: .top, spacing: 4) {
                            Text(item.0 + ":").font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
                            Text(item.1).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                        }
                    }
                }
            }
        }
        .padding(18)
        .toggCardBackground(22)
    }

    private func hero(for section: ExperienceSummarySection) -> (value: String, unit: String, label: String)? {
        if let distance = section.distanceKM {
            return (ExperienceFormat.oneDecimal(distance), "km", "Mesafe")
        }
        if let added = section.addedEnergyKWh {
            return (ExperienceFormat.oneDecimal(added), "kWh", "Eklenen enerji")
        }
        if let count = section.journeyCount {
            return (ExperienceFormat.whole(count), "yolculuk", "Yolculuk")
        }
        if let count = section.chargeCount {
            return (ExperienceFormat.whole(count), "şarj", "Şarj")
        }
        if let energy = section.totalConsumptionKWh {
            return (ExperienceFormat.oneDecimal(energy), "kWh", "Tüketim")
        }
        return nil
    }

    private func summaryStats(_ section: ExperienceSummarySection, heroLabel: String?) -> [ExperienceMetric] {
        var result: [ExperienceMetric] = []
        func add(_ label: String, _ value: String?) {
            guard label != heroLabel, let value, result.count < 3,
                  !result.contains(where: { $0.label == label }) else { return }
            result.append(ExperienceMetric(label: label, value: value))
        }
        add("Mesafe", ExperienceFormat.distance(section.distanceKM))
        add("Yolculuk", section.journeyCount.map { ExperienceFormat.whole($0) })
        add("Süre", ExperienceFormat.duration(minutes: section.durationMinutes))
        add("Ort. tüketim", ExperienceFormat.consumption(section.averageConsumption))
        add("Tüketim", ExperienceFormat.energy(section.totalConsumptionKWh))
        add("Ort. hız", section.averageSpeedKMH.map { "\(ExperienceFormat.oneDecimal($0)) km/sa" })
        add("Şarj", section.chargeCount.map { ExperienceFormat.whole($0) })
        add("Eklenen enerji", ExperienceFormat.energy(section.addedEnergyKWh))
        return result
    }

    private func summaryExtras(_ section: ExperienceSummarySection, heroLabel: String?, stats: [ExperienceMetric]) -> [ExperienceMetric] {
        let used = Set(stats.map(\.label) + [heroLabel].compactMap { $0 })
        var result: [ExperienceMetric] = []
        func add(_ label: String, _ value: String?) {
            guard !used.contains(label), let value, result.count < 6,
                  !result.contains(where: { $0.label == label }) else { return }
            result.append(ExperienceMetric(label: label, value: value))
        }
        add("Mesafe", ExperienceFormat.distance(section.distanceKM))
        add("Yolculuk", section.journeyCount.map { ExperienceFormat.whole($0) })
        add("Süre", ExperienceFormat.duration(minutes: section.durationMinutes))
        add("Ort. tüketim", ExperienceFormat.consumption(section.averageConsumption))
        add("Tüketim", ExperienceFormat.energy(section.totalConsumptionKWh))
        add("Ort. hız", section.averageSpeedKMH.map { "\(ExperienceFormat.oneDecimal($0)) km/sa" })
        add("Şarj", section.chargeCount.map { ExperienceFormat.whole($0) })
        add("Eklenen enerji", ExperienceFormat.energy(section.addedEnergyKWh))
        return result
    }

    private func summaryNotes(_ section: ExperienceSummarySection) -> [(String, String)] {
        var result: [(String, String)] = []
        if let value = section.preferredMode { result.append(("Tercih edilen sürüş modu", value)) }
        if let value = section.airCondition { result.append(("Klima kullanımı", value)) }
        if let value = section.chargingType { result.append(("Şarj türü", value)) }
        return result
    }

    private func comparisonCard(_ comparisons: [ExperienceComparison]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Toplulukla karşılaştırma")
                .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
            ForEach(comparisons) { comparison in
                let maximum = max(comparison.you ?? 0, comparison.community ?? 0, 1)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(comparison.label)
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        Spacer()
                        Text(comparison.unit)
                            .font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
                    }
                    comparisonRow("Sen", value: comparison.you, unit: comparison.unit,
                                  maximum: maximum, color: ToggTheme.teal)
                    comparisonRow("Topluluk", value: comparison.community, unit: comparison.unit,
                                  maximum: maximum, color: ToggTheme.muted)
                    if comparison.id == "avg_consumption_per_100km",
                       let you = comparison.you, let community = comparison.community, community > 0 {
                        let difference = abs(you - community) / community * 100
                        let text = you < community ? "daha düşük tüketim"
                            : (you > community ? "daha yüksek tüketim" : "aynı tüketim")
                        let amount = difference < 1 ? "<1" : ExperienceFormat.whole(difference)
                        Text("\(amount)% \(text)")
                            .font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
                    }
                }
            }
        }
        .padding(18)
        .toggCardBackground(22)
    }

    private func comparisonRow(_ title: String, value: Double?, unit: String,
                               maximum: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
                Spacer()
                Text(comparisonValue(value, unit: unit))
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(ToggTheme.outline.opacity(0.35))
                    Capsule().fill(color)
                        .frame(width: geometry.size.width * (value.map { min(1, max(0, $0 / maximum)) } ?? 0))
                }
            }
            .frame(height: 6)
        }
    }

    private func comparisonValue(_ value: Double?, unit: String) -> String {
        guard let value else { return "Veri yok" }
        if unit == "adet" { return ExperienceFormat.whole(value) }
        return ExperienceFormat.oneDecimal(value)
    }

    private func highlightsRow(_ dashboard: ExperienceDashboard) -> some View {
        HStack(spacing: 10) {
            if let journey = dashboard.lastJourney { highlightCard(journey) }
            if let charge = dashboard.lastCharge { highlightCard(charge) }
        }
    }

    private func highlightCard(_ highlight: ExperienceHighlight) -> some View {
        Button {
            if let detailID = highlight.detailID {
                detailTarget = ExperienceDetailTarget(kind: highlight.kind, detailID: detailID)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(highlight.title)
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    Spacer()
                    if highlight.detailID != nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold)).foregroundStyle(ToggTheme.muted)
                    }
                }
                if !highlight.dateText.isEmpty {
                    Text(highlight.dateText)
                        .font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
                        .lineLimit(1)
                }
                if !highlight.detailText.isEmpty {
                    Text(highlight.detailText)
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(ToggTheme.teal)
                        .lineLimit(1).minimumScaleFactor(0.7)
                } else {
                    Text("Ayrıntı için dokun")
                        .font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .toggCardBackground(16)
        }
        .buttonStyle(.plain)
        .disabled(highlight.detailID == nil)
    }

    // MARK: - Seçim

    private var selector: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(ExperienceKind.allCases, id: \.rawValue) { item in
                    Button {
                        guard kind != item else { return }
                        kind = item
                        chartMetric = item == .charges ? .energy : .distance
                        Task { await load(reset: true) }
                    } label: {
                        Text(item.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(kind == item ? .black : .white)
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(kind == item ? ToggTheme.teal : ToggTheme.surfaceVariant)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                ForEach(periods, id: \.0) { item in
                    Button {
                        guard period != item.0 else { return }
                        period = item.0
                        anchor = nil
                        Task { await load(reset: true) }
                    } label: {
                        Text(item.1)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(period == item.0 ? .black : .white)
                            .frame(maxWidth: .infinity).frame(height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(period == item.0 ? ToggTheme.teal : ToggTheme.surfaceVariant)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                Button { movePeriod(-1) } label: {
                    Label("Önceki", systemImage: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 10).fill(ToggTheme.surfaceVariant))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Önceki dönem")

                Button { showPeriodPicker = true } label: {
                    HStack(spacing: 4) {
                        Text(anchorLabel)
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Image(systemName: "calendar")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(ToggTheme.teal)
                    .frame(minWidth: 92)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dönem seç: \(anchorLabel)")

                Button { movePeriod(1) } label: {
                    Label("Sonraki", systemImage: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 10).fill(ToggTheme.surfaceVariant))
                }
                .buttonStyle(.plain)
                .disabled(!canMoveForward)
                .opacity(canMoveForward ? 1 : 0.35)
                .accessibilityLabel("Sonraki dönem")
            }
        }
    }

    // MARK: - Dönem gezinme

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private func anchorDate(from anchor: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = period == "Annual" ? "yyyy" : (period == "Weekly" ? "yyyy-MM-dd" : "yyyy-MM")
        return formatter.date(from: anchor)
    }

    private func anchorString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = period == "Annual" ? "yyyy" : (period == "Weekly" ? "yyyy-MM-dd" : "yyyy-MM")
        return formatter.string(from: date)
    }

    private func shifted(_ date: Date, by steps: Int) -> Date? {
        switch period {
        case "Annual": return utcCalendar.date(byAdding: .year, value: steps, to: date)
        case "Weekly": return utcCalendar.date(byAdding: .day, value: steps * 7, to: date)
        default: return utcCalendar.date(byAdding: .month, value: steps, to: date)
        }
    }

    private var canMoveForward: Bool {
        let base = anchor.flatMap(anchorDate(from:)) ?? Date()
        guard let next = shifted(base, by: 1) else { return false }
        return next <= Date()
    }

    private func movePeriod(_ steps: Int) {
        let base = anchor.flatMap(anchorDate(from:)) ?? Date()
        guard let next = shifted(base, by: steps) else { return }
        guard steps < 0 || next <= Date() else { return }
        anchor = anchorString(for: next)
        Task { await load(reset: true) }
    }

    private var anchorLabel: String {
        guard let anchor else {
            switch period {
            case "Annual": return "Bu yıl"
            case "Weekly": return "Bu hafta"
            default: return "Bu ay"
            }
        }
        switch period {
        case "Annual":
            return anchor
        case "Weekly":
            guard let start = anchorDate(from: anchor),
                  let end = utcCalendar.date(byAdding: .day, value: 6, to: start) else { return anchor }
            let day = DateFormatter()
            day.locale = Locale(identifier: "tr_TR")
            day.timeZone = TimeZone(secondsFromGMT: 0)
            day.dateFormat = "d MMM"
            let year = utcCalendar.component(.year, from: end)
            return "\(day.string(from: start)) – \(day.string(from: end)) \(year)"
        default:
            let parts = anchor.split(separator: "-")
            guard parts.count == 2, let month = Int(parts[1]), (1...12).contains(month) else { return anchor }
            let names = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran",
                         "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"]
            return "\(names[month - 1]) \(parts[0])"
        }
    }

    private var priceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.badge.clock")
                    .font(.system(size: 16)).foregroundStyle(ToggTheme.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Elektrik birim fiyatı")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    Text("Sunucu gerçek tutarı döndürürse o gösterilir; dönmezse maliyet bu fiyatla tahmin edilir. Fatura değildir.")
                        .font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                HStack(spacing: 4) {
                    TextField("10", value: $pricePerKWh,
                              format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 64)
                    Text("₺/kWh")
                        .font(.system(size: 11)).foregroundStyle(ToggTheme.muted)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(ToggTheme.surfaceVariant))
        .onChange(of: pricePerKWh) { value in
            let clamped = EnergyPricing(pricePerKWh: value).pricePerKWh
            if clamped != value { pricePerKWh = clamped }
            recomputeMetricsFromLastResponse()
        }
    }

    #if DEBUG
    /// Yalnız `-experienceCharges` ile açılan tanılama oturumunda günlük üretir.
    private var diagnosticsEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-experienceCharges") || args.contains("-experienceDiagnostics")
    }

    /// Sunucunun şarj yanıtında hangi maliyet alanlarını döndürdüğünü görünür kılar.
    /// Yalnız hata ayıklamada ve `-experienceCharges` ile açılan ekranda çalışır.
    private func logChargeFields(_ data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[CHARGES] yanıt JSON olarak çözülemedi")
            return
        }
        let summary = root["summary"] as? [String: Any] ?? root
        let charges = root["charges"] as? [[String: Any]] ?? []
        for key in ["period_km", "period_energy"] {
            if let items = root[key] as? [[String: Any]], let first = items.first {
                print("[CHARGES] \(key) anahtarlar=\(first.keys.sorted().joined(separator: ","))")
                print("[CHARGES] \(key) ilk=\(first)")
            }
        }
        print("[CHARGES] kayıt sayısı=\(charges.count)")
        print("[CHARGES] summary anahtarları=\(summary.keys.sorted().joined(separator: ","))")
        print("[CHARGES] summary maliyet alanları=\(costFields(summary))")
        for (index, charge) in charges.prefix(3).enumerated() {
            print("[CHARGES] #\(index) anahtarlar=\(charge.keys.sorted().joined(separator: ","))")
            print("[CHARGES] #\(index) maliyet=\(costFields(charge))")
        }
        if let page = ExperienceFormat.period(from: data, kind: .charges, offset: 0, pricePerKWh: pricePerKWh) {
            let summaryLine = page.metrics.map { "\($0.label)=\($0.value)" }.joined(separator: " | ")
            print("[CHARGES] ekranda=\(summaryLine)")
            if let first = page.records.first {
                let line = first.metrics.map { "\($0.label)=\($0.value)" }.joined(separator: " | ")
                print("[CHARGES] ilk kayıt=\(line)")
            }
        }
    }

    private func costFields(_ dictionary: [String: Any]) -> String {
        let fields = dictionary.filter {
            let key = $0.key.lowercased()
            return key.contains("cost") || key.contains("price") || key.contains("amount")
        }
        return fields.isEmpty ? "yok" : fields.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " | ")
    }
    #endif

    /// Fiyat değişince yeniden istek atmadan son yanıttan maliyet satırlarını günceller.
    private func recomputeMetricsFromLastResponse() {
        guard error == nil, !raw.isEmpty,
              let page = ExperienceFormat.period(from: Data(raw.utf8), kind: kind, offset: 0,
                                                 pricePerKWh: pricePerKWh) else { return }
        metrics = page.metrics
        bars = page.bars
    }

    private var periodMetricsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Dönem Özeti")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                Spacer()
                Text(anchorLabel)
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(ToggTheme.muted)
                    .lineLimit(1)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(metrics) { metric in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(metric.label)
                            .font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
                            .lineLimit(1)
                        Text(metric.value)
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.65)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(ToggTheme.surfaceVariant))
                }
            }
            if kind == .charges {
                Text("Harcama, dönemin eklenen enerjisi × birim fiyat ile tahmin edilir; servis tutarı varsa kayıt detayında gösterilir.")
                    .font(.system(size: 9)).foregroundStyle(ToggTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .toggCardBackground(20)
    }

    /// Seçilen ölçüye göre çubukları dönüştürür; ölçüsü olmayan dönem atlanır.
    private var displayedBars: [ExperienceBar] {
        bars.compactMap { bar in
            guard let value = bar.value(for: chartMetric) else { return nil }
            return ExperienceBar(id: bar.id, label: bar.label, value: value,
                                 unit: chartMetric.unit, values: bar.values)
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Dönem grafiği")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                Spacer()
                Picker("Grafik ölçüsü", selection: $chartMetric) {
                    ForEach(ExperienceChartMetric.available(for: kind)) { metric in
                        Text(metric.title).tag(metric)
                    }
                }
                .pickerStyle(.menu)
                .tint(ToggTheme.teal)
                .accessibilityLabel("Grafik ölçüsü")
            }
            if displayedBars.isEmpty {
                Text("Bu ölçü için dönem verisi yok.")
                    .font(.system(size: 11)).foregroundStyle(ToggTheme.muted)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ExperienceBarChart(bars: displayedBars)
            }
            Text("Her çubuk bir dönemi gösterir; yalnız sunucu değeri bulunan dönemler kullanılır. Ölçü: \(chartMetric.title.lowercased()).")
                .font(.system(size: 9)).foregroundStyle(ToggTheme.muted)
        }
        .padding(16)
        .toggCardBackground(20)
    }

    // MARK: - Kayıtlar

    private func recordCard(_ record: ExperienceRecord) -> some View {
        Button {
            if let detailID = record.detailID {
                detailTarget = ExperienceDetailTarget(kind: record.kind, detailID: detailID)
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(record.dateText.isEmpty ? "Tarih belirtilmemiş" : record.dateText)
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    if record.detailID != nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(ToggTheme.muted)
                    }
                }
                if !record.subtitle.isEmpty {
                    Text(record.subtitle)
                        .font(.system(size: 11)).foregroundStyle(ToggTheme.muted)
                        .lineLimit(2)
                }
                if !record.metrics.isEmpty {
                    Divider().overlay(ToggTheme.outline.opacity(0.5))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(record.metrics) { field in
                            HStack(spacing: 4) {
                                Text(field.label)
                                    .font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(field.value)
                                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .toggCardBackground(18)
        }
        .buttonStyle(.plain)
        .disabled(record.detailID == nil)
    }

    private var technicalResponse: some View {
        DisclosureGroup("Teknik yanıt") {
            Text(raw.isEmpty ? rawSummary : raw)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(ToggTheme.muted)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(ToggTheme.muted)
    }

    // MARK: - Veri

    @MainActor
    private func loadSummary() async {
        summaryGeneration += 1
        let token = summaryGeneration
        summaryBusy = true
        summaryError = nil
        defer { if token == summaryGeneration { summaryBusy = false } }
        do {
            let data = try await api.driveExperience(vin: vehicle.vin, kind: "summary")
            guard token == summaryGeneration else { return }
            rawSummary = String(decoding: data, as: UTF8.self)
            guard let parsed = ExperienceFormat.dashboard(from: data) else {
                summaryError = "Analiz özeti beklenen biçimde değil."
                return
            }
            dashboard = parsed
            loadedSummary = true
            if selectedSummaryID == nil || !parsed.sections.contains(where: { $0.id == selectedSummaryID }) {
                selectedSummaryID = parsed.sections.first?.id
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-driveSummaryAllTime"),
               parsed.sections.contains(where: { $0.id == "all_time" }) {
                selectedSummaryID = "all_time"
            }
            #endif
        } catch {
            guard token == summaryGeneration else { return }
            summaryError = error.localizedDescription
        }
    }

    @MainActor
    private func load(reset: Bool) async {
        requestGeneration += 1
        let token = requestGeneration
        #if DEBUG
        if diagnosticsEnabled {
            print("[CHARGES] istek kind=\(kind.rawValue) anchor=\(anchor ?? "nil") period=\(period) offset=\(offset)")
        }
        #endif
        busy = true
        error = nil
        if reset {
            offset = 0
            records = []
            metrics = []
            bars = []
            hasMore = false
        }
        defer { if token == requestGeneration { busy = false } }
        do {
            let data = try await api.driveExperience(
                vin: vehicle.vin, kind: kind.rawValue, period: period, offset: offset, anchor: anchor
            )
            guard token == requestGeneration else { return }
            raw = String(decoding: data, as: UTF8.self)
            #if DEBUG
            if diagnosticsEnabled { logChargeFields(data) }
            #endif
            guard let page = ExperienceFormat.period(from: data, kind: kind, offset: offset,
                                                     pricePerKWh: pricePerKWh) else {
                throw AppError.message("Analiz yanıtı beklenen biçimde değil.")
            }
            metrics = page.metrics
            bars = page.bars
            if reset {
                records = page.records
            } else {
                let existing = Set(records.map(\.id))
                records += page.records.filter { !existing.contains($0.id) }
            }
            offset = max(page.nextOffset, offset)
            hasMore = page.hasMore && page.receivedCount > 0
        } catch {
            guard token == requestGeneration else { return }
            self.error = error.localizedDescription
            if reset { hasMore = false }
        }
    }
}

// MARK: - Grafik

private struct ExperienceBarChart: View {
    let bars: [ExperienceBar]

    private func barValueText(_ bar: ExperienceBar) -> String {
        let number = bar.unit == "adet" ? ExperienceFormat.whole(bar.value) : ExperienceFormat.oneDecimal(bar.value)
        return "\(number) \(bar.unit)"
    }

    var body: some View {
        let maximum = max(bars.map(\.value).max() ?? 0, 1)
        VStack(spacing: 7) {
            ForEach(bars) { bar in
                HStack(spacing: 8) {
                    Text(bar.label.isEmpty ? "—" : bar.label)
                        .font(.system(size: 9)).foregroundStyle(ToggTheme.muted)
                        .frame(width: 62, alignment: .leading).lineLimit(1)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(ToggTheme.outline.opacity(0.35))
                            Capsule().fill(ToggTheme.teal)
                                .frame(width: max(2, geometry.size.width * min(1, bar.value / maximum)))
                        }
                    }
                    .frame(height: 7)
                    Text(barValueText(bar))
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 62, alignment: .trailing).lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Dönem seçici

/// Takvimden dönem atlama. Haftalık için tarih, aylık için yıl+ay,
/// yıllık için yıl seçilir; gelecek dönem seçilemez.
private struct PeriodPickerSheet: View {
    let period: String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var year: Int
    @State private var month: Int
    @State private var weekDate: Date

    private let months = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran",
                          "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"]

    init(period: String, initialAnchor: String?, onSelect: @escaping (String) -> Void) {
        self.period = period
        self.onSelect = onSelect
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let components = calendar.dateComponents([.year, .month], from: now)
        _year = State(initialValue: components.year ?? 2026)
        _month = State(initialValue: components.month ?? 1)
        _weekDate = State(initialValue: now)
        if let initialAnchor {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = period == "Annual" ? "yyyy"
                : (period == "Weekly" ? "yyyy-MM-dd" : "yyyy-MM")
            if let date = formatter.date(from: initialAnchor) {
                let parts = calendar.dateComponents([.year, .month], from: date)
                _year = State(initialValue: parts.year ?? _year.wrappedValue)
                _month = State(initialValue: parts.month ?? _month.wrappedValue)
                _weekDate = State(initialValue: date)
            }
        }
    }

    private var currentYear: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar.component(.year, from: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    switch period {
                    case "Annual":
                        yearGrid
                    case "Weekly":
                        DatePicker("Hafta", selection: $weekDate, in: weekRange,
                                   displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .tint(ToggTheme.teal)
                    default:
                        yearStepper
                        monthGrid
                    }
                }
                .padding(20)
            }
            .background(ToggTheme.background.ignoresSafeArea())
            .navigationTitle("Dönem seç")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var weekRange: ClosedRange<Date> {
        let start = Calendar(identifier: .gregorian).date(byAdding: .year, value: -3, to: Date()) ?? Date()
        return start...Date()
    }

    private var yearStepper: some View {
        HStack {
            Button { if year > 2023 { year -= 1 } } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 36)
            }
            .disabled(year <= 2023)
            Spacer()
            Text(String(year)).font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
            Spacer()
            Button { if year < currentYear { year += 1 } } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 36)
            }
            .disabled(year >= currentYear)
        }
        .foregroundStyle(ToggTheme.teal)
        .padding(.horizontal, 8)
    }

    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
            ForEach(1...12, id: \.self) { value in
                let disabled = year == currentYear && value > currentMonth
                Button {
                    choose(String(format: "%04d-%02d", year, value))
                } label: {
                    Text(months[value - 1])
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(disabled ? ToggTheme.muted : .white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(disabled ? ToggTheme.surfaceVariant.opacity(0.4) : ToggTheme.surfaceVariant))
                }
                .buttonStyle(.plain)
                .disabled(disabled)
            }
        }
    }

    private var currentMonth: Int {
        Calendar(identifier: .gregorian).component(.month, from: Date())
    }

    private var yearGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
            ForEach(2023...currentYear, id: \.self) { value in
                Button {
                    choose(String(value))
                } label: {
                    Text(String(value))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 12).fill(ToggTheme.surfaceVariant))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func choose(_ anchor: String) {
        onSelect(anchor)
        dismiss()
    }
}

// MARK: - Ayrıntı

private struct ExperienceDetailSheet: View {
    let api: ToggAPI
    let vin: String
    let target: ExperienceDetailTarget
    let pricePerKWh: Double

    @Environment(\.dismiss) private var dismiss
    @State private var detail: ExperienceDetail?
    @State private var error: String?
    @State private var busy = false
    @State private var raw = ""
    @State private var generation = 0

    var body: some View {
        NavigationStack {
            ZStack {
                ToggTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if busy && detail == nil {
                            ProgressView().tint(ToggTheme.teal).padding(32)
                        }
                        if let error {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 12)).foregroundStyle(ToggTheme.pink)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(error).font(.footnote).foregroundStyle(ToggTheme.pink)
                                    Button("Tekrar dene") { Task { await load() } }
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 12).frame(height: 32)
                                        .background(Capsule().fill(ToggTheme.teal))
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 14).fill(ToggTheme.pink.opacity(0.08)))
                        }
                        if let detail {
                            detailHeader(detail)
                            if !detail.metrics.isEmpty {
                                metricsGrid(detail.metrics)
                            }
                            if !detail.notes.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(detail.notes, id: \.self) { note in
                                        Text(note).font(.system(size: 11)).foregroundStyle(ToggTheme.muted)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(RoundedRectangle(cornerRadius: 16).fill(ToggTheme.surfaceVariant.opacity(0.6)))
                            }
                            ForEach(detail.sections) { section in
                                detailSection(section)
                            }
                        }
                        if !raw.isEmpty {
                            DisclosureGroup("Teknik yanıt") {
                                Text(raw)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(ToggTheme.muted)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.caption)
                            .foregroundStyle(ToggTheme.muted)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(target.kind == .charges ? "Şarj ayrıntısı" : "Yolculuk ayrıntısı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Kapat")
                }
            }
            .task { await load() }
        }
    }

    private func detailHeader(_ detail: ExperienceDetail) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(detail.dateText.isEmpty ? "Tarih belirtilmemiş" : detail.dateText)
                .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
            if !detail.subtitle.isEmpty {
                Text(detail.subtitle)
                    .font(.system(size: 12)).foregroundStyle(ToggTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .toggCardBackground(20)
    }

    private func metricsGrid(_ metrics: [ExperienceMetric]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(metrics) { metric in
                VStack(alignment: .leading, spacing: 3) {
                    Text(metric.label)
                        .font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
                        .lineLimit(1)
                    Text(metric.value)
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.65)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(ToggTheme.surfaceVariant))
            }
        }
    }

    private func detailSection(_ section: ExperienceDetailSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            ForEach(section.metrics) { metric in
                HStack(spacing: 6) {
                    Text(metric.label)
                        .font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
                    Spacer(minLength: 6)
                    Text(metric.value)
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                }
            }
        }
        .padding(16)
        .toggCardBackground(18)
    }

    @MainActor
    private func load() async {
        generation += 1
        let token = generation
        busy = true
        error = nil
        defer { if token == generation { busy = false } }
        do {
            let data = try await api.driveExperience(
                vin: vin, kind: target.kind.detailKind, id: target.detailID
            )
            guard token == generation else { return }
            raw = String(decoding: data, as: UTF8.self)
            guard let parsed = ExperienceFormat.detail(from: data, kind: target.kind,
                                                      pricePerKWh: pricePerKWh) else {
                error = "Kayıt ayrıntısı beklenen biçimde değil."
                return
            }
            detail = parsed
        } catch {
            guard token == generation else { return }
            self.error = error.localizedDescription
        }
    }
}
