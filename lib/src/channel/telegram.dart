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
          // Pass allowed_updates explicitly so inline_query and
          // chosen_inline_result are delivered. Telegram remembers
          // the most recent allowed_updates list across getUpdates
          // calls; without an explicit list a previously-restrictive
          // setting can silently suppress inline updates even after
          // inline mode is enabled in BotFather.
          final uri = Uri.parse(
            "https://api.telegram.org/bot$botToken/getUpdates"
            "?timeout=$_pollingTimeout&offset=$offset"
            "&allowed_updates="
            "%5B%22message%22%2C%22edited_message%22%2C%22inline_query%22"
            "%2C%22chosen_inline_result%22%2C%22callback_query%22%5D",
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
              // Defence: per-update handlers (voice transcription,
              // file download, inline answer) call out to processes
              // and HTTP. Any of them throwing would otherwise tear
              // down the whole poller stream and leave the bot up
              // but deaf. Catch broadly and drop just this update.
              try {
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
              final chosen = update["chosen_inline_result"];
              if (chosen is Map) {
                final inlineEvent = _handleChosenInlineResult(
                  chosen: chosen,
                  allowedUsernames: allowedUsernames,
                  updateId: updateId,
                  logger: logger,
                );
                if (inlineEvent != null) {
                  yield inlineEvent;
                }
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
              final forwardContext = _forwardContext(message);
              final inboundPrefix =
                  _joinPrefixes(forwardContext, quotedContext);
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
                  prefix: inboundPrefix,
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
                  prefix: inboundPrefix,
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
                  content: _withPrefix(inboundPrefix, text),
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
                  prefix: inboundPrefix,
                );
                if (voiceEvent != null) {
                  yield voiceEvent;
                }
                continue;
              }
              // Other message kinds (sticker, location, etc.) are
              // silently dropped — phase 7+ candidates.
              } on Object catch (e, st) {
                logger.error(
                  "tg poller: dropped update $updateId: $e",
                  stackTrace: st,
                );
              }
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

/// Combine forward + quote prefixes (both optional). Both, either, or
/// neither may be present; this avoids stacking blank-line separators
/// when only one is set.
String? _joinPrefixes(String? a, String? b) {
  if (a == null) {
    return b;
  }
  if (b == null) {
    return a;
  }
  return "$a\n$b";
}

/// Telegram surfaces forwarded-message attribution as either the modern
/// `forward_origin` envelope (typed `user`/`hidden_user`/`chat`/
/// `channel`) or the legacy `forward_from` / `forward_from_chat` /
/// `forward_sender_name` triplet. We attribute the visible message
/// regardless: the orchestrator needs to know that the body it sees
/// is not the user's own words.
String? _forwardContext(Map<dynamic, dynamic> message) {
  final origin = message["forward_origin"];
  if (origin is Map) {
    final attribution = _forwardOriginAttribution(origin);
    if (attribution != null) {
      return "[Forwarded from $attribution]";
    }
  }
  final from = message["forward_from"];
  if (from is Map) {
    return "[Forwarded from ${_userAttribution(from)}]";
  }
  final fromChat = message["forward_from_chat"];
  if (fromChat is Map) {
    return "[Forwarded from ${_chatAttribution(fromChat)}]";
  }
  final senderName = message["forward_sender_name"];
  if (senderName is String && senderName.isNotEmpty) {
    return "[Forwarded from $senderName (hidden Telegram account)]";
  }
  return null;
}

String? _forwardOriginAttribution(Map<dynamic, dynamic> origin) {
  final type = origin["type"];
  switch (type) {
    case "user":
      final user = origin["sender_user"];
      return user is Map ? _userAttribution(user) : null;
    case "hidden_user":
      final name = origin["sender_user_name"];
      return name is String && name.isNotEmpty
          ? "$name (hidden Telegram account)"
          : null;
    case "chat":
      final chat = origin["sender_chat"];
      return chat is Map ? _chatAttribution(chat) : null;
    case "channel":
      final chat = origin["chat"];
      final sig = origin["author_signature"];
      final base = chat is Map ? _chatAttribution(chat) : null;
      if (base == null) {
        return null;
      }
      if (sig is String && sig.isNotEmpty) {
        return "$base (signed: $sig)";
      }
      return base;
    default:
      return null;
  }
}

String _userAttribution(Map<dynamic, dynamic> user) {
  final username = user["username"];
  if (username is String && username.isNotEmpty) {
    return "@$username";
  }
  final first = user["first_name"];
  final last = user["last_name"];
  final parts = <String>[
    if (first is String && first.isNotEmpty) first,
    if (last is String && last.isNotEmpty) last,
  ];
  return parts.isEmpty ? "another user" : parts.join(" ");
}

String _chatAttribution(Map<dynamic, dynamic> chat) {
  final title = chat["title"];
  if (title is String && title.isNotEmpty) {
    final type = chat["type"];
    return type is String ? '$type "$title"' : 'chat "$title"';
  }
  final username = chat["username"];
  if (username is String && username.isNotEmpty) {
    return "@$username";
  }
  return "another chat";
}

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

const _inlineRunResultId = "horizon-inline-run";
const _inlineGuestResultId = "horizon-inline-guest";

