import "dart:io";

import "package:mark/mark.dart";

const _reset = "\x1B[0m";
const _grey = "\x1B[90m";
const _purple = "\x1B[35m";

class ConsoleMessageProcessor
    extends BaseMessageProcessor<LogMessage, String>
    with StringMessageFormatterMixin {
  const ConsoleMessageProcessor();

  @override
  void process(LogMessage message, String formatted) {
    final color = message.matchPrimitive(
      primitive: (p) => p.match(
        info: (_) => _purple,
        debug: (_) => _grey,
        warning: (_) => _grey,
        error: (_) => _grey,
      ),
      orElse: () => _grey,
    );
    stdout.writeln("$color$formatted$_reset");
  }
}
