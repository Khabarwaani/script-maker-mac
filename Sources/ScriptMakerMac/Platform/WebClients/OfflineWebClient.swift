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

    // MARK: - Generic Transport

    func get<T: Decodable & Sendable>(path: String, queryItems: [URLQueryItem]? = nil) async throws -> T {
        try await pause()
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if cleanPath == "api/v1/news/category" {
            if let data = SampleData.data(for: "news_categories"),
               let decoded = try? JSONDecoder().decode(T.self, from: data) {
                return decoded
            }
            let fallback = NewsCategoriesResponse(
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
            let encoded = try JSONEncoder().encode(fallback)
            return try JSONDecoder().decode(T.self, from: encoded)
        }

        if cleanPath == "api/v1/news/title" {
            let category = queryItems?.first(where: { $0.name == "category" })?.value
            let mode = queryItems?.first(where: { $0.name == "mode" })?.value
            let nCount = queryItems?.first(where: { $0.name == "n" })?.value.flatMap(Int.init)

            if let data = SampleData.data(for: "headlines"),
               let decoded = try? JSONDecoder().decode(TopTitlesResponse.self, from: data) {
                let requestedCount = nCount ?? decoded.titles.count
                let titles = Array(decoded.titles.prefix(max(1, requestedCount)))
                let response = TopTitlesResponse(
                    category: category ?? decoded.category,
                    label: decoded.label,
                    n: titles.count,
                    mode: mode ?? decoded.mode,
                    cached: decoded.cached,
                    titles: titles
                )
                let encoded = try JSONEncoder().encode(response)
                return try JSONDecoder().decode(T.self, from: encoded)
            }
            let sampleList = (SampleData.json(for: "headlines")?["headlines"] as? [String]) ?? [
                "Delhi announces odd-even vehicle restrictions to combat air pollution",
                "Mumbai local trains get 12 new air-conditioned rakes",
                "ISRO successfully launches communication satellite GSAT-24"
            ]
            let requestedCount = nCount ?? sampleList.count
            let titles = sampleList.prefix(max(1, requestedCount)).enumerated().map { index, title in
                NewsTitle(title: title, link: "https://sample.example/articles/\(index + 1)")
            }
            let response = TopTitlesResponse(
                category: category ?? "india",
                label: "🇮🇳 India Top Stories & Breaking",
                n: titles.count,
                mode: mode ?? "sample",
                cached: false,
                titles: titles
            )
            let encoded = try JSONEncoder().encode(response)
            return try JSONDecoder().decode(T.self, from: encoded)
        }

        if cleanPath == "api/v1/news/hashtags" {
            let nCount = queryItems?.first(where: { $0.name == "n" })?.value.flatMap(Int.init)
            let tags = [
                "#AtmanirbharBharat",
                "#TNWelcomesModi",
                "#winOPPOF35",
                "#OPPOF35Series",
                "#HappyNavratri",
                "#InternationalDayOfGirlChild",
                "#JaiMataDi"
            ]
            let requestedCount = nCount ?? tags.count
            let items = tags.prefix(max(1, requestedCount)).map {
                NewsHashtag(tag: $0, headline: $0.replacingOccurrences(of: "#", with: ""), link: nil, source: "X")
            }
            let response = NewsHashtagsResponse(
                n: items.count,
                mode: "sample",
                cached: false,
                refreshedAt: Date().timeIntervalSince1970,
                hashtags: items
            )
            let encoded = try JSONEncoder().encode(response)
            return try JSONDecoder().decode(T.self, from: encoded)
        }

        throw APIError.notImplemented("Offline sample for GET \(path)")
    }

    func post<T: Decodable & Sendable>(path: String, json: [String: Any]? = nil) async throws -> T {
        try await pause()
        throw APIError.notImplemented("Offline sample for POST \(path)")
    }

    func streamSSE(path: String, json: [String: Any]? = nil) -> AsyncThrowingStream<ServerSSEEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let stagesPlan = [
                        StreamStagePlan(id: 1, type: "validation", label: "Instruction Decomposition & Wire Fact Validation"),
                        StreamStagePlan(id: 2, type: "casting", label: "Viral Angles & Hindi Hooks"),
                        StreamStagePlan(id: 3, type: "dialogue", label: "Spoken Dialogue Writing & Word Count Calibration"),
                        StreamStagePlan(id: 4, type: "scenes", label: "Scene Derivation from Dialogue"),
                        StreamStagePlan(id: 5, type: "storyboard", label: "Scene Storyboards & Cinematic Visual Direction"),
                        StreamStagePlan(id: 6, type: "script", label: "Integration & Final Validation")
                    ]

                    let planStreamData = try JSONEncoder().encode(StreamPlanStreamPayload(version: "5.1.2", stages: stagesPlan))
                    continuation.yield(ServerSSEEvent(event: "plan_stream", data: String(data: planStreamData, encoding: .utf8) ?? "{}"))
                    try await pause()

                    for (idx, meta) in stagesPlan.enumerated() {
                        let position = idx + 1
                        let stageType = meta.type
                        let label = meta.label

                        let substeps = [
                            StreamSubstepPlan(id: "\(position).1", substepType: stageType, name: "\(label) - Step 1"),
                            StreamSubstepPlan(id: "\(position).2", substepType: stageType, name: "\(label) - Step 2")
                        ]

                        let planStageData = try JSONEncoder().encode(StreamPlanStagePayload(position: position, stageType: stageType, substeps: substeps))
                        continuation.yield(ServerSSEEvent(event: "plan_stage", data: String(data: planStageData, encoding: .utf8) ?? "{}"))

                        let progressStageData = try JSONEncoder().encode(StreamProgressStagePayload(position: position, stageType: stageType, status: "running"))
                        continuation.yield(ServerSSEEvent(event: "progress_stage", data: String(data: progressStageData, encoding: .utf8) ?? "{}"))

                        for sub in substeps {
                            let progSubData = try JSONEncoder().encode(StreamProgressSubstepPayload(position: position, substep: sub.id, substepType: stageType, status: "running"))
                            continuation.yield(ServerSSEEvent(event: "progress_substep", data: String(data: progSubData, encoding: .utf8) ?? "{}"))
                            try await pause()

                            let outSubDict: [String: Any] = [
                                "type": "output_substep",
                                "step": position,
                                "substep": sub.id,
                                "substep_type": stageType,
                                "name": sub.name,
                                "status": "success",
                                "output": ["result": "OK"]
                            ]
                            let outSubData = try JSONSerialization.data(withJSONObject: outSubDict)
                            continuation.yield(ServerSSEEvent(event: "output_substep", data: String(data: outSubData, encoding: .utf8) ?? "{}"))
                        }

                        // Load sample output for this stage
                        var stageSample = SampleData.json(for: stageType) ?? [:]
                        let key = stageType == "dialogue" ? "scripts" : stageType == "storyboard" ? "storyboards" : (stageType == "script" || stageType == "validation") ? "scripts" : nil
                        if let key, let templates = stageSample[key] as? [[String: Any]], !templates.isEmpty {
                            let count = max(json?["batch_size"] as? Int ?? templates.count, 1)
                            stageSample[key] = (0..<count).map { index in
                                var item = templates[index % templates.count]
                                let title = item["title"] as? String ?? "Sample story"
                                if index >= templates.count { item["title"] = "\(title) — Sample \(index + 1)" }
                                return item
                            }
                        }

                        let outStageDict: [String: Any] = [
                            "type": "output_stage",
                            "step": position,
                            "status": "success",
                            "output_type": stageType,
                            "output": stageSample
                        ]
                        let outStageData = try JSONSerialization.data(withJSONObject: outStageDict)
                        continuation.yield(ServerSSEEvent(event: "output_stage", data: String(data: outStageData, encoding: .utf8) ?? "{}"))
                    }

                    continuation.yield(ServerSSEEvent(event: "end", data: "{}"))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}


