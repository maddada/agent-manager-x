import Foundation
import Network

private let vsmuxSessionBrokerPort: UInt16 = 47652

enum MuxSessionSource: String, Codable, CaseIterable {
    case vsmux
    case zmux

    var displayName: String {
        switch self {
        case .vsmux:
            return "vsmux"
        case .zmux:
            return "zmux"
        }
    }
}

struct VSmuxWorkspaceSession: Codable, Hashable {
    let agent: String
    let alias: String
    let displayName: String
    let isFocused: Bool
    let isRunning: Bool
    let isVisible: Bool
    let kind: String
    let lastActiveAt: String
    let projectName: String?
    let projectPath: String?
    let sessionId: String
    let status: String
    let terminalTitle: String?
    let threadId: String?

    // Newer VSmux publishers send project metadata per session. Fall back to
    // the workspace values so older publishers still decode and behave.
    func resolvedProjectName(fallback workspaceName: String) -> String {
        let trimmedProjectName = projectName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmedProjectName?.isEmpty == false ? trimmedProjectName : nil) ?? workspaceName
    }

    func resolvedProjectPath(fallback workspacePath: String) -> String {
        let trimmedProjectPath = projectPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmedProjectPath?.isEmpty == false ? trimmedProjectPath : nil) ?? workspacePath
    }
}

struct VSmuxWorkspaceSnapshot: Codable, Hashable, Identifiable {
    let brokerWorkspaceId: String
    let sessions: [VSmuxWorkspaceSession]
    let source: MuxSessionSource
    let updatedAt: String
    let workspaceFaviconDataUrl: String?
    let workspaceId: String
    let workspaceName: String
    let workspacePath: String

    var id: String {
        brokerWorkspaceId
    }
}

private extension VSmuxWorkspaceSnapshot {
    func isPresentationEquivalent(to other: VSmuxWorkspaceSnapshot) -> Bool {
        brokerWorkspaceId == other.brokerWorkspaceId &&
            source == other.source &&
            workspaceId == other.workspaceId &&
            workspaceName == other.workspaceName &&
            workspacePath == other.workspacePath &&
            workspaceFaviconDataUrl == other.workspaceFaviconDataUrl &&
            sessions == other.sessions
    }
}

private struct VSmuxWorkspaceSnapshotEnvelope: Codable {
    let sessions: [VSmuxWorkspaceSession]
    let source: MuxSessionSource?
    let type: String
    let updatedAt: String
    let workspaceFaviconDataUrl: String?
    let workspaceId: String
    let workspaceName: String
    let workspacePath: String
}

private struct VSmuxSessionCommand: Codable {
    let sessionId: String
    let type: String
    let workspaceId: String
}

private final class VSmuxBrokerClientConnection {
    let id = UUID()
    let connection: NWConnection
    var brokerWorkspaceIDs = Set<String>()

    init(connection: NWConnection) {
        self.connection = connection
    }
}

final class VSmuxSessionBroker {
    var onWorkspacesChanged: (([VSmuxWorkspaceSnapshot]) -> Void)?

    private let queue = DispatchQueue(label: "VSmuxSessionBroker.queue", qos: .userInitiated)
    private var listener: NWListener?
    private var clientsByID: [UUID: VSmuxBrokerClientConnection] = [:]
    private var workspaceByID: [String: VSmuxWorkspaceSnapshot] = [:]
    private var clientIDByWorkspaceID: [String: UUID] = [:]
    private var pendingFocusSessionIDByWorkspaceID: [String: String] = [:]
    private var isStarted = false

