import "dart:async";
import "dart:convert";

import "package:fast_immutable_collections/fast_immutable_collections.dart";
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
            case ScheduleChannel():
              // Schedule events route their reply via the harness's
              // deliver-tag handling, not the per-event channel.
              break;
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
            case ScheduleChannel():
              break;
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

// ----------------------------------------------------------------------
// Live updating reply
// ----------------------------------------------------------------------

/// Edit-message rate limit per Telegram is ~1/sec/chat. We pad to
/// 1200ms to stay clear of 429s under bursty token streams.
const _editCooldown = Duration(milliseconds: 1200);

/// Telegram caps text at 4096 chars. We truncate streaming previews
/// shorter to leave headroom for any prefix label and a tail
/// ellipsis.
const _maxPreviewLen = 4000;

enum _LiveMode { idle, thinking, tool, answer, finalized }

/// Streams progress to a single Telegram message: send once, then
/// edit as deltas arrive. Plain text during streaming (so a
/// half-streamed `<b>` doesn't 400 the API), HTML on finalize.
///
/// Lifecycle:
/// 1. `showReasoning(delta)` / `showTool(name, args)` /
///    `showAnswer(delta)` — push state. Edits are throttled.
/// 2. `finalize(text)` — flush immediately with `parse_mode=HTML`.
///    Falls back to a fresh `sendMessage` if the edit fails (so the
///    user always gets the answer even if mid-stream HTML caused a
///    400 on the last successful edit).
class TelegramLiveReply {
  TelegramLiveReply({
    required this.token,
    required this.chatId,
  });

  final String token;
  final String chatId;

  String? _messageId;
  String? _lastSentText;
  var _lastSentAsHtml = false;

  var _pendingText = "";
  var _pendingAsHtml = false;
  var _dirty = false;
  var _finalized = false;
  var _flushing = false;
  var _lastSentAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _scheduledTimer;

  // Mode state. Reasoning and answer accumulate; tool replaces.
  _LiveMode _mode = _LiveMode.idle;
  var _reasoningBuf = "";
  var _answerBuf = "";

  void showReasoning(String delta) {
    if (_finalized) {
      return;
    }
    if (_mode != _LiveMode.thinking) {
      // New cycle (entered after tool calls or from idle): restart
      // the reasoning buffer so the user sees only this cycle's
      // current line of thought, not stale earlier reasoning.
      _reasoningBuf = "";
      _answerBuf = "";
      _mode = _LiveMode.thinking;
    }
    _reasoningBuf += delta;
    final preview = "Thinking: ${_tail(_reasoningBuf, _maxPreviewLen - 12)}";
    _enqueue(preview, asHtml: false);
  }

  void showTool(String name, IMap<String, String> args) {
    if (_finalized) {
      return;
    }
    _mode = _LiveMode.tool;
    _enqueue(_briefForTool(name, args), asHtml: false);
  }

  void showAnswer(String delta) {
    if (_finalized) {
      return;
    }
    if (_mode != _LiveMode.answer) {
      _answerBuf = "";
      _mode = _LiveMode.answer;
    }
    _answerBuf += delta;
    final preview = _tail(_answerBuf, _maxPreviewLen);
    _enqueue(preview, asHtml: false);
  }

  /// Discard whatever was streamed during the current cycle: it was
  /// intermediate narration, not the final answer. Reverts to the
  /// reasoning preview so the user sees something while the next
  /// cycle starts.
  void resetAnswer() {
    if (_finalized) {
      return;
    }
    _answerBuf = "";
    if (_mode == _LiveMode.answer) {
      _mode = _LiveMode.thinking;
      final preview = _reasoningBuf.isEmpty
          ? "Thinking..."
          : "Thinking: ${_tail(_reasoningBuf, _maxPreviewLen - 12)}";
      _enqueue(preview, asHtml: false);
    }
  }

  Future<void> finalize(String htmlText) async {
    _finalized = true;
    _scheduledTimer?.cancel();
    _scheduledTimer = null;
    _mode = _LiveMode.finalized;
    final text = _trunc(htmlText, 4096);
    // Wait for any in-flight flush to complete before issuing the
    // final edit so the order on the wire matches the order here.
    while (_flushing) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    _pendingText = text;
    _pendingAsHtml = true;
    _dirty = true;
    try {
      await _doSendOrEdit(text, asHtml: true);
      _dirty = false;
    } on Object {
      // Edit failed (probably malformed HTML at the prior preview
      // state). Fall back to sending a brand-new message so the
      // answer reaches the user one way or another.
      try {
        final id = await _send(text, asHtml: true);
        _messageId = id;
        _lastSentText = text;
        _lastSentAsHtml = true;
        _dirty = false;
      } on Object {
        // Best-effort.
      }
    }
  }

  void _enqueue(String text, {required bool asHtml}) {
    if (_finalized) {
      return;
    }
    final trimmed = _trunc(text, _maxPreviewLen);
    if (trimmed == _lastSentText && asHtml == _lastSentAsHtml) {
      return;
    }
    _pendingText = trimmed;
    _pendingAsHtml = asHtml;
    _dirty = true;
    _maybeStartFlush();
  }

