import AppKit

enum LaunchNextHelper {

    static func launch() {

        let url =
            URL(
                fileURLWithPath:
                    "/Applications/LaunchNext.app"
            )

        let configuration =
            NSWorkspace.OpenConfiguration()

        configuration.activates = true

        NSWorkspace.shared.openApplication(
            at: url,
            configuration: configuration
        ) { _, error in

            if let error {

                print(
                    "LaunchNext error:",
                    error.localizedDescription
                )
            }
        }
    }
}
