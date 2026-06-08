import Foundation
import Crypto

/// SHA-256 hashing and Ed25519 (Curve25519) signing for the update feed.
///
/// The CLI signs `update.json` with a private key (kept as a CI secret); the
/// shipped app embeds the matching public key and verifies the feed before
/// trusting any download URL inside it. This makes a hijacked GitHub release
/// asset insufficient to push a malicious update.
public enum FeedSigner {
    /// Lowercase hex SHA-256 of `data`.
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public struct KeyPair: Sendable, Equatable {
        public let privateKeyBase64: String
        public let publicKeyBase64: String
    }

    public enum SignError: Error, Equatable {
        case invalidPrivateKey
    }

    /// Generate a fresh Ed25519 keypair (base64 raw representations).
    public static func generateKeyPair() -> KeyPair {
        let key = Curve25519.Signing.PrivateKey()
        return KeyPair(
            privateKeyBase64: key.rawRepresentation.base64EncodedString(),
            publicKeyBase64: key.publicKey.rawRepresentation.base64EncodedString()
        )
    }

    /// Sign `data` with a base64 Ed25519 private key; returns a base64 signature.
    public static func sign(_ data: Data, privateKeyBase64: String) throws -> String {
        guard let raw = Data(base64Encoded: privateKeyBase64),
              let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
            throw SignError.invalidPrivateKey
        }
        let signature = try key.signature(for: data)
        return signature.base64EncodedString()
    }

    /// Verify a base64 signature against `data` with a base64 public key.
    /// (The shipped app performs the same check with its embedded public key.)
    public static func verify(_ data: Data, signatureBase64: String, publicKeyBase64: String) -> Bool {
        guard let sig = Data(base64Encoded: signatureBase64),
              let pubRaw = Data(base64Encoded: publicKeyBase64),
              let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: pubRaw) else {
            return false
        }
        return pub.isValidSignature(sig, for: data)
    }
}
