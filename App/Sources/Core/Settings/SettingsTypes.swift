import Foundation

enum DefaultEditor: String, Codable, CaseIterable {
    case zed
    case code
    case cursor
    case sublime
    case neovim
    case webstorm
    case idea
    case custom
}

enum DefaultTerminal: String, Codable, CaseIterable {
    case ghostty
    case iterm
    case kitty
    case terminal
    case warp
    case alacritty
    case hyper
    case custom
}

enum SessionDetailsRetrievalMode: String, Codable, CaseIterable {
    case processBased = "Process based"
    case vsmuxSessions = "VSmux sessions"

    var displayName: String {
        switch self {
        case .processBased:
            return "Processes"
        case .vsmuxSessions:
            /*
             CDXC:MuxSessionSourceToggle 2026-04-27-19:04
             The main dashboard source toggle must name both live publishers
             because this mode now merges sessions from VSmux and zmux.
             */
            return "vsmux / zmux"
        }
    }

    var hoverDescription: String {
        switch self {
        case .processBased:
            return "Processes reads live terminal processes and shows CPU, memory, and conversation previews. vsmux / zmux reads live sessions directly from connected mux apps and focuses the exact session."
        case .vsmuxSessions:
            return "vsmux / zmux reads live sessions directly from connected mux apps and focuses the exact session. Processes reads terminal processes instead and shows CPU, memory, and conversation previews."
        }
    }
}

enum UIElementSize: String, Codable, CaseIterable {
    case small
    case medium
    case large
    case extraLarge

    var displayName: String {
        switch self {
        case .small:
            return "Small"
        case .medium:
            return "Medium"
        case .large:
            return "Large"
        case .extraLarge:
            return "Extra Large"
        }
    }

    var clampedForMiniViewer: UIElementSize {
        switch self {
        case .small, .medium, .large:
            return self
        case .extraLarge:
            return .large
        }
    }

    static var miniViewerCases: [UIElementSize] {
        [.small, .medium, .large]
    }
}

enum MiniViewerSide: String, Codable, CaseIterable {
    case left
    case right
}

enum MiniViewerScreenTarget: Hashable, Codable {
    case primary
    case builtIn
    case display(String)

    init(storageValue: String?) {
        guard let storageValue else {
            self = .primary
            return
        }

        if storageValue == "primary" {
            self = .primary
            return
        }

        if storageValue == "builtin" {
            self = .builtIn
            return
        }

        if storageValue.hasPrefix("display:") {
            let identifier = String(storageValue.dropFirst("display:".count))
            if !identifier.isEmpty {
                self = .display(identifier)
                return
            }
        }

        self = .primary
    }

    var storageValue: String {
        switch self {
        case .primary:
            return "primary"
        case .builtIn:
            return "builtin"
        case let .display(identifier):
            return "display:\(identifier)"
        }
    }
}

enum ThemePreference: String, Codable, CaseIterable {
    case dark
    case light
}

enum ProjectCommandAction: String, Codable, CaseIterable {
    case run
    case build
    case commit
    case push
    case review

    var label: String {
        rawValue.capitalized
    }

    var dialogTitle: String {
        "\(label) Command"
    }

    var placeholder: String {
        switch self {
        case .run:
            return "e.g. pnpm dev"
        case .build:
            return "e.g. pnpm build"
        case .commit:
            return "e.g. git commit"
        case .push:
            return "e.g. git push"
        case .review:
            return "e.g. gh pr view --web"
        }
    }
}
