import "dart:io";

import "package:fn/fn.dart";

/// Channel-level runtime preferences. Each toggle is a single
/// frontmatter key in `<vault>/_horizon/system/preferences.md`. Loaded
/// per event (cheap; the file is tiny) so admin commands like
/// `/quiet` and `/loud` take effect immediately without restart.
class Preferences {
  const Preferences({this.streamUi = true});

  /// When `false`, Telegram replies skip the live-edit "Thinking..." /
  /// per-tool intermediate previews and only send the final answer.
  /// Typing indicator is still re-armed independently — the user still
  /// sees the bot is working.
  final bool streamUi;

  Preferences copyWith({bool? streamUi}) =>
      Preferences(streamUi: streamUi ?? this.streamUi);
}

const preferencesPath = "_horizon/system/preferences.md";

/// Loads `_horizon/system/preferences.md`. Missing file → returns
/// `fallback` unchanged, letting the CLI flag default win.
class LoadPreferences extends Fx<Preferences> {
  LoadPreferences({
    required String vaultPath,
    required Preferences fallback,
  }) : super(() async {
          final file = File("$vaultPath/$preferencesPath");
          if (!file.existsSync()) {
            return fallback;
          }
          final lines = await file.readAsLines();
          if (lines.isEmpty || lines.first.trim() != "---") {
            return fallback;
          }
          var streamUi = fallback.streamUi;
          for (var i = 1; i < lines.length; i++) {
            final line = lines[i];
            if (line.trim() == "---") {
              break;
            }
            final colon = line.indexOf(":");
            if (colon <= 0) {
              continue;
            }
            final key = line.substring(0, colon).trim();
            final value = line.substring(colon + 1).trim().toLowerCase();
            if (key == "stream_ui") {
              streamUi = !_isOff(value);
            }
          }
          return Preferences(streamUi: streamUi);
        });
}

/// Rewrites the preferences file from scratch. Used by `/quiet` and
/// `/loud` admin commands. The body is small and machine-managed; we
/// don't try to preserve user-added prose between writes.
class SavePreferences extends Fx<void> {
  SavePreferences({
    required String vaultPath,
    required Preferences preferences,
  }) : super(() async {
          final file = File("$vaultPath/$preferencesPath");
          await file.parent.create(recursive: true);
          await file.writeAsString(_render(preferences));
        });
}

String _render(Preferences p) {
  final streamUi = p.streamUi ? "on" : "off";
  return '''
---
stream_ui: $streamUi
---

Channel-level preferences. Toggle live with admin slash commands
(`/quiet`, `/loud`) or edit by hand and the next event picks it up.

- `stream_ui` — `on` to stream intermediate "Thinking..." / per-tool
  status edits to Telegram during long turns; `off` to send only the
  final reply (typing indicator still shown either way).
''';
}

bool _isOff(String value) =>
    value == "off" ||
    value == "false" ||
    value == "0" ||
    value == "no" ||
    value == "disabled";
