import SwiftUI

/// Clean Researcher workspace: browse news headlines / trending topics and run the NewsResearcher agent.
struct ResearcherView: View {
    @Bindable var viewModel: ResearcherViewModel

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 0) {
                sidebarView
                    .frame(width: max(380, min(460, geometry.size.width * 0.38)))
                Divider().overlay(AppTheme.line)
                detailAreaView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AppTheme.paper)
        .task {
            await viewModel.initialLoad()
        }
    }

    // MARK: - Left Sidebar: News & Research Controls

    private var sidebarView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                storySection
                researcherAgentSection
                actionSection
            }
            .padding(24)
        }
        .background(AppTheme.paper)
        .scrollIndicators(.visible)
        .background(ScrollBarConfiguration())
        .disabled(viewModel.isResearching)
    }

    private var storySection: some View {
        StudioSection("Story") {
            EmptyView()
        } content: {
            StudioRow("Source", inset: 0) {
                StudioOptionPicker("Source", selection: $viewModel.selectedStorySource, options: viewModel.storySources)
                    .onChange(of: viewModel.selectedStorySource) { _, _ in
                        Task { await viewModel.onStorySourceChanged() }
                    }
            }

            if viewModel.isHashtagSource {
                StudioRow("Trending hashtag", inset: 0) {
                    HStack(spacing: 8) {
                        if viewModel.trendingHashtags.isEmpty {
                            HStack(spacing: 6) {
                                if viewModel.isRefreshingHashtags {
                                    ProgressView().controlSize(.small)
                                    Text("Loading hashtags…")
                                        .font(.callout)
                                        .foregroundStyle(AppTheme.secondaryInk)
                                } else if let error = viewModel.hashtagsErrorMessage {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.danger)
                                    Text(error)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .foregroundStyle(AppTheme.secondaryInk)
                                } else {
                                    Text("No hashtags found")
                                        .font(.callout)
                                        .foregroundStyle(AppTheme.secondaryInk)
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        } else {
                            StudioOptionPicker(
                                "Trending hashtag",
                                selection: $viewModel.selectedHashtag,
                                options: [""] + viewModel.trendingHashtags.map(\.tag),
                                label: { $0.isEmpty ? "None" : $0 }
                            )
                            .disabled(viewModel.isRefreshingHashtags)
                            .onChange(of: viewModel.selectedHashtag) { _, new in
                                viewModel.onHashtagChanged(new)
                            }
                        }
                        StudioRefreshButton(
                            isRefreshing: viewModel.isRefreshingHashtags,
                            helpText: "Refresh trending hashtags"
                        ) {
                            Task { await viewModel.refreshHashtags(forceFresh: true) }
                        }
                        .padding(.trailing, 10)
                    }
                }

                StudioRow("Custom hashtag") {
                    TextField("e.g. #MakeInIndia", text: $viewModel.customHashtag)
                        .onSubmit {
                            if !viewModel.customHashtag.isEmpty {
                                viewModel.onHashtagChanged(viewModel.customHashtag)
                            }
                        }
                }

                if let detail = viewModel.selectedTagDetail {
                    VStack(alignment: .leading, spacing: 6) {
                        if let h = detail.headline, !h.isEmpty {
                            Text(h).font(.subheadline.weight(.medium)).foregroundStyle(AppTheme.ink)
                        }
                        if let s = detail.summary, !s.isEmpty {
                            Text(s).font(.caption).foregroundStyle(AppTheme.secondaryInk).lineLimit(3)
                        }
                        if let src = detail.source, !src.isEmpty {
                            Text("Source: \(src)").font(.caption2).foregroundStyle(AppTheme.secondaryInk)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 8))
                }
            } else if !viewModel.isManualSource {
                // Group 1: Subgroup / Category
                StudioRow("Subgroup", inset: 0) {
                    HStack(spacing: 8) {
                        if viewModel.categories.isEmpty {
                            HStack(spacing: 6) {
                                if viewModel.isRefreshingCategories {
                                    ProgressView().controlSize(.small)
                                    Text("Loading subgroups…")
                                        .font(.callout)
                                        .foregroundStyle(AppTheme.secondaryInk)
                                } else if let error = viewModel.categoriesErrorMessage {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.danger)
                                    Text(error)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .foregroundStyle(AppTheme.secondaryInk)
                                } else {
                                    Text("No subgroups found")
                                        .font(.callout)
                                        .foregroundStyle(AppTheme.secondaryInk)
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        } else {
                            StudioOptionPicker(
                                "Subgroup",
                                selection: $viewModel.selectedCategory,
                                options: viewModel.categories.map(\.id),
                                label: { id in
                                    viewModel.categories.first(where: { $0.id == id })?.label ?? id
                                }
                            )
                            .disabled(viewModel.isRefreshingCategories)
                            .onChange(of: viewModel.selectedCategory) { _, newCat in
                                Task { await viewModel.onCategoryChanged(newCat) }
                            }
                        }

                        StudioRefreshButton(
                            isRefreshing: viewModel.isRefreshingCategories,
                            helpText: "Refresh news subgroups"
                        ) {
                            Task { await viewModel.loadCategories(forceFresh: true) }
                        }
                        .padding(.trailing, 10)
                    }
                }

                // Group 2: Headline
                StudioRow("Headline", inset: 0) {
                    HStack(spacing: 8) {
                        if viewModel.headlines.isEmpty {
                            HStack(spacing: 6) {
                                if viewModel.isRefreshingHeadlines {
                                    ProgressView().controlSize(.small)
                                    Text("Loading headlines…")
                                        .font(.callout)
                                        .foregroundStyle(AppTheme.secondaryInk)
                                } else if let error = viewModel.headlinesErrorMessage {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.danger)
                                    Text(error)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .foregroundStyle(AppTheme.secondaryInk)
                                } else {
                                    Text("No headlines found")
                                        .font(.callout)
                                        .foregroundStyle(AppTheme.secondaryInk)
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        } else {
                            StudioOptionPicker(
                                "Headline",
                                selection: $viewModel.selectedHeadline,
                                options: viewModel.headlines
                            )
                            .disabled(viewModel.isRefreshingHeadlines)
                            .onChange(of: viewModel.selectedHeadline) { _, new in
                                viewModel.onHeadlineChanged(new)
                            }
                        }

                        StudioRefreshButton(
                            isRefreshing: viewModel.isRefreshingHeadlines,
                            helpText: "Refresh headlines"
                        ) {
                            Task { await viewModel.refreshHeadlines(forceFresh: true) }
                        }
                        .padding(.trailing, 10)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.isManualSource ? "Title" : "Topic").font(.callout.weight(.medium))
                TextField("Write your title or news topic…", text: $viewModel.topic, axis: .vertical)
                    .lineLimit(viewModel.isManualSource ? 1...2 : 2...4)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var researcherAgentSection: some View {
        StudioSection("Agent Configuration") {
            EmptyView()
        } content: {
            Toggle("Use app default", isOn: $viewModel.usesAppDefault)
            StudioRow("Provider", inset: 0) {
                StudioOptionPicker(
                    "Provider",
                    selection: Binding(
                        get: { viewModel.selectedProvider.rawValue },
                        set: { if let p = LocalAgentProvider(rawValue: $0) { viewModel.selectedProvider = p } }
                    ),
                    options: LocalAgentProvider.allCases.map(\.rawValue),
                    label: { raw in
                        guard let p = LocalAgentProvider(rawValue: raw) else { return raw }
                        let avail = viewModel.availableProviders[p]
                        let suffix = (avail?.isAvailable == true) ? "" : " (Unavailable)"
                        return p.title + suffix
                    }
                )
            }

            Text(viewModel.providerNotice).font(.caption).foregroundStyle(AppTheme.secondaryInk)
            StudioRow("Model Override") {
                TextField("Default / Override (optional)", text: $viewModel.customModel)
            }

            DisclosureGroup("Advanced options") {
                VStack(alignment: .leading, spacing: 12) {
                    StudioRow("Source URL") {
                        TextField("https://… (optional)", text: $viewModel.sourceURL)
                    }
                    StudioRow("Instruction") {
                        TextField("e.g. Focus on economic impact", text: $viewModel.humanInstruction)
                    }
                    StudioRow("Language") {
                        TextField("English", text: $viewModel.language)
                    }
                }
                .padding(.top, 8)
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(AppTheme.secondaryInk)
        }
    }

    private var actionSection: some View {
        StudioSection("Research") {
            EmptyView()
        } content: {
            HStack(spacing: 12) {
                LoadingButton(isLoading: viewModel.isResearching) {
                    Task { await viewModel.runResearch() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkle.magnifyingglass")
                        Text(viewModel.isResearching ? "Researching…" : "Run Research")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(StudioPrimaryButtonStyle())
                .controlSize(.large)
                .disabled(!viewModel.canRunResearch)

                Button {
                    viewModel.openInPipeline()
                } label: {
                    Label("Start in Pipeline", systemImage: "arrow.triangle.branch")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(viewModel.topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isResearching)
                .help("Open current topic in Pipeline")
            }
        }
    }

    // MARK: - Right Detail Area: Research Output

    private var detailAreaView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let error = viewModel.errorMessage {
                    errorBanner(error)
                }

                if viewModel.isResearching {
                    loadingView
                } else if let result = viewModel.researchResult {
                    resultView(result)
                } else {
                    emptyStateView
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppTheme.paper)
        .scrollIndicators(.visible)
        .background(ScrollBarConfiguration())
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.danger)
                .font(.title3)
            Text(message)
                .font(.callout)
                .foregroundStyle(AppTheme.ink)
            Spacer()
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.danger.opacity(0.4), lineWidth: 1))
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Fact-checking and researching with NewsResearcher…")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            Text("Using \(viewModel.selectedProvider.title)")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private func resultView(_ result: NewsResearchResult) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Top Bar: Verification Badge, Confidence, Date, Location, Actions
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: result.verified ? "checkmark.seal.fill" : "xmark.seal.fill")
                    Text(result.verified ? "Verified" : "Unverified / False")
                        .fontWeight(.semibold)
                }
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(result.verified ? AppTheme.success : AppTheme.danger)
                .background(result.verified ? AppTheme.success.opacity(0.12) : AppTheme.danger.opacity(0.12), in: Capsule())

                HStack(spacing: 4) {
                    Text("Confidence:")
                        .foregroundStyle(AppTheme.secondaryInk)
                    Text("\(result.confidence)%")
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.ink)
                }
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppTheme.sunken, in: Capsule())

                if !result.date.isEmpty {
                    Text(result.date)
                        .font(.caption.monospaced())
                        .foregroundStyle(AppTheme.secondaryInk)
                }

                if let loc = result.location, !loc.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                        Text(loc)
                    }
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
                }

                Spacer()

                if let msg = viewModel.copyFeedbackMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(AppTheme.success)
                }

                Button {
                    viewModel.copyResearchOutput()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .controlSize(.small)

                Button {
                    viewModel.openInPipeline()
                } label: {
                    Label("Open in Pipeline", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            // Key Findings & Grounded Notes Card
            VStack(alignment: .leading, spacing: 12) {
                Text("Key Findings & Grounded Notes")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)

                if result.notes.isEmpty {
                    Text("No structured notes returned.")
                        .font(.callout)
                        .foregroundStyle(AppTheme.secondaryInk)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(result.notes.enumerated()), id: \.offset) { _, note in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .padding(.top, 7)
                                    .foregroundStyle(AppTheme.accent)
                                Text(note)
                                    .font(.body)
                                    .foregroundStyle(AppTheme.ink)
                            }
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.line, lineWidth: 1))

            // People Mentioned
            if !result.people.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("People & Entities Mentioned")
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(AppTheme.secondaryInk)

                    HStack(spacing: 8) {
                        ForEach(result.people, id: \.self) { person in
                            HStack(spacing: 4) {
                                Image(systemName: "person.fill").font(.caption2)
                                Text(person).font(.callout)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AppTheme.sunken, in: Capsule())
                            .foregroundStyle(AppTheme.ink)
                        }
                    }
                }
            }

            // Hashtags
            if !result.hashtags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Relevant Hashtags")
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(AppTheme.secondaryInk)

                    HStack(spacing: 8) {
                        ForEach(result.hashtags, id: \.self) { tag in
                            let formatted = tag.hasPrefix("#") ? tag : "#\(tag)"
                            Text(formatted)
                                .font(.callout)
                                .foregroundStyle(AppTheme.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }

            // Raw Output Disclosure
            DisclosureGroup("Raw Agent Output") {
                Text(result.rawOutput)
                    .font(.caption.monospaced())
                    .foregroundStyle(AppTheme.secondaryInk)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 8)
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(AppTheme.secondaryInk)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "newspaper.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.secondaryInk.opacity(0.6))
            Text("News Researcher")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.ink)
            Text("Browse news headlines by subgroup or trending hashtags from the left sidebar, or type a custom topic. Click Run Research to fact-check the story and generate grounded intelligence.")
                .font(.callout)
                .foregroundStyle(AppTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }
}
