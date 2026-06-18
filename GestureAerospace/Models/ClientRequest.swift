import Foundation

public struct ClientRequest:
    Codable,
    Sendable
{
    public let command: String
    public let args: [String]
    public let stdin: String

    public init(
        args: [String],
        stdin: String
    ) {

        self.command = ""
        self.args = args
        self.stdin = stdin
    }
}
