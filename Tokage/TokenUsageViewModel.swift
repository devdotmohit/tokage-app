import Combine
import Foundation

@MainActor
final class TokenUsageViewModel: ObservableObject {
    @Published private(set) var dailyUsages: [DailyTokenUsage] = []
    @Published private(set) var lastUpdated: Date?
    @Published var errorMessage: String?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var todayUsage: UsageAggregate?
    @Published private(set) var historicalSummaries: [HistoricalSummary] = []
    @Published private(set) var monthSummary: MonthlySummary?

    private let service: TokenUsageService
    private let calendar = Calendar.current
    private lazy var dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    private lazy var monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()
    private var timerCancellable: AnyCancellable?
    private var historicalCache: [String: UsageAggregate] = [:]
    private var monthCache: [String: UsageAggregate] = [:]
    private var lastTodayUsageByMonth: [String: UsageAggregate] = [:]
    private var lastDayKeyByMonth: [String: String] = [:]
    private let hasSeenUsageDataKey = "TokageHasSeenUsageData"

    private var hasSeenUsageData: Bool {
        get { UserDefaults.standard.bool(forKey: hasSeenUsageDataKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasSeenUsageDataKey) }
    }

    init(service: TokenUsageService? = nil) {
        self.service = service ?? TokenUsageService()
        refresh()
        startTimer()
    }

    deinit {
        timerCancellable?.cancel()
    }

    func refresh() {
        guard isLoading == false else { return }
        isLoading = true
        errorMessage = nil

        let service = self.service
        Task(priority: .background) { [weak self] in
            guard let self = self else { return }
            let referenceDate = Date()
            var usage: [DailyTokenUsage] = []
            var newTodayUsage: UsageAggregate?
            var terminalError: Error?

            do {
                usage = try service.fetchDailyUsage(for: referenceDate)
                newTodayUsage = usage.first?.aggregate
            } catch let tokenError as TokenUsageError {
                switch tokenError {
                case .missingMonthDirectory:
                    newTodayUsage = .zero
                case .missingSessionsDirectory:
                    terminalError = tokenError
                }
            } catch {
                terminalError = error
            }

            if let terminalError {
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    if let tokenError = terminalError as? TokenUsageError,
                       case .missingSessionsDirectory = tokenError {
                        self.dailyUsages = []
                        self.todayUsage = .zero
                        self.isLoading = false
                        self.errorMessage = nil
                        self.lastUpdated = Date()
                        if self.hasSeenUsageData == false {
                            self.historicalSummaries = []
                            self.monthSummary = nil
                        }
                        return
                    }

                    self.dailyUsages = []
                    self.todayUsage = nil
                    self.isLoading = false
                    self.errorMessage = terminalError.localizedDescription
                    self.historicalSummaries = []
                    self.monthSummary = nil
                }
                return
            }

            let plan = await MainActor.run {
                self.makeComputationPlan(referenceDate: referenceDate)
            }

            let fetchResult = TokenUsageViewModel.performBackgroundFetch(
                plan: plan,
                referenceDate: referenceDate,
                service: service
            )

            await MainActor.run { [weak self] in
                guard let self = self else { return }

                for (key, aggregate) in fetchResult.historical {
                    self.historicalCache[key] = aggregate
                }

                let historical = self.buildHistoricalSummaries(plan: plan)
                let monthSummary = self.updateMonthSummary(
                    referenceDate: referenceDate,
                    todayUsage: newTodayUsage,
                    prefetchedTotals: fetchResult.monthTotals
                )

                let sawData = (newTodayUsage?.isZero == false)
                    || (fetchResult.historical.isEmpty == false)
                    || (fetchResult.monthTotals != nil)
                if sawData {
                    self.hasSeenUsageData = true
                }

                self.dailyUsages = usage
                self.todayUsage = newTodayUsage
                self.lastUpdated = Date()
                self.isLoading = false
                self.historicalSummaries = historical
                self.monthSummary = monthSummary
            }
        }
    }

    private func startTimer() {
        timerCancellable = Timer.publish(every: 300, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }
}

extension TokenUsageViewModel {
    struct HistoricalSummary: Identifiable {
        let id: String
        let label: String
        let date: Date
        let aggregate: UsageAggregate
    }

    struct MonthlySummary: Identifiable {
        let id: String
        let label: String
        let date: Date
        let aggregate: UsageAggregate
    }

    private struct HistoricalDatePlan {
        let date: Date
        let key: String
        let isYesterday: Bool
    }

    private struct ComputationPlan {
        let historicalDates: [HistoricalDatePlan]
        let missingHistorical: [HistoricalDatePlan]
        let monthKey: String
        let needsMonthFetch: Bool
    }

    private struct BackgroundFetchResult {
        let historical: [String: UsageAggregate]
        let monthTotals: UsageAggregate?
    }

    var formattedLastUpdated: String {
        guard let lastUpdated else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return "Updated \(formatter.string(from: lastUpdated))"
    }

    var todaySummaryText: String? {
        guard let todayUsage else { return nil }
        return TokenUsageFormatter.shared.summary(usage: todayUsage)
    }

    var menuBarSummaryText: String {
        if isLoading {
            return "Loading…"
        }
        return todaySummaryText ?? "Token Usage"
    }

    var menuBarIconName: String {
        isLoading ? "hourglass" : "chart.bar.fill"
    }

