import SwiftUI

struct NativeWorkflowView: View {
    @EnvironmentObject private var store: AppStore
    @State private var task = ""
    @State private var coders: [WorkflowCoderDraft] = [WorkflowCoderDraft()]
    @State private var reviewerIds: Set<String> = []
    @State private var summarizerId = ""
    @State private var isSubmitting = false
    @State private var showReviewers = false

    var body: some View {
        Form {
            Section("Task") {
                TextField("Describe the workflow task", text: $task, axis: .vertical)
                    .lineLimit(4...8)
            }

            Section("Coders") {
                ForEach($coders) { $coder in
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Agent", selection: $coder.agentId) {
                            Text("Select agent").tag("")
                            ForEach(store.agents.filter(\.isOnline)) { agent in
                                Text("\(agent.icon) \(agent.name)").tag(agent.id)
                            }
                        }
                        TextField("Sub task", text: $coder.task, axis: .vertical)
                            .lineLimit(2...4)
                    }
                }
                Button("Add coder") {
                    coders.append(WorkflowCoderDraft())
                }
            }

            Section("Review") {
                Button(reviewerIds.isEmpty ? "Choose reviewers" : "\(reviewerIds.count) reviewers selected") {
                    showReviewers = true
                }
                Picker("Summarizer", selection: $summarizerId) {
                    Text("None").tag("")
                    ForEach(store.agents.filter(\.isOnline)) { agent in
                        Text("\(agent.icon) \(agent.name)").tag(agent.id)
                    }
                }
            }

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    Text(isSubmitting ? "Submitting..." : "Start Workflow")
                        .frame(maxWidth: .infinity)
                }
                .disabled(isSubmitting || !canSubmit)
            }

            if !store.devProgress.isEmpty {
                Section("Recent Progress") {
                    ForEach(store.devProgress.prefix(6)) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title ?? item.requirement ?? item.id)
                                .font(.headline)
                            Text(item.status ?? "unknown")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Advanced") {
                NavigationLink {
                    AgentWebContainer(route: .workflow)
                } label: {
                    Label("Open web workflow center", systemImage: "safari")
                }
            }
        }
        .navigationTitle("Workflow")
        .sheet(isPresented: $showReviewers) {
            NavigationStack {
                List(store.agents.filter(\.isOnline)) { agent in
                    Button {
                        if reviewerIds.contains(agent.id) {
                            reviewerIds.remove(agent.id)
                        } else {
                            reviewerIds.insert(agent.id)
                        }
                    } label: {
                        HStack {
                            Text(agent.icon)
                            Text(agent.name)
                            Spacer()
                            if reviewerIds.contains(agent.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .navigationTitle("Reviewers")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showReviewers = false }
                    }
                }
            }
        }
        .task {
            if store.agents.isEmpty {
                await store.refreshDashboard()
            }
        }
    }

    private var canSubmit: Bool {
        !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !reviewerIds.isEmpty &&
        !coders.filter { !$0.agentId.isEmpty && !$0.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.isEmpty
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let validCoders = coders.filter { !$0.agentId.isEmpty && !$0.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            try await store.startWorkflow(task: task, coders: validCoders, reviewerIds: Array(reviewerIds), summarizerId: summarizerId)
            task = ""
            coders = [WorkflowCoderDraft()]
            reviewerIds = []
            summarizerId = ""
        } catch {
            store.lastError = error.localizedDescription
        }
    }
}