/// Inline-mode handler. Telegram delivers an `inline_query` update
/// whenever a user types `@yourbot foo` in any chat (even chats the
/// bot is not a member of). The bot owes a sub-second
/// `answerInlineQuery` reply or the client shows nothing.
///
/// Lockdown semantics:
/// - **Non-allowlisted** users get a canned "private bot" article.
///   No vault access, no LLM, and the article carries no reply
///   markup so Telegram does not send us a `chosen_inline_result`
///   for it.
/// - **Allowlisted** users get a single "Send to Horizon" article.
///   The article ships with an empty inline keyboard, which is the
///   trick Telegram needs to (a) actually deliver
///   `chosen_inline_result` to us and (b) hand us an
///   `inline_message_id` we can later edit. When the user taps it,
///   the chat shows a "Working on…" placeholder and the harness
///   gets an event whose `InlineChannel` carries that message id;
///   on `editMessageText` with the LLM answer the placeholder
///   becomes the final reply, in-place.
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
  final rawQuery = inlineQuery["query"];
  final query = rawQuery is String ? rawQuery.trim() : "";

  final List<Map<String, Object>> results;
  int cacheTime;
  if (!isAllowed) {
    results = [
      _inlineGuestResult(),
    ];
    cacheTime = 300;
  } else if (query.isEmpty) {
    // Nothing to run yet — show a hint result, no LLM dispatch.
    results = [
      _inlineHintResult(),
    ];
    cacheTime = 5;
  } else {
    results = [
      _inlineRunResult(query: query),
    ];
    // Per-user, per-query; keep cache short so repeated taps don't
    // skip the chosen_inline_result delivery Telegram sometimes
    // suppresses for cached selections.
    cacheTime = 0;
  }

  try {
    final response = await http.post(
      Uri.parse(
        "https://api.telegram.org/bot$token/answerInlineQuery",
      ),
      body: {
        "inline_query_id": queryId,
        "results": jsonEncode(results),
        "cache_time": "$cacheTime",
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

/// Build the article that, when tapped, posts a placeholder message
/// and triggers the orchestrator. The empty `inline_keyboard` is
/// load-bearing: without it Telegram does not surface
/// `inline_message_id` to us on `chosen_inline_result`, and we lose
/// the only handle for editing the message with the answer.
Map<String, Object> _inlineRunResult({required String query}) {
  final preview = query.length > 60 ? "${query.substring(0, 59)}…" : query;
  return {
    "type": "article",
    "id": _inlineRunResultId,
    "title": "Ask Horizon",
    "description": preview,
    "input_message_content": {
      "message_text": "Working on: $preview",
    },
    // Telegram only delivers `inline_message_id` on
    // `chosen_inline_result` when the article carries a non-empty
    // `inline_keyboard`. The button is decorative — `callback_data`
    // points at a no-op handler — and the harness clears the markup
    // on the final edit so it disappears once the real answer
    // arrives.
    "reply_markup": {
      "inline_keyboard": [
        [
          {"text": "Thinking…", "callback_data": "horizon-inline-noop"},
        ],
      ],
    },
  };
}

Map<String, Object> _inlineHintResult() => {
      "type": "article",
      "id": "horizon-inline-hint",
      "title": "Ask Horizon",
      "description": "Type a question after @horizon to send it.",
      "input_message_content": {
        "message_text": "(type a question after @horizon to send it)",
      },
    };

Map<String, Object> _inlineGuestResult() => {
      "type": "article",
      "id": _inlineGuestResultId,
      "title": "This bot is private",
      "description": "Message the owner if you need access.",
      "input_message_content": {
        "message_text": "(This Horizon instance is locked down to a "
            "private allowlist.)",
      },
    };

/// Telegram fires `chosen_inline_result` when an inline result the
/// user tapped also carries `reply_markup` (or `input_message_content`).
/// For the allowed `_inlineRunResultId` article we treat the chosen
/// result as a real user message: produce an Event whose channel is
/// `InlineChannel(inlineMessageId)` so the harness routes the LLM
/// answer back via `editMessageText`.
Event? _handleChosenInlineResult({
  required Map<dynamic, dynamic> chosen,
  required Set<String> allowedUsernames,
  required int updateId,
  required Logger logger,
}) {
  final resultId = chosen["result_id"];
  if (resultId != _inlineRunResultId) {
    // Hint and guest results never run the LLM.
    return null;
  }
  final from = chosen["from"];
  final username = from is Map ? from["username"] : null;
  final lower = username is String ? username.toLowerCase() : "";
  if (allowedUsernames.isEmpty || !allowedUsernames.contains(lower)) {
    // Defence in depth — `_inlineRunResultId` is only offered to
    // allowlisted users, but reject any race here too.
    return null;
  }
  final inlineMessageId = chosen["inline_message_id"];
  if (inlineMessageId is! String || inlineMessageId.isEmpty) {
    logger.warning(
      "inline: chosen_inline_result missing inline_message_id, "
      "cannot edit reply",
    );
    return null;
  }
  final query = chosen["query"];
  if (query is! String || query.trim().isEmpty) {
    return null;
  }
  return Event(
    id: "tg_inline_$updateId",
    content: query.trim(),
    channel: InlineChannel((inlineMessageId: inlineMessageId)),
    timestamp: DateTime.now(),
  );
}

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
