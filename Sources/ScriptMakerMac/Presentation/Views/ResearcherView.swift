import SwiftUI

/// Clean Researcher workspace: browse news headlines / trending topics and run the NewsResearcher agent.
struct ResearcherView: View {
    @Bindable var viewModel: ResearcherViewModel

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 0) {
                sidebarView
                    .frame(width: max(360, min(420, geometry.size.width * 0.38)))
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
            VStack(alignment: .leading, spacing: 20) {
                sourceSection
                topicSection
                advancedSection
                providerSection
                actionSection
            }
            .padding(20)
        }
        .background(AppTheme.card)
        .scrollIndicators(.visible)
        .disabled(viewModel.isResearching)
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("News Source")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(AppTheme.secondaryInk)

            Picker("Source", selection: $viewModel.selectedStorySource) {
                ForEach(viewModel.storySources, id: \.self) { source in
                    Text(source).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.selectedStorySource) { _, _ in
                Task { await viewModel.onStorySourceChanged() }
            }

            if viewModel.isHashtagSource {
                hashtagControls
            } else if !viewModel.isManualSource {
                headlineControls
            }
        }
    }

    private var headlineControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Headline")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                if viewModel.isRefreshingHeadlines {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await viewModel.refreshHeadlines(forceFresh: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh headlines")
                .disabled(viewModel.isRefreshingHeadlines)
            }

            if viewModel.headlines.isEmpty {
                if let err = viewModel.headlinesErrorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(AppTheme.danger)
                } else {
                    Text("No headlines loaded")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
            } else {
                Picker("Headline", selection: $viewModel.selectedHeadline) {
                    ForEach(viewModel.headlines, id: \.self) { headline in
                        Text(headline).tag(headline)
                    }
                }
                .labelsHidden()
                .onChange(of: viewModel.selectedHeadline) { _, new in
                    viewModel.onHeadlineChanged(new)
                }
            }
        }
        .padding(.top, 4)
    }

    private var hashtagControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Trending Hashtag")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                if viewModel.isRefreshingHashtags {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await viewModel.refreshHashtags(forceFresh: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh hashtags")
                .disabled(viewModel.isRefreshingHashtags)
            }

            if viewModel.trendingHashtags.isEmpty {
                if let err = viewModel.hashtagsErrorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(AppTheme.danger)
                } else {
                    Text("No hashtags loaded")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
            } else {
                Picker("Hashtag", selection: $viewModel.selectedHashtag) {
                    Text("Select a hashtag…").tag("")
                    ForEach(viewModel.trendingHashtags, id: \.tag) { tag in
                        Text(tag.tag).tag(tag.tag)
                    }
                }
                .labelsHidden()
                .onChange(of: viewModel.selectedHashtag) { _, new in
                    viewModel.onHashtagChanged(new)
                }
            }

            TextField("Or custom hashtag (e.g. #ISRO)", text: $viewModel.customHashtag)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if !viewModel.customHashtag.isEmpty {
                        viewModel.onHashtagChanged(viewModel.customHashtag)
                    }
                }
        }
        .padding(.top, 4)
    }

    private var topicSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Research Topic")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(AppTheme.secondaryInk)

            TextEditor(text: $viewModel.topic)
                .font(.body)
                .frame(minHeight: 80, maxHeight: 120)
                .padding(6)
                .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.line, lineWidth: 1))
        }
    }

    private var advancedSection: some View {
        DisclosureGroup("Advanced Options") {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Authoritative Source URL").font(.caption).foregroundStyle(AppTheme.secondaryInk)
                    TextField("https://example.com/article", text: $viewModel.sourceURL)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Human Instruction").font(.caption).foregroundStyle(AppTheme.secondaryInk)
                    TextField("e.g. Focus on economic impact", text: $viewModel.humanInstruction)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Language").font(.caption).foregroundStyle(AppTheme.secondaryInk)
                    TextField("English", text: $viewModel.language)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(.top, 6)
        }
        .font(.callout.weight(.medium))
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agent Provider")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(AppTheme.secondaryInk)

            Picker("Provider", selection: $viewModel.selectedProvider) {
                ForEach(LocalAgentProvider.allCases, id: \.self) { provider in
                    let avail = viewModel.availableProviders[provider]
                    let suffix = (avail?.isAvailable == true) ? "" : " (Unavailable)"
                    Text(provider.title + suffix).tag(provider)
                }
            }
            .labelsHidden()

            TextField("Custom model override (optional)", text: $viewModel.customModel)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
        }
    }

    private var actionSection: some View {
        VStack(spacing: 10) {
            Button {
                Task { await viewModel.runResearch() }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isResearching {
                        ProgressView().controlSize(.small)
                        Text("Researching…")
                    } else {
                        Image(systemName: "sparkle.magnifyingglass")
                        Text("Run Research")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canRunResearch)
        }
        .padding(.top, 4)
    }

    // MARK: - Right Detail Area: Research Output

    private var detailAreaView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
        .padding(12)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.danger.opacity(0.3), lineWidth: 1))
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
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private func resultView(_ result: NewsResearchResult) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            // Top Bar: Verification Badge, Confidence, Date, Location
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: result.verified ? "checkmark.seal.fill" : "xmark.seal.fill")
                    Text(result.verified ? "Verified" : "Unverified / False")
                        .fontWeight(.semibold)
                }
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
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
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
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

                // Actions
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

            // Key Findings / Notes Card
            VStack(alignment: .leading, spacing: 10) {
                Text("Key Findings & Grounded Notes")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)

                if result.notes.isEmpty {
                    Text("No structured notes returned.")
                        .font(.callout)
                        .foregroundStyle(AppTheme.secondaryInk)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(result.notes.enumerated()), id: \.offset) { _, note in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .padding(.top, 6)
                                    .foregroundStyle(AppTheme.accent)
                                Text(note)
                                    .font(.body)
                                    .foregroundStyle(AppTheme.ink)
                            }
                        }
                    }
                }
            }
            .padding(16)
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
                            .padding(.vertical, 4)
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
                                .padding(.vertical, 3)
                                .background(AppTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }

            // Raw Output Disclosure
            DisclosureGroup("Raw Agent Output") {
                Text(result.rawOutput)
                    .font(.caption.monospaced())
                    .foregroundStyle(AppTheme.secondaryInk)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.sunken, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 6)
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(AppTheme.secondaryInk)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "newspaper.fill")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.secondaryInk.opacity(0.6))
            Text("News Researcher")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.ink)
            Text("Browse news headlines or trending hashtags from the left sidebar, or type a custom topic. Click Run Research to fact-check the story and generate grounded intelligence.")
                .font(.callout)
                .foregroundStyle(AppTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity, minHeight: 340)
    }
}
