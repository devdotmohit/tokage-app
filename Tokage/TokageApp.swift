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
