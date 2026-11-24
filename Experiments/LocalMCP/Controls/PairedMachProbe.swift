import CoreFoundation
import CryptoKit
import Foundation

final class Grant {
    let key: SymmetricKey
    var revoked = false
    var seen = Set<String>()
    init(bytes: Data) { key = SymmetricKey(data: bytes) }
}
let keyBytes = Data(base64Encoded: ProcessInfo.processInfo.environment["RASC_SPIKE_PAIR_KEY"]!)!
let grant = Grant(bytes: keyBytes)
var context = CFMessagePortContext(version: 0, info: Unmanaged.passUnretained(grant).toOpaque(), retain: nil, release: nil, copyDescription: nil)
let callback: CFMessagePortCallBack = { _, _, payload, info in
    let grant = Unmanaged<Grant>.fromOpaque(info!).takeUnretainedValue()
    guard let bytes = payload as Data?,
          let box = try? ChaChaPoly.SealedBox(combined: bytes),
          let plaintext = try? ChaChaPoly.open(box, using: grant.key, authenticating: Data("request".utf8)),
          let body = try? JSONDecoder().decode([String:String].self, from: plaintext),
          let tool = body["tool"], let value = body["value"], let id = body["requestID"],
          grant.seen.insert(id).inserted else { return Unmanaged.passRetained(Data() as CFData) }
    let kept = "055D1B41-AF7E-4C06-A645-0C97B56980FE"
    let reply: String
    if grant.revoked { reply = "Thought unavailable" }
    else if tool == "search_thoughts", value == "teal" { reply = kept }
    else if tool == "get_thought", value == kept { reply = "Synthetic approved text" }
    else { reply = "Thought unavailable" }
    let sealed = try! ChaChaPoly.seal(Data(reply.utf8), using: grant.key, authenticating: Data(("response:" + id).utf8))
    return Unmanaged.passRetained(sealed.combined as CFData)
}
signal(SIGUSR1, SIG_IGN)
let revoke = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
revoke.setEventHandler { grant.revoked = true; print("REVOKED"); fflush(nil) }
revoke.resume()
let name = "com.rafaeltorres.rasc.mcpspike"
let port = CFMessagePortCreateLocal(nil, name as CFString, callback, &context, nil)!
let source = CFMessagePortCreateRunLoopSource(nil, port, 0)!
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
print("READY")
fflush(nil)
CFRunLoopRunInMode(.defaultMode, 25, false)
