import SwiftUI

struct NativeDashboardView: View {
    @EnvironmentObject private var store: AppStore

    private var onlineAgents: [AgentSummary] { store.agents.filter(\.isOnline) }
    private var checkingAgents: [AgentSummary] { store.agents.filter(\.isChecking) }
    private var offlineAgents: [AgentSummary] { store.agents.filter { !$0.isOnline && !$0.isChecking } }
    private var activeRunCount: Int { store.apiRuns.filter(\.isActive).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("\u{6982}\u{89c8}")
                        .font(.largeTitle.bold())
                    Spacer()
                    if store.isLoadingDashboard { ProgressView() }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    NavigationLink {
                        NativeAgentListView(title: "\u{5168}\u{90e8}\u{667a}\u{80fd}\u{4f53}", agents: store.agents)
                    } label: {
                        statCard("\u{667a}\u{80fd}\u{4f53}", value: "\(store.agents.count)", tint: .blue)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        NativeAgentListView(title: "\u{5728}\u{7ebf}\u{667a}\u{80fd}\u{4f53}", agents: onlineAgents)
                    } label: {
                        statCard("\u{5728}\u{7ebf}", value: "\(onlineAgents.count)", tint: .green)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        NativeAgentListView(title: "\u{68c0}\u{6d4b}\u{4e2d}", agents: checkingAgents)
                    } label: {
                        statCard("\u{68c0}\u{6d4b}\u{4e2d}", value: "\(checkingAgents.count)", tint: .orange)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        NativeAgentListView(title: "\u{79bb}\u{7ebf}\u{667a}\u{80fd}\u{4f53}", agents: offlineAgents)
                    } label: {
                        statCard("\u{79bb}\u{7ebf}", value: "\(offlineAgents.count)", tint: .red)
                    }
                    .buttonStyle(.plain)
                }

                sectionCard(title: "\u{5feb}\u{6377}\u{64cd}\u{4f5c}") {
                    NavigationLink {
                        NativeChatView()
                    } label: {
                        quickRow("\u{6253}\u{5f00}\u{7fa4}\u{804a}\u{534f}\u{4f5c}", systemImage: "bubble.left.and.bubble.right")
                    }
                    .buttonStyle(.plain)

                    Divider()

                    NavigationLink {
                        NativeWorkflowView()
                    } label: {
                        quickRow("\u{6253}\u{5f00}\u{539f}\u{751f}\u{5de5}\u{4f5c}\u{6d41}", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .buttonStyle(.plain)

                    Divider()

                    NavigationLink {
                        NativeRunsView()
                    } label: {
                        quickRow("\u{67e5}\u{770b}\u{8fd0}\u{884c}\u{8bb0}\u{5f55}", systemImage: "list.bullet.rectangle")
                    }
                    .buttonStyle(.plain)
                }

                if !store.apiRuns.isEmpty {
                    sectionCard(title: "\u{6700}\u{65b0}\u{8fd0}\u{884c}") {
                        ForEach(store.apiRuns.prefix(4)) { run in
                            NavigationLink {
                                NativeRunDetailView(run: run)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: run.kind == "collaboration" ? "person.3.sequence" : "bolt")
                                        .foregroundStyle(.blue)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(run.displayTitle).font(.subheadline.weight(.semibold))
                                        Text(run.previewText.isEmpty ? run.id : run.previewText)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(run.statusText)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(run.status == "completed" ? .green : .orange)
                                }
                            }
                            .buttonStyle(.plain)
                            if run.id != store.apiRuns.prefix(4).last?.id {
                                Divider()
                            }
                        }
                    }
                }

                if store.agents.isEmpty, !store.isLoadingDashboard {
                    sectionCard(title: "\u{8fde}\u{63a5}\u{72b6}\u{6001}") {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("\u{6682}\u{672a}\u{52a0}\u{8f7d}\u{5230}\u{667a}\u{80fd}\u{4f53}", systemImage: "exclamationmark.triangle")
                                .font(.subheadline.weight(.semibold))
                            Text("\u{8bf7}\u{5728}\u{6211}\u{7684}\u{91cc}\u{68c0}\u{67e5}\u{670d}\u{52a1}\u{5668}\u{5730}\u{5740}\u{548c} API Token\u{3002}\u{5982}\u{679c}\u{670d}\u{52a1}\u{7aef}\u{8fd8}\u{662f}\u{65e7}\u{7248}\u{ff0c}App \u{4f1a}\u{81ea}\u{52a8}\u{56de}\u{9000}\u{5230}\u{65e7}\u{63a5}\u{53e3}\u{52a0}\u{8f7d}\u{3002}")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !store.devProgress.isEmpty {
                    sectionCard(title: "\u{5f53}\u{524d}\u{7814}\u{53d1}\u{8fdb}\u{5ea6}") {
                        ForEach(store.devProgress.prefix(4)) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title ?? item.requirement ?? item.id)
                                    .font(.headline)
                                Text(item.status ?? "\u{672a}\u{77e5}\u{72b6}\u{6001}")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if item.id != store.devProgress.prefix(4).last?.id {
                                Divider()
                            }
                        }
                    }
                }

                sectionCard(title: "\u{667a}\u{80fd}\u{4f53}") {
                    ForEach(store.agents.prefix(12)) { agent in
                        HStack(spacing: 12) {
                            Text(agent.displayIcon)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(agent.name).font(.headline)
                                Text(agent.primaryModelText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(agent.statusText)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(agent.isOnline ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        if agent.id != store.agents.prefix(12).last?.id {
                            Divider()
                        }
                    }
                }
            }
            .padding(20)
        }
        .refreshable { await store.refreshDashboard() }
    }

    private func statCard(_ title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title.bold())
            RoundedRectangle(cornerRadius: 4).fill(tint.opacity(0.8)).frame(height: 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func quickRow(_ title: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage).foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
    }
}

struct NativeAgentListView: View {
    let title: String
    let agents: [AgentSummary]

    var body: some View {
        List {
            if agents.isEmpty {
                VStack(alignment: .center, spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.largeTitle)
                        .foregroundStyle(Color.green)
                    Text("\u{6ca1}\u{6709}\u{667a}\u{80fd}\u{4f53}")
                        .font(.headline)
                    Text("\u{5f53}\u{524d}\u{5206}\u{7c7b}\u{4e0b}\u{6ca1}\u{6709}\u{53ef}\u{663e}\u{793a}\u{7684}\u{667a}\u{80fd}\u{4f53}\u{3002}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(agents) { agent in
                    HStack(spacing: 12) {
                        Text(agent.displayIcon)
                            .font(.title3)
                            .frame(width: 34, height: 34)
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(agent.name)
                                .font(.headline)
                            Text("\(agent.hostGroup) · \(agent.primaryModelText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(agent.statusText)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(statusColor(agent).opacity(0.15))
                            .foregroundStyle(statusColor(agent))
                            .clipShape(Capsule())
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statusColor(_ agent: AgentSummary) -> Color {
        if agent.isOnline { return .green }
        if agent.isChecking { return .orange }
        return .red
    }
}
