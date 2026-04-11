/// What kind of version bump a release is performing.
///
/// `none` is not the absence of a bump — it explicitly means "keep the
/// version, only increment the build number". This is the default for
/// `relios release` with no positional argument.
public enum BumpKind: String, Sendable, Equatable, CaseIterable {
    case none
    case patch
    case minor
    case major
}