    func start() {
        queue.async {
            guard !self.isStarted else {
                return
            }

            do {
                let tcpOptions = NWProtocolTCP.Options()
                let webSocketOptions = NWProtocolWebSocket.Options()
                webSocketOptions.autoReplyPing = true

                let parameters = NWParameters(tls: nil, tcp: tcpOptions)
                parameters.defaultProtocolStack.applicationProtocols.insert(webSocketOptions, at: 0)
                parameters.allowLocalEndpointReuse = true

                guard let port = NWEndpoint.Port(rawValue: vsmuxSessionBrokerPort) else {
                    self.stopLocked(notify: true)
                    return
                }

                let listener = try NWListener(using: parameters, on: port)
                self.listener = listener
                self.isStarted = true

                listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    if case .failed = state {
                        self.stopLocked(notify: true)
                    }
                }

                listener.newConnectionHandler = { [weak self] connection in
                    self?.handleNewConnection(connection)
                }

                listener.start(queue: self.queue)
            } catch {
                self.stopLocked(notify: true)
            }
        }
    }

    func stop() {
        queue.async {
            self.stopLocked(notify: true)
        }
    }

    func currentWorkspaces() -> [VSmuxWorkspaceSnapshot] {
        queue.sync {
            sortedWorkspacesLocked()
        }
    }

    func requestFocus(workspaceId: String, sessionId: String) {
        queue.async {
            self.pendingFocusSessionIDByWorkspaceID[workspaceId] = sessionId
            self.flushPendingFocusIfPossibleLocked(for: workspaceId)
        }
    }

    func requestClose(workspaceId: String, sessionId: String) {
        queue.async {
            self.sendSessionCommandLocked(type: "closeSession", workspaceId: workspaceId, sessionId: sessionId)
        }
    }

    private func stopLocked(notify: Bool) {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil

        for client in clientsByID.values {
            client.connection.cancel()
        }

        clientsByID.removeAll()
        clientIDByWorkspaceID.removeAll()
        workspaceByID.removeAll()
        pendingFocusSessionIDByWorkspaceID.removeAll()
        isStarted = false

        if notify {
            notifyWorkspacesChangedLocked()
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        let client = VSmuxBrokerClientConnection(connection: connection)
        clientsByID[client.id] = client

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }

            switch state {
            case .ready:
                self.receiveNextMessageLocked(from: client)
            case .failed, .cancelled:
                self.removeClientLocked(client.id)
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func receiveNextMessageLocked(from client: VSmuxBrokerClientConnection) {
        client.connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }

            if error != nil {
                self.removeClientLocked(client.id)
                return
            }

            if let data, !data.isEmpty {
                self.handleIncomingMessageLocked(data, from: client)
            }

            if self.clientsByID[client.id] != nil {
                self.receiveNextMessageLocked(from: client)
            }
        }
    }

    private func handleIncomingMessageLocked(_ data: Data, from client: VSmuxBrokerClientConnection) {
        guard let envelope = try? JSONDecoder().decode(VSmuxWorkspaceSnapshotEnvelope.self, from: data),
              envelope.type == "workspaceSnapshot" else {
            return
        }

        let source = envelope.source ?? .vsmux
        /*
         CDXC:MuxSessionBroker 2026-04-27-19:04
         Agent Manager must merge VSmux and zmux sessions for the same IDE
         workspace. The publisher's workspaceId stays unchanged for commands,
         while brokerWorkspaceId prevents equal workspace hashes from replacing
         each other in the live session snapshot store. Native zmux can publish
         multiple projects over one socket, so each client owns a set of broker
         workspace IDs that are removed together when the socket disconnects.
         */
        let brokerWorkspaceId = Self.brokerWorkspaceId(source: source, workspaceId: envelope.workspaceId)
        let snapshot = VSmuxWorkspaceSnapshot(
            brokerWorkspaceId: brokerWorkspaceId,
            sessions: envelope.sessions,
            source: source,
            updatedAt: envelope.updatedAt,
            workspaceFaviconDataUrl: envelope.workspaceFaviconDataUrl,
            workspaceId: envelope.workspaceId,
            workspaceName: envelope.workspaceName,
            workspacePath: envelope.workspacePath
        )

        let previousSnapshot = workspaceByID[snapshot.brokerWorkspaceId]

        client.brokerWorkspaceIDs.insert(snapshot.brokerWorkspaceId)
        workspaceByID[snapshot.brokerWorkspaceId] = snapshot
        clientIDByWorkspaceID[snapshot.brokerWorkspaceId] = client.id

        let didChangePresentation = previousSnapshot.map { !$0.isPresentationEquivalent(to: snapshot) } ?? true
        if didChangePresentation {
            notifyWorkspacesChangedLocked()
        }
        flushPendingFocusIfPossibleLocked(for: snapshot.brokerWorkspaceId)
    }

    private func flushPendingFocusIfPossibleLocked(for workspaceId: String) {
        guard let sessionId = pendingFocusSessionIDByWorkspaceID[workspaceId] else {
            return
        }

        guard sendSessionCommandLocked(type: "focusSession", workspaceId: workspaceId, sessionId: sessionId) else {
            return
        }

        pendingFocusSessionIDByWorkspaceID[workspaceId] = nil
    }

    @discardableResult
    private func sendSessionCommandLocked(type: String, workspaceId: String, sessionId: String) -> Bool {
        guard let snapshot = workspaceByID[workspaceId],
              snapshot.sessions.contains(where: { $0.sessionId == sessionId }),
              let clientID = clientIDByWorkspaceID[workspaceId],
              let client = clientsByID[clientID] else {
            return false
        }

        let command = VSmuxSessionCommand(
            sessionId: sessionId,
            type: type,
            workspaceId: snapshot.workspaceId
        )
        guard let data = try? JSONEncoder().encode(command) else {
            return false
        }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: type, metadata: [metadata])
        client.connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
        return true
    }

    private func removeClientLocked(_ clientID: UUID) {
        guard let client = clientsByID.removeValue(forKey: clientID) else {
            return
        }

        client.connection.stateUpdateHandler = nil
        client.connection.cancel()

        var didRemoveWorkspace = false
        for brokerWorkspaceId in client.brokerWorkspaceIDs {
            if clientIDByWorkspaceID[brokerWorkspaceId] == clientID {
                clientIDByWorkspaceID[brokerWorkspaceId] = nil
                workspaceByID[brokerWorkspaceId] = nil
                didRemoveWorkspace = true
            }
        }

        if didRemoveWorkspace {
            notifyWorkspacesChangedLocked()
        }
    }

    private func notifyWorkspacesChangedLocked() {
        let snapshots = sortedWorkspacesLocked()
        DispatchQueue.main.async { [weak self] in
            self?.onWorkspacesChanged?(snapshots)
        }
    }

    private func sortedWorkspacesLocked() -> [VSmuxWorkspaceSnapshot] {
        workspaceByID.values.sorted { left, right in
            if left.workspacePath == right.workspacePath {
                return left.brokerWorkspaceId < right.brokerWorkspaceId
            }
            return left.workspacePath < right.workspacePath
        }
    }

    private static func brokerWorkspaceId(source: MuxSessionSource, workspaceId: String) -> String {
        "\(source.rawValue):\(workspaceId)"
    }
}
