import Foundation

struct HistoryMessage: Identifiable, Hashable {
    let id: String
    let role: SessionMessageRole
    let text: String
    let timestamp: Date?

    init(role: SessionMessageRole, text: String, timestamp: Date?) {
        self.id = UUID().uuidString
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

struct HistoryConversation: Identifiable, Hashable {
    let id: String
    let filePath: String
    let agentType: AgentType
    let sessionID: String
    let gitBranch: String?
    let lastActivityAt: Date
    let fileSize: Int64
    let userMessages: [HistoryMessage]
    let lastAssistantReply: HistoryMessage?
    let summaryPreview: String
    let messagesLoaded: Bool

    init(
        filePath: String,
        agentType: AgentType,
        sessionID: String,
        gitBranch: String?,
        lastActivityAt: Date,
        fileSize: Int64,
        userMessages: [HistoryMessage],
        lastAssistantReply: HistoryMessage?
    ) {
        self.id = filePath
        self.filePath = filePath
        self.agentType = agentType
        self.sessionID = sessionID
        self.gitBranch = gitBranch
        self.lastActivityAt = lastActivityAt
        self.fileSize = fileSize
        self.userMessages = userMessages
        self.lastAssistantReply = lastAssistantReply
        self.summaryPreview = Self.summaryPreview(from: userMessages.first?.text)
        self.messagesLoaded = true
    }

    init(
        filePath: String,
        agentType: AgentType,
        sessionID: String,
        gitBranch: String?,
        lastActivityAt: Date,
        fileSize: Int64,
        summaryPreview: String
    ) {
        self.id = filePath
        self.filePath = filePath
        self.agentType = agentType
        self.sessionID = sessionID
        self.gitBranch = gitBranch
        self.lastActivityAt = lastActivityAt
        self.fileSize = fileSize
        self.userMessages = []
        self.lastAssistantReply = nil
        self.summaryPreview = Self.summaryPreview(from: summaryPreview)
        self.messagesLoaded = false
    }

    private static func summaryPreview(from text: String?) -> String {
        guard let text else { return "No user messages" }
        return SessionParsingSupport.truncate(
            text.replacingOccurrences(of: "\\n+", with: " ", options: .regularExpression),
            maxChars: 120
        )
    }
}

struct HistoryProject: Identifiable, Hashable {
    let id: String
    let projectPath: String
    let projectName: String
    let conversations: [HistoryConversation]

    var latestActivity: Date {
        conversations.map(\.lastActivityAt).max() ?? .distantPast
    }

    var conversationCount: Int {
        conversations.count
    }

    init(projectPath: String, conversations: [HistoryConversation]) {
        self.id = projectPath
        self.projectPath = projectPath
        self.projectName = SessionParsingSupport.projectName(from: projectPath)
        self.conversations = conversations
    }
}

enum HistorySortMode: String, CaseIterable {
    case latestActivity
    case alphabetical

    var label: String {
        switch self {
        case .latestActivity: return "Latest Activity"
        case .alphabetical: return "Alphabetical"
        }
    }
}
