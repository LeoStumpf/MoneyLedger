/// G48 rotating on-device snapshots — the pure policy (plain Dart): file
/// names, which snapshots to keep, when one is due.
library;

/// Daily snapshots kept (the newest ones).
const kSnapshotDailyKeep = 7;

/// Weekly snapshots kept beyond the daily ones: the newest snapshot of each
/// of the next older calendar weeks (Monday start).
const kSnapshotWeeklyKeep = 4;

String _two(int n) => n.toString().padLeft(2, '0');

/// The day key of [t] in local time: `YYYY-MM-DD`.
String snapshotDayKey(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-${_two(t.day)}';

/// The file name of the snapshot taken on [t]'s (local) day.
String snapshotFileName(DateTime t) => '${snapshotDayKey(t)}.json';

final _namePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})\.json$');

/// The day of snapshot file [name] (local midnight), or null for any other
/// file.
DateTime? parseSnapshotFileName(String name) {
  final m = _namePattern.firstMatch(name);
  if (m == null) return null;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  final t = DateTime(y, mo, d);
  // Reject impossible dates (DateTime would roll them over).
  if (t.year != y || t.month != mo || t.day != d) return null;
  return t;
}

DateTime _weekStart(DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  return d.subtract(Duration(days: d.weekday - DateTime.monday));
}

/// The snapshot days to keep out of [days]: the [daily] newest, plus the
/// newest one of each of the [weekly] next older calendar weeks that have
/// one (weeks already covered by a kept daily snapshot don't count). The
/// rest is deleted.
Set<DateTime> snapshotsToKeep(
  Iterable<DateTime> days, {
  int daily = kSnapshotDailyKeep,
  int weekly = kSnapshotWeeklyKeep,
}) {
  final sorted = days.toSet().toList()..sort((a, b) => b.compareTo(a));
  final keep = sorted.take(daily).toSet();
  final coveredWeeks = {for (final d in keep) _weekStart(d)};
  var weeks = 0;
  for (final d in sorted.skip(daily)) {
    if (weeks >= weekly) break;
    if (coveredWeeks.add(_weekStart(d))) {
      keep.add(d);
      weeks++;
    }
  }
  return keep;
}

/// Whether today's snapshot check is still to do: none ran on [now]'s day
/// ([lastDay] = the day key of the last check, null = never).
bool snapshotCheckDue(String? lastDay, DateTime now) =>
    lastDay != snapshotDayKey(now);
