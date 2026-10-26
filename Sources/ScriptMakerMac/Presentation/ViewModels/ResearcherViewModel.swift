import Foundation
import Observation

/// Owns news discovery browsing and direct execution of the NewsResearcher agent.
@Observable
@MainActor
final class ResearcherViewModel {
    static let newsSourceLabel = "News"
    static let hashtagSourceLabel = "Trending Hashtags"
    static let manualSourceLabel = "Custom Topic"

    let newsProvider: any StudioNewsProviding
    let researchService: any NewsResearching
    let clipboard: any ClipboardWriting
    let config: any DiscoverySettingsProviding

    var onNavigateToPipeline: ((String, String?) -> Void)?

    var storySources: [String] = [newsSourceLabel, hashtagSourceLabel, manualSourceLabel]
    var selectedStorySource: String = newsSourceLabel

    // Two-level News Subgroups & Headlines
    var categories: [NewsCategory] = []
    var selectedCategory: String = ""
    var isRefreshingCategories: Bool = false
    var categoriesErrorMessage: String? = nil

    var headlines: [String] = []
    var selectedHeadline: String = ""
    var isRefreshingHeadlines: Bool = false
    var headlinesErrorMessage: String? = nil

    // Trending Hashtags
    var trendingHashtags: [NewsHashtag] = []
    var selectedHashtag: String = ""
    var customHashtag: String = ""
    var isRefreshingHashtags: Bool = false
    var hashtagsErrorMessage: String? = nil
    var selectedTagDetail: NewsHashtag? = nil

    // Topic & Input
    var topic: String = ""
    var sourceURL: String = ""
    var humanInstruction: String = ""
    var language: String = "English"

    // Agent Execution
    private var providerOverride: LocalAgentProvider = .codex
    private var modelOverrideValue = ""
    private let agentSelection: (any WorkspaceAgentSelecting)?
    var usesAppDefault: Bool {
        get { agentSelection?.usesAppDefault ?? false }
        set { agentSelection?.usesAppDefault = newValue }
    }
    var selectedProvider: LocalAgentProvider {
        get { agentSelection?.provider ?? providerOverride }
        set { if let agentSelection { agentSelection.provider = newValue } else { providerOverride = newValue } }
    }
    var customModel: String {
        get { agentSelection?.model ?? modelOverrideValue }
        set { if let agentSelection { agentSelection.model = newValue } else { modelOverrideValue = newValue } }
    }
    var availableProviders: [LocalAgentProvider: LocalAgentAvailability] = [:]

    var isResearching: Bool = false
    var researchResult: NewsResearchResult? = nil
    var errorMessage: String? = nil
    var copyFeedbackMessage: String? = nil

    init(
        newsProvider: any StudioNewsProviding,
        researchService: any NewsResearching,
        clipboard: any ClipboardWriting,
        config: any DiscoverySettingsProviding,
        agentSelection: (any WorkspaceAgentSelecting)? = nil
    ) {
        self.newsProvider = newsProvider
        self.researchService = researchService
        self.clipboard = clipboard
        self.config = config
        self.agentSelection = agentSelection
    }

    var isHashtagSource: Bool { selectedStorySource == Self.hashtagSourceLabel }
    var isManualSource: Bool { selectedStorySource == Self.manualSourceLabel }

    var providerNotice: String {
        if selectedProvider == .appleLocal { return "News research needs web access. Choose an installed terminal provider." }
        return availableProviders[selectedProvider]?.reason ?? "Checking provider availability…"
    }
    var canRunResearch: Bool {

        !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResearching && selectedProvider != .appleLocal && availableProviders[selectedProvider]?.isAvailable == true
    }

