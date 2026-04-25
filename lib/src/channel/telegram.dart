import "dart:convert";

import "package:fn/fn.dart";
import "package:horizon/src/event/event.dart";
import "package:http/http.dart" as http;

const _pollingTimeout = 30;

String _generateId(int updateId) => "tg_$updateId";

class TelegramPoller extends StreamFx<Event> {
  TelegramPoller({
    required String botToken,
    required String allowedUsername,
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
              final text = message["text"];
              final chat = message["chat"];
              final from = message["from"];
              if (text is! String || chat is! Map || from is! Map) {
                continue;
              }
              final chatId = chat["id"];
              if (chatId == null) {
                continue;
              }
              if (allowedUsername.isNotEmpty) {
                final fromUsername = from["username"];
                if (fromUsername is! String ||
                    fromUsername.toLowerCase() != allowedUsername) {
                  // Drop messages from anyone other than the allowed
                  // username. The bot is single-user.
                  continue;
                }
              }
              yield Event(
                id: _generateId(updateId),
                content: text,
                channel: TelegramChannel((chatId: chatId.toString())),
                timestamp: DateTime.now(),
              );
            }
          } on http.ClientException {
            await Future<void>.delayed(const Duration(seconds: 5));
          }
        }
      });
}
