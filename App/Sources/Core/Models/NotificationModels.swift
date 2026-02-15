import Foundation

enum InstallState: String, Codable, CaseIterable {
    case unknown
    case installed
    case notInstalled
}

enum NotificationSound: String, Codable, CaseIterable {
    case shamisen
    case arcade
    case ping
    case glass
    case quick
    case doowap
    case woman
    case african
    case afrobeat
    case edm
    case comeback
    case shabala
    case basso
    case blow
    case bottle
    case frog
    case funk
    case hero
    case morse
    case pop
    case purr
    case sosumi
    case submarine
    case tink

    var displayName: String {
        switch self {
        case .shamisen:
            return "Shamisen"
        case .arcade:
            return "Arcade"
        case .ping:
            return "Ping"
        case .glass:
            return "Glass"
        case .quick:
            return "Quick Ping"
        case .doowap:
            return "Doo-Wap"
        case .woman:
            return "Agent is Done"
        case .african:
            return "Code Complete"
        case .afrobeat:
            return "Afrobeat Code Complete"
        case .edm:
            return "Long EDM"
        case .comeback:
            return "Come Back!"
        case .shabala:
            return "Shabalaba"
        case .basso:
            return "Basso (macOS)"
        case .blow:
            return "Blow (macOS)"
        case .bottle:
            return "Bottle (macOS)"
        case .frog:
            return "Frog (macOS)"
        case .funk:
            return "Funk (macOS)"
        case .hero:
            return "Hero (macOS)"
        case .morse:
            return "Morse (macOS)"
        case .pop:
            return "Pop (macOS)"
        case .purr:
            return "Purr (macOS)"
        case .sosumi:
            return "Sosumi (macOS)"
        case .submarine:
            return "Submarine (macOS)"
        case .tink:
            return "Tink (macOS)"
        }
    }

    var filename: String {
        switch self {
        case .shamisen:
            return "shamisen.mp3"
        case .arcade:
            return "arcade.mp3"
        case .ping:
            return "ping.mp3"
        case .glass:
            return "glass.mp3"
        case .quick:
            return "supersetquick.mp3"
        case .doowap:
            return "supersetdoowap.mp3"
        case .woman:
            return "agentisdonewoman.mp3"
        case .african:
            return "codecompleteafrican.mp3"
        case .afrobeat:
            return "codecompleteafrobeat.mp3"
        case .edm:
            return "codecompleteedm.mp3"
        case .comeback:
            return "comebacktothecode.mp3"
        case .shabala:
            return "shabalabadingdong.mp3"
        case .basso:
            return "Basso.aiff"
        case .blow:
            return "Blow.aiff"
        case .bottle:
            return "Bottle.aiff"
        case .frog:
            return "Frog.aiff"
        case .funk:
            return "Funk.aiff"
        case .hero:
            return "Hero.aiff"
        case .morse:
            return "Morse.aiff"
        case .pop:
            return "Pop.aiff"
        case .purr:
            return "Purr.aiff"
        case .sosumi:
            return "Sosumi.aiff"
        case .submarine:
            return "Submarine.aiff"
        case .tink:
            return "Tink.aiff"
        }
    }
}

struct NotificationState: Codable, Hashable {
    var installState: InstallState = .unknown
    var bellModeEnabled: Bool = false
    var isLoading: Bool = false
}
