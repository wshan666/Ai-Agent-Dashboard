import SwiftUI

struct NativeDashboardView: View {
    @EnvironmentObject private var store: AppStore

    private var onlineCount: Int { store.agents.filter(\.isOnline).count }
    private var offlineCount: Int { max(0, store.agents.count - onlineCount) }
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
                    statCard("\u{667a}\u{80fd}\u{4f53}", value: "\(store.agents.count)", tint: .blue)
                    statCard("\u{5728}\u{7ebf}", value: "\(onlineCount)", tint: .green)
                    statCard("\u{79bb}\u{7ebf}", value: "\(offlineCount)", tint: .orange)
                    statCard("\u{8fd0}\u{884c}\u{4e2d}", value: "\(activeRunCount)", tint: .purple)
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
