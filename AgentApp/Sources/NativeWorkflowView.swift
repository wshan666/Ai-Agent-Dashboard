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
    @FocusState private var focusedField: WorkflowField?

    private enum WorkflowField {
        case codeTask
        case coderTask(UUID)
        case projectDir
        case projectTask
        case projectTest
        case contentTopic
        case pptTopic
        case pptAudience
        case pptGoal
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("工作流中心")
                        .font(.largeTitle.bold())
                    Text("在手机里直接发起不同类型的原生工作流。")
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
                    Label("打开网页工作流中心", systemImage: "safari")
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
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("工作流")
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .dismissKeyboardOnTap()
        .simultaneousGesture(
            DragGesture(minimumDistance: 18).onChanged { _ in
                focusedField = nil
                UIApplication.dismissKeyboard()
            }
        )
        .onDisappear {
            focusedField = nil
            UIApplication.dismissKeyboard()
        }
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
                        focusedField = nil
                        UIApplication.dismissKeyboard()
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
                title: "代码审查工作流",
                subtitle: "描述任务，选择执行智能体，再指定评审和总结人。"
            )

            TextField("描述项目或需求", text: $codeTask, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(4 ... 8)
                .focused($focusedField, equals: .codeTask)

            VStack(spacing: 12) {
                ForEach($codeCoders) { $coder in
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("执行智能体", selection: $coder.agentId) {
                            Text("请选择").tag("")
                            ForEach(onlineAgents) { agent in
                                Text("\(agent.displayIcon) \(agent.name)").tag(agent.id)
                            }
                        }

                        TextField("子任务", text: $coder.task, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2 ... 4)
                            .focused($focusedField, equals: .coderTask(coder.id))
                    }
                    .padding(12)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            HStack {
                Button("新增执行位") {
                    codeCoders.append(WorkflowCoderDraft())
                }
                .buttonStyle(.bordered)

                Spacer()

                Picker("总结人", selection: $codeSummarizerId) {
                    Text("无").tag("")
                    ForEach(onlineAgents) { agent in
                        Text(agent.name).tag(agent.id)
                    }
                }
                .pickerStyle(.menu)
            }

            Button(codeReviewerIds.isEmpty ? "选择评审" : "已选 \(codeReviewerIds.count) 位评审") {
                focusedField = nil
                UIApplication.dismissKeyboard()
                reviewerSheetMode = .codeReviewers
            }
            .buttonStyle(.bordered)

            submitButton(title: "启动代码审查工作流", enabled: canSubmitCode) {
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
                focusedField = nil
                UIApplication.dismissKeyboard()
            }
        }
    }

    private var projectTemplate: some View {
        card {
            headerBlock(
                title: "项目改造工作流",
                subtitle: "适合真实目录改造，包含执行者、评审者和测试命令。"
            )

            TextField("项目目录", text: $projectDraft.projectDir)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .projectDir)

            TextField("改造需求", text: $projectDraft.task, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3 ... 6)
                .focused($focusedField, equals: .projectTask)

            pickerRow("项目经理", selection: $projectDraft.pmId, allowEmpty: true)
            pickerRow("执行者", selection: $projectDraft.executorId)

            Button(projectDraft.reviewerIds.isEmpty ? "选择评审" : "已选 \(projectDraft.reviewerIds.count) 位评审") {
                focusedField = nil
                UIApplication.dismissKeyboard()
                reviewerSheetMode = .projectReviewers
            }
            .buttonStyle(.bordered)

            TextField("测试命令", text: $projectDraft.testCommand)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .projectTest)

            stepperRow(title: "通过分数", value: $projectDraft.passScore, range: 60 ... 100)
            stepperRow(title: "最大重试", value: $projectDraft.maxRetries, range: 0 ... 5)
            Toggle("飞书通知", isOn: $projectDraft.feishuNotify)

            submitButton(title: "启动项目改造工作流", enabled: canSubmitProject) {
                try await store.startProjectWorkflow(projectDraft)
                projectDraft.task = ""
                projectDraft.pmId = ""
                projectDraft.executorId = ""
                projectDraft.reviewerIds.removeAll()
                projectDraft.testCommand = ""
                focusedField = nil
                UIApplication.dismissKeyboard()
            }
        }
    }

    private var contentTemplate: some View {
        card {
            headerBlock(
                title: "内容发布工作流",
                subtitle: "把选题拆成文案、配图、整合和审核。"
            )

            Picker("平台", selection: $contentDraft.platform) {
                Text("小红书").tag("xiaohongshu")
                Text("公众号").tag("wechat")
                Text("朋友圈").tag("moments")
                Text("通用").tag("generic")
            }
            .pickerStyle(.segmented)

            TextField("发布主题", text: $contentDraft.topic, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3 ... 6)
                .focused($focusedField, equals: .contentTopic)

            pickerRow("文案智能体", selection: $contentDraft.copyAgentId)
            pickerRow("图片智能体", selection: $contentDraft.imageAgentId)
            pickerRow("整合智能体", selection: $contentDraft.integratorAgentId)
            pickerRow("审核智能体", selection: $contentDraft.reviewerAgentId, allowEmpty: true)

            Picker("发布模式", selection: $contentDraft.publishMode) {
                Text("草稿").tag("draft")
                Text("人工").tag("manual")
                Text("自动").tag("auto")
            }
            .pickerStyle(.segmented)

            Toggle("飞书通知", isOn: $contentDraft.feishuNotify)

            submitButton(title: "启动内容发布工作流", enabled: canSubmitContent) {
                try await store.startContentWorkflow(contentDraft)
                contentDraft = ContentWorkflowDraft()
                focusedField = nil
                UIApplication.dismissKeyboard()
            }
        }
    }

    private var pptTemplate: some View {
        card {
            headerBlock(
                title: "PPT工作流",
                subtitle: "策划、制作、审核、交付一体化。"
            )

            TextField("主题", text: $pptDraft.topic, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3 ... 6)
                .focused($focusedField, equals: .pptTopic)

            TextField("受众", text: $pptDraft.audience)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .pptAudience)

            TextField("目标", text: $pptDraft.goal)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .pptGoal)

            stepperRow(title: "页数", value: $pptDraft.slideCount, range: 3 ... 30)

            Picker("风格", selection: $pptDraft.style) {
                Text("商务").tag("business")
                Text("科技").tag("tech")
                Text("路演").tag("pitch")
                Text("培训").tag("training")
                Text("极简").tag("minimal")
            }

            Picker("输出", selection: $pptDraft.outputFormat) {
                Text("markdown").tag("markdown")
                Text("pptx").tag("pptx")
                Text("md+pptx").tag("md+pptx")
            }

            pickerRow("策划智能体", selection: $pptDraft.outlineAgentId)
            pickerRow("制作智能体", selection: $pptDraft.makerAgentId)
            pickerRow("审核智能体", selection: $pptDraft.reviewerAgentId)
            pickerRow("终稿智能体", selection: $pptDraft.finalizerAgentId, allowEmpty: true)

            stepperRow(title: "通过分数", value: $pptDraft.passScore, range: 60 ... 100)
            stepperRow(title: "最大重试", value: $pptDraft.maxRetries, range: 0 ... 5)
            Toggle("飞书通知", isOn: $pptDraft.feishuNotify)

            submitButton(title: "启动PPT工作流", enabled: canSubmitPpt) {
                try await store.startPptWorkflow(pptDraft)
                pptDraft = PptWorkflowDraft()
                focusedField = nil
                UIApplication.dismissKeyboard()
            }
        }
    }

    private var devProgressCard: some View {
        card {
            headerBlock(
                title: "最近研发进度",
                subtitle: "展示仪表盘里最新的研发或工作流任务。"
            )

            ForEach(store.devProgress.prefix(6)) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title ?? item.requirement ?? item.id)
                        .font(.subheadline.weight(.semibold))
                    Text(item.status ?? "未知状态")
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
            Text(allowEmpty ? "可选" : "请选择").tag("")
            ForEach(onlineAgents) { agent in
                Text("\(agent.displayIcon) \(agent.name)").tag(agent.id)
            }
        }
    }

    private func stepperRow(title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper("\(title)：\(value.wrappedValue)", value: value, in: range)
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
                Text(isSubmitting ? "提交中..." : title)
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
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
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
        case .codeReviewers: return "代码评审"
        case .projectReviewers: return "项目评审"
        }
    }
}
