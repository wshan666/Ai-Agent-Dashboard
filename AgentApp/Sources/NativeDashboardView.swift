import SwiftUI

struct NativeDashboardView: View {
    @EnvironmentObject private var store: AppStore

    private var onlineAgents: [AgentSummary] { store.agents.filter(\.isOnline) }
    private var checkingAgents: [AgentSummary] { store.agents.filter(\.isChecking) }
    private var offlineAgents: [AgentSummary] { store.agents.filter { !$0.isOnline && !$0.isChecking } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                V2HeroHeader(
                    eyebrow: "Agent Command",
                    title: "\u{591a}\u{667a}\u{80fd}\u{4f53}\u{63a7}\u{5236}\u{53f0}",
                    subtitle: "\u{7edf}\u{4e00}\u{76d1}\u{63a7}\u{5728}\u{7ebf}\u{72b6}\u{6001}\u{3001}\u{4f1a}\u{8bdd}\u{534f}\u{4f5c}\u{548c}\u{6700}\u{65b0}\u{4efb}\u{52a1}\u{8fd0}\u{884c}\u{3002}",
                    systemImage: "sensor.tag.radiowaves.forward",
                    tint: V2Theme.cyan
                )

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    NavigationLink {
                        NativeAgentListView(title: "\u{5168}\u{90e8}\u{667a}\u{80fd}\u{4f53}", agents: store.agents)
                    } label: {
                        V2MetricTile(title: "\u{667a}\u{80fd}\u{4f53}", value: "\(store.agents.count)", systemImage: "cpu", tint: V2Theme.cyan)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        NativeAgentListView(title: "\u{5728}\u{7ebf}\u{667a}\u{80fd}\u{4f53}", agents: onlineAgents)
                    } label: {
                        V2MetricTile(title: "\u{5728}\u{7ebf}", value: "\(onlineAgents.count)", systemImage: "dot.radiowaves.left.and.right", tint: V2Theme.mint)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        NativeAgentListView(title: "\u{68c0}\u{6d4b}\u{4e2d}", agents: checkingAgents)
                    } label: {
                        V2MetricTile(title: "\u{68c0}\u{6d4b}\u{4e2d}", value: "\(checkingAgents.count)", systemImage: "waveform.path.ecg", tint: V2Theme.amber)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        NativeAgentListView(title: "\u{79bb}\u{7ebf}\u{667a}\u{80fd}\u{4f53}", agents: offlineAgents)
                    } label: {
                        V2MetricTile(title: "\u{79bb}\u{7ebf}", value: "\(offlineAgents.count)", systemImage: "antenna.radiowaves.left.and.right.slash", tint: V2Theme.red)
                    }
                    .buttonStyle(.plain)
                }

