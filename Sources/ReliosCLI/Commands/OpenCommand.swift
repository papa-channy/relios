import ArgumentParser

public struct OpenCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "open",
        abstract: "Launch the currently installed app."
    )

    public init() {}

    public func run() throws {
        print("[open] not implemented yet")
    }
}
