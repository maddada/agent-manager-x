import AppKit
import Foundation
import SwiftUI

@MainActor
final class HistoryViewModel: ObservableObject {
    private static let defaultVisibleDays = 10
    private static let visibleDaysIncrement = 10

    @Published private(set) var projects: [HistoryProject] = []
    @Published private(set) var isLoading = false
    @Published var searchText = "" {
        didSet { syncSelectedProject() }
    }
    @Published var sortMode: HistorySortMode = .latestActivity {
        didSet { syncSelectedProject() }
    }
    @Published private(set) var visibleDays = HistoryViewModel.defaultVisibleDays
    @Published private(set) var selectedProjectID: String?
    @Published var expandedConversationIDs: Set<String> = []
    @Published private(set) var loadingConversationIDs: Set<String> = []
    @Published private(set) var hasOlderHistory = false

    private let historyService = HistoryService()
    private let loadQueue = DispatchQueue(label: "HistoryViewModel.load", qos: .userInitiated)

    var filteredProjects: [HistoryProject] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered: [HistoryProject]

        if query.isEmpty {
            filtered = projects
        } else {
            filtered = projects.compactMap { project -> HistoryProject? in
                if project.projectName.lowercased().contains(query) {
                    return project
                }

                let matchingConversations = project.conversations.filter { conversation in
                    if let branch = conversation.gitBranch,
                       branch.lowercased().contains(query) {
                        return true
                    }
                    if conversation.summaryPreview.lowercased().contains(query) {
                        return true
                    }
                    return conversation.userMessages.contains { $0.text.lowercased().contains(query) }
                        || (conversation.lastAssistantReply?.text.lowercased().contains(query) ?? false)
                }

                guard !matchingConversations.isEmpty else { return nil }
                return HistoryProject(projectPath: project.projectPath, conversations: matchingConversations)
            }
        }

        switch sortMode {
        case .latestActivity:
            return filtered.sorted { $0.latestActivity > $1.latestActivity }
        case .alphabetical:
            return filtered.sorted { $0.projectName.localizedCaseInsensitiveCompare($1.projectName) == .orderedAscending }
        }
    }

    var selectedProject: HistoryProject? {
        guard let id = activeSelectedProjectID else { return nil }
        return filteredProjects.first(where: { $0.id == id })
    }

    var historyWindowLabel: String {
        "Last \(visibleDays) days"
    }

    var isUsingDefaultWindow: Bool {
        visibleDays == HistoryViewModel.defaultVisibleDays
    }

    func prepareForAppear() {
        visibleDays = HistoryViewModel.defaultVisibleDays
        expandedConversationIDs = []
        loadingConversationIDs = []
        load()
    }

    func load() {
        isLoading = true
        let service = historyService
        let cutoffDate = cutoffDateForCurrentWindow()

        loadQueue.async { [weak self] in
            let result = service.loadAllProjects(modifiedSince: cutoffDate)
            let hasOlderHistory = service.hadOlderHistoryInLastLoad

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.projects = result
                self.hasOlderHistory = hasOlderHistory
                self.syncSelectedProject()
                self.isLoading = false
            }
        }
    }

    func reload() {
        historyService.clearCache()
        load()
    }

    func selectProject(_ id: String) {
        guard selectedProjectID != id else { return }
        selectedProjectID = id
        expandedConversationIDs = []
    }

    func isProjectSelected(_ id: String) -> Bool {
        activeSelectedProjectID == id
    }

    func showMoreHistory() {
        guard hasOlderHistory else { return }
        visibleDays += HistoryViewModel.visibleDaysIncrement
        load()
    }

    func resetHistoryWindow() {
        guard visibleDays != HistoryViewModel.defaultVisibleDays else { return }
        visibleDays = HistoryViewModel.defaultVisibleDays
        load()
    }

    func toggleConversation(_ id: String) {
        if expandedConversationIDs.contains(id) {
            expandedConversationIDs.remove(id)
        } else {
            expandedConversationIDs.insert(id)
            loadConversationDetailsIfNeeded(conversationID: id)
        }
    }

    func isConversationLoading(_ id: String) -> Bool {
        loadingConversationIDs.contains(id)
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private var activeSelectedProjectID: String? {
        if let selectedProjectID,
           filteredProjects.contains(where: { $0.id == selectedProjectID }) {
            return selectedProjectID
        }
        return filteredProjects.first?.id
    }

    private func syncSelectedProject() {
        guard let selectedID = activeSelectedProjectID else {
            selectedProjectID = nil
            expandedConversationIDs = []
            return
        }

        if selectedProjectID != selectedID {
            selectedProjectID = selectedID
            expandedConversationIDs = []
        }
    }

    private func cutoffDateForCurrentWindow() -> Date {
        Calendar.current.date(byAdding: .day, value: -visibleDays, to: Date()) ?? .distantPast
    }

    private func conversation(withID conversationID: String) -> HistoryConversation? {
        for project in projects {
            if let conversation = project.conversations.first(where: { $0.id == conversationID }) {
                return conversation
            }
        }
        return nil
    }

    private func loadConversationDetailsIfNeeded(conversationID: String) {
        guard let conversation = conversation(withID: conversationID),
              !conversation.messagesLoaded,
              !loadingConversationIDs.contains(conversationID) else {
            return
        }

        loadingConversationIDs.insert(conversationID)
        let service = historyService

        loadQueue.async { [weak self] in
            let details = service.loadConversationDetails(for: conversation)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.loadingConversationIDs.remove(conversationID)

                guard let details else { return }
                self.replaceConversation(details)
            }
        }
    }

    private func replaceConversation(_ updatedConversation: HistoryConversation) {
        var didReplace = false
        let updatedProjects = projects.map { project -> HistoryProject in
            guard let index = project.conversations.firstIndex(where: { $0.id == updatedConversation.id }) else {
                return project
            }

            var conversations = project.conversations
            conversations[index] = updatedConversation
            didReplace = true
            return HistoryProject(
                projectPath: project.projectPath,
                conversations: conversations.sorted { $0.lastActivityAt > $1.lastActivityAt }
            )
        }

        guard didReplace else { return }
        projects = updatedProjects
        syncSelectedProject()
    }
}
