import "dart:async";
import "dart:convert";
import "dart:io";

import "package:fn/fn.dart";
import "package:horizon/src/channel/voice.dart";
import "package:horizon/src/event/event.dart";
import "package:http/http.dart" as http;
import "package:mark/mark.dart";

const _pollingTimeout = 30;

String _generateId(int updateId) => "tg_$updateId";

class TelegramPoller extends StreamFx<Event> {
  TelegramPoller({
    required String botToken,
    required Set<String> allowedUsernames,
    required String vaultPath,
    required Logger logger,
  }) : super(() async* {
        var offset = 0;
        while (true) {
          final uri = Uri.parse(
            "https://api.telegram.org/bot$botToken/getUpdates"
            "?timeout=$_pollingTimeout&offset=$offset",
          );
          try {
            final response = await http.get(uri);
            if (response.statusCode != 200) {
              await Future<void>.delayed(const Duration(seconds: 5));
              continue;
            }
            final body = jsonDecode(response.body);
            if (body is! Map) {
              continue;
            }
            final ok = body["ok"];
            if (ok != true) {
              await Future<void>.delayed(const Duration(seconds: 5));
              continue;
            }
            final result = body["result"];
            if (result is! List) {
              continue;
            }
            for (final update in result) {
              if (update is! Map) {
                continue;
              }
              final updateId = update["update_id"];
              if (updateId is! int) {
                continue;
              }
              offset = updateId + 1;
              final inlineQuery = update["inline_query"];
              if (inlineQuery is Map) {
                await _answerInlineQuery(
                  token: botToken,
                  inlineQuery: inlineQuery,
                  allowedUsernames: allowedUsernames,
                  logger: logger,
                );
                continue;
              }
              final message = update["message"];
              if (message is! Map) {
                continue;
              }
              final chat = message["chat"];
              final from = message["from"];
              if (chat is! Map || from is! Map) {
                continue;
              }
              final chatId = chat["id"];
              if (chatId == null) {
                continue;
              }
              // Fail-closed: if TELEGRAM_USERNAME is unset we drop
              // every inbound message rather than accepting from
              // anyone. An unconfigured allowlist is a
              // misconfiguration, never a permission grant.
              if (allowedUsernames.isEmpty) {
                continue;
              }
              final fromUsername = from["username"];
              if (fromUsername is! String ||
                  !allowedUsernames.contains(fromUsername.toLowerCase())) {
                // Drop messages from anyone outside the allowlist.
                continue;
              }
              final eventId = _generateId(updateId);
              final quotedContext =
                  _quotedReplyContext(message["reply_to_message"]);
              final caption = message["caption"];
              final captionStr = caption is String ? caption : null;
              final photo = message["photo"];
              if (photo is List && photo.isNotEmpty) {
                final photoEvent = await _handlePhoto(
                  photo: photo,
                  caption: captionStr,
                  chatId: chatId.toString(),
                  botToken: botToken,
                  vaultPath: vaultPath,
                  eventId: eventId,
                  logger: logger,
                  prefix: quotedContext,
                );
                if (photoEvent != null) {
                  yield photoEvent;
                }
                continue;
              }
              final document = message["document"];
              if (document is Map) {
                final docEvent = await _handleDocument(
                  document: document,
                  caption: captionStr,
                  chatId: chatId.toString(),
                  botToken: botToken,
                  vaultPath: vaultPath,
                  eventId: eventId,
                  logger: logger,
                  prefix: quotedContext,
                );
                if (docEvent != null) {
                  yield docEvent;
                }
                continue;
              }
              final text = message["text"];
              if (text is String) {
                yield Event(
                  id: eventId,
                  content: _withPrefix(quotedContext, text),
                  channel: TelegramChannel((chatId: chatId.toString())),
                  timestamp: DateTime.now(),
                );
                continue;
              }
              final voice = message["voice"];
              if (voice is Map) {
                final voiceEvent = await _handleVoice(
                  message: message,
                  voice: voice,
                  chatId: chatId.toString(),
                  botToken: botToken,
                  vaultPath: vaultPath,
                  eventId: eventId,
                  logger: logger,
                  prefix: quotedContext,
                );
                if (voiceEvent != null) {
                  yield voiceEvent;
                }
                continue;
              }
              // Other message kinds (sticker, location, etc.) are
              // silently dropped — phase 7+ candidates.
            }
          } on http.ClientException {
            await Future<void>.delayed(const Duration(seconds: 5));
          }
        }
      });
}

