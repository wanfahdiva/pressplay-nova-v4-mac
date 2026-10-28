import AppKit
import SwiftUI
import V4Kit

@main
struct NovaV4App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("NOVA V4", id: "main") {
            ContentView()
                .environment(appDelegate.store)
                .frame(minWidth: 760, minHeight: 520)
        }
        .windowResizability(.contentMinSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = DeviceStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Running from `swift run` leaves the process as a background app otherwise.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            // Flush a pending write, but don't hang on a missing mouse.
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.store.shutdown() }
                group.addTask { try? await Task.sleep(for: .seconds(2)) }
                await group.next()
                group.cancelAll()
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
