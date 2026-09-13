import Foundation

struct ActiveNoteStore {
    static let key = "activeNoteID"
    private static let initializedKey = "activeNoteStateInitialized"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var hasEstablishedState: Bool {
        userDefaults.object(forKey: Self.key) != nil
            || userDefaults.bool(forKey: Self.initializedKey)
    }

    var noteID: UUID? {
        get {
            userDefaults.string(forKey: Self.key).flatMap(UUID.init(uuidString:))
        }
        nonmutating set {
            userDefaults.set(true, forKey: Self.initializedKey)
            if let newValue {
                userDefaults.set(newValue.uuidString, forKey: Self.key)
            } else {
                userDefaults.removeObject(forKey: Self.key)
            }
        }
    }
}
