import Foundation

/// Concrete resolver providing predefined workflow presets, smart semantic transitions, and input mappings.
struct LocalPipelineFlowResolver: PipelineFlowResolving {
    init() {}

    func availablePresets() -> [PipelinePresetTemplate] {
        [
            PipelinePresetTemplate(
                id: "full-viral-story",
                name: "Complete Viral Story Flow",
                description: "Studio News → News Researcher → Grounded Joke Generator → 3-Scene Story Creator → Script Chat refinement.",
                icon: "sparkles.rectangle.stack",
                stageAgentIDs: ["NewsResearcher", "GroundedJokeGenerator", "ThreeSceneStoryCreator", "ScriptChat"],
                supportsStudioNews: true
            ),
            PipelinePresetTemplate(
                id: "news-to-story",
                name: "Direct News to 3-Scene Script",
                description: "Studio News → Fact-check news with News Researcher → Generate 3-Scene viral story directly.",
                icon: "newspaper",
                stageAgentIDs: ["NewsResearcher", "ThreeSceneStoryCreator"],
                supportsStudioNews: true
            ),
            PipelinePresetTemplate(
                id: "grounded-satire",
                name: "Grounded Satire Jokes Flow",
                description: "Studio News → Research news topic → Generate grounded satirical joke variations across durations.",
                icon: "quote.bubble",
                stageAgentIDs: ["NewsResearcher", "GroundedJokeGenerator"],
                supportsStudioNews: true
            ),
            PipelinePresetTemplate(
                id: "joke-to-story",
                name: "Quick Joke to 3-Scene Story",
                description: "Generate grounded jokes across durations → Weave selected joke punchline into Scene 3.",
                icon: "theatermasks",
                stageAgentIDs: ["GroundedJokeGenerator", "ThreeSceneStoryCreator"],
                supportsStudioNews: false
            ),
            PipelinePresetTemplate(
                id: "script-refinement",
                name: "Story & ScriptChat Polish",
                description: "Generate 3-Scene story → Polish spoken dialogues and punchlines with ScriptChat.",
                icon: "text.badge.checkmark",
                stageAgentIDs: ["ThreeSceneStoryCreator", "ScriptChat"],
                supportsStudioNews: false
            )
        ]
    }

