import "package:fast_immutable_collections/fast_immutable_collections.dart";

import "package:horizon/src/llm/run_result.dart";

/// Streaming events emitted by `RunAgentLlm` across an agentic turn.
///
/// A turn fires one or more LLM calls. Each call streams reasoning
/// then either content (final cycle) or tool calls (intermediate
/// cycle). Reasoning and content arrive as deltas; tool boundaries
/// are observed at end-of-cycle.
sealed class AgentEvent {
  const AgentEvent();
}

/// New reasoning chunk appended to the running reasoning buffer for
/// the current cycle.
final class AgentReasoningDelta extends AgentEvent {
  const AgentReasoningDelta(this.text);

  final String text;
}

/// New content chunk appended to the running answer for the current
/// cycle. May be retracted by [AgentTextReset] if the cycle ends in
/// tool calls.
final class AgentTextDelta extends AgentEvent {
  const AgentTextDelta(this.text);

  final String text;
}

/// The cycle ended in tool calls; any [AgentTextDelta] streamed
/// during it was intermediate narration, not the answer. Consumers
/// should drop it.
final class AgentTextReset extends AgentEvent {
  const AgentTextReset();
}

/// A tool call from the current cycle is about to execute.
final class AgentToolStarted extends AgentEvent {
  const AgentToolStarted({required this.name, required this.args});

  final String name;
  final IMap<String, String> args;
}

/// A tool call finished. [ok] is false if the executor returned an
/// error string.
final class AgentToolFinished extends AgentEvent {
  const AgentToolFinished({required this.name, required this.ok});

  final String name;
  final bool ok;
}

/// Terminal event: the turn is complete. [result] carries the final
/// reply text (if any), written paths, tools called, capabilities
/// read.
final class AgentFinished extends AgentEvent {
  const AgentFinished(this.result);

  final AgentRunResult result;
}