    private func buildHistoricalSummaries(plan: ComputationPlan) -> [HistoricalSummary] {
        plan.historicalDates.compactMap { item in
            guard let aggregate = historicalCache[item.key] else { return nil }
            let label = item.isYesterday ? "Yesterday" : formattedDateLabel(for: item.date)
            return HistoricalSummary(id: item.key, label: label, date: item.date, aggregate: aggregate)
        }
    }

    private func dayKey(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private func formattedDateLabel(for date: Date) -> String {
        let components = calendar.dateComponents([.day, .month, .year], from: date)
        guard
            let day = components.day,
            let month = components.month,
            let year = components.year
        else {
            return dayFormatter.string(from: date)
        }

        let monthName = dayFormatter.monthSymbols[month - 1]
        return "\(ordinal(for: day)) \(monthName) \(year)"
    }

    private func ordinal(for day: Int) -> String {
        let suffix: String
        let ones = day % 10
        let tens = (day / 10) % 10

        if tens == 1 {
            suffix = "th"
        } else {
            switch ones {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }

        return "\(day)\(suffix)"
    }

    private func updateMonthSummary(
        referenceDate: Date,
        todayUsage: UsageAggregate?,
        prefetchedTotals: UsageAggregate?
    ) -> MonthlySummary? {
        let key = monthKey(for: referenceDate)
        let monthName = monthLabel(for: referenceDate)
        let label = "This Month (\(monthName))"
        let currentDayKey = dayKey(for: referenceDate)

        if lastDayKeyByMonth[key] != currentDayKey {
            lastTodayUsageByMonth[key] = .zero
        }

        var monthTotals: UsageAggregate?

        if let prefetchedTotals {
            monthTotals = prefetchedTotals
            monthCache[key] = prefetchedTotals
            lastTodayUsageByMonth[key] = todayUsage ?? .zero
            lastDayKeyByMonth[key] = currentDayKey
        } else {
            monthTotals = monthCache[key]
        }

        if monthTotals == nil {
            return nil
        } else if let todayUsage {
            let previousToday = lastTodayUsageByMonth[key] ?? .zero
            if todayUsage != previousToday {
                let delta = difference(between: todayUsage, and: previousToday)
                monthTotals = monthTotals!.adding(delta)
                monthCache[key] = monthTotals
                lastTodayUsageByMonth[key] = todayUsage
                lastDayKeyByMonth[key] = currentDayKey
            }
        } else {
            lastTodayUsageByMonth[key] = .zero
            lastDayKeyByMonth[key] = currentDayKey
        }

        guard let aggregate = monthTotals else {
            return nil
        }

        return MonthlySummary(id: key, label: label, date: referenceDate, aggregate: aggregate)
    }

    private func monthKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let year = components.year, let month = components.month else {
            return dayKey(for: date)
        }
        return String(format: "%04d-%02d", year, month)
    }

    private func monthLabel(for date: Date) -> String {
        monthFormatter.string(from: date)
    }

    private func difference(between current: UsageAggregate, and previous: UsageAggregate) -> UsageAggregate {
        UsageAggregate(
            totals: TokenTotals(
                inputTokens: max(current.totals.inputTokens - previous.totals.inputTokens, 0),
                cachedInputTokens: max(current.totals.cachedInputTokens - previous.totals.cachedInputTokens, 0),
                outputTokens: max(current.totals.outputTokens - previous.totals.outputTokens, 0),
                reasoningOutputTokens: max(current.totals.reasoningOutputTokens - previous.totals.reasoningOutputTokens, 0),
                totalTokens: max(current.totals.totalTokens - previous.totals.totalTokens, 0)
            ),
            costs: CostTotals(
                inputCost: max(current.costs.inputCost - previous.costs.inputCost, 0),
                cachedInputCost: max(current.costs.cachedInputCost - previous.costs.cachedInputCost, 0),
                outputCost: max(current.costs.outputCost - previous.costs.outputCost, 0),
                reasoningCost: max(current.costs.reasoningCost - previous.costs.reasoningCost, 0)
            )
        )
    }

    private func makeComputationPlan(referenceDate: Date) -> ComputationPlan {
        let offsets = (1...6)
        var historicalDates: [HistoricalDatePlan] = []
        var missing: [HistoricalDatePlan] = []

        for offset in offsets {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: referenceDate) else {
                continue
            }
            let key = dayKey(for: date)
            let plan = HistoricalDatePlan(date: date, key: key, isYesterday: offset == 1)
            historicalDates.append(plan)
            if historicalCache[key] == nil {
                missing.append(plan)
            }
        }

        let monthKey = monthKey(for: referenceDate)
        let needsMonthFetch = monthCache[monthKey] == nil

        return ComputationPlan(
            historicalDates: historicalDates,
            missingHistorical: missing,
            monthKey: monthKey,
            needsMonthFetch: needsMonthFetch
        )
    }

    private static func performBackgroundFetch(
        plan: ComputationPlan,
        referenceDate: Date,
        service: TokenUsageService
    ) -> BackgroundFetchResult {
        var historical: [String: UsageAggregate] = [:]
        for item in plan.missingHistorical {
            if
                let usage = try? service.fetchDailyUsage(for: item.date),
                let aggregate = usage.first?.aggregate
            {
                historical[item.key] = aggregate
            }
        }

        let monthTotals: UsageAggregate?
        if plan.needsMonthFetch {
            monthTotals = try? service.fetchMonthlyTotals(for: referenceDate)
        } else {
            monthTotals = nil
        }

        return BackgroundFetchResult(historical: historical, monthTotals: monthTotals)
    }
}
