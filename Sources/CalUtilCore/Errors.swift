/// An error with a message meant for the person running calutil.
public struct CalUtilError: Error, CustomStringConvertible, Equatable, Sendable {
    public var message: String
    /// True when the problem is with how calutil was invoked (exit status 2).
    public var isUsage: Bool

    public init(_ message: String, usage: Bool = false) {
        self.message = message
        self.isUsage = usage
    }

    public var description: String { message }
}
