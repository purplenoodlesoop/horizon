import "package:horizon/src/event/event.dart";

export "package:horizon/src/event/event.dart" show Event;

/// Result yielded by the pipeline.
typedef PipelineResult = ({Event event, String? agentText});

const decayThreshold = Duration(hours: 1);
