//
//  TokageApp.swift
//  Tokage
//
//  Created by Mohit on 10/10/25.
//

import SwiftUI
import AppKit

@main
@available(macOS 13.0, *)
struct TokageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = TokenUsageViewModel()

    var body: some Scene {
        MenuBarExtra(isInserted: .constant(true)) {
            MenuContent(viewModel: viewModel)
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

private struct MenuContent: View {
    @ObservedObject var viewModel: TokenUsageViewModel
    private let formatter = TokenUsageFormatter.shared

    var body: some View {
        if let totals = viewModel.todayTotals {
            TokenBreakdownMenu(totals: totals)
            Divider()
        }

        if viewModel.historicalSummaries.isEmpty == false || viewModel.monthSummary != nil {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recent")
                    .font(.headline)
                ForEach(viewModel.historicalSummaries) { summary in
                    Button(action: {}) {
                        Label("\(summary.label): \(formatter.summary(totals: summary.totals))", systemImage: "calendar")
                    }
                    .buttonStyle(.borderless)
                }
                if let monthSummary = viewModel.monthSummary {
                    if viewModel.historicalSummaries.isEmpty == false {
                        Divider()
                    }
                    Button(action: {}) {
                        Label("\(monthSummary.label): \(formatter.summary(totals: monthSummary.totals))", systemImage: "calendar.badge.clock")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.vertical, 6)
            Divider()
        }

        Button("Refresh Now") {
            viewModel.refresh()
        }
        .keyboardShortcut("r")

        Button("Quit Tokage") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
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

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
