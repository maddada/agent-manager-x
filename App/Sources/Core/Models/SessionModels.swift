import Foundation

enum AgentType: String, Codable, CaseIterable {
    case claude
    case codex
    case gemini
    case opencode
    case t3
}

enum SessionDetailsSource: String, Codable, CaseIterable {
    case processBased
    case vsmuxSessions
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
    var detailsSource: SessionDetailsSource = .processBased
    var vsmuxWorkspaceID: String? = nil
    var vsmuxThreadID: String? = nil
    var muxSource: MuxSessionSource? = nil
    var projectIconDataUrl: String? = nil
    var sessionFilePath: String? = nil

    /// Render-safe identity for UI lists where logical `id` may repeat across processes.
    var renderID: String {
        /*
         CDXC:MuxSessionCards 2026-04-27-19:04
         VSmux and zmux can publish the same workspace and session ids for a
         repo. Include the mux source so session cards remain distinct when
         both integrations are displayed together.
         */
        "\(detailsSource.rawValue):\(muxSource?.rawValue ?? "none"):\(vsmuxWorkspaceID ?? "none"):\(agentType.rawValue):\(pid):\(id)"
    }

    var shouldHideFromMiniViewer: Bool {
        guard agentType == .claude,
              projectPath == "/" else {
            return false
        }

        let trimmedMessage = lastMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNewSession = (trimmedMessage?.isEmpty ?? true) && (status == .waiting || status == .idle)
        return isNewSession
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