Future<Event?> _handleVoice({
  required Map<dynamic, dynamic> message,
  required Map<dynamic, dynamic> voice,
  required String chatId,
  required String botToken,
  required String vaultPath,
  required String eventId,
  required Logger logger,
  String? prefix,
}) async {
  final fileId = voice["file_id"];
  if (fileId is! String) {
    return null;
  }
  // Re-arm typing indicator with `record_voice` while transcribing
  // so the user sees the bot is working.
  unawaited(_sendChatAction(
    token: botToken,
    chatId: chatId,
    action: "record_voice",
  ));
  final transcription = await TranscribeTelegramVoice(
    token: botToken,
    fileId: fileId,
    vaultPath: vaultPath,
    eventId: eventId,
    logger: logger,
  );
  final body = transcription == null
      ? "[voice memo failed: transcription unavailable — try again or "
          "send as text]"
      : "[voice memo]\n$transcription";
  return Event(
    id: eventId,
    content: _withPrefix(prefix, body),
    channel: TelegramChannel((chatId: chatId)),
    timestamp: DateTime.now(),
  );
}

/// Extract a one-line summary of the message the user is quoting via
/// Telegram's native "reply to" feature, so the orchestrator can
/// understand which prior message the new one references. Returns
/// null when there is no reply context or the quoted message has no
/// text/caption.
String? _quotedReplyContext(Object? replyTo) {
  if (replyTo is! Map) {
    return null;
  }
  final text = replyTo["text"];
  final caption = replyTo["caption"];
  final quoted = text is String && text.isNotEmpty
      ? text
      : (caption is String && caption.isNotEmpty ? caption : null);
  if (quoted == null) {
    return null;
  }
  final from = replyTo["from"];
  var author = "earlier message";
  if (from is Map) {
    final isBot = from["is_bot"] == true;
    final username = from["username"];
    if (isBot) {
      author = "your earlier reply";
    } else if (username is String && username.isNotEmpty) {
      author = "@$username's earlier message";
    }
  }
  final preview = quoted.length > 400 ? "${quoted.substring(0, 399)}…" : quoted;
  return '[User is replying to $author: "$preview"]';
}

String _withPrefix(String? prefix, String body) =>
    prefix == null ? body : "$prefix\n\n$body";

const _photosSubdir = "_horizon/messages/photos";
const _filesSubdir = "_horizon/messages/files";

/// Photos arrive as a list of size variants (smallest → largest);
/// we pick the largest so vision models see the most detail.
Future<Event?> _handlePhoto({
  required List<dynamic> photo,
  required String? caption,
  required String chatId,
  required String botToken,
  required String vaultPath,
  required String eventId,
  required Logger logger,
  String? prefix,
}) async {
  final largest = photo.lastWhere(
    (p) => p is Map && p["file_id"] is String,
    orElse: () => null,
  );
  if (largest is! Map) {
    return null;
  }
  final fileId = largest["file_id"] as String;
  final relPath = "$_photosSubdir/$eventId.jpg";
  final savedPath = await _downloadTelegramFile(
    botToken: botToken,
    fileId: fileId,
    vaultPath: vaultPath,
    targetRelPath: relPath,
    logger: logger,
  );
  if (savedPath == null) {
    return Event(
      id: eventId,
      content: _withPrefix(
        prefix,
        "[photo received but download failed]"
        "${caption == null ? "" : "\n$caption"}",
      ),
      channel: TelegramChannel((chatId: chatId)),
      timestamp: DateTime.now(),
    );
  }
  final body = "[image:$relPath]"
      "${caption == null ? "" : "\n$caption"}";
  return Event(
    id: eventId,
    content: _withPrefix(prefix, body),
    channel: TelegramChannel((chatId: chatId)),
    timestamp: DateTime.now(),
  );
}

Future<Event?> _handleDocument({
  required Map<dynamic, dynamic> document,
  required String? caption,
  required String chatId,
  required String botToken,
  required String vaultPath,
  required String eventId,
  required Logger logger,
  String? prefix,
}) async {
  final fileId = document["file_id"];
  if (fileId is! String) {
    return null;
  }
  final originalName = document["file_name"];
  final safeName = originalName is String
      ? _sanitizeFilename(originalName)
      : "file";
  final relPath = "$_filesSubdir/$eventId-$safeName";
  final savedPath = await _downloadTelegramFile(
    botToken: botToken,
    fileId: fileId,
    vaultPath: vaultPath,
    targetRelPath: relPath,
    logger: logger,
  );
  if (savedPath == null) {
    return Event(
      id: eventId,
      content: _withPrefix(
        prefix,
        "[file received but download failed: $safeName]"
        "${caption == null ? "" : "\n$caption"}",
      ),
      channel: TelegramChannel((chatId: chatId)),
      timestamp: DateTime.now(),
    );
  }
  final mime = document["mime_type"];
  final mimeNote = mime is String && mime.isNotEmpty ? " mime=$mime" : "";
  final body = "[file:$relPath$mimeNote]"
      "${caption == null ? "" : "\n$caption"}";
  return Event(
    id: eventId,
    content: _withPrefix(prefix, body),
    channel: TelegramChannel((chatId: chatId)),
    timestamp: DateTime.now(),
  );
}

