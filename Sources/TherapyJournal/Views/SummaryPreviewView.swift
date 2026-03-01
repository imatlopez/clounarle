import SwiftUI

/// Preview window showing a generated summary with an option to send to the user only.
struct SummaryPreviewView: View {
    let summary: JournalSummary
    @State private var isSending = false
    @State private var sentConfirmation = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Summary Preview")
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding([.horizontal, .top], 16)
            .padding(.bottom, 12)

            Divider()

            // Summary content
            ScrollView {
                Text(summary.content)
                    .font(.system(.body, design: .default))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .textSelection(.enabled)
            }

            Divider()

            // Action bar
            HStack {
                if sentConfirmation {
                    Label("Sent to your email", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.escape)
                Button {
                    Task { await sendToMeOnly() }
                } label: {
                    if isSending {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                        Text("Sending...")
                    } else {
                        Text("Send to Me Only")
                    }
                }
                .disabled(isSending || sentConfirmation)
                .keyboardShortcut("s")
            }
            .padding(12)
        }
        .frame(width: 600, height: 520)
    }

    private var subtitle: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM d"
        return "\(fmt.string(from: summary.periodStart)) – \(fmt.string(from: summary.periodEnd))"
    }

    private func sendToMeOnly() async {
        isSending = true
        let config = AppConfig.load()
        guard !config.userEmail.isEmpty else {
            isSending = false
            return
        }
        do {
            try await EmailService.shared.sendToRecipients(
                [config.userEmail],
                subject: summary.emailSubject,
                body: summary.emailBodyHTML
            )
            sentConfirmation = true
        } catch {
            AppLogger.shared.error("Preview send failed: \(error.localizedDescription)")
        }
        isSending = false
    }
}
