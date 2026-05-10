import SwiftUI

struct NativeDashboardView: View {
    @EnvironmentObject private var store: AppStore

    private var onlineCount: Int { store.agents.filter(\.isOnline).count }
    private var offlineCount: Int { max(0, store.agents.count - onlineCount) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Overview")
                        .font(.largeTitle.bold())
                    Spacer()
                    if store.isLoadingDashboard {
                        ProgressView()
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    statCard("Agents", value: "\(store.agents.count)", tint: .blue)
                    statCard("Online", value: "\(onlineCount)", tint: .green)
                    statCard("Offline", value: "\(offlineCount)", tint: .orange)
                    statCard("Dev Tasks", value: "\(store.devProgress.count)", tint: .purple)
                }

                sectionCard(title: "Quick Actions") {
                    NavigationLink {
                        NativeChatView()
                    } label: {
                        quickRow("Open Native Chat", systemImage: "bubble.left.and.bubble.right")
                    }
                    .buttonStyle(.plain)

                    Divider()

                    NavigationLink {
                        NativeWorkflowView()
                    } label: {
                        quickRow("Open Native Workflow", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .buttonStyle(.plain)
                }

                if !store.devProgress.isEmpty {
                    sectionCard(title: "Current Dev Progress") {
                        ForEach(store.devProgress.prefix(4)) { item in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title ?? item.requirement ?? item.id)
                                        .font(.headline)
                                    Text(item.status ?? "unknown")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            if item.id != store.devProgress.prefix(4).last?.id {
                                Divider()
                            }
                        }
                    }
                }

                sectionCard(title: "Agents") {
                    ForEach(store.agents.prefix(10)) { agent in
                        HStack(spacing: 12) {
                            Text(agent.displayIcon)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(agent.name)
                                    .font(.headline)
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
                        if agent.id != store.agents.prefix(10).last?.id {
                            Divider()
                        }
                    }
                }
            }
            .padding(20)
        }
        .refreshable {
            await store.refreshDashboard()
        }
    }

    private func statCard(_ title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title.bold())
            RoundedRectangle(cornerRadius: 4)
                .fill(tint.opacity(0.8))
                .frame(height: 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func quickRow(_ title: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
    }
}
