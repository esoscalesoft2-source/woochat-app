import '../core/constants.dart';
import 'supabase_client.dart';

/// The chat id buckets returned by the existing `scheduled_chat_ids()` RPC.
class ScheduledChatIds {
  const ScheduledChatIds({
    this.all = const <String>{},
    this.pending = const <String>{},
    this.failed = const <String>{},
    this.failedActive = const <String>{},
    this.failedCount = 0,
  });

  /// Every chat with a scheduled send.
  final Set<String> all;

  /// Scheduled sends still waiting to go out.
  final Set<String> pending;

  final Set<String> failed;
  final Set<String> failedActive;
  final int failedCount;

  static const ScheduledChatIds empty = ScheduledChatIds();

  bool get hasPending => pending.isNotEmpty;

  Set<String> bucket(ScheduleBucket bucket) => switch (bucket) {
        ScheduleBucket.all => all,
        ScheduleBucket.failed => failed,
        ScheduleBucket.failedActive => failedActive,
      };
}

/// Which slice of the scheduled chats the list is narrowed to.
enum ScheduleBucket { all, failed, failedActive }

/// Reads the existing `scheduled_chat_ids()` RPC.
///
/// The function is SECURITY DEFINER and already scopes to the caller's tenant
/// (an admin sees the workspace, an agent sees only their own or assigned
/// chats), so no extra filtering is applied here.
class SchedulesRepository {
  const SchedulesRepository();

  Future<ScheduledChatIds> fetchScheduledChatIds() async {
    final result = await db.rpc<dynamic>(Db.scheduledChatIdsFn);

    final map = switch (result) {
      final Map<String, dynamic> value => value,
      final List<dynamic> value when value.isNotEmpty =>
        value.first is Map<String, dynamic>
            ? value.first as Map<String, dynamic>
            : null,
      _ => null,
    };
    if (map == null) return ScheduledChatIds.empty;

    Set<String> ids(String key) {
      final value = map[key];
      if (value is List) {
        return value
            .where((id) => id != null)
            .map((id) => id.toString())
            .toSet();
      }
      return const <String>{};
    }

    return ScheduledChatIds(
      all: ids('all'),
      pending: ids('pending'),
      failed: ids('failed'),
      failedActive: ids('failed_active'),
      failedCount: (map['failed_count'] as num?)?.toInt() ?? 0,
    );
  }
}
