import SwiftUI
import AppKit

@main
struct TherapyJournalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No main window — this is a menu bar-only app
        Settings {
            PreferencesView()
        }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var preferencesWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        AppLogger.shared.info("Therapy Journal starting up")

        // Request notification permission
        NotificationManager.shared.requestPermission()

        // Set up status bar item
        setupStatusItem()

        // Start the nightly scheduler
        NightlyScheduler.shared.start()

        AppLogger.shared.info("Therapy Journal ready")
    }

    func applicationWillTerminate(_ notification: Notification) {
        NightlyScheduler.shared.stop()
        AppLogger.shared.info("Therapy Journal shutting down")
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "book.closed", accessibilityDescription: "Therapy Journal")
            button.action = #selector(togglePopover)
            button.target = self
        }

        let popover = NSPopover()
        popover.contentViewController = NSHostingController(rootView: MenuBarView())
        popover.behavior = .transient
        self.popover = popover
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            // Ensure the popover's window can become key
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Preferences Window

    func openPreferences() {
        if preferencesWindow == nil {
            let prefsView = PreferencesView()
            let hostingController = NSHostingController(rootView: prefsView)

            let window = NSWindow(contentViewController: hostingController)
            window.title = "Therapy Journal Preferences"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 520, height: 460))
            window.center()
            self.preferencesWindow = window
        }

        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
