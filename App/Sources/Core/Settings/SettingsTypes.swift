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
}

enum MiniViewerSide: String, Codable, CaseIterable {
    case left
    case right
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
