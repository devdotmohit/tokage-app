//
//  TokageApp.swift
//  Tokage
//
//  Created by Mohit on 10/10/25.
//

import SwiftUI
import AppKit
import Sparkle
import Combine
import ServiceManagement

@main
@available(macOS 13.0, *)
struct TokageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = TokenUsageViewModel()
    @StateObject private var updaterStore = UpdaterStore()
    @StateObject private var loginItemController = LoginItemController()

    var body: some Scene {
        MenuBarExtra(isInserted: .constant(true)) {
            MenuContent(
                viewModel: viewModel,
                updaterController: updaterStore.updaterController,
                loginItemController: loginItemController
            )
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
    let updaterController: SPUStandardUpdaterController
    @ObservedObject var loginItemController: LoginItemController
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

        CheckForUpdatesView(updaterController: updaterController)

        Toggle("Launch at Login", isOn: Binding(
            get: { loginItemController.isEnabled },
            set: { loginItemController.setEnabled($0) }
        ))

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

@MainActor
private struct CheckForUpdatesView: View {
    let updaterController: SPUStandardUpdaterController

    var body: some View {
        Button("Check for Updates...") {
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async {
                updaterController.checkForUpdates(nil)
            }
        }
        .disabled(!updaterController.updater.canCheckForUpdates)
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

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var isEnabled: Bool

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Failed to update login item: %@", error.localizedDescription)
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}

@MainActor
private final class UpdaterStore: ObservableObject {
    let updaterController: SPUStandardUpdaterController
    let objectWillChange = ObservableObjectPublisher()
    private let updaterDelegate = UpdaterDelegate()

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )
    }
}

private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        if let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String {
            return feedURL
        }
        return "https://tokage.app/appcast.xml"
    }
}
