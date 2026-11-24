import Foundation

@objc protocol ScopedThoughts {
    func search(_ value: String, reply: @escaping (String) -> Void)
    func get(_ id: String, reply: @escaping (String) -> Void)
}

final class Grant: NSObject, ScopedThoughts, NSXPCListenerDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var allowed = true
    private let kept = "055D1B41-AF7E-4C06-A645-0C97B56980FE"
    func revoke() { lock.withLock { allowed = false } }
    func search(_ value: String, reply: @escaping (String) -> Void) {
        reply(lock.withLock { allowed && value == "teal" ? kept : "" })
    }
    func get(_ id: String, reply: @escaping (String) -> Void) {
        reply(lock.withLock { allowed && id == kept ? "Synthetic result" : "Unavailable" })
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: ScopedThoughts.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }
}
func attempt(_ connection: NSXPCConnection, tool: String, input: String) -> Bool {
    let gate = DispatchSemaphore(value: 0)
    connection.remoteObjectInterface = NSXPCInterface(with: ScopedThoughts.self)
    let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
        print("\(tool) peer rejected")
        gate.signal()
    } as! ScopedThoughts
    if tool == "search" {
        proxy.search(input) { print("search granted=\(!$0.isEmpty)"); gate.signal() }
    } else {
        proxy.get(input) { print("get granted=\($0 == "Synthetic result")"); gate.signal() }
    }
    let succeeded = gate.wait(timeout: .now() + 3) == .success
    if !succeeded { print("\(tool) timed out") }
    return succeeded
}


let grant = Grant()
let name = "com.rafaeltorres.rasc.mcpxpc.named"
if CommandLine.arguments[1] == "host" {
    let listener = NSXPCListener(machServiceName: name)
    listener.delegate = grant
    listener.resume()
    print("named listener resumed")
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 12))
} else {
    let connection = NSXPCConnection(machServiceName: name)
    connection.resume()
    _ = attempt(connection, tool: "search", input: "teal")
}
