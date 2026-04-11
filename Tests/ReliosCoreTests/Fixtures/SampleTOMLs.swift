/// TOML fixtures used by SpecDecodingTests.
/// Kept as Swift constants (not loaded from disk) so the test target needs
/// no SwiftPM `resources:` declaration and tests stay self-contained.
enum SampleTOMLs {

    /// Mirrors the canonical example from the v1 spec doc, byte-for-byte.
    /// If this string changes, the test_gate2 assertions must move with it.
    static let fullSample = """
    [app]
    name = "PortfolioManager"
    display_name = "Portfolio Manager"
    bundle_id = "com.chan.portfolio-manager"
    min_macos = "14.0"
    category = "public.app-category.developer-tools"

    [project]
    type = "swiftpm"
    root = "."
    binary_target = "PortfolioManager"

    [version]
    source_file = "DesignMe/App/AppVersion.swift"
    version_pattern = 'static let current = "(.*)"'
    build_pattern = 'static let build = "(.*)"'

    [build]
    command = "swift build -c release"
    binary_path = ".build/release/PortfolioManager"
    resource_bundle_path = ".build/release/PortfolioManager_PortfolioManager.bundle"

    [assets]
    icon_path = "DesignMe/Resources/AppIcon.icns"

    [bundle]
    output_path = "dist/PortfolioManager.app"
    plist_mode = "generate"

    [install]
    path = "/Applications/PortfolioManager.app"
    auto_open = true
    backup_dir = "dist/app-backups"
    keep_backups = 3
    quit_running_app = true

    [signing]
    mode = "adhoc"
    """

    /// Same shape as `fullSample` but with empty optional placeholders that
    /// `relios init` would write — used to verify "" → nil normalization.
    static let minimalWithEmptyOptionals = """
    [app]
    name = "X"
    display_name = "X"
    bundle_id = "com.example.x"
    min_macos = "14.0"
    category = "public.app-category.developer-tools"

    [project]
    type = "swiftpm"
    root = "."
    binary_target = "X"

    [version]
    source_file = "X.swift"
    version_pattern = 'v = "(.*)"'
    build_pattern = 'b = "(.*)"'

    [build]
    command = "swift build -c release"
    binary_path = ".build/release/X"
    resource_bundle_path = ""

    [assets]
    icon_path = ""

    [bundle]
    output_path = "dist/X.app"
    plist_mode = "generate"

    [install]
    path = "/Applications/X.app"
    auto_open = true
    backup_dir = "dist/app-backups"
    keep_backups = 3
    quit_running_app = true

    [signing]
    mode = "adhoc"
    """
}
