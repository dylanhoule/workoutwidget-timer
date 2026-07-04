import SwiftUI
import UserNotifications

@main
struct WorkoutIntervalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @State private var duePanel = DuePanelController()

    var body: some Scene {
        MenuBarExtra {
            RootView(model: model)
        } label: {
            // onChange lives on the always-mounted label so it fires on every
            // phase change even when the popover is closed.
            MenuBarLabel(model: model)
                .onChange(of: model.phase) { phase in
                    if phase == .due { duePanel.show(model: model) }
                    else { duePanel.hide() }
                }
        }
        .menuBarExtraStyle(.window)
    }
}

/// Observes the model from inside the label closure — a direct read from the
/// App struct can leave the menu bar icon stale on macOS 13.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Image(systemName: model.iconSymbol)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    // Show the banner even when the app counts as frontmost (popover open).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
