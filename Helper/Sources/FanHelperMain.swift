import Foundation
import GlassWorkCore

/// LaunchDaemon that changes fan speed for GlassWork. It accepts fan commands from the signed app
/// and gives the fans back to the system whenever the app is gone.
@main
enum FanHelperMain {
    static func main() {
        guard let smc = SMCWriter() else { exit(EXIT_FAILURE) }
        let server = FanHelperServer(
            service: FanHelperService(smc: smc),
            queue: DispatchQueue(label: FanHelperIdentity.helperIdentifier),
            // Same team as this binary. An unsigned helper gets nil and refuses every connection.
            requirement: FanHelperIdentity.requirement(
                identifier: FanHelperIdentity.appIdentifier,
                team: FanHelperIdentity.currentTeam()
            ),
            now: FanClock.now
        )
        server.start()

        let listener = NSXPCListener(machServiceName: FanHelperIdentity.machService)
        listener.delegate = server
        listener.resume()

        // launchd sends SIGTERM on removal and at shutdown.
        signal(SIGTERM, SIG_IGN)
        let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termination.setEventHandler {
            exit(server.shutdown() ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        termination.resume()

        withExtendedLifetime((listener, termination)) {
            dispatchMain()
        }
    }
}
