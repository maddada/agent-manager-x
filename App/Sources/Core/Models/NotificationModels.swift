import Foundation

enum InstallState: String, Codable, CaseIterable {
    case unknown
    case installed
    case notInstalled
}

struct NotificationState: Codable, Hashable {
    var installState: InstallState = .unknown
    var bellModeEnabled: Bool = false
    var isLoading: Bool = false
}
