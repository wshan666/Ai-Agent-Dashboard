import SwiftUI

struct NativeBigScreenView: View {
    @EnvironmentObject private var store: AppStore

    @State private var selectedAgentIds: Set<String> = []
    @State private var topic = ""
    @State private var prompt = ""
    @State private var mode = "parallel"
    @State private var summarizerId = ""
    @State private var isRunning = false
    @State private var activeRun: CollaborationRun?
    @FocusState private var focusedField: Field?

    private enum Field { case topic, prompt }

    private var selectedAgents: [AgentSummary] {
        store.agents.filter { selectedAgentIds.contains($0.id) }
    }

    private var onlineAgents: [AgentSummary] {
        store.agents.filter { !$0.disabled && $0.isOnline }
    }

    private var canRun: Bool {
        selectedAgentIds.count >= 2 && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                commandCard
                agentBoard
                if let activeRun {
                    resultCard(activeRun)
                } else {
                    emptyState
                }
            }
            .padding(18)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("指挥室")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.refreshDashboard() }
        .dismissKeyboardOnTap()
        .task {
            if store.agents.isEmpty { await store.refreshDashboard() }
            if selectedAgentIds.isEmpty {
                selectedAgentIds = Set(onlineAgents.prefix(3).map(\.id))
            }
            if activeRun == nil {
                activeRun = store.lastCollaborationRun
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("多 Agent 指挥室")
                        .font(.largeTitle.bold())
                    Text("选择成员，发起协同任务，直接查看每个 agent 的贡献。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.isLoadingDashboard { ProgressView() }
            }

            HStack(spacing: 10) {
                metric("在线", "\(onlineAgents.count)", .green)
                metric("已选", "\(selectedAgentIds.count)", .blue)
                metric("总数", "\(store.agents.count)", .purple)
            }
        }
    }

    private var commandCard: some View {
        card {
            HStack {
                Label("协同任务", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Picker("", selection: $mode) {
                    Text("并行").tag("parallel")
                    Text("顺序").tag("sequential")
                }
                .pickerStyle(.segmented)
                .frame(width: 132)
            }

            TextField("话题，例如：客户上线方案", text: $topic)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .topic)

            TextField("输入要交给多个 agent 协作的任务", text: $prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(4 ... 8)
                .focused($focusedField, equals: .prompt)

            Picker("总结 agent", selection: $summarizerId) {
                Text("自动合并").tag("")
                ForEach(selectedAgents) { agent in
                    Text(agent.name).tag(agent.id)
                }
            }
            .pickerStyle(.menu)

            HStack {
                Button("选择在线成员") {
                    selectedAgentIds = Set(onlineAgents.prefix(4).map(\.id))
                }
                .buttonStyle(.bordered)

                Button("清空") {
                    selectedAgentIds.removeAll()
                    summarizerId = ""
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    Task { await runCollaboration() }
                } label: {
                    if isRunning {
                        ProgressView().tint(.white)
                    } else {
                        Label("启动", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canRun || isRunning)
            }
        }
    }

    private var agentBoard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("成员")
                    .font(.headline)
                Spacer()
                Button(selectedAgentIds.count == onlineAgents.count ? "取消全选" : "全选在线") {
                    if selectedAgentIds.count == onlineAgents.count {
                        selectedAgentIds.removeAll()
                    } else {
                        selectedAgentIds = Set(onlineAgents.map(\.id))
                    }
                }
                .font(.caption.weight(.semibold))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(store.agents) { agent in
                    agentTile(agent)
                }
            }
        }
    }

    private func agentTile(_ agent: AgentSummary) -> some View {
        let selected = selectedAgentIds.contains(agent.id)
        return Button {
            if selected {
                selectedAgentIds.remove(agent.id)
                if summarizerId == agent.id { summarizerId = "" }
            } else if !agent.disabled {
                selectedAgentIds.insert(agent.id)
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(agent.displayIcon)
                        .font(.title2)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.blue : Color.secondary)
                }
                Text(agent.name)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(agent.primaryModelText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack {
                    Circle()
                        .fill(agent.isOnline ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(agent.statusText)
                        .font(.caption2.weight(.semibold))
                    Spacer()
                    Text(agent.hostGroup)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
            .background(selected ? Color.blue.opacity(0.12) : Color(.secondarySystemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? Color.blue.opacity(0.55) : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(agent.disabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(agent.disabled)
    }

    private func resultCard(_ run: CollaborationRun) -> some View {
        card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("协同结果")
                        .font(.headline)
                    Text(run.status)
                        .font(.caption)
                        .foregroundStyle(run.isCompleted ? .green : .secondary)
                }
                Spacer()
                if isRunning { ProgressView() }
            }

            if let output = run.output, !output.isEmpty {
                Text(output)
                    .font(.subheadline)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if let responses = run.responses, !responses.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("成员输出")
                        .font(.subheadline.bold())
                    ForEach(responses) { response in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(response.agentName)
                                    .font(.caption.bold())
                                Spacer()
                                Text(response.status)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(response.status == "completed" ? .green : .orange)
                            }
                            Text(response.displayText.isEmpty ? "无输出" : response.displayText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(6)
                                .textSelection(.enabled)
                        }
                        .padding(10)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("等待协同任务", systemImage: "person.3.sequence")
                .font(.headline)
            Text("这里会显示最新一次原生协同执行结果和每个成员的输出。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func metric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func runCollaboration() async {
        let task = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return }

        isRunning = true
        focusedField = nil
        UIApplication.dismissKeyboard()
        defer { isRunning = false }

        do {
            let run = try await store.startCollaboration(
                agentIds: Array(selectedAgentIds),
                message: task,
                topic: topic.trimmingCharacters(in: .whitespacesAndNewlines),
                mode: mode,
                summarizerId: summarizerId
            )
            activeRun = run
        } catch {
            store.lastError = error.localizedDescription
        }
    }
}