    func compatibleTransitions(
        from step: AgentPipelineStep,
        catalog: [LocalAgentDefinition]
    ) async -> [PipelineTransitionOption] {
        guard step.status == .completed, let result = step.result else { return [] }
        var options: [PipelineTransitionOption] = []
        let raw = result.text.isEmpty ? result.rawOutput : result.text
        let parsed = parseJSON(raw)

        switch step.agentID {
        case "NewsResearcher":
            // 1. GroundedJokeGenerator
            if let target = catalog.first(where: { $0.agentID == "GroundedJokeGenerator" && $0.isExecutable }) {
                let mapped = await mapNewsResearcherToGroundedJoke(sourceStep: step, parsed: parsed, target: target)
                options.append(PipelineTransitionOption(
                    id: "news-to-grounded-joke",
                    targetAgentID: target.agentID,
                    targetAgentName: target.name,
                    title: "Grounded Joke Generator",
                    description: "Generate punchy satirical joke concepts across durations (10s, 20s) from verified facts.",
                    badge: "Recommended",
                    mappedDraft: mapped
                ))
            }
            // 2. ThreeSceneStoryCreator
            if let target = catalog.first(where: { $0.agentID == "ThreeSceneStoryCreator" && $0.isExecutable }) {
                let mapped = await mapNewsResearcherToStoryCreator(sourceStep: step, parsed: parsed, target: target)
                options.append(PipelineTransitionOption(
                    id: "news-to-story-creator",
                    targetAgentID: target.agentID,
                    targetAgentName: target.name,
                    title: "3-Scene Story Creator",
                    description: "Directly create a viral 3-scene story package (Curiosity → Continuity → Reaction) from news.",
                    badge: nil,
                    mappedDraft: mapped
                ))
            }

        case "GroundedJokeGenerator", "ShekharJokeGenerator":
            // -> ThreeSceneStoryCreator
            if let target = catalog.first(where: { $0.agentID == "ThreeSceneStoryCreator" && $0.isExecutable }) {
                let (mapped, summaries) = await mapJokesToStoryCreator(sourceStep: step, parsed: parsed, target: target, variationIndex: step.selectedVariationIndex)
                options.append(PipelineTransitionOption(
                    id: "joke-to-story-creator",
                    targetAgentID: target.agentID,
                    targetAgentName: target.name,
                    title: "3-Scene Story Creator",
                    description: "Weave the generated joke punchline into Scene 3 of a 3-scene viral story.",
                    badge: "Recommended",
                    mappedDraft: mapped,
                    variationSummaries: summaries
                ))
            }

        case "ThreeSceneStoryCreator":
            // -> ScriptChat
            if let target = catalog.first(where: { ($0.agentID == "ScriptChat" || $0.agentID == "ScriptRefiner") && $0.isExecutable }) {
                let mapped = await mapStoryCreatorToScriptChat(parsed: parsed, target: target)
                options.append(PipelineTransitionOption(
                    id: "story-to-script-chat",
                    targetAgentID: target.agentID,
                    targetAgentName: target.name,
                    title: "Script Chat & Refinement",
                    description: "Refine dialogue pacing, humor, punchline delivery, or character voices.",
                    badge: "Recommended",
                    mappedDraft: mapped
                ))
            }

        case "ScriptChat", "ScriptRefiner":
            // -> Loop back to ScriptChat
            if let target = catalog.first(where: { ($0.agentID == "ScriptChat" || $0.agentID == "ScriptRefiner") && $0.isExecutable }) {
                let mapped = await mapScriptChatLoop(parsed: parsed, target: target)
                options.append(PipelineTransitionOption(
                    id: "script-chat-loop",
                    targetAgentID: target.agentID,
                    targetAgentName: target.name,
                    title: "Continue Refining Script",
                    description: "Apply additional instructions to the latest refined script.",
                    badge: "Loop",
                    mappedDraft: mapped
                ))
            }

        default:
            break
        }

        return options
    }

    func mapOutput(
        from sourceStep: AgentPipelineStep,
        to targetDefinition: LocalAgentDefinition,
        variationIndex: Int
    ) async -> AgentInputDraft {
        let raw = sourceStep.result?.text.isEmpty == false ? (sourceStep.result?.text ?? "") : sourceStep.rawOutput
        let parsed = parseJSON(raw)

        switch (sourceStep.agentID, targetDefinition.agentID) {
        case ("NewsResearcher", "GroundedJokeGenerator"):
            return await mapNewsResearcherToGroundedJoke(sourceStep: sourceStep, parsed: parsed, target: targetDefinition)
        case ("NewsResearcher", "ThreeSceneStoryCreator"):
            return await mapNewsResearcherToStoryCreator(sourceStep: sourceStep, parsed: parsed, target: targetDefinition)
        case ("GroundedJokeGenerator", "ThreeSceneStoryCreator"), ("ShekharJokeGenerator", "ThreeSceneStoryCreator"):
            let (mapped, _) = await mapJokesToStoryCreator(sourceStep: sourceStep, parsed: parsed, target: targetDefinition, variationIndex: variationIndex)
            return mapped
        case ("ThreeSceneStoryCreator", "ScriptChat"), ("ThreeSceneStoryCreator", "ScriptRefiner"):
            return await mapStoryCreatorToScriptChat(parsed: parsed, target: targetDefinition)
        case ("ScriptChat", "ScriptChat"), ("ScriptRefiner", "ScriptChat"), ("ScriptChat", "ScriptRefiner"):
            return await mapScriptChatLoop(parsed: parsed, target: targetDefinition)
        default:
            return mapGenericJSON(parsed: parsed, target: targetDefinition)
        }
    }

    // MARK: - Semantic Mappings

