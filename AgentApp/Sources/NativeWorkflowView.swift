import SwiftUI

struct NativeWorkflowView: View {
    @EnvironmentObject private var store: AppStore

    @State private var selectedTemplate: WorkflowTemplate = .code

    @State private var codeTask = ""
    @State private var codeCoders: [WorkflowCoderDraft] = [WorkflowCoderDraft()]
    @State private var codeReviewerIds: Set<String> = []
    @State private var codeSummarizerId = ""

    @State private var projectDraft = ProjectWorkflowDraft(projectDir: "C:\\Users\\Administrator\\Documents\\New project\\zhongjian_new")
    @State private var contentDraft = ContentWorkflowDraft()
    @State private var pptDraft = PptWorkflowDraft()

    @State private var isSubmitting = false
    @State private var reviewerSheetMode: ReviewerSheetMode?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Workflow Center")
                        .font(.largeTitle.bold())
                    Text("Launch different native workflow templates without leaving the app.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)

                templateSwitcher
                activeTemplateCard

                if !store.devProgress.isEmpty {
                    devProgressCard
                        .padding(.horizontal, 18)
                }

                NavigationLink {
                    AgentWebContainer(route: .workflow)
                } label: {
                    Label("Open web workflow center", systemImage: "safari")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .padding(.top, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Workflow")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $reviewerSheetMode) { mode in
            reviewerPicker(mode: mode)
        }
        .task {
            if store.agents.isEmpty {
                await store.refreshDashboard()
            }
        }
    }

    private var templateSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(WorkflowTemplate.allCases) { template in
                    Button {
                        selectedTemplate = template
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(template.title, systemImage: template.systemImage)
                                .font(.subheadline.bold())
                            Text(template.subtitle)
                                .font(.caption)
                                .foregroundStyle(selectedTemplate == template ? Color.white.opacity(0.85) : .secondary)
                        }
                        .padding(14)
                        .frame(width: 220, alignment: .leading)
                        .background(selectedTemplate == template ? Color.blue : Color(.secondarySystemBackground))
                        .foregroundStyle(selectedTemplate == template ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
        }
    }

    @ViewBuilder
    private var activeTemplateCard: some View {
        switch selectedTemplate {
        case .code:
            codeTemplate.padding(.horizontal, 18)
        case .project:
            projectTemplate.padding(.horizontal, 18)
        case .content:
            contentTemplate.padding(.horizontal, 18)
        case .ppt:
            pptTemplate.padding(.horizontal, 18)
        }
    }

    private var codeTemplate: some View {
        card {
            headerBlock(
                title: "Code Review Pipeline",
                subtitle: "Describe the task, assign coders, then choose reviewers and a summarizer."
            )

            TextField("Describe the project or feature", text: $codeTask, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(4 ... 8)

            VStack(spacing: 12) {
                ForEach($codeCoders) { $coder in
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Coder", selection: $coder.agentId) {
                            Text("Select agent").tag("")
                            ForEach(onlineAgents) { agent in
                                Text("\(agent.displayIcon) \(agent.name)").tag(agent.id)
                            }
                        }

                        TextField("Sub task", text: $coder.task, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2 ... 4)
                    }
                    .padding(12)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            HStack {
                Button("Add coder") {
                    codeCoders.append(WorkflowCoderDraft())
                }
                .buttonStyle(.bordered)

                Spacer()

                Picker("Summarizer", selection: $codeSummarizerId) {
                    Text("None").tag("")
                    ForEach(onlineAgents) { agent in
                        Text(agent.name).tag(agent.id)
                    }
                }
                .pickerStyle(.menu)
            }

            Button(codeReviewerIds.isEmpty ? "Choose reviewers" : "\(codeReviewerIds.count) reviewers selected") {
                reviewerSheetMode = .codeReviewers
            }
            .buttonStyle(.bordered)

            submitButton(title: "Start Code Workflow", enabled: canSubmitCode) {
                let coders = codeCoders.filter {
                    !$0.agentId.isEmpty && !$0.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                try await store.startCodeWorkflow(
                    task: codeTask.trimmingCharacters(in: .whitespacesAndNewlines),
                    coders: coders,
                    reviewerIds: Array(codeReviewerIds),
                    summarizerId: codeSummarizerId
                )
                codeTask = ""
                codeCoders = [WorkflowCoderDraft()]
                codeReviewerIds.removeAll()
                codeSummarizerId = ""
            }
        }
    }

    private var projectTemplate: some View {
        card {
            headerBlock(
                title: "Project Upgrade",
                subtitle: "Use this for a real directory upgrade with executor, reviewers and optional PM."
            )

            TextField("Project directory", text: $projectDraft.projectDir)
                .textFieldStyle(.roundedBorder)

            TextField("Upgrade task", text: $projectDraft.task, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3 ... 6)

            pickerRow("PM Agent", selection: $projectDraft.pmId, allowEmpty: true)
            pickerRow("Executor", selection: $projectDraft.executorId)

            Button(projectDraft.reviewerIds.isEmpty ? "Choose reviewers" : "\(projectDraft.reviewerIds.count) reviewers selected") {
                reviewerSheetMode = .projectReviewers
            }
            .buttonStyle(.bordered)

            TextField("Test command", text: $projectDraft.testCommand)
                .textFieldStyle(.roundedBorder)

            stepperRow(title: "Pass score", value: $projectDraft.passScore, range: 60 ... 100)
            stepperRow(title: "Max retries", value: $projectDraft.maxRetries, range: 0 ... 5)
            Toggle("Feishu notify", isOn: $projectDraft.feishuNotify)

            submitButton(title: "Start Project Upgrade", enabled: canSubmitProject) {
                try await store.startProjectWorkflow(projectDraft)
                projectDraft.task = ""
                projectDraft.pmId = ""
                projectDraft.executorId = ""
                projectDraft.reviewerIds.removeAll()
                projectDraft.testCommand = ""
            }
        }
    }

    private var contentTemplate: some View {
        card {
            headerBlock(
                title: "Content Publish",
                subtitle: "Package a topic into copy, visuals, integration and optional review."
            )

            Picker("Platform", selection: $contentDraft.platform) {
                Text("Xiaohongshu").tag("xiaohongshu")
                Text("WeChat OA").tag("wechat")
                Text("Moments").tag("moments")
                Text("Generic").tag("generic")
            }
            .pickerStyle(.segmented)

            TextField("Topic", text: $contentDraft.topic, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3 ... 6)

            pickerRow("Copy Agent", selection: $contentDraft.copyAgentId)
            pickerRow("Image Agent", selection: $contentDraft.imageAgentId)
            pickerRow("Integrator", selection: $contentDraft.integratorAgentId)
            pickerRow("Reviewer", selection: $contentDraft.reviewerAgentId, allowEmpty: true)

            Picker("Publish Mode", selection: $contentDraft.publishMode) {
                Text("draft").tag("draft")
                Text("manual").tag("manual")
                Text("auto").tag("auto")
            }
            .pickerStyle(.segmented)

            Toggle("Feishu notify", isOn: $contentDraft.feishuNotify)

            submitButton(title: "Start Content Publish", enabled: canSubmitContent) {
                try await store.startContentWorkflow(contentDraft)
                contentDraft = ContentWorkflowDraft()
            }
        }
    }

    private var pptTemplate: some View {
        card {
            headerBlock(
                title: "PPT Review",
                subtitle: "Outline, build, review and finalize a slide deck in one native form."
            )

            TextField("Topic", text: $pptDraft.topic, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3 ... 6)

            TextField("Audience", text: $pptDraft.audience)
                .textFieldStyle(.roundedBorder)

            TextField("Goal", text: $pptDraft.goal)
                .textFieldStyle(.roundedBorder)

            stepperRow(title: "Slides", value: $pptDraft.slideCount, range: 3 ... 30)

            Picker("Style", selection: $pptDraft.style) {
                Text("Business").tag("business")
                Text("Tech").tag("tech")
                Text("Pitch").tag("pitch")
                Text("Training").tag("training")
                Text("Minimal").tag("minimal")
            }

            Picker("Output", selection: $pptDraft.outputFormat) {
                Text("markdown").tag("markdown")
                Text("pptx").tag("pptx")
                Text("md+pptx").tag("md+pptx")
            }

            pickerRow("Outline Agent", selection: $pptDraft.outlineAgentId)
            pickerRow("Maker Agent", selection: $pptDraft.makerAgentId)
            pickerRow("Reviewer Agent", selection: $pptDraft.reviewerAgentId)
            pickerRow("Finalizer", selection: $pptDraft.finalizerAgentId, allowEmpty: true)

            stepperRow(title: "Pass score", value: $pptDraft.passScore, range: 60 ... 100)
            stepperRow(title: "Max retries", value: $pptDraft.maxRetries, range: 0 ... 5)
            Toggle("Feishu notify", isOn: $pptDraft.feishuNotify)

            submitButton(title: "Start PPT Workflow", enabled: canSubmitPpt) {
                try await store.startPptWorkflow(pptDraft)
                pptDraft = PptWorkflowDraft()
            }
        }
    }

    private var devProgressCard: some View {
        card {
            headerBlock(
                title: "Recent Progress",
                subtitle: "Latest development or workflow tasks reported by the dashboard."
            )

            ForEach(store.devProgress.prefix(6)) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title ?? item.requirement ?? item.id)
                        .font(.subheadline.weight(.semibold))
                    Text(item.status ?? "unknown")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if item.id != store.devProgress.prefix(6).last?.id {
                    Divider()
                }
            }
        }
    }

    private var onlineAgents: [AgentSummary] {
        store.agents.filter(\.isOnline)
    }

    private var canSubmitCode: Bool {
        !codeTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !codeReviewerIds.isEmpty &&
        !codeCoders.filter {
            !$0.agentId.isEmpty && !$0.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.isEmpty
    }

    private var canSubmitProject: Bool {
        !projectDraft.projectDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !projectDraft.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !projectDraft.executorId.isEmpty &&
        !projectDraft.reviewerIds.isEmpty
    }

    private var canSubmitContent: Bool {
        !contentDraft.topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !contentDraft.copyAgentId.isEmpty &&
        !contentDraft.imageAgentId.isEmpty &&
        !contentDraft.integratorAgentId.isEmpty
    }

    private var canSubmitPpt: Bool {
        !pptDraft.topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !pptDraft.outlineAgentId.isEmpty &&
        !pptDraft.makerAgentId.isEmpty &&
        !pptDraft.reviewerAgentId.isEmpty
    }

    private func pickerRow(_ title: String, selection: Binding<String>, allowEmpty: Bool = false) -> some View {
        Picker(title, selection: selection) {
            Text(allowEmpty ? "Optional" : "Select").tag("")
            ForEach(onlineAgents) { agent in
                Text("\(agent.displayIcon) \(agent.name)").tag(agent.id)
            }
        }
    }

    private func stepperRow(title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper("\(title): \(value.wrappedValue)", value: value, in: range)
    }

    private func headerBlock(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func submitButton(title: String, enabled: Bool, action: @escaping () async throws -> Void) -> some View {
        Button {
            Task {
                isSubmitting = true
                defer { isSubmitting = false }
                do {
                    try await action()
                } catch {
                    store.lastError = error.localizedDescription
                }
            }
        } label: {
            HStack {
                Spacer()
                if isSubmitting {
                    ProgressView()
                        .tint(.white)
                }
                Text(isSubmitting ? "Submitting..." : title)
                Spacer()
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isSubmitting || !enabled)
    }

    private func reviewerPicker(mode: ReviewerSheetMode) -> some View {
        NavigationStack {
            List(onlineAgents) { agent in
                Button {
                    toggleReviewer(agent.id, mode: mode)
                } label: {
                    HStack(spacing: 12) {
                        Text(agent.displayIcon)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.name)
                                .foregroundStyle(.primary)
                            Text(agent.primaryModelText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if hasReviewer(agent.id, mode: mode) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        reviewerSheetMode = nil
                    }
                }
            }
        }
    }

    private func hasReviewer(_ id: String, mode: ReviewerSheetMode) -> Bool {
        switch mode {
        case .codeReviewers:
            return codeReviewerIds.contains(id)
        case .projectReviewers:
            return projectDraft.reviewerIds.contains(id)
        }
    }

    private func toggleReviewer(_ id: String, mode: ReviewerSheetMode) {
        switch mode {
        case .codeReviewers:
            if codeReviewerIds.contains(id) {
                codeReviewerIds.remove(id)
            } else {
                codeReviewerIds.insert(id)
            }
        case .projectReviewers:
            if projectDraft.reviewerIds.contains(id) {
                projectDraft.reviewerIds.remove(id)
            } else {
                projectDraft.reviewerIds.insert(id)
            }
        }
    }
}

private enum ReviewerSheetMode: Identifiable {
    case codeReviewers
    case projectReviewers

    var id: String {
        switch self {
        case .codeReviewers: return "code"
        case .projectReviewers: return "project"
        }
    }

    var title: String {
        switch self {
        case .codeReviewers: return "Code Reviewers"
        case .projectReviewers: return "Project Reviewers"
        }
    }
}
