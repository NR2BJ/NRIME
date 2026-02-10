import Cocoa
import InputMethodKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var server: IMKServer!
    var candidatesWindow: IMKCandidates!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let connectionName = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String
            ?? Bundle.main.bundleIdentifier! + "_Connection"

        server = IMKServer(
            name: connectionName,
            bundleIdentifier: Bundle.main.bundleIdentifier
        )

        candidatesWindow = IMKCandidates(
            server: server,
            panelType: kIMKSingleColumnScrollingCandidatePanel
        )

        InputSourceRecovery.shared.startMonitoring()

        NSLog("NRIME: Server started with connection name: \(connectionName)")
    }
}
