import SwiftUI

struct HistorySheetView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var viewModel = HistoryViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HistoryHeaderView(viewModel: viewModel, onDone: { store.hideHistory() })
            Divider()
            HistoryContentView(viewModel: viewModel)
        }
        .frame(minWidth: 620, minHeight: 500)
        .onAppear {
            viewModel.prepareForAppear()
        }
    }
}

private struct HistoryHeaderView: View {
    @ObservedObject var viewModel: HistoryViewModel
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Prompts & Responses")
                .font(.title2.weight(.bold))

            Spacer()

            TextField("Search...", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)

            Picker("Sort", selection: $viewModel.sortMode) {
                ForEach(HistorySortMode.allCases, id: \.rawValue) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 160)

            Button {
                viewModel.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .focusable(false)
            .pointerCursor()
            .hoverPopover("Refresh")

            Button("Done") { onDone() }
                .keyboardShortcut(.cancelAction)
                .focusable(false)
                .pointerCursor()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }
}

private struct HistoryContentView: View {
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.projects.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading history...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredProjects.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No conversations found")
                        .font(.headline)
                    Text(emptyStateMessage)
                        .foregroundStyle(.secondary)

                    if viewModel.hasOlderHistory {
                        Button("Show more") {
                            viewModel.showMoreHistory()
                        }
                        .buttonStyle(.bordered)
                        .focusable(false)
                        .pointerCursor()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    HistoryTimeWindowControlsView(viewModel: viewModel)

                    HStack(alignment: .top, spacing: 12) {
                        HistoryProjectsColumnView(viewModel: viewModel)
                        HistoryConversationsColumnView(viewModel: viewModel)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private var emptyStateMessage: String {
        if viewModel.searchText.isEmpty {
            return viewModel.hasOlderHistory
                ? "No conversations in the current range. Use Show more to include older sessions."
                : "Session history will appear here."
        }

        return "Try a different search term."
    }
}

private struct HistoryTimeWindowControlsView: View {
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        HStack(spacing: 8) {
            Text(viewModel.historyWindowLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if !viewModel.isUsingDefaultWindow {
                Button("Last 10 days") {
                    viewModel.resetHistoryWindow()
                }
                .buttonStyle(.bordered)
                .focusable(false)
                .pointerCursor()
            }

            if viewModel.hasOlderHistory {
                Button("Show more") {
                    viewModel.showMoreHistory()
                }
                .buttonStyle(.bordered)
                .focusable(false)
                .pointerCursor()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }
}

private struct HistoryProjectsColumnView: View {
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Projects")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 10)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.filteredProjects) { project in
                        HistoryProjectButtonView(
                            project: project,
                            isSelected: viewModel.isProjectSelected(project.id),
                            onTap: { viewModel.selectProject(project.id) }
                        )
                    }
                }
                .padding(10)
            }
        }
        .frame(minWidth: 250, idealWidth: 280, maxWidth: 320, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }
}

private struct HistoryProjectButtonView: View {
    let project: HistoryProject
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.projectName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text("\(project.conversationCount) conversations")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(formatTimeAgo(project.latestActivity))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .hoverPointerCursor()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
        )
    }
}

private struct HistoryConversationsColumnView: View {
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let project = viewModel.selectedProject {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(project.projectName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text("\(project.conversationCount) conversations")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(formatTimeAgo(project.latestActivity))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(project.conversations) { conversation in
                            HistoryConversationRowView(
                                conversation: conversation,
                                viewModel: viewModel
                            )
                        }
                    }
                    .padding(10)
                }
            } else {
                Spacer()
                Text("Select a project to view its conversations.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }
}

private struct HistoryConversationRowView: View {
    let conversation: HistoryConversation
    @ObservedObject var viewModel: HistoryViewModel

    private var isExpanded: Bool {
        viewModel.expandedConversationIDs.contains(conversation.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                viewModel.toggleConversation(conversation.id)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Text(conversation.summaryPreview)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let branch = conversation.gitBranch {
                        Text(branch)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.15)))
                            .foregroundStyle(.green)
                            .lineLimit(1)
                    }

                    AgentTypeBadge(agentType: conversation.agentType)

                    Spacer()

                    Text(formatTimeAgo(conversation.lastActivityAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .hoverPointerCursor()

            if isExpanded {
                Divider()
                    .padding(.horizontal, 10)

                if viewModel.isConversationLoading(conversation.id) && !conversation.messagesLoaded {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Loading full conversation...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                } else if conversation.messagesLoaded {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(conversation.userMessages) { message in
                            HistoryMessageView(message: message, viewModel: viewModel)
                        }

                        if let reply = conversation.lastAssistantReply {
                            HistoryMessageView(message: reply, viewModel: viewModel)
                        }
                    }
                    .padding(10)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }
}

private struct HistoryMessageView: View {
    let message: HistoryMessage
    @ObservedObject var viewModel: HistoryViewModel
    @State private var isHovering = false

    private var isUser: Bool {
        message.role == .user
    }

    private var backgroundColor: Color {
        isUser ? Color.blue.opacity(0.08) : Color.primary.opacity(0.06)
    }

    private var roleLabel: String {
        isUser ? "You" : "Agent"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(roleLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isUser ? .blue : .secondary)

                if let timestamp = message.timestamp {
                    Text(formatTimestamp(timestamp))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }

            Text(message.text)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(backgroundColor))
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button {
                    viewModel.copyToClipboard(message.text)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .padding(6)
                        .background(Circle().fill(Color.primary.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .pointerCursor()
                .hoverPopover("Copy")
                .padding(6)
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct AgentTypeBadge: View {
    let agentType: AgentType

    private var label: String {
        switch agentType {
        case .claude: return "CL"
        case .codex: return "CX"
        case .gemini: return "GM"
        case .opencode: return "OC"
        case .t3: return "T3"
        }
    }

    var body: some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.2)))
            .foregroundStyle(.secondary)
    }
}

private func formatTimeAgo(_ date: Date) -> String {
    let delta = Int(Date().timeIntervalSince(date))
    if delta < 60 {
        return "just now"
    }

    let minutes = delta / 60
    if minutes < 60 {
        return "\(minutes)m ago"
    }

    let hours = minutes / 60
    if hours < 24 {
        return "\(hours)h ago"
    }

    let days = hours / 24
    if days < 30 {
        return "\(days)d ago"
    }

    let months = days / 30
    return "\(months)mo ago"
}

private func formatTimestamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter.string(from: date)
}
