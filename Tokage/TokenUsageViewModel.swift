import Combine
import Foundation

@MainActor
final class TokenUsageViewModel: ObservableObject {
    @Published private(set) var dailyUsages: [DailyTokenUsage] = []
    @Published private(set) var lastUpdated: Date?
    @Published var errorMessage: String?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var todayTotals: TokenTotals?

    private let service: TokenUsageService
    private var timerCancellable: AnyCancellable?

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
                let usage = try service.fetchDailyUsage()
                await MainActor.run {
                    guard let self else { return }
                    self.dailyUsages = usage
                    self.todayTotals = usage.first?.totals
                    self.lastUpdated = Date()
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.dailyUsages = []
                    self.todayTotals = nil
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func startTimer() {
        timerCancellable = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }
}

extension TokenUsageViewModel {
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
}
