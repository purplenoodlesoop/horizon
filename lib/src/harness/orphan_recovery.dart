import "dart:io";

import "package:fn/fn.dart";
import "package:horizon/src/channel/reply.dart";
import "package:horizon/src/event/event.dart";
import "package:mark/mark.dart";

const _turnsSubdir = "_horizon/turns";
const _messagesSubdir = "_horizon/messages";
const _recoveredSuffix = ".recovered";

const _fallbackText = "I missed your earlier message — sorry. "
    "Please resend if it's still relevant.";

/// Min age before a turn is considered orphaned. Pipelines that
/// take ~10–30s to complete should not race with the scanner.
const _minOrphanAge = Duration(seconds: 30);

final _eventIdRe = RegExp(r"^event_id:\s*(\S+)\s*$", multiLine: true);
final _hadReplyFalseRe = RegExp(r"^had_reply:\s*false\s*$", multiLine: true);
final _chatIdRe = RegExp(r"^chat_id:\s*(\S+)\s*$", multiLine: true);
final _outSectionRe = RegExp(r"\n## Out\s*\n(.*)$", dotAll: true);

/// Scans recent turn records for `tg_*` events with `had_reply: false`
/// and sends a deterministic fallback to the original chat. Marks each
/// recovered turn with a `<turn>.recovered` sidecar to dedupe across
/// heartbeats. Returns the number of recoveries performed.
///
/// The scanner is conservative: it skips turns younger than 30 s
/// (live pipelines may still be running), and it skips turns whose
/// message file already carries a non-empty `## Out` section (the
/// completion=0 fallback from issue #11 already delivered something).
///
/// Acceptance for issue #13: an unanswered `tg_*` event from the past
/// N minutes is detected and responded to within one heartbeat tick,
/// regardless of which capabilities the LLM picked.
class RecoverOrphanedTurns extends Fx<int> {
  RecoverOrphanedTurns({
    required String vaultPath,
    required String telegramToken,
    required Duration lookback,
    required DateTime now,
    required Logger logger,
  }) : super(() async {
          final turnsDir = Directory("$vaultPath/$_turnsSubdir");
          if (!turnsDir.existsSync()) {
            return 0;
          }
          final cutoff = now.subtract(lookback);
          final maxStamp = now.subtract(_minOrphanAge);
          var recovered = 0;
          for (final entry in turnsDir.listSync()) {
            if (entry is! File) {
              continue;
            }
            final basename = entry.uri.pathSegments.last;
            if (!basename.endsWith(".md")) {
              continue;
            }
            // Cheap rejection on filename: only Telegram event ids.
            if (!basename.contains("-tg_")) {
              continue;
            }
            // Sidecar gate: already recovered.
            final markerPath = "${entry.path}$_recoveredSuffix";
            if (File(markerPath).existsSync()) {
              continue;
            }
            // Filename embeds the event timestamp:
            // <YYYY-MM-DDTHH-mm-ss.ffffff>-<event_id>.md
            final stamp = _parseStampFromBasename(basename);
            if (stamp == null) {
              continue;
            }
            if (stamp.isBefore(cutoff)) {
              continue;
            }
            if (stamp.isAfter(maxStamp)) {
              continue;
            }
            final body = entry.readAsStringSync();
            if (!_hadReplyFalseRe.hasMatch(body)) {
              continue;
            }
            final eventIdMatch = _eventIdRe.firstMatch(body);
            if (eventIdMatch == null) {
              continue;
            }
            final eventId = eventIdMatch.group(1)!;
            // Locate matching message file — same basename, sibling dir.
            final messagePath = "$vaultPath/$_messagesSubdir/$basename";
            final messageFile = File(messagePath);
            if (!messageFile.existsSync()) {
              continue;
            }
            final msgBody = messageFile.readAsStringSync();
            // If outbound already has content other than "(no reply)",
            // the user got something (e.g. the completion=0 fallback
            // from issue #11). Mark recovered and skip.
            final out = _outSectionRe.firstMatch(msgBody)?.group(1)?.trim();
            if (out != null && out.isNotEmpty && out != "(no reply)") {
              _writeMarker(markerPath, now, "outbound-present");
              continue;
            }
            final chatIdMatch = _chatIdRe.firstMatch(msgBody);
            if (chatIdMatch == null) {
              continue;
            }
            final chatId = chatIdMatch.group(1)!;
            try {
              await SendReply(
                channel: TelegramChannel((chatId: chatId)),
                text: _fallbackText,
                telegramToken: telegramToken,
              );
              _writeMarker(markerPath, now, "fallback-sent");
              recovered++;
              logger.warning(
                "[orphan-recovery] $eventId: fallback sent to "
                "chat $chatId (stamp=${stamp.toIso8601String()})",
              );
            } on Exception catch (e, st) {
              logger.error(
                "[orphan-recovery] $eventId: send failed: $e",
                stackTrace: st,
              );
            }
          }
          return recovered;
        });
}

void _writeMarker(String path, DateTime now, String reason) {
  File(path).writeAsStringSync(
    "recovered_at: ${now.toIso8601String()}\nreason: $reason\n",
  );
}

/// Parses the leading `<YYYY-MM-DDTHH-mm-ss.ffffff>` portion of a turn
/// or message filename. Colons in the timestamp are rendered as `-`
/// (see `_safeTimestamp` in turn_store/message_store), so we restore
/// them before parsing.
DateTime? _parseStampFromBasename(String basename) {
  // Take the substring up to the first `-tg_`.
  final tgIdx = basename.indexOf("-tg_");
  if (tgIdx <= 0) {
    return null;
  }
  final stampPart = basename.substring(0, tgIdx);
  // Restore colons: the safe form replaces ":" with "-", so the
  // last two "-" in the time portion need to become ":".
  // Form: YYYY-MM-DDTHH-mm-ss.ffffff
  // Want: YYYY-MM-DDTHH:mm:ss.ffffff
  final tIdx = stampPart.indexOf("T");
  if (tIdx < 0) {
    return null;
  }
  final datePart = stampPart.substring(0, tIdx);
  final timePart = stampPart
      .substring(tIdx + 1)
      .replaceFirst("-", ":")
      .replaceFirst("-", ":");
  return DateTime.tryParse("${datePart}T$timePart");
}
