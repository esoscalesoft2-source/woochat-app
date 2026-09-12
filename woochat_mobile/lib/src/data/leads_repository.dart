import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import 'supabase_client.dart';

/// Raised when a chat could not be turned into a lead.
class LeadException implements Exception {
  const LeadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What "Convert to Lead" did.
enum LeadOutcome { created, alreadyExisted }

/// Writes a row into the existing `leads` table for a chat.
///
/// Only the columns that certainly exist are set — `status`, `source` and
/// `value` are left to their own database defaults rather than guessed at,
/// since they are constrained values this app has no business inventing.
class LeadsRepository {
  const LeadsRepository();

  /// True when this chat has already been converted.
  Future<bool> existsFor(String chatId) async {
    try {
      final row = await db
          .from(Db.leads)
          .select('id')
          .eq('chat_id', chatId)
          .limit(1)
          .maybeSingle();
      return row != null;
    } on PostgrestException catch (error) {
      throw LeadException('Could not check for an existing lead: '
          '${error.message}');
    }
  }

  /// Creates the lead, unless the chat already has one.
  Future<LeadOutcome> convert({
    required String chatId,
    required String ownerUserId,
    required String? contactName,
    required String? contactPhone,
    String? assignedTo,
  }) async {
    if (await existsFor(chatId)) return LeadOutcome.alreadyExisted;

    try {
      await db.from(Db.leads).insert(<String, dynamic>{
        'chat_id': chatId,
        'user_id': ownerUserId,
        'contact_name': contactName,
        'contact_phone': contactPhone,
        'assigned_to': ?assignedTo,
      });
      return LeadOutcome.created;
    } on PostgrestException catch (error) {
      throw LeadException('Could not create the lead: ${error.message}');
    }
  }
}
