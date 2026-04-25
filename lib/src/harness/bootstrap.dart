import "dart:io";

import "package:fn/fn.dart";
import "package:mark/mark.dart";

const _vaultMarkerSubdir = "_horizon";
const _templatesSourceSubdir = "_horizon";

/// Copies template files into the vault wherever they are missing.
///
/// File-level idempotent: existing files in the vault are never
/// overwritten, and a partially-populated `<vault>/_horizon/` does
/// not block the rest of the bundle from arriving. The harness has
/// no opinion about what the templates contain — they are content,
/// not code.
class BootstrapVault extends Fx<void> {
  BootstrapVault({
    required String vaultPath,
    required String templatesPath,
    required Logger logger,
  }) : super(() {
        final source = Directory(
          "$templatesPath/$_templatesSourceSubdir",
        );
        if (!source.existsSync()) {
          final marker = Directory(
            "$vaultPath/$_vaultMarkerSubdir",
          );
          if (!marker.existsSync()) {
            logger.warning(
              "Vault has no $_vaultMarkerSubdir/ and no templates "
              "available at ${source.path} — capabilities will be "
              "empty until you create $_vaultMarkerSubdir/ files",
            );
          }
          return;
        }
        final target = Directory("$vaultPath/$_vaultMarkerSubdir")
          ..createSync(recursive: true);
        final copied = _copyMissing(source, target);
        if (copied.isEmpty) {
          logger.debug(
            "Bootstrap: no missing files in ${target.path}",
          );
        } else {
          logger.info(
            "Bootstrapped ${copied.length} missing file(s) into "
            "${target.path}: ${copied.join(", ")}",
          );
        }
      });
}

List<String> _copyMissing(Directory source, Directory target) {
  final copied = <String>[];
  for (final entity in source.listSync(recursive: true)) {
    final rel = entity.path.substring(source.path.length + 1);
    if (entity is Directory) {
      Directory("${target.path}/$rel").createSync(recursive: true);
    } else if (entity is File) {
      final dest = File("${target.path}/$rel");
      if (dest.existsSync()) {
        continue;
      }
      dest.parent.createSync(recursive: true);
      dest.writeAsBytesSync(entity.readAsBytesSync());
      copied.add(rel);
    }
  }
  return copied;
}
