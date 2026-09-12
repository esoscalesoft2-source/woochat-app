import '../../core/formatting.dart';
import '../../models/message.dart';

/// Builds the thread's display list: messages oldest first, with a [DateTime]
/// day divider inserted before the first message of each day.
///
/// The sort is deliberate rather than trusting the query. A missing
/// `ascending:` on the Supabase order once returned the rows newest-first and
/// stood the whole conversation on its head, so the order is settled here.
List<Object> buildThreadItems(List<Message> messages) {
  final ordered = <Message>[...messages]..sort((a, b) {
      final at = a.createdAt;
      final bt = b.createdAt;
      // Messages with no timestamp sink to the top rather than jumping about.
      if (at == null && bt == null) return 0;
      if (at == null) return -1;
      if (bt == null) return 1;
      return at.compareTo(bt);
    });

  final items = <Object>[];
  DateTime? currentDay;

  for (final message in ordered) {
    final createdAt = message.createdAt;
    if (createdAt != null &&
        (currentDay == null || !TimeFormat.isSameDay(currentDay, createdAt))) {
      currentDay = createdAt;
      items.add(createdAt);
    }
    items.add(message);
  }
  return items;
}

/// True when the message at [index] opens a run from one side.
///
/// WhatsApp gives only the first bubble of a run its tail; the rest of the
/// run are plain rounded rectangles tucked underneath it. A day divider
/// breaks the run, so the first bubble under a date always keeps its tail.
bool startsRun(List<Object> items, int index) {
  if (index < 0 || index >= items.length) return false;

  final item = items[index];
  if (item is! Message) return false;
  if (index == 0) return true;

  final previous = items[index - 1];
  if (previous is! Message) return true;
  return previous.isOutbound != item.isOutbound;
}
