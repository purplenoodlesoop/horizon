import "dart:io";

import "package:mark/mark.dart";

class FileMessageProcessor extends BaseMessageProcessor<LogMessage, String>
    with StringMessageFormatterMixin {
  FileMessageProcessor(this._sink);

  final IOSink _sink;

  factory FileMessageProcessor.open(String path) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    return FileMessageProcessor(
      file.openWrite(mode: FileMode.append),
    );
  }

  @override
  void process(LogMessage message, String formatted) {
    _sink.writeln(
      "[${DateTime.now().toIso8601String()}] $formatted",
    );
  }
}
