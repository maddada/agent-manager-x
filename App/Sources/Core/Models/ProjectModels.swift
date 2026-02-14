import Foundation

enum CardClickAction: String, Codable, CaseIterable {
    case editor
    case terminal
}

enum DisplayMode: String, Codable, CaseIterable {
    case masonry
    case list
}

struct ProjectGroup: Codable, Hashable, Identifiable {
    static let defaultColor = "bg-white/5 border-white/10"

    let projectPath: String
    let projectName: String
    let sessions: [Session]
    let color: String

    var id: String { projectPath }

    /// Groups sessions by `projectPath` with a stable path-based sort order.
    static func grouped(from sessions: [Session], color: String = defaultColor) -> [ProjectGroup] {
        let groupedSessions = Dictionary(grouping: sessions, by: \.projectPath)
        let projectPaths = groupedSessions.keys.sorted()

        return projectPaths.compactMap { projectPath in
            guard let projectSessions = groupedSessions[projectPath],
                  let firstSession = projectSessions.first else {
                return nil
            }

            return ProjectGroup(
                projectPath: projectPath,
                projectName: firstSession.projectName,
                sessions: projectSessions,
                color: color
            )
        }
    }
}
