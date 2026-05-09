/// Minimal 5-field cron expression parser.
///
/// Supported:
/// - `*` — any value
/// - integer — exact value
/// - `a-b` — inclusive range
/// - `a,b,c` — explicit list (any combination of integers and ranges)
///
/// Not supported (yet): step values (`*/5`), special expressions
/// (`@daily`, `@hourly`), named months/days (`Mon`, `Jan`). The
/// scheduler validates each Schedule's expression at load time;
/// invalid expressions are reported and the schedule is dropped from
/// the active set.
class CronExpression {
  CronExpression._({
    required this.minute,
    required this.hour,
    required this.dom,
    required this.month,
    required this.dow,
  });

  factory CronExpression.parse(String raw) {
    final parts = raw.trim().split(RegExp(r"\s+"));
    if (parts.length != 5) {
      throw FormatException(
        "Cron expression must have exactly 5 space-separated fields: $raw",
      );
    }
    return CronExpression._(
      minute: _parseField(parts[0], 0, 59, "minute"),
      hour: _parseField(parts[1], 0, 23, "hour"),
      dom: _parseField(parts[2], 1, 31, "day-of-month"),
      month: _parseField(parts[3], 1, 12, "month"),
      // Cron convention: 0=Sunday..6=Saturday (and 7=Sunday alias).
      // We normalize 7 -> 0 so dow set uses canonical 0..6.
      dow: _parseDow(parts[4]),
    );
  }

  final Set<int> minute;
  final Set<int> hour;
  final Set<int> dom;
  final Set<int> month;
  final Set<int> dow;

  /// Whether the given UTC time matches this cron expression.
  /// Matching is per-minute (the minute field is the smallest
  /// granularity).
  bool matches(DateTime utc) {
    final dowCanonical = utc.weekday == DateTime.sunday ? 0 : utc.weekday;
    return minute.contains(utc.minute) &&
        hour.contains(utc.hour) &&
        dom.contains(utc.day) &&
        month.contains(utc.month) &&
        dow.contains(dowCanonical);
  }

  /// Returns the smallest UTC `DateTime` strictly after `after` that
  /// matches this expression. Walks forward minute-by-minute up to a
  /// safety bound (one year) — enough for any sane cron.
  DateTime? nextFire(DateTime after) {
    var t = DateTime.utc(
      after.year,
      after.month,
      after.day,
      after.hour,
      after.minute,
    ).add(const Duration(minutes: 1));
    final limit = after.add(const Duration(days: 366));
    while (!t.isAfter(limit)) {
      if (matches(t)) {
        return t;
      }
      t = t.add(const Duration(minutes: 1));
    }
    return null;
  }
}

Set<int> _parseField(String field, int min, int max, String name) {
  if (field == "*") {
    return {for (var i = min; i <= max; i++) i};
  }
  final values = <int>{};
  for (final piece in field.split(",")) {
    if (piece.contains("-")) {
      final bounds = piece.split("-");
      if (bounds.length != 2) {
        throw FormatException("Bad range in $name field: $piece");
      }
      final lo = int.tryParse(bounds[0]);
      final hi = int.tryParse(bounds[1]);
      if (lo == null || hi == null || lo > hi || lo < min || hi > max) {
        throw FormatException("Out-of-range $name range: $piece");
      }
      for (var i = lo; i <= hi; i++) {
        values.add(i);
      }
    } else {
      final v = int.tryParse(piece);
      if (v == null || v < min || v > max) {
        throw FormatException("Out-of-range $name value: $piece");
      }
      values.add(v);
    }
  }
  return values;
}

Set<int> _parseDow(String field) {
  final raw = _parseField(field, 0, 7, "day-of-week");
  // Normalize 7 (Sunday alternate) to 0.
  return {for (final v in raw) v == 7 ? 0 : v};
}
