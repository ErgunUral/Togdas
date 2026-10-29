import XCTest
@testable import ToqdasCore

final class KeySharingTests: XCTestCase {
    private let phonePublicKey = Data(hexBytes: "046b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c2964fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5")!
    private let accountUUID = "00112233-4455-6677-8899-aabbccddeeff"

    func testParsesToggKeySharingInvitationAndBuildsAndroidCompatiblePayload() throws {
        let invitation = try KeySharingInvitation.parse(
            "https://share.togg.cloud/KeySharing?seId=AQIDBAUG&no=BwgJCgsM"
        )
        XCTAssertEqual(invitation.sessionID, "AQIDBAUG")
        XCTAssertEqual(invitation.nonce, "BwgJCgsM")

        let payload = try invitation.signatureMessage(accountUUID: accountUUID, phonePublicKey: phonePublicKey)
        XCTAssertEqual(payload.count, 6 + 16 + 65 + 6)
        XCTAssertEqual(Array(payload.prefix(6)), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(Array(payload[6..<22]), Array(Data(hexBytes: "00112233445566778899aabbccddeeff")!))
        XCTAssertEqual(Data(payload[22..<87]), phonePublicKey)
        XCTAssertEqual(Array(payload.suffix(6)), [7, 8, 9, 10, 11, 12])
    }

    func testRejectsUntrustedOrMalformedInvitationURLs() {
        let invalid = [
            "http://share.togg.cloud/KeySharing?seId=AQIDBAUG&no=BwgJCgsM",
            "https://togg.cloud.evil.example/KeySharing?seId=AQIDBAUG&no=BwgJCgsM",
            "https://share.togg.cloud/notKeySharing?seId=AQIDBAUG&no=BwgJCgsM",
            "https://share.togg.cloud/KeySharing?seId=AQIDBAUG&seId=AQIDBAUG&no=BwgJCgsM",
            "https://share.togg.cloud/KeySharing?seId=short&no=BwgJCgsM",
            "https://share.togg.cloud/KeySharing?seId=AQIDBAUG&no=BwgJCgsM#fragment",
            "https://user@share.togg.cloud/KeySharing?seId=AQIDBAUG&no=BwgJCgsM"
        ]
        for value in invalid {
            XCTAssertThrowsError(try KeySharingInvitation.parse(value), value)
        }
    }

    func testRejectsMalformedAccountAndPhoneKeyBeforeSigning() throws {
        let invitation = try KeySharingInvitation.parse(
            "https://share.togg.cloud/KeySharing?seId=AQIDBAUG&no=BwgJCgsM"
        )
        XCTAssertThrowsError(try invitation.signatureMessage(accountUUID: "not-a-uuid", phonePublicKey: phonePublicKey))
        XCTAssertThrowsError(try invitation.signatureMessage(accountUUID: accountUUID, phonePublicKey: Data(repeating: 0, count: 65)))
    }

    func testReplayFingerprintDoesNotExposeSessionID() throws {
        let invitation = try KeySharingInvitation.parse(
            "https://share.togg.cloud/KeySharing?seId=AQIDBAUG&no=BwgJCgsM"
        )
        XCTAssertEqual(invitation.replayFingerprint.count, 64)
        XCTAssertFalse(invitation.replayFingerprint.contains(invitation.sessionID))
    }
}
