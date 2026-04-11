import ReliosSupport

final class MockArchiveWriter: ArchiveWriter, @unchecked Sendable {
    struct Call: Equatable {
        let source: String
        let destination: String
    }

    private(set) var calls: [Call] = []
    var shouldFail = false

    /// Optional: if set, writes a placeholder at `destination` so that
    /// backup rotation tests can see the zip in `listDirectory`.
    var fs: InMemoryFileSystem?

    func writeArchive(source: String, destination: String) throws {
        calls.append(Call(source: source, destination: destination))
        if shouldFail {
            throw ArchiveError.dittoFailed(
                source: source,
                destination: destination,
                exitCode: 1,
                stderrTail: "mock archive failure"
            )
        }
        try? fs?.writeUTF8("zip-placeholder", to: destination)
    }
}