                quickActions
                latestRuns
                connectionState
                agentStrip
            }
            .padding(16)
            .padding(.bottom, 18)
        }
        .v2PageBackground()
        .refreshable { await store.refreshDashboard() }
    }

    private var quickActions: some View {
        sectionCard(title: "\u{5feb}\u{6377}\u{64cd}\u{4f5c}", systemImage: "bolt.horizontal") {
            VStack(spacing: 0) {
                NavigationLink {
                    NativeChatView()
                } label: {
                    quickRow("\u{6253}\u{5f00}\u{7fa4}\u{804a}\u{534f}\u{4f5c}", systemImage: "bubble.left.and.bubble.right")
                }
                .buttonStyle(.plain)

                Divider().opacity(0.45)

                NavigationLink {
                    NativeWorkflowView()
                } label: {
                    quickRow("\u{6253}\u{5f00}\u{539f}\u{751f}\u{5de5}\u{4f5c}\u{6d41}", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .buttonStyle(.plain)

                Divider().opacity(0.45)

                NavigationLink {
                    NativeRunsView()
                } label: {
                    quickRow("\u{67e5}\u{770b}\u{8fd0}\u{884c}\u{8bb0}\u{5f55}", systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var latestRuns: some View {
        if !store.apiRuns.isEmpty {
            sectionCard(title: "\u{6700}\u{65b0}\u{8fd0}\u{884c}", systemImage: "timeline.selection") {
                VStack(spacing: 10) {
                    ForEach(Array(store.apiRuns.prefix(4))) { run in
                        NavigationLink {
                            NativeRunDetailView(run: run)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: run.kind == "collaboration" ? "person.3.sequence" : "bolt")
                                    .foregroundStyle(V2Theme.cyan)
                                    .frame(width: 28, height: 28)
                                    .background(V2Theme.cyan.opacity(0.13))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(run.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(run.previewText.isEmpty ? run.id : run.previewText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                V2StatusBadge(text: run.statusText, tint: V2Theme.statusColor(run.status))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var connectionState: some View {
        if store.agents.isEmpty, !store.isLoadingDashboard {
            sectionCard(title: "\u{8fde}\u{63a5}\u{72b6}\u{6001}", systemImage: "exclamationmark.triangle") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("\u{6682}\u{672a}\u{52a0}\u{8f7d}\u{5230}\u{667a}\u{80fd}\u{4f53}", systemImage: "antenna.radiowaves.left.and.right.slash")
                        .font(.subheadline.weight(.semibold))
                    Text("\u{8bf7}\u{5728}\u{6211}\u{7684}\u{91cc}\u{68c0}\u{67e5}\u{670d}\u{52a1}\u{5668}\u{5730}\u{5740}\u{548c} API Token\u{3002}\u{5982}\u{679c}\u{670d}\u{52a1}\u{7aef}\u{8fd8}\u{662f}\u{65e7}\u{7248}\u{ff0c}App \u{4f1a}\u{81ea}\u{52a8}\u{56de}\u{9000}\u{5230}\u{65e7}\u{63a5}\u{53e3}\u{52a0}\u{8f7d}\u{3002}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var agentStrip: some View {
        sectionCard(title: "\u{667a}\u{80fd}\u{4f53}\u{7f51}\u{683c}", systemImage: "point.3.filled.connected.trianglepath.dotted") {
            VStack(spacing: 10) {
                ForEach(store.agents.prefix(12)) { agent in
                    HStack(spacing: 12) {
                        Text(agent.displayIcon)
                            .font(.title3)
                            .frame(width: 36, height: 36)
                            .background(V2Theme.statusColor(agent).opacity(0.14))
                            .overlay(Circle().stroke(V2Theme.statusColor(agent).opacity(0.42), lineWidth: 1))
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.name)
                                .font(.headline)
                                .lineLimit(1)
                            Text(agent.primaryModelText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        V2StatusBadge(text: agent.statusText, tint: V2Theme.statusColor(agent))
                    }
                }
            }
        }
    }

    private func sectionCard<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                V2SectionLabel(title: title, systemImage: systemImage, tint: V2Theme.cyan)
                Spacer()
                if store.isLoadingDashboard {
                    ProgressView().tint(V2Theme.cyan)
                }
            }
            content()
        }
        .v2Card(tint: V2Theme.cyan)
    }

    private func quickRow(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(V2Theme.cyan)
                .frame(width: 30, height: 30)
                .background(V2Theme.cyan.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
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
                        .foregroundStyle(V2Theme.mint)
                    Text("\u{6ca1}\u{6709}\u{667a}\u{80fd}\u{4f53}")
                        .font(.headline)
                    Text("\u{5f53}\u{524d}\u{5206}\u{7c7b}\u{4e0b}\u{6ca1}\u{6709}\u{53ef}\u{663e}\u{793a}\u{7684}\u{667a}\u{80fd}\u{4f53}\u{3002}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
            } else {
                ForEach(agents) { agent in
                    HStack(spacing: 12) {
                        Text(agent.displayIcon)
                            .font(.title3)
                            .frame(width: 34, height: 34)
                            .background(V2Theme.statusColor(agent).opacity(0.14))
                            .overlay(Circle().stroke(V2Theme.statusColor(agent).opacity(0.45), lineWidth: 1))
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(agent.name)
                                .font(.headline)
                            Text("\(agent.hostGroup) / \(agent.primaryModelText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        V2StatusBadge(text: agent.statusText, tint: V2Theme.statusColor(agent))
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .v2PageBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
