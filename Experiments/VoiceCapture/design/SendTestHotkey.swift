// Synthetic input into the test shortcut only. Run with the isolated app listening.
import CoreGraphics
import Foundation

guard CGPreflightPostEventAccess() else {
    fatalError("Posting input is unavailable. Test the chord manually; this tool never asks for permission.")
}
let source = CGEventSource(stateID: .hidSystemState)
let chord: CGEventFlags = [.maskControl, .maskCommand, .maskShift]
func send(down: Bool, flags: CGEventFlags = chord, repeated: Bool = false) {
    let event = CGEvent(keyboardEventSource: source, virtualKey: 0x50, keyDown: down)!
    event.flags = flags
    event.setIntegerValueField(.keyboardEventAutorepeat, value: repeated ? 1 : 0)
    event.post(tap: .cgSessionEventTap)
}
func wait(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

print("Quick start")
send(down: true)
wait(0.055)
send(down: false)
wait(0.8)

print("Hold with two synthesized repeat events and normal release")
send(down: true)
wait(0.24)
send(down: true, repeated: true)
wait(0.24)
send(down: true, repeated: true)
wait(0.24)
send(down: false)
wait(0.04)

print("Rapid next press while finalizing")
send(down: true)
wait(0.055)
send(down: false)
wait(1.15)

print("Release event with the modifiers already clear")
send(down: true)
wait(0.15)
send(down: false, flags: [])
