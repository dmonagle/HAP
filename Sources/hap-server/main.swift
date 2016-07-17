import Foundation
import HTTP

class Delegate: NSObject, NetServiceDelegate, StreamDelegate {
    var server: HTTP.Server

    init(application: Application) {
        server = Server(application: application)
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        print("didNotPublish", errorDict)
        abort()
    }

    func netService(_ sender: NetService, didAcceptConnectionWith inputStream: InputStream, outputStream: NSOutputStream) {
        server.accept(inputStream: inputStream, outputStream: outputStream)
    }
}

func identifier() -> String {
    return (1...6).map({ _ in String(arc4random() & 255, radix: 16, uppercase: false) }).joined(separator: ":")
}

func root(request: Request) -> Response {
    return Response(status: .OK, text: "Hello, <b>Gib</b>")
}

func identify(request: Request) -> Response {
    //TODO: call accessory's identify callback
    return Response(status: .OK, text: "Got identified")
}

import CLibSodium
import HKDF
import SRP
import CryptoSwift

let username = "Pair-Setup"
let password = "001-02-003"

import CommonCrypto

let group = Group.N3072
let alg = HashAlgorithm.SHA512

/* Create a salt+verification key for the user's password. The salt and
 * key need to be computed at the time the user's password is set and
 * must be stored by the server-side application for use during the
 * authentication process.
 */
let (salt, verificationKey) = createSaltedVerificationKey(username: username, password: password, group: group, alg: alg)

let server = Server(group: group, alg: alg, salt: salt, username: username, verificationKey: verificationKey)

//let ESC = "\u{001B}"
//let CSI = "\(ESC)["
//print("\(CSI)30;47m                        \(CSI)0m")
//print("\(CSI)30;47m    ┌──────────────┐    \(CSI)0m")
//print("\(CSI)30;47m    | (\(password) |    \(CSI)0m")
//print("\(CSI)30;47m    └──────────────┘    \(CSI)0m")
//print("\(CSI)30;47m                        \(CSI)0m")

//print(client_secretkey, client_publickey)

func pairSetup(request: Request) -> Response {
    guard let body = request.body else { return Response(status: .BadRequest) }
    let data = try! decode(body)

    switch PairSetupStep(rawValue: UInt8(data: data[PairTag.sequence.rawValue]!)) {
    case .startRequest?:
        print("<-- B", server.B)
        print("<-- s", salt)

        let result: TLV8 = [
            PairTag.sequence.rawValue: Data(bytes: [PairSetupStep.startResponse.rawValue]),
            PairTag.publicKey.rawValue: server.B,
            PairTag.salt.rawValue: salt,
        ]
        let response = Response(status: .OK)
        response.headers["Content-Type"] = "application/pairing+tlv8"
        response.body = encode(result)
        return response

    case .verifyRequest?:
        guard let A = data[PairTag.publicKey.rawValue], let M = data[PairTag.proof.rawValue] else {
            return Response(status: .BadRequest)
        }

        print("--> A", A)
        print("--> M", M)

        guard let HAMK = try? server.verifySession(A: A, M: M) else {
            return Response(status: .BadRequest)
        }

        print("<-- HAMK", HAMK)

        let result: TLV8 = [
            PairTag.sequence.rawValue: Data(bytes: [PairSetupStep.verifyResponse.rawValue]),
            PairTag.proof.rawValue: HAMK
        ]

        let response = Response(status: .OK)
        response.headers["Content-Type"] = "application/pairing+tlv8"
        response.body = encode(result)
        return response

    case .keyExchangeRequest?:
        guard let encryptedData = data[PairTag.encryptedData.rawValue] else {
            return Response(status: .BadRequest)
        }

//        let message = Data(encryptedData[0..<encryptedData.index(encryptedData.endIndex, offsetBy: -16)])
//        let mac = Data(encryptedData[encryptedData.index(encryptedData.endIndex, offsetBy: -16)..<encryptedData.endIndex])
//
//        print("message:", message)
//        print("MAC:", mac)
//
//        var plaintext = Data(count: message.count)

        let encryptionSalt = "Pair-Setup-Encrypt-Salt".data(using: .utf8)!
        let encryptionInfo = "Pair-Setup-Encrypt-Info".data(using: .utf8)!
        let encryptionKey = deriveKey(algorithm: .SHA512, seed: server.sessionKey!, info: encryptionInfo, salt: encryptionSalt, count: 32)

        print("S:", server.sessionKey!)
        print("encryptionKey:", encryptionKey)

//        let plaintext = try! ChaCha20(key: Array(encryptionKey), iv: Array("PS-Msg05".utf8))!.decrypt(Array(message))
//        print("authenticate result:", Data(try! Authenticator.Poly1305(key: Array(encryptionKey)).authenticate(Array(message))))

//        let r = plaintext.withUnsafeMutableBytes { (m: UnsafeMutablePointer<UInt8>) in
//            message.withUnsafeBytes { (c: UnsafePointer<UInt8>) in
//                mac.withUnsafeBytes { (mac: UnsafePointer<UInt8>) in
//                    encryptionKey.withUnsafeBytes { (k: UnsafePointer<UInt8>) in
//                        crypto_aead_chacha20poly1305_ietf_decrypt_detached(m, nil, c, UInt64(encryptedData.count), mac, nil, 0, "PS-Msg05", k)
//                    }
//                }
//            }
//        }

        let decryptor = ChaCha20Poly1305(key: encryptionKey, nonce: "PS-Msg05".data(using: .utf8)!)!
        let plaintext = try! decryptor.decrypt(cipher: encryptedData)

//        print("r", r)
        print("plaintext:", Data(plaintext))

        print(try? decode(Data(plaintext)))

    case let step: print(request); print(step); print(data)
    }

    return Response(status: .BadRequest, text: "Not sure what to do here...")
}

//print(crypto_aead_chacha20poly1305_KEYBYTES)

let router = Router(routes: [
    ("/", root),
    ("/identify", identify),
    ("/pair-setup", pairSetup),
])

let delegate = Delegate(application: router.application)

let service = NetService(domain: "local.", type: "_hap._tcp.", name: "Switch", port: 8000)
let config: [String: Data] = [
    "id": identifier().data(using: .utf8)!, // identifier
    "c#": "3".data(using: .utf8)!, // version
    "s#": "1".data(using: .utf8)!, // state
    "sf": "1".data(using: .utf8)!, // discoverable
    "ff": "0".data(using: .utf8)!, // mfi compliant
    "md": "Switch".data(using: .utf8)!, // name
    "ci": "8".data(using: .utf8)!, // category identifier -- switch
]

service.setTXTRecord(NetService.data(fromTXTRecord: config))
service.delegate = delegate
service.publish(options: [.listenForConnections])


print(service.port)

withExtendedLifetime((delegate, service)) {
    RunLoop.current.run()
}



// post /identify -> ??

// pair
// post /pair-setup
// enter code
// post /pair-setup -> fail, try again
// enter code
// post /pair-setup -> succeeds, multiple posts to here
// post /pair-verify -> ?
// GET /accessories
// POST /pairings method ADD
// paired

// setup (?)
//GET /characteristics


// unpair

// post /pairings method DELETE -> unpair
// post /pair-verify -> ??
