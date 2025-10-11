import Combine
import Foundation

@MainActor
final class TokenUsageViewModel: ObservableObject {
    @Published private(set) var dailyUsages: [DailyTokenUsage] = []
    @Published private(set) var lastUpdated: Date?
    @Published var errorMessage: String?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var todayTotals: TokenTotals?
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
    private var historicalCache: [String: TokenTotals] = [:]
    private var monthCache: [String: TokenTotals] = [:]
    private var lastTodayTotalsByMonth: [String: TokenTotals] = [:]
    private var lastDayKeyByMonth: [String: String] = [:]

    init(service: TokenUsageService = TokenUsageService()) {
        self.service = service
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
            do {
                guard let self = self else { return }
                let referenceDate = Date()
                let usage = try service.fetchDailyUsage(for: referenceDate)
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

                    for (key, totals) in fetchResult.historical {
                        self.historicalCache[key] = totals
                    }

                    let historical = self.buildHistoricalSummaries(plan: plan)
                    let newTodayTotals = usage.first?.totals
                    let monthSummary = self.updateMonthSummary(
                        referenceDate: referenceDate,
                        todayTotals: newTodayTotals,
                        prefetchedTotals: fetchResult.monthTotals
                    )

                    self.dailyUsages = usage
                    self.todayTotals = newTodayTotals
                    self.lastUpdated = Date()
                    self.isLoading = false
                    self.historicalSummaries = historical
                    self.monthSummary = monthSummary
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.dailyUsages = []
                    self.todayTotals = nil
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                    self.historicalSummaries = []
                    self.monthSummary = nil
                }
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
        let totals: TokenTotals
    }

    struct MonthlySummary: Identifiable {
        let id: String
        let label: String
        let date: Date
        let totals: TokenTotals
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
        let historical: [String: TokenTotals]
        let monthTotals: TokenTotals?
    }

    var formattedLastUpdated: String {
        guard let lastUpdated else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return "Updated \(formatter.string(from: lastUpdated))"
    }

    var todaySummaryText: String? {
        guard let totals = todayTotals else { return nil }
        return TokenUsageFormatter.shared.summary(totals: totals)
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
            guard let totals = historicalCache[item.key] else { return nil }
            let label = item.isYesterday ? "Yesterday" : formattedDateLabel(for: item.date)
            return HistoricalSummary(id: item.key, label: label, date: item.date, totals: totals)
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

    private func updateMonthSummary(referenceDate: Date, todayTotals: TokenTotals?, prefetchedTotals: TokenTotals?) -> MonthlySummary? {
        let key = monthKey(for: referenceDate)
        let monthName = monthLabel(for: referenceDate)
        let label = "This Month (\(monthName))"
        let currentDayKey = dayKey(for: referenceDate)

        if lastDayKeyByMonth[key] != currentDayKey {
            lastTodayTotalsByMonth[key] = .zero
        }

        var monthTotals: TokenTotals?

        if let prefetchedTotals = prefetchedTotals {
            monthTotals = prefetchedTotals
            monthCache[key] = prefetchedTotals
            lastTodayTotalsByMonth[key] = todayTotals ?? .zero
            lastDayKeyByMonth[key] = currentDayKey
        } else {
            monthTotals = monthCache[key]
        }

        if monthTotals == nil {
            return nil
        } else if let todayTotals {
            let previousToday = lastTodayTotalsByMonth[key] ?? .zero
            if todayTotals != previousToday {
                let delta = difference(between: todayTotals, and: previousToday)
                monthTotals = monthTotals!.adding(delta)
                monthCache[key] = monthTotals
                lastTodayTotalsByMonth[key] = todayTotals
                lastDayKeyByMonth[key] = currentDayKey
            }
        } else {
            lastTodayTotalsByMonth[key] = .zero
            lastDayKeyByMonth[key] = currentDayKey
        }

        guard let totals = monthTotals else {
            return nil
        }

        return MonthlySummary(id: key, label: label, date: referenceDate, totals: totals)
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

    private func difference(between current: TokenTotals, and previous: TokenTotals) -> TokenTotals {
        TokenTotals(
            inputTokens: max(current.inputTokens - previous.inputTokens, 0),
            cachedInputTokens: max(current.cachedInputTokens - previous.cachedInputTokens, 0),
            outputTokens: max(current.outputTokens - previous.outputTokens, 0),
            reasoningOutputTokens: max(current.reasoningOutputTokens - previous.reasoningOutputTokens, 0),
            totalTokens: max(current.totalTokens - previous.totalTokens, 0)
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

    private static func performBackgroundFetch(plan: ComputationPlan, referenceDate: Date, service: TokenUsageService) -> BackgroundFetchResult {
        var historical: [String: TokenTotals] = [:]
        for item in plan.missingHistorical {
            if
                let usage = try? service.fetchDailyUsage(for: item.date),
                let totals = usage.first?.totals
            {
                historical[item.key] = totals
            }
        }

        let monthTotals: TokenTotals?
        if plan.needsMonthFetch {
            monthTotals = try? service.fetchMonthlyTotals(for: referenceDate)
        } else {
            monthTotals = nil
        }

        return BackgroundFetchResult(historical: historical, monthTotals: monthTotals)
    }
}
