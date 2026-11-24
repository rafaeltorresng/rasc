import CoreFoundation
import Foundation

let name = CommandLine.arguments[1]
let callback: CFMessagePortCallBack = { _, _, payload, _ in
    guard let data = payload as Data?,
          let request = try? JSONDecoder().decode([String: String].self, from: data),
          let tool = request["tool"], let value = request["value"] else { return nil }
    // The unsecured control only demonstrates that IPC plumbing works.
    let id = "055D1B41-AF7E-4C06-A645-0C97B56980FE"
    let reply = tool == "search_thoughts" && value == "teal" ? id :
        tool == "get_thought" && value == id ? "Use teal." : "Thought unavailable"
    return Unmanaged.passRetained(Data(reply.utf8) as CFData)
}
let local = CFMessagePortCreateLocal(nil, name as CFString, callback, nil, nil)
print(local == nil ? "REGISTER DENIED" : "REGISTER OK")
fflush(nil)
if let local, let source = CFMessagePortCreateRunLoopSource(nil, local, 0) {
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
    CFRunLoopRunInMode(.defaultMode, 30, false)
}
