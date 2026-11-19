import Foundation

/// How Home renders its notes. `list` is the compact single-line row layout that
/// shipped in 0.1.x; `cards` shows a multi-line excerpt of each note so more of
/// what a thought contains is visible at a glance. Search, ordering and keyboard
/// navigation behave the same in both modes.
enum HomeViewMode: String, CaseIterable, Identifiable, Sendable {
    case list = "list"
    case cards = "cards"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .list: "List"
        case .cards: "Cards"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .list: "List view"
        case .cards: "Card view"
        }
    }
}

struct HomeViewModeStore {
    static let preferenceKey = "homeViewMode"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> HomeViewMode {
        guard let raw = userDefaults.string(forKey: Self.preferenceKey),
              let mode = HomeViewMode(rawValue: raw)
        else {
            return .list
        }
        return mode
    }

    func save(_ mode: HomeViewMode) {
        userDefaults.set(mode.rawValue, forKey: Self.preferenceKey)
    }
}
