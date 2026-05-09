import "dart:io";

import "package:fast_immutable_collections/fast_immutable_collections.dart";
import "package:fn/fn.dart";
import "package:freezed_annotation/freezed_annotation.dart";
import "package:yaml/yaml.dart";

part "allowlist.freezed.dart";

@freezed
abstract class ToolParam with _$ToolParam {
  const factory ToolParam({
    required String type,
    required String description,
  }) = _ToolParam;
}

@freezed
abstract class AllowlistedTool with _$AllowlistedTool {
  const factory AllowlistedTool({
    required String name,
    required String description,
    required IMap<String, ToolParam> parameters,
    required String commandTemplate,
  }) = _AllowlistedTool;
}

AllowlistedTool _parseTool(Object? raw) {
  if (raw is! YamlMap) {
    throw ArgumentError.value(raw, "raw", "Expected a YAML map for tool");
  }
  final name = raw["name"];
  final description = raw["description"];
  final command = raw["command"];
  if (name is! String) {
    throw ArgumentError("Tool missing string 'name' field");
  }
  if (description is! String) {
    throw ArgumentError("Tool '$name' missing string 'description' field");
  }
  if (command is! String) {
    throw ArgumentError("Tool '$name' missing string 'command' field");
  }
  final rawParams = raw["parameters"];
  final params = <String, ToolParam>{};
  if (rawParams is YamlMap) {
    for (final entry in rawParams.entries) {
      final key = entry.key;
      final val = entry.value;
      if (key is! String) {
        continue;
      }
      if (val is YamlMap) {
        final paramType = val["type"];
        final paramDesc = val["description"];
        params[key] = ToolParam(
          type: paramType is String ? paramType : "string",
          description: paramDesc is String ? paramDesc : "",
        );
      }
    }
  }
  return AllowlistedTool(
    name: name,
    description: description,
    parameters: params.toIMap(),
    commandTemplate: command,
  );
}

class LoadAllowlist extends Fx<IList<AllowlistedTool>> {
  LoadAllowlist(String path)
    : super(() {
        final content = File(path).readAsStringSync();
        final doc = loadYaml(content);
        if (doc is! YamlMap) {
          return IList();
        }
        final rawTools = doc["tools"];
        if (rawTools is! YamlList) {
          return IList();
        }
        return rawTools.map(_parseTool).toIList();
      });
}

/// Resolves which allowlist file to read on a given event.
///
/// Resolution order:
///   1. Explicit override (`--allowlist` flag or `HORIZON_ALLOWLIST` env)
///   2. Vault-resident `<vault>/_horizon/system/allowlist.yaml`
///   3. Bundled template `<templates>/_horizon/system/allowlist.yaml`
///
/// (1) is the dev/testing escape hatch — once set, the harness ignores
/// the vault. (2) is the live edit path — Obsidian edits propagate on
/// the next event. (3) is what BootstrapVault copies into (2) on first
/// run, and what's used until the bootstrap completes.
String resolveAllowlistPath({
  required String vaultPath,
  required String templatesPath,
  required String override,
}) {
  if (override.isNotEmpty) {
    return override;
  }
  final vaultFile = "$vaultPath/_horizon/system/allowlist.yaml";
  if (File(vaultFile).existsSync()) {
    return vaultFile;
  }
  return "$templatesPath/_horizon/system/allowlist.yaml";
}
