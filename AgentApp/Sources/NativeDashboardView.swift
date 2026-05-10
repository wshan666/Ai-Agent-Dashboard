import SwiftUI

struct NativeDashboardView: View {
    @EnvironmentObject private var store: AppStore

    private var onlineCount: Int { store.agents.filter(\.isOnline).count }
    private var offlineCount: Int { max(0, store.agents.count - onlineCount) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("概览")
                        .font(.largeTitle.bold())
                    Spacer()
                    if store.isLoadingDashboard {
                        ProgressView()
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    statCard("智能体", value: "\(store.agents.count)", tint: .blue)
                    statCard("在线", value: "\(onlineCount)", tint: .green)
                    statCard("离线", value: "\(offlineCount)", tint: .orange)
                    statCard("研发任务", value: "\(store.devProgress.count)", tint: .purple)
                }

                sectionCard(title: "快捷操作") {
                    NavigationLink {
                        NativeChatView()
                    } label: {
                        quickRow("打开原生协作", systemImage: "bubble.left.and.bubble.right")
                    }
                    .buttonStyle(.plain)

                    Divider()

                    NavigationLink {
                        NativeWorkflowView()
                    } label: {
                        quickRow("打开原生工作流", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .buttonStyle(.plain)
                }

                if !store.devProgress.isEmpty {
                    sectionCard(title: "当前研发进度") {
                        ForEach(store.devProgress.prefix(4)) { item in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title ?? item.requirement ?? item.id)
                                        .font(.headline)
                                    Text(item.status ?? "未知状态")
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

                sectionCard(title: "智能体") {
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
