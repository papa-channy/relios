import ArgumentParser

public struct InstallCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install the most recently built .app bundle without rebuilding."
    )

    @Flag(name: .long, help: "Do not auto-launch after install.")
    public var noOpen: Bool = false

    @Flag(name: .long, help: "Skip backup of the currently installed app.")
    public var skipBackup: Bool = false

    @Flag(name: .shortAndLong, help: "Verbose output.")
    public var verbose: Bool = false

    public init() {}

    public func run() throws {
        print("[install] not implemented yet")
    }
}
