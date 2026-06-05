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
            case InlineChannel(:final value):
              await _editInlineMessage(
                token: telegramToken,
                inlineMessageId: value.inlineMessageId,
                text: text,
              );
            case VaultChannel():
              // Vault-triggered events have no reply destination —
              // any human-visible output goes back into the vault as
              // a side-effect of the capability's tool calls.
              break;
          }
        });
}

Future<void> _editInlineMessage({
  required String token,
  required String inlineMessageId,
  required String text,
}) async {
  final normalized = normalizeMarkdownToTelegramHtml(text);
  // Telegram caps message text at 4096 chars; editInlineMessageText
  // rejects longer payloads with a 400.
  final body = normalized.length > 4096
      ? "${normalized.substring(0, 4095)}…"
      : normalized;
  // Clear the "Thinking…" placeholder button by passing an empty
  // inline_keyboard. The button was load-bearing for getting
  // inline_message_id back on chosen_inline_result; it has no use
  // once the final answer is in.
  const clearedMarkup = '{"inline_keyboard":[]}';
  final response = await http.post(
    Uri.parse(
      "https://api.telegram.org/bot$token/editMessageText",
    ),
    body: {
      "inline_message_id": inlineMessageId,
      "text": body,
      "parse_mode": "HTML",
      "reply_markup": clearedMarkup,
    },
  );
  // Recovery: if Telegram rejects the HTML (model emitted invalid
  // tags), retry as plain text so the user actually sees the
  // answer instead of being stuck on "Working on: …".
  if (response.statusCode != 200) {
    await http.post(
      Uri.parse(
        "https://api.telegram.org/bot$token/editMessageText",
      ),
      body: {
        "inline_message_id": inlineMessageId,
        "text": _stripHtml(body),
        "reply_markup": clearedMarkup,
      },
    );
  }
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
            case InlineChannel():
              // No chat_id for inline messages; the placeholder
              // article text already signals "working on it" to the
              // user.
              break;
            case VaultChannel():
              break;
          }
        });
}

Future<void> _sendTelegram({
  required String token,
  required String chatId,
  required String text,
}) async {
  // #28: split over-cap bodies into ordered parts (no blind truncation).
  // #27: every part's delivery is verified, not fire-and-forget.
  final chunks = chunkForTelegram(normalizeMarkdownToTelegramHtml(text));
  for (final chunk in chunks) {
    await _postTelegramMessage(token: token, chatId: chatId, html: chunk);
  }
}

/// Sends one Telegram message and VERIFIES it landed (HTTP 200 + `ok`).
/// On an HTML-parse/4xx failure, retries once as plain text so the user
/// still receives the content. Throws if the message could not be
/// delivered at all, so a lost reply is surfaced upstream — never
/// silently counted as a successful turn (#27).
Future<void> _postTelegramMessage({
  required String token,
  required String chatId,
  required String html,
}) async {
  final uri = Uri.parse("https://api.telegram.org/bot$token/sendMessage");
  final res = await http.post(uri, body: {
    "chat_id": chatId,
    "text": html,
    "parse_mode": "HTML",
  });
  if (_telegramOk(res)) {
    return;
  }
  // HTML/parse or transient failure: retry once as plain text.
  final plain = await http.post(uri, body: {
    "chat_id": chatId,
    "text": _stripHtml(html),
  });
  if (_telegramOk(plain)) {
    return;
  }
  throw http.ClientException(
    "sendMessage not delivered: ${res.statusCode} ${res.body}",
  );
}

bool _telegramOk(http.Response res) {
  if (res.statusCode != 200) {
    return false;
  }
  try {
    final body = jsonDecode(res.body);
    return body is Map && body["ok"] == true;
  } on FormatException {
    return false;
  }
}

/// Telegram hard-caps message text at 4096 chars. Split longer bodies
/// into ordered parts on paragraph/line/word boundaries — never a blind
/// mid-token cut — so a long reply is delivered in full (#28). Tags
/// rarely span paragraph breaks; any part Telegram rejects as HTML is
/// retried as plain text by [_postTelegramMessage].
const telegramMaxLen = 4096;

List<String> chunkForTelegram(String s, {int max = telegramMaxLen}) {
  if (s.length <= max) {
    return [s];
  }
  final parts = <String>[];
  var rest = s;
  while (rest.length > max) {
    var cut = rest.lastIndexOf("\n\n", max);
    if (cut < max ~/ 2) {
      cut = rest.lastIndexOf("\n", max);
    }
    if (cut < max ~/ 2) {
      cut = rest.lastIndexOf(" ", max);
    }
    if (cut < max ~/ 2) {
      cut = max;
    }
    parts.add(rest.substring(0, cut).trimRight());
    rest = rest.substring(cut).trimLeft();
  }
  if (rest.isNotEmpty) {
    parts.add(rest);
  }
  return parts;
}

