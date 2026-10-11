import Foundation

/// Offline WebClient. Returns bundled sample JSON — no network.
/// Used when AppConfig.dataSource == .offline (the default).
struct OfflineWebClient: WebClient {
    let delay: TimeInterval

    init(delay: TimeInterval = 0) { self.delay = min(max(delay, 0), 60) }

    private func pause() async throws {
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
    }

    func ping() async -> Bool {
        do { try await pause(); return true } catch { return false }
    }

    func fetchData(from url: URL) async throws -> Data {
        // Offline mode: no network fetches. Caller shows placeholder.
        throw APIError.notImplemented("Image fetch unavailable offline")
    }

    func createSession() async throws -> String {
        try await pause()
        return "sample-" + UUID().uuidString
    }

    func runStage(sessionID: String, stage: PipelineStage, inputs: [String: Any]) async throws -> [String: Any] {
        try await pause()
        guard var sample = SampleData.json(for: stage.rawValue) else {
            throw APIError.notImplemented("sample data for stage \(stage.rawValue)")
        }
        // Expand the fixture to exercise the requested story count without generation work.
        let key = stage == .dialogue ? "scripts" : stage == .storyboard ? "storyboards" : nil
        if let key, let templates = sample[key] as? [[String: Any]], !templates.isEmpty {
            let count = max(inputs["script_count"] as? Int ?? templates.count, 1)
            sample[key] = (0..<count).map { index in
                var item = templates[index % templates.count]
                let title = item["title"] as? String ?? "Sample story"
                if index >= templates.count { item["title"] = "\(title) — Sample \(index + 1)" }
                return item
            }
        }
        return sample
    }

    func select(sessionID: String, selection: [String: Any]) async throws -> [String: Any] {
        try await pause()
        return [:]
    }

    func listStories() async throws -> [[String: Any]] {
        try await pause()
        return []
    }

    func startJob(sessionID: String, stage: PipelineJob, inputs: [String: Any]) async throws -> String {
        try await pause()
        return "sample-job"
    }

    func jobStatus(jobID: String) async throws -> JobStatus {
        try await pause()
        return JobStatus(status: "done", progress: 1.0, detail: "Sample render complete.")
    }

    func pollJob(jobID: String, interval: TimeInterval) -> AsyncThrowingStream<JobStatus, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await pause()
                    continuation.yield(JobStatus(status: "done", progress: 1.0, detail: "Sample render complete."))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func eventStream(sessionID: String) -> AsyncThrowingStream<SubstepEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(SubstepEvent(name: "verify", stage: "verify", label: "Verifying", status: "running", detail: "Sample: verifying facts…"))
            continuation.yield(SubstepEvent(name: "verify", stage: "verify", label: "Verifying", status: "done", detail: "Sample: 4 facts verified."))
            continuation.finish()
        }
    }

    func fetchNewsCategories() async throws -> NewsCategoriesResponse {
        try await pause()
        if let data = SampleData.data(for: "news_categories"),
           let response = try? JSONDecoder().decode(NewsCategoriesResponse.self, from: data) {
            return response
        }
        return NewsCategoriesResponse(
            categories: [
                NewsCategory(id: "trending", label: "🔥 India Trending & Viral"),
                NewsCategory(id: "india", label: "🇮🇳 India Top Stories & Breaking"),
                NewsCategory(id: "funny_india", label: "😂 Desi Quirky, Jugaad & Funny India"),
                NewsCategory(id: "proud_india", label: "🏆 Proud India"),
                NewsCategory(id: "emotional", label: "❤️ Emotional India"),
                NewsCategory(id: "politics", label: "🏛️ Indian Politics, Elections & Governance"),
                NewsCategory(id: "culture", label: "🪔 Indian Culture, Heritage & Festivals"),
                NewsCategory(id: "india_tech", label: "🚀 India Tech, Space (ISRO) & Startups"),
                NewsCategory(id: "tech", label: "💻 Technology & AI"),
                NewsCategory(id: "world", label: "🌍 World News"),
                NewsCategory(id: "business", label: "📈 Business & Economy")
            ],
            defaultCategory: "trending"
        )
    }

    func fetchTopTitles(category: String?, n: Int?, mode: String?) async throws -> TopTitlesResponse {
        try await pause()
        if let data = SampleData.data(for: "headlines"),
           let decoded = try? JSONDecoder().decode(TopTitlesResponse.self, from: data) {
            let requestedCount = n ?? decoded.titles.count
            let titles = Array(decoded.titles.prefix(max(1, requestedCount)))
            return TopTitlesResponse(
                category: category ?? decoded.category,
                label: decoded.label,
                n: titles.count,
                mode: mode ?? decoded.mode,
                cached: decoded.cached,
                titles: titles
            )
        }
        let sampleList = (SampleData.json(for: "headlines")?["headlines"] as? [String]) ?? [
            "Delhi announces odd-even vehicle restrictions to combat air pollution",
            "Mumbai local trains get 12 new air-conditioned rakes",
            "ISRO successfully launches communication satellite GSAT-24"
        ]
        let requestedCount = n ?? sampleList.count
        let titles = sampleList.prefix(max(1, requestedCount)).enumerated().map { index, title in
            NewsTitle(title: title, link: "https://sample.example/articles/\(index + 1)")
        }
        return TopTitlesResponse(
            category: category ?? "india",
            label: "🇮🇳 India Top Stories & Breaking",
            n: titles.count,
            mode: mode ?? "sample",
            cached: false,
            titles: titles
        )
    }

    func fetchTrendingHashtags(n: Int? = nil) async throws -> NewsHashtagsResponse {
        try await pause()
        let tags = [
            "#AtmanirbharBharat",
            "#TNWelcomesModi",
            "#winOPPOF35",
            "#OPPOF35Series",
            "#HappyNavratri",
            "#InternationalDayOfGirlChild",
            "#JaiMataDi"
        ]
        let requestedCount = n ?? tags.count
        let items = tags.prefix(max(1, requestedCount)).map {
            NewsHashtag(tag: $0, headline: $0.replacingOccurrences(of: "#", with: ""), link: nil, source: "X")
        }
        return NewsHashtagsResponse(
            n: items.count,
            mode: "sample",
            cached: false,
            refreshedAt: Date().timeIntervalSince1970,
            hashtags: items
        )
    }

    func verifyNewsEndpoints() async throws -> Bool {
        try await pause()
        return true
    }
}

