import Foundation

final class SessionDetectionService {
    private let detectors: [AgentSessionDetecting]

    init(
        processService: ProcessIntrospectionService = ProcessIntrospectionService(),
        shell: ShellCommandRunning = ShellCommandRunner()
    ) {
        self.detectors = [
            ClaudeSessionDetector(processService: processService, shell: shell),
            CodexSessionDetector(processService: processService),
            OpenCodeSessionDetector(processService: processService)
        ]
    }

    init(detectors: [AgentSessionDetecting]) {
        self.detectors = detectors
    }

    func getAllSessions() -> SessionsResponse {
        let allSessions = detectors.flatMap { $0.detectSessions() }

        var foreground: [Session] = []
        var background: [Session] = []

        for session in allSessions {
            if session.isBackground {
                background.append(session)
            } else {
                foreground.append(session)
            }
        }

        foreground.sort(by: compareForeground)
        background.sort(by: compareBackground)

        return SessionsResponse(
            sessions: foreground,
            backgroundSessions: background,
            totalCount: foreground.count,
            waitingCount: foreground.filter { $0.status == .waiting }.count
        )
    }

    private func compareForeground(lhs: Session, rhs: Session) -> Bool {
        let lhsPriority = SessionParsingSupport.statusPriority(lhs.status)
        let rhsPriority = SessionParsingSupport.statusPriority(rhs.status)

        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        return lhs.sortableLastActivityDate > rhs.sortableLastActivityDate
    }

    private func compareBackground(lhs: Session, rhs: Session) -> Bool {
        let lhsType = backgroundAgentSortKey(lhs.agentType)
        let rhsType = backgroundAgentSortKey(rhs.agentType)

        if lhsType != rhsType {
            return lhsType < rhsType
        }

        return lhs.sortableLastActivityDate > rhs.sortableLastActivityDate
    }

    private func backgroundAgentSortKey(_ type: AgentType) -> Int {
        switch type {
        case .claude: return 0
        case .codex: return 1
        case .opencode: return 2
        }
    }
}