final _mdCodeSpan = RegExp(r"`([^`\n]+?)`");
final _mdBold = RegExp(r"\*\*([^\n*]+?)\*\*");

/// Defensive converter for the auto-reply path: the standing prompt
/// tells the model to emit Telegram-HTML, but it sometimes leaks
/// Markdown `**bold**` / `` `code` `` patterns into replies, which
/// Telegram then renders as literal asterisks/backticks under
/// `parse_mode=HTML`. We rewrite the obvious cases before send.
///
/// Conservative on purpose: only paired delimiters on a single line
/// (`** … **`, `` ` … ` ``). Unpaired markers, multi-line spans, and
/// already-correct HTML pass through unchanged. Code spans are
/// rewritten first so their content is not pattern-matched again as
/// bold; their inner `<`, `>`, `&` are escaped to keep the HTML valid.
String normalizeMarkdownToTelegramHtml(String s) => s
    .replaceAllMapped(_mdCodeSpan, (m) {
      final inner = m
          .group(1)!
          .replaceAll("&", "&amp;")
          .replaceAll("<", "&lt;")
          .replaceAll(">", "&gt;");
      return "<code>$inner</code>";
    })
    .replaceAllMapped(_mdBold, (m) => "<b>${m.group(1)!}</b>");

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
/// Two modes:
/// - **streaming = true** (default, "loud"): show* calls cycle the
///   message through reasoning preview / tool status / streamed
///   answer; finalize() edits to the HTML reply.
/// - **streaming = false** ("quiet"): a single "Thinking…" placeholder
///   is sent eagerly on `start()`; show* calls are no-ops; finalize()
///   edits the placeholder to the HTML reply. The user sees one
///   reaction at the start and one final answer — no flicker.
class TelegramLiveReply {
  TelegramLiveReply({
    required this.token,
    required this.chatId,
    this.streaming = true,
  });

  final String token;
  final String chatId;
  final bool streaming;

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

  /// Sends the initial placeholder. Idempotent. In quiet mode this
  /// fires immediately on construction (so the user sees "Thinking…"
  /// without waiting for the first reasoning token); in streaming
  /// mode it's a no-op (the first show* call sends the first state).
  Future<void> start() async {
    if (!streaming) {
      _enqueue("Thinking…", asHtml: false);
      // Wait for the placeholder to actually go out before returning,
      // so the user sees the reaction before any tool work begins.
      while (_dirty && !_finalized) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
    }
  }

  void showReasoning(String delta) {
    if (_finalized || !streaming) {
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
    if (_finalized || !streaming) {
      return;
    }
    _mode = _LiveMode.tool;
    _enqueue(_briefForTool(name, args), asHtml: false);
  }

  void showAnswer(String delta) {
    if (_finalized || !streaming) {
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
    if (_finalized || !streaming) {
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
    // #28: deliver the full answer — edit the live message with the
    // first part, then send any overflow as ordered follow-ups, instead
    // of blindly truncating at 4096.
    final chunks = chunkForTelegram(normalizeMarkdownToTelegramHtml(htmlText));
    final text = chunks.first;
    // Wait for any in-flight flush to complete before issuing the
    // final edit so the order on the wire matches the order here.
    while (_flushing) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    _pendingText = text;
    _pendingAsHtml = true;
    _dirty = true;
    await _finalizeFirstChunk(text);
    for (final extra in chunks.skip(1)) {
      try {
        await _postTelegramMessage(token: token, chatId: chatId, html: extra);
      } on Object {
        // Best-effort: the first (live) part already landed.
      }
    }
  }

  /// Edits/sends the first part of the final answer into the live
  /// message, with the existing HTML → plain → fresh-send recovery
  /// ladder so the user is never left stuck on "Thinking…".
  Future<void> _finalizeFirstChunk(String text) async {
    try {
      await _doSendOrEdit(text, asHtml: true);
      _dirty = false;
      return;
    } on Object {
      // HTML parse failure (e.g. the model emitted `<br/>` or an
      // unclosed tag). Recover by sending a plain-text version.
    }
    final plain = _stripHtml(text);
    try {
      await _doSendOrEdit(plain, asHtml: false);
      _dirty = false;
      return;
    } on Object {
      // Edit failed too — try a fresh plain-text send.
    }
    try {
      final id = await _send(plain, asHtml: false);
      _messageId = id;
      _lastSentText = plain;
      _lastSentAsHtml = false;
      _dirty = false;
    } on Object {
      // Best-effort: out of recovery options.
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

/// Strip HTML tags and decode the three escapes Telegram cares about,
/// for the last-resort plain-text fallback when finalize-as-HTML
/// fails. Not a full HTML parser — just enough to turn a Telegram
/// HTML reply into readable plain text.
final _htmlTagRe = RegExp(r"<[^>]+>");

String _stripHtml(String html) => html
    .replaceAll(_htmlTagRe, "")
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&amp;", "&");

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
