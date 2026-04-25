import "dart:io";

import "package:fn/fn.dart";

const _systemSubdir = "_horizon/system";
const _standingFile = "standing.md";
const _heartbeatAddendumFile = "heartbeat-addendum.md";

/// Loads a system-prompt template from `<vault>/_horizon/system/`,
/// falling back to `<templates>/_horizon/system/`. Substitutes
/// `{{manifest}}` with the supplied manifest text. The user is free
/// to edit the vault copy to tune the orchestrator's standing
/// prompt — nothing in the harness inspects the prompt's contents.
class LoadSystemPrompt extends Fx<String> {
  LoadSystemPrompt({
    required String vaultPath,
    required String templatesPath,
    required String manifest,
    required bool heartbeatMode,
  }) : super(() {
        final standing = _readWithFallback(
          vaultPath: vaultPath,
          templatesPath: templatesPath,
          fileName: _standingFile,
        ).replaceAll("{{manifest}}", manifest);
        if (!heartbeatMode) {
          return standing.trimRight();
        }
        final addendum = _readWithFallback(
          vaultPath: vaultPath,
          templatesPath: templatesPath,
          fileName: _heartbeatAddendumFile,
        );
        return "${standing.trimRight()}\n\n${addendum.trimRight()}";
      });
}

String _readWithFallback({
  required String vaultPath,
  required String templatesPath,
  required String fileName,
}) {
  final vaultFile = File("$vaultPath/$_systemSubdir/$fileName");
  if (vaultFile.existsSync()) {
    return vaultFile.readAsStringSync();
  }
  final templateFile = File("$templatesPath/$_systemSubdir/$fileName");
  if (templateFile.existsSync()) {
    return templateFile.readAsStringSync();
  }
  throw StateError(
    "System prompt template '$fileName' not found in either "
    "${vaultFile.path} or ${templateFile.path}",
  );
}
