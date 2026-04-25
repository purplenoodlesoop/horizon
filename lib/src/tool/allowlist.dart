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
