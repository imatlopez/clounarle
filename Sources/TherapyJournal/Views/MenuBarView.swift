import SwiftUI
import AppKit

/// The main menu bar view displayed when clicking the status item.
struct MenuBarView: View {
    @ObservedObject var orchestrator = SummaryOrchestrator.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Generate Summary Now
            Button {
                Task {
                    await orchestrator.generateNow()
                }
            } label: {
                HStack {
                    Image(systemName: orchestrator.isGenerating ? "arrow.triangle.2.circlepath" : "text.badge.checkmark")
                    Text(orchestrator.isGenerating ? "Generating..." : "Generate Summary Now")
                }
            }
            .disabled(orchestrator.isGenerating)
            .keyboardShortcut("g")

            // Preview Summary
            Button {
                Task {
                    if let summary = await orchestrator.generatePreview() {
                        AppDelegate.shared?.openSummaryPreview(summary: summary)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "eye")
                    Text("Preview Summary")
                }
            }
            .disabled(orchestrator.isGenerating)
            .keyboardShortcut("p")

            Divider()

            // Open Claude Journal Project
            Button {
                openClaudeProject()
            } label: {
                HStack {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                    Text("Open Claude Journal Project")
                }
            }
            .keyboardShortcut("j")

            Divider()

            // Last Summary Status
            HStack {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                Text("Last summary: \(orchestrator.lastStatus.displayString)")
                    .font(.caption)
            }
            .padding(.horizontal, 4)

            Divider()

            // Preferences
            Button {
                AppDelegate.shared?.openPreferences()
            } label: {
                HStack {
                    Image(systemName: "gear")
                    Text("Preferences...")
                }
            }
            .keyboardShortcut(",")

            Divider()

            // Quit
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Image(systemName: "power")
                    Text("Quit Therapy Journal")
                }
            }
            .keyboardShortcut("q")
        }
        .padding(8)
        .frame(width: 280)
    }

    // MARK: - Helpers

    private var statusIcon: String {
        switch orchestrator.lastStatus {
        case .sent: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .skipped: return "exclamationmark.circle"
        case .none: return "minus.circle"
        }
    }

    private var statusColor: Color {
        switch orchestrator.lastStatus {
        case .sent: return .green
        case .failed: return .red
        case .skipped: return .yellow
        case .none: return .secondary
        }
    }

    private func openClaudeProject() {
        let config = AppConfig.load()
        let urlString = config.claudeProjectURL.isEmpty ? "https://claude.ai" : config.claudeProjectURL
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
