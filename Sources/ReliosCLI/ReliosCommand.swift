import ArgumentParser

public struct ReliosCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "relios",
        abstract: "Local release pipeline for SwiftPM-based macOS apps.",
        // Sentinel for source builds. Release artifacts (Homebrew, etc.)
        // replace this at install time with the actual tag.
        version: "0.0.0-dev",
        subcommands: [
            InitCommand.self,
            DoctorCommand.self,
            ReleaseCommand.self,
            BuildCommand.self,
            InstallCommand.self,
            InspectCommand.self,
            RollbackCommand.self,
            OpenCommand.self,
            CICommand.self,
            SigningCommand.self,
            DMGCommand.self,
            NotarizeCommand.self,
        ]
    )

    public init() {}
}
