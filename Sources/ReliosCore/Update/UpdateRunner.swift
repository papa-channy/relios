import Foundation
import ReliosSupport

/// Generates the auto-update feed (`update.json`) for the current version.
///
/// Reads the version (no bump) from the version source, resolves the artifact
/// download URL (explicit, or from `[update].download_url_template`), and
/// writes the manifest to `[update].output_dir/[update].feed_file`.
///
/// Stateless and side-effect-isolated: the only write is the manifest file, so
/// it's safe to run in CI right before publishing the GitHub Release.
public struct UpdateRunner: Sendable {
    private let fs: any FileSystem

    public init(fs: any FileSystem) {
        self.fs = fs
    }

    /// Inputs that vary per release. In CI these come from the GitHub context
    /// (tag, repository, artifact filename); locally the user passes them.
    public struct Options: Sendable, Equatable {
        public let tag: String
        public let repo: String?
        public let asset: String?
        public let downloadURL: String?
        public let notes: String?
        public let notesURL: String?
        public let outputOverride: String?
        /// Local artifact file to hash (sha256 + size). In CI this is the
        /// just-built DMG/zip; the published URL points at where it will land.
        public let artifactPath: String?
        /// Git commit for provenance.
        public let gitCommit: String?
        /// Base64 Ed25519 private key; when present the feed is signed → `.sig`.
        public let signingKeyBase64: String?

        public init(
            tag: String,
            repo: String? = nil,
            asset: String? = nil,
            downloadURL: String? = nil,
            notes: String? = nil,
            notesURL: String? = nil,
            outputOverride: String? = nil,
            artifactPath: String? = nil,
            gitCommit: String? = nil,
            signingKeyBase64: String? = nil
        ) {
            self.tag = tag
            self.repo = repo
            self.asset = asset
            self.downloadURL = downloadURL
            self.notes = notes
            self.notesURL = notesURL
            self.outputOverride = outputOverride
            self.artifactPath = artifactPath
            self.gitCommit = gitCommit
            self.signingKeyBase64 = signingKeyBase64
        }
    }

    public struct Result: Sendable, Equatable, Encodable {
        public let manifestPath: String
        public let downloadURL: String
        public let version: String
        public let build: String
        public let feedURL: String?
        public let sha256: String?
        public let signaturePath: String?

        private enum CodingKeys: String, CodingKey {
            case manifestPath = "manifest_path"
            case downloadURL = "download_url"
            case version
            case build
            case feedURL = "feed_url"
            case sha256
            case signaturePath = "signature_path"
        }
    }

    public func run(
        spec: ReleaseSpec,
        projectRoot: String,
        options: Options,
        now: Date = Date()
    ) throws -> Result {
        guard let update = spec.update, update.enabled else {
            throw UpdateError.updateDisabled
        }

        // 1. Read current version (no bump).
        let (version, build) = try readVersion(spec: spec, projectRoot: projectRoot)

        // 2. Resolve the artifact download URL.
        let downloadURL = try resolveDownloadURL(update: update, options: options)

        // 3. Resolve the release-notes link (explicit, or derive from repo+tag).
        let notesURL = options.notesURL ?? deriveNotesURL(repo: options.repo, tag: options.tag)

        // 4. Hash the local artifact (integrity), if provided.
        var sha256: String? = nil
        var size: Int? = nil
        if let artifactPath = options.artifactPath, !artifactPath.isEmpty {
            if let data = try? fs.readData(at: artifactPath) {
                sha256 = FeedSigner.sha256Hex(data)
                size = data.count
            }
        }

        // 5. Build + write the manifest.
        let manifest = UpdateManifest(
            appName: spec.app.name,
            bundleId: spec.app.bundleId,
            version: version.formatted,
            build: build.formatted,
            url: downloadURL,
            notes: normalizedNotes(options.notes),
            notesURL: notesURL,
            minMacOS: spec.app.minMacOS,
            publishedAt: timestamp(now),
            sha256: sha256,
            size: size,
            gitCommit: options.gitCommit.flatMap { $0.isEmpty ? nil : $0 }
        )

        let path = options.outputOverride
            ?? (projectRoot + "/" + update.outputDir + "/" + update.feedFileName)

        let json = try UpdateManifestWriter(fs: fs).write(manifest, to: path)

        // 6. Sign the exact bytes written, if a key was supplied.
        var signaturePath: String? = nil
        if let key = options.signingKeyBase64, !key.isEmpty {
            let signature: String
            do {
                signature = try FeedSigner.sign(Data(json.utf8), privateKeyBase64: key)
            } catch {
                throw UpdateError.writeFailed(path: path + ".sig", underlying: "signing failed: \(error)")
            }
            let sigPath = path + ".sig"
            do {
                try fs.writeUTF8(signature + "\n", to: sigPath)
            } catch {
                throw UpdateError.writeFailed(path: sigPath, underlying: String(describing: error))
            }
            signaturePath = sigPath
        }

        return Result(
            manifestPath: path,
            downloadURL: downloadURL,
            version: version.formatted,
            build: build.formatted,
            feedURL: update.feedURL,
            sha256: sha256,
            signaturePath: signaturePath
        )
    }

    // MARK: - private

    private func readVersion(
        spec: ReleaseSpec,
        projectRoot: String
    ) throws -> (SemanticVersion, BuildNumber) {
        let reader = VersionSourceReader(fs: fs)
        let path = projectRoot + "/" + spec.version.sourceFile
        do {
            let r = try reader.read(spec: spec.version, at: path)
            return (r.version, r.build)
        } catch let error as VersionSourceError {
            throw UpdateError.versionReadFailed(reason: error.shortReason)
        }
    }

    private func resolveDownloadURL(
        update: UpdateSection,
        options: Options
    ) throws -> String {
        if let explicit = options.downloadURL, !explicit.isEmpty {
            return explicit
        }
        // Fall back to the template — requires repo + asset.
        guard let repo = options.repo, !repo.isEmpty else {
            throw UpdateError.downloadURLUnresolved(
                reason: "No --download-url given and --repo is missing for the URL template"
            )
        }
        guard let asset = options.asset, !asset.isEmpty else {
            throw UpdateError.downloadURLUnresolved(
                reason: "No --download-url given and --asset is missing for the URL template"
            )
        }
        return update.downloadURLTemplate
            .replacingOccurrences(of: "{repo}", with: repo)
            .replacingOccurrences(of: "{tag}", with: options.tag)
            .replacingOccurrences(of: "{asset}", with: asset)
    }

    private func deriveNotesURL(repo: String?, tag: String) -> String? {
        guard let repo, !repo.isEmpty else { return nil }
        return "https://github.com/\(repo)/releases/tag/\(tag)"
    }

    private func normalizedNotes(_ notes: String?) -> String? {
        guard let notes else { return nil }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func timestamp(_ date: Date) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return iso.string(from: date)
    }
}
