import Foundation

public struct ServerAnswer:
    Codable,
    Sendable
{
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let serverVersionAndHash: String
}
