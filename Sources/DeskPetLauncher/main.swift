@preconcurrency import AppKit
@preconcurrency import Carbon.HIToolbox

@main
@MainActor
final class DeskPetLauncher: NSObject, NSApplicationDelegate {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.prohibited)
        hotKeyObserver = NotificationCenter.default.addObserver(
            forName: .deskPetLauncherHotKeyPressed,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                (NSApp.delegate as? DeskPetLauncher)?.handleHotKey()
            }
        }
        registerHotKey()
    }

    static func main() {
        let app = NSApplication.shared
        let delegate = DeskPetLauncher()
        app.delegate = delegate
        app.run()
    }

    private func registerHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .deskPetLauncherHotKeyPressed, object: nil)
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        let hotKeyID = EventHotKeyID(signature: Self.fourCharacterCode("DPLn"), id: 1)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_D),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func handleHotKey() {
        if isDeskPetRunning {
            DistributedNotificationCenter.default().postNotificationName(
                .deskPetToggleRequested,
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            return
        }

        NSWorkspace.shared.openApplication(
            at: deskPetAppURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            if let error {
                NSLog("DeskPetLauncher failed to open DeskPet: \(error.localizedDescription)")
            }
        }
    }

    private var isDeskPetRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == "com.local.DeskPet" || app.localizedName == "DeskPet"
        }
    }

    private var deskPetAppURL: URL {
        Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("DeskPet.app")
    }

    private static func fourCharacterCode(_ text: String) -> OSType {
        var result: OSType = 0
        for scalar in text.unicodeScalars.prefix(4) {
            result = (result << 8) + OSType(scalar.value)
        }
        return result
    }
}

extension Notification.Name {
    static let deskPetToggleRequested = Notification.Name("DeskPetToggleRequested")
    static let deskPetLauncherHotKeyPressed = Notification.Name("DeskPetLauncherHotKeyPressed")
}
