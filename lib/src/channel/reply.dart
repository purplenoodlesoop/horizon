import "package:fn/fn.dart";
import "package:horizon/src/event/event.dart";
import "package:http/http.dart" as http;

class SendReply extends Fx<void> {
  SendReply({
    required Channel<Object?> channel,
    required String text,
    required String telegramToken,
  }) : super(() async {
          switch (channel) {
            case CliChannel():
              break;
            case TelegramChannel(:final value):
              await _sendTelegram(
                token: telegramToken,
                chatId: value.chatId,
                text: text,
              );
          }
        });
}

/// Sends `sendChatAction(typing)` so the user sees "typing..." in
/// Telegram while the pipeline runs. The action expires server-side
/// after ~5s, so the harness re-arms it periodically. CLI is a no-op.
class SendChatActionTyping extends Fx<void> {
  SendChatActionTyping({
    required Channel<Object?> channel,
    required String telegramToken,
  }) : super(() async {
          switch (channel) {
            case CliChannel():
              break;
            case TelegramChannel(:final value):
              try {
                await _sendChatAction(
                  token: telegramToken,
                  chatId: value.chatId,
                  action: "typing",
                );
              } on http.ClientException {
                // Best-effort indicator; never let this fail the
                // pipeline.
              }
          }
        });
}

Future<void> _sendTelegram({
  required String token,
  required String chatId,
  required String text,
}) async {
  final uri = Uri.parse(
    "https://api.telegram.org/bot$token/sendMessage",
  );
  await http.post(uri, body: {
    "chat_id": chatId,
    "text": text,
    // The standing prompt instructs the orchestrator to format
    // Telegram replies as Telegram-flavoured HTML. Markdown is
    // never sent here intentionally; if the model emits
    // un-escaped < > & literals we'll get a 400 on those replies
    // (visible in logs) but won't crash.
    "parse_mode": "HTML",
  });
}

Future<void> _sendChatAction({
  required String token,
  required String chatId,
  required String action,
}) async {
  final uri = Uri.parse(
    "https://api.telegram.org/bot$token/sendChatAction",
  );
  await http.post(uri, body: {"chat_id": chatId, "action": action});
}
