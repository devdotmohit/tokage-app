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
        "\(usage.displayDate) — \(formatTokens(usage.aggregate.billingTokenTotal)) • \(formatCurrency(for: usage.costs.totalCost))"
    }

    func summary(usage: UsageAggregate) -> String {
        "\(formatTokens(usage.billingTokenTotal)) • \(formatCurrency(for: usage.costs.totalCost))"
    }

    func breakdown(for usage: UsageAggregate) -> [TokenBreakdown] {
        let totals = usage.totals
        let costs = usage.costs
        return [
            TokenBreakdown(
                kind: .input,
                label: "Input",
                tokensText: formatTokens(totals.billedInputTokens),
                costText: formatCurrency(for: costs.inputCost)
            ),
            TokenBreakdown(
                kind: .cached,
                label: "Cached",
                tokensText: formatTokens(totals.cachedInputTokens),
                costText: formatCurrency(for: costs.cachedInputCost)
            ),
            TokenBreakdown(
                kind: .output,
                label: "Output",
                tokensText: formatTokens(totals.outputTokens),
                costText: formatCurrency(for: costs.outputCost)
            ),
            TokenBreakdown(
                kind: .reasoning,
                label: "Reasoning",
                tokensText: formatTokens(totals.reasoningOutputTokens),
                costText: formatCurrency(for: costs.reasoningCost)
            )
        ]
    }

    private func formatTokens(_ value: Int) -> String {
        switch abs(value) {
        case 1_000_000_000...:
            return formatCompact(Double(value) / 1_000_000_000, suffix: "B")
        case 1_000_000...:
            return formatCompact(Double(value) / 1_000_000, suffix: "M")
        case 1_000...:
            return formatCompact(Double(value) / 1_000, suffix: "K")
        default:
            return "\(value)"
        }
    }

    private func formatCurrency(for cost: Double) -> String {
        String(format: "$%.2f", cost)
    }

    private func formatCompact(_ value: Double, suffix: String) -> String {
        let formatted = String(format: "%.2f", value)
        let trimmed: String
        if formatted.contains(".") {
            let trimmedZeros = formatted.replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            trimmed = trimmedZeros.hasSuffix(".") ? String(trimmedZeros.dropLast()) : trimmedZeros
        } else {
            trimmed = formatted
        }
        return trimmed + suffix
    }
}
