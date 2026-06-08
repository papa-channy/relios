import XCTest
import ReliosCore
import Foundation

final class FeedSignerTests: XCTestCase {

    func test_sha256KnownVector() {
        // SHA-256("abc")
        XCTAssertEqual(
            FeedSigner.sha256Hex(Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func test_signVerifyRoundTrip() throws {
        let pair = FeedSigner.generateKeyPair()
        let data = Data("update.json contents".utf8)
        let sig = try FeedSigner.sign(data, privateKeyBase64: pair.privateKeyBase64)
        XCTAssertTrue(FeedSigner.verify(data, signatureBase64: sig, publicKeyBase64: pair.publicKeyBase64))
    }

    func test_tamperedDataFailsVerification() throws {
        let pair = FeedSigner.generateKeyPair()
        let sig = try FeedSigner.sign(Data("original".utf8), privateKeyBase64: pair.privateKeyBase64)
        XCTAssertFalse(FeedSigner.verify(Data("tampered".utf8), signatureBase64: sig, publicKeyBase64: pair.publicKeyBase64))
    }

    func test_wrongPublicKeyFailsVerification() throws {
        let a = FeedSigner.generateKeyPair()
        let b = FeedSigner.generateKeyPair()
        let data = Data("x".utf8)
        let sig = try FeedSigner.sign(data, privateKeyBase64: a.privateKeyBase64)
        XCTAssertFalse(FeedSigner.verify(data, signatureBase64: sig, publicKeyBase64: b.publicKeyBase64))
    }

    func test_invalidPrivateKeyThrows() {
        XCTAssertThrowsError(try FeedSigner.sign(Data("x".utf8), privateKeyBase64: "not-base64-!!"))
    }
}
