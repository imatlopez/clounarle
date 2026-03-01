import SwiftUI
import AppKit

/// The main menu bar view displayed when clicking the status item.
struct MenuBarView: View {
    @ObservedObject var orchestrator = SummaryOrchestrator.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Summary actions
            Button {
                Task { await orchestrator.generateNow() }
            } label: {
                Label(
                    orchestrator.isGenerating ? "Generating..." : "Generate Summary Now",
                    systemImage: orchestrator.isGenerating ? "arrow.triangle.2.circlepath" : "paperplane"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .disabled(orchestrator.isGenerating)
            .keyboardShortcut("g")

            Button {
                Task {
                    if let summary = await orchestrator.generatePreview() {
                        AppDelegate.shared?.openSummaryPreview(summary: summary)
                    }
                }
            } label: {
                Label("Preview Summary", systemImage: "eye")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .disabled(orchestrator.isGenerating)
            .keyboardShortcut("p")

            Divider().padding(.vertical, 4)

            Button {
                openClaudeProject()
            } label: {
                Label("Open Journal", systemImage: "arrow.up.forward.app")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .keyboardShortcut("j")

            Divider().padding(.vertical, 4)

            // Status
            Label(orchestrator.lastStatus.displayString, systemImage: statusIcon)
                .font(.subheadline)
                .foregroundStyle(statusColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)

            Divider().padding(.vertical, 4)

            // App controls
            Button {
                AppDelegate.shared?.openPreferences()
            } label: {
                Label("Preferences...", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .keyboardShortcut(",")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit Therapy Journal", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
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
