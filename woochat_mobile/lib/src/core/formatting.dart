import 'package:intl/intl.dart';

/// Timestamp formatting shared by the chat list and the message bubbles.
class TimeFormat {
  const TimeFormat._();

  static final DateFormat _time = DateFormat.jm();
  static final DateFormat _weekday = DateFormat.E();
  static final DateFormat _date = DateFormat.yMd();
  static final DateFormat _dayHeader = DateFormat.yMMMMd();

  /// Compact stamp for a chat list row: time today, weekday this week, else date.
  static String listStamp(DateTime? value) {
    if (value == null) return '';
    final now = DateTime.now();
    final days = _dayDifference(now, value);
    if (days == 0) return _time.format(value);
    if (days == 1) return 'Yesterday';
    if (days < 7) return _weekday.format(value);
    return _date.format(value);
  }

  static String bubbleStamp(DateTime? value) =>
      value == null ? '' : _time.format(value);

  /// Header shown above the first message of each day.
  static String dayHeader(DateTime value) {
    final days = _dayDifference(DateTime.now(), value);
    if (days == 0) return 'Today';
    if (days == 1) return 'Yesterday';
    return _dayHeader.format(value);
  }

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static int _dayDifference(DateTime now, DateTime value) {
    final today = DateTime(now.year, now.month, now.day);
    final other = DateTime(value.year, value.month, value.day);
    return today.difference(other).inDays;
  }
}
