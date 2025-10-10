import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var viewModel: TokenUsageViewModel
    private let formatter = TokenUsageFormatter.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            statusLine
            content
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 480)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if let summaryText = viewModel.todaySummaryText {
                    Text(summaryText)
                        .font(.subheadline)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Daily Token Usage")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            Button(action: viewModel.refresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .labelStyle(.iconOnly)
            .help("Refresh now")
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if !viewModel.formattedLastUpdated.isEmpty {
            Text(viewModel.formattedLastUpdated)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let message = viewModel.errorMessage {
            Text(message)
                .foregroundStyle(Color.red)
        } else if viewModel.dailyUsages.isEmpty {
            if viewModel.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading token usage…")
                }
            } else {
                Text("No token usage found for today.")
                    .foregroundStyle(.secondary)
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.dailyUsages) { usage in
                        Text(formatter.header(for: usage))
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(nsColor: NSColor.windowBackgroundColor))
                                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                            )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

#Preview {
    ContentView(viewModel: TokenUsageViewModel())
}
