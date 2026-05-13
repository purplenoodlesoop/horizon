import "dart:io";

import "package:fast_immutable_collections/fast_immutable_collections.dart";
import "package:fn/fn.dart";
import "package:freezed_annotation/freezed_annotation.dart";
import "package:yaml/yaml.dart";

part "capability.freezed.dart";

/// A vault-resident markdown capability.
///
/// `id` and `description` come from YAML frontmatter; the body is
/// loaded on demand by the orchestrator via the existing `read_file`
/// tool. The harness never reads the body itself.
///
/// [watch] lists glob patterns (relative to the vault root) that the
/// vault-watcher channel uses to fire events. A file change matching
/// any of a capability's watch patterns produces a vault-channel
/// event the orchestrator processes with the capability loaded.
@freezed
abstract class Capability with _$Capability {
  const factory Capability({
    required String id,
    required String description,
    required String relativePath,
    String? schedule,
    @Default(IListConst([])) IList<String> watch,
  }) = _Capability;
}

const _capabilitiesSubdir = "_horizon/capabilities";

/// Loads the capability manifest from `<vault>/_horizon/capabilities/`.
///
/// Re-invoked at the start of every event so changes the user makes
/// in Obsidian propagate without restart.
class LoadCapabilities extends Fx<IList<Capability>> {
  LoadCapabilities(String vaultPath)
    : super(() {
        final dir = Directory("$vaultPath/$_capabilitiesSubdir");
        if (!dir.existsSync()) {
          return IList();
        }
        final files = dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith(".md"))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        final capabilities = <Capability>[];
        for (final file in files) {
          final content = file.readAsStringSync();
          final cap = _parseCapability(file, vaultPath, content);
          if (cap != null) {
            capabilities.add(cap);
          }
        }
        return capabilities.toIList();
      });
}

Capability? _parseCapability(
  File file,
  String vaultPath,
  String content,
) {
  final frontmatter = _extractFrontmatter(content);
  if (frontmatter == null) {
    return null;
  }
  final Object? doc = loadYaml(frontmatter);
  if (doc is! YamlMap) {
    return null;
  }
  final id = doc["id"];
  final description = doc["description"];
  if (id is! String || description is! String) {
    return null;
  }
  final schedule = doc["schedule"];
  final watchRaw = doc["watch"];
  final watch = watchRaw is YamlList
      ? watchRaw.whereType<String>().toIList()
      : <String>[].lock;
  final prefix = "$vaultPath/";
  final relativePath = file.path.startsWith(prefix)
      ? file.path.substring(prefix.length)
      : file.path;
  return Capability(
    id: id,
    description: description,
    relativePath: relativePath,
    schedule: schedule is String ? schedule : null,
    watch: watch,
  );
}

String? _extractFrontmatter(String content) {
  final normalized = content.replaceAll("\r\n", "\n");
  if (!normalized.startsWith("---\n")) {
    return null;
  }
  final lines = normalized.split("\n");
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].trim() == "---") {
      return lines.sublist(1, i).join("\n");
    }
  }
  return null;
}
