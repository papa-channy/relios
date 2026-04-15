/// Optional `[dmg]` section in relios.toml. When absent or `enabled = false`,
/// DMG generation is skipped.
///
/// Design follows the "don't create files you'd need to hide" principle from
/// the W.Prep DMG guide: solid background color (never an image), no volume
/// icon. Those paths are intentionally not exposed as fields.
public struct DMGSection: Decodable, Equatable, Sendable {
    public let enabled: Bool
    public let outputDir: String
    public let volumeName: String?
    public let backgroundColor: String
    public let windowWidth: Int
    public let windowHeight: Int
    public let iconSize: Int

    private enum CodingKeys: String, CodingKey {
        case enabled
        case outputDir        = "output_dir"
        case volumeName       = "volume_name"
        case backgroundColor  = "background_color"
        case windowSize       = "window_size"
        case iconSize         = "icon_size"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled         = try c.decodeIfPresent(Bool.self, forKey: .enabled)         ?? true
        self.outputDir       = try c.decodeIfPresent(String.self, forKey: .outputDir)     ?? "dist"
        let vn = try c.decodeIfPresent(String.self, forKey: .volumeName)
        self.volumeName      = (vn?.isEmpty == false) ? vn : nil
        self.backgroundColor = try c.decodeIfPresent(String.self, forKey: .backgroundColor) ?? "#FCF5F3"
        self.iconSize        = try c.decodeIfPresent(Int.self, forKey: .iconSize)         ?? 80

        // window_size accepts [width, height]. Default: 540×360 (the guide's
        // calibrated "not too big, not too small" choice).
        let size = try c.decodeIfPresent([Int].self, forKey: .windowSize) ?? [540, 360]
        guard size.count == 2 else {
            throw DecodingError.dataCorruptedError(
                forKey: .windowSize,
                in: c,
                debugDescription: "window_size must be a 2-element array [width, height]"
            )
        }
        self.windowWidth  = size[0]
        self.windowHeight = size[1]
    }

    public init(
        enabled: Bool = true,
        outputDir: String = "dist",
        volumeName: String? = nil,
        backgroundColor: String = "#FCF5F3",
        windowWidth: Int = 540,
        windowHeight: Int = 360,
        iconSize: Int = 80
    ) {
        self.enabled = enabled
        self.outputDir = outputDir
        self.volumeName = volumeName
        self.backgroundColor = backgroundColor
        self.windowWidth = windowWidth
        self.windowHeight = windowHeight
        self.iconSize = iconSize
    }
}
