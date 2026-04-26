import "package:fast_immutable_collections/fast_immutable_collections.dart";

/// Aggregate outcome of a full agentic turn.
typedef AgentRunResult = ({
  String? text,
  IList<String> writtenPaths,
  IList<String> toolsCalled,
  IList<String> capabilitiesRead,
});