    var effectiveModel: String {
        customModel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Lifecycle

    func initialLoad() async {
        await refreshProviders()
        if isHashtagSource {
            await refreshHashtags(forceFresh: false)
        } else if !isManualSource {
            await loadCategories(forceFresh: false)
        }
    }

    func onStorySourceChanged() async {
        if isHashtagSource {
            await refreshHashtags(forceFresh: false)
        } else if !isManualSource {
            if categories.isEmpty {
                await loadCategories(forceFresh: false)
            } else {
                await refreshHeadlines(forceFresh: false)
            }
        } else {
            // Custom topic mode: leave topic as is or clear headline
            selectedHeadline = ""
        }
    }

    // MARK: - Two-Level News: Categories (Subgroups) & Headlines

    func loadCategories(forceFresh: Bool = false) async {
        guard !isRefreshingCategories else { return }
        isRefreshingCategories = true
        categoriesErrorMessage = nil
        defer { isRefreshingCategories = false }

        do {
            let resp = try await newsProvider.categories(location: config.newsSettings.location)
            categories = resp.categories
            if selectedCategory.isEmpty || !categories.contains(where: { $0.id == selectedCategory }) {
                if categories.contains(where: { $0.id == resp.defaultCategory }) {
                    selectedCategory = resp.defaultCategory
                } else if let first = categories.first {
                    selectedCategory = first.id
                }
            }
            await refreshHeadlines(forceFresh: forceFresh)
        } catch {
            categoriesErrorMessage = error.localizedDescription
            await refreshHeadlines(forceFresh: forceFresh)
        }
    }

    func onCategoryChanged(_ newCategory: String) async {
        guard selectedCategory != newCategory else { return }
        selectedCategory = newCategory
        await refreshHeadlines(forceFresh: false)
    }

    func refreshHeadlines(forceFresh: Bool = false) async {
        guard !isRefreshingHeadlines else { return }
        isRefreshingHeadlines = true
        headlinesErrorMessage = nil
        defer { isRefreshingHeadlines = false }

        let categoryParam = selectedCategory.isEmpty ? nil : selectedCategory
        do {
            let resp = try await newsProvider.headlines(
                category: categoryParam,
                location: config.newsSettings.location,
                limit: config.newsPageSize,
                forceFresh: forceFresh
            )
            let titles = resp.titles.map(\.title)
            headlines = titles
            if selectedHeadline.isEmpty || !headlines.contains(selectedHeadline) {
                if let first = headlines.first {
                    onHeadlineChanged(first)
                } else {
                    selectedHeadline = ""
                }
            }
        } catch {
            headlinesErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Trending Hashtags

    func refreshHashtags(forceFresh: Bool = true) async {
        guard !isRefreshingHashtags else { return }
        isRefreshingHashtags = true
        hashtagsErrorMessage = nil
        defer { isRefreshingHashtags = false }

        do {
            let resp = try await newsProvider.hashtags(limit: config.trendingSettings.resultLimit, forceFresh: forceFresh)
            trendingHashtags = resp.hashtags
            let tags = trendingHashtags.map(\.tag)
            if selectedHashtag.isEmpty || !tags.contains(selectedHashtag) {
                if let first = tags.first {
                    onHashtagChanged(first)
                }
            }
        } catch {
            hashtagsErrorMessage = error.localizedDescription
        }
    }

    func onHeadlineChanged(_ new: String) {
        selectedHeadline = new
        topic = new
    }

    func onHashtagChanged(_ new: String) {
        selectedHashtag = new
        if let found = trendingHashtags.first(where: { $0.tag == new }) {
            selectedTagDetail = found
            topic = found.headline ?? found.summary ?? found.tag
        } else if !new.isEmpty {
            topic = new
            Task { await loadHashtagDetail(for: new) }
        }
    }

    func loadHashtagDetail(for tag: String? = nil) async {
        let target = tag ?? selectedHashtag
        guard !target.isEmpty else { return }
        do {
            let detail = try await newsProvider.hashtagDetail(for: target)
            try Task.checkCancellation()
            guard selectedHashtag == target, isHashtagSource else { return }
            selectedTagDetail = detail
            if let desc = detail.headline ?? detail.summary, !desc.isEmpty {
                topic = desc
            }
        } catch {
            if !Task.isCancelled, selectedHashtag == target, isHashtagSource {
                hashtagsErrorMessage = StringFormatting.errorMessage(error)
            }
        }
    }

    // MARK: - Research Execution

    func runResearch() async {
        guard canRunResearch else { return }
        isResearching = true
        errorMessage = nil
        defer { isResearching = false }

        let request = NewsResearchRequest(
            topic: topic,
            language: language,
            sourceURL: sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : sourceURL,
            humanInstruction: humanInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : humanInstruction,
            provider: selectedProvider,
            model: effectiveModel
        )

        do {
            let result = try await researchService.research(request)
            researchResult = result
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copyResearchOutput() {
        guard let result = researchResult else { return }
        let textToCopy = formatResearchForCopy(result)
        if clipboard.write(textToCopy) {
            copyFeedbackMessage = "Research copied to clipboard"
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if copyFeedbackMessage == "Research copied to clipboard" {
                    copyFeedbackMessage = nil
                }
            }
        }
    }

    func openInPipeline() {
        guard !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let loc = researchResult?.location.flatMap { RegionGeo.resolve($0)?.name } ?? config.newsSettings.location
        onNavigateToPipeline?(topic, loc)
    }

    func refreshProviders() async {
        availableProviders = await researchService.availability()
    }

    private func formatResearchForCopy(_ result: NewsResearchResult) -> String {
        var lines: [String] = []
        lines.append("Topic: \(topic)")
        lines.append("Status: \(result.verified ? "VERIFIED" : "UNVERIFIED") (Confidence: \(result.confidence)%)")
        lines.append("Date: \(result.date)")
        if let loc = result.location { lines.append("Location: \(loc)") }
        if !result.people.isEmpty { lines.append("People: \(result.people.joined(separator: ", "))") }
        if !result.notes.isEmpty {
            lines.append("\nFindings:")
            for note in result.notes { lines.append("• \(note)") }
        }
        if !result.hashtags.isEmpty {
            lines.append("\nHashtags: " + result.hashtags.map { $0.hasPrefix("#") ? $0 : "#\($0)" }.joined(separator: " "))
        }
        return lines.joined(separator: "\n")
    }
}
