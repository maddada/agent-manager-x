import Foundation

enum AgentType: String, Codable, CaseIterable {
    case claude
    case codex
    case opencode
}

enum SessionStatus: String, Codable, CaseIterable {
    case waiting
    case processing
    case thinking
    case idle
    case stale
}

enum SessionMessageRole: String, Codable, CaseIterable {
    case user
    case assistant
}

struct Session: Codable, Hashable, Identifiable {
    let id: String
    let agentType: AgentType
    let projectName: String
    let projectPath: String
    let gitBranch: String?
    let githubUrl: String?
    let status: SessionStatus
    let lastMessage: String?
    let lastMessageRole: SessionMessageRole?
    let lastActivityAt: String
    let pid: Int
    let cpuUsage: Double
    let memoryBytes: Int64
    let activeSubagentCount: Int
    let isBackground: Bool

    /// Render-safe identity for UI lists where logical `id` may repeat across processes.
    var renderID: String {
        "\(agentType.rawValue):\(pid):\(id)"
    }
}

struct SessionsResponse: Codable, Hashable {
    let sessions: [Session]
    let backgroundSessions: [Session]
    let totalCount: Int
    let waitingCount: Int
}

struct GitDiffStats: Codable, Hashable {
    let additions: Int
    let deletions: Int
}
