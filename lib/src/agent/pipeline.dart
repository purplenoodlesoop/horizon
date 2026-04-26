import "package:fast_immutable_collections/fast_immutable_collections.dart";
import "package:horizon/src/event/event.dart";

export "package:horizon/src/event/event.dart" show Event;

/// Streaming events emitted by a pipeline as it processes one
/// channel event. Mirrors `AgentEvent` from the LLM layer plus a
/// terminal [PipelineReply] that carries the channel-routed reply
/// (timing footer applied, sentinel suppressed).
sealed class PipelineEvent {
  const PipelineEvent();
}

final class PipelineReasoningDelta extends PipelineEvent {
  const PipelineReasoningDelta(this.text);

  final String text;
}

final class PipelineTextDelta extends PipelineEvent {
  const PipelineTextDelta(this.text);

  final String text;
}

final class PipelineTextReset extends PipelineEvent {
  const PipelineTextReset();
}

final class PipelineToolStarted extends PipelineEvent {
  const PipelineToolStarted({required this.name, required this.args});

  final String name;
  final IMap<String, String> args;
}

final class PipelineToolFinished extends PipelineEvent {
  const PipelineToolFinished({required this.name, required this.ok});

  final String name;
  final bool ok;
}

/// Terminal: the pipeline finished. [text] is the channel-routed
/// reply with timing footer applied (or null if no reply / sentinel
/// suppressed).
final class PipelineReply extends PipelineEvent {
  const PipelineReply({required this.event, required this.text});

  final Event event;
  final String? text;
}

const decayThreshold = Duration(hours: 1);
