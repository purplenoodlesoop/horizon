import "dart:async";
import "dart:io";

import "package:fn/fn.dart";
import "package:horizon/src/config/env_store.dart";
import "package:mark/mark.dart";

/// Polls the env file for mtime changes every 1s. On change, calls
/// `store.reload()` and invokes `onReload(diff)` if anything changed.
///
/// Polling rather than `FileSystemWatcher` because the latter is
/// flaky on macOS, on networked filesystems, and across editors that
/// rename-on-save (vim, sed -i). 1s polling is cheap (one stat per
/// tick) and the worst case — a token edit takes <2s to take effect —
/// is well below human reaction time on mobile.
class WatchEnvFile extends Fx<void> {
  WatchEnvFile({
    required EnvStore store,
    required Logger logger,
    void Function(EnvDiff diff)? onReload,
  }) : super(() async {
          final file = File(store.envFilePath);
          var lastMtime =
              file.existsSync() ? file.lastModifiedSync() : null;
          while (true) {
            await Future<void>.delayed(const Duration(seconds: 1));
            DateTime? currentMtime;
            try {
              currentMtime = file.existsSync() ? file.lastModifiedSync() : null;
            } on FileSystemException {
              continue;
            }
            if (currentMtime == lastMtime) {
              continue;
            }
            lastMtime = currentMtime;
            final diff = store.reload();
            if (diff == null) {
              continue;
            }
            logger.info(diff.summarize());
            onReload?.call(diff);
          }
        });
}
