import Foundation

struct TokenUsageFormatter {
    static let shared = TokenUsageFormatter()

    private init() {
    }

    func header(for usage: DailyTokenUsage) -> String {
        let totals = usage.totals
        return "\(usage.displayDate) — \(formatTokens(totals.totalTokens)) • \(formatCost(for: totals))"
    }

    func summary(totals: TokenTotals) -> String {
        "\(formatTokens(totals.totalTokens)) • \(formatCost(for: totals))"
    }

    private func formatTokens(_ value: Int) -> String {
        switch abs(value) {
        case 1_000_000...:
            return formatCompact(Double(value) / 1_000_000, suffix: "M")
        case 1_000...:
            return formatCompact(Double(value) / 1_000, suffix: "K")
        default:
            return "\(value)"
        }
    }

    private func formatCost(for totals: TokenTotals) -> String {
        let cost = Pricing.input * Double(totals.inputTokens) +
            Pricing.cache * Double(totals.cachedInputTokens) +
            Pricing.output * Double(totals.outputTokens) +
            Pricing.reasoning * Double(totals.reasoningOutputTokens)

        return String(format: "$%.2f", cost / 1_000_000)
    }

    private func formatCompact(_ value: Double, suffix: String) -> String {
        let formatted = String(format: "%.1f", value)
        let trimmed = formatted.hasSuffix(".0") ? String(formatted.dropLast(2)) : formatted
        return trimmed + suffix
    }
}

private enum Pricing {
    static let input = 1.25
    static let cache = 0.125
    static let output = 10.00
    static let reasoning = 10.00
}
