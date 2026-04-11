import ArgumentParser

public struct BuildCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Run the release build defined in [build].command without installing."
    )

    @Flag(name: .shortAndLong, help: "Verbose output.")
    public var verbose: Bool = false

    public init() {}

    public func run() throws {
        print("[build] not implemented yet")
    }
}
