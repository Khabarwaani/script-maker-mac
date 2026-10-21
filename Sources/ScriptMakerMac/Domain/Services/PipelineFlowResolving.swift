import Foundation

/// Protocol governing pipeline transitions, preset templates, and output-to-input mappings.
protocol PipelineFlowResolving: Sendable {
    /// Returns the available pipeline workflow presets.
    func availablePresets() -> [PipelinePresetTemplate]

    /// Evaluates a completed step's output to find compatible next agents and pre-populated drafts.
    func compatibleTransitions(
        from step: AgentPipelineStep,
        catalog: [LocalAgentDefinition]
    ) async -> [PipelineTransitionOption]

    /// Maps a completed step's output directly into the target agent definition's input draft.
    func mapOutput(
        from sourceStep: AgentPipelineStep,
        to targetDefinition: LocalAgentDefinition,
        variationIndex: Int
    ) async -> AgentInputDraft
}
