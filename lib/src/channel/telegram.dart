import "dart:async";
import "dart:convert";

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
    required String allowedUsername,
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
              // anyone. The bot is single-user; an unconfigured
              // username is a misconfiguration, never a permission
              // grant.
              if (allowedUsername.isEmpty) {
                continue;
              }
              final fromUsername = from["username"];
              if (fromUsername is! String ||
                  fromUsername.toLowerCase() != allowedUsername) {
                // Drop messages from anyone other than the allowed
                // username.
                continue;
              }
              final eventId = _generateId(updateId);
              final text = message["text"];
              if (text is String) {
                yield Event(
                  id: eventId,
                  content: text,
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
                );
                if (voiceEvent != null) {
                  yield voiceEvent;
                }
                continue;
              }
              // Other message kinds (photo, sticker, document, etc.)
              // are silently dropped today. Phase 7+ candidate to
              // surface them as events.
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
    content: body,
    channel: TelegramChannel((chatId: chatId)),
    timestamp: DateTime.now(),
  );
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
