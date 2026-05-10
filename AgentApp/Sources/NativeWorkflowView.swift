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
    @State private var musicDraft = MusicWorkflowDraft()
    @State private var musicResult: MusicResult?
    @State private var musicSearchText = ""

    @State private var isSubmitting = false
    @State private var reviewerSheetMode: ReviewerSheetMode?
    @FocusState private var focusedField: WorkflowField?

    private enum WorkflowField {
        case codeTask, projectDir, projectTask, projectTest, contentTopic, pptTopic, pptAudience, pptGoal, musicSong, musicArtist, musicStyle
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\u{5de5}\u{4f5c}\u{6d41}\u{4e2d}\u{5fc3}")
                        .font(.largeTitle.bold())
                    Text("\u{5728}\u{624b}\u{673a}\u{91cc}\u{76f4}\u{63a5}\u{53d1}\u{8d77}\u{4e0d}\u{540c}\u{7c7b}\u{578b}\u{7684}\u{539f}\u{751f}\u{5de5}\u{4f5c}\u{6d41}\u{3002}")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)

                templateSwitcher
                activeTemplateCard

                if !store.devProgress.isEmpty {
                    devProgressCard.padding(.horizontal, 18)
                }

                NavigationLink {
                    AgentWebContainer(route: .workflow)
                } label: {
                    Label("\u{6253}\u{5f00}\u{7f51}\u{9875}\u{5de5}\u{4f5c}\u{6d41}\u{4e2d}\u{5fc3}", systemImage: "safari")
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
        .navigationTitle("\u{5de5}\u{4f5c}\u{6d41}")
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .dismissKeyboardOnTap()
        .sheet(item: $reviewerSheetMode) { mode in reviewerPicker(mode: mode) }
        .task {
            if store.agents.isEmpty { await store.refreshDashboard() }
            if store.musicFavorites.isEmpty && store.musicRecent.isEmpty { await store.loadMusicLibrary() }
        }
    }

    private var templateSwitcher: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
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
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
                    .background(selectedTemplate == template ? Color.blue : Color(.secondarySystemBackground))
                    .foregroundStyle(selectedTemplate == template ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
    }

    @ViewBuilder
    private var activeTemplateCard: some View {
        switch selectedTemplate {
        case .code: codeTemplate.padding(.horizontal, 18)
        case .project: projectTemplate.padding(.horizontal, 18)
        case .content: contentTemplate.padding(.horizontal, 18)
        case .ppt: pptTemplate.padding(.horizontal, 18)
        case .music: musicTemplate.padding(.horizontal, 18)
        }
    }

    private var codeTemplate: some View {
        card {
            headerBlock("\u{4ee3}\u{7801}\u{5ba1}\u{67e5}\u{5de5}\u{4f5c}\u{6d41}", "\u{63cf}\u{8ff0}\u{4efb}\u{52a1}\u{ff0c}\u{9009}\u{62e9}\u{6267}\u{884c}\u{667a}\u{80fd}\u{4f53}\u{ff0c}\u{518d}\u{6307}\u{5b9a}\u{8bc4}\u{5ba1}\u{548c}\u{603b}\u{7ed3}\u{4eba}\u{3002}")
            TextField("\u{63cf}\u{8ff0}\u{9879}\u{76ee}\u{6216}\u{9700}\u{6c42}", text: $codeTask, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(4 ... 8)
                .focused($focusedField, equals: .codeTask)

            VStack(spacing: 12) {
                ForEach($codeCoders) { $coder in
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("\u{6267}\u{884c}\u{667a}\u{80fd}\u{4f53}", selection: $coder.agentId) {
                            Text("\u{8bf7}\u{9009}\u{62e9}").tag("")
                            ForEach(onlineAgents) { agent in
                                Text("\(agent.displayIcon) \(agent.name)").tag(agent.id)
                            }
                        }
                        TextField("\u{5b50}\u{4efb}\u{52a1}", text: $coder.task, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2 ... 4)
                    }
                    .padding(12)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            HStack {
                Button("\u{65b0}\u{589e}\u{6267}\u{884c}\u{4f4d}") { codeCoders.append(WorkflowCoderDraft()) }
                    .buttonStyle(.bordered)
                Spacer()
                Picker("\u{603b}\u{7ed3}\u{4eba}", selection: $codeSummarizerId) {
                    Text("\u{65e0}").tag("")
                    ForEach(onlineAgents) { agent in Text(agent.name).tag(agent.id) }
                }
                .pickerStyle(.menu)
            }

            Button(codeReviewerIds.isEmpty ? "\u{9009}\u{62e9}\u{8bc4}\u{5ba1}" : "\u{5df2}\u{9009} \(codeReviewerIds.count) \u{4f4d}\u{8bc4}\u{5ba1}") {
                reviewerSheetMode = .codeReviewers
            }
            .buttonStyle(.bordered)

            submitButton("\u{542f}\u{52a8}\u{4ee3}\u{7801}\u{5ba1}\u{67e5}\u{5de5}\u{4f5c}\u{6d41}", canSubmitCode) {
                let coders = codeCoders.filter { !$0.agentId.isEmpty && !$0.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                try await store.startCodeWorkflow(task: codeTask.trimmingCharacters(in: .whitespacesAndNewlines), coders: coders, reviewerIds: Array(codeReviewerIds), summarizerId: codeSummarizerId)
                codeTask = ""
                codeCoders = [WorkflowCoderDraft()]
                codeReviewerIds.removeAll()
                codeSummarizerId = ""
            }
        }
    }

    private var projectTemplate: some View {
        card {
            headerBlock("\u{9879}\u{76ee}\u{6539}\u{9020}\u{5de5}\u{4f5c}\u{6d41}", "\u{9002}\u{5408}\u{771f}\u{5b9e}\u{76ee}\u{5f55}\u{6539}\u{9020}\u{ff0c}\u{5305}\u{542b}\u{6267}\u{884c}\u{8005}\u{3001}\u{8bc4}\u{5ba1}\u{8005}\u{548c}\u{6d4b}\u{8bd5}\u{547d}\u{4ee4}\u{3002}")
            TextField("\u{9879}\u{76ee}\u{76ee}\u{5f55}", text: $projectDraft.projectDir).textFieldStyle(.roundedBorder).focused($focusedField, equals: .projectDir)
            TextField("\u{6539}\u{9020}\u{9700}\u{6c42}", text: $projectDraft.task, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(3 ... 6).focused($focusedField, equals: .projectTask)
            pickerRow("\u{9879}\u{76ee}\u{7ecf}\u{7406}", selection: $projectDraft.pmId, allowEmpty: true)
            pickerRow("\u{6267}\u{884c}\u{8005}", selection: $projectDraft.executorId)
            Button(projectDraft.reviewerIds.isEmpty ? "\u{9009}\u{62e9}\u{8bc4}\u{5ba1}" : "\u{5df2}\u{9009} \(projectDraft.reviewerIds.count) \u{4f4d}\u{8bc4}\u{5ba1}") { reviewerSheetMode = .projectReviewers }.buttonStyle(.bordered)
            TextField("\u{6d4b}\u{8bd5}\u{547d}\u{4ee4}", text: $projectDraft.testCommand).textFieldStyle(.roundedBorder).focused($focusedField, equals: .projectTest)
            stepperRow("\u{901a}\u{8fc7}\u{5206}\u{6570}", $projectDraft.passScore, 60 ... 100)
            stepperRow("\u{6700}\u{5927}\u{91cd}\u{8bd5}", $projectDraft.maxRetries, 0 ... 5)
            Toggle("\u{98de}\u{4e66}\u{901a}\u{77e5}", isOn: $projectDraft.feishuNotify)
            submitButton("\u{542f}\u{52a8}\u{9879}\u{76ee}\u{6539}\u{9020}\u{5de5}\u{4f5c}\u{6d41}", canSubmitProject) {
                try await store.startProjectWorkflow(projectDraft)
                projectDraft.task = ""; projectDraft.pmId = ""; projectDraft.executorId = ""; projectDraft.reviewerIds.removeAll(); projectDraft.testCommand = ""
            }
        }
    }

    private var contentTemplate: some View {
        card {
            headerBlock("\u{5185}\u{5bb9}\u{53d1}\u{5e03}\u{5de5}\u{4f5c}\u{6d41}", "\u{628a}\u{9009}\u{9898}\u{62c6}\u{6210}\u{6587}\u{6848}\u{3001}\u{914d}\u{56fe}\u{3001}\u{6574}\u{5408}\u{548c}\u{5ba1}\u{6838}\u{3002}")
            Picker("\u{5e73}\u{53f0}", selection: $contentDraft.platform) {
                Text("\u{5c0f}\u{7ea2}\u{4e66}").tag("xiaohongshu")
                Text("\u{516c}\u{4f17}\u{53f7}").tag("wechat")
                Text("\u{670b}\u{53cb}\u{5708}").tag("moments")
                Text("\u{901a}\u{7528}").tag("generic")
            }.pickerStyle(.segmented)
            TextField("\u{53d1}\u{5e03}\u{4e3b}\u{9898}", text: $contentDraft.topic, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(3 ... 6).focused($focusedField, equals: .contentTopic)
            pickerRow("\u{6587}\u{6848}\u{667a}\u{80fd}\u{4f53}", selection: $contentDraft.copyAgentId)
            pickerRow("\u{56fe}\u{7247}\u{667a}\u{80fd}\u{4f53}", selection: $contentDraft.imageAgentId)
            pickerRow("\u{6574}\u{5408}\u{667a}\u{80fd}\u{4f53}", selection: $contentDraft.integratorAgentId)
            pickerRow("\u{5ba1}\u{6838}\u{667a}\u{80fd}\u{4f53}", selection: $contentDraft.reviewerAgentId, allowEmpty: true)
            Picker("\u{53d1}\u{5e03}\u{6a21}\u{5f0f}", selection: $contentDraft.publishMode) {
                Text("\u{8349}\u{7a3f}").tag("draft")
                Text("\u{4eba}\u{5de5}").tag("manual")
                Text("\u{81ea}\u{52a8}").tag("auto")
            }.pickerStyle(.segmented)
            Toggle("\u{98de}\u{4e66}\u{901a}\u{77e5}", isOn: $contentDraft.feishuNotify)
            submitButton("\u{542f}\u{52a8}\u{5185}\u{5bb9}\u{53d1}\u{5e03}\u{5de5}\u{4f5c}\u{6d41}", canSubmitContent) {
                try await store.startContentWorkflow(contentDraft)
                contentDraft = ContentWorkflowDraft()
            }
        }
    }

    private var pptTemplate: some View {
        card {
            headerBlock("PPT\u{5de5}\u{4f5c}\u{6d41}", "\u{7b56}\u{5212}\u{3001}\u{5236}\u{4f5c}\u{3001}\u{5ba1}\u{6838}\u{3001}\u{4ea4}\u{4ed8}\u{4e00}\u{4f53}\u{5316}\u{3002}")
            TextField("\u{4e3b}\u{9898}", text: $pptDraft.topic, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(3 ... 6).focused($focusedField, equals: .pptTopic)
            TextField("\u{53d7}\u{4f17}", text: $pptDraft.audience).textFieldStyle(.roundedBorder).focused($focusedField, equals: .pptAudience)
            TextField("\u{76ee}\u{6807}", text: $pptDraft.goal).textFieldStyle(.roundedBorder).focused($focusedField, equals: .pptGoal)
            stepperRow("\u{9875}\u{6570}", $pptDraft.slideCount, 3 ... 30)
            Picker("\u{98ce}\u{683c}", selection: $pptDraft.style) {
                Text("\u{5546}\u{52a1}").tag("business")
                Text("\u{79d1}\u{6280}").tag("tech")
                Text("\u{8def}\u{6f14}").tag("pitch")
                Text("\u{57f9}\u{8bad}").tag("training")
                Text("\u{6781}\u{7b80}").tag("minimal")
            }
            Picker("\u{8f93}\u{51fa}", selection: $pptDraft.outputFormat) {
                Text("markdown").tag("markdown")
                Text("pptx").tag("pptx")
                Text("md+pptx").tag("md+pptx")
            }
            pickerRow("\u{7b56}\u{5212}\u{667a}\u{80fd}\u{4f53}", selection: $pptDraft.outlineAgentId)
            pickerRow("\u{5236}\u{4f5c}\u{667a}\u{80fd}\u{4f53}", selection: $pptDraft.makerAgentId)
            pickerRow("\u{5ba1}\u{6838}\u{667a}\u{80fd}\u{4f53}", selection: $pptDraft.reviewerAgentId)
            pickerRow("\u{7ec8}\u{7a3f}\u{667a}\u{80fd}\u{4f53}", selection: $pptDraft.finalizerAgentId, allowEmpty: true)
            stepperRow("\u{901a}\u{8fc7}\u{5206}\u{6570}", $pptDraft.passScore, 60 ... 100)
            stepperRow("\u{6700}\u{5927}\u{91cd}\u{8bd5}", $pptDraft.maxRetries, 0 ... 5)
            Toggle("\u{98de}\u{4e66}\u{901a}\u{77e5}", isOn: $pptDraft.feishuNotify)
            submitButton("\u{542f}\u{52a8} PPT \u{5de5}\u{4f5c}\u{6d41}", canSubmitPpt) {
                try await store.startPptWorkflow(pptDraft)
                pptDraft = PptWorkflowDraft()
            }
        }
    }

    private var musicTemplate: some View {
        card {
            headerBlock("\u{97f3}\u{4e50}\u{5de5}\u{4f5c}\u{6d41}", "\u{8f93}\u{5165}\u{6b4c}\u{66f2}\u{540d}\u{ff0c}\u{751f}\u{6210}\u{6b4c}\u{8bcd}\u{3001}\u{8bd5}\u{542c}\u{97f3}\u{9891}\u{548c}\u{8bf4}\u{660e}\u{6587}\u{6863}\u{3002}")
            TextField("\u{6b4c}\u{66f2}\u{540d}\u{79f0}", text: $musicDraft.song).textFieldStyle(.roundedBorder).focused($focusedField, equals: .musicSong)
            TextField("\u{53c2}\u{8003}\u{6b4c}\u{624b}\u{6216}\u{98ce}\u{683c}", text: $musicDraft.artist).textFieldStyle(.roundedBorder).focused($focusedField, equals: .musicArtist)
            TextField("\u{6b4c}\u{8bcd}\u{98ce}\u{683c}", text: $musicDraft.lyricsStyle).textFieldStyle(.roundedBorder).focused($focusedField, equals: .musicStyle)
            pickerRow("\u{6b4c}\u{8bcd}\u{667a}\u{80fd}\u{4f53}", selection: $musicDraft.agentId, allowEmpty: true)
            Toggle("\u{751f}\u{6210}\u{540e}\u{81ea}\u{52a8}\u{64ad}\u{653e}", isOn: $musicDraft.autoPlay)
            submitButton("\u{542f}\u{52a8}\u{97f3}\u{4e50}\u{5de5}\u{4f5c}\u{6d41}", !musicDraft.song.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                musicResult = try await store.startMusicWorkflow(musicDraft)
                if musicDraft.autoPlay, let result = musicResult {
                    let generated = MusicTrack(
                        id: result.title.isEmpty ? UUID().uuidString : result.title,
                        title: result.title,
                        channel: result.artist,
                        duration: "",
                        source: "generated",
                        sourceLabel: "\u{8bed}\u{97f3}\u{8bd5}\u{5531}",
                        previewUrl: result.audioUrl,
                        url: result.audioUrl,
                        rawId: "",
                        artwork: "",
                        lyrics: result.lyrics,
                        local: false
                    )
                    store.playMusic(track: generated, queue: [generated])
                }
            }

            Divider()
            headerBlock("\u{539f}\u{751f}\u{641c}\u{6b4c}\u{4e0e}\u{64ad}\u{653e}", "\u{76f4}\u{63a5}\u{5728} App \u{91cc}\u{641c}\u{7d22}\u{3001}\u{64ad}\u{653e}\u{3001}\u{6536}\u{85cf}\u{548c}\u{7ba1}\u{7406}\u{6700}\u{8fd1}\u{64ad}\u{653e}\u{3002}")

            HStack(spacing: 10) {
                TextField("\u{641c}\u{7d22}\u{6b4c}\u{66f2}\u{6216} YouTube \u{94fe}\u{63a5}", text: $musicSearchText)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await store.searchMusic(musicSearchText) }
                } label: {
                    if store.isSearchingMusic {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(musicSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isSearchingMusic)
            }

            if let current = store.currentMusicTrack {
                nativePlayerCard(current)
            }

            if let hint = store.musicSearchHint, !hint.isEmpty {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !store.musicSearchResults.isEmpty {
                musicListBlock("\u{641c}\u{7d22}\u{7ed3}\u{679c}", tracks: store.musicSearchResults, showDelete: false)
            }

            musicListBlock("\u{6700}\u{8fd1}\u{64ad}\u{653e}", tracks: store.musicRecent, showDelete: false)
            musicListBlock("\u{6536}\u{85cf}\u{5217}\u{8868}", tracks: store.musicFavorites, showDelete: true)

            if let result = musicResult {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                    Text("\u{6700}\u{8fd1}\u{4e00}\u{6b21}\u{7ed3}\u{679c}").font(.headline)
                    Text(result.artist.isEmpty ? result.title : "\(result.title) - \(result.artist)")
                        .font(.subheadline)
                    if !result.audioUrl.isEmpty, let url = URL(string: result.audioUrl) {
                        Link(destination: url) {
                            Label("\u{6253}\u{5f00}\u{8bd5}\u{542c}\u{97f3}\u{9891}", systemImage: "play.circle.fill")
                        }
                    }
                    if !result.notesUrl.isEmpty, let url = URL(string: result.notesUrl) {
                        Link(destination: url) {
                            Label("\u{6253}\u{5f00}\u{8bf4}\u{660e}\u{6587}\u{6863}", systemImage: "doc.text")
                        }
                    }
                    if !result.lyrics.isEmpty {
                        Text(result.lyrics).font(.caption).foregroundStyle(.secondary).lineLimit(8)
                    }
                }
            }
        }
    }

    private var devProgressCard: some View {
        card {
            headerBlock("\u{6700}\u{8fd1}\u{7814}\u{53d1}\u{8fdb}\u{5ea6}", "\u{5c55}\u{793a}\u{6700}\u{65b0}\u{7684}\u{7814}\u{53d1}\u{6216}\u{5de5}\u{4f5c}\u{6d41}\u{4efb}\u{52a1}\u{3002}")
            ForEach(store.devProgress.prefix(6)) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title ?? item.requirement ?? item.id).font(.subheadline.weight(.semibold))
                    Text(item.status ?? "\u{672a}\u{77e5}\u{72b6}\u{6001}").font(.caption).foregroundStyle(.secondary)
                }
                if item.id != store.devProgress.prefix(6).last?.id { Divider() }
            }
        }
    }

    private var onlineAgents: [AgentSummary] { store.agents.filter(\.isOnline) }

    private var canSubmitCode: Bool {
        !codeTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !codeReviewerIds.isEmpty &&
        !codeCoders.filter { !$0.agentId.isEmpty && !$0.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.isEmpty
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
            Text(allowEmpty ? "\u{53ef}\u{9009}" : "\u{8bf7}\u{9009}\u{62e9}").tag("")
            ForEach(onlineAgents) { agent in
                Text("\(agent.displayIcon) \(agent.name)").tag(agent.id)
            }
        }
    }

    private func stepperRow(_ title: String, _ value: Binding<Int>, _ range: ClosedRange<Int>) -> some View {
        Stepper("\(title)\u{ff1a}\(value.wrappedValue)", value: value, in: range)
    }

    private func headerBlock(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) { content() }
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func nativePlayerCard(_ track: MusicTrack) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                artworkThumbnail(track, size: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title.isEmpty ? "\u{672a}\u{77e5}\u{6b4c}\u{66f2}" : track.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(track.artistText.isEmpty ? track.sourceLabel : track.artistText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    Task { await store.toggleFavorite(track: track) }
                } label: {
                    Image(systemName: store.isFavorite(track: track) ? "star.fill" : "star")
                }
                .buttonStyle(.bordered)
            }

            if !track.lyrics.isEmpty {
                Text(track.lyrics)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            VStack(spacing: 6) {
                Slider(value: Binding(
                    get: { store.musicCurrentTime },
                    set: { store.seekMusic(to: $0) }
                ), in: 0 ... max(store.musicDuration, 1))
                HStack {
                    Text(formatSeconds(store.musicCurrentTime))
                    Spacer()
                    Text(formatSeconds(store.musicDuration))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button { store.playPreviousTrack() } label: {
                    Image(systemName: "backward.fill")
                }
                .buttonStyle(.bordered)

                Button { store.toggleMusicPlayback() } label: {
                    Image(systemName: store.isMusicPlaying ? "pause.fill" : "play.fill")
                        .frame(minWidth: 28)
                }
                .buttonStyle(.borderedProminent)

                Button { store.playNextTrack() } label: {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func musicListBlock(_ title: String, tracks: [MusicTrack], showDelete: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            if tracks.isEmpty {
                Text("\u{6682}\u{65e0}\u{5185}\u{5bb9}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tracks) { track in
                    HStack(spacing: 10) {
                        Button {
                            store.playMusic(track: track, queue: tracks)
                        } label: {
                            artworkThumbnail(track, size: 42)
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: store.currentMusicTrack == track && store.isMusicPlaying ? "speaker.wave.2.fill" : "play.fill")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 18, height: 18)
                                        .background(Color.blue)
                                        .clipShape(Circle())
                                        .offset(x: 2, y: 2)
                                }
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.title.isEmpty ? "\u{672a}\u{77e5}\u{6b4c}\u{66f2}" : track.title)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(track.artistText.isEmpty ? track.sourceLabel : track.artistText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if !track.duration.isEmpty {
                            Text(track.duration)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if showDelete {
                            Button(role: .destructive) {
                                Task { await store.toggleFavorite(track: track) }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                    if track.stableKey != tracks.last?.stableKey { Divider() }
                }
            }
        }
    }

    private func artworkThumbnail(_ track: MusicTrack, size: CGFloat) -> some View {
        Group {
            if let url = artworkURL(for: track) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholderArtwork
                    }
                }
            } else {
                placeholderArtwork
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var placeholderArtwork: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.blue.opacity(0.14))
            .overlay(Text("\u{266A}").font(.title3))
    }

    private func artworkURL(for track: MusicTrack) -> URL? {
        let trimmed = track.artwork.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed, relativeTo: nil)
    }

    private func formatSeconds(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0:00" }
        let total = Int(value.rounded(.down))
        let minute = total / 60
        let second = total % 60
        return String(format: "%d:%02d", minute, second)
    }

    private func submitButton(_ title: String, _ enabled: Bool, action: @escaping () async throws -> Void) -> some View {
        Button {
            Task {
                isSubmitting = true
                defer { isSubmitting = false }
                do {
                    try await action()
                    focusedField = nil
                    UIApplication.dismissKeyboard()
                } catch {
                    store.lastError = error.localizedDescription
                }
            }
        } label: {
            HStack {
                Spacer()
                if isSubmitting { ProgressView().tint(.white) }
                Text(isSubmitting ? "\u{63d0}\u{4ea4}\u{4e2d}..." : title)
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
                    HStack {
                        Text(agent.displayIcon)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.name).foregroundStyle(.primary)
                            Text(agent.primaryModelText).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if hasReviewer(agent.id, mode: mode) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("\u{5b8c}\u{6210}") { reviewerSheetMode = nil }
                }
            }
        }
    }

    private func hasReviewer(_ id: String, mode: ReviewerSheetMode) -> Bool {
        switch mode {
        case .codeReviewers: return codeReviewerIds.contains(id)
        case .projectReviewers: return projectDraft.reviewerIds.contains(id)
        }
    }

    private func toggleReviewer(_ id: String, mode: ReviewerSheetMode) {
        switch mode {
        case .codeReviewers:
            if codeReviewerIds.contains(id) { codeReviewerIds.remove(id) } else { codeReviewerIds.insert(id) }
        case .projectReviewers:
            if projectDraft.reviewerIds.contains(id) { projectDraft.reviewerIds.remove(id) } else { projectDraft.reviewerIds.insert(id) }
        }
    }
}

private enum ReviewerSheetMode: Identifiable {
    case codeReviewers, projectReviewers
    var id: String { self == .codeReviewers ? "code" : "project" }
    var title: String {
        self == .codeReviewers ? "\u{4ee3}\u{7801}\u{8bc4}\u{5ba1}" : "\u{9879}\u{76ee}\u{8bc4}\u{5ba1}"
    }
}
