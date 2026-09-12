import '../../../models/chat.dart';

/// One owner appearing in the loaded chat list.
class ChatOwner {
  const ChatOwner({required this.userId, required this.label, required this.count});

  final String userId;
  final String label;
  final int count;
}

/// Groups the loaded chats by `chats.user_id`.
///
/// The owners are derived from the chats themselves rather than a separate
/// directory, so the list can never offer a team member whose conversations
/// are not actually here.
List<ChatOwner> ownersOf(
  List<Chat> chats, {
  required String signedInUserId,
  required String? signedInLabel,
}) {
  final counts = <String, int>{};
  for (final chat in chats) {
    counts[chat.userId] = (counts[chat.userId] ?? 0) + 1;
  }

  final owners = counts.entries
      .map((entry) => ChatOwner(
            userId: entry.key,
            label: entry.key == signedInUserId
                ? (signedInLabel ?? 'You')
                : 'User ${entry.key.substring(0, entry.key.length.clamp(0, 8))}',
            count: entry.value,
          ))
      .toList()
    ..sort((a, b) => b.count.compareTo(a.count));

  return owners;
}
