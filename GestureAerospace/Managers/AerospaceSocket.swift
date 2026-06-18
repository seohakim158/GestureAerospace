import Foundation
import Socket

enum AerospaceError: Error {
    case socket(String)
    case command(String)
    case unknown(String)
}

final class AerospaceSocket {

    private var socket: Socket?

    init() {
        connect()
    }

    func connect(
        reconnect: Bool = false
    ) {

        if socket != nil && !reconnect {
            return
        }

        let path =
            "/tmp/bobko.aerospace-\(NSUserName()).sock"

        do {

            socket = try Socket.create(
                family: .unix,
                type: .stream,
                proto: .unix
            )

            try socket?.connect(to: path)

        } catch {
            print(error.localizedDescription)
        }
    }
}

extension AerospaceSocket {

    func runCommand(
        args: [String],
        stdin: String = "",
        retry: Bool = false
    ) -> Result<String, AerospaceError> {

        guard let socket else {

            return .failure(
                .socket("Socket unavailable")
            )
        }

        do {

            let request =
                try JSONEncoder().encode(
                    ClientRequest(
                        args: args,
                        stdin: stdin
                    )
                )

            try socket.write(from: request)

            _ = try Socket.wait(
                for: [socket],
                timeout: 0,
                waitForever: true
            )

            var answer = Data()

            try socket.read(into: &answer)

            let result =
                try JSONDecoder()
                .decode(
                    ServerAnswer.self,
                    from: answer
                )

            if result.exitCode != 0 {

                return .failure(
                    .command(result.stderr)
                )
            }

            return .success(result.stdout)

        } catch {

            if retry {

                return .failure(
                    .unknown(error.localizedDescription)
                )
            }

            connect(reconnect: true)

            return runCommand(
                args: args,
                stdin: stdin,
                retry: true
            )
        }
    }
}

extension AerospaceSocket {

    func workspaceBackAndForth() {

        _ = runCommand(
            args: [
                "workspace-back-and-forth"
            ]
        )
    }

    func switchWorkspace(
        name: String
    ) {

        _ = runCommand(
            args: [
                "workspace",
                name
            ]
        )
    }
}

extension AerospaceSocket {

    func directionalWorkspace(
        next: Bool
    ) {

        let list =
            runCommand(
                args: [
                    "list-workspaces",
                    "--monitor",
                    "focused",
                    "--empty",
                    "no"
                ]
            )

        guard case .success(let output) = list
        else {
            return
        }

        let filtered =
            output
            .split(separator: "\n")
            .map {
                $0.trimmingCharacters(
                    in:
                    .whitespacesAndNewlines
                )
            }
            .filter {
                $0 != "􀎡"
            }
            .joined(separator: "\n")

        _ = runCommand(
            args: [
                "workspace",
                next ? "next" : "prev",
                "--stdin"
            ],
            stdin: filtered
        )
    }
}

extension AerospaceSocket {

    func focusedWorkspace()
    -> String {

        let result =
            runCommand(
                args: [
                    "list-workspaces",
                    "--focused"
                ]
            )

        guard case .success(let output) = result
        else {
            return ""
        }

        return output.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    func workspaceApps()
    -> [String:[String]] {

        let result =
            runCommand(
                args: [
                    "list-windows",
                    "--all",
                    "--format",
                    "workspace=%{workspace}, app=%{app-name}"
                ]
            )

        guard case .success(let output) = result
        else {
            return [:]
        }

        var map:
            [String:[String]] = [:]

        output
            .split(separator: "\n")
            .forEach { line in

                let comps =
                    line
                    .split(separator: ",")
                    .map {
                        $0.trimmingCharacters(
                            in: .whitespaces
                        )
                    }

                guard comps.count == 2
                else {
                    return
                }

                let ws =
                    comps[0]
                    .replacingOccurrences(
                        of: "workspace=",
                        with: ""
                    )

                let app =
                    comps[1]
                    .replacingOccurrences(
                        of: "app=",
                        with: ""
                    )

                map[ws, default: []]
                    .append(app)
            }

        return map
    }
}
