import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import '../models/chat_filters.dart';
import 'supabase_client.dart';

/// Raised when a note could not be written or linked.
class NotesException implements Exception {
  const NotesException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The note library and its links to contacts.
///
/// A note is one row in `notes`, shared across the workspace; putting it on
/// a customer is a `contact_notes` link row. The same note can sit on many
/// contacts, which is why detaching removes the link and never the note.
class NotesRepository {
  const NotesRepository();

  /// Puts an existing note on a contact.
  Future<void> attach({
    required String authUserId,
    required String contactId,
    required String noteId,
  }) async {
    try {
      await db.from(Db.contactNotes).insert(<String, dynamic>{
        'user_id': authUserId,
        'contact_id': contactId,
        'note_id': noteId,
      });
    } on PostgrestException catch (error) {
      // Already linked is the state being asked for.
      if (error.code == '23505') return;
      throw NotesException('Could not attach the note: ${error.message}');
    }
  }

  /// Takes a note off a contact. The note itself stays in the library.
  Future<void> detach({
    required String contactId,
    required String noteId,
  }) async {
    try {
      await db
          .from(Db.contactNotes)
          .delete()
          .eq('contact_id', contactId)
          .eq('note_id', noteId);
    } on PostgrestException catch (error) {
      throw NotesException('Could not detach the note: ${error.message}');
    }
  }

  /// Writes a new note and, when [contactId] is given, links it straight
  /// onto that contact — the two steps the web note editor takes.
  Future<Note> create({
    required String authUserId,
    required String text,
    List<String> tags = const <String>[],
    String? contactId,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) {
      throw const NotesException('Write something in the note first.');
    }

    final Map<String, dynamic> row;
    try {
      row = await db
          .from(Db.notes)
          .insert(<String, dynamic>{
            'user_id': authUserId,
            'note_text': clean,
            'tags': tags,
          })
          .select('id, note_text, tags, created_at')
          .single();
    } on PostgrestException catch (error) {
      throw NotesException('Could not save the note: ${error.message}');
    }

    final note = Note.fromMap(row);
    if (contactId != null) {
      await attach(
        authUserId: authUserId,
        contactId: contactId,
        noteId: note.id,
      );
    }
    return note;
  }
}
