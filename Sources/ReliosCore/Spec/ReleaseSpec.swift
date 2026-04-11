/// Top-level Decodable model for relios.toml.
/// `decode` is concerned only with well-formedness; whether the spec is
/// _usable_ (paths exist, build command runs, etc.) is `Validation/Rules`'
/// responsibility, consumed by `Doctor` and `Release.preflight`.
public struct ReleaseSpec: Decodable, Equatable, Sendable {
    public let app: AppSection
    public let project: ProjectSection
    public let version: VersionSection
    public let build: BuildSection
    public let assets: AssetsSection
    public let bundle: BundleSection
    public let install: InstallSection
    public let signing: SigningSection
}
