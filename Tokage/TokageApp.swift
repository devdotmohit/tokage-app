//
//  TokageApp.swift
//  Tokage
//
//  Created by Mohit on 10/10/25.
//

import SwiftUI

@main
struct TokageApp: App {
    @StateObject private var viewModel = TokenUsageViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }

        if #available(macOS 13.0, *) {
            MenuBarExtra(isInserted: .constant(true)) {
                if let totals = viewModel.todayTotals {
                    TokenBreakdownMenu(totals: totals)
                    Divider()
                }
                Button("Refresh Now") {
                    viewModel.refresh()
                }
                .keyboardShortcut("r")
            } label: {
                Label {
                    Text(viewModel.menuBarSummaryText)
                } icon: {
                    Image(systemName: viewModel.menuBarIconName)
                }
                .labelStyle(.titleAndIcon)
            }
        }
    }
}

@available(macOS 13.0, *)
private struct TokenBreakdownMenu: View {
    let totals: TokenTotals
    private let formatter = TokenUsageFormatter.shared

    var body: some View {
        let items = formatter.breakdown(for: totals)
        VStack(alignment: .leading, spacing: 6) {
            Text("Today")
                .font(.headline)
            ForEach(items) { item in
                Button(action: {}) {
                    Label("\(item.label): \(item.tokensText) • \(item.costText)", systemImage: item.iconSystemName)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
