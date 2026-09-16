import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import 'supabase_client.dart';

/// One entry in the Users filter.
class TeamUser {
  const TeamUser({required this.userId, required this.name, this.phone});

  final String userId;
  final String name;
  final String? phone;
}

/// The team behind the Users filter, the way the web app builds it.
///
/// A tenant admin's list is their own staff — `list_customers_for_admin()`,
/// which the database scopes to `profiles.created_by = auth.uid()`. A super
/// admin has no staff of their own; their list is the chat OWNERS (one per
/// WhatsApp number), which the caller derives from the loaded chats.
class TeamRepository {
  const TeamRepository();

  Future<List<TeamUser>> myStaff() async {
    try {
      final rows = await db.rpc<dynamic>(Db.listCustomersForAdminFn);
      if (rows is! List) return const <TeamUser>[];
      final out = <TeamUser>[];
      for (final row in rows.whereType<Map<String, dynamic>>()) {
        final id = row['user_id']?.toString();
        if (id == null || id.isEmpty) continue;
        final name = (row['full_name'] as String?)?.trim();
        final email = (row['email'] as String?)?.trim();
        out.add(TeamUser(
          userId: id,
          name: (name != null && name.isNotEmpty)
              ? name
              : (email != null && email.isNotEmpty)
                  ? email
                  : 'User ${id.substring(0, id.length.clamp(0, 8))}',
          phone: row['whatsapp_phone'] as String?,
        ));
      }
      out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return out;
    } on PostgrestException {
      return const <TeamUser>[];
    }
  }
}