/// Strip anything outside `[a-zA-Z0-9._-]` so the saved filename is
/// safe to embed in shell-quoted commands (write_file path checks
/// already cover traversal). Truncated at 80 chars.
String _sanitizeFilename(String name) {
  final cleaned = name.replaceAll(RegExp(r"[^a-zA-Z0-9._-]"), "_");
  if (cleaned.length <= 80) {
    return cleaned;
  }
  return cleaned.substring(0, 80);
}

/// Inline-mode handler. Telegram delivers an `inline_query` update
/// whenever a user types `@yourbot foo` in any chat (even chats the
/// bot is not a member of). The bot owes a sub-second
/// `answerInlineQuery` reply or the client shows nothing.
///
/// The lockdown semantics:
/// - Non-allowlisted users get a single canned article result
///   directing them to message the owner. No vault access, no LLM
///   call.
/// - Allowlisted users get a single canned result acknowledging that
///   inline mode is a v1 placeholder; the real pipeline runs over
///   DMs, which is where it has time to think.
///
/// `cache_time: 0` keeps Telegram from showing stale results if we
/// change behavior — important while this is a thin stub.
Future<void> _answerInlineQuery({
  required String token,
  required Map<dynamic, dynamic> inlineQuery,
  required Set<String> allowedUsernames,
  required Logger logger,
}) async {
  final queryId = inlineQuery["id"];
  if (queryId is! String) {
    return;
  }
  final from = inlineQuery["from"];
  final username = from is Map ? from["username"] : null;
  final lower = username is String ? username.toLowerCase() : "";
  final isAllowed =
      allowedUsernames.isNotEmpty && allowedUsernames.contains(lower);
  final result = isAllowed
      ? _inlineResult(
          id: "horizon-inline-allowed",
          title: "Horizon: inline mode coming soon",
          description:
              "Inline answers aren't supported yet — DM the bot directly "
              "to chat.",
          message: "(I tried using @horizon inline. It's a placeholder; "
              "DM the bot to actually chat with it.)",
        )
      : _inlineResult(
          id: "horizon-inline-guest",
          title: "This bot is private",
          description: "Message the owner if you need access.",
          message: "(This Horizon instance is locked down to a private "
              "allowlist.)",
        );
  try {
    final response = await http.post(
      Uri.parse(
        "https://api.telegram.org/bot$token/answerInlineQuery",
      ),
      body: {
        "inline_query_id": queryId,
        "results": jsonEncode([result]),
        "cache_time": "0",
        "is_personal": "true",
      },
    );
    if (response.statusCode != 200) {
      logger.debug(
        "inline: answerInlineQuery ${response.statusCode}: ${response.body}",
      );
    }
  } on http.ClientException catch (e) {
    logger.debug("inline: answerInlineQuery failed: $e");
  }
}

Map<String, Object> _inlineResult({
  required String id,
  required String title,
  required String description,
  required String message,
}) => {
      "type": "article",
      "id": id,
      "title": title,
      "description": description,
      "input_message_content": {
        "message_text": message,
      },
    };

/// Two-step Telegram file download (`getFile` then bytes), parking
/// the result under `<vault>/<targetRelPath>`. Returns the absolute
/// path on success, null on failure (which is logged).
Future<String?> _downloadTelegramFile({
  required String botToken,
  required String fileId,
  required String vaultPath,
  required String targetRelPath,
  required Logger logger,
}) async {
  final getFileUri = Uri.parse(
    "https://api.telegram.org/bot$botToken/getFile?file_id=$fileId",
  );
  final getFileResp = await http.get(getFileUri);
  if (getFileResp.statusCode != 200) {
    logger.warning(
      "tg file: getFile ${getFileResp.statusCode}: ${getFileResp.body}",
    );
    return null;
  }
  final body = jsonDecode(getFileResp.body);
  if (body is! Map ||
      body["ok"] != true ||
      body["result"] is! Map) {
    logger.warning("tg file: getFile bad response: ${getFileResp.body}");
    return null;
  }
  final filePath = (body["result"] as Map)["file_path"];
  if (filePath is! String) {
    logger.warning("tg file: getFile missing file_path");
    return null;
  }
  final dlUri = Uri.parse(
    "https://api.telegram.org/file/bot$botToken/$filePath",
  );
  final dlResp = await http.get(dlUri);
  if (dlResp.statusCode != 200) {
    logger.warning("tg file: download ${dlResp.statusCode}");
    return null;
  }
  final absPath = "$vaultPath/$targetRelPath";
  final file = File(absPath);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(dlResp.bodyBytes);
  return absPath;
}

Future<void> _sendChatAction({
  required String token,
  required String chatId,
  required String action,
}) async {
  try {
    await http.post(
      Uri.parse("https://api.telegram.org/bot$token/sendChatAction"),
      body: {"chat_id": chatId, "action": action},
    );
  } on Object {
    // Best-effort indicator.
  }
}
