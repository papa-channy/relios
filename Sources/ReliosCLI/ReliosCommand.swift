import ArgumentParser

public struct ReliosCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "relios",
        abstract: "Local release pipeline for SwiftPM-based macOS apps.",
        version: "0.1.0-alpha",
        subcommands: [
            InitCommand.self,
            DoctorCommand.self,
            ReleaseCommand.self,
            BuildCommand.self,
            InstallCommand.self,
            InspectCommand.self,
            RollbackCommand.self,
            OpenCommand.self,
        ]
    )

    public init() {}
}
