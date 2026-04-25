import "package:fast_immutable_collections/fast_immutable_collections.dart";
import "package:fn/fn.dart";
import "package:horizon/src/capability/capability.dart";
import "package:mark/mark.dart";

/// Cheap, mechanical check: warn if two capabilities have textually
/// identical descriptions. Pure string comparison, no LLM.
///
/// The richer semantic-confusability check lives in the
/// `lint-capabilities` capability (prose, LLM-driven, user-invoked).
class WarnIdenticalDescriptions extends Fx<void> {
  WarnIdenticalDescriptions({
    required IList<Capability> capabilities,
    required Logger logger,
  }) : super(() {
        final seen = <String, String>{};
        for (final cap in capabilities) {
          final key = cap.description.trim();
          final priorId = seen[key];
          if (priorId != null) {
            logger.warning(
              "Capabilities '$priorId' and '${cap.id}' have "
              "textually identical descriptions — load decisions "
              "will be ambiguous",
            );
          } else {
            seen[key] = cap.id;
          }
        }
      });
}
