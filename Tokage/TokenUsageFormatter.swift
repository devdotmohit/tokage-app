import Foundation

struct TokenUsageFormatter {
    struct TokenBreakdown: Identifiable {
        enum Kind: String {
            case input
            case cached
            case output
            case reasoning
        }

        let kind: Kind
        let label: String
        let tokensText: String
        let costText: String

        var id: Kind { kind }

        var iconSystemName: String {
            switch kind {
            case .input:
                return "tray.and.arrow.down"
            case .cached:
                return "internaldrive"
            case .output:
                return "arrow.up.right"
            case .reasoning:
                return "brain.head.profile"
            }
        }
    }

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

    func breakdown(for totals: TokenTotals) -> [TokenBreakdown] {
        [
            TokenBreakdown(
                kind: .input,
                label: "Input",
                tokensText: formatTokens(totals.inputTokens),
                costText: formatCurrency(for: cost(tokens: totals.inputTokens, rate: Pricing.input))
            ),
            TokenBreakdown(
                kind: .cached,
                label: "Cached",
                tokensText: formatTokens(totals.cachedInputTokens),
                costText: formatCurrency(for: cost(tokens: totals.cachedInputTokens, rate: Pricing.cache))
            ),
            TokenBreakdown(
                kind: .output,
                label: "Output",
                tokensText: formatTokens(totals.outputTokens),
                costText: formatCurrency(for: cost(tokens: totals.outputTokens, rate: Pricing.output))
            ),
            TokenBreakdown(
                kind: .reasoning,
                label: "Reasoning",
                tokensText: formatTokens(totals.reasoningOutputTokens),
                costText: formatCurrency(for: cost(tokens: totals.reasoningOutputTokens, rate: Pricing.reasoning))
            )
        ]
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
        let cost = cost(tokens: totals.inputTokens, rate: Pricing.input) +
            cost(tokens: totals.cachedInputTokens, rate: Pricing.cache) +
            cost(tokens: totals.outputTokens, rate: Pricing.output) +
            cost(tokens: totals.reasoningOutputTokens, rate: Pricing.reasoning)

        return formatCurrency(for: cost)
    }

    private func cost(tokens: Int, rate: Double) -> Double {
        (Double(tokens) * rate) / 1_000_000
    }

    private func formatCurrency(for cost: Double) -> String {
        String(format: "$%.2f", cost)
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
