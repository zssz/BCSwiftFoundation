import XCTest
@testable import BCFoundation
import WolfBase
import CryptoKit

class SealedMessageTests: XCTestCase {
    static let plaintext = "Some mysteries aren't meant to be solved.".utf8Data

    static let aliceSeed = Seed(data: "82f32c855d3d542256180810797e0073".hexData!)!
    static let aliceIdentity = Identity(aliceSeed, salt: "Salt")
    static let alicePeer = Peer(identity: aliceIdentity)
    
    static let bobSeed = Seed(data: "187a5973c64d359c836eba466a44db7b".hexData!)!
    static let bobIdentity = Identity(bobSeed, salt: "Salt")
    static let bobPeer = Peer(identity: bobIdentity)
    
    static let carolSeed = Seed(data: "8574afab18e229651c1be8f76ffee523".hexData!)!
    static let carolIdentity = Identity(carolSeed, salt: "Salt")
    static let carolPeer = Peer(identity: carolIdentity)

    func test1() {
        // Alice constrructs a message for Bob's eyes only.
        let message = SealedMessage(plaintext: Self.plaintext, peer: Self.bobPeer)
        
        print(message.taggedCBOR.hex)
        
        // Bob decrypts and reads the message.
        XCTAssertEqual(message.plaintext(with: Self.bobIdentity), Self.plaintext)
        
        // No one else can decrypt the message.
        XCTAssertNil(message.plaintext(with: Self.aliceIdentity))
        XCTAssertNil(message.plaintext(with: Self.carolIdentity))
    }
}
