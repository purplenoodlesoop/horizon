import "dart:async";
import "dart:io";

import "package:fast_immutable_collections/fast_immutable_collections.dart";
import "package:fn/fn.dart";
import "package:glob/glob.dart";

import "package:horizon/src/capability/capability.dart";
import "package:horizon/src/event/event.dart";

var _nextId = 0;
String _generateVaultId() {
  _nextId++;
  return "vault_$_nextId";
}

/// Watches the vault tree for filesystem changes that match any
/// capability's `watch:` glob and emits one [Event] per match.
///
/// The glob set is frozen at construction time. Capability bodies
/// still hot-reload per event — only the SET of paths the watcher
/// cares about is fixed at startup. Adding or removing a `watch:`
/// glob requires a restart.
///
/// Loop prevention: a 1-second TTL per relative path dedups bursts
/// of create+modify events some filesystems emit, and guards against
/// rapid re-fires. There is no Horizon-write filter — capability
/// authors should keep `watch:` globs narrow and not write to files
/// that match their own globs.
///
/// Recovery after Horizon downtime: the watcher only sees live FS
/// events. Files written while Horizon was stopped are caught by
/// the existing `schedule:` heartbeat path (capability authors who
/// want a safety net should declare both `watch:` and `schedule:`).
class VaultWatchEvents extends StreamFx<Event> {
  VaultWatchEvents({
    required String vaultPath,
    required IList<Capability> capabilities,
  }) : super(() => _watch(vaultPath, capabilities));

  static Stream<Event> _watch(
    String vaultPath,
    IList<Capability> capabilities,
  ) {
    final patterns = <String>{
      for (final cap in capabilities) ...cap.watch,
    };
    if (patterns.isEmpty) {
      return const Stream.empty();
    }
    final globs = patterns.map((p) => Glob(p)).toList(growable: false);

    final recentFires = <String, DateTime>{};
    bool shouldFire(String relPath) {
      final now = DateTime.now();
      recentFires.removeWhere(
        (_, ts) => now.difference(ts) > const Duration(seconds: 1),
      );
      if (recentFires.containsKey(relPath)) {
        return false;
      }
      recentFires[relPath] = now;
      return true;
    }

    final dir = Directory(vaultPath);
    final prefix = "$vaultPath/";
    return dir.watch(recursive: true).where((fsEvent) {
      if (!fsEvent.path.startsWith(prefix)) {
        return false;
      }
      final relPath = fsEvent.path.substring(prefix.length);
      if (!globs.any((g) => g.matches(relPath))) {
        return false;
      }
      return shouldFire(relPath);
    }).map((fsEvent) {
      final relPath = fsEvent.path.substring(prefix.length);
      final eventType = switch (fsEvent.type) {
        FileSystemEvent.create => "create",
        FileSystemEvent.modify => "modify",
        FileSystemEvent.delete => "delete",
        FileSystemEvent.move => "move",
        _ => "unknown",
      };
      return Event(
        id: _generateVaultId(),
        content: "vault file $eventType: $relPath",
        channel: VaultChannel((path: relPath, eventType: eventType)),
        timestamp: DateTime.now(),
      );
    });
  }
}