    private func mapNewsResearcherToGroundedJoke(
        sourceStep: AgentPipelineStep,
        parsed: [String: Any],
        target: LocalAgentDefinition
    ) async -> AgentInputDraft {
        var fields: [String: AgentJSON] = [:]

        // Topic: fallback to input topic if output lacks one
        let sourceTopic = (parsed["topic"] as? String) ?? sourceStep.draft.fields["topic"]?.text ?? ""
        if !sourceTopic.isEmpty {
            fields["topic"] = .string(sourceTopic)
        }

        // Notes: array of findings joined into multiline text
        var notesText = ""
        if let notesArray = parsed["notes"] as? [String] {
            notesText = notesArray.joined(separator: "\n• ")
            if !notesText.isEmpty { notesText = "• " + notesText }
        } else if let notesStr = parsed["notes"] as? String {
            notesText = notesStr
        }
        if !notesText.isEmpty {
            fields["notes"] = .string(notesText)
        }

        // Date
        if let dateStr = parsed["date"] as? String, !dateStr.isEmpty {
            fields["date"] = .string(dateStr)
        }

        // Location
        if let locDict = parsed["location"] as? [String: Any] {
            let parts = [locDict["city"] as? String, locDict["state"] as? String, locDict["country"] as? String]
                .compactMap { $0 }.filter { !$0.isEmpty }
            if !parts.isEmpty { fields["location"] = .string(parts.joined(separator: ", ")) }
        } else if let locStr = parsed["location"] as? String, !locStr.isEmpty {
            fields["location"] = .string(locStr)
        }

        // People
        if let people = parsed["people"] as? [String] {
            fields["people"] = .array(people.map { .string($0) })
        }

        // Hashtags
        if let hashtags = parsed["hashtags"] as? [String] {
            fields["hashtags"] = .array(hashtags.map { .string($0) })
        }

        // Default durations and concept count
        fields["target_durations"] = .array([.number(10), .number(20)])
        fields["concept_count"] = .number(3)

        return AgentInputDraft(schema: target.schema, required: true, value: .object(fields))
    }

    private func mapNewsResearcherToStoryCreator(
        sourceStep: AgentPipelineStep,
        parsed: [String: Any],
        target: LocalAgentDefinition
    ) async -> AgentInputDraft {
        var fields: [String: AgentJSON] = [:]

        let sourceTopic = (parsed["topic"] as? String) ?? sourceStep.draft.fields["topic"]?.text ?? ""
        var newsPieces: [String] = []
        if !sourceTopic.isEmpty {
            newsPieces.append("Headline / Topic: \(sourceTopic)")
        }

        if let notesArray = parsed["notes"] as? [String], !notesArray.isEmpty {
            newsPieces.append("Verified Facts:\n• " + notesArray.joined(separator: "\n• "))
        } else if let notesStr = parsed["notes"] as? String, !notesStr.isEmpty {
            newsPieces.append("Verified Facts:\n\(notesStr)")
        }

        if let dateStr = parsed["date"] as? String, !dateStr.isEmpty {
            newsPieces.append("Date: \(dateStr)")
        }

        if let people = parsed["people"] as? [String], !people.isEmpty {
            newsPieces.append("People Involved: \(people.joined(separator: ", "))")
        }

        fields["news"] = .string(newsPieces.joined(separator: "\n\n"))
        fields["output_count"] = .number(1)

        return AgentInputDraft(schema: target.schema, required: true, value: .object(fields))
    }

