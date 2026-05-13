import SwiftUI

struct NativeRunsView: View {
    @EnvironmentObject private var store: AppStore

    @State private var filter: RunFilter = .all

    private enum RunFilter: String, CaseIterable, Identifiable {
        case all, queued, running, completed, failed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "\u{5168}\u{90e8}"
            case .queued: return "\u{6392}\u{961f}"
            case .running: return "\u{8fd0}\u{884c}"
            case .completed: return "\u{5b8c}\u{6210}"
            case .failed: return "\u{5931}\u{8d25}"
            }
        }

        var apiStatus: String? {
            self == .all ? nil : rawValue
        }
    }

    var body: some View {
        List {
            Section {
                Picker("\u{72b6}\u{6001}", selection: $filter) {
                    ForEach(RunFilter.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            }

            if store.apiRuns.isEmpty {
                emptyState
            } else {
                Section("\u{8fd1}\u{671f}\u{8fd0}\u{884c}") {
                    ForEach(store.apiRuns) { run in
                        NavigationLink {
                            NativeRunDetailView(run: run)
                        } label: {
                            runRow(run)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .v2PageBackground()
        .navigationTitle("\u{8fd0}\u{884c}\u{8bb0}\u{5f55}")
        .refreshable { await store.refreshRuns(status: filter.apiStatus) }
        .overlay {
            if store.isLoadingRuns {
                ProgressView()
                    .padding(18)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .task {
            await store.refreshRuns(status: filter.apiStatus)
        }
        .onChange(of: filter) { newValue in
            Task { await store.refreshRuns(status: newValue.apiStatus) }
        }
    }

    private var emptyState: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("\u{6682}\u{65e0}\u{8fd0}\u{884c}\u{8bb0}\u{5f55}", systemImage: "tray")
                    .font(.headline)
                Text("\u{4ece}\u{534f}\u{4f5c}\u{6216}\u{6307}\u{6325}\u{5ba4}\u{542f}\u{52a8}\u{4efb}\u{52a1}\u{540e}\u{ff0c}\u{8fd9}\u{91cc}\u{4f1a}\u{663e}\u{793a}\u{72b6}\u{6001}\u{3001}\u{8f93}\u{51fa}\u{548c}\u{6bcf}\u{4e2a} agent \u{7684}\u{56de}\u{590d}\u{3002}")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
        }
    }

    private func runRow(_ run: CollaborationRun) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Label(run.displayTitle, systemImage: run.kind == "collaboration" ? "person.3.sequence" : "bolt")
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
                Text(run.statusText)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(statusColor(run.status).opacity(0.14))
                    .foregroundStyle(statusColor(run.status))
                    .clipShape(Capsule())
            }

            if !run.previewText.isEmpty {
                Text(run.previewText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            HStack(spacing: 10) {
                if let createdAt = run.createdAt {
                    Label(shortDate(createdAt), systemImage: "clock")
                }
                if let latency = run.latencyMs {
                    Label("\(latency)ms", systemImage: "timer")
                }
                if let count = run.agentIds?.count, count > 0 {
                    Label("\(count)", systemImage: "person.3")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct NativeRunDetailView: View {
    @EnvironmentObject private var store: AppStore

    @State var run: CollaborationRun
    @State private var isLoading = false
    @State private var isCancelling = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let input = run.input, !input.isEmpty {
                    block(title: "\u{8f93}\u{5165}", text: input)
                } else if let preview = run.inputPreview, !preview.isEmpty {
                    block(title: "\u{8f93}\u{5165}", text: preview)
                }

                if let output = run.output, !output.isEmpty {
                    block(title: "\u{8f93}\u{51fa}", text: output)
                }

                if let error = run.error, !error.isEmpty {
                    block(title: "\u{9519}\u{8bef}", text: error, color: .red)
                }

                if let responses = run.responses, !responses.isEmpty {
                    responsesBlock(responses)
                }
            }
            .padding(18)
        }
        .v2PageBackground()
        .navigationTitle("\u{8fd0}\u{884c}\u{8be6}\u{60c5}")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if run.isActive {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("\u{53d6}\u{6d88}") {
                        Task { await cancel() }
                    }
                    .disabled(isCancelling)
                }
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
                    .padding(18)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .task { await loadDetail() }
        .refreshable { await loadDetail() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(run.displayTitle)
                        .font(.title2.bold())
                    Text(run.id)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Text(run.statusText)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(statusColor(run.status).opacity(0.14))
                    .foregroundStyle(statusColor(run.status))
                    .clipShape(Capsule())
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metaTile("\u{7c7b}\u{578b}", run.kind ?? "agent")
                metaTile("\u{6267}\u{884c}\u{8005}", run.agentName ?? run.agentIds?.joined(separator: ", ") ?? "-")
                metaTile("\u{521b}\u{5efa}", run.createdAt.map(shortDate) ?? "-")
                metaTile("\u{8017}\u{65f6}", run.latencyMs.map { "\($0)ms" } ?? "-")
            }
        }
        .v2Card(tint: V2Theme.cyan)
    }

    private func block(title: String, text: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .v2Card(tint: V2Theme.cyan)
    }

    private func responsesBlock(_ responses: [CollaborationAgentResponse]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Agent \u{56de}\u{590d}")
                .font(.headline)
            ForEach(responses) { response in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(response.agentName).font(.subheadline.bold())
                        Spacer()
                        Text(response.status)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(statusColor(response.status))
                    }
                    Text(response.displayText.isEmpty ? "\u{65e0}\u{8f93}\u{51fa}" : response.displayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(12)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .v2Card(tint: V2Theme.cyan)
    }

    private func metaTile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func loadDetail() async {
        isLoading = true
        defer { isLoading = false }

        do {
            run = try await store.refreshRunDetail(id: run.id)
        } catch {
            store.lastError = error.localizedDescription
        }
    }

    private func cancel() async {
        isCancelling = true
        defer { isCancelling = false }

        do {
            try await store.cancelRun(id: run.id)
            await loadDetail()
        } catch {
            store.lastError = error.localizedDescription
        }
    }
}

private func statusColor(_ status: String) -> Color {
    switch status {
    case "completed": return .green
    case "running": return .blue
    case "queued": return .orange
    case "failed": return .red
    case "cancelled": return .secondary
    default: return .secondary
    }
}

private func shortDate(_ iso: String) -> String {
    guard let date = iso.asIsoDate else { return iso }
    return date.formatted(date: .abbreviated, time: .shortened)
}