  void _maybeStartFlush() {
    if (_flushing || !_dirty) {
      return;
    }
    final now = DateTime.now();
    final elapsed = now.difference(_lastSentAt);
    if (elapsed >= _editCooldown) {
      _scheduledTimer?.cancel();
      _scheduledTimer = null;
      unawaited(_runFlush());
    } else {
      _scheduledTimer ??= Timer(_editCooldown - elapsed, () {
        _scheduledTimer = null;
        unawaited(_runFlush());
      });
    }
  }

  Future<void> _runFlush() async {
    if (_flushing || _finalized || !_dirty) {
      return;
    }
    _flushing = true;
    try {
      while (_dirty && !_finalized) {
        final text = _pendingText;
        final asHtml = _pendingAsHtml;
        _dirty = false;
        _lastSentAt = DateTime.now();
        try {
          await _doSendOrEdit(text, asHtml: asHtml);
        } on Object {
          // Drop this edit; the next one will retry. finalize()
          // does the recovery if even the final fails.
        }
        if (_dirty && !_finalized) {
          // Respect cooldown between consecutive edits.
          await Future<void>.delayed(_editCooldown);
        }
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> _doSendOrEdit(String text, {required bool asHtml}) async {
    if (_messageId == null) {
      final id = await _send(text, asHtml: asHtml);
      _messageId = id;
    } else if (text != _lastSentText || asHtml != _lastSentAsHtml) {
      await _edit(_messageId!, text, asHtml: asHtml);
    }
    _lastSentText = text;
    _lastSentAsHtml = asHtml;
  }

  Future<String> _send(String text, {required bool asHtml}) async {
    final uri = Uri.parse(
      "https://api.telegram.org/bot$token/sendMessage",
    );
    final response = await http.post(uri, body: {
      "chat_id": chatId,
      "text": text,
      if (asHtml) "parse_mode": "HTML",
    });
    if (response.statusCode != 200) {
      throw http.ClientException(
        "sendMessage ${response.statusCode}: ${response.body}",
      );
    }
    final body = jsonDecode(response.body);
    if (body is Map &&
        body["ok"] == true &&
        body["result"] is Map &&
        (body["result"] as Map)["message_id"] != null) {
      return (body["result"] as Map)["message_id"].toString();
    }
    throw http.ClientException(
      "sendMessage: missing message_id in ${response.body}",
    );
  }

  Future<void> _edit(
    String messageId,
    String text, {
    required bool asHtml,
  }) async {
    final uri = Uri.parse(
      "https://api.telegram.org/bot$token/editMessageText",
    );
    final response = await http.post(uri, body: {
      "chat_id": chatId,
      "message_id": messageId,
      "text": text,
      if (asHtml) "parse_mode": "HTML",
    });
    if (response.statusCode != 200) {
      // 400 "message is not modified" can happen if the rendered
      // text matches the previous state after Telegram normalizes
      // whitespace; treat that as a no-op rather than an error.
      try {
        final body = jsonDecode(response.body);
        if (body is Map &&
            body["description"] is String &&
            (body["description"] as String)
                .contains("message is not modified")) {
          return;
        }
      } on FormatException {
        // fallthrough
      }
      throw http.ClientException(
        "editMessageText ${response.statusCode}: ${response.body}",
      );
    }
  }
}

String _tail(String s, int max) {
  if (s.length <= max) {
    return s;
  }
  return "…${s.substring(s.length - max + 1)}";
}

String _trunc(String s, int max) {
  if (s.length <= max) {
    return s;
  }
  return "${s.substring(0, max - 1)}…";
}

String _briefForTool(String name, IMap<String, String> args) {
  String? a(String key) {
    final v = args[key];
    if (v == null || v.isEmpty) {
      return null;
    }
    if (v.length <= 80) {
      return v;
    }
    return "${v.substring(0, 79)}…";
  }
  switch (name) {
    case "read_file":
      return "Reading ${a("path") ?? "file"}";
    case "write_file":
      return "Writing ${a("path") ?? "file"}";
    case "append_file":
      return "Appending to ${a("path") ?? "file"}";
    case "list_files":
      return "Listing files";
    case "list_files_glob":
      return "Listing ${a("pattern") ?? "files"}";
    case "search_vault":
      return "Searching vault for ${a("query") ?? "..."}";
    case "count_matches":
      return "Counting ${a("query") ?? "..."} in ${a("path") ?? "vault"}";
    case "delete_file":
      return "Deleting ${a("path") ?? "file"}";
    case "now":
      return "Checking time";
    case "fetch_url":
    case "fetch_url_text":
      return "Fetching ${a("url") ?? "url"}";
    case "web_search":
      return "Searching the web for ${a("query") ?? "..."}";
    case "send_telegram":
      return "Sending message";
    case "schedule_reminder":
      return "Setting reminder ${a("id") ?? ""}";
    case "schedule_cron":
      return "Setting cron ${a("id") ?? ""}";
    case "cancel_schedule":
      return "Cancelling ${a("id") ?? "schedule"}";
    case "list_schedules":
      return "Listing schedules";
    default:
      return "Running $name";
  }
}
