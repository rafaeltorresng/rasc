import CoreFoundation
import CryptoKit
import Foundation
import MCP

private let server = Server(name: "Rasc Synthetic Probe", version: "0.1", capabilities: .init(tools: .init()))
private let search = Tool(
    name: "search_thoughts", description: "Search synthetic Kept Rasc thoughts.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object(["query": .object(["type": .string("string")])]),
        "required": .array([.string("query")])
    ])
)
private let get = Tool(
    name: "get_thought", description: "Read a synthetic thought by the id returned by search.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object(["id": .object(["type": .string("string")])]),
        "required": .array([.string("id")])
    ])
)
private let fixtureID = "055D1B41-AF7E-4C06-A645-0C97B56980FE"
private let fixtureText = "Use the teal prototype and allow three retries."
private let processArguments = CommandLine.arguments
private let endpoint = processArguments.count >= 3 && processArguments[1] == "--mach" ? processArguments[2] : nil
private let fixtureMode = processArguments.contains("--fixture")

private func callHost(_ name: String, _ value: String) -> String? {
    guard let endpoint, let port = CFMessagePortCreateRemote(nil, endpoint as CFString),
          let request = try? JSONEncoder().encode(["tool": name, "value": value]) else { return nil }
    let key = ProcessInfo.processInfo.environment["RASC_SPIKE_PAIR_KEY"].flatMap { Data(base64Encoded: $0) }.map { SymmetricKey(data: $0) }
    let requestID = UUID().uuidString
    var requestBytes = request
    if let key {
        guard let body = try? JSONEncoder().encode(["tool": name, "value": value, "requestID": requestID]),
              let sealed = try? ChaChaPoly.seal(body, using: key, authenticating: Data("request".utf8)) else { return nil }
        requestBytes = sealed.combined
    }
    var response: Unmanaged<CFData>?
    let status = CFMessagePortSendRequest(port, 1, requestBytes as CFData, 1, 1, CFRunLoopMode.defaultMode.rawValue, &response)
    guard status == kCFMessagePortSuccess, let bytes = response?.takeRetainedValue() else { return nil }
    if let key {
        guard let sealed = try? ChaChaPoly.SealedBox(combined: bytes as Data),
              let plaintext = try? ChaChaPoly.open(sealed, using: key, authenticating: Data(("response:" + requestID).utf8)) else { return nil }
        return String(data: plaintext, encoding: .utf8)
    }
    return String(data: bytes as Data, encoding: .utf8)
}

await server.withMethodHandler(ListTools.self) { _ in .init(tools: [search, get]) }
await server.withMethodHandler(CallTool.self) { params in
    let key = params.name == search.name ? "query" : "id"
    guard [search.name, get.name].contains(params.name),
          let value = params.arguments?[key]?.stringValue, value.utf8.count <= 256 else {
        return .init(content: [.text("Invalid request")], isError: true)
    }
    if fixtureMode {
        if params.name == search.name {
            let rows = fixtureText.localizedStandardContains(value) ? "[{\"id\":\"\(fixtureID)\",\"title\":\"Teal prototype\"}]" : "[]"
            return .init(content: [.text(rows)])
        }
        return value.caseInsensitiveCompare(fixtureID) == .orderedSame
            ? .init(content: [.text(fixtureText)])
            : .init(content: [.text("Thought unavailable")], isError: true)
    }

    guard let result = callHost(params.name, value) else {
        return .init(content: [.text("Rasc IPC unavailable")], isError: true)
    }
    return .init(content: [.text(result)])
}
try await server.start(transport: StdioTransport())
await server.waitUntilCompleted()
