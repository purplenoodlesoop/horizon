import "dart:convert";
import "dart:io";

import "package:fn/fn.dart";
import "package:http/http.dart" as http;
import "package:mark/mark.dart";

const _voiceSubdir = "_horizon/messages/voice";

/// Telegram → local file path. Returns the saved audio file path on
/// success, or null on failure (logged).
class DownloadTelegramVoice extends Fx<String?> {
  DownloadTelegramVoice({
    required String token,
    required String fileId,
    required String vaultPath,
    required String eventId,
    required Logger logger,
  }) : super(() async {
          // Step 1: getFile → file_path
          final getFileUri = Uri.parse(
            "https://api.telegram.org/bot$token/getFile?file_id=$fileId",
          );
          final getFileResp = await http.get(getFileUri);
          if (getFileResp.statusCode != 200) {
            logger.warning(
              "voice: getFile ${getFileResp.statusCode}: "
              "${getFileResp.body}",
            );
            return null;
          }
          final body = jsonDecode(getFileResp.body);
          if (body is! Map ||
              body["ok"] != true ||
              body["result"] is! Map) {
            logger.warning("voice: getFile bad response: ${getFileResp.body}");
            return null;
          }
          final filePath = (body["result"] as Map)["file_path"];
          if (filePath is! String) {
            logger.warning("voice: getFile missing file_path");
            return null;
          }
          // Step 2: download the audio bytes.
          final dlUri = Uri.parse(
            "https://api.telegram.org/file/bot$token/$filePath",
          );
          final dlResp = await http.get(dlUri);
          if (dlResp.statusCode != 200) {
            logger.warning("voice: download ${dlResp.statusCode}");
            return null;
          }
          // Step 3: write to vault. Use the original extension so
          // whisper-cpp can demux via its bundled libavcodec.
          final ext = filePath.contains(".")
              ? filePath.substring(filePath.lastIndexOf("."))
              : ".oga";
          final saveDir = Directory("$vaultPath/$_voiceSubdir");
          await saveDir.create(recursive: true);
          final savePath = "${saveDir.path}/$eventId$ext";
          await File(savePath).writeAsBytes(dlResp.bodyBytes);
          return savePath;
        });
}

/// Runs whisper.cpp on the audio file. Uses the upstream
/// `whisper-cli` binary (provided by the Nix wrapper) and the
/// matching `whisper-cpp-download-ggml-model` script for first-time
/// model fetch.
///
/// `HORIZON_WHISPER_MODEL` (env, default `base`) selects the model
/// name (e.g. `base`, `small`, `large-v3-turbo` — see the upstream
/// list at <https://github.com/ggml-org/whisper.cpp>). The model is
/// cached to `~/.cache/horizon/whisper/ggml-<name>.bin` on first
/// run; subsequent calls reuse it.
class TranscribeWithWhisper extends Fx<String?> {
  TranscribeWithWhisper({
    required String audioPath,
    required Logger logger,
  }) : super(() async {
          final modelName =
              Platform.environment["HORIZON_WHISPER_MODEL"] ?? "base";
          final cacheDir = Directory(
            "${Platform.environment["HOME"] ?? ""}/.cache/horizon/whisper",
          )..createSync(recursive: true);
          final modelPath = "${cacheDir.path}/ggml-$modelName.bin";
          if (!File(modelPath).existsSync()) {
            logger.info(
              "voice: model $modelName not cached, downloading via "
              "whisper-cpp-download-ggml-model (first run only)…",
            );
            final dl = await Process.run(
              "whisper-cpp-download-ggml-model",
              [modelName, cacheDir.path],
            );
            if (dl.exitCode != 0 || !File(modelPath).existsSync()) {
              logger.error(
                "voice: model download failed (exit=${dl.exitCode}): "
                "${dl.stderr}",
              );
              return null;
            }
            logger.info("voice: model cached at $modelPath");
          }
          final outDir =
              Directory.systemTemp.createTempSync("horizon_whisper_");
          try {
            // whisper-cli expects 16 kHz mono WAV — Telegram voice
            // memos are OGG/Opus. Convert via ffmpeg first, since
            // the nixpkgs whisper-cpp build doesn't link ffmpeg in.
            final wavPath = "${outDir.path}/audio.wav";
            final convert = await Process.run("ffmpeg", [
              "-y",
              "-loglevel",
              "error",
              "-i",
              audioPath,
              "-ar",
              "16000",
              "-ac",
              "1",
              "-c:a",
              "pcm_s16le",
              wavPath,
            ]);
            if (convert.exitCode != 0 || !File(wavPath).existsSync()) {
              logger.warning(
                "ffmpeg exit=${convert.exitCode}: ${convert.stderr}",
              );
              return null;
            }
            // whisper-cli writes <out_prefix>.txt next to the prefix.
            final outPrefix = "${outDir.path}/transcript";
            final result = await Process.run("whisper-cli", [
              "-m",
              modelPath,
              "-f",
              wavPath,
              "--output-txt",
              "--output-file",
              outPrefix,
              "--language",
              "auto",
              "--no-prints",
            ]);
            if (result.exitCode != 0) {
              logger.warning(
                "whisper-cli exit=${result.exitCode}: ${result.stderr}",
              );
              return null;
            }
            // whisper-cli exits 0 even on unreadable audio, so the
            // absence of the output file (or an empty file) is the
            // signal that transcription actually produced nothing.
            final txt = File("$outPrefix.txt");
            if (!txt.existsSync()) {
              logger.warning(
                "whisper-cli produced no output file; "
                "stderr: ${result.stderr}",
              );
              return null;
            }
            final text = (await txt.readAsString()).trim();
            if (text.isEmpty) {
              logger.warning(
                "whisper-cli produced an empty transcription "
                "(audio may be silent or unintelligible)",
              );
              return null;
            }
            return text;
          } finally {
            try {
              outDir.deleteSync(recursive: true);
            } on FileSystemException {
              // Best-effort cleanup.
            }
          }
        });
}

/// End-to-end: download via Telegram + transcribe via Whisper.
/// Returns the transcription on success, null on failure. Audio is
/// kept under `_horizon/messages/voice/` for diagnosis either way.
class TranscribeTelegramVoice extends Fx<String?> {
  TranscribeTelegramVoice({
    required String token,
    required String fileId,
    required String vaultPath,
    required String eventId,
    required Logger logger,
  }) : super(() async {
          final audioPath = await DownloadTelegramVoice(
            token: token,
            fileId: fileId,
            vaultPath: vaultPath,
            eventId: eventId,
            logger: logger,
          );
          if (audioPath == null) {
            return null;
          }
          final text = await TranscribeWithWhisper(
            audioPath: audioPath,
            logger: logger,
          );
          if (text == null) {
            logger.warning(
              "voice: transcription failed for $eventId — keeping audio "
              "at $audioPath for diagnosis",
            );
          }
          return text;
        });
}
