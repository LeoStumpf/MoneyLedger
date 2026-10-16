import 'expense_model.dart';

/// G49 — the day an expense happened (plain Dart, no Flutter / DB).
///
/// An expense's optional `date` is a **calendar day** as an ISO string
/// `YYYY-MM-DD`: no time and no time zone, so a back-dated dinner shows on
/// the same day on every member's device (a millisecond timestamp — even
/// "local noon" — lands on the previous / next day for a peer 12+ hours
/// away). It is only stored when it differs from the local day of
/// `created_at`; the **display date** is `date ?? created_at`.

/// Earliest accepted year of an expense date.
const kMinExpenseDateYear = 2000;

/// How far ahead the date picker goes (from today).
const kMaxExpenseDateAheadDays = 365;

/// How far ahead the content rules accept a date (a little more than the
/// picker, so a peer whose clock is a few days behind doesn't refuse it).
const kMaxExpenseDateAheadValidDays = 400;

final _isoDay = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// The day of [s] (`YYYY-MM-DD`) as local midnight, or null when [s] isn't a
/// well-formed, existing calendar day (e.g. `2026-02-30`).
DateTime? parseExpenseDate(String? s) {
  if (s == null) return null;
  final m = _isoDay.firstMatch(s);
  if (m == null) return null;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  final day = DateTime(y, mo, d);
  if (day.year != y || day.month != mo || day.day != d) return null;
  return day;
}

/// [d]'s local calendar day as `YYYY-MM-DD`.
String expenseDateOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Local midnight of [d]'s day.
DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// Why [date] isn't an acceptable expense date, or null when it is: not a
/// `YYYY-MM-DD` calendar day, before [kMinExpenseDateYear] or more than
/// [kMaxExpenseDateAheadValidDays] after [now]'s day.
String? expenseDateProblem(String date, {DateTime? now}) {
  final day = parseExpenseDate(date);
  if (day == null) return 'date "$date"';
  if (day.year < kMinExpenseDateYear) return 'date $date too early';
  final today = dayOf(now ?? DateTime.now());
  final last = DateTime(
    today.year,
    today.month,
    today.day + kMaxExpenseDateAheadValidDays,
  );
  if (day.isAfter(last)) return 'date $date too far ahead';
  return null;
}

/// The `date` to store for an expense created at [createdAtMs] that the
/// user dated [day]: null when [day] is [createdAtMs]'s local day (an
/// undated expense — the payload stays exactly as before G49), else its
/// ISO string.
String? storedExpenseDate(DateTime day, int createdAtMs) {
  final created = dayOf(DateTime.fromMillisecondsSinceEpoch(createdAtMs));
  final picked = dayOf(day);
  return picked == created ? null : expenseDateOf(picked);
}

extension ExpenseDisplayDate on ExpenseModel {
  /// Local midnight of the day the expense is shown under: its `date`, or
  /// the day of `created_at` (also for a malformed stored date).
  DateTime get displayDay =>
      parseExpenseDate(date) ??
      dayOf(DateTime.fromMillisecondsSinceEpoch(createdAt));
}
