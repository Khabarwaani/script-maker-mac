import Foundation

enum PipelineInstructionComposer {
    static let instructionKeys = ["human_instruction", "custom_instructions", "userInstruction", "instruction"]

    static func preparedStep(_ step: AgentPipelineStep, schema: AgentInputSchema,
                             master: String, polish: String) -> AgentPipelineStep {
        var prepared = step
        let key: String
        if schema.properties["human_instruction"] != nil { key = "human_instruction" }
        else if schema.properties["custom_instructions"] != nil { key = "custom_instructions" }
        else if schema.properties["userInstruction"] != nil { key = "userInstruction" }
        else if step.agentID == "ScriptRefiner", schema.properties["instruction"] != nil { key = "instruction" }
        else { return prepared }

        let stageKeys = key == "human_instruction" ? ["custom_instructions", "human_instruction"] : [key]
        let stageParts = stageKeys.compactMap { candidate -> String? in
            let field = step.draft.fields[candidate]
            guard field?.included == true, let text = field?.text.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return text
        }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let stage = stageParts.joined(separator: "\n\n")
        let sections = [
            step.agentID == "ScriptChat" && !polish.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Default script polish guidance (lowest priority):\n\(polish)" : nil,
            !master.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Pipeline master instruction:\n\(master)" : nil,
            !stage.isEmpty ? "Stage-specific instruction (overrides conflicting master guidance):\n\(stage)" : nil
        ].compactMap { $0 }
        guard !sections.isEmpty else { return prepared }
        prepared.draft.fields[key]?.text = sections.joined(separator: "\n\n")
        prepared.draft.fields[key]?.included = true
        if key == "human_instruction" { prepared.draft.fields["custom_instructions"]?.included = false }
        return prepared
    }

    static func effectiveInstruction(_ step: AgentPipelineStep, schema: AgentInputSchema,
                                     master: String, polish: String) -> String {
        let prepared = preparedStep(step, schema: schema, master: master, polish: polish)
        return instructionKeys.compactMap { key -> String? in
            guard prepared.draft.fields[key]?.included == true else { return nil }
            return prepared.draft.fields[key]?.text
        }.first ?? ""
    }
}

protocol AgentPipelineExecuting: Sendable {
    func execute(step: AgentPipelineStep, definition: LocalAgentDefinition, model: String) async throws -> LocalAgentResult
}

struct PipelineExecutionService: AgentPipelineExecuting {
    let runner: any LocalAgentRunning
    func execute(step: AgentPipelineStep, definition: LocalAgentDefinition, model: String) async throws -> LocalAgentResult {
        guard definition.agentID == step.agentID, definition.version == step.version,
              definition.isExecutable, definition.supports(step.provider) else {
            throw LocalAgentError.invalidInput("The selected agent version or provider is not executable.")
        }
        guard let value = try step.draft.value(schema: definition.schema, required: true) else {
            throw LocalAgentError.invalidInput("Incomplete inputs for \(definition.name).")
        }
        try definition.schema.validate(value)
        try Task.checkCancellation()
        let override = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await runner.run(LocalAgentRequest(agentID: step.agentID, version: step.version,
            inputJSON: value.json(), provider: step.provider, executable: step.provider.executable,
            model: override.isEmpty ? nil : override, thinkingEffort: step.thinkingEffort))
    }
}

protocol PipelineStoryMapping: Sendable {
    func story(from steps: [AgentPipelineStep]) throws -> Story
}

struct PipelineStoryMapper: PipelineStoryMapping {
    func story(from steps: [AgentPipelineStep]) throws -> Story {
        // Find best candidate step
        guard let storyStep = steps.last(where: {
            $0.status == .completed && ($0.agentID == "ThreeSceneStoryCreator" || $0.agentID == "TwoSceneStoryCreator" || $0.agentID == "ScriptChat" || $0.agentID == "ScriptRefiner")
        }) else {
            throw LocalAgentError.invalidInput("No completed story found to save to Library.")
        }

        let raw = storyStep.result?.text.isEmpty == false ? (storyStep.result?.text ?? "") : storyStep.rawOutput
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LocalAgentError.invalidOutput(raw: raw, reason: "Could not parse story output to save to Library.")
        }

        var title = "Pipeline Generated Story"
        var scriptText = ""
        var summary = ""
        var hashtags: [String] = []

        for step in steps.reversed() where step.status == .completed {
            guard let text = step.result?.text.data(using: .utf8),
                  let output = try? JSONSerialization.jsonObject(with: text) as? [String: Any],
                  let items = output["items"] as? [[String: Any]],
                  let storyTitle = items.first?["title"] as? String,
                  !StringFormatting.isBlank(storyTitle) else { continue }
            title = storyTitle
            break
        }

        if let items = json["items"] as? [[String: Any]], let first = items.first {
            title = first["title"] as? String ?? title
            summary = "Generated through Pipeline flow from \(steps.first?.agentName ?? "Pipeline")."
            var lines = ["Title: \(title)", ""]
            if let scenes = first["scenes"] as? [[String: Any]] {
                for (i, sc) in scenes.enumerated() {
                    let sTitle = sc["title"] as? String ?? "Scene \(i + 1)"
                    let sGoal = sc["goal"] as? String ?? ""
                    let sLoc = sc["location"] as? String ?? ""
                    lines.append("--- Scene \(i + 1): \(sTitle) (\(sGoal)) - \(sLoc) ---")
                    if let dialogues = sc["dialogues"] as? [[String: Any]] {
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
        } else if let script = json["latestScript"] as? String ?? json["script"] as? String {
            scriptText = script
            if let titleLine = script.split(separator: "\n").first,
               titleLine.hasPrefix("Title:") {
                let scriptTitle = titleLine.dropFirst("Title:".count).trimmingCharacters(in: .whitespaces)
                if !scriptTitle.isEmpty { title = scriptTitle }
            }
            summary = "Refined script from \(storyStep.agentName)."
        }

        // Gather any hashtags from earlier steps (e.g. NewsResearcher)
        for s in steps {
            if let r = s.result, let d = r.text.data(using: .utf8),
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let tags = j["hashtags"] as? [String] {
                hashtags.append(contentsOf: tags)
            }
        }

        return Story(
            id: UUID().uuidString,
            title: title,
            summary: summary,
            headline: title,
            createdAt: DateFormatting.iso8601Now(),
            status: "completed",
            hashtags: hashtags.isEmpty ? nil : Array(Set(hashtags)),
            scriptText: scriptText.isEmpty ? raw : scriptText
        )

    }
}