    private func mapJokesToStoryCreator(
        sourceStep: AgentPipelineStep,
        parsed: [String: Any],
        target: LocalAgentDefinition,
        variationIndex: Int
    ) async -> (AgentInputDraft, [String]) {
        var fields: [String: AgentJSON] = [:]
        var summaries: [String] = []

        // News facts from GroundedJokeGenerator
        let newsContent = (parsed["news_content"] as? String) ?? (parsed["newsContent"] as? String) ?? ""
        let topic = (parsed["topic"] as? String) ?? sourceStep.draft.fields["topic"]?.text ?? ""
        let combinedNews = newsContent.isEmpty ? topic : (topic.isEmpty ? newsContent : "\(topic)\n\n\(newsContent)")
        if !combinedNews.isEmpty {
            fields["news"] = .string(combinedNews)
        }

        // Extract joke candidates from joke concepts
        if let jokeConcepts = parsed["jokes"] as? [[String: Any]] {
            for concept in jokeConcepts {
                if let variations = concept["variations"] as? [[String: Any]] {
                    for v in variations {
                        if let content = v["content"] as? String, !content.isEmpty {
                            let dur = v["duration"] as? Int ?? 0
                            let label = dur > 0 ? "[\(dur)s] \(content)" : content
                            summaries.append(label)
                        }
                    }
                } else if let content = concept["content"] as? String {
                    summaries.append(content)
                }
            }
        }

        // Select chosen joke
        if !summaries.isEmpty {
            let index = max(0, min(variationIndex, summaries.count - 1))
            let selectedJoke = summaries[index]
            // Strip duration tag like [10s] if present
            let cleanedJoke = selectedJoke.replacingOccurrences(of: #"^\[\d+s\]\s*"#, with: "", options: .regularExpression)
            fields["user_joke"] = .string(cleanedJoke)
        }

        fields["output_count"] = .number(1)
        return (AgentInputDraft(schema: target.schema, required: true, value: .object(fields)), summaries)
    }

    private func mapStoryCreatorToScriptChat(
        parsed: [String: Any],
        target: LocalAgentDefinition
    ) async -> AgentInputDraft {
        var fields: [String: AgentJSON] = [:]
        var scriptText = ""

        if let items = parsed["items"] as? [[String: Any]], let firstStory = items.first {
            let title = firstStory["title"] as? String ?? "Untitled Story"
            var lines = ["Title: \(title)", ""]

            if let scenes = firstStory["scenes"] as? [[String: Any]] {
                for (idx, scene) in scenes.enumerated() {
                    let sTitle = scene["title"] as? String ?? "Scene \(idx + 1)"
                    let sGoal = scene["goal"] as? String ?? ""
                    let sLoc = scene["location"] as? String ?? ""
                    lines.append("--- Scene \(idx + 1): \(sTitle) (\(sGoal)) - \(sLoc) ---")

                    if let dialogues = scene["dialogues"] as? [[String: Any]] {
                        for d in dialogues {
                            let spk = d["speaker"] as? String ?? "Speaker"
                            let txt = d["dialogue"] as? String ?? ""
                            lines.append("\(spk): \(txt)")
                        }
                    }
                    lines.append("")
                }
            }
            scriptText = lines.joined(separator: "\n")
        }

        if scriptText.isEmpty {
            scriptText = parsed["script"] as? String ?? ""
        }

        fields["originalScript"] = .string(scriptText)
        fields["latestScript"] = .string(scriptText)
        fields["userInstruction"] = .string("")

        return AgentInputDraft(schema: target.schema, required: true, value: .object(fields))
    }

    private func mapScriptChatLoop(
        parsed: [String: Any],
        target: LocalAgentDefinition
    ) async -> AgentInputDraft {
        var fields: [String: AgentJSON] = [:]
        let latest = (parsed["latestScript"] as? String) ?? (parsed["script"] as? String) ?? ""
        fields["originalScript"] = .string(latest)
        fields["latestScript"] = .string(latest)
        fields["userInstruction"] = .string("")
        return AgentInputDraft(schema: target.schema, required: true, value: .object(fields))
    }

    private func mapGenericJSON(
        parsed: [String: Any],
        target: LocalAgentDefinition
    ) -> AgentInputDraft {
        var fields: [String: AgentJSON] = [:]
        for (key, schema) in target.schema.properties {
            if let val = parsed[key] {
                if let s = val as? String { fields[key] = .string(s) }
                else if let n = val as? NSNumber { fields[key] = schema.kind == "boolean" ? .bool(n.boolValue) : .number(n.doubleValue) }
                else if let arr = val as? [String] { fields[key] = .array(arr.map { .string($0) }) }
            }
        }
        return AgentInputDraft(schema: target.schema, required: true, value: .object(fields))
    }

    private func parseJSON(_ text: String) -> [String: Any] {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }
}
